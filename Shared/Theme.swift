import SwiftUI
import UIKit

/// The whole app is light-mode only, so every colour here is a fixed literal
/// rather than an asset that adapts. Keeping them in one place means the widget
/// extension renders with exactly the same palette as the app.
///
/// The palette is warm-neutral: a sand page, with ivory and charcoal cards
/// sitting on it.
///
/// Every accent is a **pair** — a light form that lives on charcoal and a dark
/// form of the same hue that lives on ivory — because no single mid-tone reads
/// against both a near-black card and a near-white one. `onCharcoal` picks the
/// light form and `onCanvas` picks the dark form, so a call site names the hue
/// once and the surface decides which end of the pair it gets. Three hues are in
/// the rotation: denim, lilac, and tan.
///
/// Gold is deliberately *not* in the rotation. It's the loudest thing in the
/// palette, and a colour that loud stops meaning anything once it's also the
/// default button, the default glyph, and every third card. It's kept for the
/// two places that should actually shout — a warning, and a timer that's
/// finished ringing.
enum Blur {

    // MARK: Accents — light form / dark form

    /// Denim. The dark form of the blue pair; also the app's overall tint.
    static let blue = Color(red: 0.169, green: 0.353, blue: 0.627)   // #2B5AA0
    /// Pale denim. The light form — type and marks on a charcoal card (8.8:1).
    static let blueSoft = Color(red: 0.663, green: 0.761, blue: 0.910)   // #A9C2E8

    /// Lavender. The light form of the purple pair: a fill on ivory that carries
    /// ink at 8.4:1, and type on charcoal at 7.7:1.
    static let lilac = Color(red: 0.725, green: 0.682, blue: 0.863)   // #B9AEDC
    /// Lavender's dark form — the colour it becomes as type on ivory (6.8:1).
    static let plum = Color(red: 0.357, green: 0.294, blue: 0.576)   // #5B4B93

    /// Warm tan. The light form of the neutral-warm pair; the palette's way of
    /// putting colour on a card without putting a hue on it.
    static let tan = Color(red: 0.804, green: 0.733, blue: 0.604)   // #CDBB9A
    /// Tan's dark form as type on ivory (5.0:1).
    static let taupe = Color(red: 0.490, green: 0.408, blue: 0.267)   // #7D6844

    /// The one mid-tone, and the only accent that isn't a pair: it clears 3:1
    /// against ivory *and* 4.2:1 against charcoal, so it's what gets used for a
    /// graphical mark — an arc, a track — that has to read on either surface
    /// without being swapped out. Reads as light blue against the dark cards and
    /// as light purple against the sand.
    static let periwinkle = Color(red: 0.420, green: 0.498, blue: 0.800)   // #6B7FCC

    /// Gold, and its dark form. Sparingly: warnings, and the ringing state.
    static let yellow = Color(red: 0.953, green: 0.769, blue: 0.235)   // #F3C43C
    static let amber  = Color(red: 0.541, green: 0.392, blue: 0.031)   // #8A6408
    /// Washed gold for the warning banner's field.
    static let yellowSoft = Color(red: 0.984, green: 0.906, blue: 0.659)   // #FBE7A8

    /// Destructive, and its light form for charcoal. Warm enough to belong to
    /// the sand family rather than arriving from a system palette; the dark form
    /// reads as type on ivory at 5.7:1, the light one on charcoal at 7.5:1.
    static let clay      = Color(red: 0.643, green: 0.267, blue: 0.180)   // #A4442E
    static let clayLight = Color(red: 0.910, green: 0.627, blue: 0.549)   // #E8A08C

    // MARK: Neutrals

    /// Warm sand page. Everything else is layered over this.
    static let canvas = Color(red: 0.906, green: 0.875, blue: 0.812)   // #E7DFCF

    /// The deeper sand used in the backdrop's blurred fields.
    static let canvasDeep = Color(red: 0.863, green: 0.820, blue: 0.733)   // #DCD1BB

    /// Light card. Not pure white — white against sand reads as a hole.
    static let surface = Color(red: 0.984, green: 0.969, blue: 0.937)   // #FBF7EF

    /// Dark card. Warm near-black, so it sits in the same colour world as the
    /// sand rather than looking like a system dark-mode panel dropped in.
    static let charcoal = Color(red: 0.137, green: 0.129, blue: 0.118)   // #23211E

