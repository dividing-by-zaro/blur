import Foundation
import Observation
import AlarmKit

/// Tracks timers that are currently counting down.
///
/// No history, no recents: when a timer is stopped or dismissed it is removed
/// from `running` and nothing about it is kept. The store is memory-only — it is
/// rebuilt at launch from AlarmKit's live alarms, which is the only place a
/// running timer legitimately survives a relaunch.
@MainActor
@Observable
final class TimerStore {

    /// Timers the app has started and that haven't finished yet.
    private(set) var running: [TimerEntry] = []

    /// Ids the alarm store must not garbage-collect during reconciliation.
    /// Static because reconciliation runs on the alarm store, which has no
    /// reference to this one.
    nonisolated(unsafe) static var activeTimerIDs: Set<UUID> = []

    /// Tone and label carried over between quick-timer taps, so setting a tone
    /// once and then tapping 5 / 10 / 15 does what you'd expect.
    var selectedTone: AlarmTone = .system
    var pendingLabel: String = ""

    private let center: AlarmCenter
    private var accentCounter = 0

    init(center: AlarmCenter = .shared) {
        self.center = center
    }

    // MARK: - Starting

    @discardableResult
    func start(seconds: TimeInterval, label: String? = nil, tone: AlarmTone? = nil) async -> Bool {
        // Guard the range AlarmKit accepts and the range that makes sense.
        let clamped = max(1, min(seconds, 24 * 60 * 60))

        let entry = TimerEntry(
            label: label ?? pendingLabel,
            duration: clamped,
            tone: tone ?? selectedTone,
            accentIndex: nextAccentIndex()
        )

        let ok = await center.scheduleTimer(entry)
        guard ok else { return false }

        running.append(entry)
        Self.activeTimerIDs.insert(entry.id)

        // The label is a one-shot: it applies to the timer just started and then
        // clears, so the next quick tap isn't mislabelled.
        pendingLabel = ""
        return true
    }

    @discardableResult
    func start(preset: TimerPreset) async -> Bool {
        await start(seconds: preset.seconds)
    }

    // MARK: - Controlling

    func pause(_ entry: TimerEntry) {
        center.pause(id: entry.id)
        guard let index = running.firstIndex(where: { $0.id == entry.id }) else { return }
        running[index].pausedRemaining = running[index].remaining()
    }

    func resume(_ entry: TimerEntry) {
        center.resume(id: entry.id)
        guard let index = running.firstIndex(where: { $0.id == entry.id }),
              let remaining = running[index].pausedRemaining else { return }
        running[index].fireDate = Date().addingTimeInterval(remaining)
        running[index].pausedRemaining = nil
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
        center.stop(id: entry.id)
        remove(entry.id)
    }

    /// Cancels a still-counting timer and removes it.
    func cancel(_ entry: TimerEntry) {
        center.cancel(id: entry.id)
        remove(entry.id)
    }

    func cancelAll() {
        for entry in running { center.cancel(id: entry.id) }
        running.removeAll()
        Self.activeTimerIDs.removeAll()
    }

    private func remove(_ id: UUID) {
        running.removeAll { $0.id == id }
        Self.activeTimerIDs.remove(id)
    }

    // MARK: - State bridging

    func state(of entry: TimerEntry) -> Alarm.State? {
        center.state(for: entry.id)
    }

    func isRinging(_ entry: TimerEntry) -> Bool {
        center.state(for: entry.id) == .alerting
    }

    // MARK: - Reconciliation

    /// Rebuilds `running` from AlarmKit, dropping anything that finished while
    /// the app was away and re-adopting timers that are still counting.
    func reconcile() {
        center.refreshLiveAlarms()

        // Drop timers AlarmKit no longer has — they fired and were dismissed.
        running.removeAll { entry in
            guard center.alarm(for: entry.id) == nil else { return false }
            Self.activeTimerIDs.remove(entry.id)
            return true
        }

        syncPauseStates()
        Self.activeTimerIDs = Set(running.map(\.id))
    }

    /// Reconciles local pause bookkeeping with AlarmKit's view of the world.
    ///
    /// Needed because the pause and resume buttons on the Live Activity go
    /// straight to `AlarmManager` without passing through this store — without
    /// this, a timer paused from the lock screen would keep counting down here.
    func syncPauseStates() {
        let now = Date()
        for index in running.indices {
            let entry = running[index]
            switch center.state(for: entry.id) {
            case .paused where entry.pausedRemaining == nil:
                running[index].pausedRemaining = entry.remaining(at: now)
            case .countdown where entry.pausedRemaining != nil:
                let remaining = entry.pausedRemaining ?? entry.duration
                running[index].fireDate = now.addingTimeInterval(remaining)
                running[index].pausedRemaining = nil
            default:
                break
            }
        }
    }

    private func nextAccentIndex() -> Int {
        defer { accentCounter += 1 }
        return accentCounter % 3
    }
}
