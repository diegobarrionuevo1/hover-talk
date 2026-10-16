/// User-facing speech speed as a multiplier of the engine's normal rate (1.0 = normal).
///
/// Values are clamped to `minimum...maximum` and snapped to the nearest `step`, so every
/// multiplier lies on the 0.25 grid. Each engine maps the multiplier to its own rate scale.
public struct SpeechRate: Equatable, Hashable, Sendable {
    public static let minimum = 0.5
    public static let maximum = 3.0
    public static let step = 0.25
    public static let `default` = SpeechRate(1.0)

    public let multiplier: Double

    /// A NaN multiplier falls back to the default rate.
    public init(_ multiplier: Double) {
        guard !multiplier.isNaN else {
            self.multiplier = 1.0
            return
        }
        let clamped = min(max(multiplier, Self.minimum), Self.maximum)
        self.multiplier = (clamped / Self.step).rounded() * Self.step
    }

    /// One step faster, capped at `maximum`.
    public func faster() -> SpeechRate {
        SpeechRate(multiplier + Self.step)
    }

    /// One step slower, capped at `minimum`.
    public func slower() -> SpeechRate {
        SpeechRate(multiplier - Self.step)
    }
}
