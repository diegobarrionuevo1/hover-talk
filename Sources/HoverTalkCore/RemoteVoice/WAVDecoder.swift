import Foundation

/// PCM audio ready for playback.
public struct DecodedAudio: Equatable, Sendable {
    /// Frames per second, for example 24000.
    public let sampleRate: Int
    /// 1 (mono) or 2 (stereo); `WAVDecoder` rejects any other count.
    public let channels: Int
    /// Interleaved samples (left, right, left, … for stereo), normalized to -1...1.
    public let samples: [Float]

    public var frameCount: Int { samples.count / channels }
}

/// Parses a RIFF/WAVE file, the `wav` response format of OpenAI-compatible speech servers.
///
/// Supported: 16-bit integer PCM and 32-bit float, mono or stereo, also inside a
/// WAVE_FORMAT_EXTENSIBLE header. Chunks other than "fmt " and "data" are skipped. The RIFF size
/// is never used, and a data size of 0xFFFFFFFF (the streaming placeholder) or larger than the
/// bytes present reads to the end; a partial last frame is dropped.
public enum WAVDecoder {
    public enum DecodingError: Error, Equatable, Sendable {
        /// The bytes do not start with "RIFF", size, "WAVE".
        case notWAV
        /// The 12-byte RIFF header, the "fmt " chunk (16 bytes at least) or the "data" chunk
        /// header is cut short or missing.
        case truncatedHeader
        /// A "data" chunk comes before any "fmt " chunk.
        case missingFormat
        case unsupportedFormat(formatTag: UInt16, bitsPerSample: UInt16)
        case unsupportedChannelCount(UInt16)
        case invalidSampleRate
    }

    private enum SampleFormat {
        case int16
        case float32
    }

    private static let pcmTag: UInt16 = 1
    private static let floatTag: UInt16 = 3
    private static let extensibleTag: UInt16 = 0xFFFE

    public static func decode(_ data: Data) throws(DecodingError) -> DecodedAudio {
        // `Data` may be a slice; copying gives zero-based offsets.
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0..<4].elementsEqual("RIFF".utf8) else { throw .notWAV }
        guard bytes.count >= 12 else { throw .truncatedHeader }
        guard bytes[8..<12].elementsEqual("WAVE".utf8) else { throw .notWAV }

        var format: (sample: SampleFormat, channels: Int, sampleRate: Int)?
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = bytes[offset..<offset + 4]
            let size = uint32(bytes, at: offset + 4)
            let body = offset + 8
            if id.elementsEqual("fmt ".utf8) {
                format = try parseFormat(bytes, at: body, size: size)
            } else if id.elementsEqual("data".utf8) {
                guard let format else { throw .missingFormat }
                // 0xFFFFFFFF, the streaming placeholder, exceeds any payload under 4 GiB, so `min`
                // reads such a chunk to the end.
                let length = min(Int(size), bytes.count - body)
                let samples = decodeSamples(bytes[body..<body + length], format: format.sample, channels: format.channels)
                return DecodedAudio(sampleRate: format.sampleRate, channels: format.channels, samples: samples)
            }
            // Chunks are word-aligned: an odd size is followed by one pad byte.
            offset = body + Int(size) + Int(size % 2)
        }
        throw .truncatedHeader
    }

    private static func parseFormat(_ bytes: [UInt8], at body: Int, size: UInt32) throws(DecodingError) -> (sample: SampleFormat, channels: Int, sampleRate: Int) {
        guard size >= 16, body + 16 <= bytes.count else { throw .truncatedHeader }
        var tag = uint16(bytes, at: body)
        let channels = uint16(bytes, at: body + 2)
        let sampleRate = uint32(bytes, at: body + 4)
        let bits = uint16(bytes, at: body + 14)
        // WAVE_FORMAT_EXTENSIBLE: the subformat GUID starts 24 bytes into the chunk, and its first
        // two bytes are the real format tag.
        if tag == extensibleTag, size >= 26, body + 26 <= bytes.count {
            tag = uint16(bytes, at: body + 24)
        }
        let sample: SampleFormat
        switch (tag, bits) {
        case (pcmTag, 16): sample = .int16
        case (floatTag, 32): sample = .float32
        default: throw .unsupportedFormat(formatTag: tag, bitsPerSample: bits)
        }
        guard channels == 1 || channels == 2 else { throw .unsupportedChannelCount(channels) }
        guard sampleRate > 0 else { throw .invalidSampleRate }
        return (sample, Int(channels), Int(sampleRate))
    }

    private static func decodeSamples(_ payload: ArraySlice<UInt8>, format: SampleFormat, channels: Int) -> [Float] {
        let bytesPerSample = format == .int16 ? 2 : 4
        let frameBytes = bytesPerSample * channels
        let usable = payload.count - payload.count % frameBytes
        let start = payload.startIndex
        return stride(from: start, to: start + usable, by: bytesPerSample).map { index in
            switch format {
            case .int16: Float(Int16(bitPattern: uint16(payload, at: index))) / 32768
            case .float32: Float(bitPattern: uint32(payload, at: index))
            }
        }
    }

    private static func uint16<C: RandomAccessCollection<UInt8>>(_ bytes: C, at index: C.Index) -> UInt16 where C.Index == Int {
        UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
    }

    private static func uint32<C: RandomAccessCollection<UInt8>>(_ bytes: C, at index: C.Index) -> UInt32 where C.Index == Int {
        UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
    }
}
