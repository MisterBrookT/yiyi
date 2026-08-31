#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_IDENTITY="yiyi Local Signing"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SIGNING_IDENTITY=""

warn_adhoc() {
  cat >&2 <<'EOF'
WARNING: yiyi could not create or use a stable signing identity.
The app will be ad-hoc signed, so macOS Accessibility permission must be re-granted after every reinstall.
EOF
  SIGNING_IDENTITY="-"
}

create_local_identity() {
  local temp_dir openssl_config p12_password
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/yiyi-signing.XXXXXX")"
  openssl_config="$temp_dir/certificate.conf"
  p12_password="$(openssl rand -hex 24)"

  cat > "$openssl_config" <<'EOF'
[req]
prompt = no
distinguished_name = subject
x509_extensions = extensions

[subject]
CN = yiyi Local Signing
O = yiyi

[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

  if ! openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
      -config "$openssl_config" -keyout "$temp_dir/key.pem" -out "$temp_dir/certificate.pem" >/dev/null 2>&1 ||
     ! openssl pkcs12 -export -legacy -name "$LOCAL_IDENTITY" \
      -inkey "$temp_dir/key.pem" -in "$temp_dir/certificate.pem" \
      -passout "pass:$p12_password" -out "$temp_dir/identity.p12" >/dev/null 2>&1 ||
     ! security import "$temp_dir/identity.p12" -k "$LOGIN_KEYCHAIN" \
      -P "$p12_password" -A -T /usr/bin/codesign >/dev/null 2>&1; then
    cat >&2 <<EOF
Could not import the local signing identity. If the login keychain is locked, run once:
  security unlock-keychain "$LOGIN_KEYCHAIN" && ./install.sh
EOF
    rm -rf "$temp_dir"
    return 1
  fi

  # `security import -A` grants codesign non-interactive access to the private key.
  rm -rf "$temp_dir"
}

resolve_signing_identity() {
  local line developer_identity=""

  if [[ -n "${YIYI_CODESIGN_IDENTITY:-}" ]]; then
    SIGNING_IDENTITY="$YIYI_CODESIGN_IDENTITY"
    echo "==> signing identity: $SIGNING_IDENTITY (YIYI_CODESIGN_IDENTITY)"
    return
  fi

  while IFS= read -r line; do
    if [[ "$line" =~ \"(Developer\ ID\ Application:[^\"]+)\" ]]; then
      developer_identity="${BASH_REMATCH[1]}"
      break
    fi
  done < <(security find-identity -v -p codesigning 2>/dev/null || true)
  if [[ -n "$developer_identity" ]]; then
    SIGNING_IDENTITY="$developer_identity"
    echo "==> signing identity: $SIGNING_IDENTITY (existing Developer ID Application)"
    return
  fi

  if security find-certificate -c "$LOCAL_IDENTITY" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    SIGNING_IDENTITY="$LOCAL_IDENTITY"
    echo "==> signing identity: $SIGNING_IDENTITY (existing local identity)"
    return
  fi

  echo "==> creating one-time local signing identity: $LOCAL_IDENTITY"
  if create_local_identity; then
    SIGNING_IDENTITY="$LOCAL_IDENTITY"
    echo "==> signing identity: $SIGNING_IDENTITY (new local identity)"
  else
    warn_adhoc
    echo "==> signing identity: - (ad-hoc fallback)"
  fi
}

cd "$ROOT"
resolve_signing_identity

echo "==> swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/yiyi"
DIST="$ROOT/dist"
APP="$DIST/yiyi.app"
STAGED_APP="$DIST/.yiyi.app.$$.staged"
rm -rf "$STAGED_APP"
trap 'rm -rf "$STAGED_APP"' EXIT
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN" "$STAGED_APP/Contents/MacOS/yiyi"
cp Info.plist "$STAGED_APP/Contents/Info.plist"
printf 'APPL????' > "$STAGED_APP/Contents/PkgInfo"
chmod +x "$STAGED_APP/Contents/MacOS/yiyi"
xattr -cr "$STAGED_APP"

if ! codesign --force --sign "$SIGNING_IDENTITY" --identifier cc.blackblue.yiyi "$STAGED_APP"; then
  if [[ "$SIGNING_IDENTITY" == "$LOCAL_IDENTITY" ]]; then
    warn_adhoc
    codesign --force --sign - --identifier cc.blackblue.yiyi "$STAGED_APP"
  else
    echo "ERROR: codesign failed with requested identity '$SIGNING_IDENTITY'." >&2
    exit 1
  fi
fi
codesign --verify --deep --strict "$STAGED_APP"
rm -rf "$APP.previous"
[[ ! -e "$APP" ]] || mv "$APP" "$APP.previous"
if ! mv "$STAGED_APP" "$APP"; then
  [[ ! -e "$APP.previous" ]] || mv "$APP.previous" "$APP"
  exit 1
fi
rm -rf "$APP.previous"
trap - EXIT
echo "==> done: $APP"
