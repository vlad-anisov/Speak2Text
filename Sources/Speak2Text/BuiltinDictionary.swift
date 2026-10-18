import Foundation

/// Built-in, always-on replacements: how Whisper writes English IT/business terms in Cyrillic -> the proper Latin spelling.
///
/// Format of a line: `heard | written`. Whole words only, case-insensitive. A leading `!` means "exactly this form":
/// without it a Russian case ending after the word is absorbed ("в гитхабе" -> "в GitHub").
/// Conservative on purpose: words that are normal Russian (баг, фича, код, билд, ...) are not listed.
enum BuiltinDictionary {
    static let lines = """
    # git and code hosting
    гитхаб | GitHub
    гит хаб | GitHub
    гитлаб | GitLab
    гит лаб | GitLab
    битбакет | Bitbucket
    гит пуш | git push
    гит пулл | git pull
    гит коммит | git commit
    гит мёрж | git merge
    гит мерж | git merge
    гит ребейз | git rebase
    гит чекаут | git checkout
    гит клон | git clone
    гит стэш | git stash
    гит стеш | git stash
    !гит | git
    пулл реквест | pull request
    пул реквест | pull request
    пулреквест | pull request
    !пулл реквесты | pull requests
    !пул реквесты | pull requests
    !пулл реквестов | pull requests
    мёрдж реквест | merge request
    мерж реквест | merge request
    мёрж реквест | merge request
    мердж реквест | merge request
    !мёрдж реквесты | merge requests
    !мерж реквесты | merge requests
    код ревью | code review
    коде ревью | code review
    кодревью | code review
    # ci/cd and infrastructure
    пайплайн | pipeline
    !пайплайны | pipelines
    !пайплайнов | pipelines
    сиай | CI
    си ай | CI
    сисиди | CI/CD
    си ай си ди | CI/CD
    деплой | deploy
    !деплои | deploys
    !докер | Docker
    докер компоуз | Docker Compose
    докерфайл | Dockerfile
    кубернетес | Kubernetes
    кубернейтис | Kubernetes
    кубер | Kubernetes
    хельм | Helm
    джанкинс | Jenkins
    дженкинс | Jenkins
    терраформ | Terraform
    ансибл | Ansible
    нджинкс | Nginx
    энджинкс | Nginx
    нгинкс | Nginx
    линукс | Linux
    убунту | Ubuntu
    дебиан | Debian
    # dev terms
    фронтенд | frontend
    фронт энд | frontend
    бэкенд | backend
    бекенд | backend
    бэк энд | backend
    фуллстек | fullstack
    фулстек | fullstack
    эндпоинт | endpoint
    эндпойнт | endpoint
    !эндпоинты | endpoints
    вебхук | webhook
    !вебхуки | webhooks
    апи | API
    эй пи ай | API
    рест апи | REST API
    ямл | YAML
    скл | SQL
    эс кью эл | SQL
    постгрес | Postgres
    постгри | Postgres
    постгрес скл | PostgreSQL
    редис | Redis
    монго | MongoDB
    монгодб | MongoDB
    рэббит эм кью | RabbitMQ
    реакт | React
    вью джс | Vue.js
    ангуляр | Angular
    нод джс | Node.js
    нодджс | Node.js
    некст джс | Next.js
    питон | Python
    джаваскрипт | JavaScript
    джава скрипт | JavaScript
    тайпскрипт | TypeScript
    тайп скрипт | TypeScript
    котлин | Kotlin
    сишарп | C#
    си шарп | C#
    си плюс плюс | C++
    джава | Java
    пхп | PHP
    эйчтимл | HTML
    эйч ти эм эл | HTML
    хтмл | HTML
    цсс | CSS
    си эс эс | CSS
    ай-ти | IT
    айти | IT
    ай ти | IT
    ай-пи | IP
    ай пи | IP
    эйчтитипи | HTTP
    хттп | HTTP
    хттпс | HTTPS
    юрл | URL
    юарэль | URL
    ю ар эл | URL
    ссш | SSH
    ви пи эн | VPN
    впн | VPN
    # products and companies
    одоо | Odoo
    оду | Odoo
    джира | Jira
    джиру | Jira
    джиро | Jira
    джире | Jira
    джирой | Jira
    конфлюенс | Confluence
    слак | Slack
    телеграм | Telegram
    телеграмм | Telegram
    ватсап | WhatsApp
    вотсап | WhatsApp
    зум | Zoom
    тимс | Teams
    майкрософт тимс | Microsoft Teams
    гугл докс | Google Docs
    гугл докс | Google Docs
    гугл шитс | Google Sheets
    гугл мит | Google Meet
    гугл драйв | Google Drive
    гугл | Google
    эксель | Excel
    пауэрпоинт | PowerPoint
    пауэр поинт | PowerPoint
    ноушн | Notion
    нотион | Notion
    фигма | Figma
    трелло | Trello
    майкрософт | Microsoft
    чатджипити | ChatGPT
    чат джипити | ChatGPT
    чат гпт | ChatGPT
    чатгпт | ChatGPT
    джипити | GPT
    опенаи | OpenAI
    опен эй ай | OpenAI
    антропик | Anthropic
    клод | Claude
    клауд код | Claude Code
    копайлот | Copilot
    # platforms
    иос | iOS
    айос | iOS
    макос | macOS
    мак ос | macOS
    виндовс | Windows
    # business
    кпи | KPI
    кей пи ай | KPI
    ойкейар | OKR
    оукейар | OKR
    эсэмэм | SMM
    сео | SEO
    эс и о | SEO
    црм | CRM
    си ар эм | CRM
    эрпэ | ERP
    ерп | ERP
    эйчар | HR
    эйч ар | HR
    эмвипи | MVP
    эм ви пи | MVP
    эсэлэй | SLA
    эс эл эй | SLA
    бэклог | backlog
    !бэклоги | backlogs
    скрам | Scrum
    канбан | Kanban
    дедлайн | deadline
    !дедлайны | deadlines
    митап | meetup
    онбординг | onboarding
    стендап | standup
    стэндап | standup
    """

