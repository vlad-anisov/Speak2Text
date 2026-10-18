import Foundation
import Combine

struct Replacement: Codable, Identifiable, Equatable {
    var id = UUID()
    var from: String
    var to: String
}

enum Accelerator: String, CaseIterable, Codable {
    case ane, gpu, cpu
}

/// All user settings, stored in UserDefaults. Changes are published and applied immediately.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    static let defaultFillers = ["э", "ээ", "эм", "ну", "типа", "как бы", "короче"]

    @Published var hotkey: HotkeySpec { didSet { save(hotkey, "hotkey") } }
    @Published var mode: String { didSet { d.set(mode, forKey: "mode") } }
    @Published var language: String { didSet { d.set(language, forKey: "language") } }
    @Published var muteEnabled: Bool { didSet { d.set(muteEnabled, forKey: "muteEnabled") } }
    @Published var overlayEnabled: Bool { didSet { d.set(overlayEnabled, forKey: "overlayEnabled") } }
    @Published var soundsEnabled: Bool { didSet { d.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published var accelerator: Accelerator { didSet { d.set(accelerator.rawValue, forKey: "accelerator") } }
    @Published var replacements: [Replacement] { didSet { save(replacements, "replacements") } }
    @Published var fillersEnabled: Bool { didSet { d.set(fillersEnabled, forKey: "fillersEnabled") } }
    @Published var fillers: [String] { didSet { d.set(fillers, forKey: "fillers") } }
    @Published var historyEnabled: Bool { didSet { d.set(historyEnabled, forKey: "historyEnabled") } }
    /// 0 = keep forever.
    @Published var historyDays: Int { didSet { d.set(historyDays, forKey: "historyDays") } }
    var onboarded: Bool {
        get { d.bool(forKey: "onboarded") }
        set { d.set(newValue, forKey: "onboarded") }
    }
    /// Live re-recognition period, seconds (prototype value).
    let step = 1.0

    private init() {
        func bool(_ k: String, _ def: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? def }
        let d = UserDefaults.standard
        hotkey = (d.data(forKey: "hotkey").flatMap { try? JSONDecoder().decode(HotkeySpec.self, from: $0) }) ?? .default
        mode = d.string(forKey: "mode") ?? "toggle"
        language = d.string(forKey: "language") ?? "ru"
        muteEnabled = bool("muteEnabled", true)
        overlayEnabled = bool("overlayEnabled", true)
        soundsEnabled = bool("soundsEnabled", true)
        launchAtLogin = bool("launchAtLogin", true)
        accelerator = Accelerator(rawValue: d.string(forKey: "accelerator") ?? "") ?? .ane
        replacements = (d.data(forKey: "replacements").flatMap { try? JSONDecoder().decode([Replacement].self, from: $0) }) ?? []
        fillersEnabled = bool("fillersEnabled", false)
        fillers = d.stringArray(forKey: "fillers") ?? Settings.defaultFillers
        if CommandLine.arguments.contains("--screenshots") {   // dummy dictionary for the screenshots; init does not persist it
            replacements = [Replacement(from: isRussian ? "гит хаб" : "git hub", to: "GitHub"), Replacement(from: isRussian ? "пайплайн" : "pipe line", to: "pipeline")]
            fillersEnabled = true
        }
        historyEnabled = bool("historyEnabled", true)
        historyDays = d.object(forKey: "historyDays") as? Int ?? 30
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: key) }
    }
}
