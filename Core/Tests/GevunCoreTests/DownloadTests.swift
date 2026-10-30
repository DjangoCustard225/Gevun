import Foundation
import XCTest
@testable import GevunCore

final class DownloadTests: XCTestCase {
    private func song(_ id: String = "track", album: String = "album") throws -> Song {
        try JSONDecoder().decode(
            Song.self,
            from: JSONSerialization.data(withJSONObject: [
                "id": id, "title": "Song \(id)", "albumId": album, "album": "An album", "artist": "Artist",
                "suffix": "flac", "duration": 180, "size": 8_000_000,
            ]))
    }

    private func instance() throws -> Instance {
        try Instance(
            name: "Music", address: "https://music.example.com/navidrome", username: "listener",
            password: "private-password")
    }

    func testDownloadParametersRemainSeparateFromDirectStreaming() throws {
        let api = NavidromeAPI(instance: try instance())
        func params(_ url: URL) -> [String: String] {
            Dictionary(
                uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map {
                    ($0.name, $0.value ?? "")
                })
        }
        let raw = try api.downloadURL("a+b /?", quality: DownloadQuality())
        XCTAssertEqual(raw.path, "/navidrome/rest/download.view")
        XCTAssertEqual(params(raw)["id"], "a+b /?")
        XCTAssertEqual(params(raw)["format"], "raw")
        XCTAssertEqual(params(raw)["bitrate"], "0")
        XCTAssertNil(params(raw)["maxBitRate"])
        for format in DownloadFormat.allCases where format != .original {
            let converted = try api.downloadURL("song", quality: DownloadQuality(format: format))
            XCTAssertEqual(params(converted)["format"], format.rawValue)
            XCTAssertEqual(params(converted)["bitrate"], String(format.defaultBitrate))
        }
        let stream = try api.streamURL("song")
        XCTAssertEqual(params(stream)["format"], "raw")
        XCTAssertEqual(params(stream)["maxBitRate"], "0")
        XCTAssertNil(params(stream)["bitrate"])
    }

    func testQualityChoicesNeverSendAnInvalidBitrate() {
        XCTAssertEqual(DownloadFormat.allCases, [.original, .mp3, .aac])
        XCTAssertEqual(try JSONDecoder().decode(DownloadFormat.self, from: Data("\"opus\"".utf8)), .opus)
        XCTAssertEqual(DownloadQuality(format: .original, bitrate: 320).bitrate, 0)
        XCTAssertEqual(DownloadQuality(format: .opus, bitrate: -1).bitrate, 128)
        XCTAssertEqual(DownloadQuality(format: .mp3, bitrate: 999).bitrate, 320)
        XCTAssertEqual(DownloadQuality(format: .aac, bitrate: 96).bitrate, 96)
    }

    func testNamespaceSeparatesAccountsServersAndInstancesButSurvivesPasswordChanges() throws {
        let first = try instance()
        var changed = first
        changed.password = "new-password"
        changed.name = "Renamed"
        XCTAssertEqual(DownloadKey.namespace(for: first), DownloadKey.namespace(for: changed))
        changed.username = "another-user"
        XCTAssertNotEqual(DownloadKey.namespace(for: first), DownloadKey.namespace(for: changed))
        changed = first
        changed.url = URL(string: "https://music.example.com/another-library")!
        XCTAssertNotEqual(DownloadKey.namespace(for: first), DownloadKey.namespace(for: changed))
        changed = first
        changed.id = UUID()
        XCTAssertNotEqual(DownloadKey.namespace(for: first), DownloadKey.namespace(for: changed))
    }

