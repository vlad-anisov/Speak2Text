import Foundation

/// The only supported model: Whisper large-v3 turbo (632 MB, WhisperKit variant folder name).
enum ModelCatalog {
    static let modelID = "openai_whisper-large-v3-v20240930_turbo_632MB"
    static let title = "Whisper large v3 turbo"
    static let sizeMB = 632

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
final class EngineManager: ObservableObject, @unchecked Sendable {
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
        guard let folder = ModelCatalog.folder(for: ModelCatalog.modelID) else {
            engine = nil; status = .needsDownload; appLog("model not downloaded: \(ModelCatalog.modelID)"); return
        }
        loading = true; dirty = false
        status = .preparing; preparingSince = Date()
        let e = WhisperEngine(modelFolder: folder, accelerator: st.accelerator, language: st.language, step: st.step)
        appLog("loading model \(ModelCatalog.modelID) accelerator=\(st.accelerator.rawValue)")
        Task {
            let t = nowS()
            let failure: String?
            do { try await e.load(); failure = nil } catch { failure = "\(error)" }
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

    func download(_ id: String = ModelCatalog.modelID) {
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
                    self.reload()
                    self.objectWillChange.send()
                }
            } catch {
                await MainActor.run { self.downloads[id] = nil; self.downloadErrors[id] = "\(error)"; appLog("download failed: \(error)") }
            }
        }
    }
}
