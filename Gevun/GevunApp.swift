import SwiftUI
import GevunCore

@main
struct GevunApp: App {
    @UIApplicationDelegateAdaptor(DownloadAppDelegate.self) private var delegate
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environmentObject(store.player)
                .environmentObject(store.player.interface)
                .environmentObject(store.appearance)
                .preferredColorScheme(.dark)
        }
    }
}

private enum AppTab: Hashable {
    case library, settings, search
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @EnvironmentObject private var appearance: ArtworkAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = AppTab.library
    @State private var searchQuery = ""
    @State private var searchPresented = false

    var body: some View {
        @Bindable var store = store
        appContent
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { store.player.listening.checkpoint(urgent: true) }
            }
            .downloadPresentation()
            .background {
                PlayerPresentation(store: store, isPresented: interface.expanded, reduceMotion: reduceMotion)
            }
            .allowsHitTesting(!interface.expanded)
            .accessibilityHidden(interface.expanded)
            .background(AppBackground())
            .sheet(isPresented: $store.showConnection) {
                ConnectionView().environment(store).presentationDragIndicator(.visible)
            }
            .noticeAlert()
            .environment(\.appTheme, appearance.theme.oled)
            .tint(appearance.theme.accent)
            // Song menus inside the player's queue sheet present their own prompt.
            .newPlaylistPrompt(isActive: !interface.expanded)
            .task(id: store.sessionID) { await store.ensurePlaylists() }
            .onChange(of: store.sessionID) { _, _ in
                store.downloadSelection = nil
                searchPresented = false; searchQuery = ""; selection = .library
            }
            .task(id: "\(interface.expanded):\(store.sessionID):\(interface.current?.coverArt ?? "")") {
                guard !interface.expanded else { return }
                await appearance.update(
                    coverArt: interface.current?.coverArt, api: store.api, cache: store.artwork,
                    reduceMotion: reduceMotion)
            }
    }

    private var appContent: some View {
        Group {
            if store.instances.isEmpty {
                ConnectionView(firstConnection: true)
            } else {
                TabView(selection: $selection) {
                    Tab("Library", systemImage: "music.note.square.stack", value: AppTab.library) {
                        AlbumNavigationStack { LibraryHomeView() }.id(store.sessionID)
                    }
                    Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                        NavigationStack { SettingsView() }
                    }
                    Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                        AlbumNavigationStack { MusicSearchView(query: $searchQuery) }
                            .searchable(
                                text: $searchQuery, isPresented: $searchPresented, prompt: "Albums, artists, tracks"
                            )
                            .id(store.sessionID)
                    }
                }
                .tabViewSearchActivation(.searchTabSelection)
                .onChange(of: selection) { _, tab in
                    if tab != .search { searchPresented = false }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: interface.current != nil) {
                    MiniPlayer()
                }
            }
        }
    }
}

extension View {
    /// Shows `AppStore.notice`.
    fileprivate func noticeAlert() -> some View { modifier(NoticeAlert()) }
}

private struct NoticeAlert: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        @Bindable var store = store
        content.alert("Gevun", isPresented: $store.notice.isPresent()) {
            Button("OK", role: .cancel) { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }
}
