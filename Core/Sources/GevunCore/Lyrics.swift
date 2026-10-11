import Foundation

public struct LyricLine: Codable, Hashable, Sendable {
    public let start: Double?
    public let value: String
    public init(start: Double? = nil, value: String) {
        self.start = start
        self.value = value
    }
}

public struct StructuredLyrics: Codable, Hashable, Sendable {
    public let displayArtist: String?
    public let displayTitle: String?
    public let lang: String?
    public let synced: Bool
    public let offset: Double?
    public let line: [LyricLine]

    public init(
        displayArtist: String? = nil, displayTitle: String? = nil, lang: String? = nil,
        synced: Bool = false, offset: Double? = nil, line: [LyricLine]
    ) {
        self.displayArtist = displayArtist
        self.displayTitle = displayTitle
        self.lang = lang
        self.synced = synced
        self.offset = offset
        self.line = line
    }

    public var hasContent: Bool { line.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    public func activeLineIndex(at seconds: Double) -> Int? {
        guard synced, seconds.isFinite else { return nil }
        // OpenSubsonic positive offsets advance the lyrics, so add them to playback time.
        let milliseconds = seconds * 1000 + (offset ?? 0)
        return line.lastIndex { ($0.start ?? .infinity) <= milliseconds }
    }

    public func seekTime(for index: Int) -> Double? {
        guard synced, line.indices.contains(index), let start = line[index].start else { return nil }
        return max(0, (start - (offset ?? 0)) / 1000)
    }
}
