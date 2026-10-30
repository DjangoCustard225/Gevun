import Foundation
import XCTest
@testable import GevunCore

final class TaggedMP3ExportTests: XCTestCase {
    private let audio = Data([0xFF, 0xFB, 0x90, 0x64]) + Data(repeating: 0x55, count: 2_100_000)

    private func metadata() throws -> DownloadExportMetadata {
        let song = try JSONDecoder().decode(
            Song.self,
            from: Data(
                #"{"id":"1","title":"曲 🎵","artist":"Singer","albumArtist":"Band","album":"Record","track":2,"discNumber":1,"year":2026,"genre":"Jazz"}"#
                    .utf8))
        return DownloadExportMetadata(
            song: song, album: nil,
            lyrics: [
                StructuredLyrics(
                    synced: true, offset: 250,
                    line: [
                        LyricLine(start: 1000, value: "First line"), LyricLine(start: 2500, value: "次の行"),
                    ])
            ], artwork: Data([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0, 0xFF, 0xD9]))
    }

    private func export(_ original: Data, metadata supplied: DownloadExportMetadata? = nil) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp3")
        let destination = directory.appendingPathComponent("export.mp3")
        try original.write(to: source)
        try await TaggedMP3Export.write(from: source, to: destination, metadata: supplied ?? metadata())
        XCTAssertEqual(try Data(contentsOf: source), original)
        let exported = try Data(contentsOf: destination)
        XCTAssertEqual(Data(exported.suffix(audio.count)), audio, "All audio bytes must remain unchanged")
        return exported
    }

    private func size(_ count: Int) -> Data {
        Data((0..<4).reversed().map { UInt8((count >> ($0 * 7)) & 127) })
    }

    private func frame(_ id: String, value: Data) -> Data {
        // Small frame sizes have the same representation in ID3v2.3 and ID3v2.4.
        precondition(value.count < 128)
        return Data(id.utf8) + Data([0, 0, 0, UInt8(value.count), 0, 0]) + value
    }

    private func tag(version: UInt8, flags: UInt8 = 0, body: Data) -> Data {
        let header = Data("ID3".utf8) + Data([version, 0, flags]) + size(body.count)
        let footer = flags & 0x10 != 0 ? Data("3DI".utf8) + header.dropFirst(3) : Data()
        return header + body + footer
    }

    func testRichTagsKeepExistingUserTextAndAddDistinctDescriptors() async throws {
        let song = try JSONDecoder().decode(
            Song.self,
            from: Data(
                #"{"id":"1","title":"Track","displayComposer":"Composer","bpm":120,"musicBrainzId":"new-id","replayGain":{"trackGain":-3,"albumGain":-2}}"#
                    .utf8))
        let metadata = DownloadExportMetadata(song: song, album: nil, lyrics: [], artwork: nil)
        let existing = frame(
            "TXXX", value: Data([3]) + Data("MusicBrainz Track Id".utf8) + Data([0]) + Data("original-id".utf8))
        let result = try await export(tag(version: 4, body: existing) + audio, metadata: metadata)
        XCTAssertNotNil(result.range(of: existing))
        XCTAssertNil(result.range(of: Data("new-id".utf8)))
        for value in ["TCOM", "TBPM", "replaygain_track_gain", "replaygain_album_gain"] {
            XCTAssertNotNil(result.range(of: Data(value.utf8)))
        }
    }

    func testMissingFrontCoverDoesNotReplaceBackCover() async throws {
        let back = frame("APIC", value: Data([3]) + Data("image/jpeg".utf8) + Data([0, 4, 0, 1, 2, 3]))
        let result = try await export(tag(version: 4, body: back) + audio)
        XCTAssertNotNil(result.range(of: back))
        var count = 0
        var offset = result.startIndex
        while let range = result.range(of: Data("APIC".utf8), in: offset..<result.endIndex) {
            count += 1; offset = range.upperBound
        }
        XCTAssertEqual(count, 2)
    }

    func testUntaggedAudioGetsStandardTagsAndBothLyricFrames() async throws {
        let exported = try await export(audio)
        XCTAssertEqual(exported.prefix(4), Data([0x49, 0x44, 0x33, 3]))
        for id in ["TIT2", "TPE1", "TPE2", "TALB", "TRCK", "TPOS", "TYER", "TCON", "APIC", "USLT", "SYLT"] {
            XCTAssertNotNil(exported.range(of: Data(id.utf8)), "Missing \(id)")
        }
    }

    func testExistingV23AndV24FramesRemainUnchangedAndAreNotDuplicated() async throws {
        for version: UInt8 in [3, 4] {
            let title = frame("TIT2", value: Data([0]) + Data("Server title".utf8))
            let custom = frame("TXXX", value: Data([0]) + Data("Custom\0Keep me".utf8))
            let unknown = frame("ZZZZ", value: Data([1, 2, 3, 4, 5]))
            let original = tag(version: version, body: title + custom + unknown + Data(repeating: 0, count: 1024))
            let exported = try await export(original + audio)
            XCTAssertEqual(exported[3], version)
            for bytes in [title, custom, unknown] { XCTAssertNotNil(exported.range(of: bytes)) }
            let titleEnd = try XCTUnwrap(exported.range(of: Data("TIT2".utf8))).upperBound
            XCTAssertNil(exported.range(of: Data("TIT2".utf8), in: titleEnd..<exported.count))
        }
    }

    func testV23UnsynchronisationRetainsBinaryFrameContents() async throws {
        let binary = frame("PRIV", value: Data([0x41, 0xFF, 0xE0, 0x42]))
        let escaped = Data(binary.dropLast(2)) + Data([0, 0xE0, 0x42])
        let exported = try await export(tag(version: 3, flags: 0x80, body: escaped) + audio)
        XCTAssertEqual(exported[5] & 0x80, 0x80)
        XCTAssertNotNil(exported.range(of: escaped))
    }

    func testV24FooterAndExtendedHeaderDoNotGetCopiedIntoAudio() async throws {
        let custom = frame("PRIV", value: Data("keep\0private data".utf8))
        let extended = Data([0, 0, 0, 6, 1, 0])
        let exported = try await export(tag(version: 4, flags: 0x50, body: extended + custom) + audio)
        XCTAssertEqual(exported[5] & 0x50, 0)
        XCTAssertNotNil(exported.range(of: custom))
        let tagLength = exported[6..<10].reduce(0) { ($0 << 7) | Int($1) }
        XCTAssertEqual(exported.count, 10 + tagLength + audio.count)
    }

    func testCorruptTagFailsWithoutCreatingAnExportOrChangingSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp3")
        let destination = directory.appendingPathComponent("export.mp3")
        let corrupt = tag(version: 4, body: Data("TIT2".utf8) + Data([0, 0, 100, 0, 0, 0]))
        try corrupt.write(to: source)
        do {
            try await TaggedMP3Export.write(from: source, to: destination, metadata: metadata())
            XCTFail("Corrupt frames must not be silently discarded")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: source), corrupt)
        }
    }

    func testCancellationDoesNotCreateAnExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp3")
        let destination = directory.appendingPathComponent("export.mp3")
        try audio.write(to: source)
        let metadata = try metadata()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await TaggedMP3Export.write(from: source, to: destination, metadata: metadata)
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: source), audio)
        }
    }
}
