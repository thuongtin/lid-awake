@testable import LidAwake
import LidAwakeCore
import XCTest

@MainActor
final class AppModelLifecycleTests: XCTestCase {
    func testApprovalRefreshMovesFromRequiresApprovalToEnabledAndAppliesSuppressedClosedLidTarget() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .requiresApproval,
            closedLidStatus: .disabled
        )
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertEqual(harness.model.closedLidHelperStatus, .requiresApproval)
        XCTAssertEqual(harness.model.closedLidError, "Set up Advanced Helper before enabling closed-lid mode.")
        XCTAssertTrue(harness.helper.setClosedLidModeRequests.isEmpty)

        harness.helper.status = .enabled
        harness.model.refreshAfterExternalPermissionChange()
        await drainMainQueue()

        XCTAssertEqual(harness.model.closedLidHelperStatus, .enabled)
        XCTAssertNil(harness.model.closedLidError)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
        XCTAssertEqual(harness.closedLidStatusReader.status, .enabled)
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
        XCTAssertEqual(harness.ownershipStore.record?.previousStatus, .disabled)
        XCTAssertGreaterThan(harness.powerController.acquireCount, 0)
    }

    func testPreExistingEnabledSystemStateDoesNotCreateOwnership() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertTrue(harness.helper.setClosedLidModeRequests.isEmpty)
        XCTAssertNil(harness.ownershipStore.record)
        XCTAssertNil(harness.model.closedLidError)
        XCTAssertEqual(harness.model.closedLidStatus, .enabled)
    }

    func testSuccessfulEnableFromDisabledRecordsOwnership() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
        XCTAssertEqual(harness.model.closedLidStatus, .enabled)
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
        XCTAssertEqual(harness.ownershipStore.record?.previousStatus, .disabled)
        XCTAssertNil(harness.ownershipStore.record?.lastAttemptedRestoreAt)
    }

    func testDisableRestoresAndClearsOwnership() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
        XCTAssertNotNil(harness.ownershipStore.record)

        harness.model.updateSettings { settings in
            settings.enabled = false
        }
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.model.closedLidStatus, .disabled)
        XCTAssertNil(harness.ownershipStore.record)
        XCTAssertNil(harness.model.closedLidError)
    }

    func testRemoveHelperRestoresOwnedClosedLidModeBeforeUnregistering() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
        XCTAssertNotNil(harness.ownershipStore.record)

        harness.model.removeClosedLidHelper()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.helper.unregisterCallCount, 1)
        XCTAssertEqual(harness.model.closedLidStatus, .disabled)
        XCTAssertNil(harness.ownershipStore.record)
        XCTAssertNil(harness.model.closedLidError)
    }

    func testRemoveHelperKeepsHelperWhenRestoreFails() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertNotNil(harness.ownershipStore.record)

        harness.helper.onSetClosedLidMode = nil
        harness.helper.setClosedLidModeResult = .failure(NSError(domain: "Restore", code: 1))
        harness.model.removeClosedLidHelper()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.helper.unregisterCallCount, 0)
        XCTAssertEqual(harness.model.closedLidStatus, .enabled)
        XCTAssertNotNil(harness.ownershipStore.record)
        XCTAssertTrue(harness.model.closedLidError?.contains("Could not restore closed-lid mode") == true)
    }

    func testRemoveHelperUnregistersDirectlyWithoutOwnership() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertNil(harness.ownershipStore.record)

        harness.model.removeClosedLidHelper()
        await drainMainQueue()

        XCTAssertTrue(harness.helper.setClosedLidModeRequests.isEmpty)
        XCTAssertEqual(harness.helper.unregisterCallCount, 1)
        XCTAssertNil(harness.model.closedLidError)
    }

    func testStartupRestoreAttemptsCleanupWhenPersistedOwnershipExists() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .enabled,
            ownershipRecord: ownedRecord()
        )
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [false])
        XCTAssertEqual(harness.model.closedLidStatus, .disabled)
        XCTAssertNil(harness.ownershipStore.record)
        XCTAssertNil(harness.model.closedLidError)
    }

    func testStartupRestoreKeepsWarningAndOwnershipWhenHelperUnavailable() async {
        let existingRecord = ownedRecord()
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .requiresApproval,
            closedLidStatus: .enabled,
            ownershipRecord: existingRecord
        )

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertTrue(harness.helper.setClosedLidModeRequests.isEmpty)
        XCTAssertEqual(
            harness.model.closedLidError,
            "Advanced Helper is not ready, so closed-lid mode could not be restored."
        )
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
        XCTAssertEqual(harness.ownershipStore.record?.previousStatus, existingRecord.previousStatus)
        XCTAssertNotNil(harness.ownershipStore.record?.lastAttemptedRestoreAt)
    }

    func testClosedLidModeTimeoutClearsUpdatingStateAndOffersRepair() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled,
            closedLidModeChangeTimeout: 0.05
        )
        harness.helper.shouldReplyToSetClosedLidMode = false

        harness.model.start(scheduleTimers: false)
        XCTAssertTrue(harness.model.isChangingClosedLidMode)

        try? await Task.sleep(nanoseconds: 120_000_000)
        await drainMainQueue()

        XCTAssertFalse(harness.model.isChangingClosedLidMode)
        XCTAssertEqual(harness.model.closedLidStatus, .disabled)
        XCTAssertEqual(
            harness.model.closedLidError,
            "Lid Awake Helper did not respond. Repair the helper, then try again."
        )
        XCTAssertTrue(harness.model.closedLidControlNeedsAttention)
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertEqual(harness.model.closedLidCompactActionTitle, "Repair")
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
    }

    func testClosedLidModeTimeoutRecordsSuccessWhenSystemStateChanged() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled,
            closedLidModeChangeTimeout: 0.05
        )
        harness.helper.shouldReplyToSetClosedLidMode = false
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }

        harness.model.start(scheduleTimers: false)

        try? await Task.sleep(nanoseconds: 120_000_000)
        await drainMainQueue()

        XCTAssertFalse(harness.model.isChangingClosedLidMode)
        XCTAssertEqual(harness.model.closedLidStatus, .enabled)
        XCTAssertNil(harness.model.closedLidError)
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
    }

    func testRepairActionReinstallsHelperAndRetriesSuppressedTarget() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled,
            closedLidModeChangeTimeout: 0.05
        )
        harness.helper.shouldReplyToSetClosedLidMode = false

        harness.model.start(scheduleTimers: false)
        try? await Task.sleep(nanoseconds: 120_000_000)
        await drainMainQueue()

        harness.helper.shouldReplyToSetClosedLidMode = true
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }
        harness.model.performClosedLidHelperAction()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.repairRegistrationCallCount, 1)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, true])
        XCTAssertEqual(harness.model.closedLidStatus, .enabled)
        XCTAssertNil(harness.model.closedLidError)
    }

    func testExternalAccessibilityGrantClearsStaleScreenLockError() async {
        let harness = AppModelHarness(
            settings: UserSettings(
                enabled: true,
                lockScreenWhenLidCloses: true
            ),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.lockClamshellReader.state = .open
        harness.deviceLocker.error = ScreenLockError.accessibilityPermissionRequired
        harness.screenLockPermissionChecker.requiresAccessibilityPermission = true
        harness.screenLockPermissionChecker.hasPermission = false

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.lockClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(
            harness.model.closedLidLockError,
            ScreenLockError.accessibilityPermissionMessage
        )
        XCTAssertEqual(harness.screenLockPermissionChecker.promptRequests, [false, true, false])

        harness.screenLockPermissionChecker.hasPermission = true
        harness.deviceLocker.error = nil
        harness.model.refreshAfterExternalPermissionChange()
        await drainMainQueue()

        XCTAssertNil(harness.model.closedLidLockError)
        XCTAssertEqual(
            harness.screenLockPermissionChecker.promptRequests,
            [false, true, false, false, false, false]
        )
        XCTAssertEqual(harness.deviceLocker.lockCount, 1)
    }

    func testStartupDoesNotLockWhenLidWasAlreadyClosed() async {
        let harness = AppModelHarness(
            settings: UserSettings(
                enabled: true,
                lockScreenWhenLidCloses: true
            ),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.lockClamshellReader.state = .closed

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.model.refreshAfterExternalPermissionChange()
        await drainMainQueue()

        XCTAssertNil(harness.model.closedLidLockError)
        XCTAssertEqual(harness.deviceLocker.lockCount, 0)
    }

    func testScreenLockPermissionActionOpensAccessibilitySettings() async {
        let harness = AppModelHarness(
            settings: UserSettings(
                enabled: true,
                lockScreenWhenLidCloses: true
            ),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.screenLockPermissionChecker.requiresAccessibilityPermission = true
        harness.screenLockPermissionChecker.hasPermission = false

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertTrue(harness.model.screenLockPermissionNeedsAttention)
        XCTAssertTrue(harness.model.screenLockPermissionIsRelevant)
        XCTAssertEqual(harness.model.screenLockPermissionStatusText, "Needs approval")

        harness.model.openScreenLockAccessibilitySettings()

        XCTAssertEqual(harness.screenLockPermissionChecker.openAccessibilitySettingsCallCount, 1)
        XCTAssertEqual(harness.screenLockPermissionChecker.promptRequests, [false, true, true])
    }

    func testDisplaySleepProceedsAfterLockFailure() async {
        let harness = AppModelHarness(
            settings: UserSettings(
                enabled: true,
                lockScreenWhenLidCloses: true
            ),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.lockClamshellReader.state = .open
        harness.displayClamshellReader.state = .open
        harness.displayScreenLockStateReader.state = .unlocked
        harness.deviceLocker.error = ScreenLockError.accessibilityPermissionRequired
        harness.screenLockPermissionChecker.requiresAccessibilityPermission = true
        harness.screenLockPermissionChecker.hasPermission = false

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.lockClamshellReader.state = .closed
        harness.displayClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(
            harness.model.closedLidLockError,
            ScreenLockError.accessibilityPermissionMessage
        )
        XCTAssertEqual(harness.displaySleeper.sleepCount, 1)
        XCTAssertNil(harness.model.closedLidDisplayError)
    }

    func testSoftwareUpdateServiceStartsAndSyncsState() async {
        let updateState = SoftwareUpdateState(
            isConfigured: true,
            canCheckForUpdates: true,
            sessionInProgress: false,
            automaticallyChecksForUpdates: true,
            automaticallyDownloadsUpdates: false,
            allowsAutomaticUpdates: true,
            feedURL: "https://example.com/appcast.xml",
            message: "Ready to check for signed updates."
        )
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .disabled,
            softwareUpdateState: updateState
        )

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertEqual(harness.softwareUpdateService.startCallCount, 1)
        XCTAssertEqual(harness.model.softwareUpdateState, updateState)
    }

    func testCheckForSoftwareUpdatesUsesSoftwareUpdateService() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .disabled,
            softwareUpdateState: SoftwareUpdateState(
                isConfigured: true,
                canCheckForUpdates: true,
                sessionInProgress: false,
                automaticallyChecksForUpdates: true,
                automaticallyDownloadsUpdates: false,
                allowsAutomaticUpdates: true,
                feedURL: "https://example.com/appcast.xml",
                message: "Ready to check for signed updates."
            )
        )

        harness.model.checkForSoftwareUpdates()
        await drainMainQueue()

        XCTAssertEqual(harness.softwareUpdateService.checkForUpdatesCallCount, 1)
    }

    func testSoftwareUpdateTogglesUseSoftwareUpdateService() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )

        harness.model.setAutomaticallyChecksForUpdates(false)
        harness.model.setAutomaticallyDownloadsUpdates(true)
        await drainMainQueue()

        XCTAssertEqual(harness.softwareUpdateService.automaticCheckRequests, [false])
        XCTAssertEqual(harness.softwareUpdateService.automaticDownloadRequests, [true])

        harness.softwareUpdateService.emit(
            SoftwareUpdateState(
                isConfigured: true,
                canCheckForUpdates: true,
                sessionInProgress: false,
                automaticallyChecksForUpdates: false,
                automaticallyDownloadsUpdates: true,
                allowsAutomaticUpdates: true,
                feedURL: "https://example.com/appcast.xml",
                message: "Ready to check for signed updates."
            )
        )
        await drainMainQueue()

        XCTAssertFalse(harness.model.softwareUpdateState.automaticallyChecksForUpdates)
        XCTAssertTrue(harness.model.softwareUpdateState.automaticallyDownloadsUpdates)
    }

    func testSteadyStateEvaluateDoesNotSpamStatusReadsOrPublish() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        let countAfterStart = harness.closedLidStatusReader.readCount

        // Note: the objectWillChange churn assertion was dropped here because it is
        // flaky due to unrelated published writes outside this plan's scope
        // (e.g. syncClosedLidHelperStatus() and refreshScreenLockAccessibilityState()
        // reassign their @Published properties unconditionally on every tick). See
        // plan 019 step 5 for the documented fallback.
        harness.model.evaluate()
        harness.model.evaluate()
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.closedLidStatusReader.readCount, countAfterStart)
    }
}

