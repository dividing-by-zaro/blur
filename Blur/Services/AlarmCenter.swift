import Foundation
import AlarmKit
import SwiftUI

/// Thin, single-purpose wrapper over `AlarmManager`.
///
/// Everything that talks to AlarmKit goes through here so there is exactly one
/// place where authorization, scheduling and error handling live. The stores
/// above it never touch `AlarmManager` directly.
@MainActor
@Observable
final class AlarmCenter {

    static let shared = AlarmCenter()

    /// Cached authorization state, mirrored from AlarmKit's async stream.
    private(set) var authorization: AlarmManager.AuthorizationState = .notDetermined

    /// Live snapshot of every alarm AlarmKit currently knows about, keyed by id.
    /// This — not our own persisted list — is the truth about what will ring.
    private(set) var liveAlarms: [UUID: Alarm] = [:]

    /// Set when a schedule attempt fails, so the UI can tell the user rather
    /// than silently pretending an alarm exists.
    var lastError: AlarmCenterError?

    private var observationTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var currentlyAlertingIDs: Set<UUID> = []
    @ObservationIgnored private var alarmAlertHandler: ((Set<UUID>, Date) -> Void)?

    private init() {
        authorization = AlarmManager.shared.authorizationState
        refreshLiveAlarms()
        startObserving()
    }

    // MARK: - Authorization

