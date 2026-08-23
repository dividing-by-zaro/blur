import SwiftUI
import UIKit

struct AlarmEditorView: View {

    private enum TimeField: Hashable {
        case hour
        case minute
    }

    private enum Meridiem: String, CaseIterable, Identifiable {
        case am = "AM"
        case pm = "PM"

        var id: String { rawValue }
    }

    enum Mode {
        case create
        case edit(AlarmEntry)

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    let mode: Mode

    @Environment(AlarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AlarmEntry
    @State private var hourText: String
    @State private var minuteText: String
    @State private var meridiem: Meridiem
    @State private var showDeleteConfirm = false
    @State private var preparedHourField = false
    @State private var preparedMinuteField = false
    @FocusState private var focusedTimeField: TimeField?

    init(mode: Mode) {
        self.mode = mode
        let entry: AlarmEntry
        switch mode {
        case .create:
            entry = AlarmEntry()
        case .edit(let existing):
            entry = existing
        }
        _draft = State(initialValue: entry)
        let displayHour = Self.uses24HourClock
            ? entry.hour
            : (entry.hour % 12 == 0 ? 12 : entry.hour % 12)
        _hourText = State(initialValue: String(format: "%02d", displayHour))
        _minuteText = State(initialValue: String(format: "%02d", entry.minute))
        _meridiem = State(initialValue: entry.hour < 12 ? .am : .pm)
    }

    /// The editor is a light sheet throughout — it's the densest screen in the
    /// app and every control on it is small — so wherever this is used as type
    /// it goes through `onCanvas` and resolves to the pair's dark form. As a
    /// chip *fill* it stays the light form, which is what carries ink.
    private var accent: Color { Blur.blue }

    var body: some View {
        NavigationStack {
            ZStack {
                BlurBackdrop()

                ScrollView {
                    VStack(spacing: 18) {
                        timePicker
                        daysPicker
                        labelAndTone
                        snoozePicker

                        if mode.isEditing {
                            Button("Delete Alarm", role: .destructive) {
                                showDeleteConfirm = true
                            }
                            .buttonStyle(BlurSecondaryButtonStyle(tint: Blur.clay))
                            .padding(.top, 4)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            // `.tint` rather than a `foregroundStyle` on each button: the
            // confirmation action is drawn by the system as a prominent glass
            // capsule, and that capsule takes its fill from the tint. Colouring
            // the label alone leaves it system blue.
            .tint(Blur.blue)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(mode.isEditing ? "Edit Alarm" : "New Alarm")
                        .font(.blurRounded(17, weight: .semibold))
                        .foregroundStyle(Blur.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.blurRounded(16, weight: .medium))
                        .foregroundStyle(Blur.inkSoft)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.blurRounded(16, weight: .bold))
                        .disabled(resolvedHour == nil || resolvedMinute == nil)
                }
                if focusedTimeField != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        if focusedTimeField == .hour {
                            Button("Next") { focusedTimeField = .minute }
                        }
                        Spacer()
                        Button("Done") { focusedTimeField = nil }
                            .fontWeight(.semibold)
                    }
                }
            }
            .confirmationDialog("Delete this alarm?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await store.delete(draft) {
                            dismiss()
                        }
                    }
                }
                Button("Keep", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard !mode.isEditing else { return }
            Task { @MainActor in
                await Task.yield()
                focusedTimeField = .hour
            }
        }
        .onChange(of: focusedTimeField) { _, field in
            prepareForTyping(field)
        }
    }

    // MARK: Sections

    private var timePicker: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                timeField(
                    text: $hourText,
                    placeholder: Self.uses24HourClock ? "07" : "7",
                    label: "HOUR",
                    field: .hour,
                    isValid: resolvedHour != nil
                )

                Text(":")
                    .font(.blurDigits(46, weight: .bold))
                    .foregroundStyle(Blur.inkSoft)
                    .padding(.bottom, 18)

                timeField(
                    text: $minuteText,
                    placeholder: "00",
                    label: "MIN",
                    field: .minute,
                    isValid: resolvedMinute != nil
                )

