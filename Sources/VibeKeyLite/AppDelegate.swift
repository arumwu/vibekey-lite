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
    private let actionPerformer = ActionPerformer()
    private var knobPressStateMachine = KnobPressStateMachine()
    private var knobPressTimer: Timer?
    private let logger = Logger(
        subsystem: "io.github.arumwu.VibeKeyLite",
        category: "HID"
    )

    private var listenerActive = false
    private var accessibilityGranted = false
    private var deviceConnected = false
    private var hardwareSyncInProgress = false
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
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        knobPressTimer?.invalidate()
        hardwareListener?.stop()
    }

    private func loadConfiguration() {
        do {
            let url = try ConfigStore.defaultConfigURL()
            let store = ConfigStore(configURL: url)
            configuration = try store.loadOrCreate()
            configStore = store
        } catch {
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
            self.configuration.activeProfile = profile
            self.persistConfiguration()
            self.refreshUI()
        }
        settings.onMappingChanged = { [weak self] profile, control, action in
            guard let self else { return }
            var profileConfiguration = self.configuration[profile]
            profileConfiguration[control] = action
            self.configuration[profile] = profileConfiguration
            self.persistConfiguration()
            self.refreshUI()
        }
        settings.onRestartApplication = { [weak self] in
            self?.restartApplication()
        }
        settings.onSyncHardware = { [weak self] in
            self?.confirmAndSyncHardware()
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
            connectionHandler: { [weak self] connected in
                guard let self else { return }
                self.deviceConnected = connected
                if connected, self.notice?.hasPrefix("AU05 已移除") == true {
                    self.notice = nil
                }
                self.refreshUI()
            },
            deviceRemovalHandler: { [weak self] in
                self?.handleDeviceRemoval()
            }
        )
        hardwareListener = listener
        startHardwareListener(promptForPermission: true)
    }

    private func restartApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.notice = "重新啟動失敗：\(error.localizedDescription)"
                    self?.refreshUI()
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func startHardwareListener(promptForPermission: Bool) {
        resetKnobPressState()
        accessibilityGranted = AccessibilityAccess.isTrusted(
            promptForPermission: promptForPermission
        )

        do {
            try hardwareListener?.start(promptForPermission: promptForPermission)
            listenerActive = true

            if accessibilityGranted {
                if notice?.contains("權限") == true || notice?.hasPrefix("監聽失敗") == true {
                    notice = nil
                }
            } else {
                notice = "需要「輔助使用」權限，才能送出你設定的按鍵。"
            }
        } catch {
            listenerActive = false
            deviceConnected = false
            notice = "監聽失敗：\(error.localizedDescription)"
        }

        refreshUI()
    }

    private func resetKnobPressState() {
        knobPressTimer?.invalidate()
        knobPressTimer = nil
        knobPressStateMachine.reset()
    }

    private func handleDeviceRemoval() {
        resetKnobPressState()
        deviceConnected = false
        notice = "AU05 已移除；未完成的旋鈕按壓已取消。"
        refreshUI()
    }

    private func handle(_ deviceEvent: DeviceEvent, at timestamp: TimeInterval) {
        let eventTime = String(format: "%.6f", timestamp)
        logger.notice(
            "HID event: \(String(describing: deviceEvent), privacy: .public) time=\(eventTime, privacy: .public)"
        )
        switch deviceEvent {
        case let .key(control: .knobPress, phase: phase):
            handleKnobPress(phase, at: timestamp)
        case let .key(control: control, phase: .down):
            performConfiguredAction(for: control)
        case .key(control: _, phase: .up):
            break
        }
    }

    private func handleKnobPress(_ phase: KeyPhase, at timestamp: TimeInterval) {
        switch phase {
        case .down:
            if let decision = knobPressStateMachine.pressDown(at: timestamp) {
                applyKnobPressDecision(decision)
            }
        case .up:
            knobPressTimer?.invalidate()
            knobPressTimer = nil
            if let decision = knobPressStateMachine.pressUp(at: timestamp) {
                applyKnobPressDecision(decision)
            }
        }
    }

    private func applyKnobPressDecision(_ decision: KnobPressDecision) {
        logger.notice("Knob decision: \(String(describing: decision), privacy: .public)")
        switch decision {
        case let .scheduleLongPress(delay):
            knobPressTimer?.invalidate()
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.knobPressTimer = nil
                if let decision = self.knobPressStateMachine.longPressTimerFired() {
                    self.applyKnobPressDecision(decision)
                }
            }
            knobPressTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .performShortPress:
            performConfiguredAction(for: .knobPress)
        case .switchProfile:
            switchProfile()
        }
    }

    private func performConfiguredAction(for control: InputControl) {
        let action = configuration[configuration.activeProfile][control]
        let resolved = ActionResolver.resolve(action)

        if resolved == .switchProfile {
            switchProfile()
        } else if resolved != .none {
            guard accessibilityGranted else {
                notice = "需要「輔助使用」權限，才能送出你設定的按鍵。"
                refreshUI()
                return
            }
            actionPerformer.perform(resolved)
        }
    }

    private func switchProfile() {
        configuration.activeProfile = configuration.activeProfile.toggled
        logger.notice(
            "Profile switched to \(self.configuration.activeProfile.rawValue, privacy: .public)"
        )
        notice = "已切換到「\(configuration.activeProfile.displayName)」設定組。"
        persistConfiguration()
        refreshUI()
    }

    private func confirmAndSyncHardware() {
        guard !hardwareSyncInProgress else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "要同步 6 個硬體動作嗎？"
        alert.informativeText = "這會把裝置的上、中、下鍵與旋鈕三個動作覆寫為 F13–F18。AI／系統的 12 格設定仍保存在 VibeKey Lite。"
        alert.addButton(withTitle: "同步")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        syncHardware()
    }

    private func syncHardware() {
        let vendorBundleIdentifier = "ulanzi.UlanziStudio"
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: vendorBundleIdentifier
        ).isEmpty else {
            notice = "請先完全結束 Ulanzi Studio，再同步到裝置。"
            refreshUI()
            return
        }

        hardwareSyncInProgress = true
        notice = "正在同步 6 個硬體動作…"
        refreshUI()

        let configurator = hardwareConfigurator
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try configurator.apply(layout: .vibeKeyDefault)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.hardwareSyncInProgress = false

                switch result {
                case .success:
                    self.notice = "已同步到裝置：6 個硬體動作已設為 F13–F18。"
                case let .failure(error):
                    self.notice = "同步失敗：\(error.localizedDescription)"
                }

                self.refreshUI()
            }
        }
    }

    private func persistConfiguration() {
        guard let configStore else {
            notice = "設定檔位置不可用，這次變更尚未保存。"
            return
        }

        do {
            try configStore.save(configuration)
            if notice?.contains("尚未保存") == true || notice?.hasPrefix("設定檔") == true {
                notice = nil
            }
        } catch {
            notice = "設定檔保存失敗：\(error.localizedDescription)"
        }
    }

    private func refreshUI() {
        refreshStatusItem()
        settingsViewController?.update(
            configuration: configuration,
            listenerActive: listenerActive,
            accessibilityGranted: accessibilityGranted,
            deviceConnected: deviceConnected,
            hardwareSyncInProgress: hardwareSyncInProgress,
            notice: notice
        )
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }

        let profileName = configuration.activeProfile.displayName
        let accessibleName = "VibeKey Lite：\(profileName)"
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
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
