import SwiftUI
import UIKit

struct TimersView: View {

    private enum DurationField: Hashable {
        case hours
        case minutes
        case seconds
    }

    @Environment(TimerStore.self) private var store
    @Environment(AlarmCenter.self) private var center

    @State private var hoursText = ""
    @State private var minutesText = ""
    @State private var secondsText = ""
    @FocusState private var focusedDurationField: DurationField?

    private let columnCount = 5
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    var body: some View {
        @Bindable var store = store

        BlurScreen(title: "Timer") {
            if !store.running.isEmpty {
                BlurGlassButton(systemName: "xmark") { store.cancelAll() }
                    .accessibilityLabel("Clear all timers")
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
                                  accent: Blur.blue,
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
            customTimer
        }
        // `Alarm` isn't Equatable, so watch the states — which is the only part
        // that matters here anyway (including a stopped timer disappearing).
        .onChange(of: center.liveAlarms.mapValues(\.state)) { _, _ in
            store.reconcile()
        }
        .toolbar {
            if focusedDurationField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedDurationField != .seconds {
                        Button("Next") { focusNextDurationField() }
                    }
                    Spacer()
                    Button("Done") { focusedDurationField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Quick timers

    private var quickTimers: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quick Timers", accent: Blur.lilac)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(TimerPreset.all.enumerated()), id: \.element.id) { index, preset in
                    // One surface per row, not per tile: the grid darkens as the
                    // durations get longer — ivory for minutes, lavender for the
                    // quarter-hours, charcoal for the longest. It reads as three
                    // bands rather than a checkerboard, and the weight of the
                    // tile tells you roughly how long the timer is before you've
                    // read the number.
                    PresetTile(preset: preset, band: index / columnCount) {
                        Task { await store.start(preset: preset) }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            }
        }
    }

    // MARK: Custom

    private var customTimer: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Custom Duration", accent: Blur.charcoal)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 8) {
                    durationField(
                        text: $hoursText,
                        label: "HR",
                        field: .hours,
                        maximum: 23
                    )

                    durationColon

                    durationField(
                        text: $minutesText,
                        label: "MIN",
                        field: .minutes,
                        maximum: 59
                    )

                    durationColon

                    durationField(
                        text: $secondsText,
                        label: "SEC",
                        field: .seconds,
                        maximum: 59
                    )
                }

                if let durationSeconds {
                    Label(
                        "Starts a \(TimerEntry.describe(seconds: durationSeconds)) timer",
                        systemImage: "timer"
                    )
                    .font(.blurRounded(13, weight: .semibold))
                    .foregroundStyle(Blur.inkSoft)
                }

                Button("Start Timer") { startCustom() }
                    .buttonStyle(BlurPrimaryButtonStyle())
                    .disabled(durationSeconds == nil)
            }
            .blurCard(.light)
        }
    }

    private var durationColon: some View {
        Text(":")
            .font(.blurDigits(34, weight: .bold))
            .foregroundStyle(Blur.inkSoft)
            .padding(.bottom, 18)
    }

    private func durationField(
        text: Binding<String>,
        label: String,
        field: DurationField,
        maximum: Int
    ) -> some View {
        let isValid = text.wrappedValue.isEmpty
            || (Int(text.wrappedValue).map { (0...maximum).contains($0) } ?? false)

        return VStack(spacing: 6) {
            TextField("00", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.blurDigits(34, weight: .bold))
                .foregroundStyle(Blur.ink)
                .tint(Blur.blue)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Blur.canvas.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(
                            focusedDurationField == field
                                ? Blur.blue
                                : (isValid ? Blur.hairline : Blur.clay),
                            lineWidth: focusedDurationField == field ? 2 : 1
                        )
                )
                .focused($focusedDurationField, equals: field)
                .accessibilityLabel(label == "HR" ? "Hours" : (label == "MIN" ? "Minutes" : "Seconds"))
                .onChange(of: text.wrappedValue) { _, value in
                    updateDurationText(value, field: field, maximum: maximum)
                }

            Text(label)
                .font(.blurRounded(10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Blur.inkFaint)
        }
    }

    // MARK: Actions

    private var durationSeconds: TimeInterval? {
        let hours = Int(hoursText) ?? 0
        let minutes = Int(minutesText) ?? 0
        let seconds = Int(secondsText) ?? 0
        guard (0...23).contains(hours),
              (0...59).contains(minutes),
              (0...59).contains(seconds) else { return nil }
        let total = hours * 3600 + minutes * 60 + seconds
        return total > 0 ? TimeInterval(total) : nil
    }

    private func startCustom() {
        guard let durationSeconds else { return }
        focusedDurationField = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            let ok = await store.start(seconds: durationSeconds)
            if ok {
                hoursText = ""
                minutesText = ""
                secondsText = ""
            }
        }
    }

    private func updateDurationText(
        _ value: String,
        field: DurationField,
        maximum: Int
    ) {
        let cleaned = String(value.filter(\.isNumber).prefix(2))
        if cleaned != value {
            setDurationText(cleaned, for: field)
            return
        }

        if cleaned.count == 2,
           let number = Int(cleaned),
           (0...maximum).contains(number) {
            focusNextDurationField()
        }
    }

    private func setDurationText(_ value: String, for field: DurationField) {
        switch field {
        case .hours: hoursText = value
        case .minutes: minutesText = value
        case .seconds: secondsText = value
        }
    }

    private func focusNextDurationField() {
        switch focusedDurationField {
        case .hours: focusedDurationField = .minutes
        case .minutes: focusedDurationField = .seconds
        case .seconds, nil: focusedDurationField = nil
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Preset tile

/// One tile in the quick-timer grid. `band` is the row index, which is the only
/// thing that decides how the tile is drawn.
private struct PresetTile: View {
    let preset: TimerPreset
    let band: Int
    let action: () -> Void

    private var surface: BlurSurface { band >= 2 ? .dark : .light }

    /// Row 1 is the one filled tile — a flat lavender field with ink numerals.
    private var isFilled: Bool { band == 1 }

    private var label: Color {
        if isFilled { return Blur.ink }
        return band >= 2 ? Blur.tan : Blur.ink
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(preset.title)
                    .font(.blurDigits(21, weight: .bold))
                if !preset.unit.isEmpty {
                    Text(preset.unit)
                        .font(.blurRounded(9, weight: .semibold))
                        .opacity(0.72)
                }
            }
            .foregroundStyle(label)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                ZStack {
                    switch (isFilled, surface) {
                    case (true, _):    shape.fill(Blur.lilac)
                    case (_, .dark):   shape.fill(Blur.charcoal)
                    default:           shape.fill(Blur.surface.opacity(0.92))
                    }

                    Stipple(color: label,
                            spacing: 5,
                            opacity: surface == .dark ? 0.13 : 0.09,
                            seed: UInt64(preset.minutes) &* 0x9E37_79B1)
                        .clipShape(shape)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(surface == .dark ? Blur.onDarkLine : Blur.hairline,
                                  lineWidth: 1)
            )
            .shadow(color: Color(red: 0.35, green: 0.28, blue: 0.16).opacity(0.10),
                    radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.accessibilityLabel)
    }
}

// MARK: - Running timer card

/// A live timer is the loudest thing on the screen, so it gets the dark card —
/// the same role the reference gives its session-history panel.
struct RunningTimerCard: View {
    let entry: TimerEntry
    let isRinging: Bool
    let onToggle: () -> Void
    let onCancel: () -> Void

    /// Resolved against charcoal, since that's the only surface this card has.
    /// A timer that has finished drops its own accent for gold — the one state
    /// in the app that should read as louder than everything around it, and the
    /// reason gold is still in the palette at all.
    private var accent: Color {
        isRinging ? Blur.yellow : Blur.onCharcoal(Blur.accent(entry.accentIndex))
    }

    var body: some View {
        // Redraws once a second; the countdown itself is date-derived so it
        // stays exact even if a tick is dropped.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let remaining = entry.remaining(at: now)

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Blur.onDarkLine, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: entry.progress(at: now))
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isRinging ? "Done" : Self.clock(remaining))
                        .font(.blurDigits(27, weight: .bold))
                        .foregroundStyle(isRinging ? accent : Blur.onDark)

                    HStack(spacing: 5) {
                        Text(entry.displayLabel)
                            .font(.blurRounded(13, weight: .semibold))
                            .foregroundStyle(Blur.onDarkSoft)
                            .lineLimit(1)

                        if entry.isPaused {
                            Text("· Paused")
                                .font(.blurRounded(13, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                    }
                }

                Spacer(minLength: 0)

                if !isRinging {
                    Button(action: onToggle) {
                        Image(systemName: entry.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Blur.charcoalSoft))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.isPaused ? "Resume" : "Pause")
                }

                Button(action: onCancel) {
                    Image(systemName: isRinging ? "checkmark" : "xmark")
                        .font(.system(size: 15, weight: .bold))
                        // `accent` is already resolved for charcoal, so it's
                        // always one of the light tints — a glyph sitting on a
                        // circle of it takes charcoal, never a light label.
                        .foregroundStyle(isRinging ? Blur.charcoal : Blur.onDarkSoft)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(isRinging
                                          ? AnyShapeStyle(accent)
                                          : AnyShapeStyle(Blur.charcoalSoft))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRinging ? "Dismiss" : "Cancel timer")
            }
            .blurCard(.dark)
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
