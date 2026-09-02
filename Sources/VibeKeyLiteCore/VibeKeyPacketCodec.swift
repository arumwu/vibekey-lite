import Foundation

public enum VibeKeyPacketCodecError: Error, Equatable {
    case invalidPlaintextLength(actual: Int)
}

extension VibeKeyPacketCodecError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidPlaintextLength(actual):
            "VibeKey 明文必須是 64 bytes，目前是 \(actual) bytes。"
        }
    }
}

public enum VibeKeyPacketCodec {
    public static let reportID: UInt8 = 0x55
    public static let packetLength = 64

    private static let key: [UInt32] = [
        0xCABAA5CA,
        0x6D8A2ABC,
        0xBA9E5ACA,
        0xCA8BB89B
    ]
    private static let delta: UInt32 = 0x9E3779B9

    /// Builds the 64-byte cleartext command that assigns one device slot to a USB HID key usage.
    public static func shortcutPlaintext(index: UInt8, usbHIDUsage: UInt8) -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x06
        plaintext[2] = 0x50
        plaintext[3] = 0x04
        plaintext[4] = index
        plaintext[5] = 0x01
        plaintext[6] = 0x01
        plaintext[7] = 0x02
        plaintext[8] = usbHIDUsage
        return plaintext
    }

    public static func shortcutReport(index: UInt8, usbHIDUsage: UInt8) throws -> [UInt8] {
        try outputReport(
            encrypting: shortcutPlaintext(index: index, usbHIDUsage: usbHIDUsage)
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
