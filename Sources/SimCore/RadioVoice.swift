import Foundation

/// One radio call the simulation wants spoken. The simulation has already decided everything in it; a voice may only
/// change how it is worded.
public struct RadioUtterance: Equatable {
    public enum Speaker: String { case pilot, controller }
    public let speaker: Speaker
    public let callsignSpoken: String
    /// The template wording. Always safe to show.
    public let template: String

    public init(speaker: Speaker, callsignSpoken: String, template: String) {
        self.speaker = speaker
        self.callsignSpoken = callsignSpoken
        self.template = template
    }
}

/// Something that can offer a different wording for an utterance. Nil means "use the template".
public protocol RadioVoice {
    func variant(for utterance: RadioUtterance) async -> String?
}

/// The default voice: always the template.
public struct TemplateVoice: RadioVoice {
    public init() {}
    public func variant(for utterance: RadioUtterance) async -> String? { nil }
}

/// Accepts a reworded call only if it says exactly what the template says: every spoken number, fix name and the
/// callsign survive, nothing numeric or fix-like is added, and it stays short and on one line.
public enum RadioVerifier {
    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "niner", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "decimal", "point", "left", "right", "centre", "center",
    ]

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
    }

    /// Words that carry facts: spoken numbers and digits, plus capitalised fix-like names (all caps or Title case
    /// words that are not the first word).
    static func factWords(_ text: String) -> [String] {
        words(text).filter { numberWords.contains($0) || $0.contains(where: \.isNumber) }
    }

    public static func accepts(_ variant: String, for u: RadioUtterance) -> Bool {
        let v = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, !v.contains("\n"), v.count <= u.template.count * 3 / 2 + 20 else { return false }
        // No chatter: at most four extra words.
        guard words(v).count <= words(u.template).count + 4 else { return false }
        // The callsign must be present as spoken; it may move, so it is taken out before the facts are compared.
        guard v.range(of: u.callsignSpoken, options: .caseInsensitive) != nil else { return false }
        func withoutCallsign(_ text: String) -> String {
            text.replacingOccurrences(of: u.callsignSpoken, with: " ", options: .caseInsensitive)
        }
        // Same spoken numbers and directions, in the same order.
        guard factWords(withoutCallsign(v)) == factWords(withoutCallsign(u.template)) else { return false }
        // Every word of the callsign and every non-number content word that names something (4+ letters, not common
        // English) must survive: simplest safe rule is that all words longer than 3 letters that are in the template's
        // capitalised tokens (fixes, runway names, airline) appear in the variant.
        let templateNames = u.template.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { token in token.count >= 3 && token == token.uppercased() && token.contains(where: \.isLetter) }
            .map { $0.lowercased() }
        let variantWords = Set(words(v))
        guard templateNames.allSatisfy({ variantWords.contains($0) }) else { return false }
        // No new capitalised names invented.
        let variantNames = v.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { token in token.count >= 3 && token == token.uppercased() && token.contains(where: \.isLetter) }
            .map { $0.lowercased() }
        return Set(variantNames).isSubset(of: Set(templateNames))
    }

    /// The text to show: the variant if it passes, otherwise the template.
    public static func choose(variant: String?, for u: RadioUtterance) -> String {
        if let variant, accepts(variant, for: u) { return variant }
        return u.template
    }
}
