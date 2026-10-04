import Foundation
import Observation
import AlarmKit

/// Tracks timers that are currently counting down.
///
/// No history, no recents: when a timer is stopped or dismissed it is removed
/// from `running` and from persistence. Only active records are stored, allowing
/// Blur to restore and manage a system timer that survives an app relaunch.
@MainActor
@Observable
final class TimerStore {

    /// Timers the app has started and that haven't finished yet.
    private(set) var running: [TimerEntry] = []

    private let center: AlarmCenter
    private let defaultsKey = "blur.activeTimers.v1"
    private var accentCounter = 0

    init(center: AlarmCenter = .shared) {
        self.center = center
        load()
        accentCounter = (running.map(\.accentIndex).max() ?? -1) + 1
    }

    // MARK: - Starting

    @discardableResult
    func start(seconds: TimeInterval, label: String? = nil, tone: AlarmTone? = nil) async -> Bool {
        // Guard the range AlarmKit accepts and the range that makes sense.
        let clamped = max(1, min(seconds, 24 * 60 * 60))

        let entry = TimerEntry(
            label: label ?? "",
            duration: clamped,
            tone: tone ?? .system,
            accentIndex: nextAccentIndex()
        )

        let ok = await center.scheduleTimer(entry)
        guard ok else { return false }

        running.append(entry)
        save()
        return true
    }

    @discardableResult
    func start(preset: TimerPreset) async -> Bool {
        await start(seconds: preset.seconds)
    }

    // MARK: - Controlling

    func pause(_ entry: TimerEntry) {
        guard center.pause(id: entry.id) else {
            reconcile()
            return
        }
        guard let index = running.firstIndex(where: { $0.id == entry.id }) else { return }
        running[index].pausedRemaining = running[index].remaining()
        save()
    }

    func resume(_ entry: TimerEntry) {
        guard center.resume(id: entry.id) else {
            reconcile()
            return
        }
        guard let index = running.firstIndex(where: { $0.id == entry.id }),
              let remaining = running[index].pausedRemaining else { return }
        running[index].fireDate = Date().addingTimeInterval(remaining)
        running[index].pausedRemaining = nil
        save()
    }

    func togglePause(_ entry: TimerEntry) {
        if entry.isPaused { resume(entry) } else { pause(entry) }
    }

    /// Whichever of stop/cancel is right for the timer's current state.
    func dismiss(_ entry: TimerEntry) {
        if isRinging(entry) { stop(entry) } else { cancel(entry) }
    }

    /// Stops a ringing timer and removes it.
    func stop(_ entry: TimerEntry) {
        if center.stop(id: entry.id) {
            remove(entry.id)
        }
    }

    /// Cancels a still-counting timer and removes it.
    func cancel(_ entry: TimerEntry) {
        if center.cancel(id: entry.id) {
            remove(entry.id)
        }
    }

    func cancelAll() {
        let cancelledIDs = Set(running.compactMap { entry in
            center.cancel(id: entry.id) ? entry.id : nil
        })
        running.removeAll { cancelledIDs.contains($0.id) }
        save()
    }

    private func remove(_ id: UUID) {
        running.removeAll { $0.id == id }
        save()
    }

    // MARK: - State bridging

    func state(of entry: TimerEntry) -> Alarm.State? {
        center.state(for: entry.id)
    }

    func isRinging(_ entry: TimerEntry) -> Bool {
        center.state(for: entry.id) == .alerting
    }

    // MARK: - Reconciliation

    /// Drops persisted timers AlarmKit no longer has and refreshes the local
    /// state of the active records that survived a relaunch.
    func reconcile() {
        // A failed daemon read is not evidence that any timer disappeared.
        guard center.refreshLiveAlarms() else { return }

        // Drop timers AlarmKit no longer has — they fired and were dismissed.
        let previousCount = running.count
        running.removeAll { entry in
            guard center.alarm(for: entry.id) == nil else { return false }
            return true
        }

        let stateChanged = updatePauseStates()
        if running.count != previousCount || stateChanged { save() }
    }

    /// Reconciles local pause bookkeeping with AlarmKit's view of the world.
    ///
    /// Needed because the pause and resume buttons on the Live Activity go
    /// straight to `AlarmManager` without passing through this store — without
    /// this, a timer paused from the lock screen would keep counting down here.
    func syncPauseStates() {
        if updatePauseStates() { save() }
    }

    @discardableResult
    private func updatePauseStates() -> Bool {
        let now = Date()
        var changed = false
        for index in running.indices {
            let entry = running[index]
            switch center.state(for: entry.id) {
            case .paused where entry.pausedRemaining == nil:
                running[index].pausedRemaining = entry.remaining(at: now)
                changed = true
            case .countdown where entry.pausedRemaining != nil:
                let remaining = entry.pausedRemaining ?? entry.duration
                running[index].fireDate = now.addingTimeInterval(remaining)
                running[index].pausedRemaining = nil
                changed = true
            default:
                break
            }
        }
        return changed
    }

    private func nextAccentIndex() -> Int {
        defer { accentCounter += 1 }
        return accentCounter % 3
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([TimerEntry].self, from: data)
        else { return }
        running = entries
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(running) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
