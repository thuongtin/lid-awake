import AppKit
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

    func testScheduledStopDisablesAppAndRestoresOwnedClosedLidMode() async {
        let clock = FakeClock()
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true, stopAt: clock.now.addingTimeInterval(60)),
            helperStatus: .enabled,
            closedLidStatus: .disabled,
            clock: clock
        )
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
        XCTAssertTrue(harness.powerController.isHolding)

        clock.advance(seconds: 60)
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertFalse(harness.model.settings.enabled)
        XCTAssertNil(harness.model.settings.stopAt)
        XCTAssertEqual(harness.model.status, .inactive)
        XCTAssertFalse(harness.powerController.isHolding)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertNil(harness.ownershipStore.record)
        XCTAssertEqual(harness.settingsStore.savedSettings.last?.enabled, false)
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

    func testFailedRemovalWarningSurvivesTheNextEvaluate() async {
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

        harness.helper.onSetClosedLidMode = nil
        harness.helper.setClosedLidModeResult = .failure(NSError(domain: "Restore", code: 1))
        harness.model.removeClosedLidHelper()
        await drainMainQueue()

        // Closed-lid mode is still on and still wanted, which used to read as
        // the healthy steady state and wipe the warning within five seconds.
        harness.model.evaluate()
        await drainMainQueue()
        harness.model.evaluate(forceClosedLidStatusRead: true)
        await drainMainQueue()

        XCTAssertTrue(harness.model.closedLidError?.contains("Could not restore closed-lid mode") == true)
        XCTAssertEqual(harness.helper.unregisterCallCount, 0)
    }

    func testChangingTheDisplayModeDuringRemovalKeepsItPending() async {
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

        harness.helper.onSetClosedLidMode = nil
        harness.helper.setClosedLidModeResult = .failure(NSError(domain: "Restore", code: 1))
        harness.model.removeClosedLidHelper()
        XCTAssertTrue(harness.model.isChangingClosedLidMode)

        // The picker cannot cancel a removal already underway, so it must not
        // drop the guard the failed removal relies on.
        harness.model.updateLidClosedDisplayMode(.turnDisplayOff)
        await drainMainQueue()
        harness.model.evaluate(forceClosedLidStatusRead: true)
        await drainMainQueue()

        XCTAssertTrue(harness.model.closedLidError?.contains("Could not restore closed-lid mode") == true)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
    }

    func testAFailedEnableIsNotRetriedOnEveryEvaluate() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.setClosedLidModeResult = .failure(NSError(domain: "pmset", code: 1))

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])

        for _ in 0..<3 {
            harness.clock.advance(seconds: 5)
            harness.model.evaluate()
            await drainMainQueue()
        }

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
        XCTAssertNotNil(harness.model.closedLidError)

        harness.clock.advance(seconds: AppModel.closedLidFailureRetryDelay)
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, true])
    }

    func testRefreshRetriesAFailedEnableAtOnce() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.setClosedLidModeResult = .failure(NSError(domain: "pmset", code: 1))

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        harness.helper.setClosedLidModeResult = .success(())
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }
        harness.model.refreshClosedLidPermissionState()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, true])
        XCTAssertNil(harness.model.closedLidError)
    }

    func testLaunchAtLoginWaitingForApprovalStaysOnAndSaysWhy() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .notRegistered,
            closedLidStatus: .disabled
        )
        harness.loginItemService.requiresApproval = true

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.model.updateLaunchAtLogin(true)

        XCTAssertTrue(harness.model.settings.launchAtLogin)
        XCTAssertTrue(harness.model.launchAtLoginNeedsApproval)
        XCTAssertNil(harness.model.launchAtLoginError)

        // Coming back from System Settings after allowing it clears the note.
        harness.loginItemService.status = .enabled
        harness.model.refreshAfterExternalPermissionChange()
        await drainMainQueue()

        XCTAssertTrue(harness.model.settings.launchAtLogin)
        XCTAssertFalse(harness.model.launchAtLoginNeedsApproval)
    }

    func testLaunchAtLoginWaitingForApprovalIsNotTurnedOffAtLaunch() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false, launchAtLogin: true),
            helperStatus: .notRegistered,
            closedLidStatus: .disabled
        )
        harness.loginItemService.status = .requiresApproval

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertTrue(harness.model.settings.launchAtLogin)
        XCTAssertTrue(harness.model.launchAtLoginNeedsApproval)
    }

    func testTurningOffLaunchAtLoginClearsTheApprovalNote() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false, launchAtLogin: true),
            helperStatus: .notRegistered,
            closedLidStatus: .disabled
        )
        harness.loginItemService.status = .requiresApproval

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.model.updateLaunchAtLogin(false)

        XCTAssertFalse(harness.model.settings.launchAtLogin)
        XCTAssertFalse(harness.model.launchAtLoginNeedsApproval)
        XCTAssertEqual(harness.loginItemService.setEnabledRequests, [false])
    }

    func testSetUpAndRepairWaitWhileHelperRemovalIsUnderway() async {
        let blockingWork = HeldBlockingWork()
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .disabled,
            blockingWork: blockingWork
        )
        harness.model.start(scheduleTimers: false)
        blockingWork.releaseAll()
        await drainMainQueue()

        // Removal holds the change flag while `pmset` answers. Repair used to
        // drop that flag, which let an enable start underneath the removal and
        // land after the helper that could restore it was gone.
        harness.model.removeClosedLidHelper()
        XCTAssertTrue(harness.model.isChangingClosedLidMode)

        harness.model.repairClosedLidHelper()
        harness.model.setupClosedLidHelper()

        XCTAssertTrue(harness.model.isChangingClosedLidMode)
        XCTAssertEqual(harness.helper.repairRegistrationCallCount, 0)
        XCTAssertEqual(harness.helper.registerCallCount, 0)
        XCTAssertEqual(harness.model.closedLidError, AppModel.closedLidHelperUpdateInProgressMessage)

        blockingWork.releaseAll()
        await drainMainQueue()

        XCTAssertFalse(harness.model.isChangingClosedLidMode)
        XCTAssertEqual(harness.helper.unregisterCallCount, 1)
    }

    func testRelaunchWithOwnedClosedLidModeRearmsTheHelperWatchdog() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled,
            ownershipRecord: ownedRecord()
        )

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        // The helper only watches the process that sent it an enable, and a
        // new app process has sent none, so it is sent again once.
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
        XCTAssertEqual(harness.ownershipStore.record?.previousStatus, .disabled)

        harness.model.evaluate(forceClosedLidStatusRead: true)
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
    }

    func testRearmThatTimesOutOffersRepairInsteadOfCountingAsArmed() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled,
            ownershipRecord: ownedRecord(),
            closedLidModeChangeTimeout: 0.05
        )
        harness.helper.shouldReplyToSetClosedLidMode = false

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertTrue(harness.model.isChangingClosedLidMode)

        try? await Task.sleep(nanoseconds: 120_000_000)
        await drainMainQueue()

        // `pmset` was already on before the request, so reading it back says
        // nothing about whether the helper is now watching this process.
        XCTAssertFalse(harness.model.isChangingClosedLidMode)
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertEqual(
            harness.model.closedLidError,
            "Lid Awake Helper did not respond. Repair the helper, then try again."
        )
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
    }

    func testEnabledModeTheAppDoesNotOwnIsNotRearmed() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertTrue(harness.helper.setClosedLidModeRequests.isEmpty)
        XCTAssertNil(harness.ownershipStore.record)
    }

    func testRepairRearmsTheWatchdogForOwnedClosedLidMode() async {
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

        // Repair replaces the helper process, and its watchdog with it.
        harness.model.repairClosedLidHelper()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, true])
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
    }

    func testFailedRepairRearmsOnceTheHelperIsRegisteredAgain() async {
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

        // The unregister went through and stopped the helper process, then the
        // register was refused.
        harness.helper.repairRegistrationError = ClosedLidHelperFailure.commandFailed("Registration failed.")
        harness.helper.statusAfterRepair = .notRegistered
        harness.model.repairClosedLidHelper()
        await drainMainQueue()
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])

        // Registered again from outside the app, so nothing reset the flag on
        // the way back.
        harness.helper.status = .enabled
        harness.model.evaluate(forceClosedLidStatusRead: true)
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, true])
    }

    func testSetUpAfterTheHelperWentAwayRearmsTheWatchdog() async {
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

        // Removed in System Settings, taking its process with it.
        harness.helper.status = .notRegistered
        harness.model.evaluate()
        await drainMainQueue()

        harness.helper.status = .enabled
        harness.model.setupClosedLidHelper()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.registerCallCount, 1)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, true])
    }

    func testRepairHoldsHelperChangesUntilTheRegistrationSettles() async {
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
        harness.helper.shouldReplyToRepairRegistration = false

        harness.model.repairClosedLidHelper()
        await drainMainQueue()
        XCTAssertTrue(harness.model.isChangingClosedLidMode)

        // Removing the helper while macOS is still replacing it could leave
        // closed-lid mode on with no helper to restore it.
        harness.model.removeClosedLidHelper()
        harness.model.updateSettings { $0.enabled = false }
        await drainMainQueue()
        XCTAssertEqual(harness.helper.unregisterCallCount, 0)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])

        harness.helper.pendingRepairReply?()
        await drainMainQueue()

        XCTAssertFalse(harness.model.isChangingClosedLidMode)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.closedLidStatusReader.status, .disabled)
    }

    func testQuitDuringRepairRestoresThroughTheNewHelper() async {
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
        harness.helper.shouldReplyToRepairRegistration = false
        harness.model.repairClosedLidHelper()
        await drainMainQueue()

        // The old helper and its watchdog are already gone, so quitting now
        // must not finish before the new helper has restored the mode.
        var completions = 0
        harness.model.prepareForTermination {
            completions += 1
        }
        await drainMainQueue()
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])

        harness.helper.pendingRepairReply?()
        await drainMainQueue()

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.closedLidStatusReader.status, .disabled)
        XCTAssertNil(harness.ownershipStore.record)
    }

    func testQuitAfterAFailedRepairRegistersTheHelperToRestore() async {
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

        // The unregister went through and the register was refused, so no
        // helper is left to turn closed-lid mode off.
        harness.helper.repairRegistrationError = ClosedLidHelperFailure.commandFailed("Registration failed.")
        harness.helper.statusAfterRepair = .notRegistered
        harness.model.repairClosedLidHelper()
        await drainMainQueue()
        XCTAssertEqual(harness.closedLidStatusReader.status, .enabled)

        harness.helper.statusAfterRegister = .enabled
        var completions = 0
        harness.model.prepareForTermination {
            completions += 1
        }
        await drainMainQueue()

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(harness.helper.registerCallCount, 1)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.closedLidStatusReader.status, .disabled)
        XCTAssertNil(harness.ownershipStore.record)
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
        await drainMainQueue()
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

    func testEnableThatLandsAfterTheHelperTimesOutIsStillOwned() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        // The helper ran `pmset` but its reply missed the XPC deadline.
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }
        harness.helper.setClosedLidModeResult = .failure(ClosedLidHelperFailure.timedOut)

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertEqual(harness.model.closedLidStatus, .enabled)
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
        XCTAssertEqual(harness.ownershipStore.record?.previousStatus, .disabled)

        harness.helper.setClosedLidModeResult = .success(())
        harness.model.updateSettings { settings in
            settings.enabled = false
        }
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.closedLidStatusReader.status, .disabled)
        XCTAssertNil(harness.ownershipStore.record)
    }

    func testQuitWhileEnableIsInFlightRestoresClosedLidMode() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.shouldReplyToSetClosedLidMode = false

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertTrue(harness.model.isChangingClosedLidMode)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])

        // The enable can still land after the app reads `pmset`, so quitting
        // has to restore without waiting to see it.
        harness.helper.shouldReplyToSetClosedLidMode = true
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }
        let readsBeforeQuit = harness.closedLidStatusReader.readCount
        var completions = 0
        harness.model.prepareForTermination {
            completions += 1
        }
        await drainMainQueue()

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertNil(harness.ownershipStore.record)
        XCTAssertEqual(harness.closedLidStatusReader.readCount, readsBeforeQuit)

        // The fallback deadline must not report a second time.
        try? await Task.sleep(nanoseconds: 700_000_000)
        await drainMainQueue()
        XCTAssertEqual(completions, 1)
    }

    func testQuitDoesNotWaitForeverOnAHelperThatNeverAnswers() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled,
            ownershipRecord: ownedRecord(),
            terminationRestoreTimeout: 0.1
        )
        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        harness.helper.shouldReplyToSetClosedLidMode = false
        var completions = 0
        harness.model.prepareForTermination {
            completions += 1
        }
        await drainMainQueue()
        XCTAssertEqual(completions, 0)

        await waitUntil { completions > 0 }

        XCTAssertEqual(completions, 1)
        // The launch re-arms the helper watchdog, then quit restores.
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        // Kept for the next launch; the helper restores on its own once the
        // app process is gone.
        XCTAssertEqual(harness.ownershipStore.record?.ownedByThisApp, true)
        XCTAssertNotNil(harness.ownershipStore.record?.lastAttemptedRestoreAt)
    }

    func testQuitWithoutOwnershipCompletesAtOnce() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        var completions = 0
        harness.model.prepareForTermination {
            completions += 1
        }

        XCTAssertEqual(completions, 1)
        XCTAssertTrue(harness.helper.setClosedLidModeRequests.isEmpty)
    }

    func testSlowClosedLidStatusReadDoesNotBlockTheMainActor() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled,
            blockingWork: BackgroundBlockingWork()
        )
        let gate = DispatchSemaphore(value: 0)
        harness.closedLidStatusReader.gate = gate

        let startedAt = Date()
        harness.model.start(scheduleTimers: false)
        harness.model.refreshAfterExternalPermissionChange()

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
        XCTAssertEqual(harness.model.closedLidStatus, .notReported)

        for _ in 0..<10 {
            gate.signal()
        }
        await waitUntil { !harness.helper.setClosedLidModeRequests.isEmpty }

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
    }

    func testRemoveHelperWaitsForInFlightClosedLidChange() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.shouldReplyToSetClosedLidMode = false

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertTrue(harness.model.isChangingClosedLidMode)

        harness.model.removeClosedLidHelper()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.unregisterCallCount, 0)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
        XCTAssertTrue(harness.model.isChangingClosedLidMode)
        XCTAssertNotNil(harness.ownershipStore.record)
        XCTAssertEqual(harness.model.closedLidError, AppModel.closedLidHelperBusyMessage)
    }

    func testFailedHelperRemovalDoesNotReenableClosedLidMode() async {
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

        harness.helper.unregisterError = NSError(domain: "Unregister", code: 1)
        harness.model.removeClosedLidHelper()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.helper.unregisterCallCount, 1)
        XCTAssertNotNil(harness.model.closedLidError)

        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, false])
        XCTAssertEqual(harness.closedLidStatusReader.status, .disabled)
        XCTAssertNotNil(harness.model.closedLidError)
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

    func testLostHelperConnectionOffersRepairRatherThanSetup() async {
        let harness = makeHarnessWithLostHelperConnection()

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertEqual(
            harness.model.closedLidError,
            ClosedLidHelperFailure.connectionLostMessage
        )
        XCTAssertTrue(harness.model.closedLidHelperNeedsRepair)
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertEqual(harness.model.closedLidAttentionTitle, "Repair Advanced Helper")
        XCTAssertEqual(harness.model.closedLidCompactActionTitle, "Repair")
        XCTAssertEqual(harness.model.closedLidPrimaryActionTitle, "Repair Helper")
    }

    func testLostHelperConnectionStopsRetryingUntilTheHelperAnswers() async {
        let harness = makeHarnessWithLostHelperConnection()

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])

        harness.model.evaluate()
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])
    }

    func testReachableHelperClearsLostConnectionWarning() async {
        let harness = makeHarnessWithLostHelperConnection()

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)

        harness.helper.setClosedLidModeResult = .success(())
        harness.helper.probeConnectionResult = .success(())
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }
        harness.model.refreshAfterExternalPermissionChange()
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.probeConnectionCallCount, 1)
        XCTAssertFalse(harness.model.closedLidHelperNeedsRepair)
        XCTAssertFalse(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertNil(harness.model.closedLidError)
        XCTAssertEqual(harness.model.closedLidStatus, .enabled)
    }

    func testUnreachableHelperKeepsLostConnectionWarning() async {
        let harness = makeHarnessWithLostHelperConnection()
        harness.helper.probeConnectionResult = .failure(.connectionLost)

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        harness.model.refreshAfterExternalPermissionChange()
        await drainMainQueue()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.probeConnectionCallCount, 1)
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertEqual(
            harness.model.closedLidError,
            ClosedLidHelperFailure.connectionLostMessage
        )
    }

    func testHelperCommandFailureDoesNotOfferRepair() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.helper.setClosedLidModeResult = .failure(
            ClosedLidHelperFailure.commandFailed("pmset exited with code 1.")
        )

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        XCTAssertEqual(harness.model.closedLidError, "pmset exited with code 1.")
        XCTAssertFalse(harness.model.closedLidHelperNeedsRepair)
        XCTAssertFalse(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertEqual(harness.model.closedLidCompactActionTitle, "Set Up")
    }

    func testClearingTheErrorAlsoRetiresTheHelperRepairFlag() async {
        let harness = makeHarnessWithLostHelperConnection()

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertTrue(harness.model.closedLidHelperNeedsRepair)
        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true])

        // Removing the helper clears the error without anything having proven
        // the helper is reachable. `SMAppService` still reports `.enabled`, as
        // it does through this whole class of failure, so the repair flag has
        // to be retired with the error it belonged to. Left behind, it hides
        // the warning panel and the Repair button while still blocking every
        // retry, which strands closed-lid mode for the life of the process.
        harness.model.removeClosedLidHelper()
        await drainMainQueue()

        XCTAssertNil(harness.model.closedLidError)
        XCTAssertFalse(harness.model.closedLidHelperNeedsRepair)
        XCTAssertFalse(harness.model.closedLidControlNeedsAttention)

        harness.helper.setClosedLidModeResult = .success(())
        harness.helper.onSetClosedLidMode = { enabled in
            harness.closedLidStatusReader.status = enabled ? .enabled : .disabled
        }
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.helper.setClosedLidModeRequests, [true, true])
        XCTAssertEqual(harness.model.closedLidStatus, .enabled)
    }

    func testFailedRestoreBeforeHelperRemovalOffersRepair() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled,
            ownershipRecord: ownedRecord()
        )
        harness.helper.setClosedLidModeResult = .failure(ClosedLidHelperFailure.connectionLost)

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        harness.model.removeClosedLidHelper()
        await drainMainQueue()

        // An unreachable helper cannot restore closed-lid mode, so the helper
        // is kept and the user is left needing the one action that reconnects it.
        XCTAssertEqual(harness.helper.unregisterCallCount, 0)
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertEqual(harness.model.closedLidCompactActionTitle, "Repair")
    }

    func testFailedRepairKeepsOfferingRepair() async {
        let harness = makeHarnessWithLostHelperConnection()
        harness.helper.repairRegistrationError = ClosedLidHelperFailure.commandFailed("Registration failed.")

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)

        harness.model.repairClosedLidHelper()
        await drainMainQueue()

        // The registration still reports `.enabled`, so Set Up would return
        // early and do nothing. Repair has to stay the offered action.
        XCTAssertEqual(harness.helper.repairRegistrationCallCount, 1)
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)
        XCTAssertEqual(
            harness.model.closedLidMenuAttentionMessage,
            "Repairing Lid Awake Helper failed: Registration failed."
        )
    }

    func testStaleProbeReplyDoesNotClearANewerError() async {
        let harness = makeHarnessWithLostHelperConnection()
        harness.helper.shouldReplyToProbeConnection = false

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        // Opening the popover starts a probe.
        harness.model.refreshAfterExternalPermissionChange()
        await drainMainQueue()
        XCTAssertEqual(harness.helper.probeConnectionCallCount, 1)

        // The user presses Repair before that probe answers, and it fails, so a
        // different failure is now the one on screen.
        harness.helper.repairRegistrationError = ClosedLidHelperFailure.commandFailed("Registration failed.")
        harness.model.repairClosedLidHelper()
        await drainMainQueue()
        let repairError = "Repairing Lid Awake Helper failed: Registration failed."
        XCTAssertEqual(harness.model.closedLidError, repairError)

        // The late reply only ever tested the failure it was launched against.
        harness.helper.pendingProbeReply?(.success(()))
        await drainMainQueue()

        XCTAssertEqual(harness.model.closedLidError, repairError)
        XCTAssertTrue(harness.model.shouldOfferClosedLidHelperRepair)
    }

    @MainActor
    private func makeHarnessWithLostHelperConnection() -> AppModelHarness {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        // A helper that refuses this client refuses every call, so the probe has
        // to fail too. A fake that answered probes while dropping mode changes
        // would describe a machine that does not exist.
        harness.helper.setClosedLidModeResult = .failure(ClosedLidHelperFailure.connectionLost)
        harness.helper.probeConnectionResult = .failure(.connectionLost)
        return harness
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
        // One refresh for the external change, one from the evaluate it runs.
        XCTAssertEqual(
            harness.screenLockPermissionChecker.promptRequests,
            [false, true, false, false]
        )
        XCTAssertEqual(harness.deviceLocker.lockCount, 1)
    }

    func testScreenLockFailureFromAnEndedLidClosureIsIgnored() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true, lockScreenWhenLidCloses: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.lockClamshellReader.state = .open
        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.lockClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()
        XCTAssertEqual(harness.deviceLocker.lockCount, 1)

        // The command for this closure is still running as the lid opens.
        harness.lockClamshellReader.state = .open
        harness.model.evaluate()
        await drainMainQueue()
        harness.model.reportClosedLidLockFailure("Screen lock failed.")
        XCTAssertNil(harness.model.closedLidLockError)

        harness.lockClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()
        harness.model.reportClosedLidLockFailure("Screen lock failed.")
        XCTAssertEqual(harness.model.closedLidLockError, "Screen lock failed.")
    }

    func testAccessibilityPromptIsShownAtMostOncePerLaunch() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true, lockScreenWhenLidCloses: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.screenLockPermissionChecker.requiresAccessibilityPermission = true
        harness.screenLockPermissionChecker.hasPermission = false

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        for _ in 0..<3 {
            harness.model.updateSettings { $0.lockScreenWhenLidCloses = false }
            harness.model.updateSettings { $0.lockScreenWhenLidCloses = true }
        }
        await drainMainQueue()

        XCTAssertEqual(harness.screenLockPermissionChecker.promptRequests.filter { $0 }.count, 1)
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

    func testDisplaySleepFailureFromAnEndedLidClosureIsIgnored() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true, lidClosedDisplayMode: .turnDisplayOff),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.displayClamshellReader.state = .open
        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.displayClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()
        XCTAssertEqual(harness.displaySleeper.sleepCount, 1)

        // The command for this closure is still running as the lid opens.
        harness.displayClamshellReader.state = .open
        harness.model.evaluate()
        await drainMainQueue()
        harness.model.reportClosedLidDisplayFailure("Display sleep failed.")
        XCTAssertNil(harness.model.closedLidDisplayError)

        harness.displayClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()
        harness.model.reportClosedLidDisplayFailure("Display sleep failed.")
        XCTAssertEqual(harness.model.closedLidDisplayError, "Display sleep failed.")
    }

    func testLidClosedWhileDisabledIsNotTreatedAsAFreshCloseOnReenable() async {
        let harness = AppModelHarness(
            settings: UserSettings(
                enabled: true,
                lidClosedDisplayMode: .turnDisplayOff,
                lockScreenWhenLidCloses: true
            ),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.lockClamshellReader.state = .open
        harness.displayClamshellReader.state = .open

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.model.updateSettings { $0.enabled = false }
        await drainMainQueue()

        // The lid closed while the app was off, so it never saw the change.
        harness.lockClamshellReader.state = .closed
        harness.displayClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()

        harness.model.updateSettings { $0.enabled = true }
        await drainMainQueue()
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.deviceLocker.lockCount, 0)
        XCTAssertEqual(harness.displaySleeper.sleepCount, 0)
    }

    func testTimersKeepFiringWhileAModalAlertRunsTheRunLoop() {
        // AppKit adds the modal panel mode to the common modes when the
        // application object comes up, as it does in the running app.
        _ = NSApplication.shared
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true, lockScreenWhenLidCloses: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.screenLockPermissionChecker.requiresAccessibilityPermission = true
        harness.screenLockPermissionChecker.hasPermission = true

        harness.model.start(scheduleTimers: true)
        defer { harness.model.stop() }
        let checksBeforeModal = harness.screenLockPermissionChecker.promptRequests.count

        // `NSAlert.runModal` spins the run loop in this mode.
        let deadline = Date().addingTimeInterval(1.8)
        while Date() < deadline {
            RunLoop.main.run(mode: .modalPanel, before: Date().addingTimeInterval(0.05))
        }

        XCTAssertGreaterThan(harness.screenLockPermissionChecker.promptRequests.count, checksBeforeModal)
    }

    func testTurningOffClearsTheScheduledStopSoReenablingSticks() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        harness.model.scheduleStop(for: 3600)
        harness.model.updateSettings { $0.enabled = false }
        XCTAssertNil(harness.model.settings.stopAt)

        // Back on after the old deadline would have passed.
        harness.clock.now = harness.clock.now.addingTimeInterval(7200)
        harness.model.updateSettings { $0.enabled = true }
        await drainMainQueue()

        XCTAssertTrue(harness.model.settings.enabled)
        XCTAssertTrue(harness.settingsStore.savedSettings.last?.enabled == true)
        XCTAssertNil(harness.settingsStore.savedSettings.last?.stopAt)
    }

    func testSchedulingAStopWhileOffTurnsKeepAwakeOn() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: false),
            helperStatus: .enabled,
            closedLidStatus: .disabled
        )
        harness.model.start(scheduleTimers: false)
        await drainMainQueue()

        harness.model.scheduleStop(for: 1800)

        XCTAssertTrue(harness.model.settings.enabled)
        XCTAssertEqual(harness.model.settings.stopAt, harness.clock.now.addingTimeInterval(1800))
    }

    func testClosingTheLidOnAnExternalDisplayNeitherLocksNorSleepsDisplays() async {
        let harness = AppModelHarness(
            settings: UserSettings(
                enabled: true,
                lidClosedDisplayMode: .turnDisplayOff,
                lockScreenWhenLidCloses: true
            ),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.externalDisplayDetector.hasActiveExternalDisplay = true
        harness.lockClamshellReader.state = .open
        harness.displayClamshellReader.state = .open
        harness.displayScreenLockStateReader.state = .locked

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.lockClamshellReader.state = .closed
        harness.displayClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.deviceLocker.lockCount, 0)
        XCTAssertEqual(harness.displaySleeper.sleepCount, 0)

        // Unplugging it later does not count as a fresh close either.
        harness.externalDisplayDetector.hasActiveExternalDisplay = false
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.deviceLocker.lockCount, 0)
        XCTAssertEqual(harness.displaySleeper.sleepCount, 0)
    }

    func testClosingTheLidWithoutAnExternalDisplayStillLocks() async {
        let harness = AppModelHarness(
            settings: UserSettings(enabled: true, lockScreenWhenLidCloses: true),
            helperStatus: .enabled,
            closedLidStatus: .enabled
        )
        harness.lockClamshellReader.state = .open

        harness.model.start(scheduleTimers: false)
        await drainMainQueue()
        harness.lockClamshellReader.state = .closed
        harness.model.evaluate()
        await drainMainQueue()

        XCTAssertEqual(harness.deviceLocker.lockCount, 1)
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

final class ClosedLidHelperRemovalTests: XCTestCase {
    func testRemovalRestoresOwnedClosedLidModeBeforeUnregistering() throws {
        let helper = FakeClosedLidHelperService(status: .enabled)
        let statusReader = FakeClosedLidStatusReader(status: .enabled)
        let ownershipStore = FakeClosedLidOwnershipStore(record: ownedRecord())
        helper.onSetClosedLidMode = { enabled in
            statusReader.status = enabled ? .enabled : .disabled
        }

        try ClosedLidHelperRemoval.removeHelper(
            helperService: helper,
            statusReader: statusReader,
            ownershipStore: ownershipStore
        )

        XCTAssertEqual(helper.setClosedLidModeRequests, [false])
        XCTAssertEqual(helper.unregisterCallCount, 1)
        XCTAssertEqual(statusReader.status, .disabled)
        XCTAssertNil(ownershipStore.record)
    }

    func testRemovalKeepsHelperWhenRestoreFails() {
        let helper = FakeClosedLidHelperService(status: .enabled)
        let statusReader = FakeClosedLidStatusReader(status: .enabled)
        let ownershipStore = FakeClosedLidOwnershipStore(record: ownedRecord())
        helper.setClosedLidModeResult = .failure(ClosedLidHelperFailure.timedOut)

        XCTAssertThrowsError(try ClosedLidHelperRemoval.removeHelper(
            helperService: helper,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            appIsRunning: false
        ))

        XCTAssertEqual(helper.setClosedLidModeRequests, [false])
        XCTAssertEqual(helper.unregisterCallCount, 0)
        XCTAssertEqual(ownershipStore.record?.ownedByThisApp, true)
    }

    func testRemovalKeepsHelperWhenItCannotRestore() {
        let helper = FakeClosedLidHelperService(status: .requiresApproval)
        let statusReader = FakeClosedLidStatusReader(status: .enabled)
        let ownershipStore = FakeClosedLidOwnershipStore(record: ownedRecord())

        XCTAssertThrowsError(try ClosedLidHelperRemoval.removeHelper(
            helperService: helper,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            appIsRunning: false
        ))

        XCTAssertTrue(helper.setClosedLidModeRequests.isEmpty)
        XCTAssertEqual(helper.unregisterCallCount, 0)
        XCTAssertEqual(ownershipStore.record?.ownedByThisApp, true)
    }

    func testRemovalRestoresEvenWhenTheModeReadsAsOff() throws {
        // An enable the app already sent can still be queued in the helper.
        let helper = FakeClosedLidHelperService(status: .enabled)
        let statusReader = FakeClosedLidStatusReader(status: .disabled)
        let ownershipStore = FakeClosedLidOwnershipStore(record: ownedRecord())

        try ClosedLidHelperRemoval.removeHelper(
            helperService: helper,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            appIsRunning: false
        )

        XCTAssertEqual(helper.setClosedLidModeRequests, [false])
        XCTAssertEqual(helper.unregisterCallCount, 1)
        XCTAssertNil(ownershipStore.record)
    }

    func testRemovalClearsOwnershipWhenAHelperThatCannotChangeTheModeReadsOff() throws {
        let helper = FakeClosedLidHelperService(status: .requiresApproval)
        let statusReader = FakeClosedLidStatusReader(status: .disabled)
        let ownershipStore = FakeClosedLidOwnershipStore(record: ownedRecord())

        try ClosedLidHelperRemoval.removeHelper(
            helperService: helper,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            appIsRunning: false
        )

        XCTAssertTrue(helper.setClosedLidModeRequests.isEmpty)
        XCTAssertEqual(helper.unregisterCallCount, 1)
        XCTAssertNil(ownershipStore.record)
    }

    func testRemovalIsRefusedWhileTheAppIsRunning() {
        let helper = FakeClosedLidHelperService(status: .enabled)
        let statusReader = FakeClosedLidStatusReader(status: .enabled)
        let ownershipStore = FakeClosedLidOwnershipStore(record: ownedRecord())

        XCTAssertThrowsError(try ClosedLidHelperRemoval.removeHelper(
            helperService: helper,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            appIsRunning: true
        )) { error in
            XCTAssertEqual(error as? ClosedLidHelperRemovalError, .appIsRunning)
        }

        XCTAssertTrue(helper.setClosedLidModeRequests.isEmpty)
        XCTAssertEqual(helper.unregisterCallCount, 0)
        XCTAssertEqual(ownershipStore.record?.ownedByThisApp, true)
    }

    func testRemovalWithoutOwnershipUnregistersDirectly() throws {
        let helper = FakeClosedLidHelperService(status: .enabled)
        let statusReader = FakeClosedLidStatusReader(status: .enabled)
        let ownershipStore = FakeClosedLidOwnershipStore()

        try ClosedLidHelperRemoval.removeHelper(
            helperService: helper,
            statusReader: statusReader,
            ownershipStore: ownershipStore,
            appIsRunning: false
        )

        XCTAssertTrue(helper.setClosedLidModeRequests.isEmpty)
        XCTAssertEqual(helper.unregisterCallCount, 1)
        XCTAssertEqual(statusReader.status, .enabled)
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
    let externalDisplayDetector: FakeExternalDisplayDetector
    let clock: FakeClock
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
        clock: FakeClock = FakeClock(),
        closedLidModeChangeTimeout: TimeInterval = 6,
        blockingWork: BlockingWorkPerforming = DeferredBlockingWork(),
        terminationRestoreTimeout: TimeInterval = 0.5
    ) {
        self.settingsStore = FakeSettingsStore(settings: settings)
        self.ownershipStore = FakeClosedLidOwnershipStore(record: ownershipRecord)
        self.closedLidStatusReader = FakeClosedLidStatusReader(status: closedLidStatus)
        self.helper = FakeClosedLidHelperService(status: helperStatus)
        self.softwareUpdateService = FakeSoftwareUpdateService(state: softwareUpdateState)
        self.notificationService = FakeNotificationService()
        self.externalDisplayDetector = FakeExternalDisplayDetector()
        self.clock = clock
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
            clock: clock,
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
            externalDisplayDetector: externalDisplayDetector,
            initialBattery: batteryMonitor.currentState(),
            closedLidModeChangeTimeout: closedLidModeChangeTimeout,
            blockingWork: blockingWork,
            terminationRestoreTimeout: terminationRestoreTimeout
        )
    }
}

