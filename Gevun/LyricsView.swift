import SwiftUI
import Combine
import GevunCore

struct LyricsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var versions: [StructuredLyrics] = []
    @State private var selection = 0
    @State private var loading = true
    @State private var message: String?
    @State private var following = true
    @State private var revision = UUID()
    @State private var activeLine: Int?

    private let horizontalPadding: CGFloat = 28
    private let lyricAnchor = UnitPoint(x: 0.5, y: 0.38)
    private var player: PlayerStore { store.player }
    private var lyrics: StructuredLyrics? { versions.indices.contains(selection) ? versions[selection] : nil }
    private var requestID: String { "\(store.sessionID):\(interface.current?.id ?? "")" }
    private var lyricAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.75, extraBounce: 0) }

    var body: some View {
        NavigationStack {
            content
                .background { LyricsBackdrop() }
                .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private var content: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    scrollContent(width: max(1, geometry.size.width - 2 * horizontalPadding), proxy: proxy)
                        .padding(.horizontal, horizontalPadding).padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                }
                .contentMargins(
                    .bottom, lyrics?.synced == true ? geometry.size.height * (1 - lyricAnchor.y) : 0,
                    for: .scrollContent
                )
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .onScrollPhaseChange { _, phase in
                    if phase == .tracking || phase == .interacting { following = false }
                }
                .onChange(of: activeLine) { _, _ in followActiveLine(using: proxy) }
                .onChange(of: geometry.size) { _, _ in followActiveLine(using: proxy) }
                .onChange(of: selection) { _, _ in
                    updateActiveLine(at: player.elapsed)
                    following = true
                    if activeLine == nil { proxy.scrollTo(0, anchor: .top) } else { followActiveLine(using: proxy) }
                }
                .toolbar { lyricsToolbar(proxy: proxy) }
            }
        }
        .onReceive(player.$elapsed.removeDuplicates()) { updateActiveLine(at: $0) }
        .onChange(of: versions) { _, _ in updateActiveLine(at: player.elapsed) }
        .task(id: requestID) { await load() }
    }

    @ViewBuilder private func scrollContent(width: CGFloat, proxy: ScrollViewProxy) -> some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40).accessibilityLabel("Loading lyrics")
        } else if let message {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn't load lyrics").font(.headline)
                Text(message).foregroundStyle(theme.secondary)
                Button("Try again", systemImage: "arrow.clockwise") { Task { await load() } }
                    .buttonStyle(.bordered)
            }
        } else if let lyrics {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lyrics.line.indices, id: \.self) { index in
                    let line = lyrics.line[index]
                    Group {
                        if line.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Color.clear.frame(height: 8).accessibilityHidden(true)
                        } else {
                            let seekTime = lyrics.seekTime(for: index)
                            let text = LyricsText(
                                text: line.value, synced: seekTime != nil, active: activeLine == index,
                                adjacent: activeLine.map { abs($0 - index) == 1 } ?? false, width: width)
                            if let seekTime {
                                Button {
                                    seek(to: seekTime, line: index, proxy: proxy)
                                } label: {
                                    text
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Seek to this line")
                                .accessibilityAddTraits(activeLine == index ? .isSelected : [])
                            } else {
                                text
                            }
                        }
                    }.id(index)
                }
            }
            .animation(lyricAnimation, value: activeLine)
            .padding(.bottom, 32)
        } else {
            ContentUnavailableView(
                "No lyrics available", systemImage: "quote.bubble",
                description: Text("Your server has no lyrics for this track."))
        }
    }

    @ToolbarContentBuilder private func lyricsToolbar(proxy: ScrollViewProxy) -> some ToolbarContent {
        if versions.count > 1 {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Lyrics version", selection: $selection) {
                        ForEach(versions.indices, id: \.self) { index in Text(versionLabel(index)).tag(index) }
                    }
                } label: {
                    Image(systemName: "globe")
                }.accessibilityLabel("Choose lyrics version")
            }
        }
        if lyrics?.synced == true && !following {
            ToolbarItem(placement: .bottomBar) {
                Button("Follow lyrics", systemImage: "location.fill") {
                    following = true
                    followActiveLine(using: proxy)
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }

    private func updateActiveLine(at seconds: Double) {
        let index = lyrics?.activeLineIndex(at: seconds)
        if activeLine != index { activeLine = index }
    }

    private func seek(to time: Double, line index: Int, proxy: ScrollViewProxy) {
        let alreadyActive = activeLine == index
        following = true
        player.seek(time)
        if alreadyActive { scroll(to: index, proxy: proxy) }
    }

    private func followActiveLine(using proxy: ScrollViewProxy) {
        guard following, let activeLine else { return }
        scroll(to: activeLine, proxy: proxy)
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        withAnimation(lyricAnimation) { proxy.scrollTo(index, anchor: lyricAnchor) }
    }

    private func versionLabel(_ index: Int) -> String {
        let value = versions[index]
        let code = value.lang?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let language =
            ["", "und", "xxx"].contains(code.lowercased())
            ? "Lyrics" : Locale.current.localizedString(forLanguageCode: code) ?? code
        return "\(language) · \(value.synced ? "Synced" : "Text") · \(index + 1)"
    }

    private func load() async {
        let request = UUID()
        revision = request
        activeLine = nil
        versions = []
        selection = 0
        message = nil
        loading = true
        following = true
        guard let api = store.api, let song = player.current else {
            loading = false
            return
        }
        let session = store.sessionID
        do {
            let values = try await api.lyrics(for: song)
            guard revision == request, store.sessionID == session, player.current?.id == song.id, !Task.isCancelled
            else { return }
            versions = values
        } catch {
            guard revision == request, store.sessionID == session, player.current?.id == song.id, !Task.isCancelled
            else { return }
            message = error as? GevunError == .server(0) ? "This server doesn't support lyrics." : friendlyError(error)
        }
        if revision == request { loading = false }
    }
}

private struct LyricsText: View {
    @ScaledMetric(relativeTo: .title2) private var lyricSize: CGFloat = 22
    @ScaledMetric(relativeTo: .largeTitle) private var highlightedLyricSize: CGFloat = 34
    let text: String
    let synced: Bool
    let active: Bool
    let adjacent: Bool
    let width: CGFloat

    private var highlighted: Bool { synced && active }
    private var blur: CGFloat { !synced || highlighted ? 0 : (adjacent ? 1.5 : 2.5) }
    private var opacity: Double { !synced || highlighted ? 1 : (adjacent ? 0.6 : 0.45) }

    var body: some View {
        Text(text)
            .font(.system(size: highlighted ? highlightedLyricSize : lyricSize, weight: synced ? .bold : .semibold))
            .foregroundStyle(.white.opacity(opacity))
            .contentTransition(transition)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2).frame(minHeight: 44, alignment: .leading)
            .geometryGroup()
            .blur(radius: blur)
    }

    private var transition: ContentTransition {
        guard synced else { return .interpolate }
        let font = UIFont.systemFont(ofSize: highlightedLyricSize, weight: .bold)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        // Wrapped lines dissolve without reshaping glyphs between different line breaks.
        return bounds.height > font.lineHeight + 1 ? .opacity : .interpolate
    }
}

private struct LyricsBackdrop: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var interface: PlaybackInterfaceState

    private var moving: Bool { interface.isPlaying && scenePhase == .active && !reduceMotion }

    var body: some View {
        ZStack {
            if moving {
                mesh(shifted: false)
                    .phaseAnimator([false, true]) { _, shifted in
                        mesh(shifted: shifted)
                    } animation: { _ in
                        .easeInOut(duration: 9)
                    }
            } else {
                mesh(shifted: false)
            }
            LinearGradient(
                colors: [.black.opacity(0.28), .black.opacity(0.58)],
                startPoint: .top, endPoint: .bottom)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: moving)
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }

    private func mesh(shifted: Bool) -> some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
                SIMD2<Float>(0, 0.5), SIMD2<Float>(shifted ? 0.62 : 0.38, shifted ? 0.42 : 0.6), SIMD2<Float>(1, 0.5),
                SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1),
            ],
            colors: [
                theme.playerPrimary, theme.playerSecondary, theme.playerPrimary,
                theme.playerSecondary, theme.playerPrimary, theme.playerSecondary,
                theme.playerPrimary, theme.playerSecondary, theme.playerPrimary,
            ])
    }
}
