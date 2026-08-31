import CryptoKit
import Foundation
import Security
import YiyiCore

struct AccessibilityStatus {
    let trusted: Bool
    let superKeyTapStatus: String
    let signatureIdentity: String
    let advice: AccessibilityAdvice
}

@MainActor enum AccessibilityState {
    static let hasPromptedKey = "yiyi.accessibility.hasPrompted"
    static let grantedSignatureKey = "yiyi.accessibility.grantedSignature"
    static let repairAttemptedKey = "yiyi.accessibility.repairAttempted"

    static func currentSignature() -> String {
        guard let executableURL = Bundle.main.executableURL else { return "unavailable" }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &code) == errSecSuccess, let code else { return "unavailable" }
        var rawInfo: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &rawInfo) == errSecSuccess,
              let info = rawInfo as? [CFString: Any] else { return "unavailable" }

        let identifier = info[kSecCodeInfoIdentifier] as? String ?? Bundle.main.bundleIdentifier ?? "cc.blackblue.yiyi"
        if let certificates = info[kSecCodeInfoCertificates] as? [SecCertificate], let leaf = certificates.first {
            let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
            return "identity:\(identifier):\(digest.map { String(format: "%02x", $0) }.joined())"
        }
        if let unique = info[kSecCodeInfoUnique] as? Data {
            return "cdhash:\(unique.map { String(format: "%02x", $0) }.joined())"
        }
        return "identifier:\(identifier)"
    }

    static func observe(defaults: UserDefaults = .standard) -> (trusted: Bool, signature: String, advice: AccessibilityAdvice) {
        let trusted = SelectionCapture.isTrusted(prompt: false)
        let signature = currentSignature()
        if trusted {
            defaults.set(signature, forKey: grantedSignatureKey)
            defaults.removeObject(forKey: repairAttemptedKey)
        }
        let advice = accessibilityAdvice(
            trusted: trusted,
            hasPrompted: defaults.bool(forKey: hasPromptedKey),
            repairAttempted: defaults.bool(forKey: repairAttemptedKey),
            grantedSignature: defaults.string(forKey: grantedSignatureKey),
            currentSignature: signature
        )
        return (trusted, signature, advice)
    }

    static func requestSystemPrompt(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: hasPromptedKey)
        _ = SelectionCapture.isTrusted(prompt: true)
    }

    static func resetAccessibility(completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "cc.blackblue.yiyi"]
        process.terminationHandler = { process in
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(NSError(
                        domain: "cc.blackblue.yiyi.accessibility",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "tccutil could not reset yiyi's Accessibility entry."]
                    )))
                }
            }
        }
        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }

    static func shortSignature(_ signature: String) -> String {
        let parts = signature.split(separator: ":", maxSplits: 2).map(String.init)
        guard let digest = parts.last, digest.count > 12 else { return signature }
        return parts.dropLast().joined(separator: ":") + ":" + digest.prefix(12)
    }
}
