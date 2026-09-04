import Foundation

public enum ProfileID: String, CaseIterable, Codable, Sendable {
    case a
    case b

    public var displayName: String {
        switch self {
        case .a: "AI"
        case .b: "系統"
        }
    }

    public var toggled: ProfileID {
        self == .a ? .b : .a
    }
}

public enum InputControl: String, CaseIterable, Codable, CodingKey, Sendable {
    case knobPress
    case knobDoublePress
    case knobLeft
    case knobRight
    case topButton
    case middleButton
    case bottomButton

    public var displayName: String {
        switch self {
        case .knobPress: "旋鈕單按"
        case .knobDoublePress: "旋鈕雙按"
        case .knobLeft: "旋鈕向左"
        case .knobRight: "旋鈕向右"
        case .topButton: "上鍵"
        case .middleButton: "中鍵"
        case .bottomButton: "下鍵"
        }
    }

    public var isNativeHardwareControl: Bool {
        self != .knobDoublePress
    }

}

public enum KeyPhase: Equatable, Sendable {
    case down
    case up
}

public enum DeviceEvent: Equatable, Sendable {
    case key(control: InputControl, phase: KeyPhase)
}

public enum KeyAction: String, CaseIterable, Codable, Sendable {
    case none
    case space
    case returnKey
    case escape
    case tab
    case fnDoubleTap
    case optionKey
    case rightOptionKey
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case deleteBackward
    case deleteForward
    case home
    case end
    case pageUp
    case pageDown
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case selectAll
    case copy
    case paste
    case cut
    case undo
    case redo
    case save
    case appSwitcher
    case spotlight
    case screenshot
    case missionControl
    case switchProfile
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
    case previousTrack
    case nextTrack
    case playPause

    public var displayName: String {
        switch self {
        case .none: "不做事"
        case .space: "Space"
        case .returnKey: "Return"
        case .escape: "Escape"
        case .tab: "Tab"
        case .fnDoubleTap: "Fn 按兩次（App 開啟時）"
        case .optionKey: "左 Option"
        case .rightOptionKey: "右 Option"
        case .leftArrow: "方向鍵 ←"
        case .rightArrow: "方向鍵 →"
        case .upArrow: "方向鍵 ↑"
        case .downArrow: "方向鍵 ↓"
        case .deleteBackward: "Delete／Backspace"
        case .deleteForward: "Forward Delete"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        case .selectAll: "⌘A（全選）"
        case .copy: "⌘C（複製）"
        case .paste: "⌘V（貼上）"
        case .cut: "⌘X（剪下）"
        case .undo: "⌘Z（復原）"
        case .redo: "⌘⇧Z（重做）"
        case .save: "⌘S（儲存）"
        case .appSwitcher: "⌘Tab（切換 App）"
        case .spotlight: "⌘Space（Spotlight）"
        case .screenshot: "⌘⇧5（截圖）"
        case .missionControl: "⌃↑（Mission Control）"
        case .switchProfile: "切換 AI／系統"
        case .volumeUp: "音量提高"
        case .volumeDown: "音量降低"
        case .mute: "靜音"
        case .brightnessUp: "亮度提高"
        case .brightnessDown: "亮度降低"
        case .previousTrack: "上一首"
        case .nextTrack: "下一首"
        case .playPause: "播放／暫停"
        }
    }

    public var category: KeyActionCategory {
        switch self {
        case .none, .space, .returnKey, .escape, .tab, .fnDoubleTap,
             .optionKey, .rightOptionKey:
            .basic
        case .leftArrow, .rightArrow, .upArrow, .downArrow,
             .deleteBackward, .deleteForward, .home, .end, .pageUp, .pageDown:
            .navigation
        case .f1, .f2, .f3, .f4, .f5, .f6,
             .f7, .f8, .f9, .f10, .f11, .f12:
            .functionKeys
        case .selectAll, .copy, .paste, .cut, .undo, .redo, .save:
            .editing
        case .appSwitcher, .spotlight, .screenshot, .missionControl, .switchProfile:
            .system
        case .volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown,
             .previousTrack, .nextTrack, .playPause:
            .media
        }
    }
}

public enum KeyActionCategory: String, CaseIterable, Sendable {
    case basic = "基本"
    case navigation = "導航"
    case functionKeys = "F1–F12"
    case editing = "編輯"
    case system = "系統"
    case media = "媒體"
}

public enum ControlBinding: Codable, Equatable, Sendable {
    case preset(KeyAction)
    case shortcut(NativeShortcut)

    private enum CodingKeys: String, CodingKey {
        case type
        case shortcut
    }

    private enum Kind: String, Codable {
        case shortcut
    }

    public init(from decoder: Decoder) throws {
        if let action = try? decoder.singleValueContainer().decode(KeyAction.self) {
            self = .preset(action)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .shortcut:
            self = .shortcut(try container.decode(NativeShortcut.self, forKey: .shortcut))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .preset(action):
            var container = encoder.singleValueContainer()
            try container.encode(action)
        case let .shortcut(shortcut):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.shortcut, forKey: .type)
            try container.encode(shortcut, forKey: .shortcut)
        }
    }

    public var displayName: String {
        switch self {
        case let .preset(action): action.displayName
        case let .shortcut(shortcut): shortcut.displayName
        }
    }
}

