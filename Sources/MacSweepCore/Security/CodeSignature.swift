import Foundation
import Security

public enum SignatureStatus: Sendable, Equatable {
    case apple
    case developer(teamID: String)
    /// Signed without an identity: normal for Homebrew and locally built tools, unusual for apps.
    case adHoc
    case unsigned
    case invalid
    case missing

    public var title: String {
        switch self {
        case .apple: "Apple"
        case .developer(let team): "Developer ID (\(team))"
        case .adHoc: "Ad-hoc signed"
        case .unsigned: "Unsigned"
        case .invalid: "Invalid signature"
        case .missing: "File missing"
        }
    }

    public var isTrusted: Bool {
        switch self {
        case .apple, .developer: true
        default: false
        }
    }
}

public enum CodeSignature {
    /// Static (on-disk) signature check via the Security framework. Fast; never executes the code.
    public static func check(path: String) -> SignatureStatus {
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode
        else { return .unsigned }

        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil)
        if validity == errSecCSUnsigned { return .unsigned }

        var appleRequirement: SecRequirement?
        if SecRequirementCreateWithString("anchor apple" as CFString, [], &appleRequirement) == errSecSuccess,
           let requirement = appleRequirement,
           SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess {
            return .apple
        }
        guard validity == errSecSuccess else { return .invalid }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any]
        else { return .adHoc }
        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return .developer(teamID: team)
        }
        return .adHoc
    }
}
