import Foundation
import AlarmKit

// MARK: - Weekday

/// `Locale.Weekday` is what AlarmKit speaks, but it isn't `Codable` or ordered
/// in a way that's useful for a picker, so entries store this instead.
enum Weekday: Int, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    /// Single letter for the day chips. Sunday and Saturday both start with "S";
    /// that's the accepted convention and the order disambiguates them.
    var initial: String {
        switch self {
        case .sunday:    return "S"
        case .monday:    return "M"
        case .tuesday:   return "T"
        case .wednesday: return "W"
        case .thursday:  return "T"
        case .friday:    return "F"
        case .saturday:  return "S"
        }
    }

    var shortName: String {
        switch self {
        case .sunday:    return "Sun"
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        }
    }

    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday:    return .sunday
        case .monday:    return .monday
        case .tuesday:   return .tuesday
        case .wednesday: return .wednesday
        case .thursday:  return .thursday
        case .friday:    return .friday
        case .saturday:  return .saturday
        }
    }

    /// Week order starting from the user's locale first weekday, so the chip row
    /// reads M–S or S–S depending on region.
    static var localeOrdered: [Weekday] {
        let first = Calendar.current.firstWeekday          // 1 = Sunday
        return (0..<7).compactMap { offset in
            Weekday(rawValue: ((first - 1 + offset) % 7) + 1)
        }
    }

    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend: Set<Weekday> = [.saturday, .sunday]
    static let all: Set<Weekday> = Set(Weekday.allCases)
}

// MARK: - Section

/// Which section of the alarms list an entry belongs to.
///
/// Derived from how often the alarm repeats rather than being set by hand — an
/// alarm that runs every day *is* a daily alarm, and asking the user to also
/// file it under "Daily" would be busywork.
enum AlarmSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case frequent
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:    return "Daily"
        case .frequent: return "Frequent"
        case .other:    return "Other"
        }
    }

    var subtitle: String {
        switch self {
        case .daily:    return "Every day"
        case .frequent: return "Several days a week"
        case .other:    return "One-offs and single days"
        }
    }

    var accent: Color3 {
        switch self {
        case .daily:    return .pink
        case .frequent: return .green
        case .other:    return .yellow
        }
    }
}

/// Tiny indirection so the model layer doesn't have to import SwiftUI.
enum Color3: Sendable { case pink, green, yellow }

// MARK: - Alarm entry

/// The app's own record of an alarm. AlarmKit owns firing; this owns everything
/// the user typed (label, tone, chosen days) plus the enabled flag, because a
/// disabled alarm has no AlarmKit counterpart at all — it is unscheduled, and
/// re-created when toggled back on.
struct AlarmEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var label: String
    var hour: Int
    var minute: Int
    var days: Set<Weekday>
    var tone: AlarmTone
    var isEnabled: Bool
    /// Minutes added when the user taps Snooze; 0 disables the snooze button.
    var snoozeMinutes: Int
    var createdAt: Date
    /// The concrete date this alarm was last scheduled for.
    ///
    /// Reconciliation needs it to tell two cases apart when AlarmKit no longer
    /// has the alarm: a one-off that already fired (leave it off) versus one the
    /// system dropped before firing (re-schedule it). `nextFireDate()` can't
    /// distinguish them, because it always returns a future date.
    var armedFor: Date?

    init(
        id: UUID = UUID(),
        label: String = "",
        hour: Int = 7,
        minute: Int = 0,
        days: Set<Weekday> = [],
        tone: AlarmTone = .system,
        isEnabled: Bool = true,
        snoozeMinutes: Int = 9,
        createdAt: Date = Date(),
        armedFor: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.hour = hour
        self.minute = minute
        self.days = days
        self.tone = tone
        self.isEnabled = isEnabled
        self.snoozeMinutes = snoozeMinutes
        self.createdAt = createdAt
        self.armedFor = armedFor
    }

    // MARK: Derived

    var section: AlarmSection {
        switch days.count {
        case 7:      return .daily      // every day
        case 2...6:  return .frequent   // several days a week
        default:     return .other      // never repeats, or a single day
        }
    }

    var hasSnooze: Bool { snoozeMinutes > 0 }

    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Alarm" : trimmed
    }

    /// e.g. "Every day", "Weekdays", "Mon, Wed, Fri", "Once"
    var repeatDescription: String {
        if days.isEmpty { return "Once" }
        if days == Weekday.all { return "Every day" }
        if days == Weekday.weekdays { return "Weekdays" }
        if days == Weekday.weekend { return "Weekends" }
        return Weekday.localeOrdered
            .filter { days.contains($0) }
            .map(\.shortName)
            .joined(separator: ", ")
    }

    /// Localised clock string for the row, respecting 12/24-hour settings.
    var timeText: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour().minute())
    }

    /// The next moment this alarm will fire, used only for sorting and for the
    /// "rings in …" hint. AlarmKit computes the real fire date itself.
    func nextFireDate(after now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        if days.isEmpty {
            return calendar.nextDate(after: now,
                                     matching: components,
                                     matchingPolicy: .nextTime)
        }
        // Walk forward to the soonest matching weekday.
        return (0..<8).lazy.compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let candidate = calendar.date(
                      bySettingHour: hour, minute: minute, second: 0, of: day
                  ),
                  candidate > now,
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: candidate)),
                  days.contains(weekday)
            else { return nil }
            return candidate
        }.first
    }

    // MARK: AlarmKit bridging

    var schedule: Alarm.Schedule {
        let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence =
            days.isEmpty
            ? .never
            : .weekly(Weekday.localeOrdered.filter { days.contains($0) }.map(\.localeWeekday))
        return .relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
    }
}