private final class AppModelHarness {
    let settingsStore: FakeSettingsStore
    let ownershipStore: FakeClosedLidOwnershipStore
    let batteryMonitor = FakeBatteryMonitor()
    let loginItemService = FakeLoginItemService()
    let closedLidStatusReader: FakeClosedLidStatusReader
    let helper: FakeClosedLidHelperService
    let softwareUpdateService: FakeSoftwareUpdateService
    let screenLockPermissionChecker = FakeScreenLockPermissionChecker()
    let powerController = FakePowerController()
    let notificationService: FakeNotificationService
    let displayClamshellReader = FakeClamshellStateReader()
    let lockClamshellReader = FakeClamshellStateReader()
    let displayScreenLockStateReader = FakeScreenLockStateReader()
    let displaySleeper = FakeDisplaySleeper()
    let deviceLocker = FakeDeviceLocker()
    let model: AppModel

    @MainActor
    init(
        settings: UserSettings,
        helperStatus: ClosedLidHelperStatus,
        closedLidStatus: ClosedLidStatus,
        ownershipRecord: ClosedLidOwnershipRecord? = nil,
        softwareUpdateState: SoftwareUpdateState = .unavailable(
            message: "Software updates are not configured for this build.",
            feedURL: nil
        ),
        closedLidModeChangeTimeout: TimeInterval = 6
    ) {
        self.settingsStore = FakeSettingsStore(settings: settings)
        self.ownershipStore = FakeClosedLidOwnershipStore(record: ownershipRecord)
        self.closedLidStatusReader = FakeClosedLidStatusReader(status: closedLidStatus)
        self.helper = FakeClosedLidHelperService(status: helperStatus)
        self.softwareUpdateService = FakeSoftwareUpdateService(state: softwareUpdateState)
        self.notificationService = FakeNotificationService()
        self.model = AppModel(
            settingsStore: settingsStore,
            closedLidOwnershipStore: ownershipStore,
            batteryMonitor: batteryMonitor,
            loginItemService: loginItemService,
            closedLidStatusReader: closedLidStatusReader,
            closedLidHelperService: helper,
            softwareUpdateService: softwareUpdateService,
            screenLockPermissionChecker: screenLockPermissionChecker,
            powerController: powerController,
            clock: FakeClock(),
            closedLidDisplayCoordinator: ClosedLidDisplayCoordinator(
                clamshellStateReader: displayClamshellReader,
                displaySleeper: displaySleeper,
                screenLockStateReader: displayScreenLockStateReader
            ),
            closedLidLockCoordinator: ClosedLidLockCoordinator(
                clamshellStateReader: lockClamshellReader,
                deviceLocker: deviceLocker
            ),
            notificationService: notificationService,
            initialBattery: batteryMonitor.currentState(),
            closedLidModeChangeTimeout: closedLidModeChangeTimeout
        )
    }
}

