import SwiftUI

struct PlayerBackdrop: View {
    @EnvironmentObject private var appearance: ArtworkAppearance
    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [theme.playerPrimary, theme.playerSecondary, theme.playerPrimary], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                if let image = appearance.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .saturation(1.8).blur(radius: 65).opacity(0.55)
                }
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.12), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.5),
                        .init(color: .black.opacity(0.72), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
