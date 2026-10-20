import Foundation
import Testing
@testable import HoverTalkCore

// Builders for little-endian RIFF/WAVE bytes, so every test states its file byte by byte.

private func le16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8(value >> 8)]
}

private func le32(_ value: UInt32) -> [UInt8] {
    (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) }
}

/// A chunk with `body`; the declared size is `size` when given, else the body's length, in which
/// case an odd body gets the RIFF pad byte.
private func chunk(_ id: String, _ body: [UInt8], size: UInt32? = nil) -> [UInt8] {
    let pad: [UInt8] = size == nil && body.count % 2 == 1 ? [0] : []
    return Array(id.utf8) + le32(size ?? UInt32(body.count)) + body + pad
}

private func fmt(tag: UInt16 = 1, channels: UInt16 = 1, sampleRate: UInt32 = 24_000, bits: UInt16 = 16) -> [UInt8] {
    let blockAlign = channels * bits / 8
    let body = le16(tag) + le16(channels) + le32(sampleRate) + le32(sampleRate * UInt32(blockAlign)) + le16(blockAlign) + le16(bits)
    return chunk("fmt ", body)
}

/// WAVE_FORMAT_EXTENSIBLE: the real format tag is the first two bytes of the subformat GUID.
private func extensibleFmt(subformat: UInt16, channels: UInt16, bits: UInt16) -> [UInt8] {
    let blockAlign = channels * bits / 8
    let base = le16(0xFFFE) + le16(channels) + le32(24_000) + le32(24_000 * UInt32(blockAlign)) + le16(blockAlign) + le16(bits)
    let guidTail: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]
    let extensionBytes = le16(22) + le16(bits) + le32(0x3) + le16(subformat) + guidTail
    return chunk("fmt ", base + extensionBytes)
}

private func wav(_ chunks: [UInt8]..., riffSize: UInt32? = nil) -> Data {
    let body = Array("WAVE".utf8) + chunks.flatMap { $0 }
    return Data(Array("RIFF".utf8) + le32(riffSize ?? UInt32(body.count)) + body)
}

private func pcm16(_ values: [Int16]) -> [UInt8] {
    values.flatMap { le16(UInt16(bitPattern: $0)) }
}

private func float32(_ values: [Float]) -> [UInt8] {
    values.flatMap { le32($0.bitPattern) }
}

@Suite("WAVDecoder formats")
struct WAVDecoderFormatTests {
    @Test("16-bit PCM mono is normalized by 32768")
    func pcm16Mono() throws {
        let audio = try WAVDecoder.decode(wav(fmt(), chunk("data", pcm16([0, 16384, -16384, 32767, -32768]))))

        #expect(audio.sampleRate == 24_000)
        #expect(audio.channels == 1)
        #expect(audio.samples == [0, 0.5, -0.5, Float(32767) / 32768, -1])
        #expect(audio.frameCount == 5)
    }

    @Test("16-bit PCM stereo stays interleaved")
    func pcm16Stereo() throws {
        let audio = try WAVDecoder.decode(wav(fmt(channels: 2, sampleRate: 44_100), chunk("data", pcm16([8192, -8192, 16384, -16384]))))

        #expect(audio.sampleRate == 44_100)
        #expect(audio.channels == 2)
        #expect(audio.samples == [0.25, -0.25, 0.5, -0.5])
        #expect(audio.frameCount == 2)
    }

    @Test("32-bit float mono and stereo keep their values")
    func float32Samples() throws {
        let mono = try WAVDecoder.decode(wav(fmt(tag: 3, bits: 32), chunk("data", float32([0.25, -0.75, 1]))))
        #expect(mono.channels == 1)
        #expect(mono.samples == [0.25, -0.75, 1])

        let stereo = try WAVDecoder.decode(wav(fmt(tag: 3, channels: 2, bits: 32), chunk("data", float32([0.1, -0.1, 0.2, -0.2]))))
        #expect(stereo.channels == 2)
        #expect(stereo.samples == [0.1, -0.1, 0.2, -0.2])
    }

    @Test("WAVE_FORMAT_EXTENSIBLE uses the subformat's tag")
    func extensible() throws {
        let pcm = try WAVDecoder.decode(wav(extensibleFmt(subformat: 1, channels: 1, bits: 16), chunk("data", pcm16([16384]))))
        #expect(pcm.samples == [0.5])

        let float = try WAVDecoder.decode(wav(extensibleFmt(subformat: 3, channels: 2, bits: 32), chunk("data", float32([0.5, -0.5]))))
        #expect(float.samples == [0.5, -0.5])
    }
}

@Suite("WAVDecoder chunks and sizes")
struct WAVDecoderChunkTests {
    @Test("Unknown chunks before and after the format chunk are skipped, including an odd one with its pad byte")
    func skipsUnknownChunks() throws {
        let list = chunk("LIST", Array("INFOabc".utf8))
        let fact = chunk("fact", le32(2))
        let audio = try WAVDecoder.decode(wav(list, fmt(), fact, chunk("data", pcm16([16384, -16384]))))

        #expect(audio.samples == [0.5, -0.5])
    }

