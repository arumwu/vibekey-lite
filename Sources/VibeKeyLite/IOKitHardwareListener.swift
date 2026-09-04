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
    case invalidPowerSavingTransition

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
        case .invalidPowerSavingTransition:
            "AU05 省電模式狀態已改變；請重新啟動 VibeKey Lite。"
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
    private let powerResponseHandler: (VibeKeyPowerResponse) -> Void
    private let noticeHandler: (VibeKeyDeviceNotice) -> Void
    private let powerSavingWakeHandler: () -> Void
    private let connectionHandler: (Bool) -> Void
    private let failureHandler: (Error) -> Void
    private let deviceRemovalHandler: () -> Void
    private let shouldRemainOnline: () -> Bool
    private var manager: IOHIDManager?
    private var inputDevice: IOHIDDevice?
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private var inputReportCapacity = 0
    private var wakeDevice: IOHIDDevice?
    private var wakeReportBuffer: UnsafeMutablePointer<UInt8>?
    private var wakeReportCapacity = 0
    private var heartbeatTimer: Timer?
    private var heartbeatFailureReported = false
    private var heartbeatInFlight = false
    private var onlineGeneration: UInt64 = 0
    private var pressedControls: Set<InputControl> = []
    private var connected = false
    private var isRunning = false
    private var parkedForPowerSaving = false
    private var wakeRequestDelivered = false
    private var nativeWakeReportID: UInt32?
    private let heartbeatInterval: TimeInterval
    private let startupResetDelay: TimeInterval
    private let logger = Logger(
        subsystem: "io.github.arumwu.VibeKeyLite",
        category: "HID"
    )

    var hasAttachedDevice: Bool {
        inputDevice != nil
    }

    /// Refreshes runtime-only power information. This performs GET requests
    /// only and never changes the device's saved timers.
    func refreshPowerStatus() {
        guard !parkedForPowerSaving else { return }
        sendPowerQueriesAsynchronously()
    }

    /// Stops host-online traffic without closing either HID interface. The
    /// AU05 immediately regains its native mapping and can use its own saved
    /// standby and power-off timers.
    func enterPowerSavingMode() -> Error? {
        guard inputDevice != nil, connected, !parkedForPowerSaving else {
            return IOKitHardwareListenerError.invalidPowerSavingTransition
        }
        let error = leaveOnlineMode()
        guard error == nil else { return error }
        parkedForPowerSaving = true
        wakeRequestDelivered = false
        nativeWakeReportID = nil
        pressedControls.removeAll(keepingCapacity: true)
        logger.notice("AU05 handed back to native power saving")
        return nil
    }

    /// Re-enters host-online mode after the first native wake input.
    func resumeFromPowerSaving() -> Error? {
        guard parkedForPowerSaving, let device = inputDevice else {
            return IOKitHardwareListenerError.invalidPowerSavingTransition
        }
        guard shouldRemainOnline() else {
            return IOKitHardwareListenerError.onlinePrerequisiteLost
        }
        if let error = enterOnlineModeSynchronously(on: device) {
            return error
        }

        parkedForPowerSaving = false
        wakeRequestDelivered = false
        nativeWakeReportID = nil
        heartbeatFailureReported = false
        onlineGeneration &+= 1
        startHeartbeat()
        refreshPowerStatus()
        logger.notice("AU05 resumed host-online mode after native wake input")
        return nil
    }

    init(
        heartbeatInterval: TimeInterval = 0.8,
        startupResetDelay: TimeInterval = 0.08,
        eventHandler: @escaping (DeviceEvent, TimeInterval) -> Void,
        powerResponseHandler: @escaping (VibeKeyPowerResponse) -> Void,
        noticeHandler: @escaping (VibeKeyDeviceNotice) -> Void,
        powerSavingWakeHandler: @escaping () -> Void,
        connectionHandler: @escaping (Bool) -> Void,
        failureHandler: @escaping (Error) -> Void,
        deviceRemovalHandler: @escaping () -> Void,
        shouldRemainOnline: @escaping () -> Bool
    ) {
        self.heartbeatInterval = heartbeatInterval
        self.startupResetDelay = startupResetDelay
        self.eventHandler = eventHandler
        self.powerResponseHandler = powerResponseHandler
        self.noticeHandler = noticeHandler
        self.powerSavingWakeHandler = powerSavingWakeHandler
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
        let customMatching: [String: Any] = [
            kIOHIDVendorIDKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.vendorID),
            kIOHIDProductIDKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.productID),
            kIOHIDPrimaryUsagePageKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.usagePage),
            kIOHIDPrimaryUsageKey: NSNumber(value: 1)
        ]
        let nativeWakeMatching: [String: Any] = [
            kIOHIDVendorIDKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.vendorID),
            kIOHIDProductIDKey: NSNumber(value: VibeKeyHIDDescriptor.vibeKey.productID),
            kIOHIDPrimaryUsagePageKey: NSNumber(value: 0x000C),
            kIOHIDPrimaryUsageKey: NSNumber(value: 1)
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerSetDeviceMatchingMultiple(
            manager,
            [customMatching as CFDictionary, nativeWakeMatching as CFDictionary] as CFArray
        )
        IOHIDManagerRegisterDeviceMatchingCallback(manager, vibeKeyDeviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, vibeKeyDeviceRemovalCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        self.manager = manager
        isRunning = true
        let result = IOHIDManagerOpen(manager, options)
        guard result == kIOReturnSuccess else {
            isRunning = false
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            self.manager = nil
            throw IOKitHardwareListenerError.managerOpenFailed(code: result)
        }
    }

    @discardableResult
    func stop() -> Error? {
        isRunning = false
        let offlineError = leaveOnlineMode()
        guard let manager else {
            detachInputDevice()
            detachWakeDevice()
            setConnected(false)
            parkedForPowerSaving = false
            wakeRequestDelivered = false
            nativeWakeReportID = nil
            return offlineError
        }

        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        detachInputDevice()
        detachWakeDevice()
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        parkedForPowerSaving = false
        wakeRequestDelivered = false
        nativeWakeReportID = nil
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

        if let notice = VibeKeyDeviceNoticeParser.parse(reportID: reportID, report: bytes) {
            logger.notice(
                "AU05 notice: \(String(describing: notice), privacy: .public) powerSaving=\(self.parkedForPowerSaving, privacy: .public)"
            )
            deliverOnMain { [noticeHandler] in
                noticeHandler(notice)
            }
            return
        }

        if let powerResponse = VibeKeyPowerResponseParser.parse(
            reportID: reportID,
            report: bytes
        ) {
            deliverOnMain { [powerResponseHandler] in
                powerResponseHandler(powerResponse)
            }
            return
        }

        guard !parkedForPowerSaving else {
            return
        }

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
        guard isRunning else { return }
        if primaryUsagePage(for: device) == 0x000C {
            attachWakeDevice(device)
            return
        }

        guard inputDevice == nil else { return }
        attachInputDevice(device)

        guard shouldRemainOnline() else {
            deliverOnMain { [failureHandler] in
                failureHandler(IOKitHardwareListenerError.onlinePrerequisiteLost)
            }
            return
        }

        // A host reboot can interrupt the previous process before it sends the
        // offline packet. Always establish a clean native baseline before a
        // fresh app session enters online mode. This does not rewrite any of
        // the six shortcuts stored in device flash.
        if let error = enterOnlineModeSynchronously(on: device, resetFirst: true) {
            deliverOnMain { [failureHandler] in failureHandler(error) }
            return
        }

        heartbeatFailureReported = false
        parkedForPowerSaving = false
        wakeRequestDelivered = false
        nativeWakeReportID = nil
        onlineGeneration &+= 1
        startHeartbeat()
        setConnected(true)
        refreshPowerStatus()
        logger.notice("AU05 software-online mode active")
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        if let wakeDevice, CFEqual(wakeDevice, device) {
            detachWakeDevice()
            return
        }

        guard let inputDevice, CFEqual(inputDevice, device) else { return }
        invalidateHeartbeatTimer()
        parkedForPowerSaving = false
        wakeRequestDelivered = false
        nativeWakeReportID = nil
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

    private func attachWakeDevice(_ device: IOHIDDevice) {
        guard wakeDevice == nil else { return }
        let capacity = maxInputReportSize(for: device)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            capacity,
            vibeKeyNativeWakeInputReportCallback,
            context
        )
        wakeDevice = device
        wakeReportBuffer = buffer
        wakeReportCapacity = capacity
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

    private func detachWakeDevice() {
        guard let device = wakeDevice,
              let buffer = wakeReportBuffer else {
            wakeDevice = nil
            wakeReportBuffer = nil
            wakeReportCapacity = 0
            return
        }

        let capacity = wakeReportCapacity
        IOHIDDeviceRegisterInputReportCallback(device, buffer, capacity, nil, nil)
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
        wakeDevice = nil
        wakeReportBuffer = nil
        wakeReportCapacity = 0
    }

    fileprivate func receiveNativeWake(
        result: IOReturn,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess, reportLength > 0 else { return }
        var bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
        if reportID != 0, bytes.first == UInt8(truncatingIfNeeded: reportID) {
            bytes.removeFirst()
        }
        guard parkedForPowerSaving, !wakeRequestDelivered else { return }

        let isNeutral = !bytes.contains(where: { $0 != 0 })
        if !isNeutral {
            if nativeWakeReportID == nil {
                nativeWakeReportID = reportID
                logger.notice("Native wake press began id=\(reportID, privacy: .public)")
            }
            return
        }

        // Wait until the same native report becomes neutral. This lets the
        // device finish the complete first shortcut, including key-up, before
        // host-online mode suppresses native output again.
        guard nativeWakeReportID == reportID else { return }
        nativeWakeReportID = nil
        logger.notice("Native wake press completed id=\(reportID, privacy: .public)")
        requestWakeFromPowerSavingIfNeeded()
    }

    private func requestWakeFromPowerSavingIfNeeded() {
        guard parkedForPowerSaving, !wakeRequestDelivered else { return }
        wakeRequestDelivered = true
        deliverOnMain { [powerSavingWakeHandler] in powerSavingWakeHandler() }
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

    private func sendPowerQueriesAsynchronously() {
        guard let device = inputDevice else { return }
        let reports = VibeKeyPowerQuery.allCases.compactMap {
            try? VibeKeyPacketCodec.powerQueryReport($0)
        }
        guard reports.count == VibeKeyPowerQuery.allCases.count else { return }

        HIDOutputSerialQueue.queue.async { [logger] in
            for report in reports {
                let result = Self.write(report: report, to: device)
                guard result == kIOReturnSuccess else {
                    logger.error(
                        "AU05 power query failed: \(String(format: "0x%08X", UInt32(bitPattern: result)), privacy: .public)"
                    )
                    return
                }
            }
        }
    }

    private func enterOnlineModeSynchronously(
        on device: IOHIDDevice,
        resetFirst: Bool = false
    ) -> Error? {
        let offlineReport: [UInt8]?
        if resetFirst {
            guard let report = try? VibeKeyPacketCodec.softwareOnlineReport(false) else {
                return IOKitHardwareListenerError.offlineWriteFailed(code: kIOReturnError)
            }
            offlineReport = report
        } else {
            offlineReport = nil
        }

        guard let onlineReport = try? VibeKeyPacketCodec.softwareOnlineReport(true),
              let heartbeatReport = try? VibeKeyPacketCodec.heartbeatReport() else {
            return IOKitHardwareListenerError.heartbeatWriteFailed(code: kIOReturnError)
        }

        return HIDOutputSerialQueue.queue.sync {
            if let offlineReport {
                let offlineResult = Self.write(report: offlineReport, to: device)
                guard offlineResult == kIOReturnSuccess else {
                    return IOKitHardwareListenerError.offlineWriteFailed(code: offlineResult)
                }
                logger.notice("AU05 startup reset to native mode")
                Thread.sleep(forTimeInterval: startupResetDelay)
            }

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
              let heartbeatReport = try? VibeKeyPacketCodec.heartbeatReport(),
              !heartbeatInFlight else { return }

        heartbeatInFlight = true
        let generation = onlineGeneration

        HIDOutputSerialQueue.queue.async { [weak self] in
            let result = Self.write(report: heartbeatReport, to: device)
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

    private func primaryUsagePage(for device: IOHIDDevice) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString),
              CFGetTypeID(value) == CFNumberGetTypeID() else {
            return -1
        }

        var usagePage: Int32 = -1
        CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .sInt32Type, &usagePage)
        return Int(usagePage)
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

private func vibeKeyNativeWakeInputReportCallback(
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
    listener.receiveNativeWake(
        result: result,
        reportID: reportID,
        report: report,
        reportLength: reportLength
    )
}
