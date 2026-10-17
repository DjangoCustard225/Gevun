import SwiftUI
import GevunCore

struct DownloadSelection: Identifiable {
    let id = UUID()
    let songs: [Song]
    let album: Album?
    let instance: Instance
}

extension View {
    func downloadPresentation(fromPlayer: Bool = false) -> some View {
        modifier(DownloadPresentation(fromPlayer: fromPlayer))
    }
}

private struct DownloadPresentation: ViewModifier {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    let fromPlayer: Bool
    func body(content: Content) -> some View {
        content.sheet(
            item: Binding(
                get: { interface.expanded == fromPlayer ? store.downloadSelection : nil },
                set: { store.downloadSelection = $0 }
            )
        ) { selection in
            DownloadOptionsView(selection: selection).environment(store)
        }
    }
}
