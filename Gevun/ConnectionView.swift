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
    @State private var showName = false
    @State private var busy = false
    @State private var message: String?
    @State private var request: Task<Void, Never>?
    @FocusState private var focus: Field?
    private enum Field { case address, username, password }

    var body: some View {
        Form {
            Section {
                TextField("https://music.example.com", text: $address)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .address).submitLabel(.next).onSubmit { focus = .username }
                    .accessibilityLabel("Server URL")
            } header: {
                Text("Navidrome server")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Include any base path; omit /rest.")
                    if address.lowercased().hasPrefix("http://") {
                        Text("HTTP is unencrypted. Use HTTPS for remote access.").foregroundStyle(.orange)
                    }
                }
            }.listRowBackground(theme.surface)

            Section("Account") {
                TextField("Username", text: $username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .username).submitLabel(.next).onSubmit { focus = .password }
                SecureField("Password", text: $password)
                    .textContentType(.password).focused($focus, equals: .password).submitLabel(.go).onSubmit {
                        connect()
                    }
            }.listRowBackground(theme.surface)

            Section {
                DisclosureGroup("Instance name", isExpanded: $showName) {
                    TextField("Name (optional)", text: $name)
                }
            }.listRowBackground(theme.surface)

            if let message {
                Section {
                    Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                        .accessibilityLabel("Connection failed. \(message)")
                }.listRowBackground(theme.surface)
            }
        }
        .listSectionSpacing(.compact)
        .disabled(busy)
        .pageBackground()
        .safeAreaInset(edge: .bottom) {
            Button(action: connect) {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(theme.background) }
                    Text(busy ? "Connecting…" : editing == nil ? "Sign in" : "Save").font(.headline)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16)).foregroundStyle(
                theme.background
            )
            .disabled(
                busy || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
            )
            .frame(maxWidth: 520).padding(16).frame(maxWidth: .infinity)
            .background(theme.background)
        }
        .navigationTitle(firstConnection ? "Gevun" : editing == nil ? "Add instance" : "Edit instance")
        .navigationBarTitleDisplayMode(firstConnection ? .large : .inline)
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
        .interactiveDismissDisabled(busy)
        .onAppear {
            if let editing {
                name = editing.name
                address = editing.url.absoluteString
                username = editing.username
                password = editing.password
                showName = true
            }
        }
        .onDisappear { request?.cancel() }
    }

    private func connect() {
        guard !busy else { return }
        focus = nil
        message = nil
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
