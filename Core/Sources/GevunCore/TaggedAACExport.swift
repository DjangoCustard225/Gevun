#if canImport(AVFoundation)
    import AVFoundation
    import Foundation

    /// Repackage compressed AAC packets without decoding or encoding the audio again.
    @available(iOS 26.0, macOS 26.0, *)
    public enum TaggedAACExport {
        public static func write(from source: URL, to destination: URL, metadata: DownloadExportMetadata) async throws {
            try Task.checkCancellation()
            guard source.standardizedFileURL != destination.standardizedFileURL else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            let asset = AVURLAsset(url: source)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first,
                let format = try await track.load(.formatDescriptions).first
            else { throw CocoaError(.fileReadCorruptFile) }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            guard reader.canAdd(output), writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
            var existing = try await asset.load(.metadata)
            for format in try await asset.load(.availableMetadataFormats) {
                let known = Set(existing.compactMap(\.identifier))
                let additional = try await asset.loadMetadata(for: format)
                existing.append(
                    contentsOf: additional.filter { item in
                        item.identifier.map { !known.contains($0) } ?? false
                    })
            }
            let expected = items(metadata, existing: existing)
            writer.metadata = expected
            let provider = reader.outputProvider(for: output)
            let receiver = writer.inputReceiver(for: input)
            do {
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    try writer.start()
                    writer.startSession(atSourceTime: .zero)
                    try reader.start()
                    while let sample = try await provider.next() {
                        try Task.checkCancellation()
                        try await receiver.append(sample)
                    }
                    receiver.finish()
                    await writer.finishWriting()
                    try Task.checkCancellation()
                    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                    let exported = AVURLAsset(url: destination)
                    guard try await exported.load(.isPlayable) else { throw CocoaError(.fileWriteUnknown) }
                    let tags = try await exported.load(.metadata)
                    let verified: Set<AVMetadataIdentifier> = [
                        .iTunesMetadataSongName, .iTunesMetadataArtist,
                        .iTunesMetadataAlbumArtist, .iTunesMetadataAlbum, .iTunesMetadataReleaseDate,
                        .iTunesMetadataUserGenre, .iTunesMetadataLyrics, .iTunesMetadataCoverArt,
                        .iTunesMetadataTrackNumber, .iTunesMetadataDiscNumber, .iTunesMetadataComposer,
                        .iTunesMetadataUserComment, .iTunesMetadataBeatsPerMin,
                    ]
                    for item in expected where item.identifier.map(verified.contains) == true {
                        var matched = false
                        for actual in tags where actual.identifier == item.identifier {
                            if let value = try await item.load(.stringValue),
                                value == (try await actual.load(.stringValue))
                            {
                                matched = true; break
                            }
                            if let value = try await item.load(.dataValue),
                                value == (try await actual.load(.dataValue))
                            {
                                matched = true; break
                            }
                            if let value = try await item.load(.numberValue),
                                value == (try await actual.load(.numberValue))
                            {
                                matched = true; break
                            }
                        }
                        guard matched else { throw CocoaError(.fileWriteUnknown) }
                    }
                } onCancel: {
                    reader.cancelReading()
                    writer.cancelWriting()
                }
            } catch {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }

        private static func items(_ metadata: DownloadExportMetadata, existing: [AVMetadataItem]) -> [AVMetadataItem] {
            var items = existing
            func add(_ identifier: AVMetadataIdentifier, value: any NSCopying & NSObjectProtocol, type: CFString) {
                guard !items.contains(where: { $0.identifier == identifier }) else { return }
                let item = AVMutableMetadataItem()
                item.identifier = identifier
                item.value = value
                item.dataType = type as String
                items.append(item)
            }
            func text(_ identifier: AVMetadataIdentifier, _ value: String?) {
                guard let value, !value.isEmpty else { return }
                add(identifier, value: value as NSString, type: kCMMetadataBaseDataType_UTF8)
            }
            text(.iTunesMetadataSongName, metadata.title)
            text(.iTunesMetadataArtist, metadata.artist)
            text(.iTunesMetadataAlbumArtist, metadata.albumArtist)
            text(.iTunesMetadataAlbum, metadata.album)
            text(.iTunesMetadataReleaseDate, metadata.year.map(String.init))
            text(.iTunesMetadataUserGenre, metadata.genre)
            text(.iTunesMetadataLyrics, metadata.lyrics)
            text(.iTunesMetadataComposer, metadata.composer)
            text(.iTunesMetadataUserComment, metadata.comment)
            if let bpm = metadata.bpm {
                add(
                    .iTunesMetadataBeatsPerMin, value: NSNumber(value: UInt16(clamping: bpm)),
                    type: kCMMetadataBaseDataType_UInt16)
            }
            if let artwork = metadata.artwork {
                let type =
                    artwork.starts(with: [0x89, 0x50, 0x4E, 0x47])
                    ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG
                add(.iTunesMetadataCoverArt, value: artwork as NSData, type: type)
            }
            if let track = metadata.track, track > 0 {
                add(
                    .iTunesMetadataTrackNumber,
                    value: number(track, total: metadata.trackCount, trailingPadding: true) as NSData,
                    type: kCMMetadataBaseDataType_RawData)
            }
            if let disc = metadata.disc, disc > 0 {
                add(
                    .iTunesMetadataDiscNumber,
                    value: number(disc, total: metadata.discCount, trailingPadding: false) as NSData,
                    type: kCMMetadataBaseDataType_RawData)
            }
            return items
        }

        private static func number(_ value: Int, total: Int?, trailingPadding: Bool) -> Data {
            let value = UInt16(clamping: value)
            let total = UInt16(clamping: total ?? 0)
            var data = Data([0, 0, UInt8(value >> 8), UInt8(value & 255), UInt8(total >> 8), UInt8(total & 255)])
            if trailingPadding { data.append(contentsOf: [0, 0]) }
            return data
        }
    }
#endif
