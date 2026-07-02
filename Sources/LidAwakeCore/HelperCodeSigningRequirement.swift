import Foundation

public enum HelperCodeSigningRequirement {
    /// Builds a code signing requirement string that pins the XPC peer to the
    /// Lid Awake app identifier, an Apple-anchored certificate chain, and the
    /// helper's own Team ID. Returns nil when the helper build has no Team ID
    /// (ad-hoc signing), which matches HelperClientAuthorizer rejecting all
    /// clients in that configuration.
    public static func requirement(
        bundleIdentifier: String = LidAwakeHelperConstants.clientBundleIdentifier,
        teamIdentifier: String?
    ) -> String? {
        guard let teamIdentifier, !teamIdentifier.isEmpty else {
            return nil
        }
        guard isSafeRequirementAtom(bundleIdentifier), isSafeRequirementAtom(teamIdentifier) else {
            return nil
        }
        return "identifier \"\(bundleIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    private static func isSafeRequirementAtom(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
        }
    }
}