                if !Self.uses24HourClock {
                    VStack(spacing: 7) {
                        ForEach(Meridiem.allCases) { period in
                            Button {
                                meridiem = period
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Text(period.rawValue)
                                    .font(.blurRounded(13, weight: .bold))
                                    .foregroundStyle(
                                        meridiem == period
                                            ? Blur.onAccent(accent)
                                            : Blur.inkSoft
                                    )
                                    .frame(width: 50, height: 38)
                                    .background(
                                        Capsule().fill(
                                            meridiem == period
                                                ? AnyShapeStyle(accent)
                                                : AnyShapeStyle(Blur.canvas.opacity(0.6))
                                        )
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(
                                            meridiem == period ? Color.clear : Blur.hairline,
                                            lineWidth: 1
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 18)
                }
            }

            Text(nextFireHint)
                .font(.blurRounded(13, weight: .semibold))
                .foregroundStyle(Blur.onCanvas(accent))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Blur.onCanvas(accent).opacity(0.10)))
        }
        .frame(maxWidth: .infinity)
        .blurCard(.light, padding: 16, stipple: false)
    }

    private func timeField(
        text: Binding<String>,
        placeholder: String,
        label: String,
        field: TimeField,
        isValid: Bool
    ) -> some View {
        VStack(spacing: 6) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.blurDigits(42, weight: .bold))
                .foregroundStyle(Blur.ink)
                .tint(accent)
                .frame(width: 88, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Blur.canvas.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            focusedTimeField == field
                                ? accent
                                : (text.wrappedValue.isEmpty || isValid ? Blur.hairline : Blur.clay),
                            lineWidth: focusedTimeField == field ? 2 : 1
                        )
                )
                .focused($focusedTimeField, equals: field)
                .accessibilityLabel(label == "MIN" ? "Minute" : "Hour")
                .onChange(of: text.wrappedValue) { _, value in
                    updateTimeText(value, field: field)
                }

            Text(label)
                .font(.blurRounded(10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Blur.inkFaint)
        }
    }

    private var daysPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REPEAT")
                    .font(.blurRounded(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Blur.inkFaint)
                Spacer()
                Text(draft.repeatDescription)
                    .font(.blurRounded(13, weight: .semibold))
                    .foregroundStyle(Blur.onCanvas(accent))
            }

            HStack(spacing: 7) {
                ForEach(Weekday.localeOrdered) { day in
                    let isOn = draft.days.contains(day)
                    Button {
                        if isOn { draft.days.remove(day) } else { draft.days.insert(day) }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(day.initial)
                            .font(.blurRounded(15, weight: .bold))
                            .foregroundStyle(isOn ? Blur.onAccent(accent) : Blur.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                Circle().fill(isOn
                                              ? AnyShapeStyle(accent)
                                              : AnyShapeStyle(Blur.canvas.opacity(0.6)))
                            )
                            .overlay(
                                Circle().strokeBorder(
                                    isOn ? Color.clear : Blur.hairline, lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.shortName)
                    .accessibilityValue(isOn ? "On" : "Off")
                }
            }

            // Shortcuts, because these three are the overwhelming majority of
            // what people actually pick.
            HStack(spacing: 8) {
                quickDayButton("Every day", days: Weekday.all)
                quickDayButton("Weekdays", days: Weekday.weekdays)
                quickDayButton("Weekends", days: Weekday.weekend)
                quickDayButton("Once", days: [])
            }
        }
        .blurCard()
    }

    private func quickDayButton(_ title: String, days: Set<Weekday>) -> some View {
        let isActive = draft.days == days
        return Button {
            draft.days = days
        } label: {
            Text(title)
                .font(.blurRounded(12, weight: .semibold))
                .foregroundStyle(isActive ? Blur.onAccent(accent) : Blur.inkSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(isActive
                                           ? AnyShapeStyle(accent)
                                           : AnyShapeStyle(Blur.canvas.opacity(0.6))))
                .overlay(Capsule().strokeBorder(
                    isActive ? Color.clear : Blur.hairline, lineWidth: 1
                ))
        }
        .buttonStyle(.plain)
    }

    private var labelAndTone: some View {
        VStack(alignment: .leading, spacing: 16) {
            BlurField(title: "Label (optional)",
                      text: $draft.label,
                      placeholder: "Wake up",
                      accent: accent)

            VStack(alignment: .leading, spacing: 8) {
                Text("TONE")
                    .font(.blurRounded(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Blur.inkFaint)

                TonePickerRow(selection: $draft.tone, accent: accent)

                if draft.tone == .silent {
                    Text("This alarm will still show and vibrate — it just won't make a sound.")
                        .font(.blurRounded(12, weight: .medium))
                        .foregroundStyle(Blur.inkSoft)
                }
            }
        }
        .blurCard()
    }

    private var snoozePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SNOOZE")
                    .font(.blurRounded(11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Blur.inkFaint)
                Spacer()
                Text(draft.hasSnooze ? "\(draft.snoozeMinutes) min" : "Off")
                    .font(.blurRounded(13, weight: .semibold))
                    .foregroundStyle(Blur.onCanvas(accent))
            }

            HStack(spacing: 8) {
                ForEach([0, 5, 9, 10, 15], id: \.self) { minutes in
                    let isActive = draft.snoozeMinutes == minutes
                    Button {
                        draft.snoozeMinutes = minutes
                    } label: {
                        Text(minutes == 0 ? "Off" : "\(minutes)")
                            .font(.blurRounded(14, weight: .bold))
                            .foregroundStyle(isActive ? Blur.onAccent(accent) : Blur.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isActive ? AnyShapeStyle(accent) : AnyShapeStyle(Blur.canvas.opacity(0.6))))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isActive ? Color.clear : Blur.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .blurCard()
    }

    // MARK: Helpers

    private static var uses24HourClock: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)
            ?? "h a"
        return !format.contains("a")
    }

    private var resolvedHour: Int? {
        guard let value = Int(hourText) else { return nil }
        if Self.uses24HourClock {
            return (0...23).contains(value) ? value : nil
        }
        guard (1...12).contains(value) else { return nil }
        switch meridiem {
        case .am: return value == 12 ? 0 : value
        case .pm: return value == 12 ? 12 : value + 12
        }
    }

    private var resolvedMinute: Int? {
        guard let value = Int(minuteText), (0...59).contains(value) else { return nil }
        return value
    }

    private var nextFireHint: String {
        guard let hour = resolvedHour, let minute = resolvedMinute else {
            return "Enter a valid time"
        }
        var preview = draft
        preview.hour = hour
        preview.minute = minute
        guard let next = preview.nextFireDate() else { return "Won't repeat" }
        return "Rings \(next.formatted(.relative(presentation: .named, unitsStyle: .wide)))"
    }

    private func save() {
        guard let hour = resolvedHour, let minute = resolvedMinute else { return }
        draft.hour = hour
        draft.minute = minute
        // Saving an alarm always arms it — an edit you deliberately made should
        // not stay switched off.
        draft.isEnabled = true

        let entry = draft
        Task {
            if mode.isEditing {
                await store.update(entry)
            } else {
                await store.add(entry)
            }
        }
        dismiss()
    }

    private func prepareForTyping(_ field: TimeField?) {
        switch field {
        case .hour where !preparedHourField:
            preparedHourField = true
            hourText = ""
        case .minute where !preparedMinuteField:
            preparedMinuteField = true
            minuteText = ""
        default:
            break
        }
    }

    private func updateTimeText(_ value: String, field: TimeField) {
        let cleaned = String(value.filter(\.isNumber).prefix(2))
        if cleaned != value {
            switch field {
            case .hour: hourText = cleaned
            case .minute: minuteText = cleaned
            }
            return
        }

        guard cleaned.count == 2 else { return }
        switch field {
        case .hour where resolvedHour != nil:
            // A new alarm is entered as one fast HHMM run. While editing,
            // finishing the hour keeps the existing minutes intact; tapping
            // the minute field explicitly clears it for replacement.
            focusedTimeField = mode.isEditing ? nil : .minute
        case .minute where resolvedMinute != nil:
            focusedTimeField = nil
        default:
            break
        }
    }
}
