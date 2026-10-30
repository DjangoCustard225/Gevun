import AVFoundation
import MediaPlayer
import SwiftUI
import GevunCore

/// Library, queue and accessory views observe controls without observing the playback clock.
@MainActor
final class PlaybackInterfaceState: ObservableObject {
    @Published fileprivate(set) var queue = PlaybackQueue()
    var current: Song? { queue.current }
    @Published fileprivate(set) var expanded = false
    @Published fileprivate(set) var isPlaying = false
    @Published fileprivate(set) var buffering = false
    @Published fileprivate(set) var error: String?
}

@MainActor
final class PlayerStore: ObservableObject {
    let interface = PlaybackInterfaceState()
    @Published private(set) var queue = PlaybackQueue() {
        didSet {
            interface.queue = queue
        }
    }
    @Published private(set) var isPlaying = false {
        didSet { if interface.isPlaying != isPlaying { interface.isPlaying = isPlaying } }
    }
    @Published private(set) var buffering = false {
        didSet { if interface.buffering != buffering { interface.buffering = buffering } }
    }
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var canSeek = false
    @Published private(set) var playbackID = UUID()
    @Published var error: String? {
        didSet { if interface.error != error { interface.error = error } }
    }
    @Published var expanded = false {
        didSet {
            if interface.expanded != expanded { interface.expanded = expanded }
        }
    }
    private let player = AVPlayer()
    private var api: NavidromeAPI?
    private var periodic: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var remoteCommands: RemotePlaybackCommands?
    private var artworkTask: Task<Void, Never>?
    private var assetTimingTask: Task<Void, Never>?
    private let artwork: ArtworkCache
    private let downloads: DownloadStore
    private var mediaArtwork: MPMediaItemArtwork?
    private var artworkRevision: UUID?
    private var publication = NowPlayingPublication()
    private var timeline = PlaybackTimeline()
    private var scrobbled = false
    private var resumeAfterInterruption = false
    private var wantsPlayback = false
    private var resumePosition: Double?
    private var atEnd = false
    private var endDuringSeek = false
    var current: Song? { queue.current }

    init(artwork: ArtworkCache, downloads: DownloadStore) {
        self.artwork = artwork
        self.downloads = downloads
        configurePlayerObservation()
        configureAudioObservation()
        remoteCommands = RemotePlaybackCommands(player: self)
    }

