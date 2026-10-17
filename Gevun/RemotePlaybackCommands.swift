import MediaPlayer

/// Owns lock-screen command registrations for the lifetime of the player.
@MainActor
final class RemotePlaybackCommands {
    private var targets: [(MPRemoteCommand, Any)] = []

    init(player: PlayerStore) {
        let center = MPRemoteCommandCenter.shared()
        bind(center.playCommand, player: player) { $0.resume() }
        bind(center.pauseCommand, player: player) { $0.pause() }
        bind(center.togglePlayPauseCommand, player: player) { $0.toggle() }
        bind(center.nextTrackCommand, player: player) { $0.next() }
        bind(center.previousTrackCommand, player: player) { $0.previous() }
        let target = center.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in player?.seek(position) }
            return .success
        }
        targets.append((center.changePlaybackPositionCommand, target))
    }

    private func bind(_ command: MPRemoteCommand, player: PlayerStore, action: @escaping (PlayerStore) -> Void) {
        let target = command.addTarget { [weak player] _ in
            Task { @MainActor in if let player { action(player) } }
            return .success
        }
        targets.append((command, target))
    }

    deinit {
        targets.forEach { $0.0.removeTarget($0.1) }
    }
}
