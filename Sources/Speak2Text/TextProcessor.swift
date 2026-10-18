import Foundation

/// Post-processing of the final text: built-in replacements (always on), then filler words (optional).
enum TextProcessor {
    private static let wordChar = "[\\p{L}\\p{N}_]"

    /// Always removed when they stand alone as a word.
    static let strongFillers = ["э", "ээ", "эээ", "э-э", "э-э-э", "эм", "эмм", "ээм", "um", "umm", "uh", "uhh"]
    /// Real words too, so they are removed only when followed by a comma ("Ну, давай", "Это, как бы, важно").
    static let weakFillers = ["ну", "ну вот", "типа", "как бы", "так сказать", "короче", "вот"]

    static func process(_ text: String, fillers: Bool) -> String {
        var t = BuiltinDictionary.apply(text)
        if fillers { t = removeFillers(t) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes filler words together with the commas around them; keeps the next word capitalised when the filler opened a sentence.
    static func removeFillers(_ text: String) -> String {
        func alt(_ l: [String]) -> String { l.sorted { $0.count > $1.count }.map { $0.replacingOccurrences(of: " ", with: "\\s+") }.joined(separator: "|") }
        let strong = alt(strongFillers), weak = alt(weakFillers)
        let word = "(?<!\(wordChar))(?:\(strong)|(?<!и\\s)(?:\(weak))(?=\\s*,))(?!\(wordChar))"
        guard let re = try? NSRegularExpression(pattern: "(,\\s*)?\(word)(\\s*,)?", options: [.caseInsensitive]) else { return text }
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

    static func current(_ text: String) -> String { process(text, fillers: Settings.shared.fillersEnabled) }

    /// Self-check used by `--test-dictionary`: (input, fillers on?, expected output).
    static func selfTest() -> Bool {
        let cases: [(String, Bool, String)] = [
            // replacements: must change
            ("Настроил пайплайн и залил в гитхаб", false, "Настроил pipeline и залил в GitHub"),
            ("Выложил на гитхабе", false, "Выложил на GitHub"),
            ("Сделай гит пуш в мастер", false, "Сделай git push в мастер"),
            ("Открой пулл реквест в Джире", false, "Открой pull request в Jira"),
            ("Создал мёрдж реквест", false, "Создал merge request"),
            ("Фронтенд и бэкенд готовы", false, "Frontend и backend готовы"),
            ("Деплой прошёл успешно", false, "Deploy прошёл успешно"),
            ("Подними докер и кубернетес", false, "Подними Docker и Kubernetes"),
            ("Пишу на питоне и тайпскрипт", false, "Пишу на Python и TypeScript"),
            ("Сделал новый эндпоинт для апи", false, "Сделал новый endpoint для API"),
            ("Работаю в сфере ай-ти", false, "Работаю в сфере IT"),
            ("Написал в слак и телеграм, потом зум", false, "Написал в Slack и Telegram, потом Zoom"),
            ("Открой гугл докс и эксель", false, "Открой Google Docs и Excel"),
            ("Заметки в ноушн", false, "Заметки в Notion"),
            ("Спроси у чатджипити и клод", false, "Спроси у ChatGPT и Claude"),
            ("Приложение для иос и макос", false, "Приложение для iOS и macOS"),
            ("Модуль в оду", false, "Модуль в Odoo"),
            ("Настроил сиай", false, "Настроил CI"),
            ("Запустил два пайплайна", false, "Запустил два pipeline"),
            ("Чинил пайплайны всю неделю", false, "Чинил pipelines всю неделю"),
            ("Открыл МР и выложил на стейдж, потом влил в девелоп", false, "Открыл MR и выложил на stage, потом влил в develop"),
            ("Спросил у клода, потом у джемини и дипсик", false, "Спросил у Claude, потом у Gemini и DeepSeek"),
            ("Антропик выпустил ллм", false, "Anthropic выпустил LLM"),
            ("Скинул пдф на макбук и айфон", false, "Скинул PDF на MacBook и iPhone"),
            ("Код ревью и деплой на стейджинг", false, "Code review и deploy на staging"),
            // replacements: must NOT change
            ("Мастер ветка и релиз без токенов", false, "Мастер ветка и релиз без токенов"),
            ("Девелопер и девелоперы пишут код", false, "Девелопер и девелоперы пишут код"),
            ("Это баг, а не фича, поправь код", false, "Это баг, а не фича, поправь код"),
            ("Сыграй на гитаре, гита здесь ни при чём", false, "Сыграй на гитаре, гита здесь ни при чём"),
            ("Докеры разгрузили порт", false, "Докеры разгрузили порт"),
            ("Пайплайнер ничего не знает про зумеры", false, "Пайплайнер ничего не знает про зумеры"),
            ("Выпил кофе в кафе и пошёл дальше", false, "Выпил кофе в кафе и пошёл дальше"),
            ("Мы работаем с зумом ежедневно", false, "Мы работаем с Zoom ежедневно"),
            // fillers
            ("Ну, давай начнём", true, "Давай начнём"),
            ("Это, как бы, очень важно", true, "Это, очень важно"),
            ("Мы э сделали, типа, всё", true, "Мы сделали, всё"),
            ("Он вышел. Короче, вопрос есть", true, "Он вышел. Вопрос есть"),
            ("I um think uh this works", true, "I think this works"),
            ("Ну вот, давай начнём", true, "Давай начнём"),
            ("Это, так сказать, важно", true, "Это, важно"),
            ("Мы э-э сделали и эмм проверили", true, "Мы сделали и проверили"),
            // fillers: must NOT change
            ("Слушай, это важно, вот смотри", true, "Слушай, это важно, вот смотри"),
            ("Значит, делаем так, то есть вот так", true, "Значит, делаем так, то есть вот так"),
            ("Ну вот это и есть ответ", true, "Ну вот это и есть ответ"),
            ("Определение типа данных", true, "Определение типа данных"),
            ("Ну и ну, как бы вы поступили?", true, "Ну и ну, как бы вы поступили?"),
            ("Вот это да, стал короче", true, "Вот это да, стал короче"),
            ("Намного лучше, нужно эхо", true, "Намного лучше, нужно эхо"),
            ("Ну, давай", false, "Ну, давай"),
        ]
        var ok = true
        for (inp, f, want) in cases {
            let got = process(inp, fillers: f)
            let p = got == want; ok = ok && p
            print(p ? "PASS" : "FAIL", "'\(inp)' ->", "'\(got)'", p ? "" : "expected '\(want)'")
        }
        if ProcessInfo.processInfo.environment["S2T_BENCH"] != nil { bench() }
        return ok
    }

    /// Timing of the whole post-processing (replacements + fillers): median of 101 runs, in ms.
    static func bench() {
        let base = "Слушай, ну я вчера, типа, настроил пайплайн в гитлабе и залил в гитхаб, потом сделал деплой на стейдж. Короче, мёрдж реквест открыт, э надо глянуть код ревью в джире, вот. Это обычный текст без терминов, который просто идёт дальше и дальше. "
        for n in [100, 1000, 5000] {
            var text = ""
            while text.count < n { text += base }
            text = String(text.prefix(n))
            for f in [true, false] {
                var times = [Double](), out = ""
                for _ in 0..<101 {
                    let t0 = DispatchTime.now().uptimeNanoseconds
                    out = process(text, fillers: f)
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
                }
                let s = times.sorted()
                print(String(format: "BENCH chars=%d fillers=%@ median=%.3f ms min=%.3f max=%.3f outlen=%d", n, f ? "on" : "off", s[50], s[0], s[100], out.count))
            }
        }
    }
}
