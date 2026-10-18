import Foundation
import Combine

enum Accelerator: String, CaseIterable, Codable {
    case ane, gpu, cpu
}

/// All user settings, stored in UserDefaults. Changes are published and applied immediately.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var hotkey: HotkeySpec { didSet { save(hotkey, "hotkey") } }
    @Published var mode: String { didSet { d.set(mode, forKey: "mode") } }
    /// "system" (follow macOS), "auto" (detect) or a Whisper language code. Resolved at recognition time with `recognitionLanguage`.
    @Published var language: String { didSet { d.set(language, forKey: "recognitionLanguage") } }
    @Published var muteEnabled: Bool { didSet { d.set(muteEnabled, forKey: "muteEnabled") } }
    @Published var overlayEnabled: Bool { didSet { d.set(overlayEnabled, forKey: "overlayEnabled") } }
    @Published var soundsEnabled: Bool { didSet { d.set(soundsEnabled, forKey: "soundsEnabled") } }
    /// Id of the start/stop sound variant (see `Sounds.variants`).
    @Published var soundVariant: String { didSet { d.set(soundVariant, forKey: "soundVariant") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }
    @Published var accelerator: Accelerator { didSet { d.set(accelerator.rawValue, forKey: "accelerator") } }
    @Published var fillersEnabled: Bool { didSet { d.set(fillersEnabled, forKey: "fillersEnabled") } }
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
        language = d.string(forKey: "recognitionLanguage") ?? "system"
        for k in ["language", "replacements", "fillers", "muteLevel", "model", "promptEnabled", "promptTerms"] { d.removeObject(forKey: k) }   // keys of older versions
        muteEnabled = bool("muteEnabled", true)
        overlayEnabled = bool("overlayEnabled", true)
        soundsEnabled = bool("soundsEnabled", true)
        soundVariant = d.string(forKey: "soundVariant").flatMap { v in Sounds.variants.contains { $0.id == v } ? v : nil } ?? Sounds.variants[0].id
        launchAtLogin = bool("launchAtLogin", true)
        accelerator = Accelerator(rawValue: d.string(forKey: "accelerator") ?? "") ?? .ane
        fillersEnabled = bool("fillersEnabled", true)   // on unless the user switched it off explicitly
        historyEnabled = bool("historyEnabled", true)
        historyDays = d.object(forKey: "historyDays") as? Int ?? 30
    }

    /// Language code passed to the engine: "auto" or a Whisper code. "system" is resolved here, every time.
    var recognitionLanguage: String { WhisperLanguages.resolve(language) }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: key) }
    }
}