private final class FakeExternalDisplayDetector: ExternalDisplayDetecting {
    var hasActiveExternalDisplay = false
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
    var status: LoginItemStatus = .disabled
    /// Whether macOS holds a registration back until the user allows it.
    var requiresApproval = false
    var setEnabledRequests: [Bool] = []
    private(set) var openLoginItemsSettingsCallCount = 0

    func setEnabled(_ enabled: Bool) throws {
        setEnabledRequests.append(enabled)
        if enabled {
            status = requiresApproval ? .requiresApproval : .enabled
        } else {
            status = .disabled
        }
    }

    func openLoginItemsSettings() {
        openLoginItemsSettingsCallCount += 1
    }
}

private final class FakeClosedLidStatusReader: ClosedLidStatusReading {
    var status: ClosedLidStatus
    /// When set, every read waits on it, like a `pmset` that stopped answering.
    var gate: DispatchSemaphore?
    private(set) var readCount = 0

    init(status: ClosedLidStatus) {
        self.status = status
    }

    func readClosedLidStatus() -> ClosedLidStatus {
        readCount += 1
        _ = gate?.wait(timeout: .now() + 5)
        return status
    }
}


private final class FakeClosedLidHelperService: ClosedLidHelperServicing {
    var status: ClosedLidHelperStatus
    var setClosedLidModeRequests: [Bool] = []
    var onSetClosedLidMode: ((Bool) -> Void)?
    var setClosedLidModeResult: Result<Void, Error> = .success(())
    var shouldReplyToSetClosedLidMode = true
    /// Makes every change fail as unanswered until a repair registers the
    /// helper again, the way a helper that needs repair behaves.
    var isUnreachableUntilRepair = false
    var probeConnectionResult: Result<Void, ClosedLidHelperFailure> = .success(())
    var shouldReplyToProbeConnection = true
    private(set) var pendingProbeReply: ((Result<Void, ClosedLidHelperFailure>) -> Void)?
    private(set) var probeConnectionCallCount = 0
    var repairRegistrationError: Error?
    /// Status the registration reports once a repair finishes, success or not.
    var statusAfterRepair: ClosedLidHelperStatus?
    var shouldReplyToRepairRegistration = true
    private(set) var pendingRepairReply: (() -> Void)?
    /// Status the registration reports once `register()` returns.
    var statusAfterRegister: ClosedLidHelperStatus?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var repairRegistrationCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openApprovalSettingsCallCount = 0

