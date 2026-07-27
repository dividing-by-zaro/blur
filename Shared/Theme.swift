import SwiftUI

/// The whole app is light-mode only, so every colour here is a fixed literal
/// rather than an asset that adapts. Keeping them in one place means the widget
/// extension renders with exactly the same palette as the app.
enum Blur {

    // MARK: Accents

    static let pink   = Color(red: 1.00, green: 0.11, blue: 0.51)   // #FF1C82
    static let green  = Color(red: 0.63, green: 0.95, blue: 0.04)   // #A0F109 — the icon's lime
    static let yellow = Color(red: 1.00, green: 0.79, blue: 0.05)   // #FFC90D

    // MARK: Neutrals

    /// Warm off-white page background. Pure white makes the accents read as harsh.
    static let canvas     = Color(red: 0.988, green: 0.984, blue: 0.976)
    static let surface    = Color.white
    static let ink        = Color(red: 0.09, green: 0.08, blue: 0.12)
    static let inkSoft    = Color(red: 0.42, green: 0.40, blue: 0.47)
    static let inkFaint   = Color(red: 0.66, green: 0.64, blue: 0.70)
    static let hairline   = Color(red: 0.91, green: 0.90, blue: 0.92)

    // MARK: Gradients

    /// The signature pink → yellow → lime sweep. Used sparingly: one dominant
    /// gradient element per screen, everything else is neutral.
    ///
    /// Yellow sits in the middle deliberately. Pink and lime are near-opposites,
    /// so interpolating straight between them passes through olive sludge;
    /// routing through yellow keeps every step of the ramp a colour we chose.
    static let sweep = LinearGradient(
        colors: [pink, yellow, green],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let sweepDiagonal = LinearGradient(
        colors: [pink, yellow, green],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent for a given position in a list, cycling through the three accents so
    /// a stack of rows reads as a spectrum instead of a single flat colour.
    static func accent(_ index: Int) -> Color {
        [pink, green, yellow][abs(index) % 3]
    }

    /// Two rules govern every accent, because lime and yellow are light colours
    /// and pink is a dark one:
    ///
    /// `onAccent` — type sitting **on** an accent fill. Lime and yellow can't
    /// carry white (1.4:1 and 1.6:1); against ink they clear 15:1. Pink is dark
    /// enough to do the opposite.
    static func onAccent(_ color: Color) -> Color {
        color == pink ? .white : ink
    }

    /// `onCanvas` — an accent used as **type or a hairline mark** on the light
    /// page. Lime on white is 1.4:1 and yellow 1.6:1, so both collapse to ink
    /// and stay fills only. Pink reads at 3.7:1 and survives at bold weights.
    ///
    /// Accents are still free to fill shapes — this governs strokes and glyphs,
    /// where there's no mass of colour to carry the meaning.
    static func onCanvas(_ color: Color) -> Color {
        color == pink ? pink : ink
    }
}

// MARK: - Type

extension Font {
    /// Century Gothic isn't on iOS. Futura is the geometric sans it was drawn
    /// from — circular bowls, single-storey `a`, the same wide even rhythm —
    /// and it ships with the system, so no font file to bundle or licence.
    ///
    /// Only two usable weights exist (Medium and Bold), so anything semibold or
    /// heavier maps to Bold and everything lighter to Medium.
    private static func geometric(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let face: String
        switch weight {
        case .ultraLight, .thin, .light, .regular, .medium: face = "Futura-Medium"
        default:                                            face = "Futura-Bold"
        }
        // `fixedSize` rather than `size`: these sit in fixed-height tiles and
        // rows, so Dynamic Type scaling would overflow them.
        return .custom(face, fixedSize: size)
    }

    /// Tabular figures matter everywhere a number ticks (clocks, countdowns) —
    /// without them the layout jitters on every digit change. Futura's digits
    /// are already uniform width in both cuts, so no `.monospacedDigit()`
    /// needed (it's a no-op on custom fonts anyway).
    static func blurDigits(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        geometric(size, weight)
    }

    static func blurRounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        geometric(size, weight)
    }
}

// MARK: - Surfaces

/// Soft raised card. The shadow is warm-tinted rather than grey so it sits in
/// the same colour world as the accents.
struct BlurCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Blur.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Blur.hairline, lineWidth: 1)
            )
            .shadow(color: Color(red: 0.55, green: 0.35, blue: 0.30).opacity(0.07),
                    radius: 14, x: 0, y: 6)
    }
}

extension View {
    func blurCard(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        modifier(BlurCard(padding: padding, radius: radius))
    }

    /// A coloured glow behind an element. In light mode the glow has to stay
    /// at very low opacity or it turns muddy.
    func blurGlow(_ color: Color, radius: CGFloat = 18, opacity: Double = 0.45) -> some View {
        shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 4)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var accent: Color = Blur.pink
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(accent)
                .frame(width: 4, height: 15)

            Text(title.uppercased())
                .font(.blurRounded(13, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Blur.ink)

            if let count {
                Text("\(count)")
                    .font(.blurRounded(11, weight: .bold))
                    .foregroundStyle(Blur.onCanvas(accent))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.13)))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Buttons

/// Primary filled action — the icon's move: black capsule, lime label. A
/// gradient is no longer usable here, since pink→lime interpolates through mud
/// and no single label colour stays legible across the sweep.
struct BlurPrimaryButtonStyle: ButtonStyle {
    var fill: Color = Blur.ink
    var label: Color = Blur.green

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blurRounded(17, weight: .bold))
            .foregroundStyle(label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(fill))
            .blurGlow(fill, radius: 16, opacity: 0.22)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

/// Quiet action — neutral surface, coloured label.
struct BlurSecondaryButtonStyle: ButtonStyle {
    var tint: Color = Blur.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blurRounded(17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(Blur.surface))
            .overlay(Capsule().strokeBorder(Blur.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}
