import XCTest
@testable import GevunCore

final class NowPlayingPublicationTests: XCTestCase {
    private func playing() -> NowPlayingPublication.State {
        .init(playbackID: UUID(), duration: 240, rate: 1)
    }

    func testSteadyPlaybackDoesNotRepublishMetadata() {
        var publication = NowPlayingPublication()
        let state = playing()
        XCTAssertTrue(publication.shouldPublish(state))
        for _ in 0..<120 { XCTAssertFalse(publication.shouldPublish(state)) }
    }

    func testPauseBufferAndResumeUpdateTheSystemClock() {
        var publication = NowPlayingPublication()
        var state = playing()
        XCTAssertTrue(publication.shouldPublish(state))
        state.rate = 0
        XCTAssertTrue(publication.shouldPublish(state))
        XCTAssertFalse(publication.shouldPublish(state))
        state.rate = 1
        XCTAssertTrue(publication.shouldPublish(state))
        state.rate = 0  // buffering
        XCTAssertTrue(publication.shouldPublish(state))
        state.rate = 1
        XCTAssertTrue(publication.shouldPublish(state))
    }

    func testEachSeekAndItsSettlementRepublishEvenWhilePaused() {
        var publication = NowPlayingPublication()
        var state = playing()
        state.rate = 0
        XCTAssertTrue(publication.shouldPublish(state))
        state.seekID = UUID()
        XCTAssertTrue(publication.shouldPublish(state))
        XCTAssertFalse(publication.shouldPublish(state))
        state.seekID = UUID()  // supersedes the first seek without changing playback rate
        XCTAssertTrue(publication.shouldPublish(state))
        state.seekID = nil
        XCTAssertTrue(publication.shouldPublish(state))
        XCTAssertFalse(publication.shouldPublish(state))
    }

    func testTrackReplacementAndRepeatRestartUpdateMetadata() {
        var publication = NowPlayingPublication()
        var state = playing()
        XCTAssertTrue(publication.shouldPublish(state))
        state.playbackID = UUID()  // new item, including a repeat of the same song
        XCTAssertTrue(publication.shouldPublish(state))
        XCTAssertFalse(publication.shouldPublish(state))
    }

    func testArtworkDurationAndFailureChangesArePublishedOnce() {
        var publication = NowPlayingPublication()
        var state = playing()
        XCTAssertTrue(publication.shouldPublish(state))
        state.artworkRevision = UUID()
        XCTAssertTrue(publication.shouldPublish(state))
        XCTAssertFalse(publication.shouldPublish(state))
        state.duration = 245
        XCTAssertTrue(publication.shouldPublish(state))
        state.failed = true
        XCTAssertTrue(publication.shouldPublish(state))
        XCTAssertFalse(publication.shouldPublish(state))
    }

    func testDiscontinuityForcesAnUpdateAndStopResetsPublication() {
        var publication = NowPlayingPublication()
        let state = playing()
        XCTAssertTrue(publication.shouldPublish(state))
        XCTAssertTrue(publication.shouldPublish(state, force: true))
        XCTAssertFalse(publication.shouldPublish(state))
        publication.reset()
        XCTAssertTrue(publication.shouldPublish(state))
    }
}