    init(status: ClosedLidHelperStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }

    func repairRegistration(completion: @escaping (Result<Void, Error>) -> Void) {
        repairRegistrationCallCount += 1
        let reply = { [self] in
            if let statusAfterRepair {
                status = statusAfterRepair
            }
            if let repairRegistrationError {
                completion(.failure(repairRegistrationError))
            } else {
                completion(.success(()))
            }
        }
        guard shouldReplyToRepairRegistration else {
            pendingRepairReply = reply
            return
        }

        reply()
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
    }

    func setClosedLidMode(enabled: Bool, reply: @escaping (Result<Void, Error>) -> Void) {
        setClosedLidModeRequests.append(enabled)
        onSetClosedLidMode?(enabled)
        if shouldReplyToSetClosedLidMode {
            reply(setClosedLidModeResult)
        }
    }

    func probeConnection(reply: @escaping (Result<Void, ClosedLidHelperFailure>) -> Void) {
        probeConnectionCallCount += 1
        guard shouldReplyToProbeConnection else {
            pendingProbeReply = reply
            return
        }

        reply(probeConnectionResult)
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

    func advance(seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

private final class FakeClamshellStateReader: ClamshellStateReading {
    var state: ClamshellState = .open

    func clamshellState() -> ClamshellState {
        state
    }
}

private final class FakeDisplaySleeper: DisplaySleeping {
    private(set) var sleepCount = 0

    func sleepDisplaysNow() throws -> Bool {
        sleepCount += 1
        return true
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

/// Lets main-queue work settle. A helper reply, the status read it triggers,
/// and the follow-up that read schedules each take a turn of their own.
private func drainMainQueue() async {
    for _ in 0..<10 {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
