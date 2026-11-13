import Foundation

/// The Heart Rate Measurement characteristic (0x2A37) of the Bluetooth SIG's Heart Rate Service.
/// Byte 0 holds flags. Bit 0 says whether the heart rate that follows is one byte or two, least
/// significant first. Energy expended and RR intervals come after it, and the app reads neither.
enum HeartRateMeasurement {
    /// nil for a value too short to hold the heart rate its flags announce.
    static func bpm(from data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        if flags & 0x01 == 0 {
            return bytes.count >= 2 ? Int(bytes[1]) : nil
        }
        return bytes.count >= 3 ? Int(bytes[1]) | Int(bytes[2]) << 8 : nil
    }
}
