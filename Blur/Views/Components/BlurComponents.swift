import SwiftUI
import UIKit

// MARK: - Screen scaffold

/// Shared page chrome: warm canvas, a large gradient title, and a consistent
/// scroll layout so the three tabs feel like one app.
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
            Blur.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.blurRounded(34, weight: .heavy))
                                .foregroundStyle(Blur.sweep)

                            if let subtitle {
                                Text(subtitle)
                                    .font(.blurRounded(14, weight: .medium))
                                    .foregroundStyle(Blur.inkSoft)
                            }
                        }
                        Spacer(minLength: 12)
                        trailing()
                    }
                    .padding(.top, 8)

                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
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

struct BlurIconButton: View {
    let systemName: String
    var fill: Color = Blur.ink
    var glyph: Color = Blur.green
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(glyph)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .blurGlow(fill, radius: 12, opacity: 0.22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state

struct BlurEmptyState: View {
    let systemName: String
    let title: String
    let message: String
    var accent: Color = Blur.pink

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Blur.onCanvas(accent))

            Text(title)
                .font(.blurRounded(19, weight: .bold))
                .foregroundStyle(Blur.ink)

            Text(message)
                .font(.blurRounded(14, weight: .medium))
                .foregroundStyle(Blur.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .blurCard(padding: 0)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Blur.pink)   // a warning is the one place pink means "stop"

            Text(text)
                .font(.blurRounded(13, weight: .medium))
                .foregroundStyle(Blur.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.blurRounded(13, weight: .bold))
                    .foregroundStyle(Blur.pink)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Blur.yellow.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Blur.pink.opacity(0.28), lineWidth: 1)
        )
    }
}

// MARK: - Tone picker

/// Horizontal chip row. Small enough to sit inline in both the alarm editor and
/// the timer setup without a navigation push.
struct TonePickerRow: View {
    @Binding var selection: AlarmTone
    var accent: Color = Blur.pink

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
                        .foregroundStyle(isSelected ? Blur.onAccent(accent) : Blur.inkSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(
                                isSelected
                                ? AnyShapeStyle(accent)
                                : AnyShapeStyle(Blur.canvas)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isSelected ? Color.clear : Blur.hairline,
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
    var accent: Color = Blur.pink

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.blurRounded(11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Blur.inkFaint)

            TextField(placeholder, text: $text)
                .font(.blurRounded(17, weight: .medium))
                .foregroundStyle(Blur.ink)
                .tint(accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Blur.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Blur.hairline, lineWidth: 1)
                )
        }
    }
}
