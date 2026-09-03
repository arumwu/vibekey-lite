import AppKit
import CoreGraphics
import VibeKeyLiteCore

enum KeyboardShortcutRecorder {
    static func record() -> Result<NativeShortcut, Error>? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "錄製硬體快捷鍵"
        alert.informativeText = "請直接按下按鍵或組合鍵。可分辨左／右 Option、Control、Shift、Command。"
        alert.addButton(withTitle: "取消")

        let captureView = ShortcutCaptureView(frame: NSRect(x: 0, y: 0, width: 320, height: 58))
        alert.accessoryView = captureView

        var capturedResult: Result<NativeShortcut, Error>?
        captureView.onCapture = { result in
            capturedResult = result
            NSApp.stopModal(withCode: .OK)
        }

        DispatchQueue.main.async {
            alert.window.makeFirstResponder(captureView)
        }
        _ = alert.runModal()
        alert.window.orderOut(nil)
        return capturedResult
    }
}

private final class ShortcutCaptureView: NSView {
    var onCapture: ((Result<NativeShortcut, Error>) -> Void)?

    private let promptLabel = NSTextField(labelWithString: "等待按鍵…")
    private var modifierOrder: [UInt16] = []
    private var pressedModifiers: Set<UInt16> = []

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        promptLabel.alignment = .center
        promptLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(promptLabel)

        NSLayoutConstraint.activate([
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            promptLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            promptLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func becomeFirstResponder() -> Bool {
        promptLabel.stringValue = "請按下快捷鍵"
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        let keyCode = event.keyCode

        if keyCode == 57 {
            finish(with: [keyCode], fallbackName: "Caps Lock")
            return
        }

        guard MacKeyCodeShortcutMapper.isModifier(keyCode) else {
            super.flagsChanged(with: event)
            return
        }

        let isDown: Bool
        if keyCode == 63 {
            isDown = event.modifierFlags.contains(.function)
        } else {
            isDown = CGEventSource.keyState(
                .hidSystemState,
                key: CGKeyCode(keyCode)
            )
        }

        if isDown {
            if pressedModifiers.insert(keyCode).inserted {
                modifierOrder.append(keyCode)
            }
            promptLabel.stringValue = MacKeyCodeShortcutMapper.displayName(for: modifierOrder)
        } else {
            pressedModifiers.remove(keyCode)
            if pressedModifiers.isEmpty, !modifierOrder.isEmpty {
                finish(with: modifierOrder, fallbackName: nil)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }

        if MacKeyCodeShortcutMapper.isModifier(event.keyCode) {
            return
        }

        var keyCodes = modifierOrder
        keyCodes.append(event.keyCode)
        let fallback = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        finish(with: keyCodes, fallbackName: fallback)
    }

    private func finish(with keyCodes: [UInt16], fallbackName: String?) {
        guard keyCodes.count <= 4 else {
            onCapture?(.failure(MacKeyCodeShortcutError.tooManyKeys))
            return
        }

        do {
            let shortcut = try MacKeyCodeShortcutMapper.shortcut(
                for: keyCodes,
                fallbackName: fallbackName
            )
            promptLabel.stringValue = shortcut.displayName
            onCapture?(.success(shortcut))
        } catch {
            onCapture?(.failure(error))
        }
    }
}
