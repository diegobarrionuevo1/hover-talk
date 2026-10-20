import Foundation
import Testing
@testable import HoverTalkCore

private let retryAt = Date(timeIntervalSinceReferenceDate: 0)

private func config(enabled: Bool = true, address: Bool = true) -> RemoteVoiceServerConfig {
    RemoteVoiceServerConfig(
        enabled: enabled,
        address: address ? try! RemoteVoiceServerAddress(validating: "http://192.168.1.50:8880") : nil
    )
}

@Suite("RemoteVoicePresenter menu status")
struct RemoteVoiceMenuStatusTests {
    @Test("The Voice menu says whether the voice server reads", arguments: [
        (true, RemoteVoiceAvailability.State.available(latency: 0.12), "Voice server: available"),
        (true, .unavailable(retryAt: retryAt, failures: 2), "Voice server: unreachable — using system voice"),
        (true, .unknown, "Voice server: checking…"),
        (true, .checking, "Voice server: checking…"),
        (false, .disabled, "Voice server: off"),
        (false, .available(latency: 0.12), "Voice server: off"),
    ])
    func menuStatus(enabled: Bool, state: RemoteVoiceAvailability.State, expected: String) {
        #expect(RemoteVoicePresenter.menuStatus(config: config(enabled: enabled), state: state) == expected)
    }

    @Test("An enabled server without an address is not set up")
    func notSetUp() {
        #expect(RemoteVoicePresenter.menuStatus(config: config(address: false), state: .unknown)
            == "Voice server: not set up — using system voice")
    }
}

@Suite("RemoteVoicePresenter connection test")
struct RemoteVoiceConnectionStatusTests {
    @Test("The Test Connection status shows checking, the latency in milliseconds, or the problem", arguments: [
        (ConnectionTestStatus.checking, "Checking…"),
        (.available(latency: 0.1204), "Available · 120 ms"),
        (.available(latency: 0.0016), "Available · 2 ms"),
        (.invalidAddress, "Invalid URL"),
        (.failed(.unreachable), "Unreachable"),
        (.failed(.timedOut), "Unreachable"),
        (.failed(.cancelled), "Unreachable"),
        (.failed(.transport(code: -1011)), "Unreachable"),
        (.failed(.httpStatus(404)), "Server error (HTTP 404)"),
        (.failed(.invalidVoiceList), "Not a voice server"),
        (.failed(.emptyBody), "Not a voice server"),
        (.failed(.insecureConnectionBlocked), "Blocked: use https for this address"),
    ])
    func connectionStatus(status: ConnectionTestStatus, expected: String) {
        #expect(RemoteVoicePresenter.connectionStatus(status) == expected)
    }

    @Test("Each address problem has its own hint", arguments: [
        (RemoteVoiceServerAddress.ValidationError.empty, "Enter the server address, for example http://192.168.1.50:8880."),
        (.malformed, "This is not a valid URL."),
        (.unsupportedScheme, "Start the address with http:// or https://."),
        (.missingHost, "Add the server's host name or IP address."),
        (.queryOrFragment, "Remove the part after ? or #."),
    ])
    func validationMessage(error: RemoteVoiceServerAddress.ValidationError, expected: String) {
        #expect(RemoteVoicePresenter.validationMessage(error) == expected)
    }
}

@Suite("RemoteRouting fallback")
struct RemoteRoutingFallbackTests {
    @Test("The system voice stands in for a set-up server that is not available", arguments: [
        RemoteVoiceAvailability.State.unknown, .checking, .unavailable(retryAt: retryAt, failures: 1),
    ])
    func fallback(state: RemoteVoiceAvailability.State) {
        #expect(RemoteRouting.isFallback(config: config(), availability: state))
    }

    @Test("No fallback while the server is available, off, or has no address")
    func noFallback() {
        #expect(!RemoteRouting.isFallback(config: config(), availability: .available(latency: 0.1)))
        #expect(!RemoteRouting.isFallback(config: config(enabled: false), availability: .disabled))
        #expect(!RemoteRouting.isFallback(config: config(enabled: false), availability: .unavailable(retryAt: retryAt, failures: 1)))
        #expect(!RemoteRouting.isFallback(config: config(address: false), availability: .unknown))
    }
}
