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
    case knobLeft
    case knobRight
    case topButton
    case middleButton
    case bottomButton

    public var displayName: String {
        switch self {
        case .knobPress: "旋鈕短按"
        case .knobLeft: "旋鈕向左"
        case .knobRight: "旋鈕向右"
        case .topButton: "上鍵"
        case .middleButton: "中鍵"
        case .bottomButton: "下鍵"
        }
    }

    public var sourceFunctionKey: String {
        switch self {
        case .knobPress: "F13"
        case .knobLeft: "F14"
        case .knobRight: "F15"
        case .topButton: "F16"
        case .middleButton: "F17"
        case .bottomButton: "F18"
        }
    }
}

public enum KeyAction: String, CaseIterable, Codable, Sendable {
    case none
    case space
    case returnKey
    case escape
    case tab
    case optionKey
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
        case .optionKey: "Option"
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
        case .none, .space, .returnKey, .escape, .tab, .optionKey:
            .basic
        case .leftArrow, .rightArrow, .upArrow, .downArrow,
             .deleteBackward, .deleteForward, .home, .end, .pageUp, .pageDown:
            .navigation
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
    case editing = "編輯"
    case system = "系統"
    case media = "媒體"
}

public struct ProfileConfiguration: Codable, Equatable, Sendable {
    private var mappings: [InputControl: KeyAction]

    public init(mappings: [InputControl: KeyAction] = [:]) {
        self.mappings = mappings
    }

    public subscript(control: InputControl) -> KeyAction {
        get { mappings[control] ?? .none }
        set { mappings[control] = newValue }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: InputControl.self)
        var decoded: [InputControl: KeyAction] = [:]

        for control in InputControl.allCases {
            decoded[control] = try container.decodeIfPresent(KeyAction.self, forKey: control) ?? KeyAction.none
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
    public var profileA: ProfileConfiguration
    public var profileB: ProfileConfiguration

    public init(
        activeProfile: ProfileID = .a,
        profileA: ProfileConfiguration = .init(),
        profileB: ProfileConfiguration = .init()
    ) {
        self.activeProfile = activeProfile
        self.profileA = profileA
        self.profileB = profileB
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
        profileA[.knobPress] = .none
        profileA[.knobLeft] = .downArrow
        profileA[.knobRight] = .upArrow
        profileA[.topButton] = .optionKey
        profileA[.middleButton] = .returnKey
        profileA[.bottomButton] = .tab

        var profileB = ProfileConfiguration()
        profileB[.knobPress] = .none
        profileB[.knobLeft] = .volumeDown
        profileB[.knobRight] = .volumeUp
        profileB[.topButton] = .playPause
        profileB[.middleButton] = .mute
        profileB[.bottomButton] = .appSwitcher

        return AppConfiguration(
            activeProfile: .a,
            profileA: profileA,
            profileB: profileB
        )
    }
}

public struct KeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let option = KeyModifiers(rawValue: 1 << 3)
}

public enum MediaAction: Equatable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
    case previousTrack
    case nextTrack
    case playPause
}

public enum ResolvedAction: Equatable, Sendable {
    case none
    case keyStroke(keyCode: UInt16, modifiers: KeyModifiers)
    case media(MediaAction)
    case switchProfile
}

public enum ActionResolver {
    public static func resolve(_ action: KeyAction) -> ResolvedAction {
        switch action {
        case .none: .none
        case .space: .keyStroke(keyCode: 49, modifiers: [])
        case .returnKey: .keyStroke(keyCode: 36, modifiers: [])
        case .escape: .keyStroke(keyCode: 53, modifiers: [])
        case .tab: .keyStroke(keyCode: 48, modifiers: [])
        case .optionKey: .keyStroke(keyCode: 58, modifiers: [])
        case .leftArrow: .keyStroke(keyCode: 123, modifiers: [])
        case .rightArrow: .keyStroke(keyCode: 124, modifiers: [])
        case .downArrow: .keyStroke(keyCode: 125, modifiers: [])
        case .upArrow: .keyStroke(keyCode: 126, modifiers: [])
        case .deleteBackward: .keyStroke(keyCode: 51, modifiers: [])
        case .deleteForward: .keyStroke(keyCode: 117, modifiers: [])
        case .home: .keyStroke(keyCode: 115, modifiers: [])
        case .end: .keyStroke(keyCode: 119, modifiers: [])
        case .pageUp: .keyStroke(keyCode: 116, modifiers: [])
        case .pageDown: .keyStroke(keyCode: 121, modifiers: [])
        case .selectAll: .keyStroke(keyCode: 0, modifiers: .command)
        case .copy: .keyStroke(keyCode: 8, modifiers: .command)
        case .paste: .keyStroke(keyCode: 9, modifiers: .command)
        case .cut: .keyStroke(keyCode: 7, modifiers: .command)
        case .undo: .keyStroke(keyCode: 6, modifiers: .command)
        case .redo: .keyStroke(keyCode: 6, modifiers: [.command, .shift])
        case .save: .keyStroke(keyCode: 1, modifiers: .command)
        case .appSwitcher: .keyStroke(keyCode: 48, modifiers: .command)
        case .spotlight: .keyStroke(keyCode: 49, modifiers: .command)
        case .screenshot: .keyStroke(keyCode: 23, modifiers: [.command, .shift])
        case .missionControl: .keyStroke(keyCode: 126, modifiers: .control)
        case .switchProfile: .switchProfile
        case .volumeUp: .media(.volumeUp)
        case .volumeDown: .media(.volumeDown)
        case .mute: .media(.mute)
        case .brightnessUp: .media(.brightnessUp)
        case .brightnessDown: .media(.brightnessDown)
        case .previousTrack: .media(.previousTrack)
        case .nextTrack: .media(.nextTrack)
        case .playPause: .media(.playPause)
        }
    }
}
