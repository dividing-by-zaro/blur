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
                .activityBackgroundTint(Blur.surface)
                .activitySystemActionForegroundColor(Blur.ink)
        } dynamicIsland: { context in
            let tint = context.attributes.tintColor

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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
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

    /// The Dynamic Island is always dark, so the raw accent reads well there.
    /// This surface is the app's white card, where lime and yellow vanish —
    /// everything drawn here goes through `onCanvas` instead.
    private var tint: Color { Blur.onCanvas(attributes.tintColor) }
    private var wash: Color { attributes.tintColor }
    private var metadata: BlurAlarmMetadata? { attributes.metadata }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                // A pale wash of the true accent still reads as a colour field,
                // so the alarm keeps its identity even though the glyph is ink.
                Circle()
                    .fill(wash.opacity(0.18))
                Image(systemName: metadata?.kind == .timer ? "timer" : "alarm.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(metadata?.displayTitle ?? "Blur")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Blur.ink)
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
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)

            case .paused(let paused):
                let remaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
                Text(Self.clock(remaining))
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint.opacity(0.75))

            case .alert:
                Text("Now")
                    .font(.system(size: size, weight: .bold, design: .rounded))
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
                // Depends on the fill, not the surface, so it holds up in both
                // the dark Dynamic Island and on the white lock screen.
                .foregroundStyle(filled ? Blur.onAccent(tint) : tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(filled ? tint : tint.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