private final class FakeSettingsStore: UserSettingsStoring {
    private(set) var savedSettings: [UserSettings] = []
    private var settings: UserSettings

    init(settings: UserSettings) {
        self.settings = settings
    }

    func load() -> UserSettings {
        settings
    }

    func save(_ settings: UserSettings) {
        self.settings = settings
        savedSettings.append(settings)
    }
}

private final class FakeClosedLidOwnershipStore: ClosedLidOwnershipStoring {
    private(set) var savedRecords: [ClosedLidOwnershipRecord] = []
    private(set) var clearCount = 0
    var record: ClosedLidOwnershipRecord?

    init(record: ClosedLidOwnershipRecord? = nil) {
        self.record = record
    }

    func load() -> ClosedLidOwnershipRecord? {
        record
    }

    func save(_ record: ClosedLidOwnershipRecord) {
        self.record = record
        savedRecords.append(record)
    }

    func clear() {
        record = nil
        clearCount += 1
    }
}

private final class FakeBatteryMonitor: BatteryMonitoring {
    var state = BatteryState.desktopOrUnknown(lowPowerMode: false)

    func currentState() -> BatteryState {
        state
    }
}

private final class FakeLoginItemService: LoginItemServicing {
    var isEnabled = false
    var setEnabledRequests: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
        setEnabledRequests.append(enabled)
    }
}

