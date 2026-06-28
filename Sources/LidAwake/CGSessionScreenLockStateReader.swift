import LidAwakeCore
import CoreGraphics
import Foundation

final class CGSessionScreenLockStateReader: ScreenLockStateReading {
    func screenLockState() -> ScreenLockState {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return .unavailable
        }

        for key in ["CGSSessionScreenIsLocked", "kCGSSessionScreenIsLocked"] {
            if let value = session[key] as? Bool {
                return value ? .locked : .unlocked
            }
            if let value = session[key] as? NSNumber {
                return value.boolValue ? .locked : .unlocked
            }
        }

        return .unlocked
    }
}
