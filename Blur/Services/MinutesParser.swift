import Foundation

/// Turns a written or spoken phrase into a minute count.
///
/// Handles the ways people actually say durations: "25", "twenty five",
/// "twenty five minutes", "an hour", "half an hour", "one and a half hours",
/// "1 hour 30".
///
/// This is the floor the app always stands on. `TimerIntentParser` reaches for
/// the on-device model to get a label and a tone out of the same phrase, but
/// falls back here whenever the model is unavailable or unsure — so a duration
/// typed into the field works on every device, in every state.
enum MinutesParser {

    static func minutes(from text: String) -> Int? {
        let lower = text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return nil }

        let mentionsHours = lower.contains("hour")
        let mentionsHalf = lower.contains("half")

        // "half an hour" / "an hour and a half" — no digits to find.
        if mentionsHours && mentionsHalf && numericValues(in: lower).isEmpty {
            return 30
        }

        let values = numericValues(in: lower)

        if mentionsHours {
            guard let hoursValue = values.first else {
                return mentionsHalf ? 30 : 60      // "an hour"
            }
            var total = hoursValue * 60
            if mentionsHalf { total += 30 }        // "one and a half hours"
            // "1 hour 30" — a second number is the trailing minutes.
            if values.count > 1 { total += values[1] }
            return total > 0 ? total : nil
        }

        guard let first = values.first else { return nil }
        return first > 0 ? first : nil
    }

    /// All numbers in the string, whether written as digits or words, in order.
    private static func numericValues(in text: String) -> [Int] {
        // Digits win — they're unambiguous and what dictation usually produces.
        let digitRuns = text
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        if !digitRuns.isEmpty { return digitRuns }

        return spelledOutValues(in: text)
    }

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "a": 1, "an": 1
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    /// Words that describe the duration itself and so can never be the label.
    static let durationVocabulary: Set<String> = {
        var words: Set<String> = [
            "min", "mins", "minute", "minutes", "hr", "hrs", "hour", "hours",
            "sec", "secs", "second", "seconds", "half", "quarter"
        ]
        words.formUnion(units.keys)
        words.formUnion(tens.keys)
        words.insert("hundred")
        return words
    }()

    /// Accumulates word-numbers like "twenty five" into 25, flushing whenever a
    /// non-number word breaks the run.
    private static func spelledOutValues(in text: String) -> [Int] {
        var results: [Int] = []
        var current: Int?

        for word in text.split(separator: " ").map(String.init) {
            if let ten = tens[word] {
                current = (current ?? 0) + ten
            } else if let unit = units[word] {
                // "a"/"an" only count as one when they precede a duration word.
                if (word == "a" || word == "an") && current == nil {
                    continue
                }
                current = (current ?? 0) + unit
            } else if word == "hundred" {
                current = max(current ?? 1, 1) * 100
            } else if word == "and" {
                continue          // "one hundred and five"
            } else if let value = current {
                results.append(value)
                current = nil
            }
        }
        if let value = current { results.append(value) }
        return results
    }
}

// MARK: - Model-free label and tone

/// The label-and-tone half of the same job, done without a language model.
///
/// `TimerIntentParser` prefers the on-device model, which reads intent properly.
/// This is what runs when the model isn't there — which is most simulators, any
/// device with Apple Intelligence off, and every ineligible device. It's crude,
/// but "30 mins for pasta" naming the timer *Pasta* is the whole point of the
/// feature, and it shouldn't vanish because a model is missing.
enum PhraseHeuristics {

    /// Strips the duration and the filler, keeps what's left as the label, and
    /// picks up a tone if one is named.
    static func labelAndTone(from text: String) -> (label: String, tone: AlarmTone?) {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        // A named tone is both the tone and a word the label must not keep.
        let tone = AlarmTone.allCases.first { candidate in
            candidate != .system && words.contains(candidate.rawValue)
        }

        let keep = words.filter { word in
            guard Int(word) == nil else { return false }
            guard !MinutesParser.durationVocabulary.contains(word) else { return false }
            guard !filler.contains(word) else { return false }
            return word != tone?.rawValue
        }

        let label = keep
            .prefix(3)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        return (String(label.prefix(24)), tone)
    }

    /// Words that survive duration-stripping but carry no meaning as a name.
    private static let filler: Set<String> = [
        "for", "the", "a", "an", "my", "to", "of", "on", "in", "and", "with",
        "please", "set", "start", "make", "timer", "alarm", "me", "up", "tone",
        "sound", "call", "it", "named", "label", "called", "no"
    ]
}
