import Foundation
import Observation

/// Owns the user's alarms: persistence, ordering into sections, and keeping
/// AlarmKit in step with what's on screen.
///
/// The reliability rule this class enforces: **an enabled entry always has a
/// live AlarmKit alarm with the same id.** `reconcile()` re-asserts that on every
/// launch and every foreground, so an alarm can never be "on" in the UI while
/// being absent from the system.
@MainActor
@Observable
final class AlarmStore {

    private(set) var alarms: [AlarmEntry] = []

    /// Set when reconciliation could not restore an alarm, so the UI can warn
    /// instead of showing a toggle that lies.
    private(set) var unreliableIDs: Set<UUID> = []

    private let center: AlarmCenter
    private let defaultsKey = "blur.alarms.v1"

    init(center: AlarmCenter = .shared) {
        self.center = center
        load()
    }

    // MARK: - Sections

    func alarms(in section: AlarmSection) -> [AlarmEntry] {
        alarms
            .filter { $0.section == section }
            .sorted { lhs, rhs in
                // Chronological by time of day, then by label for a stable order.
                if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
                if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }
                return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
            }
    }

    var isEmpty: Bool { alarms.isEmpty }

    /// The soonest upcoming enabled alarm, shown in the header.
    var nextAlarm: (entry: AlarmEntry, date: Date)? {
        alarms
            .filter(\.isEnabled)
            .compactMap { entry in entry.nextFireDate().map { (entry, $0) } }
            .min { $0.1 < $1.1 }
    }

    // MARK: - Mutations

    func add(_ entry: AlarmEntry) async {
        alarms.append(entry)
        save()
        if entry.isEnabled {
            await applySchedule(for: entry)
        }
    }

    func update(_ entry: AlarmEntry) async {
        guard let index = alarms.firstIndex(where: { $0.id == entry.id }) else { return }
        alarms[index] = entry
        save()

        // Any edit re-creates the AlarmKit alarm from scratch. Cheaper to reason
        // about than diffing which fields changed, and guarantees the scheduled
        // alarm matches the entry exactly.
        center.cancel(id: entry.id)
        if entry.isEnabled {
            await applySchedule(for: entry)
        } else {
            unreliableIDs.remove(entry.id)
        }
    }

    func delete(_ entry: AlarmEntry) {
        alarms.removeAll { $0.id == entry.id }
        unreliableIDs.remove(entry.id)
        center.cancel(id: entry.id)
        save()
    }

    func delete(ids: Set<UUID>) {
        for id in ids {
            center.cancel(id: id)
            unreliableIDs.remove(id)
        }
        alarms.removeAll { ids.contains($0.id) }
        save()
    }

    func setEnabled(_ isEnabled: Bool, for entry: AlarmEntry) async {
        guard let index = alarms.firstIndex(where: { $0.id == entry.id }) else { return }
        alarms[index].isEnabled = isEnabled
        save()

        if isEnabled {
            await applySchedule(for: alarms[index])
        } else {
            center.cancel(id: entry.id)
            unreliableIDs.remove(entry.id)
        }
    }

    /// Stops an alarm that is currently ringing or snoozed.
    func stopRinging(_ entry: AlarmEntry) {
        center.stop(id: entry.id)
    }

    // MARK: - Reconciliation

    /// Re-asserts that every enabled entry is actually scheduled with AlarmKit.
    ///
    /// Called at launch and whenever the app returns to the foreground. Alarms
    /// can go missing legitimately — a one-shot alarm is consumed after it
    /// fires, and the system may drop alarms if authorization was revoked — so
    /// this is the mechanism that makes "the toggle is on" mean "it will ring".
    func reconcile() async {
        center.refreshLiveAlarms()
        guard center.isAuthorized else {
            // Without permission nothing is scheduled; flag every enabled alarm
            // rather than leaving the UI looking healthy.
            unreliableIDs = Set(alarms.filter(\.isEnabled).map(\.id))
            return
        }

        var stillUnreliable: Set<UUID> = []
        let now = Date()

        for entry in alarms where entry.isEnabled {
            if center.isScheduled(entry.id) { continue }

            // A one-off whose armed time has passed was consumed by firing.
            // Switch it off rather than silently re-arming it for tomorrow.
            let firedAndDone = entry.days.isEmpty
                && (entry.armedFor.map { $0 <= now } ?? false)

            if firedAndDone {
                if let index = alarms.firstIndex(where: { $0.id == entry.id }) {
                    alarms[index].isEnabled = false
                    alarms[index].armedFor = nil
                }
            } else {
                // Either a repeating alarm, or a one-off the system lost before
                // it fired — both should be put back.
                await applySchedule(for: entry)
                if unreliableIDs.contains(entry.id) { stillUnreliable.insert(entry.id) }
            }
        }

        // Drop AlarmKit alarms with no matching entry — leftovers from a delete
        // that didn't complete, or from a previous install.
        let knownIDs = Set(alarms.map(\.id))
        for id in center.liveAlarms.keys where !knownIDs.contains(id) {
            // Timers live in AlarmKit too and are not in `alarms`; only remove
            // ids the timer store isn't tracking.
            if !TimerStore.activeTimerIDs.contains(id) {
                center.cancel(id: id)
            }
        }

        unreliableIDs = stillUnreliable
        save()
    }

    private func applySchedule(for entry: AlarmEntry) async {
        let ok = await center.scheduleAlarm(entry)
        guard let index = alarms.firstIndex(where: { $0.id == entry.id }) else { return }

        if ok {
            unreliableIDs.remove(entry.id)
            // Record the concrete date so reconciliation can later tell a fired
            // one-off from one the system dropped.
            alarms[index].armedFor = entry.nextFireDate()
        } else {
            unreliableIDs.insert(entry.id)
            // Don't leave a toggle on for an alarm that will never ring.
            alarms[index].isEnabled = false
            alarms[index].armedFor = nil
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            alarms = try JSONDecoder().decode([AlarmEntry].self, from: data)
        } catch {
            alarms = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