    private func configurePlayerObservation() {
        periodic = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in
            // This callback is delivered on main. Read the current item/time now rather than
            // enqueueing a captured timestamp that may belong to an earlier seek or track.
            MainActor.assumeIsolated { self?.tick() }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) {
            [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                let playing = player.timeControlStatus == .playing
                let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if self.isPlaying != playing { self.isPlaying = playing }
                if self.buffering != buffering { self.buffering = buffering }
                self.tick()
                self.updateNowPlaying()
            }
        }
        notifications.append(
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
            ) { [weak self] event in
                Task { @MainActor in
                    guard let self, let item = event.object as? AVPlayerItem, item === self.player.currentItem else {
                        return
                    }
                    self.didReachEnd(item)
                }
            })
        notifications.append(
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.timeJumpedNotification, object: nil, queue: .main
            ) { [weak self] event in
                Task { @MainActor in
                    guard let self, let item = event.object as? AVPlayerItem, item === self.player.currentItem,
                        self.timeline.pendingSeek == nil
                    else { return }
                    self.tick()
                    self.updateNowPlaying(force: true)
                }
            })
        notifications.append(
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
            ) { [weak self] event in
                Task { @MainActor in
                    guard let self, let item = event.object as? AVPlayerItem, item === self.player.currentItem else {
                        return
                    }
                    self.fail("Playback was interrupted by the server. Try this track again.")
                }
            })
    }

    private func configureAudioObservation() {
        notifications.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.didBecomeInactiveNotification, object: nil, queue: .main
            ) { [weak self] event in
                guard
                    let context = event.userInfo?[AVAudioSession.deactivationContextKey]
                        as? AVAudioSession.DeactivationContext,
                    context.source == .system
                else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.resumeAfterInterruption = self.resumeAfterInterruption || self.wantsPlayback
                    self.wantsPlayback = false
                    self.player.pause()
                }
            })
        notifications.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main
            ) { [weak self] event in
                guard
                    let context = event.userInfo?[AVAudioSession.resumptionContextKey]
                        as? AVAudioSession.ResumptionContext
                else { return }
                let shouldResume = context.recommendation == .shouldResume
                Task { @MainActor in
                    guard let self, self.resumeAfterInterruption else { return }
                    self.resumeAfterInterruption = false
                    if shouldResume { self.resume() } else { self.wantsPlayback = false }
                }
            })
        notifications.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { [weak self] event in
                let reason = event.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    Task { @MainActor in self?.pause() }
                }
            })
    }

    func configure(api: NavidromeAPI?) { self.api = api }
    func play(_ songs: [Song], at index: Int = 0, shuffle: Bool = false) {
        guard !songs.isEmpty else { return }
        queue.replace(songs, startingAt: index, shuffle: shuffle)
        loadCurrent()
    }

    func add(_ song: Song, next: Bool) {
        if current == nil {
            play([song])
            return
        }
        queue.append(song, next: next)
    }

    func select(_ index: Int) {
        guard queue.songs.indices.contains(index) else { return }
        queue.select(index)
        loadCurrent()
    }

    func toggle() { wantsPlayback ? pause() : resume() }
    func pause() {
        wantsPlayback = false
        resumeAfterInterruption = false
        player.pause()
        tick()
        updateNowPlaying()
    }
    func resume() {
        guard current != nil else { return }
        if error != nil {
            loadCurrent()
            return
        }
        do {
            try activateAudio()
            resumeAfterInterruption = false
            if atEnd { seek(0) }
            wantsPlayback = true
            if resumePosition == nil { player.play() }
            updateNowPlaying()
        } catch { fail("Audio playback could not start. Try again.") }
    }

    func retry() { loadCurrent() }
    func seek(_ seconds: Double) {
        guard let item = player.currentItem, item.status == .readyToPlay else { return }
        refreshTiming(for: item)
        guard canSeek else { return }
        guard let request = timeline.beginSeek(to: seconds) else { return }
        let playbackID = playbackID
        atEnd = false
        endDuringSeek = false
        publishTimeline()
        // Mark the new request before cancelling: cancellation can immediately complete an old seek.
        item.cancelPendingSeeks()
        player.seek(
            to: CMTime(seconds: request.target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero
        ) { [weak self, weak item] finished in
            Task { @MainActor in
                guard let self, let item, self.playbackID == playbackID, self.player.currentItem === item,
                    self.timeline.completeSeek(request, at: item.currentTime().seconds)
                else { return }
                self.publishTimeline()
                self.updateNowPlaying()
                let reachedEnd = self.endDuringSeek
                self.endDuringSeek = false
                if finished && reachedEnd { self.didReachEnd(item) }
            }
        }
        updateNowPlaying()
    }

    func previous() {
        if elapsed > 3 {
            seek(0)
        } else if queue.index > 0 {
            queue.previous()
            loadCurrent()
        } else {
            seek(0)
        }
    }

    func next(automatic: Bool = false) {
        if queue.advance(automatic: automatic) {
            loadCurrent()
        } else if automatic {
            pause()
            atEnd = true
            tick()
        }
    }

    func cycleRepeat() {
        switch queue.repeatMode {
        case .off: queue.repeatMode = .all
        case .all: queue.repeatMode = .one
        case .one: queue.repeatMode = .off
        }
    }

    func stop() {
        playbackID = UUID()
        resumePosition = nil
        timeline.reset(duration: 0)
        wantsPlayback = false
        resumeAfterInterruption = false
        atEnd = false
        endDuringSeek = false
        canSeek = false
        player.currentItem?.cancelPendingSeeks()
        player.pause()
        player.replaceCurrentItem(with: nil)
        cancelItemWork()
        mediaArtwork = nil
        artworkRevision = nil
        publication.reset()
        queue = PlaybackQueue()
        elapsed = 0
        duration = 0
        isPlaying = false
        buffering = false
        error = nil
        expanded = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cancelItemWork() {
        itemStatusObservation = nil
        assetTimingTask?.cancel()
        assetTimingTask = nil
        artworkTask?.cancel()
        artworkTask = nil
    }

    private func activateAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try session.setActive(true)
    }

    func restore(_ saved: SavedPlayQueue) {
        guard !saved.songs.isEmpty else { return }
        queue.replace(saved.songs, startingAt: saved.index)
        loadCurrent(startAt: saved.seconds)
    }

    private func loadCurrent(startAt: Double = 0) {
        guard let song = current, let api else { return }
        let playbackID = UUID()
        self.playbackID = playbackID
        resumePosition = startAt > 0 ? startAt : nil
        timeline.reset(duration: Double(song.duration ?? 0))
        publishTimeline()
        error = nil
        canSeek = false
        resumeAfterInterruption = false
        wantsPlayback = false
        atEnd = false
        endDuringSeek = false
        scrobbled = false
        mediaArtwork = nil
        artworkRevision = nil
        cancelItemWork()
        player.currentItem?.cancelPendingSeeks()
        player.pause()
        player.replaceCurrentItem(with: nil)
        do {
            try activateAudio()
            let localURL = downloads.localURL(songID: song.id, instance: api.instance)
            guard localURL != nil || downloads.connected else {
                fail("This song isn't downloaded. Connect to your server to play it.")
                return
            }
            let asset = AVURLAsset(
                url: try localURL ?? api.streamURL(song.id),
                options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let item = AVPlayerItem(asset: asset)
            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self, self.playbackID == playbackID, self.player.currentItem === item else { return }
                    self.refreshTiming(for: item)
                    if item.status == .readyToPlay, let position = self.resumePosition {
                        self.resumePosition = nil
                        self.seek(position)
                        if self.wantsPlayback { self.player.play() }
                    }
                    if item.status == .failed {
                        self.fail(
                            "This file couldn't be played. Check the connection or download it again in a supported format."
                        )
                    }
                }
            }
            player.replaceCurrentItem(with: item)
            wantsPlayback = true
            if resumePosition == nil { player.play() }
            updateNowPlaying()
            loadPreciseTiming(asset: asset, item: item, playbackID: playbackID)
            if let id = song.coverArt {
                loadArtwork(id: id, api: api, playbackID: playbackID)
            }
        } catch { fail("Playback could not start. Check the server connection and try again.") }
    }

    private func loadPreciseTiming(asset: AVAsset, item: AVPlayerItem, playbackID: UUID) {
        assetTimingTask = Task { [weak self, weak item] in
            do {
                let (duration, precise) = try await asset.load(.duration, .providesPreciseDurationAndTiming)
                guard !Task.isCancelled, precise, let self, let item,
                    self.playbackID == playbackID, self.player.currentItem === item
                else { return }
                self.timeline.updatePreciseDuration(duration.seconds)
                self.refreshTiming(for: item)
                self.tick()
                self.updateNowPlaying()
            } catch { /* Library duration remains available when precise timing cannot load. */  }
        }
    }

    private func loadArtwork(id: String, api: NavidromeAPI, playbackID: UUID) {
        let artwork = artwork
        artworkTask = Task { [weak self] in
            guard let image = await artwork.image(id: id, api: api, size: 600), !Task.isCancelled,
                let self, self.playbackID == playbackID
            else { return }
            self.mediaArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.artworkRevision = UUID()
            self.updateNowPlaying()
        }
    }

    private func tick() {
        guard current != nil, let item = player.currentItem, item.status == .readyToPlay else { return }
        refreshTiming(for: item)
        guard timeline.tick(at: item.currentTime().seconds, isPlaying: player.timeControlStatus == .playing) else {
            return
        }
        publishTimeline()
        if !scrobbled, duration > 30, timeline.listeningTime >= min(duration / 2, 240),
            UserDefaults.standard.bool(forKey: "scrobbleEnabled"), let song = current, let api
        {
            scrobbled = true
            Task { try? await api.scrobble(song.id) }
        }
    }

    private func refreshTiming(for item: AVPlayerItem) {
        let oldDuration = timeline.duration
        if item.status == .readyToPlay { timeline.updateAssetDuration(item.duration.seconds) }
        let available = item.status == .readyToPlay && timeline.duration > 0 && error == nil
        if canSeek != available { canSeek = available }
        publishTimeline()
        if timeline.duration != oldDuration { updateNowPlaying() }
    }

    private func publishTimeline() {
        if elapsed != timeline.elapsed { elapsed = timeline.elapsed }
        if duration != timeline.duration { duration = timeline.duration }
    }

    private func fail(_ message: String) {
        wantsPlayback = false
        resumeAfterInterruption = false
        endDuringSeek = false
        if let request = timeline.pendingSeek {
            timeline.completeSeek(request, at: player.currentTime().seconds)
            publishTimeline()
        }
        player.currentItem?.cancelPendingSeeks()
        player.pause()
        canSeek = false
        error = message
        updateNowPlaying()
    }

    private func didReachEnd(_ item: AVPlayerItem) {
        guard player.currentItem === item else { return }
        if timeline.pendingSeek != nil {
            endDuringSeek = true
            return
        }
        let end = item.duration.seconds
        let position = item.currentTime().seconds
        // An end notification queued before a backward seek must not skip the current song.
        guard !end.isFinite || end <= 0 || position >= end - 0.25 else { return }
        if wantsPlayback {
            next(automatic: true)
        } else {
            atEnd = true
            tick()
        }
    }

    private func updateNowPlaying(force: Bool = false) {
        guard let song = current else { return }
        let rate: Float =
            timeline.pendingSeek == nil && error == nil && wantsPlayback && player.timeControlStatus == .playing
            ? player.rate : 0
        let state = NowPlayingPublication.State(
            playbackID: playbackID, duration: duration, rate: rate,
            artworkRevision: artworkRevision, seekID: timeline.pendingSeek?.id,
            failed: error != nil)
        guard publication.shouldPublish(state, force: force) else { return }
        // Capture the precise reference time on transport changes rather than the last UI tick.
        let actualTime = player.currentItem?.currentTime().seconds ?? .nan
        let position = timeline.pendingSeek == nil && actualTime.isFinite ? max(0, actualTime) : elapsed
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title, MPMediaItemPropertyArtist: song.artistName,
            MPMediaItemPropertyAlbumTitle: song.album ?? "", MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: duration > 0 ? min(duration, position) : position,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let mediaArtwork { info[MPMediaItemPropertyArtwork] = mediaArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    deinit {
        if let periodic { player.removeTimeObserver(periodic) }
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        artworkTask?.cancel()
        assetTimingTask?.cancel()
    }
}
