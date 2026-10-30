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
    public let composer: String?
    public let comment: String?
    public let bpm: Int?
    public let discCount: Int?
    public let extraTags: [(key: String, value: String)]

    public init(song: Song, album: Album?, lyrics: [StructuredLyrics], artwork: Data?) {
        title = ArtistCredit.nonempty(song.title) ?? "Untitled"
        artist =
            ArtistCredit.display(song.displayArtist, credits: song.artists, fallback: song.artist) ?? song.artistName
        albumArtist = song.artistName
        self.album = ArtistCredit.nonempty(song.album) ?? album?.name
        year = song.year ?? album?.year
        genre =
            ArtistCredit.nonempty(song.genres?.map(\.name).joined(separator: "; ")) ?? ArtistCredit.nonempty(song.genre)
            ?? album?.genre
        track = song.track
        let completeAlbum = album.flatMap { value -> [Song]? in
            guard let count = value.songCount, count > 0, value.songs.count == count else { return nil }
            return value.songs
        }
        if let completeAlbum {
            let discTracks = completeAlbum.filter { ($0.discNumber ?? 1) == (song.discNumber ?? 1) }
            let numbers = discTracks.compactMap(\.track)
            trackCount =
                numbers.count == discTracks.count && Set(numbers) == Set(1...max(1, discTracks.count))
                ? discTracks.count : nil
            discCount = completeAlbum.map { $0.discNumber ?? 1 }.max()
        } else {
            trackCount = nil
            discCount = nil
        }
        composer = ArtistCredit.nonempty(song.displayComposer)
        comment = ArtistCredit.nonempty(song.comment)
        bpm = song.bpm.flatMap { $0 > 0 ? $0 : nil }
        var extras: [(key: String, value: String)] = []
        if let id = ArtistCredit.nonempty(song.musicBrainzId) { extras.append(("MUSICBRAINZ_TRACKID", id)) }
        for isrc in song.isrc ?? [] { if let value = ArtistCredit.nonempty(isrc) { extras.append(("ISRC", value)) } }
        if let gain = song.replayGain {
            for (key, value) in [
                ("REPLAYGAIN_TRACK_GAIN", gain.trackGain), ("REPLAYGAIN_ALBUM_GAIN", gain.albumGain),
                ("REPLAYGAIN_TRACK_PEAK", gain.trackPeak), ("REPLAYGAIN_ALBUM_PEAK", gain.albumPeak),
            ] {
                if let value, value.isFinite {
                    extras.append(
                        (
                            key,
                            String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
                                + (key.hasSuffix("GAIN") ? " dB" : "")
                        ))
                }
            }
        }
        extraTags = extras
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
