import SwiftUI
import GevunCore

struct MiniPlayer: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    private var player: PlayerStore { store.player }
    var body: some View {
        if let song = interface.current {
            HStack(spacing: 4) {
                Button {
                    player.expanded = true
                } label: {
                    HStack(spacing: 10) {
                        ArtworkView(id: song.coverArt, size: 128, cornerRadius: Theme.playerArtworkCornerRadius)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(interface.error == nil ? song.artistName : "Playback needs attention")
                                .font(.caption2).foregroundStyle(theme.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(
                    "Now playing: \(song.title) by \(song.artistName). Open player")
                Button {
                    player.toggle()
                } label: {
                    Group {
                        if interface.buffering {
                            ProgressView().tint(theme.accent)
                        } else {
                            Image(systemName: interface.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                        }
                    }.frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(.white).accessibilityLabel(
                    interface.isPlaying || interface.buffering ? "Pause" : "Play")
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).foregroundStyle(.white).accessibilityLabel("Next track")
            }.padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 4)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
        }
    }
}

private enum PlayerSheet: String, Identifiable {
    case lyrics, queue
    var id: String { rawValue }
}

struct NowPlayingView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    private var player: PlayerStore { store.player }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let safeAreaInsets: EdgeInsets
    let motion: PlayerDismissalMotion
    let onClose: (CGFloat) -> Void
    @ScaledMetric(relativeTo: .body) private var metadataHeight: CGFloat = 94
    @ScaledMetric(relativeTo: .caption) private var playbackErrorHeight: CGFloat = 76
    @State private var presentedSheet: PlayerSheet?

    var body: some View {
        GeometryReader { geometry in
            let bodyHeight = max(0, geometry.size.height - safeAreaInsets.top - safeAreaInsets.bottom - 80)
            let controlsHeight = metadataHeight + 44 + 72 + 36 + (interface.error == nil ? 0 : playbackErrorHeight + 12)
            let width = max(0, min(640, geometry.size.width - 24, bodyHeight - controlsHeight))
            ZStack(alignment: .bottom) {
                PlayerBackdrop()
                Group {
                    if let song = interface.current {
                        VStack(spacing: 12) {
                            ArtworkView(id: song.coverArt, size: 1200, cornerRadius: Theme.playerArtworkCornerRadius)
                                .frame(width: width, height: width)
                                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                            PlayerSeekView()
                            VStack(spacing: 4) {
                                Text(song.artistName).font(.body).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                                Text(song.title).font(.headline.weight(.bold)).lineLimit(2)
                                if let album = song.album, !album.isEmpty {
                                    Text(album).font(.body).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                }
                            }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                                .frame(height: metadataHeight)
                            transportControls
                            if let error = interface.error {
                                VStack(spacing: 6) {
                                    Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                                    Button("Retry playback", systemImage: "arrow.clockwise") { player.retry() }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }.frame(minHeight: bodyHeight, alignment: .top)
                            .padding(.horizontal, 12).padding(.top, safeAreaInsets.top + 4)
                            .padding(.bottom, safeAreaInsets.bottom + 76)
                            .frame(maxWidth: 664).frame(maxWidth: .infinity)
                    }
                }
                bottomControls
                    .padding(.horizontal, 20).frame(maxWidth: 664)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, safeAreaInsets.bottom + 12)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .modifier(PlayerSurfaceMotion(motion: motion, reduceMotion: reduceMotion))
            .onAppear { motion.resize(height: geometry.size.height) }
            .onChange(of: geometry.size.height) { _, height in motion.resize(height: height) }
        }
        .contentShape(Rectangle())
        .onChange(of: reduceMotion) { _, _ in motion.interrupt() }
        .onChange(of: presentedSheet) { _, sheet in if sheet != nil { motion.interrupt() } }
        .onDisappear { motion.stop() }
        .accessibilityAction(.escape) { close() }
        .accessibilityAction(named: Text("Close player")) { close() }
        .accessibilityAction(named: Text("Show lyrics")) { presentedSheet = .lyrics }
        .accessibilityAction(named: Text("Show queue")) { presentedSheet = .queue }
        .sheet(item: $presentedSheet) { sheet in
            Group {
                switch sheet {
                case .lyrics: LyricsView()
                case .queue: QueueView()
                }
            }.environment(store).environmentObject(player).presentationDragIndicator(.visible)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 32) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 24)).frame(width: 56, height: 56)
            }.accessibilityLabel("Previous track")
            Button {
                player.toggle()
            } label: {
                ZStack {
                    Circle().fill(.black.opacity(0.32)).frame(width: 64, height: 64)
                    if interface.buffering {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: interface.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 25, weight: .semibold)).offset(x: interface.isPlaying ? 0 : 2)
                    }
                }.frame(width: 72, height: 72)
            }.accessibilityLabel(interface.isPlaying || interface.buffering ? "Pause" : "Play")
            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 24)).frame(width: 56, height: 56)
            }.accessibilityLabel("Next track")
        }.buttonStyle(.plain).foregroundStyle(.white).frame(maxWidth: .infinity)
    }

    private var bottomControls: some View {
        HStack(spacing: 24) {
            Button {
                presentedSheet = .lyrics
            } label: {
                Text("LYRICS")
                    .font(.caption.weight(.semibold)).tracking(2.4)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Lyrics").accessibilityHint("Open lyrics")
            Button {
                player.cycleRepeat()
            } label: {
                Image(systemName: interface.queue.repeatMode == .one ? "repeat.1" : "repeat").font(.title3)
                    .foregroundStyle(interface.queue.repeatMode == .off ? .white.opacity(0.7) : theme.accent)
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("Repeat").accessibilityValue(interface.queue.repeatMode.rawValue)
            Button {
                presentedSheet = .queue
            } label: {
                Text("QUEUE")
                    .font(.caption.weight(.semibold)).tracking(2.4)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Queue").accessibilityHint("Open play queue")
        }.buttonStyle(.plain).frame(maxWidth: 300)
    }

    private func close() {
        onClose(0)
    }
}

private struct PlayerSeekView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var scrubPlaybackID: UUID?

    var body: some View {
        let playbackID = player.playbackID
        let isScrubbing = scrubbing && scrubPlaybackID == playbackID
        return HStack(spacing: 10) {
            Text(TimeLabel.clock(isScrubbing ? scrub : player.elapsed)).frame(minWidth: 34)
            MinimalSeekSlider(
                value: isScrubbing ? scrub : player.elapsed, duration: player.canSeek ? player.duration : 0,
                onChange: { if player.playbackID == playbackID { scrub = $0 } },
                onCommit: { if player.playbackID == playbackID { player.seek($0) } }
            ) { editing in
                guard player.playbackID == playbackID else { return }
                if editing {
                    scrub = player.elapsed
                    scrubPlaybackID = playbackID
                    scrubbing = true
                } else {
                    scrubbing = false
                    scrubPlaybackID = nil
                }
            }.id(playbackID).frame(height: 44)
            Text(TimeLabel.clock(player.duration)).frame(minWidth: 34)
        }.font(.caption2).monospacedDigit().foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .onChange(of: player.playbackID) { _, _ in
                scrubbing = false
                scrub = 0
                scrubPlaybackID = nil
            }
    }

}

private struct MinimalSeekSlider: UIViewRepresentable {
    let value: Double
    let duration: Double
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void
    var onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SeekControl {
        let control = SeekControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        control.addTarget(context.coordinator, action: #selector(Coordinator.began), for: .editingDidBegin)
        control.addTarget(context.coordinator, action: #selector(Coordinator.ended(_:)), for: .editingDidEnd)
        return control
    }

    func updateUIView(_ control: SeekControl, context: Context) {
        context.coordinator.parent = self
        control.duration = duration.isFinite ? max(0, duration) : 0
        control.isEnabled = control.duration > 0
        // UIKit can still report isTracking while delivering editingDidEnd. Our own
        // editing flag is already cleared then, so the final actual time must be applied.
        if !control.scrubbing { control.value = min(max(0, value), control.duration) }
    }

    final class Coordinator: NSObject {
        var parent: MinimalSeekSlider
        init(_ parent: MinimalSeekSlider) { self.parent = parent }
        @objc func changed(_ control: SeekControl) { parent.onChange(control.value) }
        @objc func began() { parent.onEditingChanged(true) }
        @objc func ended(_ control: SeekControl) {
            if !control.trackingCancelled { parent.onCommit(control.value) }
            parent.onEditingChanged(false)
        }
    }

    final class SeekControl: UIControl {
        var duration: Double = 0 {
            didSet {
                setNeedsLayout()
                updateAccessibility()
            }
        }
        var value: Double = 0 {
            didSet {
                setNeedsLayout()
                updateAccessibility()
            }
        }
        private(set) var trackingCancelled = false
        private(set) var scrubbing = false
        private let rail = CALayer()
        private let progress = CALayer()
        private let thumb = CALayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            rail.backgroundColor = UIColor.white.withAlphaComponent(0.22).cgColor
            progress.backgroundColor = UIColor.white.withAlphaComponent(0.9).cgColor
            thumb.backgroundColor = UIColor.white.cgColor
            [rail, progress, thumb].forEach(layer.addSublayer)
            isAccessibilityElement = true
            accessibilityIdentifier = "player.seek"
            accessibilityLabel = "Playback position"
            accessibilityTraits = [.adjustable]
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            let height: CGFloat = scrubbing ? 3 : 2
            let fraction = duration > 0 ? min(1, max(0, value / duration)) : 0
            let width = bounds.width * fraction
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rail.frame = CGRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
            progress.frame = CGRect(x: 0, y: rail.frame.minY, width: width, height: height)
            rail.cornerRadius = height / 2
            progress.cornerRadius = height / 2
            thumb.frame = CGRect(
                x: min(max(3.5, width), max(3.5, bounds.width - 3.5)) - 3.5, y: bounds.midY - 3.5, width: 7, height: 7)
            thumb.cornerRadius = 3.5
            thumb.opacity = scrubbing ? 1 : 0
            rail.opacity = isEnabled ? 1 : 0.4
            progress.opacity = rail.opacity
            CATransaction.commit()
        }

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            guard isEnabled else { return false }
            trackingCancelled = false
            scrubbing = true
            sendActions(for: .editingDidBegin)
            move(to: touch.location(in: self).x)
            return true
        }
        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            move(to: touch.location(in: self).x)
            return true
        }
        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            if let touch { move(to: touch.location(in: self).x) }
            finish()
        }
        override func cancelTracking(with event: UIEvent?) {
            trackingCancelled = true
            finish()
        }
        private func move(to x: CGFloat) {
            value = min(1, max(0, x / max(1, bounds.width))) * duration
            sendActions(for: .valueChanged)
        }
        private func finish() {
            scrubbing = false
            setNeedsLayout()
            sendActions(for: .editingDidEnd)
        }
        private func updateAccessibility() {
            accessibilityValue = "\(TimeLabel.clock(value)) of \(TimeLabel.clock(duration))"
        }
        override func accessibilityIncrement() { adjust(by: 10) }
        override func accessibilityDecrement() { adjust(by: -10) }
        private func adjust(by seconds: Double) {
            guard isEnabled else { return }
            trackingCancelled = false
            sendActions(for: .editingDidBegin)
            value = min(duration, max(0, value + seconds))
            sendActions(for: .valueChanged)
            sendActions(for: .editingDidEnd)
        }
    }
}

