import Foundation
import IOKit.hid
import VibeKeyLiteCore

enum IOKitHardwareConfiguratorError: LocalizedError {
    case managerOpenFailed(code: IOReturn)
    case deviceNotFound
    case deviceOpenFailed(code: IOReturn)
    case reportWriteFailed(index: UInt8, code: IOReturn)

    var errorDescription: String? {
        switch self {
        case let .managerOpenFailed(code):
            "無法開啟 HID 管理器（\(Self.hex(code))）。"
        case .deviceNotFound:
            "找不到 VibeKey（VID 0xFFF1、PID 0x00DD、usagePage 0xFFFC、usage 1）。"
        case let .deviceOpenFailed(code):
            "找到 VibeKey，但無法開啟 custom HID 介面（\(Self.hex(code))）。"
        case let .reportWriteFailed(index, code):
            "寫入硬體動作 index \(index) 失敗（\(Self.hex(code))）。"
        }
    }

    private static func hex(_ code: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: code))
    }
}

final class IOKitHardwareConfigurator: HardwareConfigurator {
    private let descriptor: VibeKeyHIDDescriptor
    private let packetDelay: TimeInterval

    init(
        descriptor: VibeKeyHIDDescriptor = .vibeKey,
        packetDelay: TimeInterval = 0.08
    ) {
        self.descriptor = descriptor
        self.packetDelay = packetDelay
    }

    func apply(layout: HardwareFunctionKeyLayout) throws {
        try IOHIDListenAccess.ensure(promptForPermission: true)

        let options = IOOptionBits(kIOHIDOptionsTypeNone)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: NSNumber(value: descriptor.vendorID),
            kIOHIDProductIDKey: NSNumber(value: descriptor.productID),
            kIOHIDPrimaryUsagePageKey: NSNumber(value: descriptor.usagePage),
            kIOHIDPrimaryUsageKey: NSNumber(value: 1)
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, options)
        guard managerResult == kIOReturnSuccess else {
            throw IOKitHardwareConfiguratorError.managerOpenFailed(code: managerResult)
        }
        defer { IOHIDManagerClose(manager, options) }

        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        guard let device = devices.first else {
            throw IOKitHardwareConfiguratorError.deviceNotFound
        }

        let deviceResult = IOHIDDeviceOpen(device, options)
        guard deviceResult == kIOReturnSuccess else {
            throw IOKitHardwareConfiguratorError.deviceOpenFailed(code: deviceResult)
        }
        defer { IOHIDDeviceClose(device, options) }

        let assignments = layout.indexedFunctionKeys
        for (offset, assignment) in assignments.enumerated() {
            let report = try VibeKeyPacketCodec.shortcutReport(
                index: assignment.index,
                usbHIDUsage: assignment.functionKey.usbHIDUsage
            )

            let writeResult = report.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(descriptor.reportID),
                    buffer.baseAddress!,
                    CFIndex(buffer.count)
                )
            }

            guard writeResult == kIOReturnSuccess else {
                throw IOKitHardwareConfiguratorError.reportWriteFailed(
                    index: assignment.index,
                    code: writeResult
                )
            }

            if offset < assignments.count - 1 {
                Thread.sleep(forTimeInterval: packetDelay)
            }
        }
    }

}
