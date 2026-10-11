import SwiftUI
import Combine
import GevunCore

struct LyricsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    private var player: PlayerStore { store.player }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var versions: [StructuredLyrics] = []
    @State private var selection = 0
    @State private var loading = true
    @State private var message: String?
    @State private var following = true
    @State private var revision = UUID()
    private var lyrics: StructuredLyrics? { versions.indices.contains(selection) ? versions[selection] : nil }
    @State private var activeLine: Int?
    private var requestID: String { "\(store.sessionID):\(interface.current?.id ?? "")" }

    var body: some View {
        NavigationStack {
            content.navigationTitle("").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40).accessibilityLabel(
                            "Loading lyrics")
                    } else if let message {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Couldn't load lyrics").font(.headline)
                            Text(message).foregroundStyle(theme.secondary)
                            Button("Try again", systemImage: "arrow.clockwise") { Task { await load() } }.buttonStyle(
                                .bordered)
                        }
                    } else if let lyrics {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(lyrics.line.enumerated()), id: \.offset) { index, line in
                                if line.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Color.clear.frame(height: 12).id(index).accessibilityHidden(true)
                                } else if let seekTime = lyrics.seekTime(for: index) {
                                    Button {
                                        following = true
                                        player.seek(seekTime)
                                    } label: {
                                        lyricText(line.value, active: activeLine == index, synced: true)
                                    }
                                    .buttonStyle(.plain).id(index)
                                    .accessibilityHint("Seek to this line")
                                    .accessibilityAddTraits(activeLine == index ? .isSelected : [])
                                } else {
                                    lyricText(line.value, active: false, synced: false).id(index)
                                }
                            }
                        }.padding(.bottom, 32)
                    } else {
                        ContentUnavailableView(
                            "No lyrics available", systemImage: "quote.bubble",
                            description: Text("Your server has no lyrics for this track."))
                    }
                }.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .leading)
            }
            .pageBackground()
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { following = false }
            }
            .onChange(of: activeLine) { _, index in
                guard following, let index else { return }
                scroll(to: index, proxy: proxy)
            }
            .onChange(of: selection) { _, _ in
                updateActiveLine(at: player.elapsed)
                following = true
                if let activeLine { scroll(to: activeLine, proxy: proxy) } else { proxy.scrollTo(0, anchor: .top) }
            }
            .toolbar {
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
                            if let activeLine { scroll(to: activeLine, proxy: proxy) }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onReceive(player.$elapsed.removeDuplicates()) { updateActiveLine(at: $0) }
        .onChange(of: versions) { _, _ in updateActiveLine(at: player.elapsed) }
        .task(id: requestID) { await load() }
    }

    private func updateActiveLine(at seconds: Double) {
        let index = lyrics?.activeLineIndex(at: seconds)
        if activeLine != index { activeLine = index }
    }

    private func lyricText(_ text: String, active: Bool, synced: Bool) -> some View {
        Text(text).font(.title2.weight(.semibold))
            .foregroundStyle(active ? theme.accent : (synced ? theme.secondary : .white))
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2).frame(minHeight: 44, alignment: .leading)
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(index, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
        }
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
            if error as? GevunError == .server(0) {
                message = "This server doesn't support lyrics."
            } else {
                message = friendlyError(error)
            }
        }
        if revision == request { loading = false }
    }
}
