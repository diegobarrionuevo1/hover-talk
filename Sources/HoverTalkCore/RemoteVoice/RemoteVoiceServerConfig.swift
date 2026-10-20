import Foundation

/// The base URL of a user-hosted, OpenAI-compatible voice server (for example Kokoro-FastAPI),
/// valid by construction: `init(validating:)` is the only way to make one.
public struct RemoteVoiceServerAddress: Equatable, Hashable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        /// Nothing but whitespace was entered.
        case empty
        /// The text does not parse as a URL.
        case malformed
        /// The scheme is not http or https, or there is none (for example "studio.local:8880").
        case unsupportedScheme
        case missingHost
        /// The URL has a query or a fragment, which no endpoint would keep.
        case queryOrFragment
    }

    /// Scheme, host, port and path, with a lowercase scheme and no trailing slash or "/v1";
    /// for example "http://192.168.1.20:8880".
    public let baseURL: URL

    /// Validates `text` after trimming whitespace. Trailing slashes are dropped, and so is one
    /// trailing "/v1" path component, so both "http://host:8880" and the OpenAI-style base URL
    /// "http://host:8880/v1/" name the same server.
    public init(validating text: String) throws(ValidationError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard var components = URLComponents(string: trimmed) else { throw .malformed }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw .unsupportedScheme
        }
        guard let host = components.host, !host.isEmpty else { throw .missingHost }
        guard components.query == nil, components.fragment == nil else { throw .queryOrFragment }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/v1") { path.removeLast(3) }
        while path.hasSuffix("/") { path.removeLast() }
        components.scheme = scheme
        components.path = path
        guard let url = components.url else { throw .malformed }
        baseURL = url
    }

    /// `POST` endpoint that turns text into audio.
    public var speechURL: URL { baseURL.appending(path: "v1/audio/speech") }
    /// `GET` endpoint that lists the server's voices.
    public var voicesURL: URL { baseURL.appending(path: "v1/audio/voices") }
}

/// The voice server settings. Off by default; `RemoteRouting.shouldUseRemote` refuses the server
/// until it is enabled and has an address.
public struct RemoteVoiceServerConfig: Equatable, Sendable {
    public static let `default` = RemoteVoiceServerConfig()

    public var enabled: Bool
    /// Nil while the user has not entered a valid address.
    public var address: RemoteVoiceServerAddress?
    /// The server voice: `.automatic` for `RemoteVoiceCatalog.resolve`'s choice per reading, or
    /// `.voice(id:)` with a voice name the server lists (for example "ef_dora").
    public var voice: VoiceSelection

    public init(enabled: Bool = false, address: RemoteVoiceServerAddress? = nil, voice: VoiceSelection = .automatic) {
        self.enabled = enabled
        self.address = address
        self.voice = voice
    }
}
