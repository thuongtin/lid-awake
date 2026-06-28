import Darwin
import Foundation
import Security

public struct CodeSigningInfo: Equatable, Sendable {
    public let signingIdentifier: String?
    public let bundleIdentifier: String?
    public let teamIdentifier: String?

    public init(signingIdentifier: String?, bundleIdentifier: String?, teamIdentifier: String?) {
        self.signingIdentifier = signingIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
    }
}

public protocol CodeSigningInfoProviding {
    func codeSigningInfo(forProcessID processID: pid_t) throws -> CodeSigningInfo
    func currentProcessCodeSigningInfo() throws -> CodeSigningInfo
}

public enum CodeSigningInfoError: Error, Equatable {
    case copyGuestFailed(OSStatus)
    case copyStaticCodeFailed(OSStatus)
    case copySigningInformationFailed(OSStatus)
    case signingInformationUnavailable
}

public struct HelperClientAuthorizer {
    private let allowedIdentifier: String
    private let allowedTeamIdentifier: String?
    private let provider: CodeSigningInfoProviding

    public init(
        allowedIdentifier: String = LidAwakeHelperConstants.clientBundleIdentifier,
        allowedTeamIdentifier: String? = nil,
        provider: CodeSigningInfoProviding = SecurityCodeSigningInfoProvider()
    ) {
        self.allowedIdentifier = allowedIdentifier
        self.allowedTeamIdentifier = allowedTeamIdentifier
        self.provider = provider
    }

    public func isAuthorized(processID: pid_t) -> Bool {
        guard let info = try? provider.codeSigningInfo(forProcessID: processID) else {
            return false
        }

        guard info.signingIdentifier == allowedIdentifier
            || info.bundleIdentifier == allowedIdentifier else {
            return false
        }

        guard
            let expectedTeamIdentifier = expectedTeamIdentifier(),
            !expectedTeamIdentifier.isEmpty,
            let clientTeamIdentifier = info.teamIdentifier,
            !clientTeamIdentifier.isEmpty
        else {
            return false
        }

        return clientTeamIdentifier == expectedTeamIdentifier
    }

    private func expectedTeamIdentifier() -> String? {
        if let allowedTeamIdentifier {
            return allowedTeamIdentifier
        }

        return try? provider.currentProcessCodeSigningInfo().teamIdentifier
    }
}

public struct SecurityCodeSigningInfoProvider: CodeSigningInfoProviding {
    public init() {}

    public func codeSigningInfo(forProcessID processID: pid_t) throws -> CodeSigningInfo {
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: processID)
        ] as CFDictionary

        var code: SecCode?
        let guestStatus = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
        guard guestStatus == errSecSuccess, let code else {
            throw CodeSigningInfoError.copyGuestFailed(guestStatus)
        }

        return try codeSigningInfo(from: code)
    }

    public func currentProcessCodeSigningInfo() throws -> CodeSigningInfo {
        var code: SecCode?
        let status = SecCodeCopySelf(SecCSFlags(), &code)
        guard status == errSecSuccess, let code else {
            throw CodeSigningInfoError.copyGuestFailed(status)
        }

        return try codeSigningInfo(from: code)
    }

    private func codeSigningInfo(from code: SecCode) throws -> CodeSigningInfo {
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw CodeSigningInfoError.copyStaticCodeFailed(staticStatus)
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSSigningInformation)),
            &information
        )
        guard infoStatus == errSecSuccess, let information else {
            throw CodeSigningInfoError.copySigningInformationFailed(infoStatus)
        }

        let dictionary = information as NSDictionary
        let signingIdentifier = dictionary[kSecCodeInfoIdentifier] as? String
        let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier] as? String
        let plist = dictionary[kSecCodeInfoPList] as? NSDictionary
        let bundleIdentifier = plist?["CFBundleIdentifier"] as? String

        return CodeSigningInfo(
            signingIdentifier: signingIdentifier,
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier
        )
    }
}
