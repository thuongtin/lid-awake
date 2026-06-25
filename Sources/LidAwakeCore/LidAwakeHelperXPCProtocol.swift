import Foundation

public enum LidAwakeHelperConstants {
    public static let clientBundleIdentifier = "com.thuongtin.LidAwake"
    public static let machServiceName = "com.thuongtin.LidAwake.Helper"
    public static let daemonPlistName = "com.thuongtin.LidAwake.Helper.plist"
}

@objc public protocol LidAwakeHelperXPCProtocol {
    func readClosedLidStatus(reply: @escaping (String) -> Void)
    func setClosedLidMode(enabled: Bool, reply: @escaping (Bool, String?) -> Void)
}
