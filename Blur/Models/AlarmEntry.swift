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

// MARK: - Sorting

enum AlarmSortOrder: String, CaseIterable, Identifiable, Sendable {
    case mostUsed
    case time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostUsed: return "Most used"
        case .time:     return "Time"
        }
    }
}

// MARK: - Alarm entry

/// The app's own record of an alarm. AlarmKit owns firing; this owns everything
/// the user typed (label, tone, chosen days) plus the enabled flag, because a
/// disabled alarm has no AlarmKit counterpart at all — it is unscheduled, and
/// re-created when toggled back on.
struct AlarmEntry: Identifiable, Codable, Hashable, Sendable {
    /// Five observed rings earns a place in the remembered Frequent list.
    static let frequentUseThreshold = 5
    /// `100` is the internal sentinel displayed as "99+".
    static let maximumFireCount = 100

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
    /// Number of distinct scheduled occurrences observed in AlarmKit's
    /// `.alerting` state. Saturates at `100`, which the UI presents as "99+".
    var fireCount: Int
    /// The concrete occurrence represented by the last increment. AlarmKit can
    /// enter `.alerting` again after a snooze, so this prevents double-counting.
    var lastCountedOccurrence: Date?
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
        fireCount: Int = 0,
        lastCountedOccurrence: Date? = nil,
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
        self.fireCount = min(max(fireCount, 0), Self.maximumFireCount)
        self.lastCountedOccurrence = lastCountedOccurrence
        self.armedFor = armedFor
    }

    // MARK: Derived

    var isFrequentlyUsed: Bool { fireCount >= Self.frequentUseThreshold }

    var fireCountText: String { fireCount >= 100 ? "99+" : "\(fireCount)" }

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

    /// The scheduled occurrence responsible for an observed alert. Walking
    /// backwards means a snooze still resolves to the original ring time.
    func mostRecentOccurrence(onOrBefore observedAt: Date) -> Date? {
        if days.isEmpty {
            return armedFor
        }

        let calendar = Calendar.current
        // AlarmKit updates can arrive just before the clock rolls to the exact
        // minute, so allow a small tolerance without turning a snooze into a
        // different occurrence.
        let upperBound = observedAt.addingTimeInterval(60)

        return (0..<8).lazy.compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: observedAt),
                  let candidate = calendar.date(
                      bySettingHour: hour, minute: minute, second: 0, of: day
                  ),
                  candidate <= upperBound,
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: candidate)),
                  days.contains(weekday)
            else { return nil }
            return candidate
        }.first
    }

    // MARK: Codable migration

    /// `fireCount` was added after the first persisted schema shipped. Decode
    /// it permissively so existing alarms migrate with a zero count instead of
    /// causing the whole saved list to be discarded.
    private enum CodingKeys: String, CodingKey {
        case id, label, hour, minute, days, tone, isEnabled, snoozeMinutes
        case createdAt, fireCount, lastCountedOccurrence, armedFor
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        label = try values.decode(String.self, forKey: .label)
        hour = try values.decode(Int.self, forKey: .hour)
        minute = try values.decode(Int.self, forKey: .minute)
        days = try values.decode(Set<Weekday>.self, forKey: .days)
        tone = try values.decode(AlarmTone.self, forKey: .tone)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        snoozeMinutes = try values.decode(Int.self, forKey: .snoozeMinutes)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        fireCount = min(
            max(try values.decodeIfPresent(Int.self, forKey: .fireCount) ?? 0, 0),
            Self.maximumFireCount
        )
        lastCountedOccurrence = try values.decodeIfPresent(
            Date.self,
            forKey: .lastCountedOccurrence
        )
        armedFor = try values.decodeIfPresent(Date.self, forKey: .armedFor)
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
