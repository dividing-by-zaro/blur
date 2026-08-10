import SwiftUI
import UIKit

/// Start, stop, reset. No laps — the whole point of this screen is that it does
/// one thing without a second button competing for the same thumb.
struct StopwatchView: View {

    @Environment(StopwatchModel.self) private var stopwatch

    var body: some View {
        BlurScreen(title: "Stopwatch", subtitle: "One number, three buttons") {
            VStack(spacing: 24) {
                dial
                controls
            }
            .padding(.top, 12)
        }
    }

    // MARK: Dial

    /// The reference's gauge, made round: a yellow arc running over a charcoal
    /// remainder, on a light card, with the number it describes inside it.
    ///
    /// The two-tone ring is why this card is light and not dark. Charcoal is
    /// the only thing yellow reads cleanly against at this weight, and charcoal
    /// only reads as a track if the card behind it is pale — a dark card would
    /// swallow the untravelled part of the ring and leave a yellow arc floating
    /// with nothing to measure it against.

    /// Three-quarters of a turn with the gap at the bottom, not a closed ring.
    /// A full circle of charcoal this heavy reads as a loading spinner stuck at
    /// zero; an open gauge reads as a dial with a start and an end, which is
    /// also the shape the reference uses.
    private static let sweep: CGFloat = 0.75

    private var dial: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .trim(from: 0, to: Self.sweep)
                    .stroke(Blur.charcoal,
                            style: StrokeStyle(lineWidth: 15, lineCap: .round))

                // Sweeps once a minute, so the arc reads as a seconds hand
                // rather than a progress bar toward some arbitrary end.
                Circle()
                    .trim(from: 0, to: Self.sweep * secondsFraction)
                    .stroke(Blur.wave, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    .animation(.linear(duration: 0.05), value: secondsFraction)
                    .blurGlow(Blur.periwinkle, radius: 18,
                              opacity: stopwatch.isRunning ? 0.40 : 0.10)
            }
            // Trim starts at 3 o'clock, so this puts the gauge's open end at
            // 7:30 and closes it at 4:30.
            .rotationEffect(.degrees(135))
            // Applied after the rotation, so the readout stays upright.
            .overlay {
                VStack(spacing: 10) {
                    Text(stopwatch.formatted)
                        .font(.blurDigits(42, weight: .bold))
                        .foregroundStyle(Blur.ink)
                        .contentTransition(.numericText())

                    Text(statusText)
                        .font(.blurRounded(11, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(statusColor.opacity(0.14)))
                }
            }
            .frame(width: 244, height: 244)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
        .blurCard(.light, padding: 22, radius: 34)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stopwatch")
        .accessibilityValue(stopwatch.formatted)
    }

    private var secondsFraction: Double {
        stopwatch.elapsed.truncatingRemainder(dividingBy: 60) / 60
    }

    private var statusText: String {
        switch stopwatch.mode {
        case .idle:    return "READY"
        case .running: return "RUNNING"
        case .stopped: return "STOPPED"
        }
    }

    /// Type on ivory, so each state takes its pair's dark form — the pill
    /// behind it is a 14% wash of the same colour, which is enough to code the
    /// state without putting a light fill under small letterspaced caps.
    private var statusColor: Color {
        switch stopwatch.mode {
        case .idle:    return Blur.inkFaint
        case .running: return Blur.plum
        case .stopped: return Blur.clay
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Reset") {
                stopwatch.reset()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .buttonStyle(BlurSecondaryButtonStyle(tint: Blur.inkSoft))
            .disabled(stopwatch.mode == .idle)

            Button(stopwatch.isRunning ? "Stop" : "Start") {
                stopwatch.toggle()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            // Running flips the button to a solid periwinkle field with ink on
            // it, so stopping is the most saturated thing on the screen; idle
            // keeps the quieter charcoal-and-pale-denim pairing.
            .buttonStyle(stopwatch.isRunning
                         ? BlurPrimaryButtonStyle(fill: Blur.periwinkle, label: Blur.ink)
                         : BlurPrimaryButtonStyle())
        }
    }
}
