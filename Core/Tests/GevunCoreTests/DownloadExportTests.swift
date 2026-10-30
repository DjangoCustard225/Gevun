import Foundation
import XCTest
@testable import GevunCore

final class DownloadExportTests: XCTestCase {
    private func copy(title: String, artist: String = "Artist", filename: String = "saved.m4a") throws -> OfflineSong {
        let song = try JSONDecoder().decode(
            Song.self,
            from: JSONSerialization.data(withJSONObject: [
                "id": UUID().uuidString, "title": title, "artist": "Track artist",
                "displayAlbumArtist": artist, "suffix": "flac",
            ]))
        return OfflineSong(
            key: DownloadKey(namespace: "server", songID: song.id), song: song,
            quality: DownloadQuality(format: .aac), filename: filename, bytes: 100)
    }

    func testExportUsesAlbumArtistAndActualSavedFormat() throws {
        let names = DownloadExportNames.filenames(for: [try copy(title: "A song", artist: "The Band")])
        XCTAssertEqual(names, ["The Band - A song.m4a"])
    }

    func testRawAACExportsUseM4AWhileOriginalsKeepTheirFormat() throws {
        let aac = try copy(title: "A song", filename: "saved.aac")
        let original = OfflineSong(
            key: aac.key, song: aac.song, quality: DownloadQuality(), filename: "original.flac", bytes: 100)
        XCTAssertEqual(DownloadExportNames.filenames(for: [aac]), ["Artist - A song.m4a"])
        XCTAssertEqual(DownloadExportNames.filenames(for: [original]), ["Artist - A song.flac"])
    }

    func testExportMetadataKeepsTrackAndAlbumArtistsSeparateAndIncludesLyrics() throws {
        let copy = try copy(title: "A song", artist: "Album artist")
        let metadata = DownloadExportMetadata(
            song: copy.song, album: nil,
            lyrics: [
                StructuredLyrics(
                    synced: true,
                    line: [
                        LyricLine(start: 0, value: "First line"), LyricLine(start: 1000, value: "次の行"),
                    ])
            ], artwork: nil)
        XCTAssertEqual(metadata.artist, "Track artist")
        XCTAssertEqual(metadata.albumArtist, "Album artist")
        XCTAssertEqual(metadata.lyrics, "First line\n次の行")
        XCTAssertNil(metadata.year)
        XCTAssertNil(metadata.artwork)
    }

    func testRichServerCreditsAndDiscTotals() throws {
        let song = try JSONDecoder().decode(
            Song.self,
            from: Data(
                #"{"id":"1","title":"Track","artist":"Legacy","displayArtist":"Singer & Guest","genres":[{"name":"Jazz"},{"name":"Soul"}],"displayComposer":"Composer","bpm":120,"comment":"Notes","musicBrainzId":"mb-id","isrc":["CODE"],"replayGain":{"trackGain":-4.2},"discNumber":2,"track":1}"#
                    .utf8))
        let album = try JSONDecoder().decode(
            Album.self,
            from: Data(
                #"{"id":"a","name":"Album","songCount":3,"song":[{"id":"x","title":"X","track":1,"discNumber":1},{"id":"1","title":"Track","track":1,"discNumber":2},{"id":"2","title":"Y","track":2,"discNumber":2}]}"#
                    .utf8))
        let metadata = DownloadExportMetadata(song: song, album: album, lyrics: [], artwork: nil)
        XCTAssertEqual(metadata.artist, "Singer & Guest")
        XCTAssertEqual(metadata.genre, "Jazz; Soul")
        XCTAssertEqual(metadata.composer, "Composer")
        XCTAssertEqual(metadata.bpm, 120)
        XCTAssertEqual(metadata.trackCount, 2)
        XCTAssertEqual(metadata.discCount, 2)
        XCTAssertTrue(metadata.extraTags.contains { $0.key == "MUSICBRAINZ_TRACKID" && $0.value == "mb-id" })
        XCTAssertTrue(metadata.extraTags.contains { $0.key == "REPLAYGAIN_TRACK_GAIN" && $0.value == "-4.20000000 dB" })
    }

    func testMetadataCannotCreateHiddenFilesOrPaths() throws {
        let copies = [
            try copy(title: "../Song\\?\u{0}<>\n", artist: "../AC/DC:"),
            try copy(title: " ... / ", artist: " ... / "),
        ]
        let names = DownloadExportNames.filenames(for: copies)
        for name in names {
            XCTAssertEqual(URL(fileURLWithPath: name).lastPathComponent, name)
            XCTAssertFalse(name.hasPrefix("."))
            XCTAssertNil(name.rangeOfCharacter(from: .controlCharacters))
            XCTAssertNil(name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:*?\"<>|")))
        }
        XCTAssertTrue(names[1].contains("Untitled"))
    }

    func testBulkExportDisambiguatesCaseAndUnicodeEquivalentNames() throws {
        let copies = try ["Café", "Cafe\u{301}", "CAFÉ", "Café (2)"].map { try copy(title: $0) }
        let names = DownloadExportNames.filenames(for: copies)
        let normalized = names.map { $0.precomposedStringWithCanonicalMapping.lowercased() }
        XCTAssertEqual(Set(normalized).count, copies.count)
        XCTAssertTrue(names.allSatisfy { $0.hasSuffix(".m4a") })
    }

    func testLongUnicodeNamesStayWithinFilesystemLimit() throws {
        let copies = [try copy(title: String(repeating: "🎵曲", count: 200), artist: "音楽")]
        let name = try XCTUnwrap(DownloadExportNames.filenames(for: copies).first)
        XCTAssertLessThanOrEqual(name.utf8.count, 255)
        XCTAssertTrue(name.hasPrefix("音楽 - "))
        XCTAssertTrue(name.hasSuffix(".m4a"))
    }
}
