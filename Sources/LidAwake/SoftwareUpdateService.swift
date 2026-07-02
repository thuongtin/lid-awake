import Combine
import Foundation
import Sparkle

struct SoftwareUpdateState: Equatable {
    var isConfigured: Bool
    var canCheckForUpdates: Bool
    var sessionInProgress: Bool
    var automaticallyChecksForUpdates: Bool
    var automaticallyDownloadsUpdates: Bool
    var allowsAutomaticUpdates: Bool
    var feedURL: String?
    var message: String

    static func unavailable(message: String, feedURL: String?) -> SoftwareUpdateState {
        SoftwareUpdateState(
            isConfigured: false,
            canCheckForUpdates: false,
            sessionInProgress: false,
            automaticallyChecksForUpdates: false,
            automaticallyDownloadsUpdates: false,
            allowsAutomaticUpdates: false,
            feedURL: feedURL,
            message: message
        )
    }
}

@MainActor
protocol SoftwareUpdateServicing: AnyObject {
    var state: SoftwareUpdateState { get }

    func setStateChangeHandler(_ handler: @escaping @MainActor () -> Void)
    func start()
    func checkForUpdates()
    func setAutomaticallyChecksForUpdates(_ enabled: Bool)
    func setAutomaticallyDownloadsUpdates(_ enabled: Bool)
}

@MainActor
final class SystemSoftwareUpdateService: NSObject, SoftwareUpdateServicing {
    private let bundle: Bundle
    private var updaterController: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []
    private var stateChangeHandler: (@MainActor () -> Void)?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        super.init()
    }

    var state: SoftwareUpdateState {
        guard configuration.isConfigured, let updater = updaterController?.updater else {
            return .unavailable(
                message: configuration.message,
                feedURL: configuration.feedURL
            )
        }

        return SoftwareUpdateState(
            isConfigured: true,
            canCheckForUpdates: updater.canCheckForUpdates,
            sessionInProgress: updater.sessionInProgress,
            automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
            automaticallyDownloadsUpdates: updater.automaticallyDownloadsUpdates,
            allowsAutomaticUpdates: updater.allowsAutomaticUpdates,
            feedURL: updater.feedURL?.absoluteString ?? configuration.feedURL,
            message: updater.sessionInProgress ? "Update check is running." : "Ready to check for signed updates."
        )
    }

    func setStateChangeHandler(_ handler: @escaping @MainActor () -> Void) {
        stateChangeHandler = handler
    }

    func start() {
        guard updaterController == nil else {
            notifyStateChanged()
            return
        }

        guard configuration.isConfigured else {
            notifyStateChanged()
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        observe(updater: controller.updater)
        notifyStateChanged()
    }

    func checkForUpdates() {
        guard let updaterController, updaterController.updater.canCheckForUpdates else {
            notifyStateChanged()
            return
        }

        updaterController.checkForUpdates(nil)
        notifyStateChanged()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else {
            notifyStateChanged()
            return
        }

        updater.automaticallyChecksForUpdates = enabled
        notifyStateChanged()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else {
            notifyStateChanged()
            return
        }

        updater.automaticallyDownloadsUpdates = enabled
        notifyStateChanged()
    }

    private var configuration: SoftwareUpdateConfiguration {
        SoftwareUpdateConfiguration(bundle: bundle)
    }

    private func observe(updater: SPUUpdater) {
        cancellables.removeAll()

        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.notifyStateChanged()
                }
            }
            .store(in: &cancellables)

        updater.publisher(for: \.sessionInProgress)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.notifyStateChanged()
                }
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.notifyStateChanged()
                }
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.notifyStateChanged()
                }
            }
            .store(in: &cancellables)
    }

    private func notifyStateChanged() {
        stateChangeHandler?()
    }
}

struct SoftwareUpdateConfiguration {
    let feedURL: String?
    let publicKey: String?

    init(bundle: Bundle) {
        self.feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        self.publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }

    init(feedURL: String?, publicKey: String?) {
        self.feedURL = feedURL
        self.publicKey = publicKey
    }

    var isConfigured: Bool {
        hasText(feedURL) && hasText(publicKey)
    }

    var message: String {
        if !hasText(feedURL), !hasText(publicKey) {
            return "This build does not include a Sparkle feed URL or update signing key."
        }

        if !hasText(feedURL) {
            return "This build does not include a Sparkle feed URL."
        }

        if !hasText(publicKey) {
            return "This build does not include a Sparkle update signing key."
        }

        return "Ready to check for signed updates."
    }

    private func hasText(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
