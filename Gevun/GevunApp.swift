import SwiftUI

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

private enum AppTab: Hashable { case albums, artists, songs, settings, search }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @EnvironmentObject private var appearance: ArtworkAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = AppTab.albums
    @State private var searchQuery = ""
    @State private var searchPresented = false

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
                searchPresented = false; searchQuery = ""; selection = .albums
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
                        NavigationStack { LibraryView(category: .albums) }.id(store.sessionID)
                    }
                    Tab("Artists", systemImage: "person.2", value: .artists) {
                        NavigationStack { LibraryView(category: .artists) }.id(store.sessionID)
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
}
