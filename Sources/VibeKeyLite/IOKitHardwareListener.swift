import Foundation
import IOKit.hid
import Darwin
import OSLog
import VibeKeyLiteCore

enum IOKitHardwareListenerError: LocalizedError {
    case managerOpenFailed(code: IOReturn)
    case heartbeatWriteFailed(code: IOReturn)
    case offlineWriteFailed(code: IOReturn)
    case onlinePrerequisiteLost

    var errorDescription: String? {
        switch self {
        case let .managerOpenFailed(code):
            "無法開啟 AU05 HID 監聽器（\(Self.hex(code))）。"
        case let .heartbeatWriteFailed(code):
            "AU05 線上模式中斷（\(Self.hex(code))）；已退回裝置原生按鍵。"
        case let .offlineWriteFailed(code):
            "AU05 離線指令失敗（\(Self.hex(code))）；請結束 App，等待裝置自動恢復。"
        case .onlinePrerequisiteLost:
            "進階手勢已停止；AU05 已退回裝置原生按鍵。"
        }
    }

    private static func hex(_ code: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: code))
    }
}

/// Runs AU05's software-online protocol. The firmware suppresses its native
/// output while online reports continue. A normal stop explicitly sends the
/// offline report; firmware timeout is the crash-only fallback.
final class IOKitHardwareListener {
    private let eventHandler: (DeviceEvent, TimeInterval) -> Void
    private let connectionHandler: (Bool) -> Void
    private let failureHandler: (Error) -> Void
    private let deviceRemovalHandler: () -> Void
    private let shouldRemainOnline: () -> Bool
    private var manager: IOHIDManager?
    private var inputDevice: IOHIDDevice?
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private var inputReportCapacity = 0
    private var heartbeatTimer: Timer?
    private var heartbeatFailureReported = false
    private var heartbeatInFlight = false
    private var onlineGeneration: UInt64 = 0
    private var pressedControls: Set<InputControl> = []
    private var connected = false
    private let heartbeatInterval: TimeInterval
    private let logger = Logger(
        subsystem: "io.github.arumwu.VibeKeyLite",
        category: "HID"
    )

    var hasAttachedDevice: Bool {
        inputDevice != nil
    }

    init(
        heartbeatInterval: TimeInterval = 0.8,
        eventHandler: @escaping (DeviceEvent, TimeInterval) -> Void,
        connectionHandler: @escaping (Bool) -> Void,
        failureHandler: @escaping (Error) -> Void,
        deviceRemovalHandler: @escaping () -> Void,
        shouldRemainOnline: @escaping () -> Bool
    ) {
        self.heartbeatInterval = heartbeatInterval
        self.eventHandler = eventHandler
        self.connectionHandler = connectionHandler
        self.failureHandler = failureHandler
        self.deviceRemovalHandler = deviceRemovalHandler
        self.shouldRemainOnline = shouldRemainOnline
    }

    deinit {
        _ = stop()
    }

