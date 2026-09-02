import AppKit
import VibeKeyLiteCore

final class SettingsViewController: NSViewController {
    var onProfileSelected: ((ProfileID) -> Void)?
    var onMappingChanged: ((ProfileID, InputControl, KeyAction) -> Void)?
    var onRestartApplication: (() -> Void)?
    var onSyncHardware: (() -> Void)?
    var onQuit: (() -> Void)?

    private var configuration: AppConfiguration
    private var listenerActive = false
    private var accessibilityGranted = false
    private var deviceConnected = false
    private var hardwareSyncInProgress = false
    private var notice: String?

    private let profileSelector = NSSegmentedControl(
        labels: ["AI", "系統"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let statusLabel = NSTextField(labelWithString: "")
    private lazy var syncButton = NSButton(
        title: "同步到裝置",
        target: self,
        action: #selector(syncHardware(_:))
    )
    private var actionPopups: [InputControl: NSPopUpButton] = [:]

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 365))

        let title = NSTextField(labelWithString: "VibeKey Lite")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let explanation = NSTextField(
            wrappingLabelWithString: "旋鈕短按執行「旋鈕短按」那一格；長按約 0.65 秒切換 AI／系統。"
        )
        explanation.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: 12)

        profileSelector.target = self
        profileSelector.action = #selector(profileChanged(_:))
        profileSelector.setAccessibilityLabel("目前設定組")

        let profileRow = NSStackView(views: [
            NSTextField(labelWithString: "目前設定組"),
            profileSelector
        ])
        profileRow.orientation = .horizontal
        profileRow.alignment = .centerY
        profileRow.distribution = .fill
        profileRow.spacing = 12

        let mappingGrid = makeMappingGrid()

        let syncExplanation = NSTextField(
            wrappingLabelWithString: "第一次使用須同步；這會把裝置的 6 個硬體動作覆寫為 F13–F18。"
        )
        syncExplanation.textColor = .secondaryLabelColor
        syncExplanation.font = .systemFont(ofSize: 11)

        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.font = .systemFont(ofSize: 11)

        let retryButton = NSButton(
            title: "套用並重啟",
            target: self,
            action: #selector(restartApplication(_:))
        )
        retryButton.bezelStyle = .rounded

        syncButton.bezelStyle = .rounded

        let quitButton = NSButton(
            title: "結束",
            target: self,
            action: #selector(quit(_:))
        )
        quitButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [syncButton, retryButton, NSView(), quitButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let stack = NSStackView(views: [
            title,
            explanation,
            profileRow,
            mappingGrid,
            syncExplanation,
            statusLabel,
            buttons
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16),
            profileRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            mappingGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        reloadControls()
    }

    func update(
        configuration: AppConfiguration,
        listenerActive: Bool,
        accessibilityGranted: Bool,
        deviceConnected: Bool,
        hardwareSyncInProgress: Bool,
        notice: String?
    ) {
        self.configuration = configuration
        self.listenerActive = listenerActive
        self.accessibilityGranted = accessibilityGranted
        self.deviceConnected = deviceConnected
        self.hardwareSyncInProgress = hardwareSyncInProgress
        self.notice = notice

        if isViewLoaded {
            reloadControls()
        }
    }

    private func makeMappingGrid() -> NSGridView {
        let rows: [[NSView]] = InputControl.allCases.map { control in
            let label = NSTextField(
                labelWithString: "\(control.displayName)  \(control.sourceFunctionKey)"
            )
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.identifier = NSUserInterfaceItemIdentifier(control.rawValue)
            popup.target = self
            popup.action = #selector(mappingChanged(_:))

            popup.removeAllItems()
            for (categoryIndex, category) in KeyActionCategory.allCases.enumerated() {
                if categoryIndex > 0 {
                    popup.menu?.addItem(.separator())
                }

                let heading = NSMenuItem(title: category.rawValue, action: nil, keyEquivalent: "")
                heading.isEnabled = false
                popup.menu?.addItem(heading)

                for action in KeyAction.allCases where action.category == category {
                    popup.addItem(withTitle: action.displayName)
                    popup.lastItem?.representedObject = action.rawValue
                }
            }

            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
            actionPopups[control] = popup
            return [label, popup]
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 5
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private func reloadControls() {
        profileSelector.selectedSegment = configuration.activeProfile == .a ? 0 : 1
        syncButton.isEnabled = !hardwareSyncInProgress
        syncButton.title = hardwareSyncInProgress ? "同步中…" : "同步到裝置"
        let profile = configuration.activeProfile

        for control in InputControl.allCases {
            let action = configuration[profile][control]
            let popup = actionPopups[control]
            let matchingItem = popup?.itemArray.first {
                ($0.representedObject as? String) == action.rawValue
            }
            popup?.select(matchingItem)
        }

        if !listenerActive {
            statusLabel.stringValue = notice ?? "尚未取得輸入監控權限，無法讀取 AU05。"
            statusLabel.textColor = .systemOrange
        } else if !accessibilityGranted {
            statusLabel.stringValue = "已可讀取 AU05，但缺少「輔助使用」權限，尚不能送出設定動作。"
            statusLabel.textColor = .systemOrange
        } else if let notice {
            statusLabel.stringValue = notice
            if notice.hasPrefix("已同步") {
                statusLabel.textColor = .systemGreen
            } else if notice.hasPrefix("正在同步") {
                statusLabel.textColor = .secondaryLabelColor
            } else {
                statusLabel.textColor = .systemOrange
            }
        } else if deviceConnected {
            statusLabel.stringValue = "AU05 已連接；讀取與動作權限都可用。"
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "權限可用，正在等待 AU05。"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func profileChanged(_ sender: NSSegmentedControl) {
        let profile: ProfileID = sender.selectedSegment == 0 ? .a : .b
        onProfileSelected?(profile)
    }

    @objc private func mappingChanged(_ sender: NSPopUpButton) {
        guard let rawControl = sender.identifier?.rawValue,
              let control = InputControl(rawValue: rawControl),
              let rawAction = sender.selectedItem?.representedObject as? String,
              let action = KeyAction(rawValue: rawAction) else {
            return
        }

        onMappingChanged?(configuration.activeProfile, control, action)
    }

    @objc private func restartApplication(_ sender: Any?) {
        onRestartApplication?()
    }

    @objc private func syncHardware(_ sender: Any?) {
        onSyncHardware?()
    }

    @objc private func quit(_ sender: Any?) {
        onQuit?()
    }
}