    /// One step up from charcoal, for wells and tracks *inside* a dark card.
    static let charcoalSoft = Color(red: 0.196, green: 0.184, blue: 0.165)   // #322F2A

    static let ink      = Color(red: 0.106, green: 0.102, blue: 0.090)   // #1B1A17
    static let inkSoft  = Color(red: 0.357, green: 0.337, blue: 0.298)   // #5B564C
    /// Faintest usable ink. Held at 4.9:1 on ivory rather than going lighter —
    /// every label in this app has to survive being read, including the small
    /// uppercase ones.
    static let inkFaint = Color(red: 0.451, green: 0.424, blue: 0.365)   // #736C5D
    static let hairline = Color(red: 0.847, green: 0.812, blue: 0.741)   // #D8CFBD

    // MARK: On charcoal

    static let onDark     = Color(red: 0.965, green: 0.945, blue: 0.902)   // #F6F1E6
    /// Secondary type on charcoal, 6.7:1.
    static let onDarkSoft = Color(red: 0.675, green: 0.651, blue: 0.604)   // #ACA69A
    /// Hairlines and tracks on charcoal.
    static let onDarkLine = Color.white.opacity(0.14)

    // MARK: Gradients

    /// The page wash: cool sand at the top settling into warm sand at the
    /// bottom, which is the gradient the reference runs down each phone frame.
    static let page = LinearGradient(
        colors: [
            Color(red: 0.914, green: 0.902, blue: 0.878),
            canvas,
            Color(red: 0.914, green: 0.863, blue: 0.761)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The fill gradient for large graphical marks — the next-alarm ring. Runs periwinkle into indigo so a long stroke has some
    /// depth; both ends clear 3:1 on ivory.
    static let wave = LinearGradient(
        colors: [Color(red: 0.510, green: 0.588, blue: 0.867), periwinkle,
                 Color(red: 0.333, green: 0.400, blue: 0.720)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Accent resolution

    /// The three hues in the rotation, named by their light form. A call site
    /// passes one of these and lets the surface resolve it.
    private static let lightForms: [Color] = [blueSoft, lilac, tan, yellow,
                                              clayLight, periwinkle]

    /// Accent for a given position in a list. Denim, lilac, tan — cycled so a
    /// stack of cards reads as a spectrum instead of one flat colour.
    static func accent(_ index: Int) -> Color {
        [blue, lilac, tan][abs(index) % 3]
    }

    /// Type sitting **on** an accent fill. The light forms carry ink, the dark
    /// forms carry the cream.
    static func onAccent(_ color: Color) -> Color {
        lightForms.contains(color) ? ink : onDark
    }

    /// An accent used as **type or a hairline mark** on the sand page: the pair
    /// resolves to its dark form. Periwinkle and charcoal already clear the bar
    /// on ivory and pass through unchanged.
    static func onCanvas(_ color: Color) -> Color {
        switch color {
        case blueSoft: return blue
        case lilac:    return plum
        case tan:      return taupe
        case yellow:   return amber
        case clayLight: return clay
        default:       return color
        }
    }

    /// The same for a charcoal card: the pair resolves to its light form.
    static func onCharcoal(_ color: Color) -> Color {
        switch color {
        case blue, blueSoft: return blueSoft
        case plum, lilac:    return lilac
        case taupe, tan:     return tan
        case amber, yellow:  return yellow
        case clay, clayLight: return clayLight
        case charcoal, ink:  return onDark
        default:             return color
        }
    }
}

// MARK: - Type

extension Font {

    /// Avenir Next. The reference sets everything in a geometric sans with
    /// circular bowls and a wide even rhythm; Avenir is that, but drawn with a
    /// tall x-height and open apertures, which is what keeps a 12pt label
    /// readable where a true geometric (Futura, Century Gothic) closes up.
    ///
    /// It also ships six usable weights against Futura's two, so the hierarchy
    /// comes from weight instead of from size alone.
    private static func geometric(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .custom(Self.faceName(for: weight), fixedSize: size)
    }

    private static func faceName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: return "AvenirNext-UltraLight"
        case .regular:                   return "AvenirNext-Regular"
        case .medium:                    return "AvenirNext-Medium"
        case .semibold:                  return "AvenirNext-DemiBold"
        case .heavy, .black:             return "AvenirNext-Heavy"
        default:                         return "AvenirNext-Bold"
        }
    }

    /// Clocks and countdowns. Avenir's default figures are proportional, so the
    /// layout would jitter on every digit change — this asks the face for its
    /// monospaced number set instead. (`.monospacedDigit()` is a no-op on
    /// custom fonts, which is why the feature is applied at the descriptor.)
    ///
    /// `fixedSize` rather than `size` throughout: these sit in fixed-height
    /// tiles and rows that Dynamic Type scaling would overflow.
    static func blurDigits(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name = faceName(for: weight)
        guard let base = UIFont(name: name, size: size) else {
            return .system(size: size, weight: weight).monospacedDigit()
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
    }

    static func blurRounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        geometric(size, weight)
    }
}

// MARK: - Stipple

/// Deterministic generator, so a card's stipple is the same dots on every
/// redraw. A running timer redraws its card once a second; a texture that
/// reshuffled each tick would crawl.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A field of small dots — the app's second texture, next to blur.
///
/// The dots are laid on a jittered grid rather than scattered at random:
/// uniform random points clump and leave bald patches, which reads as dirt on
/// the screen. A jittered grid gives even coverage with no visible ruling.
///
/// Every dot goes into a single `Path` and is filled once, so a full-screen
/// field is one draw call rather than several thousand.
struct Stipple: View {
    var color: Color
    /// Grid pitch in points. Larger is sparser.
    var spacing: CGFloat = 7
    var opacity: Double = 0.10
    /// Dots grow toward the bottom of the frame, so a card has a faint sense of
    /// weight rather than an even wash.
    var graded: Bool = true
    var seed: UInt64 = 0x5EED_1234

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard size.width > 0, size.height > 0 else { return }
            var rng = SplitMix64(seed: seed)
            var path = Path()

            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    let jitterX = CGFloat.random(in: -0.42...0.42, using: &rng) * spacing
                    let jitterY = CGFloat.random(in: -0.42...0.42, using: &rng) * spacing
                    let weight = graded ? 0.55 + 0.45 * (y / size.height) : 1
                    let radius = CGFloat.random(in: 0.34...1.05, using: &rng) * weight

                    path.addEllipse(in: CGRect(
                        x: x + jitterX - radius,
                        y: y + jitterY - radius,
                        width: radius * 2,
                        height: radius * 2
                    ))
                    x += spacing
                }
                y += spacing
            }

