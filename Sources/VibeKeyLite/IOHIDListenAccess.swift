import Foundation
import IOKit.hid

enum IOHIDListenAccessError: LocalizedError {
    case denied
    case permissionRequired

    var errorDescription: String? {
        switch self {
        case .denied:
            "輸入監控權限已被拒絕。請到「系統設定 → 隱私權與安全性 → 輸入監控」允許 VibeKey Lite。"
        case .permissionRequired:
            "已要求輸入監控權限。允許 VibeKey Lite 後，請按「套用並重啟」。"
        }
    }
}

enum IOHIDListenAccess {
    static var isGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func ensure(promptForPermission: Bool) throws {
        let requestType = kIOHIDRequestTypeListenEvent
        switch IOHIDCheckAccess(requestType) {
        case kIOHIDAccessTypeGranted:
            return
        case kIOHIDAccessTypeDenied:
            throw IOHIDListenAccessError.denied
        case kIOHIDAccessTypeUnknown:
            guard promptForPermission,
                  IOHIDRequestAccess(requestType),
                  IOHIDCheckAccess(requestType) == kIOHIDAccessTypeGranted else {
                throw IOHIDListenAccessError.permissionRequired
            }
        default:
            throw IOHIDListenAccessError.permissionRequired
        }
    }
}
