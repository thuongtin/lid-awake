import Foundation
import Security

/// Whether the helper process that answers the app is the build this app
/// bundle ships.
///
/// Nothing else reports this. The helper never exits on its own and launchd
/// keeps the process it started, so after an update the previous build's
/// helper is still the one running. `SMAppService` reports `.enabled` either
/// way, the XPC contract carries no version, and an older helper accepts a
/// newer app signed by the same team, so every call still succeeds while the
/// fixes in the new helper are not running.
enum ClosedLidHelperBuildCheck: Equatable {
    /// The running helper is the one in this app bundle.
    case current
    /// The running helper was started from a different build.
    case outdated
    /// The comparison could not be made, so nothing may be concluded from it.
    case unknown
}

enum RunningHelperBuild {
    /// Compares the code the process is running with the helper at
    /// `bundledHelperURL` by code directory hash, which changes with every
    /// build and does not depend on where the running file is now.
    static func check(processIdentifier: pid_t, bundledHelperURL: URL) -> ClosedLidHelperBuildCheck {
        guard let requirement = requirement(matchingCodeAt: bundledHelperURL) else {
            return .unknown
        }

        var code: SecCode?
        let attributes = [kSecGuestAttributePid: processIdentifier] as CFDictionary
        let lookupStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard lookupStatus == errSecSuccess, let code else {
            return result(forFailedLookupStatus: lookupStatus)
        }

        return result(forValidityStatus: SecCodeCheckValidity(code, [], requirement))
    }

    /// The lookup needs the file the process was started from. An updater that
    /// moves the previous bundle aside and then deletes it, which is how
    /// Sparkle installs, leaves the old helper running with no file anywhere,
    /// and the bundled helper is on disk, so that process is not the bundled
    /// build's. A reinstall of the identical build done the same way lands
    /// here too and costs one replacement that changes nothing. A process
    /// that is gone, or any other failure, says nothing about the build.
    static func result(forFailedLookupStatus status: OSStatus) -> ClosedLidHelperBuildCheck {
        status == errSecErrnoBase + ENOENT ? .outdated : .unknown
    }

    /// An update that moved the previous bundle aside and kept it leaves the
    /// old helper valid but failing the requirement. One that deleted the
    /// previous bundle where it was leaves the old helper running code that
    /// differs from the file now at its path. Anything else says the check
    /// itself failed, not that the helper is old.
    static func result(forValidityStatus status: OSStatus) -> ClosedLidHelperBuildCheck {
        switch status {
        case errSecSuccess:
            .current
        case errSecCSReqFailed, errSecCSStaticCodeChanged:
            .outdated
        default:
            .unknown
        }
    }

    private static func requirement(matchingCodeAt url: URL) -> SecRequirement? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let codeDirectoryHash = (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
        else {
            return nil
        }

        let hex = codeDirectoryHash.map { String(format: "%02x", $0) }.joined()
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("cdhash H\"\(hex)\"" as CFString, [], &requirement) == errSecSuccess else {
            return nil
        }

        return requirement
    }
}
