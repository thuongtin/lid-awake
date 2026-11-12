import Foundation
import ServiceManagement

final class LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        default:
            .disabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        let current = SMAppService.mainApp.status
        if enabled {
            if current != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            // A registration still waiting for approval is undone as well, so
            // it cannot start the app at login once someone allows it later.
            if current == .enabled || current == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
