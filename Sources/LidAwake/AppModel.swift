import LidAwakeCore
import AppKit
import Foundation
import OSLog

protocol UserSettingsStoring {
    func load() -> UserSettings
    func save(_ settings: UserSettings)
}

protocol BatteryMonitoring: AnyObject {
    func currentState() -> BatteryState
}

protocol LoginItemServicing: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

protocol ClosedLidStatusReading {
    func readClosedLidStatus() -> ClosedLidStatus
}

protocol ClosedLidHelperServicing: AnyObject {
    var status: ClosedLidHelperStatus { get }
    func register() throws
    func repairRegistration() throws
    func unregister() throws
    func setClosedLidMode(enabled: Bool, reply: @escaping (Result<Void, Error>) -> Void)
    func probeConnection(reply: @escaping (Result<Void, ClosedLidHelperFailure>) -> Void)
    func openApprovalSettings()
}

@MainActor
protocol NotificationServicing: AnyObject {
    func handleTransition(from oldStatus: WakeStatus, to newStatus: WakeStatus)
}

extension SettingsStore: UserSettingsStoring {}
extension SystemBatteryMonitor: BatteryMonitoring {}
extension LoginItemService: LoginItemServicing {}
extension PMSetService: ClosedLidStatusReading {}
extension ClosedLidHelperService: ClosedLidHelperServicing {}
extension SystemNotificationService: NotificationServicing {}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings: UserSettings
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var battery: BatteryState
    @Published private(set) var status: WakeStatus = .inactive
    @Published private(set) var softwareUpdateState = SoftwareUpdateState.unavailable(
        message: "Software updates are not configured for this build.",
        feedURL: nil
    )
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var closedLidStatus: ClosedLidStatus = .notReported
    @Published private(set) var closedLidHelperStatus: ClosedLidHelperStatus = .notRegistered
    /// Why closed-lid control is currently blocked, if it is.
    ///
    /// `closedLidHelperNeedsRepair` and any in-flight probe qualify *this*
    /// error, so neither may outlive it. Every consumer reads the pair: with a
    /// repair flag and no error there is no warning panel, no Repair button,
    /// and no code path that can clear the flag again, and a probe that lands
    /// after the error changed would retire a failure it never tested.
    @Published private(set) var closedLidError: String? {
        didSet {
            closedLidHelperProbeID = nil
            if closedLidError == nil {
                closedLidHelperNeedsRepair = false
            }
        }
    }
    @Published private(set) var closedLidDisplayError: String?
    @Published private(set) var closedLidLockError: String?
    @Published private(set) var screenLockAccessibilityTrusted = true
    @Published private(set) var isChangingClosedLidMode = false
    /// Set when the last helper call failed in a way that re-registering can fix.
    ///
    /// This cannot be derived from `closedLidHelperStatus`, because the failures
    /// it covers all leave the `SMAppService` record reporting `.enabled`. It is
    /// only ever true alongside a `closedLidError`, which `closedLidError`
    /// enforces on its own.
    @Published private(set) var closedLidHelperNeedsRepair = false

    private static let closedLidModeChangeTimeoutMessage = ClosedLidHelperFailure.timedOutMessage
    static let closedLidHelperBusyMessage = "Wait for the helper update to finish, then remove Lid Awake Helper."

    private let settingsStore: UserSettingsStoring
    private let closedLidOwnershipStore: ClosedLidOwnershipStoring
    private let batteryMonitor: BatteryMonitoring
    private let loginItemService: LoginItemServicing
    private let closedLidStatusReader: ClosedLidStatusReading
    private let closedLidHelperService: ClosedLidHelperServicing
    private let softwareUpdateService: SoftwareUpdateServicing
    private let screenLockPermissionChecker: ScreenLockPermissionChecking
    private let closedLidModeChangeTimeout: TimeInterval
    private let blockingWork: BlockingWorkPerforming
    /// How long a quit waits for the restore. It outlasts the helper's XPC
    /// deadline, so a reply that is coming is not cut off.
    private let terminationRestoreTimeout: TimeInterval
    private let logger = Logger(subsystem: "com.thuongtin.LidAwake", category: "app")
    private let powerController: PowerAssertionControlling
    private let clock: Clock
    private let coordinator: WakePolicyCoordinator
    private let closedLidDisplayCoordinator: ClosedLidDisplayCoordinator
    private let closedLidLockCoordinator: ClosedLidLockCoordinator
    private let notificationService: NotificationServicing
    private var previousStatus: WakeStatus = .inactive
    private var timer: Timer?
    private var closedLidSideEffectsTimer: Timer?
    private var closedLidOwnershipRecord: ClosedLidOwnershipRecord?
    private var suppressedClosedLidTarget: Bool?
    /// The `setClosedLidMode` request whose reply is still wanted.
    private struct ClosedLidModeChange {
        let id: UUID
        let enabled: Bool
    }
    private var pendingClosedLidModeChange: ClosedLidModeChange?
    /// Set while a requested helper removal has not gone through, so a removal
    /// that fails after closed-lid mode was restored does not get undone by the
    /// next evaluate turning it straight back on.
    private var closedLidHelperRemovalRequested = false
    /// Identifies the probe whose reply is still wanted. Nil means none is in
    /// flight, or the state it was testing has already moved on.
    private var closedLidHelperProbeID: UUID?
    private var lastClosedLidHelperProbeAt: Date?
    private let closedLidHelperProbeInterval: TimeInterval = 30
    private var lastClosedLidVerifiedAt: Date?
    /// Set while the status read behind `reconcileClosedLidMode` is out, so a
    /// slow `pmset` does not get another read stacked behind it every tick.
    private var isReadingClosedLidStatus = false
    /// Set once the app started quitting, so nothing turns closed-lid mode
    /// back on after the restore that runs on the way out.
    private var isTerminating = false
    private var didPromptForScreenLockAccessibility = false
    private let closedLidVerifyInterval: TimeInterval = 30

    private var appEnabledClosedLidMode: Bool {
        closedLidOwnershipRecord?.ownedByThisApp == true
    }

    convenience init() {
        let powerController = PowerAssertionManager(creator: IOKitPowerAssertionCreator())
        let displaySleeper = PMSetDisplaySleepService()
        let screenLocker = SystemScreenLockService()
        self.init(
            settingsStore: SettingsStore(),
            closedLidOwnershipStore: UserDefaultsClosedLidOwnershipStore(),
            batteryMonitor: SystemBatteryMonitor(),
            loginItemService: LoginItemService(),
            closedLidStatusReader: PMSetService(),
            closedLidHelperService: ClosedLidHelperService(),
            softwareUpdateService: SystemSoftwareUpdateService(activationPolicyController: .shared),
            screenLockPermissionChecker: SystemScreenLockPermissionChecker(),
            powerController: powerController,
            clock: SystemClock(),
            closedLidDisplayCoordinator: ClosedLidDisplayCoordinator(
                clamshellStateReader: IOKitClamshellStateReader(),
                displaySleeper: displaySleeper,
                screenLockStateReader: CGSessionScreenLockStateReader()
            ),
            closedLidLockCoordinator: ClosedLidLockCoordinator(
                clamshellStateReader: IOKitClamshellStateReader(),
                deviceLocker: screenLocker
            ),
            notificationService: SystemNotificationService(),
            initialBattery: BatteryState.desktopOrUnknown(
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        )
        displaySleeper.failureHandler = { [weak self] message in
            self?.reportClosedLidDisplayFailure(message)
        }
        screenLocker.failureHandler = { [weak self] message in
            self?.reportClosedLidLockFailure(message)
        }
    }

    init(
        settingsStore: UserSettingsStoring,
        closedLidOwnershipStore: ClosedLidOwnershipStoring,
        batteryMonitor: BatteryMonitoring,
        loginItemService: LoginItemServicing,
        closedLidStatusReader: ClosedLidStatusReading,
        closedLidHelperService: ClosedLidHelperServicing,
        softwareUpdateService: SoftwareUpdateServicing,
        screenLockPermissionChecker: ScreenLockPermissionChecking,
        powerController: PowerAssertionControlling,
        clock: Clock,
        closedLidDisplayCoordinator: ClosedLidDisplayCoordinator,
        closedLidLockCoordinator: ClosedLidLockCoordinator,
        notificationService: NotificationServicing,
        initialBattery: BatteryState,
        closedLidModeChangeTimeout: TimeInterval = 6,
        blockingWork: BlockingWorkPerforming = BackgroundBlockingWork(),
        terminationRestoreTimeout: TimeInterval = 5
    ) {
        self.settingsStore = settingsStore
        self.closedLidOwnershipStore = closedLidOwnershipStore
        self.batteryMonitor = batteryMonitor
        self.loginItemService = loginItemService
        self.closedLidStatusReader = closedLidStatusReader
        self.closedLidHelperService = closedLidHelperService
        self.softwareUpdateService = softwareUpdateService
        self.screenLockPermissionChecker = screenLockPermissionChecker
        self.closedLidModeChangeTimeout = closedLidModeChangeTimeout
        self.blockingWork = blockingWork
        self.terminationRestoreTimeout = terminationRestoreTimeout
        self.powerController = powerController
        self.clock = clock
        self.coordinator = WakePolicyCoordinator(
            powerController: powerController,
            clock: clock
        )
        self.closedLidDisplayCoordinator = closedLidDisplayCoordinator
        self.closedLidLockCoordinator = closedLidLockCoordinator
        self.notificationService = notificationService
        self.settings = settingsStore.load()
        self.battery = initialBattery
        self.softwareUpdateService.setStateChangeHandler { [weak self] in
            self?.syncSoftwareUpdateState()
        }
        self.softwareUpdateState = softwareUpdateService.state
    }

    func start(scheduleTimers: Bool = true) {
        logger.info("Lid Awake model start")
        softwareUpdateService.start()
        syncSoftwareUpdateState()
        loadClosedLidOwnershipRecord()
        syncLaunchAtLoginStatus()
        syncClosedLidHelperStatus()
        evaluate(forceClosedLidStatusRead: true)
        requestScreenLockAccessibilityPermissionIfNeeded()
        guard scheduleTimers else {
            return
        }

        // Common modes, so the timers keep running while a modal alert or a
        // tracking menu spins the run loop in a mode of its own. The callbacks
        // run in place rather than through a main-actor task, which would wait
        // on the main queue, and a modal loop started from a main-queue block
        // does not drain it.
        timer?.invalidate()
        let evaluateTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        }
        // Give the kernel slack to coalesce these periodic wakeups with other
        // timers so a long-lived background process does not defeat App Nap.
        evaluateTimer.tolerance = 1
        RunLoop.main.add(evaluateTimer, forMode: .common)
        timer = evaluateTimer

        closedLidSideEffectsTimer?.invalidate()
        let sideEffectsTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcileClosedLidSideEffects()
            }
        }
        sideEffectsTimer.tolerance = 0.5
        RunLoop.main.add(sideEffectsTimer, forMode: .common)
        closedLidSideEffectsTimer = sideEffectsTimer
    }

    var shouldShowClosedLidPermissionPrompt: Bool {
        closedLidHelperStatus.needsPermissionPrompt
    }

    var closedLidControlNeedsAttention: Bool {
        closedLidHelperStatus.needsPermissionPrompt || closedLidError != nil
    }

    var screenLockPermissionNeedsAttention: Bool {
        settings.enabled
            && settings.lockScreenWhenLidCloses
            && screenLockPermissionChecker.requiresAccessibilityPermission
            && !screenLockAccessibilityTrusted
    }

    var screenLockPermissionIsRelevant: Bool {
        settings.lockScreenWhenLidCloses
            && screenLockPermissionChecker.requiresAccessibilityPermission
    }

    var screenLockPermissionStatusText: String {
        guard screenLockPermissionChecker.requiresAccessibilityPermission else {
            return "Not needed"
        }

        return screenLockAccessibilityTrusted ? "Allowed" : "Needs approval"
    }

    var screenLockPermissionTitle: String {
        "Accessibility Is Not Trusted For This Build"
    }

    var screenLockPermissionMessage: String {
        "Lock-on-close uses the main Lid Awake app to send the system Lock Screen shortcut. If Lid Awake already appears allowed, remove that old entry and add the current app again."
    }

    var screenLockPermissionCompactMessage: String {
        "If Lid Awake already appears allowed, remove it and add the current app again."
    }

    var closedLidAttentionTitle: String {
        if shouldOfferClosedLidHelperRepair {
            return "Repair Advanced Helper"
        }

        if closedLidError != nil {
            return "Closed-lid playback is blocked"
        }

        return switch closedLidHelperStatus {
        case .enabled:
            "Closed-lid control is ready"
        case .requiresApproval:
            "Approve Advanced Helper"
        case .notRegistered:
            "Set up Advanced Helper"
        case .notFound:
            "Advanced Helper is missing"
        case .unavailable:
            "Advanced Helper is unavailable"
        }
    }

    var closedLidAttentionMessage: String {
        if let closedLidError {
            return closedLidError
        }

        return switch closedLidHelperStatus {
        case .enabled:
            "Lid Awake can control closed-lid mode."
        case .requiresApproval:
            "Lid Awake Helper is installed but still needs approval in System Settings. Closed-lid playback will not work until this is approved."
        case .notRegistered:
            "Lid Awake needs an approved helper before it can keep audio and work running after the lid closes."
        case .notFound:
            "macOS cannot find the bundled helper for this app build. Closed-lid playback will not work until the helper is available and approved."
        case let .unavailable(message):
            "Closed-lid playback is blocked because the helper is unavailable: \(message)"
        }
    }

    var closedLidMenuAttentionMessage: String {
        // The popover clamps this to two lines, so the one message long enough
        // to be cut off there is swapped for a short version that still names
        // the remedy. Settings renders `closedLidAttentionMessage` in full.
        // Matching the exact text keeps this a substitution for that message
        // alone, so no other failure reason can be hidden behind it.
        if closedLidError == ClosedLidHelperFailure.connectionLostMessage {
            return ClosedLidHelperFailure.connectionLostCompactMessage
        }

        if let closedLidError {
            return closedLidError
        }

        return switch closedLidHelperStatus {
        case .enabled:
            "Closed-lid control is ready."
        case .requiresApproval:
            "Approve the helper in System Settings before closing the lid."
        case .notRegistered:
            "Set up the helper before using closed-lid playback."
        case .notFound:
            "This build cannot find LidAwakeHelper."
        case .unavailable:
            "Helper is unavailable. Closed-lid playback is blocked."
        }
    }

    var closedLidCompactActionTitle: String {
        if shouldOfferClosedLidHelperRepair {
            return "Repair"
        }

        return switch closedLidHelperStatus {
        case .requiresApproval:
            "Approve"
        case .enabled, .notRegistered, .notFound, .unavailable(_):
            "Set Up"
        }
    }

    var closedLidPrimaryActionTitle: String {
        if shouldOfferClosedLidHelperRepair {
            return "Repair Helper"
        }

        return switch closedLidHelperStatus {
        case .requiresApproval:
            "Open System Settings"
        case .enabled, .notRegistered, .notFound, .unavailable(_):
            "Set Up Helper"
        }
    }

    var shouldOfferClosedLidHelperRepair: Bool {
        closedLidHelperStatus == .enabled
            && closedLidHelperNeedsRepair
            && closedLidError != nil
    }

    func refreshClosedLidPermissionState() {
        syncClosedLidHelperStatus()
        reconcileClosedLidMode(forceStatusRead: true)
    }

    func refreshAfterExternalPermissionChange() {
        syncClosedLidHelperStatus()
        // `evaluate` refreshes the Accessibility state on its way through.
        evaluate(forceClosedLidStatusRead: true)
        // The user just opened a window to look at this, so answer now rather
        // than on the next interval.
        probeClosedLidHelperIfBlocked(force: true)
    }

    /// Retires a connection failure once the helper answers again.
    ///
    /// Refreshing `closedLidHelperStatus` cannot do this on its own: every
    /// failure that sets `closedLidHelperNeedsRepair` leaves the `SMAppService`
    /// record reporting `.enabled`, so the warning would otherwise stay on
    /// screen for the rest of the app's life even after the user repaired the
    /// helper, reinstalled the app, or restarted the Mac. Asking the helper
    /// directly is the only thing that can tell the two states apart.
    private func probeClosedLidHelperIfBlocked(force: Bool = false) {
        guard closedLidHelperNeedsRepair,
              closedLidHelperStatus == .enabled,
              closedLidError != nil,
              !isChangingClosedLidMode,
              closedLidHelperProbeID == nil
        else {
            return
        }

        // Recovery can come from outside the app, so this also runs on the
        // regular evaluate tick, which is far more often than the helper needs
        // to be asked.
        let now = clock.now
        if !force,
           let lastClosedLidHelperProbeAt,
           now.timeIntervalSince(lastClosedLidHelperProbeAt) < closedLidHelperProbeInterval {
            return
        }

        let probeID = UUID()
        closedLidHelperProbeID = probeID
        lastClosedLidHelperProbeAt = now
        closedLidHelperService.probeConnection { [weak self] result in
            DispatchQueue.main.async {
                self?.finishClosedLidHelperProbe(probeID: probeID, result: result)
            }
        }
    }

    private func finishClosedLidHelperProbe(probeID: UUID, result: Result<Void, ClosedLidHelperFailure>) {
        // Anything that rewrote `closedLidError` while this was in flight
        // retired the probe along with it, because succeeding here would
        // otherwise clear a failure this probe never tested.
        guard closedLidHelperProbeID == probeID else {
            return
        }

        closedLidHelperProbeID = nil

        guard case .success = result else {
            return
        }

        logger.info("closed-lid helper reachable again, clearing repair prompt")
        closedLidError = nil
        suppressedClosedLidTarget = nil
        evaluate()
    }

    /// Whether re-registering the helper is the action that can clear a failure.
    private func isRepairableClosedLidFailure(_ error: Error) -> Bool {
        (error as? ClosedLidHelperFailure)?.isRecoverableByRepair ?? false
    }

    func stop() {
        logger.info("Lid Awake model stop")
        timer?.invalidate()
        timer = nil
        closedLidSideEffectsTimer?.invalidate()
        closedLidSideEffectsTimer = nil
        powerController.release()
    }

    /// Stops the model and restores closed-lid mode on the way out, without
    /// holding the main thread while the helper answers.
    ///
    /// `completion` runs once: when the restore settles, or after
    /// `terminationRestoreTimeout`, whichever comes first. A restore still out
    /// when the app exits keeps its ownership record for the next launch, and
    /// the helper restores on its own once it sees this process exit.
    func prepareForTermination(completion: @escaping @MainActor () -> Void) {
        stop()
        isTerminating = true

        var didComplete = false
        let complete: @MainActor () -> Void = {
            guard !didComplete else {
                return
            }
            didComplete = true
            completion()
        }

        guard appEnabledClosedLidMode else {
            complete()
            return
        }

        syncClosedLidHelperStatus()

        // Restoring a mode that is already off is harmless, while reading
        // `pmset` first would spend part of the quit on a process that can
        // stall. Assuming it is on also covers an enable still in flight,
        // which can land after any read.
        switch ClosedLidOwnershipReducer.restoreAction(
            record: closedLidOwnershipRecord,
            desiredClosedLidMode: false,
            currentStatus: .enabled,
            helperCanControlClosedLidMode: closedLidHelperStatus.canControlClosedLidMode,
            attemptedAt: Date()
        ) {
        case .none:
            complete()
            return
        case .clearRecord:
            saveClosedLidOwnershipRecord(nil)
            suppressedClosedLidTarget = nil
            closedLidError = nil
            complete()
            return
        case let .blockedByHelper(record):
            saveClosedLidOwnershipRecord(record)
            suppressedClosedLidTarget = false
            closedLidError = "Advanced Helper is not ready, so closed-lid mode could not be restored."
            complete()
            return
        case let .restore(record):
            saveClosedLidOwnershipRecord(record)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + terminationRestoreTimeout) { [weak self] in
            self?.logger.error("closed-lid restore did not finish before quitting")
            complete()
        }

        closedLidHelperService.setClosedLidMode(enabled: false) { [weak self] result in
            DispatchQueue.main.async {
                self?.finishTerminationRestore(result: result)
                complete()
            }
        }
    }

    private func finishTerminationRestore(result: Result<Void, Error>) {
        let errorMessage: String?
        if case let .failure(error) = result {
            errorMessage = error.localizedDescription
        } else {
            errorMessage = nil
        }

        switch ClosedLidOwnershipReducer.restoreCompletion(didComplete: true, errorMessage: errorMessage) {
        case .clearRecord:
            saveClosedLidOwnershipRecord(nil)
            suppressedClosedLidTarget = nil
            closedLidError = nil
        case let .keepRecord(message):
            closedLidError = message
        }
    }

    func updateSettings(_ update: (inout UserSettings) -> Void) {
        var nextSettings = settings
        update(&nextSettings)
        // A scheduled stop belongs to the run it was set for. Kept across an
        // off and on, a deadline that passed in between would turn the app
        // straight back off.
        if !nextSettings.enabled {
            nextSettings.stopAt = nil
        }
        settings = nextSettings
        settingsStore.save(nextSettings)
        evaluate()
        requestScreenLockAccessibilityPermissionIfNeeded()
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemService.setEnabled(enabled)
            launchAtLoginError = nil
            updateSettings { settings in
                settings.launchAtLogin = loginItemService.isEnabled
            }
        } catch {
            launchAtLoginError = error.localizedDescription
            syncLaunchAtLoginStatus()
        }
    }

    func checkForSoftwareUpdates() {
        softwareUpdateService.checkForUpdates()
        syncSoftwareUpdateState()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        softwareUpdateService.setAutomaticallyChecksForUpdates(enabled)
        syncSoftwareUpdateState()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        softwareUpdateService.setAutomaticallyDownloadsUpdates(enabled)
        syncSoftwareUpdateState()
    }

    func updateLidClosedDisplayMode(_ mode: LidClosedDisplayMode) {
        suppressedClosedLidTarget = nil
        closedLidHelperRemovalRequested = false
        updateSettings { settings in
            settings.lidClosedDisplayMode = mode
            if mode == .keepDisplayOn {
                settings.preventDisplaySleep = true
            }
        }
    }

    func setupClosedLidHelper() {
        if shouldOfferClosedLidHelperRepair {
            repairClosedLidHelper()
            return
        }

        closedLidHelperRemovalRequested = false
        do {
            try closedLidHelperService.register()
            syncClosedLidHelperStatus()
            switch closedLidHelperStatus {
            case .enabled:
                closedLidError = nil
                evaluate()
            case .requiresApproval:
                closedLidError = "Approve Lid Awake Helper in System Settings, then return here."
                closedLidHelperService.openApprovalSettings()
            case .notRegistered:
                closedLidError = "Helper is not registered yet."
            case .notFound:
                closedLidError = "Helper is missing from the app bundle."
            case let .unavailable(message):
                closedLidError = message
            }
        } catch {
            syncClosedLidHelperStatus()
            closedLidError = closedLidSetupError(from: error)
        }
    }

    func repairClosedLidHelper() {
        isChangingClosedLidMode = false
        pendingClosedLidModeChange = nil
        closedLidHelperRemovalRequested = false

        do {
            try closedLidHelperService.repairRegistration()
            syncClosedLidHelperStatus()
            suppressedClosedLidTarget = nil
            closedLidHelperNeedsRepair = false
            switch closedLidHelperStatus {
            case .enabled:
                closedLidError = nil
                evaluate()
            case .requiresApproval:
                closedLidError = "Approve Lid Awake Helper in System Settings, then return here."
                closedLidHelperService.openApprovalSettings()
            case .notRegistered:
                closedLidError = "Helper is not registered yet."
            case .notFound:
                closedLidError = "Helper is missing from the app bundle."
            case let .unavailable(message):
                closedLidError = message
            }
        } catch {
            syncClosedLidHelperStatus()
            // Repair is only ever entered while it is already the offered
            // action, and a failure leaves that unchanged, so the flag is
            // deliberately left alone here: Set Up would return early while the
            // stale registration still reports as enabled.
            closedLidError = "Repairing Lid Awake Helper failed: \(closedLidSetupError(from: error))"
        }
    }

    func performClosedLidHelperAction() {
        if shouldOfferClosedLidHelperRepair {
            repairClosedLidHelper()
            return
        }

        setupClosedLidHelper()
    }

    func requestClosedLidPermission() {
        performClosedLidHelperAction()
    }

    func openClosedLidApprovalSettings() {
        closedLidHelperService.openApprovalSettings()
    }

    func openScreenLockAccessibilitySettings() {
        refreshScreenLockAccessibilityState(prompt: true)
        screenLockPermissionChecker.openAccessibilitySettings()
    }

    func removeClosedLidHelper() {
        // An enable still in flight can land after the status read below, and
        // removing the helper then would leave closed-lid mode on with no way
        // to restore it.
        guard !isChangingClosedLidMode else {
            closedLidError = Self.closedLidHelperBusyMessage
            return
        }

        closedLidHelperRemovalRequested = true
        syncClosedLidHelperStatus()

        // Held across the status read as well, so nothing starts a change
        // underneath the removal while `pmset` answers.
        isChangingClosedLidMode = true
        readClosedLidStatus { [weak self] status in
            guard let self else {
                return
            }

            isChangingClosedLidMode = false
            continueRemovingClosedLidHelper(status: status)
        }
    }

    private func continueRemovingClosedLidHelper(status: ClosedLidStatus) {
        // Only a status `pmset` actually reported as disabled proves there is
        // nothing to restore.
        if appEnabledClosedLidMode, status != .disabled {
            restoreClosedLidModeBeforeRemovingHelper()
            return
        }

        if appEnabledClosedLidMode {
            saveClosedLidOwnershipRecord(nil)
        }

        unregisterClosedLidHelper()
    }

    private func restoreClosedLidModeBeforeRemovingHelper() {
        guard closedLidHelperStatus.canControlClosedLidMode else {
            closedLidError = "Closed-lid mode must be restored before removing the helper, but Advanced Helper is not ready."
            return
        }

        isChangingClosedLidMode = true
        closedLidError = nil

        closedLidHelperService.setClosedLidMode(enabled: false) { [weak self] result in
            DispatchQueue.main.async {
                self?.finishClosedLidRestoreBeforeHelperRemoval(result: result)
            }
        }
    }

    private func finishClosedLidRestoreBeforeHelperRemoval(result: Result<Void, Error>) {
        readClosedLidStatus { [weak self] _ in
            guard let self else {
                return
            }

            isChangingClosedLidMode = false
            continueRemovingClosedLidHelperAfterRestore(result: result)
        }
    }

    private func continueRemovingClosedLidHelperAfterRestore(result: Result<Void, Error>) {
        switch result {
        case .success:
            guard closedLidStatus != .enabled else {
                closedLidError = "Closed-lid mode is still enabled, so Lid Awake Helper was not removed."
                return
            }

            saveClosedLidOwnershipRecord(nil)
            suppressedClosedLidTarget = nil
            unregisterClosedLidHelper()
        case let .failure(error):
            closedLidError = "Could not restore closed-lid mode before removing helper: \(closedLidUserFacingError(from: error))"
            // An unreachable helper cannot restore closed-lid mode, so it also
            // cannot be removed cleanly. Repair is the way out of that, and it
            // has to be offered here too.
            closedLidHelperNeedsRepair = isRepairableClosedLidFailure(error)
        }
    }

    private func unregisterClosedLidHelper() {
        do {
            try closedLidHelperService.unregister()
            closedLidHelperRemovalRequested = false
            syncClosedLidHelperStatus()
            closedLidError = nil
        } catch {
            syncClosedLidHelperStatus()
            closedLidError = closedLidRemovalError(from: error)
        }
    }

    /// Keeps the Mac awake for `interval`, turning Keep Awake on if it was off.
    func scheduleStop(for interval: TimeInterval) {
        updateSettings { settings in
            settings.enabled = true
            settings.stopAt = clock.now.addingTimeInterval(interval)
        }
    }

    func clearScheduledStop() {
        updateSettings { settings in
            settings.stopAt = nil
        }
    }

    /// `AppDelegate` stops the model and restores closed-lid mode while
    /// AppKit waits on `applicationShouldTerminate`.
    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func evaluate(forceClosedLidStatusRead: Bool = false) {
        logger.debug("evaluate begin")
        let now = clock.now
        stopWhenDeadlineIsReached(now: now)
        let nextBattery = batteryMonitor.currentState()
        if battery != nextBattery {
            battery = nextBattery
        }
        logger.debug("evaluate battery complete")
        let nextSessions = manualHoldSessions(now: now)
        if sessions.map(\.id) != nextSessions.map(\.id) {
            sessions = nextSessions
        }
        previousStatus = status
        let nextStatus = coordinator.update(settings: settings, sessions: nextSessions, battery: nextBattery)
        if status != nextStatus {
            status = nextStatus
        }
        if status != previousStatus {
            logger.info(
                "status changed enabled=\(self.settings.enabled) sessions=\(self.sessions.count) batteryPercent=\(self.battery.percent ?? -1) ac=\(self.battery.isOnACPower) charging=\(self.battery.isCharging) lowPower=\(self.battery.isLowPowerModeEnabled) status=\(self.status.displayText, privacy: .public)"
            )
        }
        notificationService.handleTransition(from: previousStatus, to: status)
        reconcileClosedLidMode(forceStatusRead: forceClosedLidStatusRead)
        reconcileClosedLidSideEffects()
        probeClosedLidHelperIfBlocked()
    }

    private func stopWhenDeadlineIsReached(now: Date) {
        guard let stopAt = settings.stopAt, stopAt <= now else {
            return
        }

        logger.info("scheduled stop reached")
        var nextSettings = settings
        nextSettings.enabled = false
        nextSettings.stopAt = nil
        settings = nextSettings
        settingsStore.save(nextSettings)
    }

    private func manualHoldSessions(now: Date) -> [AgentSession] {
        guard settings.enabled else {
            return []
        }

        return [
            AgentSession(
                id: "manual-hold",
                kind: .unknown,
                displayName: "Manual Hold",
                state: .working,
                source: .lifecycleHook,
                lastEventAt: now
            )
        ]
    }

    private func syncLaunchAtLoginStatus() {
        let enabled = loginItemService.isEnabled
        guard settings.launchAtLogin != enabled else {
            return
        }

        var nextSettings = settings
        nextSettings.launchAtLogin = enabled
        settings = nextSettings
        settingsStore.save(nextSettings)
    }

    private func syncSoftwareUpdateState() {
        softwareUpdateState = softwareUpdateService.state
    }

    private var shouldEnableClosedLidMode: Bool {
        guard settings.shouldPreventClosedLidSleep else {
            return false
        }

        if case .holding = status {
            return true
        }

        return false
    }

    /// Reads `pmset` on the blocking-work queue and publishes the result
    /// before handing it to `completion` on the main actor.
    ///
    /// Reads are never shared: a caller that needs the status after some
    /// event, such as a helper reply, must not be handed a read that started
    /// before it.
    private func readClosedLidStatus(then completion: @escaping @MainActor (ClosedLidStatus) -> Void) {
        let reader = closedLidStatusReader
        blockingWork.perform({
            reader.readClosedLidStatus()
        }, then: { [weak self] status in
            guard let self else {
                return
            }

            if closedLidStatus != status {
                closedLidStatus = status
            }
            completion(status)
        })
    }

    private func loadClosedLidOwnershipRecord() {
        closedLidOwnershipRecord = closedLidOwnershipStore.load()
    }

    private func saveClosedLidOwnershipRecord(_ record: ClosedLidOwnershipRecord?) {
        closedLidOwnershipRecord = record

        if let record {
            closedLidOwnershipStore.save(record)
        } else {
            closedLidOwnershipStore.clear()
        }
    }

    private func syncClosedLidHelperStatus() {
        let next = closedLidHelperService.status

        // Only publish on a real transition. @Published fires objectWillChange on
        // every assignment regardless of equality, so an unconditional write here
        // would re-render observing views on every 5s evaluate for no change.
        if closedLidHelperStatus != next {
            closedLidHelperStatus = next
            logger.info("closed-lid helper status changed status=\(self.closedLidHelperStatus.displayText, privacy: .public)")
        }

        clearClosedLidReadinessBlockIfPossible()
    }

    private func clearClosedLidReadinessBlockIfPossible() {
        guard closedLidHelperStatus.canControlClosedLidMode else {
            return
        }

        // A helper the app cannot reach reports the same `.enabled` status as a
        // working one, so a status refresh is not evidence the block is gone.
        // Lifting the block here would make the app reconnect on every evaluate
        // for as long as the app runs. `probeClosedLidHelperIfBlocked()` lifts it
        // instead, once the helper has actually answered.
        guard !closedLidHelperNeedsRepair else {
            return
        }

        suppressedClosedLidTarget = nil

        guard let closedLidError, isClosedLidReadinessError(closedLidError) else {
            return
        }

        self.closedLidError = nil
    }

    private func isClosedLidReadinessError(_ message: String) -> Bool {
        message.contains("Approve Lid Awake Helper")
            || message.contains("Set up Advanced Helper")
            || message.contains("Helper is not registered")
            || message.contains("Helper is missing")
            || message.contains("Advanced Helper is not ready")
            || message.contains("needs approval in System Settings")
    }

    /// Moves closed-lid mode toward what the current settings want.
    ///
    /// Anything that needs a fresh status reads it off the main actor and
    /// finishes in `finishReconcilingClosedLidMode`, which checks every
    /// condition again, since any of them can change while `pmset` answers.
    private func reconcileClosedLidMode(forceStatusRead: Bool = false) {
        guard !isChangingClosedLidMode, !isTerminating else {
            return
        }

        syncClosedLidHelperStatus()

        let desired = shouldEnableClosedLidMode
        guard desired || appEnabledClosedLidMode || forceStatusRead else {
            return
        }

        // Steady state: when closed-lid mode is already enabled and still desired,
        // re-verify with `pmset` only occasionally instead of spawning a subprocess
        // on every 5s evaluate. Each read fork/execs /usr/bin/pmset, so an
        // unthrottled read here is ~17k process spawns/day while holding.
        if desired, !forceStatusRead, closedLidStatus == .enabled,
           let lastVerified = lastClosedLidVerifiedAt,
           Date().timeIntervalSince(lastVerified) < closedLidVerifyInterval {
            closedLidError = nil
            return
        }

        guard !isReadingClosedLidStatus else {
            return
        }

        isReadingClosedLidStatus = true
        readClosedLidStatus { [weak self] status in
            guard let self else {
                return
            }

            isReadingClosedLidStatus = false
            finishReconcilingClosedLidMode(status: status)
        }
    }

    private func finishReconcilingClosedLidMode(status: ClosedLidStatus) {
        guard !isChangingClosedLidMode, !isTerminating else {
            return
        }

        lastClosedLidVerifiedAt = status == .enabled ? Date() : nil

        if shouldEnableClosedLidMode {
            guard status != .enabled else {
                closedLidError = nil
                return
            }

            guard suppressedClosedLidTarget != true, !closedLidHelperRemovalRequested else {
                return
            }

            guard closedLidHelperStatus.canControlClosedLidMode else {
                suppressedClosedLidTarget = true
                closedLidError = "Set up Advanced Helper before enabling closed-lid mode."
                return
            }

            setClosedLidMode(enabled: true, previousStatus: status)
            return
        }

        guard appEnabledClosedLidMode, suppressedClosedLidTarget != false else {
            return
        }

        switch ClosedLidOwnershipReducer.restoreAction(
            record: closedLidOwnershipRecord,
            desiredClosedLidMode: false,
            currentStatus: status,
            helperCanControlClosedLidMode: closedLidHelperStatus.canControlClosedLidMode,
            attemptedAt: Date()
        ) {
        case .none:
            return
        case .clearRecord:
            saveClosedLidOwnershipRecord(nil)
            suppressedClosedLidTarget = nil
            closedLidError = nil
            return
        case let .blockedByHelper(record):
            saveClosedLidOwnershipRecord(record)
            suppressedClosedLidTarget = false
            closedLidError = "Advanced Helper is not ready, so closed-lid mode could not be restored."
            return
        case let .restore(record):
            saveClosedLidOwnershipRecord(record)
            setClosedLidMode(enabled: false, previousStatus: status)
        }
    }

    private func setClosedLidMode(enabled: Bool, previousStatus: ClosedLidStatus) {
        let changeID = UUID()
        pendingClosedLidModeChange = ClosedLidModeChange(id: changeID, enabled: enabled)
        isChangingClosedLidMode = true
        closedLidError = nil
        if enabled {
            let intentRecord = ClosedLidOwnershipReducer.recordBeforeEnabling(
                previousStatus: previousStatus,
                existingRecord: closedLidOwnershipRecord,
                at: Date()
            )
            if intentRecord != closedLidOwnershipRecord {
                saveClosedLidOwnershipRecord(intentRecord)
            }
        }
        scheduleClosedLidModeChangeTimeout(
            changeID: changeID,
            enabled: enabled,
            previousStatus: previousStatus
        )

        closedLidHelperService.setClosedLidMode(enabled: enabled) { [weak self] result in
            DispatchQueue.main.async {
                // A reply that already timed out is not worth a `pmset` read.
                guard let self, self.pendingClosedLidModeChange?.id == changeID else {
                    return
                }

                self.readClosedLidStatus { [weak self] status in
                    self?.finishClosedLidModeChange(
                        changeID: changeID,
                        enabled: enabled,
                        result: result,
                        previousStatus: previousStatus,
                        status: status
                    )
                }
            }
        }
    }

    private func scheduleClosedLidModeChangeTimeout(
        changeID: UUID,
        enabled: Bool,
        previousStatus: ClosedLidStatus
    ) {
        let timeout = closedLidModeChangeTimeout
        guard timeout > 0 else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finishClosedLidModeChangeTimeout(
                changeID: changeID,
                enabled: enabled,
                previousStatus: previousStatus
            )
        }
    }

    private func finishClosedLidModeChange(
        changeID: UUID,
        enabled: Bool,
        result: Result<Void, Error>,
        previousStatus: ClosedLidStatus,
        status: ClosedLidStatus
    ) {
        guard pendingClosedLidModeChange?.id == changeID else {
            return
        }

        pendingClosedLidModeChange = nil
        isChangingClosedLidMode = false
        closedLidStatus = status

        switch result {
        case .success:
            let nextRecord = ClosedLidOwnershipReducer.recordAfterSuccessfulChange(
                enabled: enabled,
                previousStatus: previousStatus,
                finalStatus: status,
                existingRecord: closedLidOwnershipRecord,
                at: Date()
            )
            saveClosedLidOwnershipRecord(nextRecord)
            suppressedClosedLidTarget = nil
            closedLidError = nil
            closedLidHelperNeedsRepair = false
        case let .failure(error):
            suppressedClosedLidTarget = enabled
            closedLidError = closedLidUserFacingError(from: error)
            closedLidHelperNeedsRepair = isRepairableClosedLidFailure(error)
        }

        reconcileClosedLidSideEffects()
    }

    private func finishClosedLidModeChangeTimeout(
        changeID: UUID,
        enabled: Bool,
        previousStatus: ClosedLidStatus
    ) {
        guard pendingClosedLidModeChange?.id == changeID else {
            return
        }

        readClosedLidStatus { [weak self] status in
            self?.finishClosedLidModeChangeTimeout(
                changeID: changeID,
                enabled: enabled,
                previousStatus: previousStatus,
                status: status
            )
        }
    }

    private func finishClosedLidModeChangeTimeout(
        changeID: UUID,
        enabled: Bool,
        previousStatus: ClosedLidStatus,
        status: ClosedLidStatus
    ) {
        // The reply can land while `pmset` answers, and then it has the say.
        guard pendingClosedLidModeChange?.id == changeID else {
            return
        }

        if status == (enabled ? .enabled : .disabled) {
            finishClosedLidModeChange(
                changeID: changeID,
                enabled: enabled,
                result: .success(()),
                previousStatus: previousStatus,
                status: status
            )
            return
        }

        pendingClosedLidModeChange = nil
        isChangingClosedLidMode = false
        syncClosedLidHelperStatus()
        closedLidStatus = status
        suppressedClosedLidTarget = enabled
        closedLidError = Self.closedLidModeChangeTimeoutMessage
        closedLidHelperNeedsRepair = true
        logger.error("closed-lid helper update timed out enabled=\(enabled)")
        reconcileClosedLidSideEffects()
    }

    private func reconcileClosedLidSideEffects() {
        refreshScreenLockAccessibilityState(prompt: false)

        // When disabled, neither the lock nor the display coordinator can act, so
        // skip their per-tick IOKit clamshell reads entirely rather than polling
        // AppleClamshellState twice every second for the life of the process.
        guard settings.enabled else {
            closedLidLockCoordinator.forgetLidState()
            closedLidDisplayCoordinator.forgetLidState()
            return
        }

        reconcileClosedLidLock()
        reconcileClosedLidDisplay()
    }

    private func requestScreenLockAccessibilityPermissionIfNeeded() {
        guard settings.enabled, settings.lockScreenWhenLidCloses else {
            return
        }
        guard screenLockPermissionChecker.requiresAccessibilityPermission else {
            clearScreenLockAccessibilityErrorIfNeeded()
            return
        }
        // macOS queues a fresh system dialog for every prompt, so toggling the
        // setting must not stack them. The Settings window covers later asks.
        guard !didPromptForScreenLockAccessibility else {
            refreshScreenLockAccessibilityState(prompt: false)
            return
        }
        didPromptForScreenLockAccessibility = true
        refreshScreenLockAccessibilityState(prompt: true)
    }

    private func refreshScreenLockAccessibilityState(prompt: Bool) {
        guard settings.enabled, settings.lockScreenWhenLidCloses else {
            setScreenLockAccessibilityTrusted(true)
            return
        }
        guard screenLockPermissionChecker.requiresAccessibilityPermission else {
            setScreenLockAccessibilityTrusted(true)
            clearScreenLockAccessibilityErrorIfNeeded()
            return
        }

        let trusted = screenLockPermissionChecker.hasAccessibilityPermission(prompt: prompt)
        setScreenLockAccessibilityTrusted(trusted)

        if trusted {
            clearScreenLockAccessibilityErrorIfNeeded()
        }
    }

    // Publish only on a real change. This runs every second while lock-on-close is
    // enabled, and @Published does not dedupe by equality, so an unconditional
    // write would re-render observing views once per second for a static value.
    private func setScreenLockAccessibilityTrusted(_ value: Bool) {
        if screenLockAccessibilityTrusted != value {
            screenLockAccessibilityTrusted = value
        }
    }

    private func clearScreenLockAccessibilityErrorIfNeeded() {
        guard closedLidLockError == ScreenLockError.accessibilityPermissionMessage else {
            return
        }
        closedLidLockError = nil
        closedLidLockCoordinator.reset()
    }

    private func reconcileClosedLidLock() {
        let action = closedLidLockCoordinator.update(settings: settings)

        if !settings.lockScreenWhenLidCloses, closedLidLockError != nil {
            closedLidLockError = nil
        }

        switch action {
        case .none:
            break
        case .requestedLock:
            closedLidLockError = nil
            logger.info("requested screen lock for closed lid")
        case let .failed(message):
            closedLidLockError = message
            logger.error("screen lock request failed message=\(message, privacy: .public)")
        }
    }

    private func reconcileClosedLidDisplay() {
        let action = closedLidDisplayCoordinator.update(
            settings: settings,
            wakeStatus: status,
            closedLidStatus: closedLidStatus,
            waitForScreenLockBeforeDisplaySleep: closedLidLockError == nil
        )

        switch action {
        case .none:
            break
        case .requestedDisplaySleep:
            closedLidDisplayError = nil
            logger.info("requested display sleep for closed lid")
        case let .failed(message):
            closedLidDisplayError = message
            logger.error("display sleep request failed message=\(message, privacy: .public)")
        }
    }

    /// A display sleep command that failed after the coordinator handed it off.
    func reportClosedLidDisplayFailure(_ message: String) {
        closedLidDisplayError = message
        logger.error("display sleep request failed message=\(message, privacy: .public)")
    }

    /// A screen lock command that failed after the coordinator handed it off.
    func reportClosedLidLockFailure(_ message: String) {
        closedLidLockError = message
        logger.error("screen lock request failed message=\(message, privacy: .public)")
    }

    private func closedLidUserFacingError(from error: Error) -> String {
        let message = error.localizedDescription
        guard PMSetService.isPermissionFailureOutput(message) else {
            return message
        }

        return "Lid Awake Helper needs approval in System Settings before it can change closed-lid mode."
    }

    private func closedLidSetupError(from error: Error) -> String {
        let message = error.localizedDescription
        guard PMSetService.isPermissionFailureOutput(message) else {
            return message
        }

        closedLidHelperService.openApprovalSettings()
        return "Approve Lid Awake Helper in System Settings, then return here."
    }

    private func closedLidRemovalError(from error: Error) -> String {
        let message = error.localizedDescription
        guard PMSetService.isPermissionFailureOutput(message) else {
            return message
        }

        closedLidHelperService.openApprovalSettings()
        return "macOS blocked removing the helper. Disable Lid Awake Helper in System Settings, then return here."
    }
}
