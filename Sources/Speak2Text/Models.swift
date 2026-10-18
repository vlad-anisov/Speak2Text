import Foundation

struct ModelInfo: Identifiable, Equatable {
    let id: String          // WhisperKit variant folder name
    let title: String
    let sizeMB: Int
}

enum ModelCatalog {
    static let defaultID = "openai_whisper-large-v3-v20240930_turbo_632MB"
    static let all: [ModelInfo] = [
        ModelInfo(id: defaultID, title: "Large v3 turbo", sizeMB: 632),
        ModelInfo(id: "openai_whisper-large-v3-v20240930_626MB", title: "Large v3", sizeMB: 626),
        ModelInfo(id: "openai_whisper-small_216MB", title: "Small", sizeMB: 216),
        ModelInfo(id: "openai_whisper-base", title: "Base", sizeMB: 140),
    ]

    /// Folders where a downloaded model may live, in search order.
    static var searchRoots: [String] {
        [Paths.home + "/Documents/huggingface/models/argmaxinc/whisperkit-coreml",
         Paths.downloadBase + "/models/argmaxinc/whisperkit-coreml"]
    }

    /// Local folder of a model, or nil if it is not downloaded yet.
    static func folder(for id: String) -> String? {
        for r in searchRoots {
            let p = r + "/" + id
            if FileManager.default.fileExists(atPath: p + "/AudioEncoder.mlmodelc") { return p }
        }
        return nil
    }
}

import WhisperKit
import AVFoundation

/// Owns the loaded WhisperKit engine: loads it for the current model + accelerator, downloads models.
final class EngineManager: ObservableObject {
    static let shared = EngineManager()
    enum Status: Equatable { case needsDownload, preparing, ready, failed(String) }

    @Published var status: Status = .needsDownload
    @Published var preparingSince: Date?
    @Published var lastLoadSeconds: Double?
    @Published var downloads: [String: Double] = [:]
    @Published var downloadErrors: [String: String] = [:]
    private(set) var engine: WhisperEngine?
    private var loading = false
    private var dirty = false

    /// (Re)loads the engine for the model and accelerator currently chosen in the settings.
    /// A running CoreML compilation is never interrupted: a change made meanwhile is applied after it.
    func reload() {
        if loading { dirty = true; return }
        let st = Settings.shared
        guard let folder = ModelCatalog.folder(for: st.model) else {
            engine = nil; status = .needsDownload; appLog("model not downloaded: \(st.model)"); return
        }
        loading = true; dirty = false
        status = .preparing; preparingSince = Date()
        let e = WhisperEngine(modelFolder: folder, accelerator: st.accelerator, language: st.language, step: st.step)
        appLog("loading model \(st.model) accelerator=\(st.accelerator.rawValue)")
        Task {
            let t = nowS()
            var failure: String?
            do { try await e.load() } catch { failure = "\(error)" }
            let dt = nowS() - t
            await MainActor.run {
                self.loading = false
                if let f = failure {
                    appLog("model load FAILED: \(f)")
                    self.status = .failed(f)
                } else {
                    appLog(String(format: "model loaded+warmed in %.1f s", dt))
                    self.engine = e; self.lastLoadSeconds = dt; self.status = .ready
                }
                self.preparingSince = nil
                if self.dirty { self.reload() }
            }
        }
    }

    func download(_ id: String, thenSelect: Bool = true) {
        guard downloads[id] == nil else { return }
        downloads[id] = 0; downloadErrors[id] = nil
        appLog("downloading model \(id)")
        Task {
            do {
                _ = try await WhisperKit.download(variant: id, downloadBase: URL(fileURLWithPath: Paths.downloadBase)) { p in
                    DispatchQueue.main.async { self.downloads[id] = p.fractionCompleted }
                }
                await MainActor.run {
                    self.downloads[id] = nil
                    appLog("downloaded model \(id)")
                    if thenSelect { Settings.shared.model = id }
                    self.objectWillChange.send()
                }
            } catch {
                await MainActor.run { self.downloads[id] = nil; self.downloadErrors[id] = "\(error)"; appLog("download failed: \(error)") }
            }
        }
    }
}

struct SpeedRow: Identifiable {
    var id: Accelerator
    var loadS: Double?
    var recogS: Double?
    var text = ""
    var error: String?
    var running = false
}

/// Loads the chosen model on each accelerator and times the recognition of one sample.
final class SpeedTest: ObservableObject {
    @Published var rows: [SpeedRow] = []
    @Published var running = false
    @Published var recordingLeft: Int?
    private let recorder = Recorder()

    var best: Accelerator? {
        rows.filter { $0.recogS != nil }.min { ($0.recogS ?? 0) < ($1.recogS ?? 0) }?.id
    }

    static func builtInSample() -> [Float]? {
        let candidates = [Bundle.main.path(forResource: "sample", ofType: "wav"), "Resources/sample.wav"].compactMap { $0 }
        for p in candidates { if let s = try? loadWav(p) { return s } }
        return nil
    }

    /// Records 5 s from the microphone.
    func recordSample(done: @escaping ([Float]?) -> Void) {
        let buf = LockedBuffer()
        recorder.onSamples = { buf.append($0) }
        do { try recorder.start() } catch { appLog("speed test: record failed \(error)"); done(nil); return }
        recordingLeft = 5
        var left = 5
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            left -= 1
            if left > 0 { self.recordingLeft = left; return }
            t.invalidate()
            self.recorder.stop()
            self.recordingLeft = nil
            done(buf.snapshot())
        }
    }

    func run(samples: [Float], modelFolder: String, language: String) {
        guard !running else { return }
        running = true
        rows = Accelerator.allCases.map { SpeedRow(id: $0) }
        Task.detached {
            for (i, a) in Accelerator.allCases.enumerated() {
                await MainActor.run { self.rows[i].running = true }
                var row = SpeedRow(id: a)
                do {
                    let t0 = nowS()
                    let cfg = WhisperKitConfig(modelFolder: modelFolder, computeOptions: WhisperEngine.computeOptions(a), verbose: false, logLevel: .error, prewarm: false, load: true, download: false)
                    let pipe = try await WhisperKit(cfg)
                    row.loadS = nowS() - t0
                    let auto = language == "auto"
                    let opts = DecodingOptions(verbose: false, task: .transcribe, language: auto ? nil : language, temperature: 0.0, detectLanguage: auto ? true : nil,
                                               skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: false)
                    _ = try await pipe.transcribe(audioArray: samples, decodeOptions: opts)   // warm-up, not counted
                    let t1 = nowS()
                    let r = try await pipe.transcribe(audioArray: samples, decodeOptions: opts)
                    row.recogS = nowS() - t1
                    row.text = normalizeText(r.map { $0.text }.joined(separator: " "))
                    appLog(String(format: "speed test %@: load=%.1fs recognize=%.2fs", a.rawValue, row.loadS ?? 0, row.recogS ?? 0))
                } catch { row.error = "\(error)"; appLog("speed test \(a.rawValue) failed: \(error)") }
                await MainActor.run { self.rows[i] = row }
            }
            await MainActor.run { self.running = false }
        }
    }
}