private struct PlayerBackdrop: View {
    @EnvironmentObject private var appearance: ArtworkAppearance
    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [theme.playerPrimary, theme.playerSecondary, theme.playerPrimary], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                if let image = appearance.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .saturation(1.8).blur(radius: 65).opacity(0.55)
                }
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.12), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.5),
                        .init(color: .black.opacity(0.72), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct QueueView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PlayerQueueView(onSelect: { dismiss() })
                .padding(.horizontal, 16).padding(.top, 8).pageBackground()
                .navigationTitle("Queue").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct PlayerQueueView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    private var player: PlayerStore { store.player }
    let onSelect: () -> Void
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("\(max(0, interface.queue.songs.count - interface.queue.index - 1)) tracks up next")
                    .font(.caption).foregroundStyle(theme.secondary).padding(.bottom, 4)
                if let song = interface.current {
                    HStack(spacing: 10) {
                        ArtworkView(id: song.coverArt, size: 192).frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.title).font(.headline).foregroundStyle(theme.accent).lineLimit(2)
                            Text(song.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "waveform").foregroundStyle(theme.accent)
                    }.padding(.vertical, 4)
                    Divider().overlay(theme.border).padding(.vertical, 8)
                }
                if interface.queue.index + 1 < interface.queue.songs.count {
                    ForEach(
                        Array(interface.queue.songs.enumerated()).filter { $0.offset > interface.queue.index },
                        id: \.offset
                    ) { index, song in
                        VStack(spacing: 0) {
                            SongRow(song: song) {
                                player.select(index)
                                onSelect()
                            }
                            Divider().overlay(theme.border)
                        }
                    }
                } else {
                    Text("You're at the end of the queue.").font(.subheadline).foregroundStyle(theme.secondary).padding(
                        .vertical, 12)
                }
            }.padding(.bottom, 12)
        }.scrollIndicators(.hidden).scrollEdgeEffectStyle(.soft, for: .all)
    }
}
