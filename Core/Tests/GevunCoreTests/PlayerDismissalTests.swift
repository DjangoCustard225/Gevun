import XCTest
@testable import GevunCore

final class PlayerDismissalTests: XCTestCase {
    func testPullTracksFingerBeforeResistanceAndNeverMovesUpward() {
        let motion = PlayerDismissalPhysics(height: 850)
        XCTAssertEqual(motion.offset(for: -50), 0)
        for distance in [0.0, 1, 10, 100, 300, 510] {
            XCTAssertEqual(motion.offset(for: distance), distance, accuracy: 0.000001)
        }
    }

    func testLongPullResistanceIsContinuousBoundedAndInvertible() {
        let motion = PlayerDismissalPhysics(height: 850)
        var previous = 0.0
        for distance in stride(from: 0.0, through: 3000, by: 0.5) {
            let offset = motion.offset(for: distance)
            XCTAssertGreaterThanOrEqual(offset, previous)
            XCTAssertLessThan(offset, 850 * 0.85)
            XCTAssertEqual(motion.distance(for: offset), distance, accuracy: 0.000001)
            previous = offset
        }
        XCTAssertEqual(motion.offset(for: 510.001) - motion.offset(for: 510), 0.001, accuracy: 0.000001)
        XCTAssertEqual(motion.velocity(600, at: 510), 600)
        XCTAssertLessThan(motion.velocity(600, at: 1000), 600)
    }

    func testIntentionalDistanceAndFlicksDismissButTinyPullsDoNot() {
        let motion = PlayerDismissalPhysics(height: 850)
        XCTAssertTrue(motion.shouldDismiss(offset: 170, velocity: 0))
        XCTAssertTrue(motion.shouldDismiss(offset: 40, velocity: 900))
        XCTAssertFalse(motion.shouldDismiss(offset: 20, velocity: 3000))
        XCTAssertFalse(motion.shouldDismiss(offset: 90, velocity: 100))
        XCTAssertFalse(motion.shouldDismiss(offset: 40, velocity: 490))
    }

    func testUpwardReversalCancelsEvenAfterALongPull() {
        let motion = PlayerDismissalPhysics(height: 850)
        XCTAssertFalse(motion.shouldDismiss(offset: 500, velocity: -600))
        XCTAssertFalse(motion.shouldDismiss(offset: 200, velocity: -180))
        XCTAssertTrue(motion.shouldDismiss(offset: 200, velocity: -50))
    }

    func testThresholdAdaptsToScreenSizeWithinComfortableBounds() {
        XCTAssertEqual(PlayerDismissalPhysics(height: 300).threshold, 110)
        XCTAssertEqual(PlayerDismissalPhysics(height: 850).threshold, 153)
        XCTAssertEqual(PlayerDismissalPhysics(height: 1400).threshold, 180)
    }

    func testSpringMatchesAcrossRefreshRatesAndDroppedFrames() {
        func advance(_ intervals: [Double]) -> PlayerSpring {
            var spring = PlayerSpring(position: 200, velocity: 700, target: 0, frequency: 18)
            for interval in intervals { spring.advance(by: interval) }
            return spring
        }
        let sixty = advance(Array(repeating: 1.0 / 60, count: 30))
        let oneTwenty = advance(Array(repeating: 1.0 / 120, count: 60))
        let dropped = advance([0.1, 0.2, 0.2])
        XCTAssertEqual(sixty.position, oneTwenty.position, accuracy: 0.000001)
        XCTAssertEqual(sixty.velocity, oneTwenty.velocity, accuracy: 0.000001)
        XCTAssertEqual(sixty.position, dropped.position, accuracy: 0.000001)
        XCTAssertEqual(sixty.velocity, dropped.velocity, accuracy: 0.000001)
    }

    func testReturnPreservesReleaseDirectionAndSettlesWithoutCrossingTop() {
        for velocity in [-3600.0, -500, 0, 1000, 3000] {
            var spring = PlayerSpring(position: 200, velocity: velocity, target: 0, frequency: 18)
            for _ in 0..<120 {
                spring.advance(by: 1.0 / 120)
                XCTAssertGreaterThanOrEqual(spring.position, 0)
            }
            XCTAssertTrue(spring.isSettled)
        }
        var downward = PlayerSpring(position: 200, velocity: 1000, target: 0, frequency: 18)
        downward.advance(by: 1.0 / 120)
        XCTAssertGreaterThan(downward.position, 200)
    }

    func testDismissalMovesMonotonicallyUntilFullyOffscreen() {
        for height in [375.0, 850, 1366] {
            let motion = PlayerDismissalPhysics(height: height)
            for velocity in [0.0, 900, 4000] {
                let initial = motion.threshold
                var spring = PlayerSpring(
                    position: initial, velocity: min(velocity, 14 * (motion.dismissalTarget - initial)),
                    target: motion.dismissalTarget, frequency: 14)
                var previous = initial
                for _ in 0..<120 {
                    spring.advance(by: 1.0 / 120)
                    XCTAssertGreaterThanOrEqual(spring.position, previous)
                    XCTAssertLessThanOrEqual(spring.position, motion.dismissalTarget)
                    previous = spring.position
                }
                XCTAssertGreaterThan(spring.position, motion.hiddenOffset)
            }
        }
    }
}
