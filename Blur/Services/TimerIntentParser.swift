import Foundation
import Observation
import FoundationModels

/// Turns one line of free text — typed, or spoken into the keyboard's own
/// dictation — into a timer: how long, what it's for, and which tone.
///
/// Apple's on-device model does the work, in a single guided-generation call.
/// Guided generation constrains decoding to the shape of `TimerRequest`, so the
/// tone that comes back is always a case that exists and the minutes always
/// parse — there is no free-text response to interpret.
///
/// The model is **not** a hard dependency. It's absent on ineligible hardware,
/// with Apple Intelligence switched off, or while the assets are still
/// downloading, so every path falls back to `MinutesParser`, which is what the
/// app used before and still handles the common case ("25", "an hour") on its
/// own without waking the model at all.
@MainActor
@Observable
final class TimerIntentParser {

    /// What the parser managed to understand.
    struct Result {
        var minutes: Int
        /// Empty when nothing label-like was said — the caller then falls back
        /// to whatever is in the label field.
        var label: String
        /// `nil` when no tone was named, so the caller keeps the selected one.
        var tone: AlarmTone?
        /// False when this came from `MinutesParser` rather than the model.
        var usedModel: Bool
    }

    /// How the last parse was actually answered. The model failing over to the
    /// heuristics used to be invisible, which made a timer labelled with its own
    /// duration look like a bug rather than a missing model.
    enum Route: Equatable {
        case none
        case model
        case heuristics
    }

    /// True while a model call is in flight, so the button can show it.
    private(set) var isThinking = false
    private(set) var lastRoute: Route = .none

    private var session: LanguageModelSession?

    // MARK: - Availability

    /// Whether the on-device model can run at all right now.
    var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Why the model isn't usable, phrased for a person. `nil` when it is.
    ///
    /// Deliberately not surfaced as an error anywhere — setting a timer must
    /// never fail because a language model is unavailable. It's here so the UI
    /// can explain why typing "for the pasta" stopped naming the timer.
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device can't run on-device intelligence, so timers are read as plain durations."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to name timers and pick tones by voice."
        case .unavailable(.modelNotReady):
            return "On-device intelligence is still downloading. Durations work in the meantime."
        case .unavailable:
            return "On-device intelligence isn't available, so timers are read as plain durations."
        }
    }

    /// Loads the model into memory ahead of the first real request. Called when
    /// the field takes focus, so the user's typing overlaps the warm-up rather
    /// than waiting for it.
    func prewarm() {
        guard isModelAvailable else { return }
        makeSession().prewarm()
    }

    // MARK: - Parsing

    /// Never throws and never returns nothing useful if the text contains a
    /// duration at all — the model is an enrichment over `MinutesParser`, not a
    /// replacement for it.
    func parse(_ text: String) async -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fallbackMinutes = MinutesParser.minutes(from: trimmed)

        // A bare duration has nothing for the model to add, and this is the
        // overwhelmingly common case — keep it instant.
        if isPlainDuration(trimmed), let minutes = fallbackMinutes {
            lastRoute = .heuristics
            return Result(minutes: minutes, label: "", tone: nil, usedModel: false)
        }

        guard isModelAvailable else {
            return heuristicResult(text: trimmed, minutes: fallbackMinutes)
        }

        isThinking = true
        defer { isThinking = false }

        do {
            let request = try await makeSession()
                .respond(to: trimmed, generating: TimerRequest.self)
                .content

            // The schema bounds minutes, but a model can still be wrong about
            // the number itself; anything nonsensical falls back rather than
            // starting a timer the user didn't ask for.
            guard (1...1440).contains(request.minutes) else {
                return heuristicResult(text: trimmed, minutes: fallbackMinutes)
            }

            // An empty label from the model still beats showing the duration
            // twice, so the heuristics get a turn at naming it.
            let label = Self.cleanLabel(request.label)
            let salvaged = label.isEmpty
                ? PhraseHeuristics.labelAndTone(from: trimmed).label
                : label

            lastRoute = .model
            return Result(
                minutes: request.minutes,
                label: salvaged,
                tone: request.tone.alarmTone,
                usedModel: true
            )
        } catch {
            // Guardrail trips, context overflow, model unloaded mid-call — none
            // of it should stop a timer being set.
            return heuristicResult(text: trimmed, minutes: fallbackMinutes)
        }
    }

    /// The no-model path: `MinutesParser` for the duration, `PhraseHeuristics`
    /// for the label and tone.
    private func heuristicResult(text: String, minutes: Int?) -> Result? {
        guard let minutes else { return nil }
        lastRoute = .heuristics
        let (label, tone) = PhraseHeuristics.labelAndTone(from: text)
        return Result(minutes: minutes, label: label, tone: tone, usedModel: false)
    }

    /// Drops a stale session so the next parse starts from clean context. Each
    /// timer is independent; carrying a transcript between them only invites the
    /// model to echo the previous label.
    func reset() {
        session = nil
    }

    // MARK: - Internals

    private func makeSession() -> LanguageModelSession {
        if let session { return session }
        let new = LanguageModelSession(instructions: Self.instructions)
        session = new
        return new
    }

    /// One bare duration and nothing else — "25", "25 min", "an hour".
    private func isPlainDuration(_ text: String) -> Bool {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let durationWords: Set<String> = [
            "min", "mins", "minute", "minutes", "hr", "hrs", "hour", "hours",
            "and", "a", "an", "half"
        ]
        return words.allSatisfy { word in
            durationWords.contains(word) || Int(word) != nil || Self.numberWords.contains(word)
        }
    }

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty",
        "forty", "fourty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred"
    ]

    /// Trims the model's label to something that fits a row without wrapping.
    private static func cleanLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 24 else { return String(trimmed.prefix(24)) }
        return trimmed
    }

    private static let instructions = """
        You extract timer settings from a short phrase a person typed or spoke.

        Rules:
        - minutes: the total duration in minutes. Convert hours ("an hour and a \
        half" is 90). If no duration is stated, use 0.
        - label: two or three words for what the timer is for, in title case, \
        with no duration words in it. "25 minutes for the pasta" gives "Pasta". \
        Return an empty string if the phrase is only a duration.
        - tone: only when the person names one of the available tones. Anything \
        else is system.
        """
}

// MARK: - Generated shape

/// The structure the model fills in. `@Generable` constrains decoding to this
/// shape, so every field comes back valid by construction.
@Generable
struct TimerRequest {

    @Guide(description: "Total duration in minutes. Convert any hours into minutes.",
           .range(0...1440))
    var minutes: Int

    @Guide(description: "Two or three words for what the timer is for, title case, no duration words. Empty if the phrase is only a duration.")
    var label: String

    @Guide(description: "The tone the person named. Use system when they named none.")
    var tone: ToneChoice
}

/// Mirrors `AlarmTone` rather than annotating it directly: `AlarmTone` lives in
/// `Shared/` and compiles into the widget extension too, which has no business
/// linking FoundationModels.
@Generable
enum ToneChoice {
    case system
    case radiate
    case chime
    case pulse
    case sunrise
    case beacon
    case silent

    /// `nil` for `.system` — no tone named means keep whatever is selected,
    /// rather than resetting the picker to Default behind the user's back.
    var alarmTone: AlarmTone? {
        switch self {
        case .system:  return nil
        case .radiate: return .radiate
        case .chime:   return .chime
        case .pulse:   return .pulse
        case .sunrise: return .sunrise
        case .beacon:  return .beacon
        case .silent:  return .silent
        }
    }
}
