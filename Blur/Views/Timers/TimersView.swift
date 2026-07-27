import SwiftUI
import UIKit

struct TimersView: View {

    @Environment(TimerStore.self) private var store
    @Environment(AlarmCenter.self) private var center

    @State private var parser = TimerIntentParser()
    @State private var customText: String = ""
    @FocusState private var customFieldFocused: Bool

    private let columnCount = 5
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    var body: some View {
        @Bindable var store = store

        BlurScreen(title: "Timer", subtitle: subtitle) {
            if !store.running.isEmpty {
                Button("Clear") { store.cancelAll() }
                    .font(.blurRounded(15, weight: .semibold))
                    .foregroundStyle(Blur.inkSoft)
            }
        } content: {
            if !center.isAuthorized {
                BlurWarningBanner(
                    text: "Timer permission is off. Turn it on so timers ring even when your phone is silenced.",
                    actionTitle: "Fix",
                    action: openSettings
                )
            }

            // Live timers only — once one is stopped it's gone. No history.
            if !store.running.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Running",
                                  accent: Blur.green,
                                  count: store.running.count)

                    ForEach(store.running) { entry in
                        RunningTimerCard(
                            entry: entry,
                            isRinging: store.isRinging(entry),
                            onToggle: { store.togglePause(entry) },
                            onCancel: { store.dismiss(entry) }
                        )
                    }
                }
            }

            quickTimers
            toneAndLabel
            customTimer
        }
        // `Alarm` isn't Equatable, so watch the states — which is the only part
        // that matters here anyway (pause/resume driven from the Live Activity).
        .onChange(of: center.liveAlarms.mapValues(\.state)) { _, _ in
            store.syncPauseStates()
        }
    }

    private var subtitle: String? {
        store.running.isEmpty ? "Tap a preset or type your own" : nil
    }

    // MARK: Quick timers

    private var quickTimers: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quick Timers", accent: Blur.pink)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(TimerPreset.all.enumerated()), id: \.element.id) { index, preset in
                    // One colour per row, not per tile — the grid reads as three
                    // bands (short / medium / long) instead of a checkerboard.
                    let accent = Blur.accent(index / columnCount)

                    Button {
                        Task { await store.start(preset: preset) }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        VStack(spacing: 1) {
                            Text(preset.title)
                                .font(.blurDigits(20, weight: .bold))
                            if !preset.unit.isEmpty {
                                Text(preset.unit)
                                    .font(.blurRounded(9, weight: .semibold))
                                    .opacity(0.8)
                            }
                        }
                        .foregroundStyle(Blur.onAccent(accent))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(accent)
                        )
                        .blurGlow(accent, radius: 8, opacity: 0.3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.accessibilityLabel)
                }
            }
        }
    }

    // MARK: Tone + label

    private var toneAndLabel: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TONE")
                        .font(.blurRounded(11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Blur.inkFaint)
                    Spacer()
                    Text("Applies to new timers")
                        .font(.blurRounded(11, weight: .medium))
                        .foregroundStyle(Blur.inkFaint)
                }

                TonePickerRow(selection: $store.selectedTone, accent: Blur.green)
            }

            BlurField(title: "Label (optional)",
                      text: $store.pendingLabel,
                      placeholder: "Pasta, laundry, focus…",
                      accent: Blur.green)
        }
        .blurCard()
    }

    // MARK: Custom

    /// One free-text line. A plain keyboard rather than a number pad, which is
    /// what puts the system dictation key within reach — so "twenty five minutes
    /// for the pasta, chime" is spoken the same way it's typed, and the app
    /// never has to hold a microphone permission of its own.
    private var customTimer: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Custom", accent: Blur.yellow)

            VStack(alignment: .leading, spacing: 14) {
                TextField(fieldPrompt, text: $customText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .font(.blurRounded(21, weight: .bold))
                    .foregroundStyle(Blur.ink)
                    .tint(Blur.pink)
                    .focused($customFieldFocused)
                    .accessibilityLabel("Timer description")
                    .onChange(of: customFieldFocused) { _, focused in
                        // Warm the model while they're still typing, so the
                        // first parse isn't paying for the load.
                        if focused { parser.prewarm() }
                    }
                    .onSubmit { startCustom() }

                readout

                Button(parser.isThinking ? "Reading…" : "Start Timer") { startCustom() }
                    .buttonStyle(BlurPrimaryButtonStyle())
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.45)
            }
            .blurCard()
        }
    }

    /// Rotates through examples so the field teaches what it now accepts.
    private var fieldPrompt: String {
        parser.isModelAvailable
            ? "25 min for the pasta, chime"
            : "25 minutes"
    }

    /// Below the field: what will happen, and which parser will do it.
    @ViewBuilder
    private var readout: some View {
        if let minutes = quickMinutes, minutes > 0 {
            let preview = PhraseHeuristics.labelAndTone(from: customText)
            Text(previewLine(minutes: minutes, label: preview.label, tone: preview.tone))
                .font(.blurRounded(13, weight: .semibold))
                .foregroundStyle(Blur.inkSoft)
        } else if !customText.isEmpty, parser.isModelAvailable {
            // No bare number in there, but the model may still find one.
            Text("Reads the label and tone from what you wrote")
                .font(.blurRounded(13, weight: .medium))
                .foregroundStyle(Blur.inkFaint)
        }

        // Shown whenever the model is missing, not only once there's text —
        // otherwise the feature just quietly does less than it claims.
        if let reason = parser.unavailableReason {
            Text(reason)
                .font(.blurRounded(12, weight: .medium))
                .foregroundStyle(Blur.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Starts a 30 min timer · Pasta · Chime" — the label and tone shown here
    /// are the heuristics' guess, which is the floor. With the model available
    /// the actual result is usually better, never worse.
    private func previewLine(minutes: Int, label: String, tone: AlarmTone?) -> String {
        var parts = ["Starts a \(TimerEntry.describe(seconds: Double(minutes) * 60)) timer"]
        if !label.isEmpty { parts.append(label) }
        if let tone { parts.append(tone.displayName) }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    /// Duration visible without waking the model — drives the live readout and
    /// keeps the button enabled for the ordinary "25" case with no latency.
    private var quickMinutes: Int? {
        MinutesParser.minutes(from: customText).map { min($0, 24 * 60) }
    }

    /// Anything at all typed is startable when the model is there, since it may
    /// find a duration `MinutesParser` can't. Without it, a duration is required.
    private var canStart: Bool {
        guard !parser.isThinking else { return false }
        let hasText = !customText.trimmingCharacters(in: .whitespaces).isEmpty
        return parser.isModelAvailable ? hasText : quickMinutes != nil
    }

    private func startCustom() {
        guard canStart else { return }
        customFieldFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            guard let parsed = await parser.parse(customText), parsed.minutes > 0 else { return }

            // `nil` label and tone fall through to whatever the field and the
            // picker hold, so what the model didn't find, the user's own
            // choices still supply.
            let ok = await store.start(
                seconds: Double(parsed.minutes) * 60,
                label: parsed.label.isEmpty ? nil : parsed.label,
                tone: parsed.tone
            )
            if ok {
                customText = ""
                parser.reset()
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Running timer card

struct RunningTimerCard: View {
    let entry: TimerEntry
    let isRinging: Bool
    let onToggle: () -> Void
    let onCancel: () -> Void

    private var accent: Color { Blur.accent(entry.accentIndex) }

    var body: some View {
        // Redraws once a second; the countdown itself is date-derived so it
        // stays exact even if a tick is dropped.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let remaining = entry.remaining(at: now)

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Blur.hairline, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: entry.progress(at: now))
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isRinging ? "Done" : Self.clock(remaining))
                        .font(.blurDigits(26, weight: .bold))
                        .foregroundStyle(isRinging ? Blur.onCanvas(accent) : Blur.ink)

                    HStack(spacing: 5) {
                        Text(entry.displayLabel)
                            .font(.blurRounded(13, weight: .semibold))
                            .foregroundStyle(Blur.inkSoft)
                            .lineLimit(1)

                        if entry.isPaused {
                            Text("· Paused")
                                .font(.blurRounded(13, weight: .semibold))
                                .foregroundStyle(Blur.onCanvas(accent))
                        }
                    }
                }

                Spacer(minLength: 0)

                if !isRinging {
                    Button(action: onToggle) {
                        Image(systemName: entry.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Blur.onCanvas(accent))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(accent.opacity(0.13)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.isPaused ? "Resume" : "Pause")
                }

                Button(action: onCancel) {
                    Image(systemName: isRinging ? "checkmark" : "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isRinging ? Blur.onAccent(accent) : Blur.inkSoft)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(isRinging
                                          ? AnyShapeStyle(accent)
                                          : AnyShapeStyle(Blur.canvas))
                        )
                        .overlay(
                            Circle().strokeBorder(
                                isRinging ? Color.clear : Blur.hairline, lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRinging ? "Dismiss" : "Cancel timer")
            }
            .blurCard()
        }
    }

    /// "M:SS" under an hour, "H:MM:SS" above it.
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
