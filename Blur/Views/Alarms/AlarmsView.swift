import SwiftUI
import UIKit

struct AlarmsView: View {

    @Environment(AlarmStore.self) private var store
    @Environment(AlarmCenter.self) private var center

    @State private var editing: AlarmEntry?
    @State private var isCreating = false
    @AppStorage("blur.alarmSortOrder") private var sortOrderRaw = AlarmSortOrder.mostUsed.rawValue

    var body: some View {
        BlurScreen(title: "Alarms", subtitle: store.isEmpty ? nil : "Frequent after 5 rings") {
            HStack(spacing: 8) {
                sortMenu
                BlurIconButton(systemName: "plus") { isCreating = true }
                    .accessibilityLabel("Add alarm")
            }
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
                    message: "Scheduled alarms appear right away. After one rings 5 times, Blur remembers it as Frequent."
                )
                .padding(.top, 16)
            } else {
                if let next = store.nextAlarm {
                    NextAlarmCard(entry: next.entry, date: next.date)
                }

                scheduledGroup
                frequentGroup
            }
        }
        .sheet(isPresented: $isCreating) {
            AlarmEditorView(mode: .create)
        }
        .sheet(item: $editing) { entry in
            AlarmEditorView(mode: .edit(entry))
        }
    }

    // MARK: Groups

    @ViewBuilder
    private var scheduledGroup: some View {
        let entries = store.scheduledAlarms(sortedBy: sortOrder)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Scheduled",
                              accent: Blur.lilac,
                              count: entries.count)

                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle()
                                .fill(Blur.onDarkLine)
                                .frame(height: 1)
                                .padding(.leading, 4)
                        }

                        AlarmRow(
                            entry: entry,
                            accent: Blur.lilac,
                            surface: .dark,
                            isUnreliable: store.unreliableIDs.contains(entry.id),
                            onToggle: { isOn in
                                Task { await store.setEnabled(isOn, for: entry) }
                            },
                            onTap: { editing = entry },
                            onDelete: { Task { await store.delete(entry) } }
                        )
                        .padding(.vertical, 12)
                    }
                }
                .blurCard(.dark, padding: 16)
            }
        }
    }

    @ViewBuilder
    private var frequentGroup: some View {
        let entries = store.frequentAlarms(sortedBy: sortOrder)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Frequent",
                              accent: Blur.blue,
                              count: entries.count)

                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        AlarmRow(
                            entry: entry,
                            accent: Blur.blue,
                            surface: .light,
                            isUnreliable: store.unreliableIDs.contains(entry.id),
                            onToggle: { isOn in
                                Task { await store.setEnabled(isOn, for: entry) }
                            },
                            onTap: { editing = entry },
                            onDelete: { Task { await store.delete(entry) } }
                        )
                        .blurCard(.light)
                    }
                }
            }
        }
    }

    private var sortOrder: AlarmSortOrder {
        AlarmSortOrder(rawValue: sortOrderRaw) ?? .mostUsed
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort alarms", selection: $sortOrderRaw) {
                ForEach(AlarmSortOrder.allCases) { order in
                    Text(order.title).tag(order.rawValue)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .bold))
                Text(sortOrder.title)
                    .font(.blurRounded(12, weight: .bold))
            }
            .foregroundStyle(Blur.ink)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Blur.hairline, lineWidth: 1))
        }
        .accessibilityLabel("Sort alarms")
        .accessibilityValue(sortOrder.title)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Next alarm

/// The screen's one summary object, in the shape of the reference's status
/// card: a light panel with a single number carrying it and everything else
/// dropped back to a label.
private struct NextAlarmCard: View {
    let entry: AlarmEntry
    let date: Date

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT ALARM")
                    .font(.blurRounded(11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Blur.inkFaint)

                Text(entry.timeText)
                    .font(.blurDigits(40, weight: .bold))
                    .foregroundStyle(Blur.ink)

                Text("\(entry.displayLabel) · \(relative)")
                    .font(.blurRounded(13, weight: .medium))
                    .foregroundStyle(Blur.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            // A three-quarter turn of periwinkle over a tan track: enough
            // colour to anchor the card without putting type on a light fill.
            ZStack {
                Circle()
                    .stroke(Blur.tan.opacity(0.6), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(Blur.wave, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "alarm.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Blur.ink)
            }
            .frame(width: 68, height: 68)
        }
        .blurCard(.light, padding: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next alarm, \(entry.displayLabel) at \(entry.timeText), \(relative)")
    }

    private var relative: String {
        date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}

// MARK: - Row

struct AlarmRow: View {
    let entry: AlarmEntry
    let accent: Color
    var surface: BlurSurface = .light
    let isUnreliable: Bool
    let onToggle: (Bool) -> Void
    let onTap: () -> Void
    let onDelete: () -> Void

    /// The accent resolved for whichever surface the row landed on — blue
    /// lightens to pale denim on charcoal, yellow stays gold there but drops to
    /// amber on ivory.
    private var tint: Color { surface.tint(accent) }

    var body: some View {
        HStack(spacing: 12) {
            // Enabled alarms carry a short accent bar; disabled ones leave the
            // slot empty so the row still occupies the same width.
            Capsule()
                .fill(entry.isEnabled ? tint : Color.clear)
                .frame(width: 3, height: 40)

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.timeText)
                        .font(.blurDigits(30, weight: .bold))
                        // Disabled alarms fade rather than disappear, so the row
                        // still reads at a glance.
                        .foregroundStyle(entry.isEnabled ? surface.ink : surface.inkFaint)

                    HStack(spacing: 6) {
                        Text(entry.displayLabel)
                            .font(.blurRounded(14, weight: .semibold))
                            .foregroundStyle(entry.isEnabled ? tint : surface.inkFaint)
                            .lineLimit(1)

                        Text("·")
                            .foregroundStyle(surface.inkFaint)

                        Text(entry.repeatDescription)
                            .font(.blurRounded(13, weight: .medium))
                            .foregroundStyle(surface.inkSoft)
                            .lineLimit(1)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(entry.fireCountText) \(entry.fireCount == 1 ? "ring" : "rings")")
                            .font(.blurDigits(11, weight: .bold))
                    }
                    .foregroundStyle(tint)

                    if entry.tone == .silent {
                        Label("No tone", systemImage: "bell.slash.fill")
                            .font(.blurRounded(11, weight: .semibold))
                            .foregroundStyle(surface.inkFaint)
                    }

                    if isUnreliable {
                        Label("Not scheduled — tap to fix",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.blurRounded(11, weight: .bold))
                            // Clay is a dark warm red — on charcoal it drops to
                            // 2.7:1, so the pair's light form takes over.
                            .foregroundStyle(surface.tint(Blur.clay))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(get: { entry.isEnabled }, set: onToggle))
                .labelsHidden()
                // The track is a fill, and the knob on it is white, so this
                // wants the light form on either surface.
                .tint(Blur.onCharcoal(accent))
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onTap)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.displayLabel), \(entry.timeText), \(entry.repeatDescription)")
        .accessibilityValue("\(entry.isEnabled ? "On" : "Off"), \(fireCountAccessibility)")
    }

    private var fireCountAccessibility: String {
        entry.fireCount >= AlarmEntry.maximumFireCount
            ? "99 or more rings"
            : "\(entry.fireCount) \(entry.fireCount == 1 ? "ring" : "rings")"
    }
}
