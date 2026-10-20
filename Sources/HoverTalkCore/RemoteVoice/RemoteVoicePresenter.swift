import Foundation

/// The outcome of the Settings window's Test Connection button.
public enum ConnectionTestStatus: Equatable, Sendable {
    case checking
    /// The voices list arrived after `latency` seconds.
    case available(latency: TimeInterval)
    case failed(RemoteVoiceError)
    /// The URL field does not hold a valid address, so nothing was sent.
    case invalidAddress
}

/// The voice server's status texts for the Voice menu and the Settings window.
public enum RemoteVoicePresenter {
    /// The Voice menu's status line.
    public static func menuStatus(config: RemoteVoiceServerConfig, state: RemoteVoiceAvailability.State) -> String {
        guard config.enabled else { return "Voice server: off" }
        guard config.address != nil else { return "Voice server: not set up — using system voice" }
        return switch state {
        case .disabled: "Voice server: off"
        case .unknown, .checking: "Voice server: checking…"
        case .available: "Voice server: available"
        case .unavailable: "Voice server: unreachable — using system voice"
        }
    }

    /// The text next to the Test Connection button.
    public static func connectionStatus(_ status: ConnectionTestStatus) -> String {
        switch status {
        case .checking:
            "Checking…"
        case .available(let latency):
            "Available · \(Int((max(latency, 0) * 1000).rounded())) ms"
        case .invalidAddress:
            "Invalid URL"
        case .failed(.httpStatus(let status)):
            "Server error (HTTP \(status))"
        case .failed(.insecureConnectionBlocked):
            "Blocked: use https for this address"
        case .failed(.invalidVoiceList), .failed(.emptyBody), .failed(.invalidAudio), .failed(.noAudio):
            "Not a voice server"
        case .failed(.unreachable), .failed(.timedOut), .failed(.cancelled), .failed(.transport):
            "Unreachable"
        }
    }

    /// The hint under the URL field for an address that does not validate.
    public static func validationMessage(_ error: RemoteVoiceServerAddress.ValidationError) -> String {
        switch error {
        case .empty: "Enter the server address, for example http://192.168.1.50:8880."
        case .malformed: "This is not a valid URL."
        case .unsupportedScheme: "Start the address with http:// or https://."
        case .missingHost: "Add the server's host name or IP address."
        case .queryOrFragment: "Remove the part after ? or #."
        }
    }
}

extension RemoteRouting {
    /// True when the user set up a voice server (enabled, with an address) that is not available,
    /// so the system voice reads in its place; false when the server is available, even if it has
    /// no voice for the text, because then the system voice reads by design, not as a stand-in.
    public static func isFallback(config: RemoteVoiceServerConfig, availability: RemoteVoiceAvailability.State) -> Bool {
        guard config.enabled, config.address != nil else { return false }
        if case .available = availability { return false }
        return true
    }
}
