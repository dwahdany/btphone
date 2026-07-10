import Foundation

/// On-the-wire audio format shared by both phones.
///
/// 16 kHz mono Int16 PCM, 20 ms per datagram. That is 320 samples / 640 bytes
/// of payload per packet plus a 4-byte big-endian sequence number — small
/// enough to never fragment on peer-to-peer Wi-Fi, and 16 kHz matches the
/// wideband quality ceiling of Bluetooth HFP helmet headsets anyway.
enum Wire {
    static let sampleRate: Double = 16_000
    static let frameSamples = 320 // 20 ms at 16 kHz
    static let frameBytes = frameSamples * MemoryLayout<Int16>.size
    static let headerBytes = 4 // UInt32 big-endian sequence number
}
