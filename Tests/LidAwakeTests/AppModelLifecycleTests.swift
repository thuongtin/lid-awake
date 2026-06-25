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
}

private final class AppModelHarness {
    let settingsStore: FakeSettingsStore
    let ownershipStore: FakeClosedLidOwnershipStore
    let batteryMonitor = FakeBatteryMonitor()
    let loginItemService = FakeLoginItemService()
    let closedLidStatusReader: FakeClosedLidStatusReader
    let helper: FakeClosedLidHelperService
    let powerController = FakePowerController()
    let notificationService: FakeNotificationService
    let model: AppModel

    @MainActor
    init(
        settings: UserSettings,
        helperStatus: ClosedLidHelperStatus,
        closedLidStatus: ClosedLidStatus,
        ownershipRecord: ClosedLidOwnershipRecord? = nil
    ) {
        self.settingsStore = FakeSettingsStore(settings: settings)
        self.ownershipStore = FakeClosedLidOwnershipStore(record: ownershipRecord)
        self.closedLidStatusReader = FakeClosedLidStatusReader(status: closedLidStatus)
        self.helper = FakeClosedLidHelperService(status: helperStatus)
        self.notificationService = FakeNotificationService()
        self.model = AppModel(
            settingsStore: settingsStore,
            closedLidOwnershipStore: ownershipStore,
            batteryMonitor: batteryMonitor,
            loginItemService: loginItemService,
            closedLidStatusReader: closedLidStatusReader,
            closedLidHelperService: helper,
            powerController: powerController,
            clock: FakeClock(),
            closedLidDisplayCoordinator: ClosedLidDisplayCoordinator(
                clamshellStateReader: FakeClamshellStateReader(),
                displaySleeper: FakeDisplaySleeper()
            ),
            notificationService: notificationService,
            initialBattery: batteryMonitor.currentState()
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

    init(status: ClosedLidStatus) {
        self.status = status
    }

    func readClosedLidStatus() -> ClosedLidStatus {
        status
    }
}

private final class FakeClosedLidHelperService: ClosedLidHelperServicing {
    var status: ClosedLidHelperStatus
    var setClosedLidModeRequests: [Bool] = []
    var onSetClosedLidMode: ((Bool) -> Void)?
    var setClosedLidModeResult: Result<Void, Error> = .success(())
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openApprovalSettingsCallCount = 0

    init(status: ClosedLidHelperStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
    }

    func unregister() throws {
        unregisterCallCount += 1
    }

    func setClosedLidMode(enabled: Bool, reply: @escaping (Result<Void, Error>) -> Void) {
        setClosedLidModeRequests.append(enabled)
        onSetClosedLidMode?(enabled)
        reply(setClosedLidModeResult)
    }

    func openApprovalSettings() {
        openApprovalSettingsCallCount += 1
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
    func clamshellState() -> ClamshellState {
        .open
    }
}

private final class FakeDisplaySleeper: DisplaySleeping {
    func sleepDisplaysNow() throws {}
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