    func testDuplicateRequestsAndMatchingSavedCopiesAreNotDownloadedAgain() throws {
        var library = DownloadLibrary()
        let track = try song()
        let id = try XCTUnwrap(library.enqueue(track, namespace: "server", quality: DownloadQuality()))
        XCTAssertNil(library.enqueue(track, namespace: "server", quality: DownloadQuality(format: .opus)))
        library.complete(id, filename: "one.flac", bytes: 100)
        XCTAssertNil(library.enqueue(track, namespace: "server", quality: DownloadQuality()))
        XCTAssertNotNil(library.enqueue(track, namespace: "server", quality: DownloadQuality(format: .opus)))
    }

    func testReplacementRetainsOldCopyUntilCommitAndLateCompletionCannotResurrectCancellation() throws {
        var library = DownloadLibrary()
        let track = try song()
        let original = try XCTUnwrap(library.enqueue(track, namespace: "server", quality: DownloadQuality()))
        library.complete(original, filename: "old.flac", bytes: 1000)
        let cancelled = try XCTUnwrap(
            library.enqueue(track, namespace: "server", quality: DownloadQuality(format: .opus)))
        XCTAssertEqual(library.copies.first?.filename, "old.flac")
        library.jobs.removeAll { $0.id == cancelled }
        XCTAssertNil(library.complete(cancelled, filename: "cancelled.opus", bytes: 200))
        XCTAssertEqual(library.copies.first?.filename, "old.flac")
        let replacement = try XCTUnwrap(
            library.enqueue(track, namespace: "server", quality: DownloadQuality(format: .aac)))
        let previous = library.complete(replacement, filename: "new.aac", bytes: 300)
        XCTAssertEqual(previous?.filename, "old.flac")
        XCTAssertEqual(library.copies.count, 1)
        XCTAssertEqual(library.copies.first?.filename, "new.aac")
        XCTAssertTrue(library.jobs.isEmpty)
    }

    func testIdenticalSongIDsAcrossServersRemainIndependent() throws {
        var library = DownloadLibrary()
        let a = try XCTUnwrap(library.enqueue(song(), namespace: "a", quality: DownloadQuality()))
        let b = try XCTUnwrap(library.enqueue(song(), namespace: "b", quality: DownloadQuality()))
        library.complete(a, filename: "a.flac", bytes: 100)
        library.complete(b, filename: "b.flac", bytes: 100)
        XCTAssertEqual(library.copies.count, 2)
        XCTAssertEqual(Set(library.copies.map(\.key.namespace)), ["a", "b"])
    }

    func testPersistedQueueAndOfflineMetadataRoundTripWithoutCredentials() throws {
        var library = DownloadLibrary()
        let server = try instance()
        let namespace = DownloadKey.namespace(for: server)
        let id = try XCTUnwrap(library.enqueue(song(), namespace: namespace, quality: DownloadQuality(format: .opus)))
        library.complete(id, filename: "saved.opus", bytes: 500)
        library.enqueue(try song("other"), namespace: namespace, quality: DownloadQuality())
        library.jobs[0].state = .transferring
        library.preferences[namespace] = DownloadQuality(format: .aac, bitrate: 192)
        let data = try JSONEncoder().encode(library)
        let restored = try JSONDecoder().decode(DownloadLibrary.self, from: data)
        XCTAssertEqual(restored.copies.first?.song.album, "An album")
        XCTAssertEqual(restored.copies.first?.song.size, 8_000_000)
        XCTAssertEqual(restored.jobs.first?.state, .transferring)
        XCTAssertEqual(restored.preferences[namespace]?.bitrate, 192)
        let text = String(decoding: data, as: UTF8.self)
        for secret in [server.password, server.username, server.url.absoluteString, "download.view", "?u="] {
            XCTAssertFalse(text.contains(secret))
        }
    }

    func testOfflineAlbumsAreDerivedFromAllSavedSongsWithoutServerPages() throws {
        var library = DownloadLibrary()
        for index in 0..<125 {
            let track = try song(String(index), album: index < 100 ? "first" : "second")
            let id = try XCTUnwrap(library.enqueue(track, namespace: "server", quality: DownloadQuality()))
            library.complete(id, filename: "\(index).flac", bytes: 100)
        }
        let albums = library.downloadedAlbums(namespace: "server")
        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(Set(albums.map { $0.songCount ?? 0 }), [100, 25])
        XCTAssertTrue(library.downloadedAlbums(namespace: "another-server").isEmpty)
    }

