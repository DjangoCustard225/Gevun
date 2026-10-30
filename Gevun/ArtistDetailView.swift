import SwiftUI
import GevunCore

struct ArtistDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    let artist: Artist
    @State private var detail: Artist?
    @State private var info: ArtistInfo?
    @State private var biography: String?
    @State private var showsAbout = false
    @State private var loading = true
    @State private var infoLoading = true
    @State private var message: String?
    @State private var infoFailed = false
    @State private var revision = UUID()

    private var albums: [Album] { detail?.albums ?? [] }
    private var related: [Artist] { info?.relatedArtists(excluding: artist.id) ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ArtworkHeaderView(id: detail?.coverArt ?? artist.coverArt)
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        Text(detail?.name ?? artist.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                        about
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Albums")
                        if let message { ErrorCard(message: message) { Task { await load() } } }
                        if loading { ProgressView().frame(maxWidth: .infinity).padding(16) }
                        if !loading && albums.isEmpty && message == nil {
                            ContentUnavailableView("No albums available", systemImage: "square.stack")
                        }
                        AlbumGrid(albums: albums)
                    }
                    if !related.isEmpty { relatedSection }
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28)
            }.frame(maxWidth: 640).frame(maxWidth: .infinity)
                .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline).pageBackground()
        .modifier(ArtworkScrollEdges())
        .tint(.white)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsAbout) {
            aboutSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: "\(store.sessionID):\(artist.id)") { await load() }
        .listeningLinkPresentation()
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            if biography != nil {
                Button {
                    showsAbout = true
                } label: {
                    aboutPreview
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(detail?.name ?? artist.name)")
                .accessibilityHint("Open the full artist description")
            } else {
                aboutPreview
            }
            if info?.lastFMURL != nil || info?.musicBrainzURL != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { profileLinks }
                    VStack(alignment: .leading, spacing: 8) { profileLinks }
                }.font(.caption.weight(.medium)).foregroundStyle(theme.secondary)
            }
        }
    }

    private var aboutPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let biography {
                Text(verbatim: biography).font(.callout).foregroundStyle(theme.secondary)
                    .lineSpacing(3).lineLimit(4).multilineTextAlignment(.leading)
            } else if infoLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading artist details…").font(.subheadline).foregroundStyle(theme.secondary)
                }
            } else if infoFailed {
                HStack {
                    Text("Artist details couldn’t load.").font(.subheadline).foregroundStyle(theme.secondary)
                    Spacer()
                    Button("Retry") { Task { await load() } }.font(.subheadline.weight(.semibold))
                }
            } else {
                Text("No artist description available from your server.")
                    .font(.subheadline).foregroundStyle(theme.secondary)
            }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }

    private var aboutSheet: some View {
        ScrollView {
            if let biography {
                Text(verbatim: biography).font(.body).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 24)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder private var profileLinks: some View {
        if let url = info?.lastFMURL {
            Link(destination: url) { Label("Last.fm", systemImage: "arrow.up.right").frame(minHeight: 36) }
                .accessibilityHint("Open the artist’s Last.fm profile")
        }
        if let url = info?.musicBrainzURL {
            Link(destination: url) { Label("MusicBrainz", systemImage: "arrow.up.right").frame(minHeight: 36) }
                .accessibilityHint("Open the artist’s MusicBrainz profile")
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Similar artists")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(related) { value in
                        NavigationLink {
                            ArtistDetailView(artist: value)
                        } label: {
                            VStack(spacing: 8) {
                                ArtworkView(id: value.coverArt, size: 300, cornerRadius: 56)
                                    .frame(width: 112, height: 112).clipShape(Circle())
                                Text(value.name).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                                    .lineLimit(2).frame(width: 112)
                            }.foregroundStyle(.primary)
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden).contentMargins(.horizontal, 20, for: .scrollContent)
                .padding(.horizontal, -20).scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        let token = UUID()
        revision = token
        detail = nil
        info = nil
        biography = nil
        loading = true
        infoLoading = true
        message = nil
        infoFailed = false
        async let library: Void = loadAlbums(api, token: token)
        async let metadata: Void = loadInfo(api, token: token)
        _ = await (library, metadata)
    }

    private func isCurrent(_ api: NavidromeAPI, _ token: UUID) -> Bool {
        !Task.isCancelled && store.api === api && revision == token
    }

    private func loadAlbums(_ api: NavidromeAPI, token: UUID) async {
        defer { if revision == token { loading = false } }
        do {
            let value = try await api.artist(artist.id)
            guard isCurrent(api, token) else { return }
            detail = value
        } catch {
            guard isCurrent(api, token) else { return }
            message = friendlyError(error)
        }
    }

    private func loadInfo(_ api: NavidromeAPI, token: UUID) async {
        defer { if revision == token { infoLoading = false } }
        do {
            let value = try await api.artistInfo(artist.id)
            guard isCurrent(api, token) else { return }
            info = value
            biography = value.description
        } catch {
            guard isCurrent(api, token) else { return }
            infoFailed = true
        }
    }
}
