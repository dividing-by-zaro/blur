import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock-screen, banner and Dynamic Island presentation for Blur's alarms and
/// timers. AlarmKit drives this automatically from the `AlarmAttributes` the app
/// passes when scheduling — there is no `Activity.request` call anywhere.
struct BlurAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<BlurAlarmMetadata>.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                // Charcoal rather than the app's ivory. The lock screen sits on
                // whatever wallpaper the user chose, and a dark card is the one
                // surface that holds its contrast against all of them — it's
                // also the app's own focal-object treatment, so a running timer
                // looks the same here as it does in the list.
                .activityBackgroundTint(Blur.charcoal)
                .activitySystemActionForegroundColor(Blur.onDark)
        } dynamicIsland: { context in
            // The Island is dark too, so it resolves exactly like the lock
            // screen — one rule instead of two.
            let tint = Blur.onCharcoal(context.attributes.tintColor)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.metadata?.kind == .timer
                          ? "timer" : "alarm.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ModeReadout(state: context.state, tint: tint, size: 22)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.displayTitle ?? "Blur")
                        .font(.blurRounded(15, weight: .semibold))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ControlRow(state: context.state, tint: tint)
                }
            } compactLeading: {
                Image(systemName: context.attributes.metadata?.kind == .timer
                      ? "timer" : "alarm.fill")
                    .foregroundStyle(tint)
            } compactTrailing: {
                ModeReadout(state: context.state, tint: tint, size: 14)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

// MARK: - Lock screen

private struct LockScreenView: View {
    let attributes: AlarmAttributes<BlurAlarmMetadata>
    let state: AlarmPresentationState

    /// This surface is charcoal, same as the Dynamic Island, so both go through
    /// `onCharcoal` — blue lightens to pale denim and charcoal itself has to
    /// give way entirely, since an accent can't be the colour it's drawn on.
    private var tint: Color { Blur.onCharcoal(attributes.tintColor) }
    private var metadata: BlurAlarmMetadata? { attributes.metadata }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Blur.charcoalSoft)
                Stipple(color: tint, spacing: 5, opacity: 0.16, seed: 0x1AC7_0001)
                    .clipShape(Circle())
                Image(systemName: metadata?.kind == .timer ? "timer" : "alarm.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(metadata?.displayTitle ?? "Blur")
                    .font(.blurRounded(16, weight: .bold))
                    .foregroundStyle(Blur.onDark)
                    .lineLimit(1)

                ModeReadout(state: state, tint: tint, size: 26)
            }

            Spacer(minLength: 0)

            ControlRow(state: state, tint: tint)
        }
    }
}

// MARK: - Readout

/// The number that changes: a live countdown, a paused figure, or the alarm
/// time when it's actually ringing.
private struct ModeReadout: View {
    let state: AlarmPresentationState
    let tint: Color
    var size: CGFloat

    var body: some View {
        Group {
            switch state.mode {
            case .countdown(let countdown):
                // System-driven countdown — no timer or refresh needed.
                Text(timerInterval: Date.now...countdown.fireDate,
                     pauseTime: nil,
                     countsDown: true,
                     showsHours: countdown.totalCountdownDuration >= 3600)
                    .font(.blurDigits(size, weight: .bold))
                    .foregroundStyle(tint)

            case .paused(let paused):
                let remaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
                Text(Self.clock(remaining))
                    .font(.blurDigits(size, weight: .bold))
                    .foregroundStyle(tint.opacity(0.75))

            case .alert:
                Text("Now")
                    .font(.blurRounded(size, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Controls

/// Buttons vary by state: pause while counting, resume while paused, stop when
/// ringing. Each is a `LiveActivityIntent`, so it runs in the app's process.
private struct ControlRow: View {
    let state: AlarmPresentationState
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            switch state.mode {
            case .countdown:
                intentButton(PauseAlarmIntent(alarmID: state.alarmID),
                             systemName: "pause.fill",
                             filled: false)
                intentButton(StopAlarmIntent(alarmID: state.alarmID),
                             systemName: "xmark",
                             filled: false)

            case .paused:
                intentButton(ResumeAlarmIntent(alarmID: state.alarmID),
                             systemName: "play.fill",
                             filled: true)
                intentButton(StopAlarmIntent(alarmID: state.alarmID),
                             systemName: "xmark",
                             filled: false)

            case .alert:
                intentButton(StopAlarmIntent(alarmID: state.alarmID),
                             systemName: "checkmark",
                             filled: true)
            }
        }
    }

    @ViewBuilder
    private func intentButton(_ intent: some LiveActivityIntent,
                              systemName: String,
                              filled: Bool) -> some View {
        Button(intent: intent) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                // `tint` has already been resolved against charcoal, so it's
                // always a light colour: a filled circle of it carries charcoal,
                // and an unfilled one carries the tint itself.
                .foregroundStyle(filled ? Blur.charcoal : tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(filled ? tint : tint.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
