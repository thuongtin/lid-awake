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
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var closedLidStatus: ClosedLidStatus = .notReported
    @Published private(set) var closedLidHelperStatus: ClosedLidHelperStatus = .notRegistered
    @Published private(set) var closedLidError: String?
    @Published private(set) var closedLidDisplayError: String?
    @Published private(set) var closedLidLockError: String?
    @Published private(set) var screenLockAccessibilityTrusted = true
    @Published private(set) var isChangingClosedLidMode = false

    private static let closedLidModeChangeTimeoutMessage =
        "Lid Awake Helper did not respond. Repair the helper, then try again."

    private let settingsStore: UserSettingsStoring
    private let closedLidOwnershipStore: ClosedLidOwnershipStoring
    private let batteryMonitor: BatteryMonitoring
    private let loginItemService: LoginItemServicing
    private let closedLidStatusReader: ClosedLidStatusReading
    private let closedLidHelperService: ClosedLidHelperServicing
    private let screenLockPermissionChecker: ScreenLockPermissionChecking
    private let closedLidModeChangeTimeout: TimeInterval
    private let logger = Logger(subsystem: "com.thuongtin.LidAwake", category: "app")
    private let powerController: PowerAssertionControlling
    private let coordinator: WakePolicyCoordinator
    private let closedLidDisplayCoordinator: ClosedLidDisplayCoordinator
    private let closedLidLockCoordinator: ClosedLidLockCoordinator
    private let notificationService: NotificationServicing
    private var previousStatus: WakeStatus = .inactive
    private var timer: Timer?
    private var closedLidSideEffectsTimer: Timer?
    private var closedLidOwnershipRecord: ClosedLidOwnershipRecord?
    private var suppressedClosedLidTarget: Bool?
    private var closedLidModeChangeID: UUID?

    private var appEnabledClosedLidMode: Bool {
        closedLidOwnershipRecord?.ownedByThisApp == true
    }

    convenience init() {
        let powerController = PowerAssertionManager(creator: IOKitPowerAssertionCreator())
        self.init(
            settingsStore: SettingsStore(),
            closedLidOwnershipStore: UserDefaultsClosedLidOwnershipStore(),
            batteryMonitor: SystemBatteryMonitor(),
            loginItemService: LoginItemService(),
            closedLidStatusReader: PMSetService(),
            closedLidHelperService: ClosedLidHelperService(),
            screenLockPermissionChecker: SystemScreenLockPermissionChecker(),
            powerController: powerController,
            clock: SystemClock(),
            closedLidDisplayCoordinator: ClosedLidDisplayCoordinator(
                clamshellStateReader: IOKitClamshellStateReader(),
                displaySleeper: PMSetDisplaySleepService(),
                screenLockStateReader: CGSessionScreenLockStateReader()
            ),
            closedLidLockCoordinator: ClosedLidLockCoordinator(
                clamshellStateReader: IOKitClamshellStateReader(),
                deviceLocker: SystemScreenLockService()
            ),
            notificationService: SystemNotificationService(),
            initialBattery: BatteryState.desktopOrUnknown(
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        )
    }

    init(
        settingsStore: UserSettingsStoring,
        closedLidOwnershipStore: ClosedLidOwnershipStoring,
        batteryMonitor: BatteryMonitoring,
        loginItemService: LoginItemServicing,
        closedLidStatusReader: ClosedLidStatusReading,
        closedLidHelperService: ClosedLidHelperServicing,
        screenLockPermissionChecker: ScreenLockPermissionChecking,
        powerController: PowerAssertionControlling,
        clock: Clock,
        closedLidDisplayCoordinator: ClosedLidDisplayCoordinator,
        closedLidLockCoordinator: ClosedLidLockCoordinator,
        notificationService: NotificationServicing,
        initialBattery: BatteryState,
        closedLidModeChangeTimeout: TimeInterval = 6
    ) {
        self.settingsStore = settingsStore
        self.closedLidOwnershipStore = closedLidOwnershipStore
        self.batteryMonitor = batteryMonitor
        self.loginItemService = loginItemService
        self.closedLidStatusReader = closedLidStatusReader
        self.closedLidHelperService = closedLidHelperService
        self.screenLockPermissionChecker = screenLockPermissionChecker
        self.closedLidModeChangeTimeout = closedLidModeChangeTimeout
        self.powerController = powerController
        self.coordinator = WakePolicyCoordinator(
            powerController: powerController,
            clock: clock
        )
        self.closedLidDisplayCoordinator = closedLidDisplayCoordinator
        self.closedLidLockCoordinator = closedLidLockCoordinator
        self.notificationService = notificationService
        self.settings = settingsStore.load()
        self.battery = initialBattery
    }

    func start(scheduleTimers: Bool = true) {
        logger.info("Lid Awake model start")
        loadClosedLidOwnershipRecord()
        syncLaunchAtLoginStatus()
        syncClosedLidHelperStatus()
        syncClosedLidStatus()
        evaluate()
        requestScreenLockAccessibilityPermissionIfNeeded()
        guard scheduleTimers else {
            return
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
        closedLidSideEffectsTimer?.invalidate()
        closedLidSideEffectsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileClosedLidSideEffects()
            }
        }
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
        "Allow Accessibility for Lock Screen"
    }

    var screenLockPermissionMessage: String {
        "Lock-on-close uses the main Lid Awake app to send the system Lock Screen shortcut on this macOS build."
    }

    var screenLockPermissionCompactMessage: String {
        "Allow the current Lid Awake app in Accessibility to use lock-on-close."
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
            && closedLidError == Self.closedLidModeChangeTimeoutMessage
    }

    func refreshClosedLidPermissionState() {
        syncClosedLidHelperStatus()
        syncClosedLidStatus()
    }

    func refreshAfterExternalPermissionChange() {
        refreshClosedLidPermissionState()
        refreshScreenLockAccessibilityState(prompt: false)
        evaluate()
        refreshScreenLockAccessibilityState(prompt: false)
    }

    func stop() {
        logger.info("Lid Awake model stop")
        timer?.invalidate()
        timer = nil
        closedLidSideEffectsTimer?.invalidate()
        closedLidSideEffectsTimer = nil
        powerController.release()
        restoreClosedLidModeForTerminationIfNeeded()
    }

    func updateSettings(_ update: (inout UserSettings) -> Void) {
        var nextSettings = settings
        update(&nextSettings)
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

    func updateLidClosedDisplayMode(_ mode: LidClosedDisplayMode) {
        suppressedClosedLidTarget = nil
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
        closedLidModeChangeID = nil

        do {
            try closedLidHelperService.repairRegistration()
            syncClosedLidHelperStatus()
            suppressedClosedLidTarget = nil
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
        isChangingClosedLidMode = false
        closedLidModeChangeID = nil

        do {
            try closedLidHelperService.unregister()
            syncClosedLidHelperStatus()
            closedLidError = nil
        } catch {
            syncClosedLidHelperStatus()
            closedLidError = closedLidRemovalError(from: error)
        }
    }

    func pause(for interval: TimeInterval) {
        updateSettings { settings in
            settings.pauseUntil = Date().addingTimeInterval(interval)
        }
    }

    func clearPause() {
        updateSettings { settings in
            settings.pauseUntil = nil
        }
    }

    func quit() {
        stop()
        NSApplication.shared.terminate(nil)
    }

    func evaluate() {
        logger.debug("evaluate begin")
        battery = batteryMonitor.currentState()
        logger.debug("evaluate battery complete")
        sessions = manualHoldSessions(now: Date())
        previousStatus = status
        status = coordinator.update(
            settings: settings,
            sessions: sessions,
            battery: battery
        )
        if status != previousStatus {
            logger.info(
                "status changed enabled=\(self.settings.enabled) sessions=\(self.sessions.count) batteryPercent=\(self.battery.percent ?? -1) ac=\(self.battery.isOnACPower) charging=\(self.battery.isCharging) lowPower=\(self.battery.isLowPowerModeEnabled) status=\(self.status.displayText, privacy: .public)"
            )
        }
        notificationService.handleTransition(from: previousStatus, to: status)
        reconcileClosedLidMode(desired: shouldEnableClosedLidMode, forceDisable: false)
        reconcileClosedLidSideEffects()
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

    private var shouldEnableClosedLidMode: Bool {
        guard settings.shouldPreventClosedLidSleep else {
            return false
        }

        if case .holding = status {
            return true
        }

        return false
    }

    private func syncClosedLidStatus() {
        closedLidStatus = closedLidStatusReader.readClosedLidStatus()
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
        let previousStatus = closedLidHelperStatus
        closedLidHelperStatus = closedLidHelperService.status

        if previousStatus != closedLidHelperStatus {
            logger.info("closed-lid helper status changed status=\(self.closedLidHelperStatus.displayText, privacy: .public)")
        }

        clearClosedLidReadinessBlockIfPossible()
    }

    private func clearClosedLidReadinessBlockIfPossible() {
        guard closedLidHelperStatus.canControlClosedLidMode else {
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

    private func reconcileClosedLidMode(desired: Bool, forceDisable: Bool) {
        if isChangingClosedLidMode {
            return
        }

        syncClosedLidHelperStatus()
        syncClosedLidStatus()

        if desired {
            guard closedLidStatus != .enabled else {
                closedLidError = nil
                return
            }

            guard suppressedClosedLidTarget != true else {
                return
            }

            guard closedLidHelperStatus.canControlClosedLidMode else {
                suppressedClosedLidTarget = true
                closedLidError = "Set up Advanced Helper before enabling closed-lid mode."
                return
            }

            setClosedLidMode(enabled: true, previousStatus: closedLidStatus)
            return
        }

        guard appEnabledClosedLidMode || forceDisable else {
            return
        }

        guard suppressedClosedLidTarget != false || forceDisable else {
            return
        }

        switch ClosedLidOwnershipReducer.restoreAction(
            record: closedLidOwnershipRecord,
            desiredClosedLidMode: desired && !forceDisable,
            currentStatus: closedLidStatus,
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
            setClosedLidMode(enabled: false, previousStatus: closedLidStatus)
        }
    }

    private func setClosedLidMode(enabled: Bool, previousStatus: ClosedLidStatus) {
        let changeID = UUID()
        closedLidModeChangeID = changeID
        isChangingClosedLidMode = true
        closedLidError = nil
        scheduleClosedLidModeChangeTimeout(
            changeID: changeID,
            enabled: enabled,
            previousStatus: previousStatus
        )

        closedLidHelperService.setClosedLidMode(enabled: enabled) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                let status = self.closedLidStatusReader.readClosedLidStatus()
                self.finishClosedLidModeChange(
                    changeID: changeID,
                    enabled: enabled,
                    result: result,
                    previousStatus: previousStatus,
                    status: status
                )
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
        guard closedLidModeChangeID == changeID else {
            return
        }

        closedLidModeChangeID = nil
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
        case let .failure(error):
            suppressedClosedLidTarget = enabled
            closedLidError = closedLidUserFacingError(from: error)
        }

        reconcileClosedLidSideEffects()
    }

    private func finishClosedLidModeChangeTimeout(
        changeID: UUID,
        enabled: Bool,
        previousStatus: ClosedLidStatus
    ) {
        guard closedLidModeChangeID == changeID else {
            return
        }

        let status = closedLidStatusReader.readClosedLidStatus()
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

        closedLidModeChangeID = nil
        isChangingClosedLidMode = false
        syncClosedLidHelperStatus()
        closedLidStatus = status
        suppressedClosedLidTarget = enabled
        closedLidError = Self.closedLidModeChangeTimeoutMessage
        logger.error("closed-lid helper update timed out enabled=\(enabled)")
        reconcileClosedLidSideEffects()
    }

    private func reconcileClosedLidSideEffects() {
        refreshScreenLockAccessibilityState(prompt: false)
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
        refreshScreenLockAccessibilityState(prompt: true)
    }

    private func refreshScreenLockAccessibilityState(prompt: Bool) {
        guard settings.enabled, settings.lockScreenWhenLidCloses else {
            screenLockAccessibilityTrusted = true
            return
        }
        guard screenLockPermissionChecker.requiresAccessibilityPermission else {
            screenLockAccessibilityTrusted = true
            clearScreenLockAccessibilityErrorIfNeeded()
            return
        }

        let trusted = screenLockPermissionChecker.hasAccessibilityPermission(prompt: prompt)
        screenLockAccessibilityTrusted = trusted

        if trusted {
            clearScreenLockAccessibilityErrorIfNeeded()
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

        if !settings.lockScreenWhenLidCloses {
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
            closedLidStatus: closedLidStatus
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

    private func restoreClosedLidModeForTerminationIfNeeded() {
        guard appEnabledClosedLidMode else {
            return
        }

        syncClosedLidHelperStatus()
        syncClosedLidStatus()

        switch ClosedLidOwnershipReducer.restoreAction(
            record: closedLidOwnershipRecord,
            desiredClosedLidMode: false,
            currentStatus: closedLidStatus,
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
        }

        let semaphore = DispatchSemaphore(value: 0)
        var restoreError: Error?
        closedLidHelperService.setClosedLidMode(enabled: false) { result in
            if case let .failure(error) = result {
                restoreError = error
            }
            semaphore.signal()
        }
        let didComplete = semaphore.wait(timeout: .now() + 3) == .success
        let completion = ClosedLidOwnershipReducer.restoreCompletion(
            didComplete: didComplete,
            errorMessage: restoreError?.localizedDescription
        )

        switch completion {
        case .clearRecord:
            saveClosedLidOwnershipRecord(nil)
            suppressedClosedLidTarget = nil
            closedLidError = nil
            syncClosedLidStatus()
        case let .keepRecord(errorMessage):
            closedLidError = errorMessage
        }
    }
}
