import ApplicationServices
import Foundation

enum AccessibilityAccess {
    static func isTrusted(promptForPermission: Bool) -> Bool {
        guard promptForPermission else { return AXIsProcessTrusted() }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}
