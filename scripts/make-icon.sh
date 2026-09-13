#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$ROOT/Resources/AppIcon.iconset"
OUTPUT="$ROOT/Resources/AppIcon.icns"
TMP_SWIFT="$(mktemp "${TMPDIR:-/tmp}/yiyi-icon.XXXXXX.swift")"
TMP_BINARY="${TMP_SWIFT%.swift}"
trap 'rm -f "$TMP_SWIFT" "$TMP_BINARY"; rm -rf "$ICONSET"' EXIT

mkdir -p "$ROOT/Resources"
rm -rf "$ICONSET" "$OUTPUT"
mkdir -p "$ICONSET"

cat > "$TMP_SWIFT" <<'SWIFT'
import CoreGraphics
import CoreText
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3,
      let pixelSize = Int(CommandLine.arguments[1]),
      pixelSize > 0 else {
    fputs("usage: make-icon-render <pixels> <output>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: pixelSize * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("could not create bitmap context\n", stderr)
    exit(1)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

let side = CGFloat(pixelSize)
let small = pixelSize <= 32
let inset = side * (100.0 / 1024.0)
let radius = side * (185.0 / 1024.0)
let tile = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)

context.clear(CGRect(x: 0, y: 0, width: side, height: side))

let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
// A restrained enamel finish. Small sizes use the same silhouette without fine detail.
context.saveGState()
if !small { context.setShadow(offset: CGSize(width: 0, height: -side * 0.008), blur: side * 0.022, color: color(0, 0.04, 0.10, 0.24)) }
context.addPath(tilePath)
context.setFillColor(color(0.12, 0.21, 0.34))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath); context.clip()
let finish = CGGradient(colorsSpace: colorSpace, colors: [color(0.12, 0.21, 0.34), color(0.26, 0.39, 0.55)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(finish, start: CGPoint(x: tile.midX, y: tile.minY), end: CGPoint(x: tile.midX, y: tile.maxY), options: [])
context.restoreGState()

if !small {
    context.saveGState()
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: side * 0.002, dy: side * 0.002), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setStrokeColor(color(0.90, 0.95, 1, 0.30))
    context.setLineWidth(side * 0.003)
    context.strokePath()
    context.restoreGState()
}
let mark = "译"
let baseFont = CTFontCreateUIFontForLanguage(.system, 1000, "zh-Hans" as CFString)!
let resolvedFont = CTFontCreateForString(baseFont, mark as CFString, CFRange(location: 0, length: 1))
let measuringFont = resolvedFont
var character = Array(mark.utf16)[0]
var glyphValue = CGGlyph()
guard CTFontGetGlyphsForCharacters(measuringFont, &character, &glyphValue, 1) else {
    fputs("could not resolve icon glyph\n", stderr)
    exit(1)
}

var measuredGlyph = glyphValue
var ink = CTFontGetBoundingRectsForGlyphs(
    measuringFont,
    .default,
    &measuredGlyph,
    nil,
    1
)
let targetScale: CGFloat
if small {
    targetScale = (tile.width * 0.72) / ink.width
} else {
    targetScale = (tile.width * 0.64) / ink.width
}
let font = CTFontCreateCopyWithAttributes(measuringFont, 1000 * targetScale, nil, nil)
ink = CTFontGetBoundingRectsForGlyphs(font, .default, &measuredGlyph, nil, 1)

var inkOrigin = CGPoint(
    x: tile.midX - ink.width / 2,
    y: tile.midY - ink.height / 2 + (small ? 0 : tile.height * 0.018)
)
if small {
    inkOrigin.x = round(inkOrigin.x)
    inkOrigin.y = round(inkOrigin.y)
}
let textPosition = CGPoint(
    x: inkOrigin.x - ink.origin.x,
    y: inkOrigin.y - ink.origin.y
)

context.setFillColor(color(0.97, 0.985, 1))
if !small { context.setShadow(offset: CGSize(width: 0, height: -side * 0.003), blur: side * 0.005, color: color(0.02, 0.07, 0.14, 0.25)) }
if small {
    context.setStrokeColor(color(0.97, 0.985, 1))
    context.setLineWidth(max(0.3, side * 0.014))
    context.setTextDrawingMode(.fillStroke)
}
context.setFont(CTFontCopyGraphicsFont(font, nil))
context.setFontSize(CTFontGetSize(font))
context.textMatrix = .identity
context.showGlyphs([glyphValue], at: [textPosition])

if pixelSize == 1024 {
    let finalInk = CGRect(origin: inkOrigin, size: ink.size)
    print(String(format: "tile rect: x=%.2f y=%.2f w=%.2f h=%.2f", tile.minX, tile.minY, tile.width, tile.height))
    print(String(format: "ink rect: x=%.2f y=%.2f w=%.2f h=%.2f", finalInk.minX, finalInk.minY, finalInk.width, finalInk.height))
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL,
          "public.png" as CFString,
          1,
          nil
      ) else {
    fputs("could not write PNG\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("could not finalize PNG\n", stderr)
    exit(1)
}
SWIFT

swiftc "$TMP_SWIFT" -o "$TMP_BINARY" \
    -framework CoreGraphics -framework CoreText -framework ImageIO

render() {
    local filename="$1"
    local pixels="$2"
    "$TMP_BINARY" "$pixels" "$ICONSET/$filename"
    echo "rendered $filename (${pixels}x${pixels})"
}

render icon_16x16.png 16
render icon_16x16@2x.png 32
render icon_32x32.png 32
render icon_32x32@2x.png 64
render icon_128x128.png 128
render icon_128x128@2x.png 256
render icon_256x256.png 256
render icon_256x256@2x.png 512
render icon_512x512.png 512
render icon_512x512@2x.png 1024

iconutil --convert icns --output "$OUTPUT" "$ICONSET"
echo "created $OUTPUT"