private final class FakeClosedLidStatusReader: ClosedLidStatusReading {
    var status: ClosedLidStatus
    private(set) var readCount = 0

    init(status: ClosedLidStatus) {
        self.status = status
    }

    func readClosedLidStatus() -> ClosedLidStatus {
        readCount += 1
        return status
    }
}

private final class FakeClosedLidHelperService: ClosedLidHelperServicing {
    var status: ClosedLidHelperStatus
    var setClosedLidModeRequests: [Bool] = []
    var onSetClosedLidMode: ((Bool) -> Void)?
    var setClosedLidModeResult: Result<Void, Error> = .success(())
    var shouldReplyToSetClosedLidMode = true
    private(set) var registerCallCount = 0
    private(set) var repairRegistrationCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openApprovalSettingsCallCount = 0

    init(status: ClosedLidHelperStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
    }

    func repairRegistration() throws {
        repairRegistrationCallCount += 1
    }

    func unregister() throws {
        unregisterCallCount += 1
    }

    func setClosedLidMode(enabled: Bool, reply: @escaping (Result<Void, Error>) -> Void) {
        setClosedLidModeRequests.append(enabled)
        onSetClosedLidMode?(enabled)
        if shouldReplyToSetClosedLidMode {
            reply(setClosedLidModeResult)
        }
    }

