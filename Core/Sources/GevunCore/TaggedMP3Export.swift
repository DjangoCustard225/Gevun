import Foundation

/// Fill missing ID3 frames in an exported copy. Existing frames and MPEG audio are retained.
public enum TaggedMP3Export {
    public static func write(from source: URL, to destination: URL, metadata: DownloadExportMetadata) async throws {
        try Task.checkCancellation()
        guard source.standardizedFileURL != destination.standardizedFileURL else { throw MP3ExportError.sameFile }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var tag = try ID3Tag.read(from: input)
        try tag.addMetadata(metadata)
        let header = try tag.encoded()
        try await AudioExportFile.write(to: destination, header: header, copying: input)
    }
}

private extension ID3Tag {
    mutating func addMetadata(_ metadata: DownloadExportMetadata) throws {
        try addText("TIT2", metadata.title)
        try addText("TPE1", metadata.artist)
        try addText("TPE2", metadata.albumArtist)
        try addText("TALB", metadata.album)
        try addText(version == 4 ? "TDRC" : "TYER", metadata.year.map(String.init))
        try addText("TCON", metadata.genre)
        try addText("TCOM", metadata.composer)
        try addText("TBPM", metadata.bpm.map(String.init))
        if let comment = metadata.comment { try addFrame("COMM", payload: lyricsHeader() + text(comment)) }
        try addText("TSRC", metadata.extraTags.first { $0.key == "ISRC" }?.value)
        for tag in metadata.extraTags where tag.key != "ISRC" {
            let descriptor = tag.key == "MUSICBRAINZ_TRACKID" ? "MusicBrainz Track Id" : tag.key.lowercased()
            try addFrame(
                "TXXX", payload: Data([textEncoding]) + text(descriptor) + textTerminator + text(tag.value),
                descriptor: descriptor)
        }
        if let track = metadata.track, track > 0 {
            let count = metadata.trackCount.flatMap { $0 > 0 ? "/\($0)" : nil } ?? ""
            try addText("TRCK", "\(track)\(count)")
        }
        if let disc = metadata.disc, disc > 0 {
            try addText("TPOS", String(disc) + (metadata.discCount.map { "/\($0)" } ?? ""))
        }
        if let lyrics = metadata.lyrics {
            try addFrame("USLT", payload: lyricsHeader() + text(lyrics))
        }
        try addTimedLyrics(metadata.timedLines)
        if let artwork = metadata.artwork {
            let mime = artwork.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
            let header = Data([textEncoding]) + Data(mime.utf8) + Data([0, 3]) + text("") + textTerminator
            try addFrame("APIC", payload: header + artwork)
        }
    }

    func lyricsHeader(synchronized: Bool = false) -> Data {
        var header = Data([textEncoding]) + Data("und".utf8)
        if synchronized { header.append(contentsOf: [2, 1]) }  // Millisecond timestamps, lyric content.
        return header + text("") + textTerminator
    }

    mutating func addTimedLyrics(_ lines: [(text: String, milliseconds: UInt32)]) throws {
        guard !lines.isEmpty else { return }
        var data = lyricsHeader(synchronized: true)
        for (index, line) in lines.enumerated() {
            data.append(text((index == 0 ? "" : "\n") + line.text) + textTerminator)
            data.append(contentsOf: Self.encodedInteger(Int(line.milliseconds), synchsafe: false))
        }
        try addFrame("SYLT", payload: data)
    }
}
