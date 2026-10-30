import Foundation

/// The displayed clock stays at the requested position until the matching seek settles.
/// Media callbacks from a superseded seek cannot move it or add listening time.
public struct PlaybackTimeline: Sendable {
    public struct Seek: Equatable, Sendable {
        public let id: UUID
        public let target: Double
    }

    public private(set) var elapsed: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var listeningTime: Double = 0
    public private(set) var pendingSeek: Seek?
    private var previousTime: Double?
    private var hasReliableDuration = false

    public init() {}

    public mutating func reset(duration: Double) {
        self = PlaybackTimeline()
        if duration.isFinite, duration > 0 {
            self.duration = duration
            hasReliableDuration = true
        }
    }

    public mutating func restorePosition(_ seconds: Double) {
        guard seconds.isFinite else { return }
        elapsed = bounded(seconds)
        previousTime = nil
    }

    public mutating func updateAssetDuration(_ seconds: Double) {
        // Navidrome's track length is stable; a streamed asset's estimate may change.
        guard !hasReliableDuration, seconds.isFinite, seconds > 0 else { return }
        duration = seconds
    }

    /// A verified file duration takes precedence over rounded or stale library metadata.
    /// Keep ignoring unverified stream estimates after accepting precise timing.
    public mutating func updatePreciseDuration(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        duration = seconds
        hasReliableDuration = true
        elapsed = bounded(elapsed)
    }

    @discardableResult
    public mutating func beginSeek(to seconds: Double) -> Seek? {
        guard seconds.isFinite, duration > 0 else { return nil }
        let seek = Seek(id: UUID(), target: bounded(seconds))
        pendingSeek = seek
        elapsed = seek.target
        previousTime = nil
        return seek
    }

    @discardableResult
    public mutating func completeSeek(_ seek: Seek, at seconds: Double) -> Bool {
        guard pendingSeek == seek else { return false }
        pendingSeek = nil
        if seconds.isFinite {
            elapsed = bounded(seconds)
            previousTime = elapsed
        }
        return true
    }

    @discardableResult
    public mutating func tick(at seconds: Double, isPlaying: Bool) -> Bool {
        guard pendingSeek == nil, seconds.isFinite else { return false }
        let position = bounded(seconds)
        if let previousTime {
            let delta = position - previousTime
            if isPlaying, delta > 0, delta < 2 { listeningTime += delta }
        }
        previousTime = position
        elapsed = position
        return true
    }

    private func bounded(_ seconds: Double) -> Double {
        duration > 0 ? min(duration, max(0, seconds)) : max(0, seconds)
    }
}
