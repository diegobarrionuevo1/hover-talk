import Foundation

/// Why a voice server request failed. `reason` is a short sentence for status text and
/// `SpeechEngineEvent.Kind.failed(reason:)`; no reason contains the text being read.
public enum RemoteVoiceError: Error, Equatable, Sendable {
    /// The host was not found, refused the connection, or the network is down.
    case unreachable
    /// No answer, or a pause in the answer, longer than the request allows.
    case timedOut
    /// App Transport Security refused plain http to this host (see `scripts/bundle.sh`).
    case insecureConnectionBlocked
    /// The server answered with a status outside 200...299.
    case httpStatus(Int)
    /// The server answered 2xx with an empty body.
    case emptyBody
    /// The voices answer is not a `{"voices": [...]}` list (`RemoteVoiceCatalog.parseVoices`).
    case invalidVoiceList
    /// The speech answer is not a WAV file `WAVDecoder` reads.
    case invalidAudio(WAVDecoder.DecodingError)
    /// The WAV file holds no audio frames.
    case noAudio
    case cancelled
    /// Any other `URLError`, by its code.
    case transport(code: Int)

    public init(_ error: URLError) {
        switch error.code {
        case .timedOut:
            self = .timedOut
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
            self = .unreachable
        case .appTransportSecurityRequiresSecureConnection:
            self = .insecureConnectionBlocked
        case .cancelled:
            self = .cancelled
        default:
            self = .transport(code: error.code.rawValue)
        }
    }

    public var reason: String {
        switch self {
        case .unreachable: "The voice server could not be reached."
        case .timedOut: "The voice server did not answer in time."
        case .insecureConnectionBlocked: "macOS blocked plain http to this address; use https."
        case .httpStatus(let status): "The voice server answered with HTTP status \(status)."
        case .emptyBody: "The voice server sent an empty answer."
        case .invalidVoiceList: "The voice server's voice list has an unexpected format."
        case .invalidAudio: "The voice server sent audio that is not a supported WAV file."
        case .noAudio: "The voice server sent no audio."
        case .cancelled: "The request was cancelled."
        case .transport(let code): "Network error \(code)."
        }
    }
}

/// The requests HoverTalk sends to a user-hosted, OpenAI-compatible voice server, and the
/// handling of the answers, without any networking: the app's `RemoteVoiceClient` sends them.
///
/// Speech is always requested at normal speed: the app changes the rate while playing, so one
/// synthesis serves every rate.
public enum RemoteVoiceRequests {
    /// The `model` field. Kokoro-FastAPI documents "kokoro".
    public static let model = "kokoro"
    /// The longest wait for the voices answer to start or continue.
    public static let voicesTimeout: TimeInterval = 2
    /// The longest wait for the speech answer's first byte, and between later bytes.
    public static let speechIdleTimeout: TimeInterval = 2.5
    static let speechTimeoutBase: TimeInterval = 4
    static let speechTimeoutPerCharacter: TimeInterval = 0.03
    /// The longest a whole speech request may take, whatever the text's length.
    public static let speechTimeoutCap: TimeInterval = 20

    /// `GET /v1/audio/voices`.
    public static func voicesRequest(_ address: RemoteVoiceServerAddress) -> URLRequest {
        var request = baseRequest(url: address.voicesURL, timeout: voicesTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// `POST /v1/audio/speech` with `{"model", "input", "voice", "speed": 1, "response_format": "wav"}`.
    public static func speechRequest(_ address: RemoteVoiceServerAddress, text: String, voice: String) -> URLRequest {
        var request = baseRequest(url: address.speechURL, timeout: speechIdleTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/wav", forHTTPHeaderField: "Accept")
        let body = SpeechBody(model: model, input: text, voice: voice, speed: 1, responseFormat: "wav")
        // Encoding four strings and a number cannot fail; `try?` keeps the API non-throwing.
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    /// The total time a speech request for a text of `count` characters may take: a base plus a
    /// share per character, never more than `speechTimeoutCap`.
    public static func speechTimeout(forCharacterCount count: Int) -> TimeInterval {
        min(speechTimeoutBase + Double(max(count, 0)) * speechTimeoutPerCharacter, speechTimeoutCap)
    }

    /// The voices of a voices answer.
    public static func voices(from data: Data, statusCode: Int) throws(RemoteVoiceError) -> [VoiceDescriptor] {
        try checkStatus(statusCode, data: data)
        do {
            return try RemoteVoiceCatalog.parseVoices(from: data)
        } catch {
            throw .invalidVoiceList
        }
    }

    /// The audio of a speech answer.
    public static func audio(from data: Data, statusCode: Int) throws(RemoteVoiceError) -> DecodedAudio {
        try checkStatus(statusCode, data: data)
        let audio: DecodedAudio
        do {
            audio = try WAVDecoder.decode(data)
        } catch {
            throw .invalidAudio(error)
        }
        guard audio.frameCount > 0 else { throw .noAudio }
        return audio
    }

    // MARK: - Helpers

    private struct SpeechBody: Encodable {
        let model: String
        let input: String
        let voice: String
        let speed: Double
        let responseFormat: String

        private enum CodingKeys: String, CodingKey {
            case model, input, voice, speed
            case responseFormat = "response_format"
        }
    }

    /// No cookies and no locally cached answers, so nothing but the request itself is sent and a
    /// stale answer is never played.
    private static func baseRequest(url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpShouldHandleCookies = false
        return request
    }

    private static func checkStatus(_ statusCode: Int, data: Data) throws(RemoteVoiceError) {
        guard (200...299).contains(statusCode) else { throw .httpStatus(statusCode) }
        guard !data.isEmpty else { throw .emptyBody }
    }
}