    @Test("Streaming sentinels 0xFFFFFFFF for the RIFF and data sizes read to the end")
    func streamingSentinel() throws {
        let data = wav(fmt(), chunk("data", pcm16([16384, -16384, 8192]), size: 0xFFFF_FFFF), riffSize: 0xFFFF_FFFF)

        #expect(try WAVDecoder.decode(data).samples == [0.5, -0.5, 0.25])
    }

    @Test("A data size larger than the payload reads to the end and drops a partial last frame")
    func oversizedData() throws {
        let stereo = wav(fmt(channels: 2), chunk("data", pcm16([16384, -16384, 8192]), size: 1_000_000))

        let audio = try WAVDecoder.decode(stereo)
        #expect(audio.samples == [0.5, -0.5])
        #expect(audio.frameCount == 1)
    }

    @Test("A data size smaller than the rest of the file reads only the declared bytes")
    func trailingChunkAfterData() throws {
        let data = wav(fmt(), chunk("data", pcm16([16384])), chunk("LIST", Array("INFO".utf8)))

        #expect(try WAVDecoder.decode(data).samples == [0.5])
    }

    @Test("An empty data chunk decodes to no samples")
    func emptyData() throws {
        let audio = try WAVDecoder.decode(wav(fmt(), chunk("data", [])))
        #expect(audio.samples.isEmpty)
        #expect(audio.frameCount == 0)
    }

    @Test("Offsets are relative to the bytes given, also for a slice of a larger buffer")
    func dataSlice() throws {
        let whole = Data([0xAA, 0xBB, 0xCC]) + wav(fmt(), chunk("data", pcm16([16384])))
        let slice = whole.dropFirst(3)

        #expect(try WAVDecoder.decode(slice).samples == [0.5])
    }
}

@Suite("WAVDecoder errors")
struct WAVDecoderErrorTests {
    @Test("Bytes that are not RIFF/WAVE are not WAV", arguments: [
        Data(),
        Data("ID3\u{3}\0\0\0\0\0\0".utf8),
        Data("RIFX\u{4}\0\0\0WAVE".utf8),
        Data("RIFF\u{4}\0\0\0AVI ".utf8),
        Data("{\"error\":\"voice not found\"}".utf8),
    ])
    func notWAV(data: Data) {
        #expect(throws: WAVDecoder.DecodingError.notWAV) { try WAVDecoder.decode(data) }
    }

    @Test("A file that ends before the format chunk or the data chunk header is truncated", arguments: [
        Data("RIFF\u{4}\0\0\0".utf8),
        wav(),
        wav(fmt()),
        wav(fmt(), Array("da".utf8)),
        wav(Array("fmt ".utf8) + le32(16) + le16(1) + le16(1)),
        wav(chunk("fmt ", le16(1) + le16(1) + le32(24_000))),
    ])
    func truncated(data: Data) {
        #expect(throws: WAVDecoder.DecodingError.truncatedHeader) { try WAVDecoder.decode(data) }
    }

    @Test("A data chunk before any format chunk has no format")
    func dataBeforeFormat() {
        #expect(throws: WAVDecoder.DecodingError.missingFormat) {
            try WAVDecoder.decode(wav(chunk("data", pcm16([1])), fmt()))
        }
    }

    @Test("Formats other than 16-bit PCM and 32-bit float are unsupported", arguments: [
        (UInt16(1), UInt16(8)),
        (UInt16(1), UInt16(24)),
        (UInt16(3), UInt16(64)),
        (UInt16(0x55), UInt16(16)),
        (UInt16(3), UInt16(16)),
    ])
    func unsupportedFormat(tag: UInt16, bits: UInt16) {
        #expect(throws: WAVDecoder.DecodingError.unsupportedFormat(formatTag: tag, bitsPerSample: bits)) {
            try WAVDecoder.decode(wav(fmt(tag: tag, bits: bits), chunk("data", [0, 0, 0, 0])))
        }
    }

    @Test("Only mono and stereo are supported", arguments: [UInt16(0), 3, 6])
    func unsupportedChannels(channels: UInt16) {
        #expect(throws: WAVDecoder.DecodingError.unsupportedChannelCount(channels)) {
            try WAVDecoder.decode(wav(fmt(channels: channels), chunk("data", [0, 0, 0, 0])))
        }
    }

    @Test("A zero sample rate is rejected")
    func zeroSampleRate() {
        #expect(throws: WAVDecoder.DecodingError.invalidSampleRate) {
            try WAVDecoder.decode(wav(fmt(sampleRate: 0), chunk("data", pcm16([1]))))
        }
    }
}
