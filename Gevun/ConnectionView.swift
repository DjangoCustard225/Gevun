import SwiftUI
import GevunCore

struct ConnectionView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var firstConnection = false
    var editing: Instance? = nil
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var path: [Field] = []
    @State private var initialized = false
    @State private var busy = false
    @State private var message: String?
    @State private var request: Task<Void, Never>?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case address, username, password, name
        var title: String {
            switch self {
            case .address: "Server address"
            case .username: "Username"
            case .password: "Password"
            case .name: "Instance name"
            }
        }
        var next: Self? {
            switch self {
            case .address: .username
            case .username: .password
            case .password: .name
            case .name: nil
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            page(.address)
                .navigationDestination(for: Field.self) { page($0) }
        }
        .interactiveDismissDisabled(busy)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if let editing {
                name = editing.name
                address = editing.url.absoluteString
                username = editing.username
                password = editing.password
            }
        }
        .onDisappear { request?.cancel() }
    }

    private func page(_ field: Field) -> some View {
        Form {
            Section {
                input(field)
            } header: {
                Text(field == .address ? "Navidrome server" : field.title)
            } footer: {
                switch field {
                case .address:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Include any base path; omit /rest.")
                        if address.lowercased().hasPrefix("http://") {
                            Text("HTTP is unencrypted. Use HTTPS for remote access.").foregroundStyle(.orange)
                        }
                    }
                case .username:
                    Text("Your Navidrome account username.")
                case .password:
                    Text("Use the password for your Navidrome account.")
                case .name:
                    Text("Optional. Leave blank to use your server's hostname.")
                }
            }.listRowBackground(theme.surface)

            if let message {
                Section {
                    Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                        .accessibilityLabel("Connection needs attention. \(message)")
                }.listRowBackground(theme.surface)
            }
        }
        .listSectionSpacing(.compact)
        .disabled(busy)
        .pageBackground()
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Button {
                advance(field)
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(theme.background) }
                    Text(busy ? "Connecting…" : field == .name ? (editing == nil ? "Sign in" : "Save") : "Continue")
                        .font(.headline)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))
            .foregroundStyle(theme.background)
            .disabled(busy || !canContinue(field))
            .frame(maxWidth: 520).padding(16).frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .navigationTitle(field == .address && firstConnection ? "Gevun" : field.title)
        .navigationBarTitleDisplayMode(field == .address && firstConnection ? .large : .inline)
        .navigationBarBackButtonHidden(busy)
        .defaultFocus($focus, field)
        .toolbar {
            if !firstConnection {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        request?.cancel()
                        dismiss()
                    }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("Done") { focus = nil }
            }
        }
    }

    @ViewBuilder private func input(_ field: Field) -> some View {
        switch field {
        case .address:
            TextField("https://music.example.com", text: $address)
                .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .address).submitLabel(.next).onSubmit { advance(.address) }
                .accessibilityLabel("Server URL")
        case .username:
            TextField("Username", text: $username)
                .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focus, equals: .username).submitLabel(.next).onSubmit { advance(.username) }
        case .password:
            SecureField("Password", text: $password)
                .textContentType(.password).focused($focus, equals: .password).submitLabel(.next)
                .onSubmit { advance(.password) }
        case .name:
            TextField("Name (optional)", text: $name)
                .focused($focus, equals: .name).submitLabel(.go).onSubmit { advance(.name) }
                .accessibilityLabel("Instance name, optional")
        }
    }

    private func canContinue(_ field: Field) -> Bool {
        switch field {
        case .address: !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .username: !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .password: !password.isEmpty
        case .name: true
        }
    }

    private func advance(_ field: Field) {
        guard !busy, field == (path.last ?? .address), canContinue(field) else { return }
        message = nil
        if field == .address {
            do {
                address = try Instance.serverURL(from: address).absoluteString
            } catch {
                message = friendlyError(error)
                return
            }
        }
        focus = nil
        if let next = field.next {
            path.append(next)
        } else {
            connect()
        }
    }

    private func connect() {
        guard !busy else { return }
        do {
            let instance = try Instance(
                id: editing?.id ?? UUID(), name: name, address: address, username: username, password: password)
            busy = true
            request = Task {
                do {
                    try await store.connect(instance)
                    busy = false
                    if !firstConnection { dismiss() }
                } catch {
                    busy = false
                    if !Task.isCancelled { message = friendlyError(error) }
                }
            }
        } catch { message = error.localizedDescription }
    }
}
