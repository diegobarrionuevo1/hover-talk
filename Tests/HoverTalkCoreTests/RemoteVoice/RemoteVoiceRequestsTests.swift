import Foundation
import Testing
@testable import HoverTalkCore

private let address = try! RemoteVoiceServerAddress(validating: "http://192.168.1.50:8880")

/// A mono 16-bit PCM WAV file at 24 kHz holding `samples`.
private func monoWAV(_ samples: [Int16]) -> Data {
    func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    func le32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) } }
    let format = le16(1) + le16(1) + le32(24_000) + le32(48_000) + le16(2) + le16(16)
    let data = samples.flatMap { le16(UInt16(bitPattern: $0)) }
    let body = Array("WAVE".utf8)
        + Array("fmt ".utf8) + le32(UInt32(format.count)) + format
        + Array("data".utf8) + le32(UInt32(data.count)) + data
    return Data(Array("RIFF".utf8) + le32(UInt32(body.count)) + body)
}

@Suite("RemoteVoiceRequests building")
struct RemoteVoiceRequestBuildingTests {
    @Test("The speech request posts Kokoro's JSON body for WAV at normal speed to /v1/audio/speech")
    func speechRequest() throws {
        let request = RemoteVoiceRequests.speechRequest(address, text: "Hola, ¿qué tal?", voice: "ef_dora")

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "http://192.168.1.50:8880/v1/audio/speech")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "audio/wav")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json.count == 5)
        #expect(json["model"] as? String == "kokoro")
        #expect(json["input"] as? String == "Hola, ¿qué tal?")
        #expect(json["voice"] as? String == "ef_dora")
        #expect(json["speed"] as? Double == 1)
        #expect(json["response_format"] as? String == "wav")
    }

    @Test("The voices request is a GET of /v1/audio/voices that accepts JSON")
    func voicesRequest() {
        let request = RemoteVoiceRequests.voicesRequest(address)

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "http://192.168.1.50:8880/v1/audio/voices")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.httpBody == nil)
    }

    @Test("Both requests send no cookies, skip the local cache, and carry their idle timeout")
    func privacyAndTimeouts() {
        let speech = RemoteVoiceRequests.speechRequest(address, text: "Hello.", voice: "af_heart")
        let voices = RemoteVoiceRequests.voicesRequest(address)

        for request in [speech, voices] {
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }
        #expect(speech.timeoutInterval == 2.5)
        #expect(voices.timeoutInterval == 2)
    }

    @Test("The speech time limit grows with the text and stops at 20 seconds", arguments: [
        (0, 4.0), (100, 7.0), (400, 16.0), (533, 19.99), (534, 20.0), (5_000, 20.0),
    ])
    func speechTimeout(characters: Int, expected: Double) {
        #expect(abs(RemoteVoiceRequests.speechTimeout(forCharacterCount: characters) - expected) < 0.000_001)
    }
}

@Suite("RemoteVoiceRequests answers")
struct RemoteVoiceAnswerTests {
    @Test("A 2xx voices answer parses into remote voices")
    func voicesOK() throws {
        let voices = try RemoteVoiceRequests.voices(from: Data("{\"voices\": [\"ef_dora\", \"af_heart\"]}".utf8), statusCode: 200)

        #expect(voices.map(\.id) == ["ef_dora", "af_heart"])
        #expect(voices.allSatisfy { $0.source == .remote })
    }

    @Test("A status outside 2xx is an HTTP error, whatever the body", arguments: [199, 301, 404, 500, 503])
    func statusErrors(status: Int) {
        let voicesBody = Data("{\"voices\": []}".utf8)
        #expect(throws: RemoteVoiceError.httpStatus(status)) {
            try RemoteVoiceRequests.voices(from: voicesBody, statusCode: status)
        }
        #expect(throws: RemoteVoiceError.httpStatus(status)) {
            try RemoteVoiceRequests.audio(from: monoWAV([1, 2]), statusCode: status)
        }
    }

    @Test("Any 2xx status is accepted", arguments: [200, 201, 299])
    func anySuccessStatus(status: Int) throws {
        #expect(try RemoteVoiceRequests.audio(from: monoWAV([0, 16384]), statusCode: status).frameCount == 2)
    }

    @Test("An empty 2xx body is an empty answer")
    func emptyBodies() {
        #expect(throws: RemoteVoiceError.emptyBody) { try RemoteVoiceRequests.voices(from: Data(), statusCode: 200) }
        #expect(throws: RemoteVoiceError.emptyBody) { try RemoteVoiceRequests.audio(from: Data(), statusCode: 200) }
    }

    @Test("A voices body that is not a voice list is an invalid voice list")
    func invalidVoiceList() {
        #expect(throws: RemoteVoiceError.invalidVoiceList) {
            try RemoteVoiceRequests.voices(from: Data("<html>Not Found</html>".utf8), statusCode: 200)
        }
    }

    @Test("A 2xx WAV answer decodes into audio")
    func audioOK() throws {
        let audio = try RemoteVoiceRequests.audio(from: monoWAV([0, 16384, -16384]), statusCode: 200)

        #expect(audio == DecodedAudio(sampleRate: 24_000, channels: 1, samples: [0, 0.5, -0.5]))
    }

    @Test("A speech body that is not WAV carries the decoder's error")
    func invalidAudio() {
        #expect(throws: RemoteVoiceError.invalidAudio(.notWAV)) {
            try RemoteVoiceRequests.audio(from: Data("ID3 mp3 bytes".utf8), statusCode: 200)
        }
    }

    @Test("A WAV file without frames is no audio")
    func noFrames() {
        #expect(throws: RemoteVoiceError.noAudio) {
            try RemoteVoiceRequests.audio(from: monoWAV([]), statusCode: 200)
        }
    }
}

@Suite("RemoteVoiceError")
struct RemoteVoiceErrorTests {
    @Test("URL loading errors map to what the user can act on", arguments: [
        (URLError.Code.timedOut, RemoteVoiceError.timedOut),
        (.cannotFindHost, .unreachable),
        (.cannotConnectToHost, .unreachable),
        (.networkConnectionLost, .unreachable),
        (.notConnectedToInternet, .unreachable),
        (.dnsLookupFailed, .unreachable),
        (.appTransportSecurityRequiresSecureConnection, .insecureConnectionBlocked),
        (.cancelled, .cancelled),
        (.badServerResponse, .transport(code: URLError.Code.badServerResponse.rawValue)),
    ])
    func mapsURLErrors(code: URLError.Code, expected: RemoteVoiceError) {
        #expect(RemoteVoiceError(URLError(code)) == expected)
    }

    @Test("Every reason is a short sentence that never repeats request content", arguments: [
        RemoteVoiceError.unreachable, .timedOut, .insecureConnectionBlocked, .httpStatus(500), .emptyBody,
        .invalidVoiceList, .invalidAudio(.notWAV), .noAudio, .cancelled, .transport(code: -1011),
    ])
    func reasons(error: RemoteVoiceError) {
        #expect(!error.reason.isEmpty)
        #expect(error.reason.hasSuffix("."))
    }

    @Test("Reasons name the status code and the https remedy")
    func reasonDetails() {
        #expect(RemoteVoiceError.httpStatus(404).reason.contains("404"))
        #expect(RemoteVoiceError.insecureConnectionBlocked.reason.contains("https"))
    }
}
