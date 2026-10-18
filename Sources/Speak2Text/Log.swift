import Foundation

enum Paths {
    static let home = NSHomeDirectory()
    static let logDir = home + "/Library/Logs/Speak2Text"
    static let logFile = logDir + "/speak2text.log"
    static let supportDir = home + "/Library/Application Support/Speak2Text"
    static let downloadBase = supportDir + "/Models"
    static let muteStateFile = supportDir + "/mute-state.json"
}

private let logQueue = DispatchQueue(label: "speak2text.log")

func appLog(_ line: String) {
    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let s = "\(df.string(from: Date())) \(line)\n"
    logQueue.sync {
        try? FileManager.default.createDirectory(atPath: Paths.logDir, withIntermediateDirectories: true)
        if let h = FileHandle(forWritingAtPath: Paths.logFile) { h.seekToEndOfFile(); h.write(Data(s.utf8)); try? h.close() }
        else { try? s.write(toFile: Paths.logFile, atomically: true, encoding: .utf8) }
    }
}

func nowS() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func normalizeText(_ t: String) -> String {
    t.trimmingCharacters(in: .whitespacesAndNewlines)
}
