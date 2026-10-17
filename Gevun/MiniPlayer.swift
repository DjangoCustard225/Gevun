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
