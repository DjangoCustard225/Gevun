import Foundation
import XCTest
@testable import GevunCore

final class TaggedFLACExportTests: XCTestCase {
    private let audio = Data([0xFF, 0xF8, 0x19, 0x18]) + Data(repeating: 0x55, count: 1_100_000)

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
            ], artwork: Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    private func comments(_ entries: [String]) -> Data {
        func count(_ value: Int) -> Data { Data((0..<4).map { UInt8(value >> ($0 * 8) & 255) }) }
        let vendor = Data("Original encoder".utf8)
        var result = count(vendor.count) + vendor + count(entries.count)
        for entry in entries {
            let data = Data(entry.utf8)
            result.append(count(data.count) + data)
        }
        return result
    }

    private func file(_ blocks: [(UInt8, Data)]) -> Data {
        let blocks = [(UInt8(0), Data(repeating: 0x55, count: 34))] + blocks
        var result = Data("fLaC".utf8)
        for (index, block) in blocks.enumerated() {
            result.append(block.0 | (index == blocks.count - 1 ? 0x80 : 0))
            result.append(contentsOf: [
                UInt8(block.1.count >> 16), UInt8(block.1.count >> 8 & 255), UInt8(block.1.count & 255),
            ])
            result.append(block.1)
        }
        return result + audio
    }

    private func exported(_ original: Data, metadata supplied: DownloadExportMetadata? = nil) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.flac")
        let destination = directory.appendingPathComponent("export.flac")
        try original.write(to: source)
        try await TaggedFLACExport.write(from: source, to: destination, metadata: supplied ?? metadata())
        XCTAssertEqual(try Data(contentsOf: source), original)
        let result = try Data(contentsOf: destination)
        XCTAssertEqual(Data(result.suffix(audio.count)), audio)
        return result
    }

    private func blocks(in file: Data) throws -> [(type: UInt8, data: Data)] {
        var offset = 4
        var blocks: [(UInt8, Data)] = []
        while offset < file.count {
            let type = file[offset]
            let size = Int(file[offset + 1]) << 16 | Int(file[offset + 2]) << 8 | Int(file[offset + 3])
            guard offset + 4 + size <= file.count else { throw CocoaError(.fileReadCorruptFile) }
            blocks.append((type & 127, Data(file[offset + 4..<offset + 4 + size])))
            offset += 4 + size
            if type & 128 != 0 { return blocks }
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    func testRichTagsSupplementButNeverOverwriteExistingValues() async throws {
        let song = try JSONDecoder().decode(
            Song.self,
            from: Data(
                #"{"id":"1","title":"Track","displayComposer":"New composer","bpm":90,"comment":"Notes","musicBrainzId":"new-id","replayGain":{"trackGain":-2}}"#
                    .utf8))
        let metadata = DownloadExportMetadata(song: song, album: nil, lyrics: [], artwork: nil)
        let result = try await exported(
            file([(4, comments(["COMPOSER=Original composer", "MUSICBRAINZ_TRACKID=original-id"]))]), metadata: metadata
        )
        let tags = try XCTUnwrap(try blocks(in: result).first { $0.type == 4 }?.data)
        for value in [
            "COMPOSER=Original composer", "MUSICBRAINZ_TRACKID=original-id", "BPM=90", "COMMENT=Notes",
            "REPLAYGAIN_TRACK_GAIN=-2.00000000 dB",
        ] {
            XCTAssertNotNil(tags.range(of: Data(value.utf8)))
        }
        XCTAssertNil(tags.range(of: Data("New composer".utf8)))
    }

    func testMissingFrontCoverIsAddedAlongsideExistingBackCover() async throws {
        let back = Data([0, 0, 0, 4]) + Data("back artwork".utf8)
        let result = try await exported(file([(6, back)]))
        let pictures = try blocks(in: result).filter { $0.type == 6 }
        XCTAssertEqual(pictures.count, 2)
        XCTAssertTrue(pictures.contains { $0.data == back })
        XCTAssertTrue(pictures.contains { $0.data.prefix(4) == Data([0, 0, 0, 3]) })
    }

    func testMissingCommentsArtworkAndLyricsAreAddedWithoutTouchingAudio() async throws {
        let result = try await exported(file([]))
        let blocks = try blocks(in: result)
        XCTAssertEqual(blocks.map(\.type), [0, 4, 6])
        let tags = try XCTUnwrap(blocks.first { $0.type == 4 }?.data)
        for value in [
            "TITLE=曲 🎵", "ARTIST=Singer", "ALBUMARTIST=Band", "TRACKNUMBER=2", "DISCNUMBER=1",
            "LYRICS=[00:00.750]First line\n[00:02.250]次の行", "UNSYNCEDLYRICS=First line\n次の行",
        ] {
            XCTAssertNotNil(tags.range(of: Data(value.utf8)), "Missing \(value)")
        }
    }

    func testExistingTagsVendorPicturesAndUnknownBlocksArePreserved() async throws {
        let entries = [
            "title=Original title", "ARTIST=One", "ARTIST=Two", "REPLAYGAIN_TRACK_GAIN=-3.5 dB",
            "MUSICBRAINZ_TRACKID=keep", "CUSTOM=unchanged",
        ]
        let picture = Data("Existing picture payload".utf8)
        let application = Data("APP1opaque data".utf8)
        let original = file([
            (4, comments(entries)), (2, application), (6, picture), (1, Data(repeating: 0, count: 128)),
        ])
        let result = try await exported(original)
        let before = try blocks(in: original)
        let after = try blocks(in: result)
        for block in before where block.type != 4 {
            XCTAssertTrue(after.contains { $0.type == block.type && $0.data == block.data })
        }
        let tags = try XCTUnwrap(after.first { $0.type == 4 }?.data)
        for value in entries + ["Original encoder"] { XCTAssertNotNil(tags.range(of: Data(value.utf8))) }
        XCTAssertNil(tags.range(of: Data("TITLE=曲".utf8)))
        XCTAssertEqual(after.filter { $0.type == 6 }.count, 1)
    }

    func testCompleteMetadataCanExportByteIdentically() async throws {
        let keys = [
            "TITLE", "ARTIST", "ALBUMARTIST", "ALBUM", "DATE", "GENRE", "TRACKNUMBER", "DISCNUMBER",
            "LYRICS", "UNSYNCEDLYRICS",
        ]
        let original = file([(4, comments(keys.map { "\($0)=Original" })), (6, Data("Original artwork".utf8))])
        let result = try await exported(original)
        XCTAssertEqual(result, original)
    }

    func testAliasesAreNotOverriddenByConflictingLibraryValues() async throws {
        let result = try await exported(file([(4, comments(["album artist=Original Band", "year=1999"]))]))
        let tags = try XCTUnwrap(try blocks(in: result).first { $0.type == 4 }?.data)
        XCTAssertNotNil(tags.range(of: Data("album artist=Original Band".utf8)))
        XCTAssertNotNil(tags.range(of: Data("year=1999".utf8)))
        XCTAssertNil(tags.range(of: Data("ALBUMARTIST=Band".utf8)))
        XCTAssertNil(tags.range(of: Data("DATE=2026".utf8)))
    }

    func testMalformedMetadataFailsWithoutCreatingAnExport() async throws {
        let malformed = [
            Data("not a FLAC".utf8), file([(4, Data([255, 255, 255, 127]))]),
            file([(4, comments(["TITLE=One"])), (4, comments(["TITLE=Two"]))]),
        ]
        for original in malformed {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = directory.appendingPathComponent("source.flac")
            let destination = directory.appendingPathComponent("export.flac")
            try original.write(to: source)
            do {
                try await TaggedFLACExport.write(from: source, to: destination, metadata: metadata())
                XCTFail("Malformed metadata must not be discarded")
            } catch {
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
                XCTAssertEqual(try Data(contentsOf: source), original)
            }
        }
    }

    func testExistingDestinationIsNeverOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.flac")
        let destination = directory.appendingPathComponent("export.flac")
        try file([]).write(to: source)
        let existing = Data("Keep this file".utf8)
        try existing.write(to: destination)
        do {
            try await TaggedFLACExport.write(from: source, to: destination, metadata: metadata())
            XCTFail("Existing destinations must be protected")
        } catch {
            XCTAssertEqual(try Data(contentsOf: destination), existing)
        }
    }
}
