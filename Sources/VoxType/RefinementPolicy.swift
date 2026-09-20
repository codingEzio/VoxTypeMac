import Foundation

enum RefinementPolicy {
    static var timeoutSeconds: TimeInterval {
        guard let value = try? QwenRefinement.configuration().timeoutSeconds,
            value.isFinite, value > 0, value <= 180
        else { return 90 }
        return value
    }
}
