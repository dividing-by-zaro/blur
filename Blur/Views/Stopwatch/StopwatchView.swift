import SwiftUI
import UIKit

/// Start, stop, reset. No laps — the whole point of this screen is that it does
/// one thing without a second button competing for the same thumb.
struct StopwatchView: View {

    @Environment(StopwatchModel.self) private var stopwatch

    var body: some View {
        BlurScreen(title: "Stopwatch") {
            VStack(spacing: 34) {
                dial
                controls
            }
            .padding(.top, 24)
        }
    }

    // MARK: Dial

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(Blur.hairline, lineWidth: 12)

            // Sweeps once a minute, so the ring reads as a seconds hand rather
            // than a progress bar toward some arbitrary end.
            Circle()
                .trim(from: 0, to: secondsFraction)
                .stroke(Blur.sweep, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: secondsFraction)
                .blurGlow(Blur.green, radius: 18, opacity: stopwatch.isRunning ? 0.45 : 0.15)

            VStack(spacing: 6) {
                Text(stopwatch.formatted)
                    .font(.blurDigits(42, weight: .bold))
                    .foregroundStyle(Blur.ink)
                    .contentTransition(.numericText())

                Text(statusText)
                    .font(.blurRounded(12, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(statusColor)
            }
        }
        .frame(width: 268, height: 268)
        .frame(maxWidth: .infinity)
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

    private var statusColor: Color {
        switch stopwatch.mode {
        case .idle:    return Blur.inkFaint
        case .running: return Blur.green
        case .stopped: return Blur.pink
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 14) {
            Button("Reset") {
                stopwatch.reset()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .buttonStyle(BlurSecondaryButtonStyle(tint: Blur.inkSoft))
            .disabled(stopwatch.mode == .idle)
            .opacity(stopwatch.mode == .idle ? 0.4 : 1)

            Button(stopwatch.isRunning ? "Stop" : "Start") {
                stopwatch.toggle()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            // Running turns the button pink so stopping reads as the loud
            // action; idle keeps the default black-on-lime.
            .buttonStyle(stopwatch.isRunning
                         ? BlurPrimaryButtonStyle(fill: Blur.pink, label: .white)
                         : BlurPrimaryButtonStyle())
        }
    }
}
