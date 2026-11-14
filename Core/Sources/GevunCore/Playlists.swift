import Foundation

/// A Navidrome playlist. List responses leave out `entry`; `getPlaylist` includes the songs in order.
public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let comment: String?
    public let owner: String?
    public let isPublic: Bool?
    public let songCount: Int?
    public let duration: Int?
    public let coverArt: String?
    public let changed: String?
    /// Navidrome marks smart playlists (`.nsp` files) as read-only.
    public let readonly: Bool?
    public let entry: [Song]?

    enum CodingKeys: String, CodingKey {
        case id, name, comment, owner, songCount, duration, coverArt, changed, readonly, entry
        case isPublic = "public"
    }

    public init(
        id: String, name: String, comment: String? = nil, owner: String? = nil, isPublic: Bool? = nil,
        songCount: Int? = nil, duration: Int? = nil, coverArt: String? = nil, changed: String? = nil,
        readonly: Bool? = nil, entry: [Song]? = nil
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.owner = owner
        self.isPublic = isPublic
        self.songCount = songCount
        self.duration = duration
        self.coverArt = coverArt
        self.changed = changed
        self.readonly = readonly
        self.entry = entry
    }

    public var songs: [Song] { entry ?? [] }

    /// Only the owner can change a playlist, and never a smart playlist.
    public func isEditable(by username: String) -> Bool {
        readonly != true && owner?.caseInsensitiveCompare(username) == .orderedSame
    }

    public var changedDate: Date? {
        guard let changed else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: changed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: changed)
    }

    /// Trims a typed name, falling back to a default for blank input.
    public static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Playlist" : String(trimmed.prefix(200))
    }
}
