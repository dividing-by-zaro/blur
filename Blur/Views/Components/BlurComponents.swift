import SwiftUI
import UIKit

// MARK: - Backdrop

/// The page behind every screen, and the app's other use of blur besides the
/// glass cards: three wide colour fields blurred past the point of having an
/// edge, so the sand shifts warm and cool across the screen without any shape
/// being visible. A stipple pass over the top gives the whole page a tooth.
///
/// Drawn once and never animated — it sits below the scroll view and doesn't
/// move with it, which is what keeps the cards feeling like they're floating
/// over a surface rather than printed on one.
struct BlurBackdrop: View {
    var body: some View {
        ZStack {
            Blur.page

            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                ZStack {
                    field(Blur.canvasDeep.opacity(0.80), size: w * 1.1)
                        .position(x: w * 0.05, y: h * 0.08)

                    field(Blur.blueSoft.opacity(0.65), size: w * 0.95)
                        .position(x: w * 1.02, y: h * 0.13)

                    field(Blur.lilac.opacity(0.42), size: w * 0.85)
                        .position(x: w * -0.08, y: h * 0.52)

                    field(Blur.tan.opacity(0.85), size: w * 1.25)
                        .position(x: w * 0.80, y: h * 0.95)
                }
                .blur(radius: 70)
            }

            Stipple(color: Blur.ink, spacing: 9, opacity: 0.075, graded: false,
                    seed: 0xBACC_D009)
        }
        .ignoresSafeArea()
    }

    private func field(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - Screen scaffold

/// Shared page chrome: the blurred sand backdrop, a large plain title, and a
/// consistent scroll layout so the three tabs feel like one app.
///
/// The title is set in flat ink rather than in colour. On a page this warm a
/// tinted headline is the first thing to lose contrast, and it's also the one
/// piece of type that has to survive being glanced at.
///
/// `trailing` is declared before `content` so that the two-trailing-closure call
/// site — `BlurScreen(title:) { accessory } content: { … }` — matches the way
/// Swift forward-scans trailing closures onto parameters.
struct BlurScreen<Trailing: View, Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: () -> Trailing
    private let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        ZStack {
            BlurBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.blurRounded(36, weight: .medium))
                                .tracking(-0.4)
                                .foregroundStyle(Blur.ink)

                            if let subtitle {
                                Text(subtitle)
                                    .font(.blurRounded(14, weight: .medium))
                                    .foregroundStyle(Blur.inkSoft)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 12)
                        trailing()
                    }
                    .padding(.top, 6)

                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 44)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

extension BlurScreen where Trailing == EmptyView {
    /// Screens with no header accessory.
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title,
                  subtitle: subtitle,
                  trailing: { EmptyView() },
                  content: content)
    }
}

// MARK: - Circular icon button

/// The reference's round chrome buttons: a soft circle floating over the page,
/// glass by default so it belongs to the backdrop.
struct BlurIconButton: View {
    let systemName: String
    var fill: Color = Blur.charcoal
    var glyph: Color = Blur.blueSoft
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.40, weight: .bold))
                .foregroundStyle(glyph)
                .frame(width: size, height: size)
                .background {
                    ZStack {
                        Circle().fill(fill)
                        Stipple(color: glyph, spacing: 5, opacity: 0.12,
                                seed: 0x1C0B_B707)
                            .clipShape(Circle())
                    }
                }
                .blurGlow(fill, radius: 12, opacity: 0.24)
        }
        .buttonStyle(.plain)
    }
}

/// Chrome button in the quiet register — frosted sand, ink glyph. Used where a
/// filled circle would read as the screen's primary action and shouldn't.
struct BlurGlassButton: View {
    let systemName: String
    var glyph: Color = Blur.ink
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(glyph)
                .frame(width: size, height: size)
                .background {
                    ZStack {
                        Circle().fill(.regularMaterial)
                        Circle().fill(Blur.surface.opacity(0.5))
                    }
                }
                .overlay(Circle().strokeBorder(Blur.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state

struct BlurEmptyState: View {
    let systemName: String
    let title: String
    let message: String
    var accent: Color = Blur.blue

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemName)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Blur.onCharcoal(accent))
                .frame(width: 68, height: 68)
                .background(Circle().fill(Blur.charcoalSoft))

            Text(title)
                .font(.blurRounded(20, weight: .bold))
                .foregroundStyle(Blur.onDark)

            Text(message)
                .font(.blurRounded(14, weight: .medium))
                .foregroundStyle(Blur.onDarkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .blurCard(.dark, padding: 0)
    }
}

// MARK: - Warning banner

/// Used when an alarm exists in the app but not in the system — the one state
/// where the UI must not look healthy.
struct BlurWarningBanner: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Blur.clay)

            Text(text)
                .font(.blurRounded(13, weight: .medium))
                .foregroundStyle(Blur.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.blurRounded(13, weight: .bold))
                    .foregroundStyle(Blur.clay)
            }
        }
        .padding(14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                shape.fill(Blur.yellowSoft.opacity(0.85))
                Stipple(color: Blur.clay, spacing: 6, opacity: 0.10, seed: 0xAA88_0001)
                    .clipShape(shape)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Blur.clay.opacity(0.30), lineWidth: 1)
        )
    }
}

// MARK: - Tone picker

/// Horizontal chip row. Small enough to sit inline in both the alarm editor and
/// the timer setup without a navigation push.
struct TonePickerRow: View {
    @Binding var selection: AlarmTone
    var accent: Color = Blur.blue
    var surface: BlurSurface = .light

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AlarmTone.allCases) { tone in
                    let isSelected = tone == selection
                    Button {
                        selection = tone
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tone.symbolName)
                                .font(.system(size: 12, weight: .bold))
                            Text(tone.displayName)
                                .font(.blurRounded(14, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? Blur.onAccent(accent) : surface.inkSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(
                                isSelected
                                ? AnyShapeStyle(accent)
                                : AnyShapeStyle(surface.well)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isSelected ? Color.clear : surface.line,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Labelled field

struct BlurField: View {
    let title: String
    @Binding var text: String
    var placeholder: String
    var accent: Color = Blur.blue
    var surface: BlurSurface = .light

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.blurRounded(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(surface.inkFaint)

            TextField(placeholder, text: $text)
                .font(.blurRounded(17, weight: .medium))
                .foregroundStyle(surface.ink)
                .tint(surface.tint(accent))
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(surface.well)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(surface.line, lineWidth: 1)
                )
        }
    }
}
