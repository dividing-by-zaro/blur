import Foundation
import Observation

/// Start / stop / reset stopwatch. No laps — by design.
///
/// Elapsed time is derived from wall-clock dates rather than accumulated by a
/// ticking counter, so backgrounding the app, locking the phone, or dropped
/// timer ticks can't make it drift. The display timer only drives redraws.
@MainActor
@Observable
final class StopwatchModel {

    enum Mode: Equatable { case idle, running, stopped }

    private(set) var mode: Mode = .idle

    /// Seconds banked from previous run segments.
    private var accumulated: TimeInterval = 0
    /// When the current segment began; nil when not running.
    private var segmentStart: Date?

    /// Bumped by the display timer purely to invalidate the view.
    private var tick: Int = 0

    private var displayTimer: Timer?

    private let accumulatedKey = "blur.stopwatch.accumulated"
    private let startKey = "blur.stopwatch.segmentStart"

    init() {
        restore()
    }

    // MARK: - Elapsed

    var elapsed: TimeInterval {
        _ = tick   // read so @Observable re-evaluates on each display tick
        guard let segmentStart else { return accumulated }
        return accumulated + Date().timeIntervalSince(segmentStart)
    }

    var isRunning: Bool { mode == .running }

    /// "MM:SS.hh", growing to "H:MM:SS.hh" past an hour.
    var formatted: String {
        let total = max(0, elapsed)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        let hundredths = Int((total.truncatingRemainder(dividingBy: 1)) * 100)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, hundredths)
        }
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    // MARK: - Controls

    func start() {
        guard mode != .running else { return }
        segmentStart = Date()
        mode = .running
        persist()
        startDisplayTimer()
    }

    func stop() {
        guard mode == .running, let segmentStart else { return }
        accumulated += Date().timeIntervalSince(segmentStart)
        self.segmentStart = nil
        mode = .stopped
        persist()
        stopDisplayTimer()
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func reset() {
        accumulated = 0
        segmentStart = nil
        mode = .idle
        persist()
        stopDisplayTimer()
    }

    // MARK: - Display timer

    /// 1/60s so the hundredths digits animate smoothly. Only alive while running.
    private func startDisplayTimer() {
        stopDisplayTimer()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick &+= 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    /// Called when the app returns to the foreground: the elapsed value is
    /// already correct (it's date-derived), the timer just needs restarting.
    func refreshAfterForeground() {
        if mode == .running { startDisplayTimer() }
    }

    func pauseDisplayForBackground() {
        stopDisplayTimer()
    }

    // MARK: - Persistence

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(accumulated, forKey: accumulatedKey)
        if let segmentStart {
            defaults.set(segmentStart.timeIntervalSince1970, forKey: startKey)
        } else {
            defaults.removeObject(forKey: startKey)
        }
    }

    private func restore() {
        let defaults = UserDefaults.standard
        accumulated = defaults.double(forKey: accumulatedKey)

        if defaults.object(forKey: startKey) != nil {
            segmentStart = Date(timeIntervalSince1970: defaults.double(forKey: startKey))
            mode = .running
            startDisplayTimer()
        } else {
            mode = accumulated > 0 ? .stopped : .idle
        }
    }
}
