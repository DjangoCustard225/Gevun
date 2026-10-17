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

private enum AppTab: Hashable { case albums, artists, songs, search, settings }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @EnvironmentObject private var appearance: ArtworkAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = AppTab.albums
    @State private var searchQuery = ""
    @State private var searchPresented = false
    @State private var albumPath = NavigationPath()
    @State private var artistPath = NavigationPath()

    var body: some View {
        @Bindable var store = store
        appContent
            .downloadPresentation()
            .background {
                PlayerPresentation(store: store, isPresented: interface.expanded, reduceMotion: reduceMotion)
            }
            .allowsHitTesting(!interface.expanded)
            .accessibilityHidden(interface.expanded)
            .background(AppBackground())
            .sheet(isPresented: $store.showConnection) {
                ConnectionView()
                    .environment(store)
                    .presentationDragIndicator(.visible)
            }
            .alert("Gevun", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } }))
        {
            Button("OK", role: .cancel) { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
            .environment(\.appTheme, appearance.theme.oled)
            .tint(appearance.theme.accent)
            .onChange(of: store.sessionID) { _, _ in
                store.downloadSelection = nil
                store.playerDestination = nil
                albumPath = NavigationPath(); artistPath = NavigationPath()
                searchPresented = false; searchQuery = ""; selection = .albums
            }
            .onChange(of: interface.expanded) { _, expanded in
                if !expanded { openPlayerDestination() }
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
                    Tab("Albums", systemImage: "square.stack", value: .albums) {
                        NavigationStack(path: $albumPath) {
                            LibraryView(category: .albums)
                                .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
                        }.id(store.sessionID)
                    }
                    Tab("Artists", systemImage: "person.2", value: .artists) {
                        NavigationStack(path: $artistPath) {
                            LibraryView(category: .artists)
                                .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
                        }.id(store.sessionID)
                    }
                    Tab("Songs", systemImage: "music.note", value: .songs) {
                        NavigationStack { LibraryView(category: .songs) }.id(store.sessionID)
                    }
                    Tab("Settings", systemImage: "gearshape", value: .settings) {
                        NavigationStack { SettingsView() }
                    }
                    Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                        NavigationStack { MusicSearchView(query: $searchQuery) }
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

    private func openPlayerDestination() {
        guard let destination = store.playerDestination else { return }
        store.playerDestination = nil
        searchPresented = false
        switch destination {
        case .album(let album):
            albumPath = NavigationPath([album])
            selection = .albums
        case .artist(let artist):
            artistPath = NavigationPath([artist])
            selection = .artists
        }
    }
}
