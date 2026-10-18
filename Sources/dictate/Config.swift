import Foundation

let appDir = NSString(string: "~/dictation-bench/dictate-app").expandingTildeInPath
let configPath = appDir + "/config.json"
let logPath = appDir + "/logs/dictate.log"

struct Config {
    var hotkey = "right_option"
    var modelFolder = "/Users/vlad/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB"
    var language = "ru"
    var step = 1.0

    static func load() -> Config {
        var c = Config()
        if let d = FileManager.default.contents(atPath: configPath),
           let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            if let v = j["hotkey"] as? String { c.hotkey = v }
            if let v = j["model_folder"] as? String { c.modelFolder = v }
            if let v = j["language"] as? String { c.language = v }
            if let v = j["live_step_s"] as? Double { c.step = v }
        } else {
            let j: [String: Any] = ["hotkey": c.hotkey, "model_folder": c.modelFolder, "language": c.language, "live_step_s": c.step,
                                    "_hotkey_values": "right_option, left_option, right_command, right_control, right_shift, fn"]
            if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? d.write(to: URL(fileURLWithPath: configPath))
            }
        }
        return c
    }
}

func appLog(_ line: String) {
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let s = "\(df.string(from: Date())) \(line)\n"
    try? FileManager.default.createDirectory(atPath: (logPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(Data(s.utf8)); try? h.close() }
    else { try? s.write(toFile: logPath, atomically: true, encoding: .utf8) }
}

func normalizeText(_ t: String) -> String {
    t.trimmingCharacters(in: .whitespacesAndNewlines)
}
