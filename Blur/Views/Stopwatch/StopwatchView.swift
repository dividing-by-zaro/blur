import SwiftUI
import UIKit

/// Start, stop, reset. No laps — the whole point of this screen is that it does
/// one thing without a second button competing for the same thumb.
struct StopwatchView: View {

    @Environment(StopwatchModel.self) private var stopwatch

    var body: some View {
        BlurScreen(title: "Stopwatch") {
            VStack(spacing: 24) {
                dial
                controls
            }
            .padding(.top, 12)
        }
    }

    // MARK: Dial

    /// Just the elapsed time and its state. A stopwatch has no end to measure
    /// progress toward, so there's no ring or gauge around the number.
    private var dial: some View {
        VStack(spacing: 14) {
            Text(stopwatch.formatted)
                .font(.blurDigits(52, weight: .bold))
                .foregroundStyle(Blur.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(statusText)
                .font(.blurRounded(11, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(statusColor.opacity(0.14)))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .blurCard(.light, padding: 22, radius: 34)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stopwatch")
        .accessibilityValue(stopwatch.formatted)
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
