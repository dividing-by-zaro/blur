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
    @ObservationIgnored private var mutationIsLocked = false
    @ObservationIgnored private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(center: AlarmCenter = .shared) {
        self.center = center
        load()
        ingestPendingFireObservations()
        center.observeAlarmAlerts { [weak self] ids, observedAt in
            self?.recordAlertingAlarms(ids, observedAt: observedAt)
        }
    }

    // MARK: - Lists

    /// Enabled alarms stay manageable while they build history. Once an alarm
    /// reaches five rings it moves to Frequent, so the two lists never repeat a
    /// row. Inactive alarms below the threshold remain persisted but hidden.
    func scheduledAlarms(sortedBy order: AlarmSortOrder) -> [AlarmEntry] {
        sorted(alarms.filter { $0.isEnabled && !$0.isFrequentlyUsed }, by: order)
    }

    func frequentAlarms(sortedBy order: AlarmSortOrder) -> [AlarmEntry] {
        sorted(alarms.filter(\.isFrequentlyUsed), by: order)
    }

    var isEmpty: Bool {
        !alarms.contains { $0.isEnabled || $0.isFrequentlyUsed }
    }

    /// The soonest upcoming enabled alarm, shown in the header.
    var nextAlarm: (entry: AlarmEntry, date: Date)? {
        alarms
            .filter(\.isEnabled)
            .compactMap { entry in entry.nextFireDate().map { (entry, $0) } }
            .min { $0.1 < $1.1 }
    }

    // MARK: - Mutations

    func add(_ entry: AlarmEntry) async {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        // Identity is the UUID, never the clock time. Multiple alarms at the
        // same minute can have different repeat days, tones, and labels, and
        // must coexist without replacing or cancelling one another.
        alarms.append(entry)
        save()
        if entry.isEnabled {
            await applySchedule(for: entry)
        }
    }

    func update(_ entry: AlarmEntry) async {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        guard let index = alarms.firstIndex(where: { $0.id == entry.id }) else { return }
        let remembered = alarms[index]
        var replacement = entry
        // A ringing update can arrive while the editor is open. The editor's
        // stale draft must never roll usage history backwards when it saves.
        replacement.createdAt = remembered.createdAt
        replacement.fireCount = remembered.fireCount
        replacement.lastCountedOccurrence = remembered.lastCountedOccurrence
        // Any edit re-creates the AlarmKit alarm from scratch. Cheaper to reason
        // about than diffing which fields changed, and guarantees the scheduled
        // alarm matches the entry exactly. Keep the old record if cancellation
        // fails, because it still describes the alarm that can ring.
        guard center.cancel(id: entry.id) else { return }

        alarms[index] = replacement
        save()
        if replacement.isEnabled {
            await applySchedule(for: replacement)
        } else {
            unreliableIDs.remove(replacement.id)
        }
    }

    @discardableResult
    func delete(_ entry: AlarmEntry) async -> Bool {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        guard center.cancel(id: entry.id) else { return false }
        alarms.removeAll { $0.id == entry.id }
        unreliableIDs.remove(entry.id)
        save()
        return true
    }

    func delete(ids: Set<UUID>) async {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        var cancelledIDs: Set<UUID> = []
        for id in ids {
            if center.cancel(id: id) {
                cancelledIDs.insert(id)
                unreliableIDs.remove(id)
            }
        }
        alarms.removeAll { cancelledIDs.contains($0.id) }
        save()
    }

    func setEnabled(_ isEnabled: Bool, for entry: AlarmEntry) async {
        await acquireMutationLock()
        defer { releaseMutationLock() }

        guard let index = alarms.firstIndex(where: { $0.id == entry.id }) else { return }

        if isEnabled {
            alarms[index].isEnabled = true
            save()
            await applySchedule(for: alarms[index])
        } else {
            // Only show the alarm as off once the system confirms it can no
            // longer ring.
            guard center.cancel(id: entry.id) else { return }
            alarms[index].isEnabled = false
            alarms[index].armedFor = nil
            unreliableIDs.remove(entry.id)
            save()
        }
    }

    /// Stops an alarm that is currently ringing or snoozed.
    func stopRinging(_ entry: AlarmEntry) {
        if center.state(for: entry.id) == .alerting {
            recordAlertingAlarms([entry.id], observedAt: Date())
        }
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
        await acquireMutationLock()
        defer { releaseMutationLock() }

        ingestPendingFireObservations()
        guard center.refreshLiveAlarms() else {
            unreliableIDs = Set(alarms.filter(\.isEnabled).map(\.id))
            return
        }
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
                if let occurrence = entry.armedFor {
                    recordFire(for: entry.id, occurrence: occurrence)
                }
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

        // Leave every unowned AlarmKit record alone. Alarms and timers share the
        // same manager, and the timer store is intentionally memory-only, so a
        // valid timer can outlive the in-app record that originally created it.
        // Explicit alarm updates and deletes already cancel ids this store owns.

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
            // Preserve the user's enabled state. A limit or transient daemon
            // failure can clear later, and reconciliation will retry it.
            alarms[index].armedFor = nil
        }
        save()
    }

    // MARK: - Mutation serialization

    /// Actor isolation protects memory, but an `await` still lets a newer UI
    /// action overtake an older schedule request. This lock preserves request
    /// order through AlarmKit so a stale completion can never create a ghost.
    private func acquireMutationLock() async {
        if !mutationIsLocked {
            mutationIsLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func releaseMutationLock() {
        guard !mutationWaiters.isEmpty else {
            mutationIsLocked = false
            return
        }
        mutationWaiters.removeFirst().resume()
    }

    // MARK: - Usage history

    private func recordAlertingAlarms(_ ids: Set<UUID>, observedAt: Date) {
        var changed = false

        for id in ids {
            guard let entry = alarms.first(where: { $0.id == id }) else { continue }
            let occurrence = entry.mostRecentOccurrence(onOrBefore: observedAt) ?? observedAt
            changed = recordFire(for: id, occurrence: occurrence) || changed
        }

        if changed { save() }
    }

    private func ingestPendingFireObservations() {
        var changed = false

        for observation in AlarmFireObservation.consume() {
            guard let entry = alarms.first(where: { $0.id == observation.id }) else { continue }
            let occurrence = entry.mostRecentOccurrence(onOrBefore: observation.observedAt)
                ?? observation.observedAt
            changed = recordFire(for: observation.id, occurrence: occurrence) || changed
        }

        if changed { save() }
    }

    @discardableResult
    private func recordFire(for id: UUID, occurrence: Date) -> Bool {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return false }

        if let last = alarms[index].lastCountedOccurrence,
           abs(last.timeIntervalSince(occurrence)) < 60 {
            return false
        }

        alarms[index].fireCount = min(
            alarms[index].fireCount + 1,
            AlarmEntry.maximumFireCount
        )
        alarms[index].lastCountedOccurrence = occurrence
        return true
    }

    // MARK: - Sorting

    private func sorted(
        _ entries: [AlarmEntry],
        by order: AlarmSortOrder
    ) -> [AlarmEntry] {
        entries.sorted { lhs, rhs in
            switch order {
            case .mostUsed:
                if lhs.fireCount != rhs.fireCount { return lhs.fireCount > rhs.fireCount }
            case .time:
                break
            }

            if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
            if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }
            return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
        }
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
