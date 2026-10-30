import Foundation

public struct DownloadExportMetadata: Sendable {
    public let title: String
    public let artist: String
    public let albumArtist: String
    public let album: String?
    public let year: Int?
    public let genre: String?
    public let track: Int?
    public let trackCount: Int?
    public let disc: Int?
    public let lyrics: String?
    public let timedLyrics: StructuredLyrics?
    public let artwork: Data?

    public init(song: Song, album: Album?, lyrics: [StructuredLyrics], artwork: Data?) {
        title = ArtistCredit.nonempty(song.title) ?? "Untitled"
        artist = ArtistCredit.nonempty(song.artist) ?? song.artistName
        albumArtist = song.artistName
        self.album = ArtistCredit.nonempty(song.album) ?? album?.name
        year = song.year ?? album?.year
        genre = ArtistCredit.nonempty(song.genre) ?? album?.genre
        track = song.track
        // Album song counts span multiple discs and aren't necessarily the track count of this disc.
        trackCount =
            (song.discNumber ?? 1) == 1 && !(album?.songs.contains { ($0.discNumber ?? 1) > 1 } ?? false)
            ? album?.songCount : nil
        disc = song.discNumber
        let available = lyrics.filter(\.hasContent)
        timedLyrics = available.first(where: \.synced)
        let text = (timedLyrics ?? available.first)?.line.map(\.value).joined(separator: "\n")
        self.lyrics = ArtistCredit.nonempty(text)
        self.artwork = artwork
    }

    var timedLines: [(text: String, milliseconds: UInt32)] {
        guard let timedLyrics, timedLyrics.offset?.isFinite != false else { return [] }
        return timedLyrics.line.enumerated().compactMap { index, line -> (index: Int, text: String, time: UInt32)? in
            guard line.start?.isFinite == true,
                let time = timedLyrics.seekTime(for: index).map({ ($0 * 1000).rounded() }),
                time.isFinite, time >= 0, time <= Double(UInt32.max)
            else { return nil }
            return (index, line.value, UInt32(time))
        }
        .sorted { $0.time == $1.time ? $0.index < $1.index : $0.time < $1.time }
        .map { ($0.text, $0.time) }
    }

    var lrcLyrics: String? {
        let lines = timedLines
        guard !lines.isEmpty else { return nil }
        return lines.map { line in
            let time = line.milliseconds
            return String(format: "[%02d:%02d.%03d]", Int(time / 60_000), Int(time / 1000 % 60), Int(time % 1000))
                + line.text
        }.joined(separator: "\n")
    }
}