            context.fill(path, with: .color(color.opacity(opacity)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

/// The three card surfaces. Mixing light and dark cards on one screen is the
/// reference's main move, so it's a first-class choice here rather than an
/// ad-hoc background colour per call site.
enum BlurSurface {
    /// Ivory. The default — anything with a lot of small type.
    case light
    /// Charcoal. The screen's focal object, one per screen at most.
    case dark
    /// Frosted sand. Blurs whatever is behind it; for panels that should feel
    /// attached to the page rather than lifted off it.
    case glass

    /// Primary type on this surface.
    var ink: Color {
        switch self {
        case .light, .glass: return Blur.ink
        case .dark:          return Blur.onDark
        }
    }

    /// Secondary type.
    var inkSoft: Color {
        switch self {
        case .light, .glass: return Blur.inkSoft
        case .dark:          return Blur.onDarkSoft
        }
    }

    /// Tertiary type and small uppercase labels.
    var inkFaint: Color {
        switch self {
        case .light, .glass: return Blur.inkFaint
        case .dark:          return Blur.onDarkSoft
        }
    }

    var line: Color {
        switch self {
        case .light, .glass: return Blur.hairline
        case .dark:          return Blur.onDarkLine
        }
    }

    /// An inset well — a chip's off state, a progress track.
    var well: Color {
        switch self {
        case .light, .glass: return Blur.canvas.opacity(0.55)
        case .dark:          return Blur.charcoalSoft
        }
    }

    /// Resolve an accent so it stays legible as type on this surface.
    func tint(_ accent: Color) -> Color {
        switch self {
        case .light, .glass: return Blur.onCanvas(accent)
        case .dark:          return Blur.onCharcoal(accent)
        }
    }
}

/// Card chrome: fill, hairline, a stipple pass, and a warm shadow.
///
/// The stipple is clipped to the card's own rounded rectangle and drawn over
/// the fill but under the content, so it textures the surface without ever
/// landing behind a glyph and thinning it out.
struct BlurCard: ViewModifier {
    var surface: BlurSurface = .light
    var padding: CGFloat = 16
    var radius: CGFloat = 24
    var stipple: Bool = true

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    switch surface {
                    case .light:
                        shape.fill(Blur.surface)
                    case .dark:
                        shape.fill(Blur.charcoal)
                    case .glass:
                        shape.fill(.regularMaterial)
                        shape.fill(Blur.surface.opacity(0.42))
                    }

                    if stipple {
                        Stipple(
                            color: surface == .dark ? .white : Blur.ink,
                            spacing: 6,
                            opacity: surface == .dark ? 0.085 : 0.055,
                            seed: 0xC0FF_EE01
                        )
                        .clipShape(shape)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    surface == .dark ? Blur.onDarkLine : Blur.hairline,
                    lineWidth: 1
                )
            }
            .shadow(color: Color(red: 0.35, green: 0.28, blue: 0.16)
                .opacity(surface == .dark ? 0.20 : 0.09),
                    radius: 16, x: 0, y: 8)
    }
}

extension View {
    func blurCard(_ surface: BlurSurface = .light,
                  padding: CGFloat = 16,
                  radius: CGFloat = 24,
                  stipple: Bool = true) -> some View {
        modifier(BlurCard(surface: surface,
                          padding: padding,
                          radius: radius,
                          stipple: stipple))
    }