    func testBatchCompletionRequiresEveryUniqueSongAtTheRequestedQualityAndServer() throws {
        let first = try song("first"), second = try song("second")
        let quality = DownloadQuality(format: .aac)
        var library = DownloadLibrary()
        func status() -> DownloadBatchStatus {
            DownloadBatchStatus(library: library, songs: [first, first, second], namespace: "a", quality: quality)
        }
        let wrongServer = try XCTUnwrap(library.enqueue(first, namespace: "b", quality: quality))
        library.complete(wrongServer, filename: "b.m4a", bytes: 100)
        let wrongQuality = try XCTUnwrap(library.enqueue(first, namespace: "a", quality: DownloadQuality()))
        library.complete(wrongQuality, filename: "a.flac", bytes: 100)
        XCTAssertEqual(status().totalCount, 2)
        XCTAssertEqual(status().savedCount, 0)
        XCTAssertFalse(status().isComplete)
        for track in [first, second] {
            let id = try XCTUnwrap(library.enqueue(track, namespace: "a", quality: quality))
            library.complete(id, filename: "\(track.id).m4a", bytes: 100)
        }
        XCTAssertEqual(status().savedCount, 2)
        XCTAssertTrue(status().isComplete)
    }

    func testFailedAndCancelledBatchesDoNotCountAsCompleted() throws {
        let track = try song()
        var library = DownloadLibrary()
        let id = try XCTUnwrap(library.enqueue(track, namespace: "a", quality: DownloadQuality()))
        library.enqueue(track, namespace: "b", quality: DownloadQuality())
        library.enqueue(try song("unrelated"), namespace: "a", quality: DownloadQuality())
        library.jobs[0].state = .failed
        let failed = DownloadBatchStatus(library: library, songs: [track], namespace: "a", quality: DownloadQuality())
        XCTAssertEqual(failed.jobs.map(\.id), [id])
        XCTAssertFalse(failed.isComplete)
        library.jobs.removeAll { $0.id == id }
        let cancelled = DownloadBatchStatus(
            library: library, songs: [track], namespace: "a", quality: DownloadQuality())
        XCTAssertTrue(cancelled.jobs.isEmpty)
        XCTAssertFalse(cancelled.isComplete)
        let empty = DownloadBatchStatus(library: library, songs: [], namespace: "a", quality: DownloadQuality())
        XCTAssertFalse(empty.isComplete)
    }

    func testHTTPAndSubsonicErrorsAreNeverAcceptedAsAudio() {
        let audio = Data([0x49, 0x44, 0x33, 0x04, 0x00])
        XCTAssertNil(DownloadLibrary.responseError(status: 200, prefix: audio))
        XCTAssertNotNil(DownloadLibrary.responseError(status: 200, prefix: Data()))
        XCTAssertNotNil(DownloadLibrary.responseError(status: 403, prefix: audio))
        XCTAssertNotNil(DownloadLibrary.responseError(status: 429, prefix: audio))
        for body in [
            "<html>Sign in</html>", "<?xml version=\"1.0\"?><subsonic-response status=\"failed\"/>",
            "{\"subsonic-response\": {\"status\": \"failed\", \"error\": {\"code\": 50}}}",
        ] {
            XCTAssertNotNil(DownloadLibrary.responseError(status: 200, prefix: Data(body.utf8)))
        }
        let disabled = Data("{\"subsonic-response\": {\"error\": {\"code\": 50}}}".utf8)
        XCTAssertTrue(DownloadLibrary.responseError(status: 200, prefix: disabled)?.contains("disabled") == true)
    }
}
