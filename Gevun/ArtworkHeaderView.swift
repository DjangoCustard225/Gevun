import SwiftUI

struct ArtworkHeaderView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    let id: String?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
            // Cover fractional-pixel gaps while the native scroll view restores its top inset.
            let overlap = 1 / max(1, displayScale)
            let side = width + pull + 2 * overlap
            let extensionHeight: CGFloat = 140
            ZStack(alignment: .top) {
                // Continue the artwork's colors beneath the title before fading into OLED black.
                artwork.frame(width: side, height: side)
                    .scaleEffect(x: 1.12, y: 1 + (extensionHeight + 64) / max(1, side), anchor: .top)
                    .blur(radius: 32)
                    .frame(width: side, height: side + extensionHeight, alignment: .top)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.32),
                                .init(color: .white, location: 0.55),
                                .init(color: .white, location: 0.78),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    }
                artwork.frame(width: side, height: side)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.5),
                                .init(color: .white.opacity(0.7), location: 0.72),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    }
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.48),
                        .init(color: theme.background.opacity(0.15), location: 0.65),
                        .init(color: theme.background.opacity(0.7), location: 0.85),
                        .init(color: theme.background, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: side + extensionHeight)
                LinearGradient(colors: [.black.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
            }
            .frame(width: side, height: side + extensionHeight).clipped()
            .frame(width: width, height: width, alignment: .top)
            .offset(y: -pull - overlap)
        }.aspectRatio(1, contentMode: .fit)
            .transaction { $0.animation = nil }
            .accessibilityHidden(true)
    }

    private var artwork: some View {
        ArtworkView(id: id, size: 1200, cornerRadius: 0)
    }

}

struct ArtworkScrollEdges: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Full-bleed artwork handles the top edge itself. Keep its viewport fixed as
            // navigation controls minimize, and avoid switching a second edge backdrop.
            .toolbarMinimizationSafeAreaAdjustment(.disabled, for: .navigationBar)
            .scrollEdgeEffectHidden(true, for: .top)
    }
}
