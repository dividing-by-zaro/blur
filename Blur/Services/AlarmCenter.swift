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
                    self.liveAlarms = Dictionary(
                        alarms.map { ($0.id, $0) },
                        uniquingKeysWith: { _, latest in latest }
                    )
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
    func refreshLiveAlarms() {
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        liveAlarms = Dictionary(alarms.map { ($0.id, $0) },
                                uniquingKeysWith: { _, latest in latest })
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

        let accentIndex = abs(entry.id.hashValue) % 3
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
            stopIntent: StopAlarmIntent(alarmID: entry.id),
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
            stopIntent: StopAlarmIntent(alarmID: entry.id),
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
            lastError = nil
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

    /// Removes an alarm entirely. Safe to call for ids AlarmKit doesn't know.
    func cancel(id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
        liveAlarms[id] = nil
    }

    func stop(id: UUID) {
        try? AlarmManager.shared.stop(id: id)
    }

    func pause(id: UUID) {
        try? AlarmManager.shared.pause(id: id)
    }

    func resume(id: UUID) {
        try? AlarmManager.shared.resume(id: id)
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

    var id: String { message }

    var title: String {
        switch self {
        case .notAuthorized, .authorizationFailed: return "Alarms Are Off"
        case .limitReached:                        return "Too Many Alarms"
        case .scheduleFailed:                      return "Couldn’t Schedule"
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
        }
    }
}
