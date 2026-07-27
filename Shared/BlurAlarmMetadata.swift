import Foundation
import AlarmKit

/// Payload AlarmKit carries alongside an alarm and hands back to the Live
/// Activity / Dynamic Island in the widget extension.
///
/// This is the only channel between the app and the widget, which is why the app
/// needs no App Group: everything the lock-screen UI has to draw travels inside
/// `AlarmAttributes.metadata`.
struct BlurAlarmMetadata: AlarmMetadata {

    enum Kind: String, Codable, Hashable, Sendable {
        case alarm
        case timer
    }

    let kind: Kind
    /// User-supplied label. Empty means "no label" — the UI falls back to the
    /// kind's generic name rather than showing a blank.
    let label: String
    /// Index used to pick which of the three accents tints this alarm, so the
    /// Live Activity matches the colour the row had in the app.
    let accentIndex: Int
    /// Original duration in seconds, for timers. Lets the widget draw progress
    /// without recomputing from the presentation state.
    let totalSeconds: Double?

    init(kind: Kind, label: String, accentIndex: Int = 0, totalSeconds: Double? = nil) {
        self.kind = kind
        self.label = label
        self.accentIndex = accentIndex
        self.totalSeconds = totalSeconds
    }

    /// Title to show when the alarm is ringing or counting down.
    var displayTitle: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return kind == .timer ? "Timer" : "Alarm"
    }
}
