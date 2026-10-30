import Foundation

public enum RepeatMode: String, CaseIterable, Codable, Sendable { case off, all, one }

public struct PlaybackQueue: Codable, Sendable {
    public private(set) var songs: [Song] = []
    public private(set) var index: Int = 0
    public var repeatMode: RepeatMode = .off
    public private(set) var shuffled = false
    private var original: [Song] = []
    public var current: Song? { songs.indices.contains(index) ? songs[index] : nil }
    public init() {}
    public mutating func replace(_ songs: [Song], startingAt index: Int = 0, shuffle: Bool = false) {
        original = songs
        self.songs = songs
        self.index = max(0, min(index, songs.count - 1))
        shuffled = shuffle
        if shuffle, let current {
            self.songs = [current] + songs.enumerated().filter { $0.offset != self.index }.map(\.element).shuffled()
            self.index = 0
        }
    }
    public mutating func advance(automatic: Bool = false) -> Bool {
        guard !songs.isEmpty else { return false }
        if automatic && repeatMode == .one { return true }
        if index + 1 < songs.count {
            index += 1
            return true
        }
        if repeatMode == .all {
            index = 0
            return true
        }
        return false
    }
    public mutating func previous() { index = max(0, index - 1) }
    public mutating func select(_ index: Int) { if songs.indices.contains(index) { self.index = index } }
    public mutating func append(_ song: Song, next: Bool) {
        songs.insert(song, at: next && !songs.isEmpty ? index + 1 : songs.count)
        original.append(song)
    }
    public mutating func toggleShuffle() {
        guard let current else { return }
        if shuffled {
            songs = original
            index = songs.firstIndex(where: { $0.id == current.id }) ?? 0
        } else {
            songs = [current] + songs.enumerated().filter { $0.offset != index }.map(\.element).shuffled()
            index = 0
        }
        shuffled.toggle()
    }
}
