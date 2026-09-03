import Foundation

public enum VibeKeyPacketCodecError: Error, Equatable {
    case invalidPlaintextLength(actual: Int)
    case invalidCiphertextLength(actual: Int)
    case tooManyShortcutEntries(maximum: Int, actual: Int)
}

extension VibeKeyPacketCodecError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidPlaintextLength(actual):
            "VibeKey 明文必須是 64 bytes，目前是 \(actual) bytes。"
        case let .invalidCiphertextLength(actual):
            "VibeKey 密文長度必須是 8 的倍數，目前是 \(actual) bytes。"
        case let .tooManyShortcutEntries(maximum, actual):
            "裝置原生快捷鍵最多只能有 \(maximum) 個按鍵，目前是 \(actual) 個。"
        }
    }
}

public enum VibeKeyPacketCodec {
    public static let reportID: UInt8 = 0x55
    public static let packetLength = 64

    private static let key: [UInt32] = [
        0xCAA5BACA,
        0xBC2A8A6D,
        0xCA5A9EBA,
        0x9BB88BCA
    ]
    private static let delta: UInt32 = 0x9E3779B9

    /// Vendor software sends this once per second while its host-side actions
    /// are active. Native recovery after a stopped heartbeat has been observed,
    /// but the firmware watchdog duration still requires controlled testing.
    public static func heartbeatPlaintext() -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: packetLength)
        plaintext[0] = 0x06
        plaintext[1] = 0x01
        plaintext[2] = 0x23
        plaintext[4] = 0x01
        return plaintext
    }

    public static func heartbeatReport() throws -> [UInt8] {
        try outputReport(encrypting: heartbeatPlaintext())
    }

    public static func softwareOnlinePlaintext(_ enabled: Bool) -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x10
        plaintext[4] = enabled ? 0x03 : 0x00
        return plaintext
    }

    public static func softwareOnlineReport(_ enabled: Bool) throws -> [UInt8] {
        try outputReport(encrypting: softwareOnlinePlaintext(enabled))
    }

    /// Input callbacks differ on whether report ID 0x55 is included. Only
    /// complete TEA blocks are needed to decode the event header.
    public static func decryptInputReport(_ report: [UInt8]) throws -> [UInt8] {
        let payload = report.first == reportID ? Array(report.dropFirst()) : report
        let completeLength = payload.count - (payload.count % 8)
        guard completeLength > 0 else {
            throw VibeKeyPacketCodecError.invalidCiphertextLength(actual: payload.count)
        }
        return try decrypt(Array(payload.prefix(completeLength)))
    }

    /// Builds the 64-byte cleartext command that assigns one device slot to a USB HID key usage.
    public static func shortcutPlaintext(index: UInt8, usbHIDUsage: UInt8) -> [UInt8] {
        shortcutPlaintext(
            index: index,
            validatedEntries: [
                NativeShortcutEntry(pageAndSign: 0x02, value: usbHIDUsage)
            ]
        )
    }

    /// Builds the 64-byte cleartext command for an on-device shortcut or chord.
    public static func shortcutPlaintext(
        index: UInt8,
        shortcut: NativeShortcut
    ) throws -> [UInt8] {
        try shortcutPlaintext(index: index, entries: shortcut.entries)
    }

    /// Entry-based overload used by importers before they construct a validated `NativeShortcut`.
    public static func shortcutPlaintext(
        index: UInt8,
        entries: [NativeShortcutEntry]
    ) throws -> [UInt8] {
        guard entries.count <= NativeShortcut.maximumEntryCount else {
            throw VibeKeyPacketCodecError.tooManyShortcutEntries(
                maximum: NativeShortcut.maximumEntryCount,
                actual: entries.count
            )
        }

        let shortcut = try NativeShortcut(entries: entries, displayName: "自訂快捷鍵")
        return shortcutPlaintext(index: index, validatedEntries: shortcut.entries)
    }

    private static func shortcutPlaintext(
        index: UInt8,
        validatedEntries entries: [NativeShortcutEntry]
    ) -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x06
        plaintext[2] = 0x50
        plaintext[3] = 0x04
        plaintext[4] = index
        plaintext[5] = 0x01
        plaintext[6] = UInt8(entries.count)

        for (entryIndex, entry) in entries.enumerated() {
            plaintext[7 + (entryIndex * 2)] = entry.pageAndSign
            plaintext[8 + (entryIndex * 2)] = entry.value
        }

        return plaintext
    }

    public static func shortcutReport(index: UInt8, usbHIDUsage: UInt8) throws -> [UInt8] {
        try outputReport(
            encrypting: shortcutPlaintext(index: index, usbHIDUsage: usbHIDUsage)
        )
    }

    public static func shortcutReport(
        index: UInt8,
        shortcut: NativeShortcut
    ) throws -> [UInt8] {
        try outputReport(
            encrypting: shortcutPlaintext(index: index, shortcut: shortcut)
        )
    }

    public static func fixedFunctionPlaintext(
        index: UInt8,
        functionCode: UInt8
    ) -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x06
        plaintext[2] = 0x10
        plaintext[3] = 0x04
        plaintext[5] = index
        plaintext[6] = functionCode
        return plaintext
    }

    public static func fixedFunctionReport(
        index: UInt8,
        functionCode: UInt8
    ) throws -> [UInt8] {
        try outputReport(
            encrypting: fixedFunctionPlaintext(
                index: index,
                functionCode: functionCode
            )
        )
    }

    /// The device expects report ID 0x55 followed by the first 63 encrypted bytes.
    public static func outputReport(encrypting plaintext: [UInt8]) throws -> [UInt8] {
        let encrypted = try encrypt(plaintext)
        return [reportID] + encrypted.prefix(packetLength - 1)
    }

    /// Encrypts eight 64-bit blocks with 32-round TEA using little-endian words.
    public static func encrypt(_ plaintext: [UInt8]) throws -> [UInt8] {
        guard plaintext.count == packetLength else {
            throw VibeKeyPacketCodecError.invalidPlaintextLength(actual: plaintext.count)
        }

        var encrypted = [UInt8]()
        encrypted.reserveCapacity(packetLength)

        for offset in stride(from: 0, to: plaintext.count, by: 8) {
            var left = readLittleEndianWord(plaintext, offset: offset)
            var right = readLittleEndianWord(plaintext, offset: offset + 4)
            var sum: UInt32 = 0

            for _ in 0..<32 {
                sum = sum &+ delta
                left = left &+ (
                    ((right << 4) &+ key[0])
                        ^ (right &+ sum)
                        ^ ((right >> 5) &+ key[1])
                )
                right = right &+ (
                    ((left << 4) &+ key[2])
                        ^ (left &+ sum)
                        ^ ((left >> 5) &+ key[3])
                )
            }

            appendLittleEndianWord(left, to: &encrypted)
            appendLittleEndianWord(right, to: &encrypted)
        }

        return encrypted
    }

    public static func decrypt(_ ciphertext: [UInt8]) throws -> [UInt8] {
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: 8) else {
            throw VibeKeyPacketCodecError.invalidCiphertextLength(actual: ciphertext.count)
        }

        var plaintext = [UInt8]()
        plaintext.reserveCapacity(ciphertext.count)

        for offset in stride(from: 0, to: ciphertext.count, by: 8) {
            var left = readLittleEndianWord(ciphertext, offset: offset)
            var right = readLittleEndianWord(ciphertext, offset: offset + 4)
            var sum: UInt32 = 0xC6EF3720

            for _ in 0..<32 {
                right = right &- (
                    ((left << 4) &+ key[2])
                        ^ (left &+ sum)
                        ^ ((left >> 5) &+ key[3])
                )
                left = left &- (
                    ((right << 4) &+ key[0])
                        ^ (right &+ sum)
                        ^ ((right >> 5) &+ key[1])
                )
                sum = sum &- delta
            }

            appendLittleEndianWord(left, to: &plaintext)
            appendLittleEndianWord(right, to: &plaintext)
        }

        return plaintext
    }

    private static func readLittleEndianWord(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func appendLittleEndianWord(_ word: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: word))
        bytes.append(UInt8(truncatingIfNeeded: word >> 8))
        bytes.append(UInt8(truncatingIfNeeded: word >> 16))
        bytes.append(UInt8(truncatingIfNeeded: word >> 24))
    }
}
