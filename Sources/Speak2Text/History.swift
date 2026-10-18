import Foundation
import AVFoundation
import AppKit

/// One saved dictation: the texts live in `<id>.json`, the audio (16 kHz mono wav) in `<id>.wav` next to it.
struct HistoryItem: Codable, Identifiable, Equatable {
    var id: String
    var date: Date
    var duration: Double
    /// Final text (after the dictionary); empty if nothing was recognized.
    var text: String
    /// Recognized text before the dictionary was applied.
    var raw: String
    var hasAudio: Bool
}

/// Thread-safe sample collector for one dictation.
final class SampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [Float] = []
    func append(_ x: [Float]) { lock.lock(); data.append(contentsOf: x); lock.unlock() }
    func snapshot() -> [Float] { lock.lock(); defer { lock.unlock() }; return data }
}

/// Saves every dictation to ~/Library/Application Support/Speak2Text/History and lists it for the History tab.
final class HistoryStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = HistoryStore()
    static let dir = Paths.supportDir + "/History"

    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var playingID: String?
    @Published private(set) var busy: Set<String> = []
    private var player: AVAudioPlayer?
    /// Screenshot mode: dummy items, nothing is read from or written to the disk.
    private let demo: Bool

    private override init() {
        demo = CommandLine.arguments.contains("--screenshots")
        super.init()
        if demo { items = HistoryStore.demoItems(); return }
        items = HistoryStore.loadAll()
        prune()
    }

    static func audioURL(_ it: HistoryItem) -> URL { URL(fileURLWithPath: dir + "/\(it.id).wav") }
    private static func jsonURL(_ id: String) -> URL { URL(fileURLWithPath: dir + "/\(id).json") }

    private static func loadAll() -> [HistoryItem] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.filter { $0.hasSuffix(".json") }
            .compactMap { try? dec.decode(HistoryItem.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/" + $0))) }
            .sorted { $0.date > $1.date }
    }

    private func writeJSON(_ it: HistoryItem) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(it) { try? d.write(to: HistoryStore.jsonURL(it.id), options: .atomic) }
    }

    private static func writeWav(_ samples: [Float], to url: URL) -> Bool {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        guard !samples.isEmpty, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return false }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        do {
            let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try f.write(from: buf)
            return true
        } catch { appLog("history: wav write failed: \(error)"); return false }
    }

    private func onMain(_ f: @escaping () -> Void) {
        if Thread.isMainThread { f() } else { DispatchQueue.main.sync(execute: f) }
    }

    /// Saves one dictation (also empty results, with the audio). Synchronous; safe to call from any thread.
    @discardableResult
    func add(samples: [Float], raw: String, text: String) -> HistoryItem? {
        guard Settings.shared.historyEnabled, !demo else { return nil }
        try? FileManager.default.createDirectory(atPath: HistoryStore.dir, withIntermediateDirectories: true)
        var it = HistoryItem(id: UUID().uuidString, date: Date(), duration: Double(samples.count) / 16000, text: text, raw: raw, hasAudio: false)
        it.hasAudio = HistoryStore.writeWav(samples, to: HistoryStore.audioURL(it))
        writeJSON(it)
        onMain { self.items.insert(it, at: 0); self.prune() }
        appLog(String(format: "history: saved %@ (%.1f s)", it.id, it.duration))
        return it
    }

    /// Removes items older than the retention period (0 = forever).
    func prune() {
        let days = Settings.shared.historyDays
        guard days > 0, !demo else { return }
        let limit = Date().addingTimeInterval(-Double(days) * 86400)
        for it in items where it.date < limit { remove(it) }
    }

    func remove(_ it: HistoryItem) {
        if playingID == it.id { stopPlayback() }
        if !demo {
            try? FileManager.default.removeItem(at: HistoryStore.jsonURL(it.id))
            try? FileManager.default.removeItem(at: HistoryStore.audioURL(it))
        }
        items.removeAll { $0.id == it.id }
    }

    func clear() {
        stopPlayback()
        for it in items { remove(it) }
    }

    // MARK: actions

    func copy(_ it: HistoryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(it.text, forType: .string)
    }

    func togglePlayback(_ it: HistoryItem) {
        if playingID == it.id { stopPlayback(); return }
        stopPlayback()
        guard it.hasAudio, let p = try? AVAudioPlayer(contentsOf: HistoryStore.audioURL(it)) else { return }
        p.delegate = self
        p.volume = 0.9
        if p.play() { player = p; playingID = it.id }
    }

    func stopPlayback() { player?.stop(); player = nil; playingID = nil }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.player = nil; self.playingID = nil }
    }

    /// Runs the current engine on the saved audio and updates the item.
    func retranscribe(_ it: HistoryItem) {
        guard it.hasAudio, !busy.contains(it.id), let engine = EngineManager.shared.engine, !demo else { return }
        busy.insert(it.id)
        let url = HistoryStore.audioURL(it)
        let lang = Settings.shared.recognitionLanguage
        Task {
            let raw: String?
            if let samples = try? loadWav(url.path) {
                engine.language = lang
                let s = engine.newSession()
                s.start()
                s.feed(samples)
                raw = normalizeText(await s.finish())
            } else { raw = nil }
            await MainActor.run {
                self.busy.remove(it.id)
                guard let raw, let i = self.items.firstIndex(where: { $0.id == it.id }) else { appLog("history: re-transcribe failed for \(it.id)"); return }
                self.items[i].raw = raw
                self.items[i].text = TextProcessor.current(raw)
                self.writeJSON(self.items[i])
                appLog("history: re-transcribed \(it.id) len=\(self.items[i].text.count)")
            }
        }
    }

    // MARK: demo

    private static func demoItems() -> [HistoryItem] {
        let now = Date()
        func it(_ ago: Double, _ dur: Double, _ text: String, raw: String? = nil) -> HistoryItem {
            HistoryItem(id: UUID().uuidString, date: now.addingTimeInterval(-ago), duration: dur, text: text, raw: raw ?? text, hasAudio: true)
        }
        let ru = isRussian
        return [
            it(120, 6.4, ru ? "Давай созвонимся завтра в десять и обсудим план релиза." : "Let's catch up tomorrow at ten and go through the release plan."),
            it(1900, 14.2, ru ? "Добавил проверку на пустой ответ, поправил тесты и обновил описание в README." : "Added a check for an empty response, fixed the tests and updated the README description.",
               raw: ru ? "добавил проверку на пустой ответ поправил тесты и обновил описание в ридми" : "added a check for an empty response fixed the tests and updated the readme description"),
            it(7200, 2.1, ""),
            it(93000, 9.8, ru ? "Напомни купить молоко и забрать посылку после работы." : "Remind me to buy milk and pick up the parcel after work."),
        ]
    }
}
