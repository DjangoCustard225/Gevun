import Foundation

/// The system advances its clock itself. Republish only when its reference state changes.
public struct NowPlayingPublication: Sendable {
    public struct State: Equatable, Sendable {
        public var playbackID: UUID
        public var duration: Double
        public var rate: Float
        public var artworkRevision: UUID?
        public var seekID: UUID?
        public var failed: Bool

        public init(
            playbackID: UUID, duration: Double, rate: Float,
            artworkRevision: UUID? = nil, seekID: UUID? = nil, failed: Bool = false
        ) {
            self.playbackID = playbackID
            self.duration = duration
            self.rate = rate
            self.artworkRevision = artworkRevision
            self.seekID = seekID
            self.failed = failed
        }
    }

    private var last: State?
    public init() {}

    public mutating func shouldPublish(_ state: State, force: Bool = false) -> Bool {
        guard force || last != state else { return false }
        last = state
        return true
    }

    public mutating func reset() { last = nil }
}
