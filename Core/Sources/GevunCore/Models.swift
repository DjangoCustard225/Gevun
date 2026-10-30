import Foundation

public struct Instance: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var username: String
    public var password: String

    public init(id: UUID = UUID(), name: String, address: String, username: String, password: String) throws {
        let url = try Self.serverURL(from: address)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else { throw GevunError.missingCredentials }
        self.id = id
        self.name =
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (url.host ?? "Navidrome") : name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
        self.username = user
        self.password = password
    }

    public static func serverURL(from address: String) throws -> URL {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: address),
            ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
            let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil
        else {
            throw GevunError.invalidAddress
        }
        parts.scheme = parts.scheme?.lowercased()
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let url = parts.url else { throw GevunError.invalidAddress }
        return url
    }
}

public struct Album: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let artist: String?
    public let displayArtist: String?
    public let artists: [ArtistCredit]?
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let year: Int?
    public let genre: String?
    public var starred: String?
    public let song: [Song]?
    public var artistName: String {
        ArtistCredit.display(displayArtist, credits: artists, fallback: artist) ?? "Unknown artist"
    }
    public var songs: [Song] {
        guard let albumArtist = ArtistCredit.display(displayArtist, credits: artists, fallback: artist) else {
            return song ?? []
        }
        return (song ?? []).map { $0.withAlbumArtistFallback(albumArtist) }
    }
}

public struct Song: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let displayAlbumArtist: String?
    public let albumArtists: [ArtistCredit]?
    public var albumArtist: String?
    public let album: String?
    public let albumId: String?
    public let artistId: String?
    public let coverArt: String?
    public let duration: Int?
    public let track: Int?
    public let discNumber: Int?
    public let year: Int?
    public let genre: String?
    public let suffix: String?
    public let bitRate: Int?
    public let size: Int64?
    public var starred: String?
    public var artistName: String {
        ArtistCredit.display(displayAlbumArtist, credits: albumArtists, fallback: albumArtist)
            ?? ArtistCredit.nonempty(artist) ?? "Unknown artist"
    }

    func withAlbumArtistFallback(_ name: String) -> Song {
        guard ArtistCredit.display(displayAlbumArtist, credits: albumArtists, fallback: albumArtist) == nil else {
            return self
        }
        var song = self
        song.albumArtist = name
        return song
    }
}

extension Album {
    public init?(song: Song) {
        guard let id = song.albumId, !id.isEmpty else { return nil }
        self.init(
            id: id, name: song.album ?? "Unknown album", artist: song.artistName,
            displayArtist: song.displayAlbumArtist, artists: song.albumArtists,
            artistId: song.albumArtists?.compactMap(\.id).first
                ?? (song.artist == song.artistName ? song.artistId : nil),
            coverArt: song.coverArt, songCount: nil, duration: nil, year: nil, genre: nil, starred: nil, song: nil)
    }
}

public struct ArtistCredit: Codable, Hashable, Sendable {
    public let id: String?
    public let name: String

    static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func display(_ display: String?, credits: [ArtistCredit]?, fallback: String?) -> String? {
        if let display = nonempty(display) { return display }
        var seen = Set<String>()
        let names = (credits ?? []).compactMap { nonempty($0.name) }.filter { seen.insert($0).inserted }
        if !names.isEmpty { return names.joined(separator: ", ") }
        return nonempty(fallback)
    }
}

public struct Artist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let coverArt: String?
    public let albumCount: Int?
    public let album: [Album]?
    public var albums: [Album] { album ?? [] }
    public init(id: String, name: String, coverArt: String? = nil, albumCount: Int? = nil, album: [Album]? = nil) {
        self.id = id
        self.name = name
        self.coverArt = coverArt
        self.albumCount = albumCount
        self.album = album
    }
}

public struct SearchResults: Codable, Sendable {
    public let album: [Album]?
    public let artist: [Artist]?
    public let song: [Song]?
    public var albums: [Album] { album ?? [] }
    public var artists: [Artist] { artist ?? [] }
    public var songs: [Song] { song ?? [] }
    public var isEmpty: Bool { albums.isEmpty && artists.isEmpty && songs.isEmpty }
    public init(album: [Album] = [], artist: [Artist] = [], song: [Song] = []) {
        self.album = album
        self.artist = artist
        self.song = song
    }
}

public enum AlbumOrder: String, CaseIterable, Identifiable, Sendable {
    case alphabeticalByName, newest, recent, frequent
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .alphabeticalByName: "A–Z"
        case .newest: "Recently added"
        case .recent: "Recently played"
        case .frequent: "Most played"
        }
    }
}

public enum GevunError: LocalizedError, Equatable {
    case invalidAddress, missingCredentials, authentication, forbidden, notFound, server(Int), http(Int),
        invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "Enter a full http:// or https:// server URL. Include its base path, without /rest, query parameters, or embedded credentials."
        case .missingCredentials: "Enter your Navidrome username and password."
        case .authentication: "The server rejected your credentials. Check your username and password."
        case .forbidden: "Your account does not have permission for this action."
        case .notFound: "This music is no longer available on the server."
        case .server(let code): "The server could not complete this request (API code \(code))."
        case .http(let code): "The server returned HTTP \(code). Check the address and reverse proxy."
        case .invalidResponse:
            "The server returned an unexpected response. Check that this is your Navidrome server URL."
        }
    }
}

public enum TimeLabel {
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    public static func duration(_ seconds: Int) -> String {
        seconds >= 3600 ? "\(seconds / 3600) hr \((seconds % 3600) / 60) min" : "\(max(0, seconds) / 60) min"
    }
}

public struct SavedPlayQueue: Decodable, Sendable {
    public let currentIndex: Int?
    public let current: String?
    public let position: Double?
    public let entry: [Song]?
    public var songs: [Song] { entry ?? [] }
    public var index: Int {
        if let currentIndex, songs.indices.contains(currentIndex) { return currentIndex }
        return songs.firstIndex { $0.id == current } ?? 0
    }
    public var seconds: Double {
        guard let position, position.isFinite else { return 0 }; return max(0, position / 1000)
    }
}
