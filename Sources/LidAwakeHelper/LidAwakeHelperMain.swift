import LidAwakeCore
import Foundation

final class HelperService: NSObject, NSXPCListenerDelegate, LidAwakeHelperXPCProtocol {
    private let pmsetService = PMSetService()
    private let clientAuthorizer = HelperClientAuthorizer()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let processID = connection.processIdentifier
        guard clientAuthorizer.isAuthorized(processID: processID) else {
            NSLog("Rejected helper XPC connection from PID \(processID)")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: LidAwakeHelperXPCProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func readClosedLidStatus(reply: @escaping (String) -> Void) {
        reply(pmsetService.readClosedLidStatus().displayText)
    }

    func setClosedLidMode(enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        do {
            try pmsetService.setClosedLidMode(enabled: enabled)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: LidAwakeHelperConstants.machServiceName)
listener.delegate = service
listener.resume()
RunLoop.current.run()
