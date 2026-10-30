import Foundation

public enum DownloadFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, opus, mp3, aac
    // Keep decoding older saved Opus downloads without offering new ones.
    public static let allCases: [Self] = [.original, .mp3, .aac]
    public var id: Self { self }
    public var title: String { self == .original ? "Original" : rawValue == "opus" ? "Opus" : rawValue.uppercased() }
    public var bitrates: [Int] {
        switch self {
        case .original: []
        case .opus: [64, 96, 128, 160, 192, 256]
        case .mp3: [128, 192, 256, 320]
        case .aac: [96, 128, 192, 256]
        }
    }
    public var defaultBitrate: Int {
        switch self {
        case .original: 0
        case .opus: 128
        case .mp3: 320
        case .aac: 256
        }
    }
}

public struct DownloadQuality: Codable, Equatable, Sendable {
    public let format: DownloadFormat
    public let bitrate: Int
    public init(format: DownloadFormat = .original, bitrate: Int? = nil) {
        self.format = format
        let value = bitrate ?? format.defaultBitrate
        self.bitrate = format.bitrates.contains(value) ? value : format.defaultBitrate
    }
    public var title: String { format == .original ? "Original" : "\(format.title) · \(bitrate) kbps" }
}

public struct DownloadKey: Codable, Hashable, Sendable {
    public let namespace: String
    public let songID: String
    public init(namespace: String, songID: String) {
        self.namespace = namespace
        self.songID = songID
    }
    public static func namespace(for instance: Instance) -> String {
        var parts = URLComponents(url: instance.url, resolvingAgainstBaseURL: false)
        let host = parts?.host?.lowercased()
        parts?.host = host
        let identity = [instance.id.uuidString, parts?.string ?? instance.url.absoluteString, instance.username]
        return SubsonicToken.md5(Array(identity.joined(separator: "\u{0}").utf8))
    }
}

public struct OfflineSong: Codable, Identifiable, Sendable {
    public var id: DownloadKey { key }
    public let key: DownloadKey
    public let song: Song
    public let quality: DownloadQuality
    public let filename: String
    public let bytes: Int64
    public let savedAt: Date
    public init(key: DownloadKey, song: Song, quality: DownloadQuality, filename: String, bytes: Int64) {
        self.key = key
        self.song = song
        self.quality = quality
        self.filename = filename
        self.bytes = bytes
        savedAt = Date()
    }
}

public struct DownloadJob: Codable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable { case queued, waiting, transferring, validating, failed }
    public let id: UUID
    public let key: DownloadKey
    public let song: Song
    public let quality: DownloadQuality
    public var state: State = .queued
    public var error: String?
    public init(key: DownloadKey, song: Song, quality: DownloadQuality) {
        id = UUID()
        self.key = key
        self.song = song
        self.quality = quality
    }
}

/// A snapshot of one download selection, scoped to its server and requested quality.
public struct DownloadBatchStatus: Sendable {
    public let jobs: [DownloadJob]
    public let savedCount: Int
    public let totalCount: Int
    public var isComplete: Bool { totalCount > 0 && savedCount == totalCount }

    public init(library: DownloadLibrary, songs: [Song], namespace: String, quality: DownloadQuality) {
        let selectedIDs = Set(songs.map(\.id))
        totalCount = selectedIDs.count
        jobs = library.jobs.filter {
            $0.key.namespace == namespace && selectedIDs.contains($0.key.songID)
        }
        let savedIDs = Set(
            library.copies.filter {
                $0.key.namespace == namespace && $0.quality == quality && selectedIDs.contains($0.key.songID)
            }.map { $0.key.songID })
        savedCount = savedIDs.count
    }
}

public struct OfflineAlbum: Codable, Sendable {
    public let namespace: String
    public let album: Album
    public init(namespace: String, album: Album) {
        self.namespace = namespace
        self.album = album
    }
}

/// Credentials and authenticated transfer URLs are deliberately absent from this index.
public struct DownloadLibrary: Codable, Sendable {
    public var copies: [OfflineSong] = []
    public var jobs: [DownloadJob] = []
    public var albums: [OfflineAlbum] = []
    public var preferences: [String: DownloadQuality] = [:]
    public init() {}

    @discardableResult public mutating func enqueue(
        _ song: Song, namespace: String, quality: DownloadQuality
    ) -> UUID? {
        let key = DownloadKey(namespace: namespace, songID: song.id)
        guard !jobs.contains(where: { $0.key == key }),
            !copies.contains(where: { $0.key == key && $0.quality == quality })
        else { return nil }
        let job = DownloadJob(key: key, song: song, quality: quality)
        jobs.append(job)
        return job.id
    }

    /// Commit only a validated file. A failed or cancelled job never replaces its old copy.
    @discardableResult public mutating func complete(_ id: UUID, filename: String, bytes: Int64) -> OfflineSong? {
        guard let job = jobs.first(where: { $0.id == id }) else { return nil }
        let previous = copies.first { $0.key == job.key }
        copies.removeAll { $0.key == job.key }
        copies.append(OfflineSong(key: job.key, song: job.song, quality: job.quality, filename: filename, bytes: bytes))
        jobs.removeAll { $0.id == id }
        return previous
    }

    public mutating func remember(_ album: Album, namespace: String) {
        albums.removeAll { $0.namespace == namespace && $0.album.id == album.id }
        albums.append(OfflineAlbum(namespace: namespace, album: album))
    }

    public func downloadedAlbums(namespace: String) -> [Album] {
        let songs = copies.filter { $0.key.namespace == namespace }.map(\.song)
        return Dictionary(grouping: songs, by: { $0.albumId ?? "" }).compactMap { id, tracks in
            guard !id.isEmpty else { return nil }
            if let album = albums.first(where: { $0.namespace == namespace && $0.album.id == id })?.album {
                return album
            }
            guard let first = tracks.first else { return nil }
            return Album(
                id: id, name: first.album ?? "Unknown album", artist: first.artistName,
                displayArtist: first.displayAlbumArtist, artists: first.albumArtists, artistId: first.artistId,
                coverArt: first.coverArt, songCount: tracks.count,
                duration: tracks.reduce(0) { $0 + ($1.duration ?? 0) },
                year: nil, genre: nil, starred: nil, song: tracks)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func responseError(status: Int, prefix: Data) -> String? {
        if status == 401 { return "The server rejected your credentials. Update them in Settings, then retry." }
        if status == 403 { return "Downloads are disabled or your account cannot download this music." }
        if status == 429 { return "The server is busy converting music. Try again shortly." }
        if !(200..<300).contains(status) { return "The server returned HTTP \(status). Try again." }
        let text = String(decoding: prefix.prefix(4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("{") || text.hasPrefix("<") || text.hasPrefix("[") {
            let json = (try? JSONSerialization.jsonObject(with: prefix)) as? [String: Any]
            let envelope = json?["subsonic-response"] as? [String: Any]
            let error = envelope?["error"] as? [String: Any]
            let code = error?["code"] as? Int
            if code == 40 || code == 41 {
                return "The server rejected your credentials. Update them in Settings, then retry."
            }
            if code == 50 || text.contains("downloads are disabled") || text.contains("code=\"50\"") {
                return "Downloads are disabled or your account cannot download this music."
            }
            return "The server did not return an audio file. Check download permissions and the selected transcoder."
        }
        return prefix.isEmpty ? "The server returned an empty file." : nil
    }
}
