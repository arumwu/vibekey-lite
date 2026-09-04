import AppKit
import OSLog
import VibeKeyLiteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hardwareConfigurator: any HardwareConfigurator
    private var configuration = AppConfiguration.default
    private var configStore: ConfigStore?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsViewController: SettingsViewController?
    private var hardwareListener: IOKitHardwareListener?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let actionPerformer = ActionPerformer()
    private var knobPressStateMachine = KnobPressStateMachine()
    private var knobLongPressTimer: Timer?
    private var knobSinglePressTimer: Timer?
    private var powerHandoffTimer: Timer?
    private var startupRecoveryTimer: Timer?
    private var startupRecoveryAttemptsRemaining = 0
    private var powerHandoffStateMachine = VibeKeyPowerHandoffStateMachine(idleInterval: 300)
    private let logger = Logger(
        subsystem: "io.github.arumwu.VibeKeyLite",
        category: "HID"
    )

    private var listenerActive = false
    private var accessibilityGranted = false
    private var deviceConnected = false
    private var devicePowerStatus = VibeKeyPowerSnapshot()
    private var powerSaving = false
    private var hardwareSyncInProgress = false
    private var vendorInterferedDuringHardwareSync = false
    private var needsHardwareSync = false
    private var configurationReady = false
    private var enhancedModeRequested = true
    private var offlineStateUnconfirmed = false
    private var notice: String?

    override init() {
        hardwareConfigurator = IOKitHardwareConfigurator()
        super.init()
    }

    init(hardwareConfigurator: any HardwareConfigurator) {
        self.hardwareConfigurator = hardwareConfigurator
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfiguration()
        configureStatusItemAndPopover()
        configureHardwareListener()
        configureLifecycleObservers()
        refreshUI()

        if needsHardwareSync {
            notice = "請按「離線備用」確認寫回完整六鍵；確認前不會改動 AU05。"
            refreshUI()
        } else {
            startHardwareListener(promptForPermission: true)
            scheduleStartupConnectionRecovery()
        }

        if ProcessInfo.processInfo.environment["VIBEKEY_SHOW_SETTINGS"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        powerHandoffTimer?.invalidate()
        powerHandoffTimer = nil
        startupRecoveryTimer?.invalidate()
        startupRecoveryTimer = nil
        resetKnobPressState()
        actionPerformer.releaseAll()
        if let error = hardwareListener?.stop() {
            logger.error("Offline shutdown failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard hardwareSyncInProgress else { return .terminateNow }
        notice = "AU05 寫入中；完成後再結束 App。"
        refreshUI()
        return .terminateCancel
    }

    private func loadConfiguration() {
        do {
            let url = try ConfigStore.defaultConfigURL()
            let store = ConfigStore(configURL: url)
            configuration = try store.loadOrCreate()
            let migratedKnob = configuration.restoreLegacyReservedKnobMappings()
            let needsInitialNativeBackup = configuration.offlineProfile == nil
            if migratedKnob || needsInitialNativeBackup {
                configuration.needsHardwareSync = true
                try store.save(configuration)
            }
            needsHardwareSync = configuration.needsHardwareSync
            configStore = store
            configurationReady = true
        } catch {
            configurationReady = false
            notice = "設定檔讀取失敗：\(error.localizedDescription)"
        }
    }

    private func configureStatusItemAndPopover() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        self.statusItem = statusItem

        let settings = SettingsViewController(configuration: configuration)
        settings.onProfileSelected = { [weak self] profile in
            guard let self else { return }
            guard !self.hardwareSyncInProgress else {
                self.refreshUI()
                return
            }
            guard profile != self.configuration.activeProfile else { return }
            let previousConfiguration = self.configuration
            self.cancelPendingInput()
            self.configuration.activeProfile = profile
            guard self.persistConfiguration() else {
                self.configuration = previousConfiguration
                self.refreshUI()
                return
            }
            self.notice = "已切換到「\(profile.displayName)」；離線備用未更動。"
            self.refreshUI()
        }
        settings.onMappingChanged = { [weak self] profile, control, binding in
            guard let self else { return }
            guard !self.hardwareSyncInProgress else {
                self.refreshUI()
                return
            }
            let previousConfiguration = self.configuration
            var profileConfiguration = self.configuration[profile]
            profileConfiguration[control] = binding
            self.configuration[profile] = profileConfiguration
            guard self.persistConfiguration() else {
                self.configuration = previousConfiguration
                self.refreshUI()
                return
            }
            self.notice = control.isNativeHardwareControl
                ? "設定已保存；按「設為離線備用」才會寫入 AU05。"
                : "雙按設定已保存。"
            self.refreshUI()
        }
        settings.onRestartApplication = { [weak self] in
            self?.restartApplication()
        }
        settings.onSyncHardware = { [weak self] in
            self?.confirmAndSyncHardware()
        }
        settings.onToggleEnhancedMode = { [weak self] in
            self?.toggleEnhancedMode()
        }
        settings.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        settingsViewController = settings

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 390, height: 365)
        popover.contentViewController = settings
        self.popover = popover
    }

    private func configureHardwareListener() {
        let listener = IOKitHardwareListener(
            eventHandler: { [weak self] deviceEvent, timestamp in
                self?.handle(deviceEvent, at: timestamp)
            },
            powerResponseHandler: { [weak self] response in
                guard let self else { return }
                self.devicePowerStatus.apply(response)
                if case let .standbyTime(seconds) = response {
                    self.applyPowerHandoffDecisions(
                        self.powerHandoffStateMachine.updateIdleInterval(
                            TimeInterval(seconds),
                            at: HIDMonotonicClock.now
                        )
                    )
                }
                self.refreshUI()
            },
            noticeHandler: { [weak self] notice in
                guard let self else { return }
                if case let .standby(status) = notice {
                    self.devicePowerStatus.isStandby = status != 0
                }
                self.applyPowerHandoffDecisions(
                    self.powerHandoffStateMachine.noticeReceived(notice)
                )
                self.refreshUI()
            },
            powerSavingWakeHandler: { [weak self] in
                guard let self else { return }
                self.applyPowerHandoffDecisions(
                    self.powerHandoffStateMachine.wakeInputReceived()
                )
            },
            connectionHandler: { [weak self] connected in
                guard let self else { return }
                self.deviceConnected = connected
                if !connected {
                    self.devicePowerStatus = VibeKeyPowerSnapshot()
                    self.powerSaving = false
                    self.cancelPowerHandoff(
                        reason: .onlinePrerequisiteLost
                    )
                } else {
                    self.startupRecoveryTimer?.invalidate()
                    self.startupRecoveryTimer = nil
                    self.startupRecoveryAttemptsRemaining = 0
                    self.applyPowerHandoffDecisions(
                        self.powerHandoffStateMachine.onlineStarted(
                            at: HIDMonotonicClock.now
                        )
                    )
                }
                if connected, self.notice?.hasPrefix("AU05 已移除") == true {
                    self.notice = nil
                }
                self.refreshUI()
            },
            failureHandler: { [weak self] error in
                guard let self else { return }
                let stopError = self.suspendEnhancedMode()
                self.notice = (stopError ?? error).localizedDescription
                self.refreshUI()
            },
            deviceRemovalHandler: { [weak self] in
                self?.handleDeviceRemoval()
            },
            shouldRemainOnline: { [weak self] in
                guard let self else { return false }
                return self.onlinePreflightIsValid
            }
        )
        hardwareListener = listener
    }

    private func configureLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopEnhancedMode(
                notice: "Mac 即將睡眠；AU05 已退回裝置原生按鍵。"
            )
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopEnhancedMode(
                notice: "Mac 即將關機；AU05 已退回裝置原生按鍵。"
            )
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeAfterUserActivityIfNeeded()
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard Self.isVendorApplication(notification) else { return }
            if self?.hardwareSyncInProgress == true {
                self?.vendorInterferedDuringHardwareSync = true
            }
            self?.stopEnhancedMode(
                notice: "Ulanzi Studio 已開啟；AU05 已退回裝置原生按鍵。"
            )
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard Self.isVendorApplication(notification) else { return }
            self?.resumeEnhancedModeIfSafe()
        })
    }

    private static func isVendorApplication(_ notification: Notification) -> Bool {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        return application?.bundleIdentifier == "ulanzi.UlanziStudio"
    }

    private func stopEnhancedMode(
        notice: String,
        reason: VibeKeyPowerHandoffSuspensionReason = .onlinePrerequisiteLost
    ) {
        let offlineError = suspendEnhancedMode(reason: reason)
        self.notice = offlineError?.localizedDescription ?? notice
        refreshUI()
    }

    private func suspendEnhancedMode(
        reason: VibeKeyPowerHandoffSuspensionReason = .onlinePrerequisiteLost
    ) -> Error? {
        cancelPowerHandoff(reason: reason)
        cancelPendingInput()
        let hadAttachedDevice = hardwareListener?.hasAttachedDevice == true
        let offlineError = hardwareListener?.stop()
        if offlineError != nil {
            offlineStateUnconfirmed = true
        } else if hadAttachedDevice {
            offlineStateUnconfirmed = false
        }
        listenerActive = false
        deviceConnected = false
        devicePowerStatus = VibeKeyPowerSnapshot()
        powerSaving = false
        return offlineError
    }

    private func toggleEnhancedMode() {
        if listenerActive {
            enhancedModeRequested = false
            stopEnhancedMode(
                notice: "已切回 AU05 原生六鍵。",
                reason: .manualNative
            )
            return
        }

        enhancedModeRequested = true
        if needsHardwareSync {
            notice = "請先按「離線備用」確認完整六鍵；不會自動改寫 AU05。"
            refreshUI()
        } else {
            startHardwareListener(promptForPermission: true)
        }
    }

    private func resumeEnhancedModeIfSafe() {
        guard !listenerActive,
              enhancedModeRequested,
              !hardwareSyncInProgress,
              !needsHardwareSync else { return }
        startHardwareListener(promptForPermission: false)
    }

    private func resumeAfterUserActivityIfNeeded() {
        // Opening the menu is not AU05 activity. While native power saving is
        // active, only a completed physical AU05 input should restore online
        // gestures; otherwise merely checking battery status wakes its lights.
        guard !powerSaving else { return }
        resumeEnhancedModeIfSafe()
    }

    private func applyPowerHandoffDecisions(
        _ decisions: [VibeKeyPowerHandoffDecision]
    ) {
        for decision in decisions {
            switch decision {
            case let .scheduleStandbyHandoff(deadline):
                powerHandoffTimer?.invalidate()
                let delay = max(0, deadline - HIDMonotonicClock.now)
                let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.powerHandoffTimer = nil
                    self.applyPowerHandoffDecisions(
                        self.powerHandoffStateMachine.standbyHandoffDeadlineReached(
                            at: HIDMonotonicClock.now
                        )
                    )
                }
                powerHandoffTimer = timer
                RunLoop.main.add(timer, forMode: .common)

            case .cancelStandbyHandoff:
                powerHandoffTimer?.invalidate()
                powerHandoffTimer = nil

            case .handoffForStandby:
                guard listenerActive,
                      deviceConnected,
                      !hardwareSyncInProgress,
                      !needsHardwareSync else {
                    cancelPowerHandoff(reason: .onlinePrerequisiteLost)
                    return
                }
                cancelPendingInput()
                if let error = hardwareListener?.enterPowerSavingMode() {
                    let stopError = suspendEnhancedMode()
                    notice = (stopError ?? error).localizedDescription
                } else {
                    powerSaving = true
                    notice = "閒置省電中；第一下使用原生單按，接著恢復三種手勢。"
                }
                refreshUI()

            case .resumeOnline:
                guard powerSaving else { continue }
                if let error = hardwareListener?.resumeFromPowerSaving() {
                    let stopError = suspendEnhancedMode()
                    notice = (stopError ?? error).localizedDescription
                } else {
                    powerSaving = false
                    devicePowerStatus.isStandby = false
                    if notice?.hasPrefix("閒置省電中") == true {
                        notice = nil
                    }
                    applyPowerHandoffDecisions(
                        powerHandoffStateMachine.onlineStarted(
                            at: HIDMonotonicClock.now
                        )
                    )
                }
                refreshUI()
            }
        }
    }

    private func cancelPowerHandoff(reason: VibeKeyPowerHandoffSuspensionReason) {
        powerHandoffTimer?.invalidate()
        powerHandoffTimer = nil
        _ = powerHandoffStateMachine.suspendAutomaticResume(reason: reason)
    }

    private func restartApplication() {
        guard !hardwareSyncInProgress else {
            notice = "AU05 寫入中；完成後再重啟 App。"
            refreshUI()
            return
        }

        if let error = suspendEnhancedMode() {
            notice = "尚未重啟：\(error.localizedDescription)"
            refreshUI()
            return
        }
        guard !offlineStateUnconfirmed else {
            notice = "尚未確認 AU05 已回原生模式；請先完成一次「離線備用」，再重啟。"
            refreshUI()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.notice = "重新啟動失敗：\(error.localizedDescription)"
                    self?.resumeEnhancedModeIfSafe()
                    self?.refreshUI()
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func startHardwareListener(promptForPermission: Bool) {
        cancelPendingInput()

        guard enhancedModeRequested else { return }

        guard configurationReady else {
            listenerActive = false
            deviceConnected = false
            notice = "設定檔無法使用；AU05 保持裝置原生模式。"
            refreshUI()
            return
        }

        accessibilityGranted = AccessibilityAccess.isTrusted(
            promptForPermission: promptForPermission
        )
        guard accessibilityGranted else {
            listenerActive = false
            deviceConnected = false
            notice = "原生六鍵仍可用；允許「輔助使用」後，雙按與長按才會啟用。"
            refreshUI()
            return
        }

        guard vendorApplicationIsNotRunning else {
            listenerActive = false
            deviceConnected = false
            notice = "Ulanzi Studio 執行中；已保留 AU05 原生模式。"
            refreshUI()
            return
        }

        do {
            try validateAllProfilesForOnlineMode()
        } catch {
            listenerActive = false
            deviceConnected = false
            notice = "原生六鍵仍可用；進階手勢設定無效：\(error.localizedDescription)"
            refreshUI()
            return
        }

        do {
            try hardwareListener?.start(promptForPermission: promptForPermission)
            listenerActive = true
            if notice?.contains("權限") == true || notice?.hasPrefix("監聽失敗") == true {
                notice = nil
            }
        } catch {
            listenerActive = false
            deviceConnected = false
            notice = "監聽失敗：\(error.localizedDescription)"
            logger.error(
                "Listener startup failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        refreshUI()
    }

    private func scheduleStartupConnectionRecovery() {
        guard !deviceConnected,
              enhancedModeRequested,
              !needsHardwareSync else { return }
        startupRecoveryAttemptsRemaining = 3
        scheduleNextStartupConnectionRecovery()
    }

    private func scheduleNextStartupConnectionRecovery() {
        startupRecoveryTimer?.invalidate()
        guard startupRecoveryAttemptsRemaining > 0,
              !deviceConnected else { return }

        let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.startupRecoveryTimer = nil
            guard !self.deviceConnected,
                  self.enhancedModeRequested,
                  !self.needsHardwareSync else { return }

            self.startupRecoveryAttemptsRemaining -= 1
            self.logger.notice(
                "Retrying startup connection; attempts remaining=\(self.startupRecoveryAttemptsRemaining, privacy: .public)"
            )
            if let error = self.suspendEnhancedMode() {
                self.notice = "自動重連失敗：\(error.localizedDescription)"
                self.refreshUI()
                return
            }
            self.startHardwareListener(promptForPermission: false)
            if !self.deviceConnected {
                self.scheduleNextStartupConnectionRecovery()
            }
        }
        startupRecoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func resetKnobPressState() {
        knobLongPressTimer?.invalidate()
        knobLongPressTimer = nil
        knobSinglePressTimer?.invalidate()
        knobSinglePressTimer = nil
        knobPressStateMachine.reset()
    }

    private func cancelPendingInput() {
        resetKnobPressState()
        actionPerformer.releaseAll()
    }

    private func handleDeviceRemoval() {
        cancelPowerHandoff(reason: .onlinePrerequisiteLost)
        cancelPendingInput()
        offlineStateUnconfirmed = false
        deviceConnected = false
        devicePowerStatus = VibeKeyPowerSnapshot()
        powerSaving = false
        notice = "AU05 已移除；未完成的旋鈕按壓已取消。"
        refreshUI()
    }

    private func handle(_ deviceEvent: DeviceEvent, at timestamp: TimeInterval) {
        guard listenerActive,
              deviceConnected,
              !hardwareSyncInProgress,
              !needsHardwareSync else { return }
        applyPowerHandoffDecisions(
            powerHandoffStateMachine.deviceInput(at: timestamp)
        )
        let eventTime = String(format: "%.6f", timestamp)
        logger.notice(
            "HID event: \(String(describing: deviceEvent), privacy: .public) time=\(eventTime, privacy: .public)"
        )
        switch deviceEvent {
        case let .key(control: .knobPress, phase: phase):
            handleKnobPress(phase, at: timestamp)
        case let .key(control: control, phase: phase):
            handleOrdinaryControl(control, phase: phase)
        }
    }

    private func handleOrdinaryControl(_ control: InputControl, phase: KeyPhase) {
        guard phase == .down else { return }
        let binding = configuration[configuration.activeProfile][control]
        do {
            // AU05 controls are macro triggers. Send one complete tap on down
            // so a crash can never leave a synthetic modifier held.
            try actionPerformer.tap(binding, for: control)
        } catch {
            notice = "按鍵執行失敗：\(error.localizedDescription)"
            refreshUI()
        }
    }

    private func handleKnobPress(_ phase: KeyPhase, at timestamp: TimeInterval) {
        switch phase {
        case .down:
            applyKnobPressDecisions(knobPressStateMachine.pressDown(at: timestamp))
        case .up:
            knobLongPressTimer?.invalidate()
            knobLongPressTimer = nil
            applyKnobPressDecisions(knobPressStateMachine.pressUp(at: timestamp))
        }
    }

    private func applyKnobPressDecisions(_ decisions: [KnobPressDecision]) {
        for decision in decisions {
            applyKnobPressDecision(decision)
        }
    }

    private func applyKnobPressDecision(_ decision: KnobPressDecision) {
        logger.notice("Knob decision: \(String(describing: decision), privacy: .public)")
        switch decision {
        case let .scheduleLongPress(delay):
            knobLongPressTimer?.invalidate()
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.knobLongPressTimer = nil
                self.applyKnobPressDecisions(
                    self.knobPressStateMachine.longPressTimerFired()
                )
            }
            knobLongPressTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case let .scheduleSinglePress(delay):
            knobSinglePressTimer?.invalidate()
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.knobSinglePressTimer = nil
                if let decision = self.knobPressStateMachine.singlePressTimerFired() {
                    self.applyKnobPressDecision(decision)
                }
            }
            knobSinglePressTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .cancelPendingSinglePress:
            knobSinglePressTimer?.invalidate()
            knobSinglePressTimer = nil
        case .performSinglePress:
            performGestureBinding(for: .knobPress)
        case .performDoublePress:
            performGestureBinding(for: .knobDoublePress)
        case .longPressRecognized:
            notice = "已辨識長按；放開旋鈕後切換設定組。"
            refreshUI()
        case .switchProfile:
            switchProfile()
        }
    }

    private func performGestureBinding(for control: InputControl) {
        let binding = configuration[configuration.activeProfile][control]
        if binding == .preset(.switchProfile) {
            switchProfile()
            return
        }

        do {
            try actionPerformer.tap(binding, for: control)
        } catch {
            notice = "按鍵執行失敗：\(error.localizedDescription)"
            refreshUI()
        }
    }

    private func switchProfile() {
        let previousConfiguration = configuration
        actionPerformer.releaseAll()
        configuration.activeProfile = configuration.activeProfile.toggled
        guard persistConfiguration() else {
            configuration = previousConfiguration
            refreshUI()
            return
        }
        logger.notice(
            "Profile switched to \(self.configuration.activeProfile.rawValue, privacy: .public)"
        )
        notice = "已切換到「\(configuration.activeProfile.displayName)」；離線備用未更動。"
        refreshUI()
    }

    private func confirmAndSyncHardware() {
        guard !hardwareSyncInProgress else { return }
        let profileID = configuration.activeProfile

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "要重寫目前這組 6 個原生按鍵嗎？"
        alert.informativeText = "這會把「\(profileID.displayName)」的完整六格寫入 AU05；關掉 VibeKey Lite 後仍可使用。"
        alert.addButton(withTitle: "同步")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        syncHardware(profileID: profileID)
    }

    private func syncHardware(profileID: ProfileID) {
        guard configurationReady else {
            notice = "設定檔無法使用；未寫入 AU05。"
            refreshUI()
            return
        }

        guard !hardwareSyncInProgress else { return }

        let vendorBundleIdentifier = "ulanzi.UlanziStudio"
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: vendorBundleIdentifier
        ).isEmpty else {
            notice = "請先完全結束 Ulanzi Studio，再同步到裝置。"
            refreshUI()
            return
        }

        if !needsHardwareSync {
            let previousConfiguration = configuration
            configuration.needsHardwareSync = true
            guard persistConfiguration() else {
                configuration = previousConfiguration
                refreshUI()
                return
            }
            needsHardwareSync = true
        }

        hardwareSyncInProgress = true
        vendorInterferedDuringHardwareSync = false
        if let error = suspendEnhancedMode() {
            hardwareSyncInProgress = false
            notice = "未寫入 AU05：\(error.localizedDescription)"
            refreshUI()
            return
        }
        let profile = configuration[profileID]
        notice = "正在寫入「\(profileID.displayName)」原生按鍵…"
        refreshUI()

        let configurator = hardwareConfigurator
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try configurator.apply(profile: profile)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.hardwareSyncInProgress = false

                switch result {
                case .success:
                    self.offlineStateUnconfirmed = false
                    if self.vendorInterferedDuringHardwareSync
                        || !self.vendorApplicationIsNotRunning {
                        self.configuration.needsHardwareSync = true
                        self.needsHardwareSync = true
                        self.notice = "Ulanzi Studio 在寫入時開啟；裝置內容不確定。請關閉它，再按「離線備用」。"
                    } else if let markerSaveError = self.completeHardwareSync(profileID: profileID) {
                        self.notice = "已寫入「\(profileID.displayName)」，但同步狀態保存失敗：\(markerSaveError) 下次啟動會再寫一次。"
                    } else {
                        self.notice = "已寫入「\(profileID.displayName)」：關掉 App 仍可使用。"
                    }
                    self.logger.notice(
                        "Hardware profile \(profileID.rawValue, privacy: .public) written successfully"
                    )
                    if !self.needsHardwareSync,
                       !self.listenerActive,
                       self.enhancedModeRequested {
                        self.startHardwareListener(promptForPermission: true)
                    }
                case let .failure(error):
                    if let configurationError = error as? IOKitHardwareConfiguratorError {
                        switch configurationError {
                        case .offlineWriteFailed:
                            self.offlineStateUnconfirmed = true
                            self.notice = "同步中止：\(error.localizedDescription) 六鍵尚未開始寫入；請保持連接再試。"
                        case .reportWriteFailed:
                            self.offlineStateUnconfirmed = false
                            self.notice = "同步失敗：\(error.localizedDescription) 裝置可能只寫入部分；請保持連接，再按「離線備用」。"
                        default:
                            self.notice = "同步中止：\(error.localizedDescription) 六鍵尚未開始寫入。"
                        }
                    } else {
                        self.notice = "同步失敗：\(error.localizedDescription)"
                    }
                    self.logger.error(
                        "Hardware profile write failed: \(error.localizedDescription, privacy: .public)"
                    )
                }

                self.refreshUI()
            }
        }
    }

    private var vendorApplicationIsNotRunning: Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "ulanzi.UlanziStudio"
        ).isEmpty
    }

    private var onlinePreflightIsValid: Bool {
        guard configurationReady,
              enhancedModeRequested,
              configuration.offlineProfile != nil,
              !needsHardwareSync,
              vendorApplicationIsNotRunning,
              IOHIDListenAccess.isGranted,
              AccessibilityAccess.isTrusted(promptForPermission: false) else {
            return false
        }
        return (try? validateAllProfilesForOnlineMode()) != nil
    }

    private func validateAllProfilesForOnlineMode() throws {
        try actionPerformer.validate(profile: configuration.profileA)
        try actionPerformer.validate(profile: configuration.profileB)
    }

    private func completeHardwareSync(profileID: ProfileID) -> String? {
        guard let configStore else {
            return "設定檔位置不可用。"
        }

        let previousOfflineProfile = configuration.offlineProfile
        configuration.offlineProfile = profileID
        configuration.needsHardwareSync = false
        do {
            try configStore.save(configuration)
            needsHardwareSync = false
            return nil
        } catch {
            configuration.offlineProfile = previousOfflineProfile
            configuration.needsHardwareSync = true
            needsHardwareSync = true
            return error.localizedDescription
        }
    }

    @discardableResult
    private func persistConfiguration() -> Bool {
        guard let configStore else {
            notice = "設定檔位置不可用，這次變更尚未保存。"
            return false
        }

        do {
            try configStore.save(configuration)
            if notice?.contains("尚未保存") == true || notice?.hasPrefix("設定檔") == true {
                notice = nil
            }
            return true
        } catch {
            notice = "設定檔保存失敗：\(error.localizedDescription)"
            return false
        }
    }

    private func refreshUI() {
        refreshStatusItem()
        settingsViewController?.update(
            configuration: configuration,
            listenerActive: listenerActive,
            accessibilityGranted: accessibilityGranted,
            deviceConnected: deviceConnected,
            powerStatus: devicePowerStatus,
            powerSaving: powerSaving,
            hardwareSyncInProgress: hardwareSyncInProgress,
            notice: notice
        )
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }

        let profileName = configuration.activeProfile.displayName
        let batteryDescription = devicePowerStatus.battery.map {
            "，電量 \($0.percent)%"
        } ?? ""
        let accessibleName = "VibeKey Lite：\(profileName)\(batteryDescription)"
        let preferredSymbol = configuration.activeProfile == .a
            ? "sparkles"
            : "slider.horizontal.3"
        let image = VibeKeyStatusIcon.image(for: configuration.activeProfile) ?? NSImage(
            systemSymbolName: preferredSymbol,
            accessibilityDescription: nil
        ) ?? NSImage(
            systemSymbolName: "dial.medium",
            accessibilityDescription: nil
        )

        button.toolTip = accessibleName
        button.setAccessibilityLabel(accessibleName)

        if let image {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "VK"
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard statusItem?.button != nil, let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button,
              let popover,
              !popover.isShown else { return }
        resumeAfterUserActivityIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hardwareListener?.refreshPowerStatus()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
