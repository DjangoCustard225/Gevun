import XCTest
@testable import GevunCore

final class PlaybackTimelineTests: XCTestCase {
    func testForwardSeekDoesNotSnapBackWhileMediaIsSeeking() throws {
        var timeline = track()
        timeline.tick(at: 20, isPlaying: true)
        let seek = try XCTUnwrap(timeline.beginSeek(to: 120))
        XCTAssertEqual(timeline.elapsed, 120)
        XCTAssertFalse(timeline.tick(at: 20.5, isPlaying: true))
        XCTAssertFalse(timeline.tick(at: 21, isPlaying: true))
        XCTAssertEqual(timeline.elapsed, 120)
        XCTAssertTrue(timeline.completeSeek(seek, at: 120.1))
        timeline.tick(at: 120.6, isPlaying: true)
        XCTAssertEqual(timeline.elapsed, 120.6)
        XCTAssertEqual(timeline.listeningTime, 0.5, accuracy: 0.0001)
    }

    func testBackwardSeekCannotBeOverwrittenByOldProgress() throws {
        var timeline = track()
        timeline.tick(at: 160, isPlaying: true)
        let seek = try XCTUnwrap(timeline.beginSeek(to: 30))
        XCTAssertFalse(timeline.tick(at: 160.5, isPlaying: true))
        XCTAssertEqual(timeline.elapsed, 30)
        timeline.completeSeek(seek, at: 30)
        timeline.tick(at: 30.5, isPlaying: true)
        XCTAssertEqual(timeline.elapsed, 30.5)
    }

    func testRapidSeeksIgnoreSupersededCompletions() throws {
        var timeline = track()
        let first = try XCTUnwrap(timeline.beginSeek(to: 100))
        let second = try XCTUnwrap(timeline.beginSeek(to: 45))
        XCTAssertFalse(timeline.completeSeek(first, at: 100))
        XCTAssertEqual(timeline.elapsed, 45)
        XCTAssertEqual(timeline.pendingSeek, second)
        XCTAssertTrue(timeline.completeSeek(second, at: 45))
        XCTAssertFalse(timeline.completeSeek(first, at: 100))
        XCTAssertEqual(timeline.elapsed, 45)
    }

    func testChangingTracksInvalidatesAnInFlightSeek() throws {
        var timeline = track()
        let old = try XCTUnwrap(timeline.beginSeek(to: 190))
        timeline.reset(duration: 80)
        XCTAssertFalse(timeline.completeSeek(old, at: 190))
        XCTAssertEqual(timeline.elapsed, 0)
        XCTAssertEqual(timeline.duration, 80)
        XCTAssertEqual(timeline.listeningTime, 0)
        XCTAssertNil(timeline.pendingSeek)
        let new = try XCTUnwrap(timeline.beginSeek(to: 40))
        XCTAssertFalse(timeline.completeSeek(old, at: 190))
        XCTAssertEqual(timeline.pendingSeek, new)
    }

    func testInterruptedSeekReconcilesToActualPosition() throws {
        var timeline = track()
        timeline.tick(at: 10, isPlaying: false)
        let seek = try XCTUnwrap(timeline.beginSeek(to: 120))
        timeline.completeSeek(seek, at: 10)
        XCTAssertNil(timeline.pendingSeek)
        XCTAssertEqual(timeline.elapsed, 10)
        timeline.tick(at: 10.5, isPlaying: true)
        XCTAssertEqual(timeline.listeningTime, 0.5)
    }

    func testPausedSeekingDoesNotCountAsListening() throws {
        var timeline = track()
        timeline.tick(at: 10, isPlaying: false)
        let seek = try XCTUnwrap(timeline.beginSeek(to: 180))
        timeline.completeSeek(seek, at: 180)
        timeline.tick(at: 180, isPlaying: false)
        timeline.tick(at: 180, isPlaying: false)
        XCTAssertEqual(timeline.elapsed, 180)
        XCTAssertEqual(timeline.listeningTime, 0)
    }

    func testOnlyContinuousPlaybackAccumulatesListeningTime() {
        var timeline = track()
        timeline.tick(at: 10, isPlaying: true)
        timeline.tick(at: 10.5, isPlaying: true)
        timeline.tick(at: 70, isPlaying: true)
        timeline.tick(at: 20, isPlaying: true)
        timeline.tick(at: 20.5, isPlaying: false)
        timeline.tick(at: 21, isPlaying: true)
        XCTAssertEqual(timeline.listeningTime, 1)
    }