public struct ProfileConfiguration: Codable, Equatable, Sendable {
    private var mappings: [InputControl: ControlBinding]

    public init(mappings: [InputControl: ControlBinding] = [:]) {
        self.mappings = mappings
    }

    public subscript(control: InputControl) -> ControlBinding {
        get { mappings[control] ?? .preset(.none) }
        set { mappings[control] = newValue }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: InputControl.self)
        var decoded: [InputControl: ControlBinding] = [:]

        for control in InputControl.allCases {
            let fallback: ControlBinding = control == .knobDoublePress
                ? .preset(.switchProfile)
                : .preset(.none)
            decoded[control] = try container.decodeIfPresent(
                ControlBinding.self,
                forKey: control
            ) ?? fallback
        }

        mappings = decoded
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: InputControl.self)

        for control in InputControl.allCases {
            try container.encode(self[control], forKey: control)
        }
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var activeProfile: ProfileID
    public var offlineProfile: ProfileID?
    public var profileA: ProfileConfiguration
    public var profileB: ProfileConfiguration
    public var needsHardwareSync: Bool

    public init(
        activeProfile: ProfileID = .a,
        offlineProfile: ProfileID? = nil,
        profileA: ProfileConfiguration = .init(),
        profileB: ProfileConfiguration = .init(),
        needsHardwareSync: Bool = true
    ) {
        self.activeProfile = activeProfile
        self.offlineProfile = offlineProfile
        self.profileA = profileA
        self.profileB = profileB
        self.needsHardwareSync = needsHardwareSync
    }

    private enum CodingKeys: String, CodingKey {
        case activeProfile
        case offlineProfile
        case profileA
        case profileB
        case needsHardwareSync
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeProfile = try container.decode(ProfileID.self, forKey: .activeProfile)
        offlineProfile = try container.decodeIfPresent(ProfileID.self, forKey: .offlineProfile)
        profileA = try container.decode(ProfileConfiguration.self, forKey: .profileA)
        profileB = try container.decode(ProfileConfiguration.self, forKey: .profileB)
        // Configurations written before this marker existed must complete one
        // full native six-slot write before online gestures may start safely.
        let decodedNeedsHardwareSync = try container.decodeIfPresent(
            Bool.self,
            forKey: .needsHardwareSync
        ) ?? true
        // An offline profile is proof that a complete six-slot native backup
        // finished. Never trust an old/partial "false" marker without it.
        needsHardwareSync = offlineProfile == nil ? true : decodedNeedsHardwareSync
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeProfile, forKey: .activeProfile)
        try container.encodeIfPresent(offlineProfile, forKey: .offlineProfile)
        try container.encode(profileA, forKey: .profileA)
        try container.encode(profileB, forKey: .profileB)
        try container.encode(needsHardwareSync, forKey: .needsHardwareSync)
    }

    public subscript(profile: ProfileID) -> ProfileConfiguration {
        get {
            switch profile {
            case .a: profileA
            case .b: profileB
            }
        }
        set {
            switch profile {
            case .a: profileA = newValue
            case .b: profileB = newValue
            }
        }
    }

    public static var `default`: AppConfiguration {
        var profileA = ProfileConfiguration()
        profileA[.knobPress] = .preset(.selectAll)
        profileA[.knobDoublePress] = .preset(.switchProfile)
        profileA[.knobLeft] = .preset(.downArrow)
        profileA[.knobRight] = .preset(.upArrow)
        profileA[.topButton] = .preset(.optionKey)
        profileA[.middleButton] = .preset(.returnKey)
        profileA[.bottomButton] = .preset(.tab)

        var profileB = ProfileConfiguration()
        profileB[.knobPress] = .preset(.appSwitcher)
        profileB[.knobDoublePress] = .preset(.switchProfile)
        profileB[.knobLeft] = .preset(.volumeDown)
        profileB[.knobRight] = .preset(.volumeUp)
        profileB[.topButton] = .preset(.playPause)
        profileB[.middleButton] = .preset(.mute)
        profileB[.bottomButton] = .preset(.appSwitcher)

        return AppConfiguration(
            activeProfile: .a,
            profileA: profileA,
            profileB: profileB
        )
    }

    /// Version 0.3 briefly reserved the knob as F18. Restore the last known
    /// pre-migration defaults so upgrading never leaves the sixth native slot dead.
    @discardableResult
    public mutating func restoreLegacyReservedKnobMappings() -> Bool {
        let legacyBinding = ControlBinding.preset(KeyAction.switchProfile)
        var changed = false

        if profileA[.knobPress] == legacyBinding {
            profileA[.knobPress] = .preset(.selectAll)
            changed = true
        }
        if profileB[.knobPress] == legacyBinding {
            profileB[.knobPress] = .preset(.appSwitcher)
            changed = true
        }

        if changed {
            offlineProfile = nil
        }

        return changed
    }
}
