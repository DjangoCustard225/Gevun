import SwiftUI

struct PlayerDetailSheet<Content: View>: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack { content }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .environment(\.appTheme, theme.oled)
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .downloadPresentation(fromPlayer: true)
    }
}