    func testSeekBoundsAndNonFiniteValues() throws {
        var timeline = track()
        XCTAssertNil(timeline.beginSeek(to: .nan))
        XCTAssertNil(timeline.beginSeek(to: .infinity))
        let start = try XCTUnwrap(timeline.beginSeek(to: -20))
        XCTAssertEqual(start.target, 0)
        let end = try XCTUnwrap(timeline.beginSeek(to: 1_000))
        XCTAssertEqual(end.target, 240)
        timeline.completeSeek(end, at: 240.3)
        XCTAssertEqual(timeline.elapsed, 240)
        XCTAssertFalse(timeline.tick(at: .nan, isPlaying: true))
        XCTAssertFalse(timeline.tick(at: .infinity, isPlaying: true))
        XCTAssertEqual(timeline.elapsed, 240)
    }

    func testServerDurationDoesNotChangeAfterSeekingAStream() {
        var timeline = track()
        timeline.tick(at: 100, isPlaying: true)
        timeline.updateAssetDuration(110)
        timeline.updateAssetDuration(600)
        XCTAssertEqual(timeline.duration, 240)
        XCTAssertEqual(timeline.elapsed, 100)
    }

    func testAssetDurationFallbackRejectsInvalidEstimates() {
        var timeline = PlaybackTimeline()
        timeline.reset(duration: 0)
        XCTAssertNil(timeline.beginSeek(to: 10))
        for value in [Double.nan, .infinity, -1, 0] { timeline.updateAssetDuration(value) }
        XCTAssertEqual(timeline.duration, 0)
        timeline.updateAssetDuration(180)
        XCTAssertEqual(timeline.duration, 180)
        XCTAssertEqual(timeline.beginSeek(to: 90)?.target, 90)
    }

    func testPreciseFileDurationCorrectsMetadataAndRejectsLaterEstimates() throws {
        var timeline = track()
        timeline.updatePreciseDuration(203.75)
        XCTAssertEqual(timeline.duration, 203.75)
        timeline.updateAssetDuration(600)
        XCTAssertEqual(timeline.duration, 203.75)
        let seek = try XCTUnwrap(timeline.beginSeek(to: 230))
        XCTAssertEqual(seek.target, 203.75)
        timeline.completeSeek(seek, at: 203.75)
        XCTAssertEqual(timeline.elapsed, 203.75)
    }

    func testInvalidPreciseDurationsPreserveTheCurrentTimeline() {
        var timeline = track()
        timeline.tick(at: 180, isPlaying: true)
        for value in [Double.nan, .infinity, -1, 0] { timeline.updatePreciseDuration(value) }
        XCTAssertEqual(timeline.duration, 240)
        XCTAssertEqual(timeline.elapsed, 180)
    }

    func testPreciseDurationDuringSeekPreservesRequestAndSettlesAtActualTime() throws {
        var timeline = track()
        timeline.tick(at: 20, isPlaying: true)
        let seek = try XCTUnwrap(timeline.beginSeek(to: 220))
        timeline.updatePreciseDuration(210.5)
        XCTAssertEqual(timeline.pendingSeek, seek)
        XCTAssertEqual(timeline.elapsed, 210.5)
        XCTAssertFalse(timeline.tick(at: 20.1, isPlaying: true))
        XCTAssertTrue(timeline.completeSeek(seek, at: 209.9))
        XCTAssertEqual(timeline.elapsed, 209.9)
        timeline.tick(at: 210, isPlaying: true)
        XCTAssertEqual(timeline.elapsed, 210)
        XCTAssertEqual(timeline.listeningTime, 0.1, accuracy: 0.0001)
    }

    func testReplacingTrackClearsPreciseDurationAndItsBounds() {
        var timeline = track()
        timeline.updatePreciseDuration(120)
        timeline.reset(duration: 0)
        timeline.updateAssetDuration(300)
        XCTAssertEqual(timeline.duration, 300)
        XCTAssertEqual(timeline.elapsed, 0)
        XCTAssertEqual(timeline.beginSeek(to: 250)?.target, 250)
    }

    private func track() -> PlaybackTimeline {
        var timeline = PlaybackTimeline()
        timeline.reset(duration: 240)
        return timeline
    }
}
