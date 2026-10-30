import SwiftUI
import UIKit
import Observation
import GevunCore

/// Menu actions send presentation requests to the screen that remains mounted after the menu closes.
@MainActor
@Observable
final class ListeningLinkPresenter {
    struct Request: Identifiable {
        let id = UUID()
        let ids: [String]
    }
    var request: Request?
}

extension View {
    func listeningLinkPresentation() -> some View { modifier(ListeningLinkPresentation()) }
}

private struct ListeningLinkPresentation: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var actions = ListeningLinkPresenter()

    func body(content: Content) -> some View {
        content
            .environment(actions)
            .sheet(item: $actions.request) { request in
                ListeningLinkView(ids: request.ids)
            }
            .onChange(of: store.sessionID) { _, _ in actions.request = nil }
    }
}

struct ServerShareButton: View {
    @Environment(ListeningLinkPresenter.self) private var actions
    let ids: [String]
    var body: some View {
        Button("Share listening link", systemImage: "square.and.arrow.up") {
            actions.request = ListeningLinkPresenter.Request(ids: ids)
        }.disabled(ids.isEmpty)
    }
}

private struct ListeningLinkView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    @State private var url: URL?
    @State private var message: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let url {
                ListeningLinkSheet(url: url, onComplete: { dismiss() }).ignoresSafeArea()
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if let message {
                            ContentUnavailableView {
                                Label("Couldn't create link", systemImage: "link")
                            } description: {
                                Text(message)
                            } actions: {
                                Button("Try again") { attempt += 1 }
                            }
                        } else {
                            ProgressView("Creating listening link")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    }
                }
            }
        }
        .task(id: attempt) {
            guard let api = store.api else { message = "Connect to your server to create a link."; return }
            message = nil
            do {
                let value = try await api.share(ids)
                guard !Task.isCancelled, store.api === api else { return }
                url = value
            } catch {
                if !Task.isCancelled { message = friendlyError(error) }
            }
        }
    }
}

private struct ListeningLinkSheet: UIViewControllerRepresentable {
    let url: URL
    let onComplete: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { onComplete() }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
