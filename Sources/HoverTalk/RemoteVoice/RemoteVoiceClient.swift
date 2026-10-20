import Foundation
import HoverTalkCore

/// Sends `RemoteVoiceRequests` to the user's voice server and hands the answers back to them.
///
/// A thin `URLSession` wrapper: building requests and reading answers live in
/// `RemoteVoiceRequests` (tested in HoverTalkCore); this type only moves bytes and enforces each
/// request's total time limit. It never logs. Its default session is ephemeral, with no cookie
/// store, no credential store and no URL cache, so a request carries nothing but itself.
struct RemoteVoiceClient: Sendable {
    let address: RemoteVoiceServerAddress
    private let session: URLSession

    /// `session` is injectable for tests and previews; the app uses `sharedSession`.
    init(address: RemoteVoiceServerAddress, session: URLSession = RemoteVoiceClient.sharedSession) {
        self.address = address
        self.session = session
    }

    static let sharedSession = makeSession()

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Each request sets its own idle timeout (`URLRequest.timeoutInterval`); these are the
        // session-wide ceilings.
        configuration.timeoutIntervalForRequest = RemoteVoiceRequests.speechIdleTimeout
        configuration.timeoutIntervalForResource = RemoteVoiceRequests.speechTimeoutCap
        // Fail at once when there is no route, instead of waiting for one.
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// The server's voices, and how long the answer took in seconds.
    func fetchVoices() async throws(RemoteVoiceError) -> (voices: [VoiceDescriptor], latency: TimeInterval) {
        let clock = ContinuousClock()
        let start = clock.now
        let (data, status) = try await send(RemoteVoiceRequests.voicesRequest(address), limit: RemoteVoiceRequests.voicesTimeout)
        let voices = try RemoteVoiceRequests.voices(from: data, statusCode: status)
        let elapsed = start.duration(to: clock.now).components
        return (voices, Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }

    /// `text` spoken by the server voice `voice` at normal speed.
    func synthesize(text: String, voice: String) async throws(RemoteVoiceError) -> DecodedAudio {
        let request = RemoteVoiceRequests.speechRequest(address, text: text, voice: voice)
        let limit = RemoteVoiceRequests.speechTimeout(forCharacterCount: text.count)
        let (data, status) = try await send(request, limit: limit)
        return try RemoteVoiceRequests.audio(from: data, statusCode: status)
    }

    /// The body and status code of `request`, or `.timedOut` once `limit` seconds have passed,
    /// whichever comes first. Cancelling the calling task cancels the request.
    private func send(_ request: URLRequest, limit: TimeInterval) async throws(RemoteVoiceError) -> (Data, Int) {
        let session = session
        do {
            return try await withThrowingTaskGroup(of: (Data, Int).self) { group in
                group.addTask {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw RemoteVoiceError.transport(code: URLError.Code.badServerResponse.rawValue)
                    }
                    return (data, http.statusCode)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(limit))
                    throw RemoteVoiceError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw RemoteVoiceError.timedOut }
                return first
            }
        } catch let error as RemoteVoiceError {
            throw error
        } catch let error as URLError {
            throw RemoteVoiceError(error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transport(code: (error as NSError).code)
        }
    }
}
