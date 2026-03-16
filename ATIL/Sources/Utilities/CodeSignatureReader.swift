import Foundation
import Security

struct CodeSignatureReader: Sendable {
    func read(path: String) -> CodeSignatureInfo? {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            return CodeSignatureInfo(
                isSigned: false,
                signingIdentity: nil,
                teamIdentifier: nil,
                isAppleSigned: false,
                isNotarized: false,
                codeIdentifier: nil
            )
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        ) == errSecSuccess,
            let dict = info as? [String: Any]
        else {
            return CodeSignatureInfo(
                isSigned: true,
                signingIdentity: nil,
                teamIdentifier: nil,
                isAppleSigned: false,
                isNotarized: false,
                codeIdentifier: nil
            )
        }

        let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let signingIdentity: String? = {
            guard let certificate = certificates?.first else { return nil }
            var commonName: CFString?
            guard SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess else {
                return nil
            }
            return commonName as String?
        }()
        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let codeIdentifier = dict[kSecCodeInfoIdentifier as String] as? String
        let isApple = signingIdentity?.contains("Apple") == true || codeIdentifier?.hasPrefix("com.apple.") == true
        let isNotarized = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            nil
        ) == errSecSuccess

        return CodeSignatureInfo(
            isSigned: true,
            signingIdentity: signingIdentity,
            teamIdentifier: teamID,
            isAppleSigned: isApple,
            isNotarized: isNotarized,
            codeIdentifier: codeIdentifier
        )
    }
}
