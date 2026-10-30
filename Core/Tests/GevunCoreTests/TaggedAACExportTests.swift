#if canImport(AVFoundation)
    import AVFoundation
    import Foundation
    import XCTest
    import GevunCore

    final class TaggedAACExportTests: XCTestCase {
        func testADTSExportWritesTagsWithoutReencodingOrChangingDownload() async throws {
            guard #available(macOS 26.0, iOS 26.0, *) else { throw XCTSkip("Requires native media APIs") }
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<4 { root.deleteLastPathComponent() }
            let probes = try PropertyListDecoder().decode(
                [String: Data].self,
                from: Data(contentsOf: root.appendingPathComponent("Gevun/Resources/DownloadProbes.plist")))
            let audio = try XCTUnwrap(probes["aac"])
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = directory.appendingPathComponent("source.aac")
            let destination = directory.appendingPathComponent("export.m4a")
            try audio.write(to: source)
            let song = try JSONDecoder().decode(
                Song.self,
                from: Data(
                    #"{"id":"1","title":"Title 曲","artist":"Singer","albumArtist":"The Band","album":"Record","track":2,"discNumber":1,"year":2026,"genre":"Jazz"}"#
                        .utf8))
            let lyrics = [StructuredLyrics(line: [LyricLine(value: "A lyric line")])]
            let artwork = try XCTUnwrap(
                Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHFEAAAAASUVORK5CYII="))
            let metadata = DownloadExportMetadata(song: song, album: nil, lyrics: lyrics, artwork: artwork)
            try await TaggedAACExport.write(from: source, to: destination, metadata: metadata)
            let tags = try await AVURLAsset(url: destination).load(.metadata)
            for (identifier, expected) in [
                (AVMetadataIdentifier.iTunesMetadataSongName, "Title 曲"),
                (.iTunesMetadataArtist, "Singer"), (.iTunesMetadataAlbumArtist, "The Band"),
                (.iTunesMetadataAlbum, "Record"), (.iTunesMetadataLyrics, "A lyric line"),
                (.iTunesMetadataReleaseDate, "2026"), (.iTunesMetadataUserGenre, "Jazz"),
            ] {
                let item = try XCTUnwrap(tags.first { $0.identifier == identifier })
                let value = try await item.load(.stringValue)
                XCTAssertEqual(value, expected)
            }
            let cover = try XCTUnwrap(tags.first { $0.identifier == .iTunesMetadataCoverArt })
            let coverData = try await cover.load(.dataValue)
            XCTAssertEqual(coverData, artwork)
            XCTAssertNotNil(tags.first { $0.identifier == .iTunesMetadataTrackNumber })
            XCTAssertNotNil(tags.first { $0.identifier == .iTunesMetadataDiscNumber })
            let originalPackets = try await packets(in: source)
            let exportedPackets = try await packets(in: destination)
            XCTAssertFalse(originalPackets.isEmpty)
            XCTAssertEqual(exportedPackets, originalPackets, "AAC packet payloads must remain unchanged")
            XCTAssertEqual(try Data(contentsOf: source), audio, "The saved download must remain untouched")
        }

        @available(macOS 26.0, iOS 26.0, *)
        private func packets(in url: URL) async throws -> Data {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let track = try XCTUnwrap(tracks.first)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let provider = reader.outputProvider(for: output)
            try reader.start()
            var data = Data()
            while let sample = try await provider.next() {
                let bytes: Data = try sample.withUnsafeSampleBuffer { buffer in
                    let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(buffer))
                    var bytes = Data(count: CMBlockBufferGetDataLength(block))
                    let count = bytes.count
                    let status = bytes.withUnsafeMutableBytes {
                        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: $0.baseAddress!)
                    }
                    XCTAssertEqual(status, noErr)
                    return bytes
                }
                data.append(bytes)
            }
            return data
        }
    }
#endif
