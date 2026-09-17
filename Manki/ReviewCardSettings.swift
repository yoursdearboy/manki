import Foundation

struct ReviewCardSettings {
    static let defaultHeight = 0.5
    static let heightRange = 0.3...0.8

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func height(for deckID: Int64) -> Double {
        let key = heightKey(for: deckID)
        guard defaults.object(forKey: key) != nil else { return Self.defaultHeight }
        return Self.clamp(defaults.double(forKey: key))
    }

    func setHeight(_ height: Double, for deckID: Int64) {
        defaults.set(Self.clamp(height), forKey: heightKey(for: deckID))
    }

    static func clamp(_ height: Double) -> Double {
        min(max(height, heightRange.lowerBound), heightRange.upperBound)
    }

    private func heightKey(for deckID: Int64) -> String {
        "reviewCardHeight.\(deckID)"
    }
}