    func start(promptForPermission: Bool) throws {
        _ = stop()
        try IOHIDListenAccess.ensure(promptForPermission: promptForPermission)

        let options = IOOptionBits(kIOHIDOptionsTypeNone)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.vendorID),
            kIOHIDProductIDKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.productID),
            kIOHIDPrimaryUsagePageKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.usagePage),
            kIOHIDPrimaryUsageKey: NSNumber(value: 1)
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, vibeKeyDeviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, vibeKeyDeviceRemovalCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let result = IOHIDManagerOpen(manager, options)
        guard result == kIOReturnSuccess else {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            throw IOKitHardwareListenerError.managerOpenFailed(code: result)
        }

        self.manager = manager
    }

    @discardableResult
    func stop() -> Error? {
        let offlineError = leaveOnlineMode()
        guard let manager else {
            detachInputDevice()
            setConnected(false)
            return offlineError
        }

        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        detachInputDevice()
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        setConnected(false)
        return offlineError
    }

    fileprivate func receive(
        result: IOReturn,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess, reportLength > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
        guard let event = RawDeviceEventParser.parse(reportID: reportID, report: bytes),
              let event = deduplicated(event) else {
            return
        }

        logger.notice("Raw AU05 event: \(String(describing: event), privacy: .public)")
        let timestamp = HIDMonotonicClock.now
        deliverOnMain { [eventHandler] in
            eventHandler(event, timestamp)
        }
    }

    fileprivate func deviceMatched(_ device: IOHIDDevice) {
        guard inputDevice == nil else { return }
        attachInputDevice(device)

        guard shouldRemainOnline() else {
            deliverOnMain { [failureHandler] in
                failureHandler(IOKitHardwareListenerError.onlinePrerequisiteLost)
            }
            return
        }

        if let error = enterOnlineModeSynchronously(on: device) {
            deliverOnMain { [failureHandler] in failureHandler(error) }
            return
        }

        heartbeatFailureReported = false
        onlineGeneration &+= 1
        startHeartbeat()
        setConnected(true)
        logger.notice("AU05 software-online mode active")
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        guard let inputDevice, CFEqual(inputDevice, device) else { return }
        invalidateHeartbeatTimer()
        detachInputDevice()
        deliverOnMain { [weak self] in
            guard let self else { return }
            self.deviceRemovalHandler()
        }
    }

    private func attachInputDevice(_ device: IOHIDDevice) {
        pressedControls.removeAll(keepingCapacity: true)
        let capacity = maxInputReportSize(for: device)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            capacity,
            vibeKeyInputReportCallback,
            context
        )

        inputDevice = device
        inputReportBuffer = buffer
        inputReportCapacity = capacity
    }

    private func detachInputDevice() {
        guard let device = inputDevice,
              let buffer = inputReportBuffer else {
            inputDevice = nil
            inputReportBuffer = nil
            inputReportCapacity = 0
            setConnected(false)
            return
        }

        let capacity = inputReportCapacity
        IOHIDDeviceRegisterInputReportCallback(device, buffer, capacity, nil, nil)
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
        inputDevice = nil
        inputReportBuffer = nil
        inputReportCapacity = 0
        pressedControls.removeAll(keepingCapacity: true)
        setConnected(false)
    }

    private func deduplicated(_ event: DeviceEvent) -> DeviceEvent? {
        guard case let .key(control, phase) = event,
              control != .knobLeft,
              control != .knobRight else {
            return event
        }

        switch phase {
        case .down:
            return pressedControls.insert(control).inserted ? event : nil
        case .up:
            return pressedControls.remove(control) != nil ? event : nil
        }
    }

    private func startHeartbeat() {
        invalidateHeartbeatTimer()
        // Keep this on the main run loop deliberately. If the UI thread hangs,
        // heartbeats stop and the AU05 firmware can fall back to native keys.
        let timer = Timer(timeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeatAsynchronously()
        }
        heartbeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func invalidateHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        heartbeatInFlight = false
        onlineGeneration &+= 1
    }

    private func enterOnlineModeSynchronously(on device: IOHIDDevice) -> Error? {
        guard let onlineReport = try? VibeKeyPacketCodec.softwareOnlineReport(true),
              let heartbeatReport = try? VibeKeyPacketCodec.heartbeatReport() else {
            return IOKitHardwareListenerError.heartbeatWriteFailed(code: kIOReturnError)
        }

        return HIDOutputSerialQueue.queue.sync {
            let onlineResult = Self.write(report: onlineReport, to: device)
            guard onlineResult == kIOReturnSuccess else {
                return IOKitHardwareListenerError.heartbeatWriteFailed(code: onlineResult)
            }
            let heartbeatResult = Self.write(report: heartbeatReport, to: device)
            guard heartbeatResult != kIOReturnSuccess else { return nil }

            guard let offlineReport = try? VibeKeyPacketCodec.softwareOnlineReport(false) else {
                return IOKitHardwareListenerError.heartbeatWriteFailed(code: heartbeatResult)
            }
            let offlineResult = Self.write(report: offlineReport, to: device)
            guard offlineResult == kIOReturnSuccess else {
                return IOKitHardwareListenerError.offlineWriteFailed(code: offlineResult)
            }
            return IOKitHardwareListenerError.heartbeatWriteFailed(code: heartbeatResult)
        }
    }

    private func leaveOnlineMode() -> Error? {
        invalidateHeartbeatTimer()
        guard let device = inputDevice,
              let offlineReport = try? VibeKeyPacketCodec.softwareOnlineReport(false) else {
            return nil
        }

        // A serial barrier prevents a queued heartbeat from being sent after offline.
        let result = HIDOutputSerialQueue.queue.sync {
            Self.write(report: offlineReport, to: device)
        }
        guard result != kIOReturnSuccess else { return nil }
        logger.error(
            "AU05 offline report failed: \(String(format: "0x%08X", UInt32(bitPattern: result)), privacy: .public)"
        )
        return IOKitHardwareListenerError.offlineWriteFailed(code: result)
    }

    private func sendHeartbeatAsynchronously() {
        guard shouldRemainOnline() else {
            failureHandler(IOKitHardwareListenerError.onlinePrerequisiteLost)
            return
        }

        guard let device = inputDevice,
              let onlineReport = try? VibeKeyPacketCodec.softwareOnlineReport(true),
              let heartbeatReport = try? VibeKeyPacketCodec.heartbeatReport(),
              !heartbeatInFlight else { return }

        heartbeatInFlight = true
        let generation = onlineGeneration

        HIDOutputSerialQueue.queue.async { [weak self] in
            let onlineResult = Self.write(report: onlineReport, to: device)
            let result = onlineResult == kIOReturnSuccess
                ? Self.write(report: heartbeatReport, to: device)
                : onlineResult
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.onlineGeneration else { return }
                self.heartbeatInFlight = false
                guard result != kIOReturnSuccess,
                      !self.heartbeatFailureReported else { return }
                self.heartbeatFailureReported = true
                // AppDelegate owns the one authoritative stop/offline attempt so
                // it can remember when native-mode confirmation fails.
                self.failureHandler(
                    IOKitHardwareListenerError.heartbeatWriteFailed(code: result)
                )
            }
        }
    }

    private static func write(report: [UInt8], to device: IOHIDDevice) -> IOReturn {
        report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(VibeKeyPacketCodec.reportID),
                buffer.baseAddress!,
                CFIndex(buffer.count)
            )
        }
    }

    private func maxInputReportSize(for device: IOHIDDevice) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString),
              CFGetTypeID(value) == CFNumberGetTypeID() else {
            return VibeKeyPacketCodec.packetLength
        }

        var reportedSize: Int32 = 0
        CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .sInt32Type, &reportedSize)
        return max(Int(reportedSize), VibeKeyPacketCodec.packetLength)
    }

    private func setConnected(_ newValue: Bool) {
        guard connected != newValue else { return }
        connected = newValue
        deliverOnMain { [connectionHandler] in connectionHandler(newValue) }
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

    static func seconds(fromMachAbsoluteTime ticks: UInt64) -> TimeInterval {
        Double(ticks) * secondsPerTick
    }
}

private func vibeKeyDeviceMatchingCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    let listener = Unmanaged<IOKitHardwareListener>.fromOpaque(context).takeUnretainedValue()
    listener.deviceMatched(device)
}

private func vibeKeyDeviceRemovalCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard result == kIOReturnSuccess, let context else { return }
    let listener = Unmanaged<IOKitHardwareListener>.fromOpaque(context).takeUnretainedValue()
    listener.deviceRemoved(device)
}

private func vibeKeyInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let listener = Unmanaged<IOKitHardwareListener>.fromOpaque(context).takeUnretainedValue()
    listener.receive(
        result: result,
        reportID: reportID,
        report: report,
        reportLength: reportLength
    )
}
