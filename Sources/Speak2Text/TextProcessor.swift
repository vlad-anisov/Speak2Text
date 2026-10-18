import Foundation

/// Post-processing of the final text: user replacements, then filler words.
enum TextProcessor {
    private static let wordChar = "[\\p{L}\\p{N}_]"

    private static func phrasePattern(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
    }

    static func process(_ text: String, replacements: [Replacement], fillers: [String]?) -> String {
        var t = text
        if let f = fillers { t = removeFillers(t, fillers: f) }
        t = applyReplacements(t, replacements)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyReplacements(_ text: String, _ list: [Replacement]) -> String {
        var t = text
        for r in list {
            let from = r.from.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !from.isEmpty,
                  let re = try? NSRegularExpression(pattern: "(?<!\(wordChar))\(phrasePattern(from))(?!\(wordChar))", options: [.caseInsensitive])
            else { continue }
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: NSRegularExpression.escapedTemplate(for: r.to))
        }
        return t
    }

    /// Removes filler words together with the commas around them; keeps the next word capitalised when the filler opened a sentence.
    static func removeFillers(_ text: String, fillers: [String]) -> String {
        let words = fillers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }.map(phrasePattern)
        guard !words.isEmpty,
              let re = try? NSRegularExpression(pattern: "(,\\s*)?(?<!\(wordChar))(?:\(words.joined(separator: "|")))(?!\(wordChar))(\\s*,)?", options: [.caseInsensitive])
        else { return text }
        var t = text
        for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
            guard let r = Range(m.range, in: t) else { continue }
            let hasLead = m.range(at: 1).location != NSNotFound, hasTrail = m.range(at: 2).location != NSNotFound
            let before = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let atStart = before.isEmpty || before.hasSuffix(".") || before.hasSuffix("!") || before.hasSuffix("?") || before.hasSuffix("…")
            let wasCapital = t[r].first(where: { $0.isLetter })?.isUppercase ?? false
            t.replaceSubrange(r, with: hasLead && hasTrail ? "," : "")
            if atStart && wasCapital {
                // capitalise the next letter
                var i = r.lowerBound
                while i < t.endIndex, !t[i].isLetter, !t[i].isNumber, t[i] == " " || t[i] == "," { i = t.index(after: i) }
                if i < t.endIndex, t[i].isLowercase { t.replaceSubrange(i...i, with: t[i].uppercased()) }
            }
        }
        // tidy spaces and punctuation left behind
        t = t.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "^[\\s,]+", with: "", options: .regularExpression)
        return t
    }

    static func current(_ text: String) -> String {
        let s = Settings.shared
        return process(text, replacements: s.replacements, fillers: s.fillersEnabled ? s.fillers : nil)
    }

    /// Self-check used by `--test-dictionary`.
    static func selfTest() -> Bool {
        let rep = [Replacement(from: "пайплайн", to: "pipeline"), Replacement(from: "гит хаб", to: "GitHub")]
        let fil = Settings.defaultFillers
        let cases: [(String, String)] = [
            (process("Настроил Пайплайн и пайплайны, на гит хабе", replacements: rep, fillers: nil), "Настроил pipeline и пайплайны, на гит хабе"),
            (process("Залил в Гит  Хаб", replacements: rep, fillers: nil), "Залил в GitHub"),
            (process("Ну, давай начнём", replacements: [], fillers: fil), "Давай начнём"),
            (process("Это, как бы, очень важно", replacements: [], fillers: fil), "Это, очень важно"),
            (process("Мы э сделали типа всё", replacements: [], fillers: fil), "Мы сделали всё"),
            (process("Он вышел. Короткий вопрос, ээ, есть", replacements: [], fillers: fil), "Он вышел. Короткий вопрос, есть"),
            (process("Намного лучше, нужно эхо", replacements: [], fillers: fil), "Намного лучше, нужно эхо"),
        ]
        var ok = true
        for (got, want) in cases { let p = got == want; ok = ok && p; print(p ? "PASS" : "FAIL", "'\(got)'", p ? "" : "expected '\(want)'") }
        return ok
    }
}