    /// A coloured glow behind an element. Kept low on the sand page — the
    /// background is already warm, so a strong glow turns to mud.
    func blurGlow(_ color: Color, radius: CGFloat = 16, opacity: Double = 0.30) -> some View {
        shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 5)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var accent: Color = Blur.blue
    var count: Int? = nil
    var surface: BlurSurface = .glass

    var body: some View {
        HStack(spacing: 9) {
            Text(title.uppercased())
                .font(.blurRounded(12, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(surface.inkSoft)

            if let count {
                Text("\(count)")
                    .font(.blurDigits(11, weight: .bold))
                    .foregroundStyle(surface.tint(accent))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(surface.tint(accent).opacity(0.14)))
            }

            // Runs the header out to the margin — the reference leans on thin
            // rules like this to separate stacks without adding a box.
            Rectangle()
                .fill(surface.line)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Buttons

/// Primary filled action: charcoal capsule, pale-denim label (8.8:1). Gold on
/// charcoal reads just as well, but this button is on every screen — the
/// loudest colour in the palette shouldn't be the one you see most often.
struct BlurPrimaryButtonStyle: ButtonStyle {
    var fill: Color = Blur.charcoal
    var label: Color = Blur.blueSoft

    /// A disabled button is drawn in its own colours rather than by fading the
    /// enabled one. Dropping a charcoal capsule to 45% over a warm page lands
    /// on a muddy grey that its yellow label can no longer be read against —
    /// unavailable has to stay legible, it just shouldn't invite a tap.
    @Environment(\.isEnabled) private var isEnabled

    private var fillColor: Color { isEnabled ? fill : Blur.hairline }
    private var labelColor: Color { isEnabled ? label : Blur.inkSoft }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blurRounded(17, weight: .bold))
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background {
                ZStack {
                    Capsule().fill(fillColor)
                    Stipple(color: labelColor, spacing: 5, opacity: 0.10,
                            seed: 0xB770_0001)
                        .clipShape(Capsule())
                }
            }
            .blurGlow(fillColor, radius: 14, opacity: isEnabled ? 0.22 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

/// Quiet action — frosted surface, coloured label.
struct BlurSecondaryButtonStyle: ButtonStyle {
    var tint: Color = Blur.ink

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.blurRounded(17, weight: .semibold))
            .foregroundStyle(isEnabled ? tint : Blur.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background {
                ZStack {
                    Capsule().fill(.regularMaterial)
                    Capsule().fill(Blur.surface.opacity(isEnabled ? 0.55 : 0.25))
                }
            }
            .overlay(Capsule().strokeBorder(Blur.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}
