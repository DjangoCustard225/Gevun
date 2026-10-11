import Foundation

/// Screen-space motion shared by the player gesture and its release animation.
public struct PlayerDismissalPhysics {
    public let height: Double
    public init(height: Double) { self.height = max(1, height) }
    public var threshold: Double { min(180, max(110, height * 0.18)) }
    public var hiddenOffset: Double { height + 48 }
    public var dismissalTarget: Double { height + 80 }
    private var resistanceStart: Double { height * 0.6 }
    private var resistanceLength: Double { height * 0.25 }

    // Ordinary pulls follow the finger exactly; resistance only limits very long pulls.
    public func offset(for distance: Double) -> Double {
        let distance = max(0, distance)
        guard distance > resistanceStart else { return distance }
        let extra = distance - resistanceStart
        return resistanceStart + resistanceLength * extra / (extra + resistanceLength)
    }

    public func distance(for offset: Double) -> Double {
        let offset = max(0, offset)
        guard offset > resistanceStart else { return offset }
        let extra = min(resistanceLength - 0.001, offset - resistanceStart)
        return resistanceStart + resistanceLength * extra / (resistanceLength - extra)
    }

    public func velocity(_ velocity: Double, at distance: Double) -> Double {
        let extra = max(0, distance - resistanceStart)
        let slope = resistanceLength / (extra + resistanceLength)
        return velocity * slope * slope
    }

    public func shouldDismiss(offset: Double, velocity: Double) -> Bool {
        // An upward reversal always returns the player, even after a long downward pull.
        guard velocity > -180 else { return false }
        return offset >= threshold || (offset >= 28 && velocity >= 500 && offset + velocity * 0.18 >= threshold)
    }
}

/// Exact critically damped spring integration, independent of display refresh rate.
public struct PlayerSpring {
    public private(set) var position: Double
    public private(set) var velocity: Double
    public let target: Double
    public let frequency: Double

    public init(position: Double, velocity: Double, target: Double, frequency: Double) {
        self.position = position
        self.velocity = velocity
        self.target = target
        self.frequency = max(1, frequency)
    }

    public mutating func advance(by seconds: Double) {
        let time = max(0, seconds)
        let displacement = position - target
        let coefficient = velocity + frequency * displacement
        let decay = exp(-frequency * time)
        position = target + (displacement + coefficient * time) * decay
        velocity = (velocity - frequency * coefficient * time) * decay
    }

    public var isSettled: Bool { abs(position - target) < 0.1 && abs(velocity) < 2 }
}
