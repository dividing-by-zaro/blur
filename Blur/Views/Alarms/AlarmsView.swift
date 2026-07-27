import SwiftUI
import UIKit

struct AlarmsView: View {

    @Environment(AlarmStore.self) private var store
    @Environment(AlarmCenter.self) private var center

    @State private var editing: AlarmEntry?
    @State private var isCreating = false

    var body: some View {
        BlurScreen(title: "Alarms", subtitle: nextAlarmSubtitle) {
            BlurIconButton(systemName: "plus") { isCreating = true }
                .accessibilityLabel("Add alarm")
        } content: {
            if !center.isAuthorized {
                BlurWarningBanner(
                    text: "Alarm permission is off, so nothing will ring. Turn it on to let Blur break through silent mode.",
                    actionTitle: "Fix",
                    action: openSettings
                )
            }

            if store.isEmpty {
                BlurEmptyState(
                    systemName: "alarm",
                    title: "No alarms yet",
                    message: "Add one and it'll ring through silent mode and Focus."
                )
                .padding(.top, 20)
            } else {
                // Daily and Frequent sit at the top; Other collects one-offs.
                ForEach(AlarmSection.allCases) { section in
                    let entries = store.alarms(in: section)
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(
                                title: section.title,
                                accent: color(for: section),
                                count: entries.count
                            )

                            VStack(spacing: 10) {
                                ForEach(entries) { entry in
                                    AlarmRow(
                                        entry: entry,
                                        accent: color(for: section),
                                        isUnreliable: store.unreliableIDs.contains(entry.id),
                                        onToggle: { isOn in
                                            Task { await store.setEnabled(isOn, for: entry) }
                                        },
                                        onTap: { editing = entry },
                                        onDelete: { store.delete(entry) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            AlarmEditorView(mode: .create)
        }
        .sheet(item: $editing) { entry in
            AlarmEditorView(mode: .edit(entry))
        }
    }

    private var nextAlarmSubtitle: String? {
        guard let next = store.nextAlarm else { return nil }
        let relative = next.date.formatted(
            .relative(presentation: .named, unitsStyle: .wide)
        )
        return "Next: \(next.entry.displayLabel) \(relative)"
    }

    private func color(for section: AlarmSection) -> Color {
        switch section.accent {
        case .pink:   return Blur.pink
        case .green:  return Blur.green
        case .yellow: return Blur.yellow
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Row

struct AlarmRow: View {
    let entry: AlarmEntry
    let accent: Color
    let isUnreliable: Bool
    let onToggle: (Bool) -> Void
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.timeText)
                        .font(.blurDigits(30, weight: .bold))
                        // Disabled alarms fade rather than disappear, so the row
                        // still reads at a glance.
                        .foregroundStyle(entry.isEnabled ? Blur.ink : Blur.inkFaint)

                    HStack(spacing: 6) {
                        Text(entry.displayLabel)
                            .font(.blurRounded(14, weight: .semibold))
                            .foregroundStyle(entry.isEnabled ? accent : Blur.inkFaint)
                            .lineLimit(1)

                        Text("·")
                            .foregroundStyle(Blur.inkFaint)

                        Text(entry.repeatDescription)
                            .font(.blurRounded(13, weight: .medium))
                            .foregroundStyle(Blur.inkSoft)
                            .lineLimit(1)
                    }

                    if entry.tone == .silent {
                        Label("No tone", systemImage: "bell.slash.fill")
                            .font(.blurRounded(11, weight: .semibold))
                            .foregroundStyle(Blur.inkFaint)
                    }

                    if isUnreliable {
                        Label("Not scheduled — tap to fix",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.blurRounded(11, weight: .bold))
                            .foregroundStyle(Blur.pink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(get: { entry.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(accent)
        }
        .blurCard()
        .overlay(alignment: .leading) {
            // Thin accent edge; the only colour on an otherwise white card.
            if entry.isEnabled {
                Capsule()
                    .fill(accent)
                    .frame(width: 3, height: 34)
                    .padding(.leading, 5)
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onTap)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.displayLabel), \(entry.timeText), \(entry.repeatDescription)")
        .accessibilityValue(entry.isEnabled ? "On" : "Off")
    }
}
