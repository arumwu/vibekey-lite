import Foundation
import IOKit.hid
import Darwin
import VibeKeyLiteCore

enum IOKitHardwareListenerError: LocalizedError {
    case managerOpenFailed(code: IOReturn)

    var errorDescription: String? {
        switch self {
        case let .managerOpenFailed(code):
            let hexCode = String(format: "0x%08X", UInt32(bitPattern: code))
            return "無法開啟 AU05 HID 監聽器（\(hexCode)）。"
        }
    }
}

final class IOKitHardwareListener {
    private let eventHandler: (DeviceEvent, TimeInterval) -> Void
    private let connectionHandler: (Bool) -> Void
    private let deviceRemovalHandler: () -> Void
    private var manager: IOHIDManager?
    private var edgeTracker = HIDKeyEdgeTracker()
    private var connected = false

    init(
        eventHandler: @escaping (DeviceEvent, TimeInterval) -> Void,
        connectionHandler: @escaping (Bool) -> Void,
        deviceRemovalHandler: @escaping () -> Void
    ) {
        self.eventHandler = eventHandler
        self.connectionHandler = connectionHandler
        self.deviceRemovalHandler = deviceRemovalHandler
    }

    deinit {
        stop()
    }

    func start(promptForPermission: Bool) throws {
        stop()
        try IOHIDListenAccess.ensure(promptForPermission: promptForPermission)

        let options = IOOptionBits(kIOHIDOptionsTypeNone)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        let deviceMatching: [String: Any] = [
            kIOHIDVendorIDKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.vendorID),
            kIOHIDProductIDKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.productID),
            kIOHIDPrimaryUsagePageKey: NSNumber(value: 0x0C),
            kIOHIDPrimaryUsageKey: NSNumber(value: 0x01)
        ]
        let elementMatching: [String: Any] = [
            kIOHIDElementUsagePageKey: NSNumber(value: HardwareEventMapper.keyboardUsagePage),
            kIOHIDElementUsageMinKey: NSNumber(value: HardwareEventMapper.acceptedUsages.lowerBound),
            kIOHIDElementUsageMaxKey: NSNumber(value: HardwareEventMapper.acceptedUsages.upperBound),
            kIOHIDElementReportIDKey: NSNumber(value: HardwareEventMapper.keyboardReportID)
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerSetDeviceMatching(manager, deviceMatching as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, elementMatching as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, vibeKeyInputValueCallback, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, vibeKeyDeviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, vibeKeyDeviceRemovalCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let result = IOHIDManagerOpen(manager, options)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            throw IOKitHardwareListenerError.managerOpenFailed(code: result)
        }

        self.manager = manager
        refreshConnectionState()
    }

    func stop() {
        edgeTracker.reset()
        guard let manager else {
            setConnected(false)
            return
        }

        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        setConnected(false)
    }

    fileprivate func receive(result: IOReturn, value: IOHIDValue) {
        guard result == kIOReturnSuccess else { return }

        let element = IOHIDValueGetElement(value)
        let reportID = IOHIDElementGetReportID(element)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)

        guard reportID == HardwareEventMapper.keyboardReportID,
              usagePage == HardwareEventMapper.keyboardUsagePage,
              HardwareEventMapper.acceptedUsages.contains(usage),
              let phase = edgeTracker.transition(
                  usage: usage,
                  integerValue: integerValue
              ),
              let event = HardwareEventMapper.event(
                  forUSBHIDUsage: usage,
                  phase: phase
              ) else {
            return
        }

        let timestamp = HIDMonotonicClock.seconds(
            fromMachAbsoluteTime: IOHIDValueGetTimeStamp(value)
        )
        deliverOnMain { [eventHandler] in
            eventHandler(event, timestamp)
        }
    }

    fileprivate func deviceMatched() {
        edgeTracker.reset()
        setConnected(true)
    }

    fileprivate func deviceRemoved() {
        edgeTracker.reset()
        deliverOnMain { [weak self] in
            guard let self else { return }
            self.deviceRemovalHandler()
            DispatchQueue.main.async { [weak self] in
                self?.refreshConnectionState()
            }
        }
    }

    private func refreshConnectionState() {
        guard let manager else {
            setConnected(false)
            return
        }

        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        setConnected(!devices.isEmpty)
    }

    private func setConnected(_ newValue: Bool) {
        guard connected != newValue else { return }
        connected = newValue
        deliverOnMain { [connectionHandler] in
            connectionHandler(newValue)
        }
    }

    private func deliverOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

enum HIDMonotonicClock {
    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        _ = mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    static var now: TimeInterval {
        seconds(fromMachAbsoluteTime: mach_absolute_time())
    }

    static func seconds(fromMachAbsoluteTime timestamp: UInt64) -> TimeInterval {
        Double(timestamp) * secondsPerTick
    }
}

private func vibeKeyInputValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let listener = Unmanaged<IOKitHardwareListener>.fromOpaque(context).takeUnretainedValue()
    listener.receive(result: result, value: value)
}

private func vibeKeyDeviceMatchingCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    let listener = Unmanaged<IOKitHardwareListener>.fromOpaque(context).takeUnretainedValue()
    listener.deviceMatched()
}

private func vibeKeyDeviceRemovalCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    let listener = Unmanaged<IOKitHardwareListener>.fromOpaque(context).takeUnretainedValue()
    listener.deviceRemoved()
}
