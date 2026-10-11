import SwiftUI
import GevunCore

struct AppTheme {
    let background: Color
    let surface: Color
    let elevated: Color
    let accent: Color
    let secondary: Color
    let border: Color
    let playerPrimary: Color
    let playerSecondary: Color
    let usesOLEDBackground: Bool

    var oled: AppTheme {
        AppTheme(
            background: .black, surface: Color(white: 0.055), elevated: Color(white: 0.095),
            accent: accent, secondary: Color(white: 0.67), border: .white.opacity(0.08),
            playerPrimary: playerPrimary, playerSecondary: playerSecondary, usesOLEDBackground: true)
    }

    static let fallback = AppTheme(
        background: Theme.background, surface: Theme.surface, elevated: Theme.elevated,
        accent: Theme.defaultAccent, secondary: Theme.secondary, border: Theme.border,
        playerPrimary: Theme.elevated, playerSecondary: Theme.background)

    private static func color(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> Color {
        Color(uiColor: UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1))
    }

    init(hue: CGFloat, secondaryHue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        usesOLEDBackground = false
        let chroma = saturation < 0.12 ? 0 : min(0.95, max(0.65, saturation * 1.4))
        background = Self.color(hue: hue, saturation: chroma * 0.95, brightness: 0.13)
        surface = Self.color(hue: hue, saturation: chroma * 0.85, brightness: 0.22)
        elevated = Self.color(hue: hue, saturation: chroma * 0.95, brightness: 0.34)
        // Lighten the accent and secondary text so all hues remain readable against dark surfaces.
        accent = Self.color(hue: hue, saturation: chroma * 0.55, brightness: 1)
        secondary = Self.color(hue: hue, saturation: chroma * 0.14, brightness: 0.8)
        border = accent.opacity(0.13)
        playerPrimary = Self.color(
            hue: hue, saturation: chroma, brightness: chroma == 0 ? 0.38 : min(0.9, max(0.65, brightness)))
        playerSecondary = Self.color(hue: secondaryHue, saturation: chroma, brightness: chroma == 0 ? 0.18 : 0.65)
    }

    private init(
        background: Color, surface: Color, elevated: Color, accent: Color, secondary: Color, border: Color,
        playerPrimary: Color, playerSecondary: Color, usesOLEDBackground: Bool = false
    ) {
        self.background = background
        self.surface = surface
        self.elevated = elevated
        self.accent = accent
        self.secondary = secondary
        self.border = border
        self.playerPrimary = playerPrimary
        self.playerSecondary = playerSecondary
        self.usesOLEDBackground = usesOLEDBackground
    }

    init(image: UIImage) {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let source = image.cgImage else {
            self = .fallback
            return
        }
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else {
            self = .fallback
            return
        }
        var weights = [CGFloat](repeating: 0, count: 12)
        var hues = weights, saturations = weights, brightnesses = weights
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let color = UIColor(
                red: CGFloat(pixels[offset]) / 255 / alpha,
                green: CGFloat(pixels[offset + 1]) / 255 / alpha,
                blue: CGFloat(pixels[offset + 2]) / 255 / alpha, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            guard saturation > 0.12, brightness > 0.12 else { continue }
            let bucket = min(11, Int(hue * 12))
            let weight = saturation * saturation * brightness
            weights[bucket] += weight
            hues[bucket] += hue * weight
            saturations[bucket] += saturation * weight
            brightnesses[bucket] += brightness * weight
        }
        guard let dominant = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[dominant] > 0 else {
            self.init(hue: 0, secondaryHue: 0, saturation: 0, brightness: 0.38)
            return
        }
        let contrasting =
            weights.indices.filter {
                let distance = abs($0 - dominant)
                return min(distance, 12 - distance) >= 3 && weights[$0] > weights[dominant] * 0.08
            }.max(by: { weights[$0] < weights[$1] }) ?? dominant
        self.init(
            hue: hues[dominant] / weights[dominant], secondaryHue: hues[contrasting] / weights[contrasting],
            saturation: saturations[dominant] / weights[dominant],
            brightness: brightnesses[dominant] / weights[dominant])
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.fallback
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

@MainActor
final class ArtworkAppearance: ObservableObject {
    @Published private(set) var theme = AppTheme.fallback
    @Published private(set) var image: UIImage?
    private var revision = UUID()
    private weak var appliedAPI: NavidromeAPI?
    private var appliedCoverArt: String?

    func update(coverArt: String?, api: NavidromeAPI?, cache: ArtworkCache, reduceMotion: Bool) async {
        let request = UUID()
        revision = request
        guard let coverArt, let api else {
            appliedAPI = nil
            appliedCoverArt = nil
            apply(nil, reduceMotion: reduceMotion)
            return
        }
        // Opening/closing the player must not reapply an identical palette to the native accessory.
        if api === appliedAPI, coverArt == appliedCoverArt, image != nil { return }
        let image = await cache.image(id: coverArt, api: api, size: 1200)
        guard revision == request, !Task.isCancelled else { return }
        appliedAPI = api
        appliedCoverArt = coverArt
        apply(image, reduceMotion: reduceMotion)
    }

    private func apply(_ image: UIImage?, reduceMotion: Bool) {
        let theme = image.map(AppTheme.init) ?? .fallback
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            self.image = image
            self.theme = theme
        }
    }
}

struct AppBackground: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        Group {
            if theme.usesOLEDBackground {
                theme.background
            } else {
                LinearGradient(
                    colors: [theme.elevated, theme.surface, theme.background],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .background(theme.background)
            }
        }.ignoresSafeArea()
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
