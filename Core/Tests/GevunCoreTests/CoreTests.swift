import XCTest
@testable import GevunCore
import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class CoreTests: XCTestCase {
    func testPublishedSubsonicTokenAndUTF8() {
        XCTAssertEqual(SubsonicToken.hash(password: "sesame", salt: "c19b2d"), "26719a1196d2a940705a59634eb18eab")
        XCTAssertEqual(SubsonicToken.hash(password: "", salt: ""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(SubsonicToken.hash(password: "abc", salt: ""), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(
            SubsonicToken.hash(password: "abcdefghijklmnopqrstuvwxyz", salt: ""), "c3fcd3d76192e4007dfb496cca67e13b")
        XCTAssertEqual(SubsonicToken.hash(password: "é", salt: ""), "66ddcd97cfdeabb2f6fb8a999b4bc76f")
        XCTAssertEqual(
            SubsonicToken.hash(password: String(repeating: "1234567890", count: 8), salt: ""),
            "57edf4a22be3c955ac49da2e2107b67a")
    }

    func testServerValidation() throws {
        let instance = try makeInstance(" https://example.com/music/// ")
        XCTAssertEqual(instance.url.absoluteString, "https://example.com/music")
        for invalid in [
            "example.com", "ftp://example.com", "https://example.com?secret=1", "https://user:pass@example.com",
            "https://example.com/#fragment", "https://",
        ] {
            XCTAssertThrowsError(try makeInstance(invalid), invalid)
            XCTAssertThrowsError(try Instance.serverURL(from: invalid), invalid)
        }
        XCTAssertThrowsError(try Instance(name: "", address: "https://example.com", username: " ", password: "x"))
    }

    func testServerAddressCanBeValidatedBeforeEnteringAccountDetails() throws {
        let url = try Instance.serverURL(from: " HTTPS://example.com/navidrome/// ")
        XCTAssertEqual(url.absoluteString, "https://example.com/navidrome")
        let instance = try Instance(name: "", address: url.absoluteString, username: " listener ", password: "secret")
        XCTAssertEqual(instance.name, "example.com")
        XCTAssertEqual(instance.username, "listener")
        XCTAssertEqual(instance.url, url)
    }

    func testAuthenticationURLPreservesBasePathAndEscapesQuery() throws {
        let api = NavidromeAPI(instance: try makeInstance("https://example.com/my%20music"))
        let url = try api.url("search3", parameters: [.init(name: "query", value: "A+B & C/é")], salt: "c19b2d")
        XCTAssertEqual(url.path, "/my music/rest/search3.view")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "query" }?.value, "A+B & C/é")
        XCTAssertEqual(items.first { $0.name == "t" }?.value, "26719a1196d2a940705a59634eb18eab")
        XCTAssertFalse(items.contains { $0.name == "p" })
        XCTAssertFalse(url.absoluteString.contains("sesame"))
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        let second = try api.url("ping")
        XCTAssertNotEqual(second, try api.url("ping"))
    }

    func testRedirectOriginComparison() {
        XCTAssertTrue(
            SameOriginRedirects.sameOrigin(
                URL(string: "https://EXAMPLE.com/a")!, URL(string: "https://example.com:443/b")!))
        XCTAssertFalse(
            SameOriginRedirects.sameOrigin(URL(string: "https://example.com")!, URL(string: "http://example.com")!))
        XCTAssertFalse(
            SameOriginRedirects.sameOrigin(URL(string: "https://example.com")!, URL(string: "https://other.com")!))
        XCTAssertFalse(
            SameOriginRedirects.sameOrigin(URL(string: "https://example.com")!, URL(string: "https://example.com:444")!)
        )
    }

    func testAPIEnvelopeEmptyListsAndProtocolFailure() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok","version":"1.16.1","albumList2":{}}}"#
        let albums = try await api.albums()
        XCTAssertTrue(albums.isEmpty)
        FixtureProtocol.body =
            #"{"subsonic-response":{"status":"failed","error":{"code":40,"message":"secret server detail"}}}"#
        do { _ = try await api.ping(); XCTFail("Expected auth error") } catch {
            XCTAssertEqual(error as? GevunError, .authentication)
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok"}}"#
        do { _ = try await api.albums(); XCTFail("Missing envelope payload must fail") } catch {
            XCTAssertEqual(error as? GevunError, .invalidResponse)
        }
    }

    func testSearchPaginationAndDecodingOptionalMetadata() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body =
            #"{"subsonic-response":{"status":"ok","searchResult3":{"album":[{"id":"a1","name":"Record"}],"song":[{"id":"s1","title":"Track"}],"artist":[{"id":"r1","name":"Artist"}]}}}"#
        let result = try await api.search("M+M", albumOffset: 30, artistOffset: 60, songOffset: 90)
        XCTAssertEqual(result.albums.first?.artistName, "Unknown artist")
        XCTAssertEqual(result.songs.first?.title, "Track")
        let items = URLComponents(url: FixtureProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "albumOffset" }?.value, "30")
        XCTAssertEqual(items.first { $0.name == "artistOffset" }?.value, "60")
        XCTAssertEqual(items.first { $0.name == "songOffset" }?.value, "90")
    }

    func testHTTPAndNonJSONFailures() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body = "<html>Login</html>"
        do {
            _ = try await api.ping()
            XCTFail()
        } catch { XCTAssertEqual(error as? GevunError, .invalidResponse) }
        FixtureProtocol.status = 503
        do {
            _ = try await api.ping()
            XCTFail()
        } catch { XCTAssertEqual(error as? GevunError, .http(503)) }
    }

    func testArtistRequestsBypassCachedResponses() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok","artist":{"id":"a1","name":"Artist"}}}"#
        _ = try await api.artist("a1")
        XCTAssertEqual(FixtureProtocol.lastRequest?.cachePolicy, .reloadIgnoringLocalCacheData)
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok","artistInfo2":{}}}"#
        _ = try await api.artistInfo("a1")
        XCTAssertEqual(FixtureProtocol.lastRequest?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testPlayerAlbumDestinationUsesAlbumArtistIdentity() throws {
        let songs = try JSONDecoder().decode(
            [Song].self,
            from: Data(
                #"[{"id":"s1","title":"Track","albumId":"record","album":"Record","artist":"Guest","artistId":"guest","albumArtists":[{"id":"band","name":"Band"}]},{"id":"s2","title":"Track","albumId":"record","artist":"Guest","artistId":"guest","albumArtist":"Band"},{"id":"s3","title":"Track"}]"#
                    .utf8))
        let album = try XCTUnwrap(Album(song: songs[0]))
        XCTAssertEqual(album.id, "record")
        XCTAssertEqual(album.name, "Record")
        XCTAssertEqual(album.artistName, "Band")
        XCTAssertEqual(album.artistId, "band")
        XCTAssertNil(Album(song: songs[1])?.artistId)
        XCTAssertNil(Album(song: songs[2]))
    }

    func testAlbumArtistDisplayPrecedence() throws {
        let song = try JSONDecoder().decode(
            Song.self,
            from: Data(
                #"{"id":"s1","title":"Track","artist":"Guest vocalist","albumArtist":"Legacy credit","displayAlbumArtist":"The Band & Friends","albumArtists":[{"id":"a1","name":"The Band"}]}"#
                    .utf8))
        XCTAssertEqual(song.artistName, "The Band & Friends")
        let album = try JSONDecoder().decode(
            Album.self,
            from: Data(
                #"{"id":"a1","name":"Record","artist":"Legacy credit","displayArtist":"The Band & Friends","artists":[{"name":"The Band"}]}"#
                    .utf8))
        XCTAssertEqual(album.artistName, "The Band & Friends")
    }

    func testAlbumArtistCreditsAndLegacyFallbacks() throws {
        let songs = try JSONDecoder().decode(
            [Song].self,
            from: Data(
                #"[{"id":"1","title":"One","artist":"Guest","displayAlbumArtist":" ","albumArtists":[{"name":" The Band "},{"name":"Friends"},{"name":"The Band"},{"name":" "}],"albumArtist":"Legacy"},{"id":"2","title":"Two","artist":"Guest","albumArtists":[],"albumArtist":" Legacy Band "},{"id":"3","title":"Three","artist":" Guest ","albumArtist":" "},{"id":"4","title":"Four"}]"#
                    .utf8))
        XCTAssertEqual(songs.map(\.artistName), ["The Band, Friends", "Legacy Band", "Guest", "Unknown artist"])
    }

    func testAlbumArtistInheritedByLegacyAlbumTracks() throws {
        let album = try JSONDecoder().decode(
            Album.self,
            from: Data(
                #"{"id":"a1","name":"Compilation","artist":"Various artists","artists":[{"name":"Album Band"},{"name":"Friends"}],"song":[{"id":"1","title":"One","artist":"Guest"},{"id":"2","title":"Two","artist":"Guest","displayAlbumArtist":"Explicit Band"}]}"#
                    .utf8))
        XCTAssertEqual(album.artistName, "Album Band, Friends")
        XCTAssertEqual(album.songs.map(\.artistName), ["Album Band, Friends", "Explicit Band"])
        let noCredit = try JSONDecoder().decode(
            Album.self,
            from: Data(#"{"id":"a2","name":"Record","song":[{"id":"3","title":"Three","artist":"Guest"}]}"#.utf8))
        XCTAssertEqual(noCredit.songs.first?.artistName, "Guest")
    }

    func testSearchRetainsAlbumArtistCredits() throws {
        let entries = #"[{"id":"s1","title":"Track","artist":"Guest","displayAlbumArtist":"Album Band"}]"#
        let search = try JSONDecoder().decode(SearchResults.self, from: Data("{\"song\":\(entries)}".utf8))
        XCTAssertEqual(search.songs.first?.artistName, "Album Band")
    }

    func testStreamAlwaysRequestsTheOriginalFile() throws {
        let api = try fixtureAPI()
        let url = try api.streamURL("song /+&?")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.path, "/rest/stream.view")
        XCTAssertEqual(query["id"], "song /+&?")
        XCTAssertEqual(query["format"], "raw")
        XCTAssertEqual(query["maxBitRate"], "0")
        XCTAssertNil(query["timeOffset"])
    }

    func testSongsBrowsePagesWithEmptyQueryAndAlbumArtistCredits() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body =
            #"{"subsonic-response":{"status":"ok","searchResult3":{"song":[{"id":"s2","title":"First","artist":"Guest","displayAlbumArtist":"Band"},{"id":"s1","title":"Second"}]}}}"#
        let songs = try await api.songs(offset: 100)
        XCTAssertEqual(songs.map(\.id), ["s2", "s1"])
        XCTAssertEqual(songs.first?.artistName, "Band")
        let url = try XCTUnwrap(FixtureProtocol.lastRequest?.url)
        XCTAssertEqual(url.lastPathComponent, "search3.view")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "query" }?.value, "")
        XCTAssertEqual(items.first { $0.name == "songOffset" }?.value, "100")
        XCTAssertEqual(items.first { $0.name == "songCount" }?.value, "100")
        XCTAssertEqual(items.first { $0.name == "albumCount" }?.value, "0")
        XCTAssertEqual(items.first { $0.name == "artistCount" }?.value, "0")
    }

    func testSongsBrowseEmptyLibraryAndMissingPayload() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok","searchResult3":{}}}"#
        let songs = try await api.songs()
        XCTAssertTrue(songs.isEmpty)
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok"}}"#
        do { _ = try await api.songs(); XCTFail("A missing browse payload must fail") } catch {
            XCTAssertEqual(error as? GevunError, .invalidResponse)
        }
    }

    func testLyricsByExactSongIDAndMultipleVersions() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body =
            #"{"subsonic-response":{"status":"ok","lyricsList":{"structuredLyrics":[{"lang":"eng","synced":true,"offset":100,"line":[{"start":1000,"value":"First original line"},{"start":3000,"value":"Second original line"}]},{"lang":"fra","synced":false,"line":[{"value":"Texte original"}]}]}}}"#
        let song = try JSONDecoder().decode(
            Song.self, from: Data(#"{"id":"s+1 &2","title":"Track","artist":"Guest"}"#.utf8))
        let lyrics = try await api.lyrics(for: song)
        XCTAssertEqual(lyrics.count, 2)
        XCTAssertEqual(lyrics.first?.lang, "eng")
        XCTAssertEqual(lyrics.first?.activeLineIndex(at: 0.9), 0)
        XCTAssertEqual(lyrics.last?.line.first?.value, "Texte original")
        XCTAssertEqual(FixtureProtocol.lastRequest?.url?.lastPathComponent, "getLyricsBySongId.view")
        let items = URLComponents(url: FixtureProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "id" }?.value, "s+1 &2")
        XCTAssertFalse(items.contains { $0.name == "artist" })
    }

    func testLyricsEmptyPayloadAndBlankText() async throws {
        let api = try fixtureAPI()
        let song = try decodeSongs()[0]
        for payload in [
            #"{"lyricsList":{}}"#,
            #"{"lyricsList":{"structuredLyrics":[{"lang":"und","synced":false,"line":[{"value":"  "},{"value":"\n"}]}]}}"#,
        ] {
            FixtureProtocol.body = "{\"subsonic-response\":{\"status\":\"ok\",\(payload.dropFirst().dropLast())}}"
            let lyrics = try await api.lyrics(for: song)
            XCTAssertTrue(lyrics.isEmpty)
            XCTAssertEqual(FixtureProtocol.lastRequest?.url?.lastPathComponent, "getLyricsBySongId.view")
        }
    }

    func testLegacyLyricsFallbackPreservesStanzasAndTrackLookup() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.bodies = [
            #"{"subsonic-response":{"status":"failed","error":{"code":0}}}"#,
            #"{"subsonic-response":{"status":"ok","lyrics":{"value":"First original line\r\n\r\nSecond original line"}}}"#,
        ]
        let song = try JSONDecoder().decode(
            Song.self,
            from: Data(#"{"id":"s1","title":"A+B","artist":"Guest vocalist","displayAlbumArtist":"Album band"}"#.utf8))
        let lyrics = try await api.lyrics(for: song)
        XCTAssertEqual(lyrics.first?.line.map(\.value), ["First original line", "", "Second original line"])
        XCTAssertEqual(lyrics.first?.synced, false)
        XCTAssertEqual(FixtureProtocol.lastRequest?.url?.lastPathComponent, "getLyrics.view")
        let items = URLComponents(url: FixtureProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "artist" }?.value, "Guest vocalist")
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "A+B")
    }

    func testLyricsDoesNotHideAuthenticationOrMalformedResponse() async throws {
        let api = try fixtureAPI()
        let song = try decodeSongs()[0]
        FixtureProtocol.body = #"{"subsonic-response":{"status":"failed","error":{"code":40}}}"#
        do { _ = try await api.lyrics(for: song); XCTFail("Authentication must fail") } catch {
            XCTAssertEqual(error as? GevunError, .authentication)
        }
        XCTAssertEqual(FixtureProtocol.lastRequest?.url?.lastPathComponent, "getLyricsBySongId.view")
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok"}}"#
        do { _ = try await api.lyrics(for: song); XCTFail("Missing lyrics payload must fail") } catch {
            XCTAssertEqual(error as? GevunError, .invalidResponse)
        }
        XCTAssertEqual(FixtureProtocol.lastRequest?.url?.lastPathComponent, "getLyricsBySongId.view")
    }

    func testSynchronizedLyricsOffsetsAndSeekPositions() {
        let lines = [LyricLine(start: 1000, value: "First"), LyricLine(start: 2000, value: "Second")]
        let early = StructuredLyrics(synced: true, offset: 100, line: lines)
        XCTAssertNil(early.activeLineIndex(at: 0.8))
        XCTAssertEqual(early.activeLineIndex(at: 0.9), 0)
        XCTAssertEqual(early.activeLineIndex(at: 1.9), 1)
        XCTAssertEqual(early.seekTime(for: 0)!, 0.9, accuracy: 0.001)
        XCTAssertEqual(early.seekTime(for: 1)!, 1.9, accuracy: 0.001)
        let late = StructuredLyrics(synced: true, offset: -100, line: lines)
        XCTAssertNil(late.activeLineIndex(at: 1))
        XCTAssertEqual(late.activeLineIndex(at: 1.1), 0)
        XCTAssertEqual(late.seekTime(for: 0)!, 1.1, accuracy: 0.001)
        XCTAssertNil(late.seekTime(for: -1))
        XCTAssertNil(late.seekTime(for: 2))
        XCTAssertNil(late.activeLineIndex(at: .nan))
        let plain = StructuredLyrics(line: [LyricLine(value: "Text")])
        XCTAssertNil(plain.activeLineIndex(at: 10))
        XCTAssertNil(plain.seekTime(for: 0))
    }

    func testQueueBoundariesRepeatAndPlayNext() throws {
        let songs = try decodeSongs()
        var queue = PlaybackQueue()
        queue.replace(songs, startingAt: 1)
        XCTAssertEqual(queue.current?.id, "2")
        queue.repeatMode = .one
        XCTAssertTrue(queue.advance(automatic: true)); XCTAssertEqual(queue.current?.id, "2")
        XCTAssertTrue(queue.advance()); XCTAssertEqual(queue.current?.id, "3")
        queue.repeatMode = .off
        XCTAssertFalse(queue.advance())
        queue.repeatMode = .all; XCTAssertTrue(queue.advance()); XCTAssertEqual(queue.current?.id, "1")
        queue.append(songs[2], next: true)
        XCTAssertTrue(queue.advance()); XCTAssertEqual(queue.current?.id, "3")
        queue.replace([])
        XCTAssertNil(queue.current)
        XCTAssertFalse(queue.advance())
    }

    func testShuffleRetainsCurrentTrackAndRestoresOrder() throws {
        let songs = try decodeSongs()
        var queue = PlaybackQueue()
        queue.replace(songs, startingAt: 1)
        queue.toggleShuffle()
        XCTAssertTrue(queue.shuffled); XCTAssertEqual(queue.current?.id, "2")
        XCTAssertEqual(Set(queue.songs.map(\.id)), Set(songs.map(\.id)))
        queue.toggleShuffle()
        XCTAssertFalse(queue.shuffled)
        XCTAssertEqual(queue.songs, songs)
        XCTAssertEqual(queue.index, 1)
    }

    func testArtistInfoRequestAndOptionalMetadata() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body =
            #"{"subsonic-response":{"status":"ok","artistInfo2":{"biography":"<p>A &amp; B</p>","similarArtist":[{"id":"r2","name":"Related"}]}}}"#
        let info = try await api.artistInfo("r1")
        XCTAssertEqual(info.description, "A & B")
        XCTAssertEqual(info.relatedArtists(excluding: "r1").map(\.id), ["r2"])
        let url = try XCTUnwrap(FixtureProtocol.lastRequest?.url)
        XCTAssertEqual(url.lastPathComponent, "getArtistInfo2.view")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "id" }?.value, "r1")
        XCTAssertEqual(items.first { $0.name == "count" }?.value, "12")
        XCTAssertEqual(items.first { $0.name == "includeNotPresent" }?.value, "false")
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok","artistInfo2":{}}}"#
        let empty = try await api.artistInfo("r1")
        XCTAssertNil(empty.description)
        XCTAssertNil(empty.lastFMURL)
        XCTAssertTrue(empty.relatedArtists(excluding: "r1").isEmpty)
        FixtureProtocol.body = #"{"subsonic-response":{"status":"ok"}}"#
        do { _ = try await api.artistInfo("r1"); XCTFail("Missing payload must fail") } catch {
            XCTAssertEqual(error as? GevunError, .invalidResponse)
        }
        FixtureProtocol.body = #"{"subsonic-response":{"status":"failed","error":{"code":10}}}"#
        do { _ = try await api.artistInfo("r1"); XCTFail("Unsupported endpoint must fail") } catch {
            XCTAssertEqual(error as? GevunError, .server(10))
        }
    }

    func testArtistBiographyPreservesParagraphsAndDecodesInertHTML() throws {
        let data =
            #"{"biography":"<p>Bj&#246;rk &amp; friends &mdash; &#x1F3B5;</p><p>Second <a href='https://last.fm/music/Test'>paragraph</a> &lt;live&gt;.</p><script>bad()</script><!-- ignore --><style>body{}</style>"}"#
        let info = try JSONDecoder().decode(ArtistInfo.self, from: Data(data.utf8))
        XCTAssertEqual(info.description, "Björk & friends — 🎵\n\nSecond paragraph <live>.")
        let blank = try JSONDecoder().decode(ArtistInfo.self, from: Data(#"{"biography":"<p> &nbsp; </p>"}"#.utf8))
        XCTAssertNil(blank.description)
        let plain = try JSONDecoder().decode(
            ArtistInfo.self, from: Data(#"{"biography":"First\n\nSecond & unknown &#999999999;"}"#.utf8))
        XCTAssertEqual(plain.description, "First\n\nSecond & unknown &#999999999;")
    }

    func testArtistProfileLinksAndRelatedArtists() throws {
        let value =
            #"{"lastFmUrl":"https://www.last.fm/music/Artist","musicBrainzId":"189002e7-3285-4e2e-92a3-7f6c30d407a2","similarArtist":[{"id":"self","name":"Current"},{"id":"-1","name":"External"},{"id":"","name":"Invalid"},{"id":"r1","name":"Related"},{"id":"r1","name":"Duplicate"},{"id":"r2","name":" "}]}"#
        let info = try JSONDecoder().decode(ArtistInfo.self, from: Data(value.utf8))
        XCTAssertEqual(info.lastFMURL?.host, "www.last.fm")
        XCTAssertEqual(
            info.musicBrainzURL?.absoluteString, "https://musicbrainz.org/artist/189002e7-3285-4e2e-92a3-7f6c30d407a2")
        XCTAssertEqual(info.relatedArtists(excluding: "self").map(\.id), ["r1"])
        for address in [
            "javascript:alert(1)", "https://last.fm.example.org/music/a", "https://user:secret@last.fm/a",
            "file:///tmp/a",
        ] {
            let data = try JSONSerialization.data(withJSONObject: ["lastFmUrl": address, "musicBrainzId": "invalid/id"])
            let invalid = try JSONDecoder().decode(ArtistInfo.self, from: data)
            XCTAssertNil(invalid.lastFMURL)
            XCTAssertNil(invalid.musicBrainzURL)
        }
    }

    func testTimeLabels() {
        XCTAssertEqual(TimeLabel.clock(.nan), "0:00")
        XCTAssertEqual(TimeLabel.clock(-10), "0:00")
        XCTAssertEqual(TimeLabel.clock(125), "2:05")
        XCTAssertEqual(TimeLabel.duration(3661), "1 hr 1 min")
    }

    private func makeInstance(_ address: String = "https://example.com") throws -> Instance {
        try Instance(name: "Home", address: address, username: "user", password: "sesame")
    }

    func testSavedQueueUsesSongIDsAndMilliseconds() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body =
            #"{"subsonic-response":{"status":"ok","playQueue":{"current":"2","position":12345,"entry":[{"id":"1","title":"One"},{"id":"2","title":"Two"}]}}}"#
        let response = try await api.savedQueue()
        let saved = try XCTUnwrap(response)
        XCTAssertEqual(saved.index, 1)
        XCTAssertEqual(saved.seconds, 12.345)
        try await api.saveQueue(songs: saved.songs, index: saved.index, position: saved.seconds)
        let query = mutationParameters()
        XCTAssertEqual(query.first { $0.name == "current" }?.value, "2")
        XCTAssertEqual(query.first { $0.name == "position" }?.value, "12345")
    }

    func testListeningLinkAndPermissionFailure() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.body =
            #"{"subsonic-response":{"status":"ok","shares":{"share":[{"url":"https://music.example/share/example"}]}}}"#
        let link = try await api.share(["album"])
        XCTAssertEqual(link.absoluteString, "https://music.example/share/example")
        FixtureProtocol.body = #"{"subsonic-response":{"status":"failed","error":{"code":50}}}"#
        do { _ = try await api.share(["album"]); XCTFail("Expected disabled sharing") } catch {
            XCTAssertEqual(error as? GevunError, .forbidden)
        }
    }

    func testIndexQueueCapabilityPreservesDuplicateOccurrence() async throws {
        let api = try fixtureAPI()
        FixtureProtocol.bodies = [
            #"{"subsonic-response":{"status":"ok","openSubsonicExtensions":[{"name":"indexBasedQueue","versions":[1]}]}}"#,
            #"{"subsonic-response":{"status":"ok","playQueueByIndex":{"currentIndex":1,"position":4500,"entry":[{"id":"same","title":"One"},{"id":"same","title":"One"}]}}}"#,
            #"{"subsonic-response":{"status":"ok"}}"#,
        ]
        let response = try await api.savedQueue()
        let saved = try XCTUnwrap(response)
        XCTAssertEqual(saved.index, 1)
        try await api.saveQueue(songs: saved.songs, index: saved.index, position: saved.seconds)
        XCTAssertEqual(FixtureProtocol.lastRequest?.url?.lastPathComponent, "savePlayQueueByIndex.view")
        let query = mutationParameters()
        XCTAssertEqual(query.first { $0.name == "currentIndex" }?.value, "1")
        XCTAssertEqual(query.filter { $0.name == "id" }.compactMap(\.value), ["same", "same"])
    }

    func testListeningSessionRoundTripPreservesQueueAndRejectsInvalidVersion() throws {
        var queue = PlaybackQueue()
        queue.replace(try decodeSongs(), startingAt: 1, shuffle: true)
        queue.repeatMode = .all
        let session = ListeningSession(queue: queue, position: 12.5)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ListeningSession.self, from: data)
        XCTAssertTrue(decoded.isValid)
        XCTAssertEqual(decoded.position, 12.5)
        XCTAssertEqual(decoded.queue.songs.map(\.id), queue.songs.map(\.id))
        XCTAssertEqual(decoded.queue.index, queue.index)
        XCTAssertEqual(decoded.queue.repeatMode, .all)
        var restored = decoded.queue
        restored.toggleShuffle()
        XCTAssertEqual(restored.songs.map(\.id), ["1", "2", "3"])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 99
        let unsupported = try JSONDecoder().decode(
            ListeningSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(unsupported.isValid)
        XCTAssertFalse(ListeningSession(queue: PlaybackQueue(), position: 0).isValid)
        XCTAssertThrowsError(try JSONDecoder().decode(ListeningSession.self, from: Data("broken".utf8)))
    }

    func testRestoredUnknownDurationRetainsPositionWithoutCountingListening() {
        var timeline = PlaybackTimeline()
        timeline.restorePosition(45)
        XCTAssertEqual(timeline.elapsed, 45)
        XCTAssertEqual(timeline.listeningTime, 0)
        timeline.updatePreciseDuration(30)
        XCTAssertEqual(timeline.elapsed, 30)
    }

    private func mutationParameters() -> [URLQueryItem] {
        let request = FixtureProtocol.lastRequest!
        XCTAssertEqual(request.httpMethod, "POST")
        var form = URLComponents()
        form.percentEncodedQuery = String(data: request.httpBody ?? Data(), encoding: .utf8)
        return form.queryItems ?? []
    }

    private func fixtureAPI() throws -> NavidromeAPI {
        FixtureProtocol.status = 200
        FixtureProtocol.bodies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return NavidromeAPI(instance: try makeInstance(), session: URLSession(configuration: config))
    }

    private func decodeSongs() throws -> [Song] {
        try JSONDecoder().decode(
            [Song].self,
            from: Data(#"[{"id":"1","title":"One"},{"id":"2","title":"Two"},{"id":"3","title":"Three"}]"#.utf8))
    }
}

private final class FixtureProtocol: URLProtocol {
    static var body = ""
    static var bodies: [String] = []
    static var status = 200
    static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        client?.urlProtocol(
            self,
            didReceive: HTTPURLResponse(
                url: request.url!, statusCode: Self.status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        let body = Self.bodies.isEmpty ? Self.body : Self.bodies.removeFirst()
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