    /// Requests permission if it hasn't been decided yet. Returns whether we are
    /// authorized *after* the call, so callers can branch on one value.
    @discardableResult
    func ensureAuthorized() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            authorization = .authorized
            return true
        case .denied:
            authorization = .denied
            return false
        case .notDetermined:
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                authorization = state
                return state == .authorized
            } catch {
                authorization = AlarmManager.shared.authorizationState
                lastError = .authorizationFailed
                return false
            }
        @unknown default:
            return false
        }
    }

    var isAuthorized: Bool { authorization == .authorized }

    // MARK: - Observation

    /// Mirrors AlarmKit's streams into observable state. Both streams are
    /// infinite, so the tasks live for the lifetime of the app.
    private func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                await MainActor.run {
                    self.replaceLiveAlarms(with: alarms)
                }
            }
        }

        authorizationTask?.cancel()
        authorizationTask = Task { [weak self] in
            for await state in AlarmManager.shared.authorizationUpdates {
                guard let self else { return }
                await MainActor.run { self.authorization = state }
            }
        }
    }

    /// Synchronous read, used at launch before the stream has produced anything.
    @discardableResult
    func refreshLiveAlarms() -> Bool {
        do {
            let alarms = try AlarmManager.shared.alarms
            replaceLiveAlarms(with: alarms)
            return true
        } catch {
            lastError = .lifecycleFailed(action: "refresh", detail: error.localizedDescription)
            return false
        }
    }

    /// Installs the single alarm-store listener and immediately reports alarms
    /// that were already ringing when the store was created.
    func observeAlarmAlerts(_ handler: @escaping (Set<UUID>, Date) -> Void) {
        alarmAlertHandler = handler
        if !currentlyAlertingIDs.isEmpty {
            handler(currentlyAlertingIDs, Date())
        }
    }

    private func replaceLiveAlarms(with alarms: [Alarm]) {
        liveAlarms = Dictionary(
            alarms.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let alertingIDs = Set(alarms.lazy.filter { $0.state == .alerting }.map(\.id))
        let newlyAlerting = alertingIDs.subtracting(currentlyAlertingIDs)
        currentlyAlertingIDs = alertingIDs

        if !newlyAlerting.isEmpty {
            alarmAlertHandler?(newlyAlerting, Date())
        }
    }

    // MARK: - Queries

    func alarm(for id: UUID) -> Alarm? { liveAlarms[id] }

    func isScheduled(_ id: UUID) -> Bool { liveAlarms[id] != nil }

    func state(for id: UUID) -> Alarm.State? { liveAlarms[id]?.state }

    // MARK: - Scheduling

    /// Schedules a repeating or one-shot wake-up alarm.
    @discardableResult
    func scheduleAlarm(_ entry: AlarmEntry) async -> Bool {
        guard await ensureAuthorized() else {
            lastError = .notAuthorized
            return false
        }

        let accentIndex = Int(entry.id.hashValue.magnitude % 3)
        let metadata = BlurAlarmMetadata(
            kind: .alarm,
            label: entry.displayLabel,
            accentIndex: accentIndex
        )

        // Snooze is expressed as a post-alert countdown; AlarmKit runs it for us
        // when the secondary button behaviour is `.countdown`.
        let snoozeSeconds = TimeInterval(entry.snoozeMinutes * 60)
        let secondaryButton: AlarmButton? = entry.hasSnooze
            ? AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
            : nil

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: entry.displayLabel),
            secondaryButton: secondaryButton,
            secondaryButtonBehavior: entry.hasSnooze ? .countdown : nil
        )

        // A `.countdown` secondary button puts the alarm into a countdown state
        // after snoozing, so that presentation has to exist too.
        let countdown = entry.hasSnooze
            ? AlarmPresentation.Countdown(title: "Snoozed", pauseButton: nil)
            : nil

        let attributes = AlarmAttributes<BlurAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown),
            metadata: metadata,
            tintColor: swiftUIAccent(accentIndex)
        )

        let configuration = AlarmManager.AlarmConfiguration<BlurAlarmMetadata>(
            countdownDuration: entry.hasSnooze
                ? Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeSeconds)
                : nil,
            schedule: entry.schedule,
            attributes: attributes,
            stopIntent: AlarmStopObservedIntent(alarmID: entry.id),
            secondaryIntent: nil,
            sound: entry.tone.alertSound
        )

        return await schedule(id: entry.id, configuration: configuration)
    }

    /// Starts a countdown timer.
    @discardableResult
    func scheduleTimer(_ entry: TimerEntry) async -> Bool {
        guard await ensureAuthorized() else {
            lastError = .notAuthorized
            return false
        }

        let metadata = BlurAlarmMetadata(
            kind: .timer,
            label: entry.displayLabel,
            accentIndex: entry.accentIndex,
            totalSeconds: entry.duration
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: entry.displayLabel),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )

        let countdown = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: entry.displayLabel),
            pauseButton: AlarmButton(text: "Pause",
                                     textColor: .white,
                                     systemImageName: "pause.fill")
        )

        let paused = AlarmPresentation.Paused(
            title: "Paused",
            resumeButton: AlarmButton(text: "Resume",
                                      textColor: .white,
                                      systemImageName: "play.fill")
        )

        let attributes = AlarmAttributes<BlurAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert,
                                            countdown: countdown,
                                            paused: paused),
            metadata: metadata,
            tintColor: swiftUIAccent(entry.accentIndex)
        )

        let configuration = AlarmManager.AlarmConfiguration<BlurAlarmMetadata>(
            countdownDuration: Alarm.CountdownDuration(preAlert: entry.duration,
                                                       postAlert: nil),
            schedule: nil,
            attributes: attributes,
            stopIntent: AlarmStopObservedIntent(alarmID: entry.id),
            secondaryIntent: nil,
            sound: entry.tone.alertSound
        )

        return await schedule(id: entry.id, configuration: configuration)
    }

    private func schedule<M: AlarmMetadata>(
        id: UUID,
        configuration: AlarmManager.AlarmConfiguration<M>
    ) async -> Bool {
        do {
            let alarm = try await AlarmManager.shared.schedule(id: id,
                                                              configuration: configuration)
            liveAlarms[alarm.id] = alarm
            if alarm.state == .alerting {
                let wasInserted = currentlyAlertingIDs.insert(alarm.id).inserted
                if wasInserted { alarmAlertHandler?([alarm.id], Date()) }
            }
            return true
        } catch AlarmManager.AlarmError.maximumLimitReached {
            lastError = .limitReached
            return false
        } catch {
            lastError = .scheduleFailed(error.localizedDescription)
            return false
        }
    }

    // MARK: - Lifecycle commands

    /// Removes an alarm entirely. A missing id already satisfies the request.
    @discardableResult
    func cancel(id: UUID) -> Bool {
        do {
            try AlarmManager.shared.cancel(id: id)
            liveAlarms[id] = nil
            currentlyAlertingIDs.remove(id)
            return true
        } catch {
            let refreshed = refreshLiveAlarms()
            if refreshed && liveAlarms[id] == nil {
                currentlyAlertingIDs.remove(id)
                return true
            }
            lastError = .lifecycleFailed(action: "cancel", detail: error.localizedDescription)
            return false
        }
    }

    /// Stops the current occurrence or countdown. Repeating schedules survive.
    @discardableResult
    func stop(id: UUID) -> Bool {
        do {
            try AlarmManager.shared.stop(id: id)
            refreshLiveAlarms()
            return true
        } catch {
            let refreshed = refreshLiveAlarms()
            if refreshed && liveAlarms[id] == nil { return true }
            lastError = .lifecycleFailed(action: "stop", detail: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func pause(id: UUID) -> Bool {
        do {
            try AlarmManager.shared.pause(id: id)
            refreshLiveAlarms()
            return true
        } catch {
            refreshLiveAlarms()
            lastError = .lifecycleFailed(action: "pause", detail: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func resume(id: UUID) -> Bool {
        do {
            try AlarmManager.shared.resume(id: id)
            refreshLiveAlarms()
            return true
        } catch {
            refreshLiveAlarms()
            lastError = .lifecycleFailed(action: "resume", detail: error.localizedDescription)
            return false
        }
    }

    // MARK: - Helpers

    private func swiftUIAccent(_ index: Int) -> Color {
        Blur.accent(index)
    }
}

// MARK: - Errors

enum AlarmCenterError: Identifiable, Equatable {
    case notAuthorized
    case authorizationFailed
    case limitReached
    case scheduleFailed(String)
    case lifecycleFailed(action: String, detail: String)

    var id: String { message }

    var title: String {
        switch self {
        case .notAuthorized, .authorizationFailed: return "Alarms Are Off"
        case .limitReached:                        return "Too Many Alarms"
        case .scheduleFailed:                      return "Couldn’t Schedule"
        case .lifecycleFailed(let action, _):       return "Couldn’t \(action.capitalized)"
        }
    }

    var message: String {
        switch self {
        case .notAuthorized:
            return "Blur needs permission to set alarms. Turn it on in Settings › Blur so your alarms can ring through silent mode."
        case .authorizationFailed:
            return "Something went wrong asking for alarm permission. Try again."
        case .limitReached:
            return "iOS limits how many alarms an app can schedule at once. Delete or turn off an alarm to make room."
        case .scheduleFailed(let detail):
            return "The alarm couldn’t be scheduled: \(detail)"
        case .lifecycleFailed(let action, let detail):
            return "The \(action) didn’t complete, so Blur kept the existing alarm or timer: \(detail)"
        }
    }
}
