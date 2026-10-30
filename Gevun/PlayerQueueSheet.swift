import SwiftUI
import GevunCore

struct PlayerQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PlayerQueueView(onSelect: { dismiss() })
                .background(AppBackground())
                .scrollContentBackground(.hidden)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 20).accessibilityHidden(true)
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .navigationTitle("Queue").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .listeningLinkPresentation()
        .downloadPresentation(fromPlayer: true)
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
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        }.scrollIndicators(.hidden).scrollEdgeEffectStyle(.soft, for: .all)
    }
}
