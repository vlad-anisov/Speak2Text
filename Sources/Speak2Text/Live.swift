import Foundation
import CoreML
import WhisperKit

func splitWords(_ s: String) -> [String] { s.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
func wordKey(_ w: String) -> String {
    String(w.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
}

final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [Float] = []
    private var fin = false
    func append(_ x: [Float]) { lock.lock(); data.append(contentsOf: x); lock.unlock() }
    func snapshot() -> [Float] { lock.lock(); defer { lock.unlock() }; return data }
    func dropFirst(_ n: Int) { lock.lock(); data.removeFirst(min(n, data.count)); lock.unlock() }
    func markFinished() { lock.lock(); fin = true; lock.unlock() }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return fin }
}

/// Holds the loaded WhisperKit pipeline; creates one LiveTranscriber per dictation.
final class WhisperEngine: @unchecked Sendable {
    var pipe: WhisperKit!
    let modelFolder: String
    let accelerator: Accelerator
    let step: Double
    /// "ru", "en" or "auto"; may change between dictations without reloading.
    var language: String
    /// Prompt token ids for the decoder (dictionary hints); set per session.
    var promptTokens: [Int]?
    init(modelFolder: String, accelerator: Accelerator, language: String, step: Double) {
        self.modelFolder = modelFolder; self.accelerator = accelerator; self.language = language; self.step = step
    }

    static func computeOptions(_ a: Accelerator) -> ModelComputeOptions {
        switch a {
        case .ane: return ModelComputeOptions(melCompute: .all, audioEncoderCompute: .all, textDecoderCompute: .all)
        case .gpu: return ModelComputeOptions(melCompute: .cpuAndGPU, audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
        case .cpu: return ModelComputeOptions(melCompute: .cpuOnly, audioEncoderCompute: .cpuOnly, textDecoderCompute: .cpuOnly)
        }
    }

    func load() async throws {
        let cfg = WhisperKitConfig(modelFolder: modelFolder, computeOptions: WhisperEngine.computeOptions(accelerator), verbose: false, logLevel: .error, prewarm: false, load: true, download: false)
        pipe = try await WhisperKit(cfg)
        // warm up: two runs of 3 s of silence-ish noise (compiles/loads ANE graphs)
        let warm = [Float](repeating: 0, count: 48000)
        for _ in 0..<2 { _ = try await pipe.transcribe(audioArray: warm, decodeOptions: decodeOptions) }
    }

    var decodeOptions: DecodingOptions {
        let auto = language == "auto"
        return DecodingOptions(verbose: false, task: .transcribe, language: auto ? nil : language, temperature: 0.0, detectLanguage: auto ? true : nil,
                               skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: false, promptTokens: promptTokens)
    }

    /// Token ids for a list of hint terms (special tokens dropped).
    func tokens(forPrompt terms: [String]) -> [Int]? {
        guard let tok = pipe?.tokenizer, !terms.isEmpty else { return nil }
        let begin = tok.specialTokens.specialTokenBegin
        let ids = tok.encode(text: " " + terms.joined(separator: ", ")).filter { $0 < begin }
        return ids.isEmpty ? nil : ids
    }

    func newSession() -> LiveTranscriber { LiveTranscriber(engine: self) }

    struct Seg { var words: [String]; var end: Double }

    func hypothesis(_ audio: [Float]) async throws -> [Seg] {
        let r = try await pipe.transcribe(audioArray: audio, decodeOptions: decodeOptions)
        var segs: [Seg] = []
        for res in r {
            for s in res.segments {
                let w = splitWords(s.text.replacingOccurrences(of: "<|", with: " <|")).filter { !$0.hasPrefix("<|") }
                if !w.isEmpty { segs.append(Seg(words: w, end: Double(s.end))) }
            }
        }
        return segs
    }
}

/// Live mode (from asr-bench Whisper.swift live()): every ~step s the whole buffer is re-recognised,
/// words equal in two consecutive hypotheses are committed (LocalAgreement-2).
final class LiveTranscriber: @unchecked Sendable {
    let engine: WhisperEngine
    let buf = LockedBuffer()
    private var task: Task<String, Never>?
    private(set) var totalSamples = 0
    var onPartial: ((String) -> Void)?

    init(engine: WhisperEngine) { self.engine = engine }

    func start() {
        task = Task.detached { [self] in
            do { return try await loop() } catch { FileHandle.standardError.write(Data("live error: \(error)\n".utf8)); return "" }
        }
    }

    func feed(_ x: [Float]) { totalSamples += x.count; buf.append(x) }

    func cancel() { task?.cancel(); buf.markFinished() }

    /// Marks the end of audio and waits for the final text.
    func finish() async -> String {
        buf.markFinished()
        return await task?.value ?? ""
    }

    private func loop() async throws -> String {
        var committed: [String] = []
        var committedInBuf = 0
        var prev: [String]? = nil
        var lastShown = ""
        let step = engine.step
        while true {
            if Task.isCancelled { return "" }
            let finished = buf.finished
            let snap = buf.snapshot()
            if !finished && snap.count < 16000 { try await Task.sleep(nanoseconds: 50_000_000); continue }
            if finished && snap.count < 1600 { return committed.joined(separator: " ") }
            let tStart = nowS()
            let segs = try await engine.hypothesis(snap)
            let words = segs.flatMap { $0.words }
            if finished {
                let tail = committedInBuf < words.count ? Array(words[committedInBuf...]) : []
                return (committed + tail).joined(separator: " ")
            }
            if let p = prev {
                var i = committedInBuf
                while i < p.count && i < words.count && wordKey(p[i]) == wordKey(words[i]) { i += 1 }
                if i > committedInBuf {
                    committed.append(contentsOf: words[committedInBuf..<i])
                    committedInBuf = i
                }
            }
            prev = words
            let tail = committedInBuf < words.count ? Array(words[committedInBuf...]) : []
            let shown = (committed + tail).joined(separator: " ")
            if shown != lastShown { lastShown = shown; onPartial?(shown) }
            if Double(snap.count) / 16000.0 > 20.0 {
                var cum = 0
                var cutEnd: Double? = nil
                var cutWords = 0
                for s in segs {
                    cum += s.words.count
                    if cum <= committedInBuf { cutEnd = s.end; cutWords = cum } else { break }
                }
                if let e = cutEnd, e > 1.0 {
                    let cutSamples = min(Int(e * 16000), snap.count)
                    buf.dropFirst(cutSamples)
                    committedInBuf -= cutWords
                    prev = nil
                }
            }
            // sleep the rest of the step, but wake immediately when the audio ends
            while nowS() - tStart < step && !buf.finished { try await Task.sleep(nanoseconds: 30_000_000) }
        }
    }
}
