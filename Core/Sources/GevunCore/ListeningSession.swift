import Foundation

public struct ListeningSession: Codable, Sendable {
    public let version: Int
    public let queue: PlaybackQueue
    public let position: Double

    public init(queue: PlaybackQueue, position: Double) {
        version = 1
        self.queue = queue
        let duration = Double(queue.current?.duration ?? 0)
        let finite = position.isFinite ? max(0, position) : 0
        self.position = duration > 0 ? min(duration, finite) : finite
    }
    public var isValid: Bool { version == 1 && queue.current != nil && position.isFinite && position >= 0 }
}
