import SwiftUI
import UIKit

struct AlarmEditorView: View {

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
    @State private var time: Date
    @State private var showDeleteConfirm = false

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

        var components = DateComponents()
        components.hour = entry.hour
        components.minute = entry.minute
        _time = State(initialValue: Calendar.current.date(from: components) ?? Date())
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
                }
            }
            .confirmationDialog("Delete this alarm?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(draft)
                    dismiss()
                }
                Button("Keep", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Sections

    private var timePicker: some View {
        VStack(spacing: 8) {
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()

            Text(nextFireHint)
                .font(.blurRounded(13, weight: .semibold))
                .foregroundStyle(Blur.onCanvas(accent))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Blur.onCanvas(accent).opacity(0.10)))
        }
        .frame(maxWidth: .infinity)
        // No stipple here: the wheel picker draws its own selection band, and a
        // texture running under it makes the digits fizz.
        .blurCard(.light, padding: 12, stipple: false)
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

    private var nextFireHint: String {
        var preview = draft
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        preview.hour = components.hour ?? 0
        preview.minute = components.minute ?? 0
        guard let next = preview.nextFireDate() else { return "Won't repeat" }
        return "Rings \(next.formatted(.relative(presentation: .named, unitsStyle: .wide)))"
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        draft.hour = components.hour ?? 0
        draft.minute = components.minute ?? 0
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
}
