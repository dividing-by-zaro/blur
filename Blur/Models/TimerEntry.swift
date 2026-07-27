import Foundation

/// A running timer.
///
/// Deliberately transient: a timer exists while it is counting down and is gone
/// the moment it is stopped or dismissed. There is no history and no "recents"
/// list, by design — nothing here is ever written to disk.
struct TimerEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    var label: String
    /// Total length in seconds.
    var duration: TimeInterval
    var tone: AlarmTone
    var accentIndex: Int
    /// When this timer is due to ring. Recomputed on resume so a paused timer
    /// doesn't finish early.
    var fireDate: Date
    /// Seconds left at the moment it was paused; nil while counting down.
    var pausedRemaining: TimeInterval?

    init(
        id: UUID = UUID(),
        label: String = "",
        duration: TimeInterval,
        tone: AlarmTone = .system,
        accentIndex: Int = 0,
        fireDate: Date? = nil,
        pausedRemaining: TimeInterval? = nil
    ) {
        self.id = id
        self.label = label
        self.duration = duration
        self.tone = tone
        self.accentIndex = accentIndex
        self.fireDate = fireDate ?? Date().addingTimeInterval(duration)
        self.pausedRemaining = pausedRemaining
    }

    var isPaused: Bool { pausedRemaining != nil }

    /// Seconds still to run, clamped at zero.
    func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return max(0, pausedRemaining) }
        return max(0, fireDate.timeIntervalSince(now))
    }

    /// 0…1 completion, for the progress ring.
    func progress(at now: Date = Date()) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? durationText : trimmed
    }

    /// Human phrasing of the total length: "25 min", "1 hr", "1 hr 30 min".
    var durationText: String { Self.describe(seconds: duration) }

    static func describe(seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        switch (hours, minutes) {
        case (0, let m):          return "\(m) min"
        case (let h, 0):          return h == 1 ? "1 hr" : "\(h) hr"
        case (let h, let m):      return "\(h) hr \(m) min"
        }
    }
}

// MARK: - Quick presets

/// The fixed row of one-tap durations at the top of the timers screen.
struct TimerPreset: Identifiable, Hashable, Sendable {
    var minutes: Int
    var id: Int { minutes }

    var seconds: TimeInterval { TimeInterval(minutes * 60) }

    /// Compact label for the tile — "5" for minutes, "1h"/"90m"/"2h" for the
    /// longer ones, so the grid stays visually even.
    var title: String {
        if minutes < 60 { return "\(minutes)" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    var unit: String {
        minutes < 60 ? (minutes == 1 ? "min" : "min") : ""
    }

    var accessibilityLabel: String {
        "\(TimerEntry.describe(seconds: seconds)) timer"
    }

    static let all: [TimerPreset] = [
        TimerPreset(minutes: 1),
        TimerPreset(minutes: 2),
        TimerPreset(minutes: 3),
        TimerPreset(minutes: 4),
        TimerPreset(minutes: 5),
        TimerPreset(minutes: 10),
        TimerPreset(minutes: 15),
        TimerPreset(minutes: 20),
        TimerPreset(minutes: 25),
        TimerPreset(minutes: 30),
        TimerPreset(minutes: 60),
        TimerPreset(minutes: 90),
        TimerPreset(minutes: 120)
    ]
}