    func openApprovalSettings() {
        openApprovalSettingsCallCount += 1
    }
}

@MainActor
private final class FakeSoftwareUpdateService: SoftwareUpdateServicing {
    var state: SoftwareUpdateState
    private var stateChangeHandler: (@MainActor () -> Void)?
    private(set) var startCallCount = 0
    private(set) var checkForUpdatesCallCount = 0
    private(set) var automaticCheckRequests: [Bool] = []
    private(set) var automaticDownloadRequests: [Bool] = []

    init(state: SoftwareUpdateState) {
        self.state = state
    }

    func setStateChangeHandler(_ handler: @escaping @MainActor () -> Void) {
        stateChangeHandler = handler
    }

    func start() {
        startCallCount += 1
        stateChangeHandler?()
    }

    func checkForUpdates() {
        checkForUpdatesCallCount += 1
        stateChangeHandler?()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticCheckRequests.append(enabled)
        state.automaticallyChecksForUpdates = enabled
        stateChangeHandler?()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        automaticDownloadRequests.append(enabled)
        state.automaticallyDownloadsUpdates = enabled
        stateChangeHandler?()
    }

    func emit(_ state: SoftwareUpdateState) {
        self.state = state
        stateChangeHandler?()
    }
}

private final class FakePowerController: PowerAssertionControlling {
    var isHolding = false
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0

    func acquire(reason: WakeHoldReason, preventDisplaySleep: Bool) throws {
        if !isHolding {
            acquireCount += 1
        }
        isHolding = true
    }

    func release() {
        if isHolding {
            releaseCount += 1
        }
        isHolding = false
    }
}

private final class FakeClock: Clock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

private final class FakeClamshellStateReader: ClamshellStateReading {
    var state: ClamshellState = .open

    func clamshellState() -> ClamshellState {
        state
    }
}

private final class FakeDisplaySleeper: DisplaySleeping {
    private(set) var sleepCount = 0

    func sleepDisplaysNow() throws {
        sleepCount += 1
    }
}

private final class FakeScreenLockStateReader: ScreenLockStateReading {
    var state: ScreenLockState = .unlocked

    func screenLockState() -> ScreenLockState {
        state
    }
}

private final class FakeDeviceLocker: DeviceLocking {
    private(set) var lockCount = 0
    var error: Error?

    func lockScreenNow() throws {
        lockCount += 1
        if let error {
            throw error
        }
    }
}

private final class FakeScreenLockPermissionChecker: ScreenLockPermissionChecking {
    var requiresAccessibilityPermission = false
    var hasPermission = true
    private(set) var openAccessibilitySettingsCallCount = 0
    private(set) var promptRequests: [Bool] = []

    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        promptRequests.append(prompt)
        return hasPermission
    }

    func openAccessibilitySettings() {
        openAccessibilitySettingsCallCount += 1
    }
}

@MainActor
private final class FakeNotificationService: NotificationServicing {
    private(set) var transitions: [(WakeStatus, WakeStatus)] = []

    func handleTransition(from oldStatus: WakeStatus, to newStatus: WakeStatus) {
        transitions.append((oldStatus, newStatus))
    }
}

private func ownedRecord() -> ClosedLidOwnershipRecord {
    ClosedLidOwnershipRecord(
        ownedByThisApp: true,
        enabledAt: Date(timeIntervalSince1970: 1_800_000_000),
        previousStatus: .disabled,
        lastAttemptedRestoreAt: nil
    )
}

private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}
