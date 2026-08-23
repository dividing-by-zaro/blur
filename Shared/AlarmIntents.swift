import AppIntents
import AlarmKit
import Foundation

/// A durable hand-off from AlarmKit's Stop intent to `AlarmStore`. The app can
/// be suspended for the entire alert, so its live update stream is not the only
/// evidence that an alarm genuinely rang.
enum AlarmFireObservation {
    private static let defaultsKey = "blur.pendingAlarmFireObservations.v1"
    private struct Stored: Codable {
        let id: UUID
        let observedAt: Date
    }

    static func record(id: UUID, at date: Date = Date()) {
        var observations = load()
        observations.append(Stored(id: id, observedAt: date))
        guard let data = try? JSONEncoder().encode(observations) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func consume() -> [(id: UUID, observedAt: Date)] {
        let observations = load()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return observations.map { ($0.id, $0.observedAt) }
    }

    private static func load() -> [Stored] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Stored].self, from: data)) ?? []
    }
}

/// Intents wired to the buttons AlarmKit renders on the lock screen, in the
/// Dynamic Island, and on the full-screen alert.
///
/// `LiveActivityIntent` runs in the **app's** process, so these can talk to
/// `AlarmManager` directly and the app's own state stays in sync without any
/// shared container.

// MARK: - Stop

/// AlarmKit runs a configuration's stop intent after it has already performed
/// the native stop transition. This intent therefore records the ring without
/// issuing a second stop, which could remove the next occurrence of a repeating
/// alarm.
struct AlarmStopObservedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Record Stop"
    static var description = IntentDescription("Records a system-handled alarm stop.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            AlarmFireObservation.record(id: id)
        }
        return .result()
    }
}

/// Used by buttons in Blur's custom Live Activity. Unlike AlarmKit's native
/// stop button, a direct `Button(intent:)` does not perform a lifecycle change
/// for us, so this intent must issue exactly one stop itself.
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"
    static var description = IntentDescription("Stops a ringing alarm or timer.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try AlarmManager.shared.stop(id: id)
            AlarmFireObservation.record(id: id)
        }
        return .result()
    }
}

// MARK: - Pause / Resume (timers)

struct PauseAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause"
    static var description = IntentDescription("Pauses a running timer.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try AlarmManager.shared.pause(id: id)
        }
        return .result()
    }
}

struct ResumeAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume"
    static var description = IntentDescription("Resumes a paused timer.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try AlarmManager.shared.resume(id: id)
        }
        return .result()
    }
}
