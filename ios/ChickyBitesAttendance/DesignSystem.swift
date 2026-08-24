import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { L10n.text(rawValue.capitalized) }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CBTheme {
    static let navy950 = Color(hex: 0x04102F)
    static let navy900 = Color(hex: 0x081F59)
    static let navy800 = Color(hex: 0x17428F)
    static let cream100 = Color(hex: 0xFFF9ED)
    static let cream200 = Color(hex: 0xF0E4CF)
    static let orange = Color(hex: 0xFFA515)
    static let gold = Color(hex: 0xFFD16A)

    static let text = Color.adaptive(light: 0x101B3E, dark: 0xFFF9EE)
    static let muted = Color.adaptive(light: 0x59627D, dark: 0xB7C0D7)
    static let surface = Color.adaptive(light: 0xFFFDF7, dark: 0x101B37)
    static let surfaceElevated = Color.adaptive(light: 0xFFFFFF, dark: 0x162448)
    static let pageTop = Color.adaptive(light: 0xFAF4E9, dark: 0x07132E)
    static let pageBottom = Color.adaptive(light: 0xEEE3D2, dark: 0x030A1C)
    static let divider = Color.adaptive(light: 0xD6CDBD, dark: 0x344267)
    static let success = Color.adaptive(light: 0x087A49, dark: 0x59DEA1)
    static let danger = Color.adaptive(light: 0xBA343C, dark: 0xFF8087)
    static let warning = Color.adaptive(light: 0x855300, dark: 0xFFC75E)
    static let info = Color.adaptive(light: 0x17428F, dark: 0x82AEFF)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(
                red: CGFloat(((traits.userInterfaceStyle == .dark ? dark : light) >> 16) & 0xFF) / 255,
                green: CGFloat(((traits.userInterfaceStyle == .dark ? dark : light) >> 8) & 0xFF) / 255,
                blue: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct AppBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(hex: 0x02081C), CBTheme.navy950, Color(hex: 0x0B2458)]
                : [Color(hex: 0x06173F), CBTheme.navy900, Color(hex: 0x12377E)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct BrandedBackground<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AppBackdrop()
            content
        }
    }
}

struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func cbGlass(
        cornerRadius: CGFloat = 24,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(
                .clear.tint(tint).interactive(interactive),
                in: .rect(cornerRadius: cornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
        }
    }

    @ViewBuilder
    func cbPrimaryButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(CBTheme.orange)
                .foregroundStyle(CBTheme.navy950)
        } else {
            buttonStyle(.borderedProminent)
                .tint(CBTheme.orange)
                .foregroundStyle(CBTheme.navy950)
        }
    }

    @ViewBuilder
    func cbSecondaryButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    func premiumCardPadding(_ value: CGFloat = 18) -> some View {
        padding(value)
    }
}

struct BrandLockup: View {
    @Environment(\.colorScheme) private var colorScheme
    var compact = false
    var onDarkBackground = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            Image(onDarkBackground || colorScheme == .dark ? "BrandLogo" : "BrandLogoLight")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 48 : 96, height: compact ? 48 : 96)

            if !compact {
                Text("CB Employee Hub")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(onDarkBackground ? .white : CBTheme.text)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?
    var symbol: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CBTheme.orange)
                    .frame(width: 36, height: 36)
                    .background(CBTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text(title))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(CBTheme.text)
                // Subtitles are intentionally omitted to keep operational screens concise.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(CBTheme.info)
                .frame(width: 64, height: 64)
                .background(CBTheme.info.opacity(0.11), in: RoundedRectangle(cornerRadius: 20))
            Text(L10n.text(title))
                .font(.headline)
                .foregroundStyle(CBTheme.text)
            Text(L10n.text(message))
                .font(.subheadline)
                .foregroundStyle(CBTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .cbGlass(cornerRadius: 24, tint: CBTheme.surface.opacity(0.12))
    }
}
