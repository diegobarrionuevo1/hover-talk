/// Replacement vocabulary for `FixtureSanitizer`: lowercase ASCII words grouped by length.
enum NeutralWords {
    /// `byLength[n - 1]` holds the words of length `n`. Every bucket needs at least two words
    /// so a replacement can always differ from the word it replaces.
    static let byLength: [[String]] = [
        ["a", "o", "e", "u"],
        ["at", "by", "do", "go", "in", "on", "up", "so"],
        ["oak", "sun", "map", "cup", "sky", "owl", "fig", "elm"],
        ["leaf", "rain", "moss", "lake", "bird", "wind", "fern", "reed"],
        ["river", "stone", "cloud", "maple", "pearl", "otter", "cedar", "brook"],
        ["meadow", "pebble", "canyon", "harbor", "willow", "falcon", "garden", "island"],
        ["lantern", "orchard", "glacier", "harvest", "compass", "sparrow", "thistle", "blossom"],
        ["mountain", "woodland", "sunlight", "lavender", "seashell", "hillside", "snowfall", "moonbeam"],
    ]

    static var maxLength: Int { byLength.count }

    /// A word of exactly `length` letters chosen by `seed`. Lengths above `maxLength` are
    /// built by concatenating words. The first piece is `bucket[seed % bucket.count]`, so
    /// `seed` and `seed ^ 1` (which differ by exactly one) always give different words.
    static func word(length: Int, seed: UInt64) -> String {
        precondition(length >= 1, "A neutral word needs at least one letter.")
        let pieceLength = min(length, maxLength)
        let bucket = byLength[pieceLength - 1]
        let piece = bucket[Int(seed % UInt64(bucket.count))]
        guard length > maxLength else { return piece }
        return piece + word(length: length - maxLength, seed: mix(seed))
    }

    /// SplitMix64 finalizer: spreads every input bit over the whole output.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