    private struct Entry { let re: NSRegularExpression; let to: String; let len: Int; let exact: Bool }

    private static let wordChar = "[\\p{L}\\p{N}_]"
    /// Russian case endings that may follow a borrowed word and are dropped ("гитхабе" -> "GitHub").
    private static let endings = "(?:ами|ов|ам|ах|ом|ей|ы|а|у|е|и)?"

    private static let entries: [Entry] = {
        var seen = Set<String>(), out: [Entry] = []
        for raw in lines.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.components(separatedBy: " | ")
            guard parts.count == 2 else { continue }
            var from = parts[0].trimmingCharacters(in: .whitespaces)
            let exact = from.hasPrefix("!")
            if exact { from.removeFirst() }
            guard seen.insert(from).inserted else { continue }
            let words = from.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[\\s\\-]+")
            let pattern = "(?<!\(wordChar))\(words)\(exact ? "" : endings)(?!\(wordChar))"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                out.append(Entry(re: re, to: parts[1].trimmingCharacters(in: .whitespaces), len: from.count, exact: exact))
            }
        }
        // longer phrases first, so "гит пуш" wins over "гит"
        return out.sorted { $0.len != $1.len ? $0.len > $1.len : ($0.exact && !$1.exact) }
    }()

    static func apply(_ text: String) -> String {
        var t = text
        for e in entries {
            for m in e.re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
                guard let r = Range(m.range, in: t) else { continue }
                var to = e.to
                // keep the capital letter at the start of a sentence ("Деплой прошёл" -> "Deploy прошёл")
                let before = t[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                if let f = to.first, f.isLowercase, before.isEmpty || ".!?…".contains(before.last!) { to = f.uppercased() + to.dropFirst() }
                t.replaceSubrange(r, with: to)
            }
        }
        return t
    }
}
