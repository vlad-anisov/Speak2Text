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
        var o = DecodingOptions(verbose: false, task: .transcribe, language: auto ? nil : language, temperature: 0.0, detectLanguage: auto ? true : nil,
                                skipSpecialTokens: true, withoutTimestamps: false, wordTimestamps: false, promptTokens: promptTokens)
        // On quiet or unclear speech WhisperKit re-decoded the whole window at up to 5 higher temperatures
        // (5-8 s per pass instead of ~1 s); one retry is enough to break a repetition loop.
        o.temperatureFallbackCount = 1
        o.firstTokenLogProbThreshold = nil
        return o
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
    /// Temperature fallbacks in the last pass (debug).
    private(set) var lastFallbacks = 0

    /// One recognition pass. `keepGoing` is polled while decoding; returning false stops the pass early
    /// (its result is then incomplete and must be discarded).
    func hypothesis(_ audio: [Float], keepGoing: (@Sendable () -> Bool)? = nil) async throws -> [Seg] {
        let cb: TranscriptionCallback? = keepGoing.map { k in { _ in k() } }
        let r = try await pipe.transcribe(audioArray: audio, decodeOptions: decodeOptions, callback: cb)
        lastFallbacks = r.reduce(0) { $0 + Int($1.timings.totalDecodingFallbacks) }
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

private let liveDebug = ProcessInfo.processInfo.environment["S2T_DEBUG"] != nil
private func dlog(_ s: @autoclosure () -> String) {
    if liveDebug { FileHandle.standardError.write(Data("[live] \(s())\n".utf8)) }
}

/// Live mode: every ~step s the audio buffer is re-recognised and words equal in two consecutive
/// hypotheses are committed (LocalAgreement-2). Once the buffer is longer than `trimAfter`, it is trimmed at
/// the end of the last fully committed Whisper segment (snapped to the quietest nearby frame); past `maxBuf`
/// it is cut even without agreement. So the buffer stays at ~6-12 s: passes stay ~1 s and the final pass on
/// release decodes just that tail, whatever the dictation length.
final class LiveTranscriber: @unchecked Sendable {
    let engine: WhisperEngine
    let buf = LockedBuffer()
    private var task: Task<String, Never>?
    private(set) var totalSamples = 0
    private var sumSquares: Double = 0
    var onPartial: ((String) -> Void)?

    /// Never cut so that less than this stays in the buffer: WhisperKit skips windows shorter than
    /// `windowClipTime` (1 s), and the final pass needs some audio to recognise the tail.
    static let minKeep = 1.5
    /// A cut point must be at least this far into the buffer (avoids churn on tiny cuts).
    static let minCut = 1.0
    /// Past this the buffer is cut even without agreement (see loop()).
    static let maxBuf = 12.0
    /// Keep at least this much audio before trimming: a longer window gives Whisper context, so fewer
    /// boundary errors, and passes are still ~1 s.
    static let trimAfter = 6.0

    /// The quietest 20 ms frame in [t-0.15, t+0.35] s: Whisper's segment end can be a bit early.
    static func quietPoint(_ x: [Float], near t: Double) -> Int {
        let frame = 320
        let lo = max(0, Int((t - 0.15) * 16000)), hi = min(x.count - frame, Int((t + 0.35) * 16000))
        guard hi > lo else { return Int(t * 16000) }
        var best = Int(t * 16000), bestE = Float.greatestFiniteMagnitude
        var i = lo
        while i <= hi {
            var e: Float = 0
            for j in i..<(i + frame) { e += x[j] * x[j] }
            if e < bestE { bestE = e; best = i + frame / 2 }
            i += frame / 2
        }
        return best
    }

    init(engine: WhisperEngine) { self.engine = engine }

    func start() {
        task = Task.detached { [self] in
            do { return try await loop() } catch { FileHandle.standardError.write(Data("live error: \(error)\n".utf8)); return "" }
        }
    }

    func feed(_ x: [Float]) {
        totalSamples += x.count
        var s: Float = 0
        for v in x { s += v * v }
        sumSquares += Double(s)
        buf.append(x)
    }

    func cancel() { task?.cancel(); buf.markFinished() }

    /// Marks the end of audio and waits for the final text.
    func finish() async -> String {
        buf.markFinished()
        let text = await task?.value ?? ""
        let dur = Double(totalSamples) / 16000
        let rms = totalSamples > 0 ? (sumSquares / Double(totalSamples)).squareRoot() : 0
        if Hallucination.isFiller(text) && (dur < Hallucination.shortClip || rms < Hallucination.quietRMS) {
            dlog(String(format: "dropped hallucination on %.2fs rms=%.4f: %@", dur, rms, text))
            return ""
        }
        return text
    }

    private func loop() async throws -> String {
        var committed: [String] = []
        /// Committed words that belong to the current buffer (after the last cut).
        var bufCommitted: [String] = []
        var prev: [String]? = nil
        /// Set after a cut until something is committed in the new buffer: Whisper may repeat the last
        /// committed words at the start of the trimmed buffer.
        var afterCut = false
        var lastShown = ""
        var cutTotal = 0.0
        let step = engine.step
        let stillRecording: @Sendable () -> Bool = { [buf] in !buf.finished }
        while true {
            if Task.isCancelled { return "" }
            let finished = buf.finished
            let snap = buf.snapshot()
            if !finished && snap.count < 16000 { try await Task.sleep(nanoseconds: 50_000_000); continue }
            if finished && snap.count < 1600 { return committed.joined(separator: " ") }
            let tStart = nowS()
            // a live pass is abandoned as soon as the key is released; the final pass then runs at once
            var segs = try await engine.hypothesis(snap, keepGoing: finished ? nil : stillRecording)
            if !finished && buf.finished {
                dlog(String(format: "pass aborted by release after %.2fs (buf %.1fs)", nowS() - tStart, Double(snap.count) / 16000))
                continue
            }
            if afterCut { Self.dropRepeatedHead(&segs, before: committed.dropLast(bufCommitted.count)) }
            let words = segs.flatMap { $0.words }
            if finished {
                // WhisperKit sometimes skips a whole window as "no speech"; then keep the last live hypothesis
                let tail = Self.tail(of: words.isEmpty ? (prev ?? []) : words, after: bufCommitted)
                var out = committed
                // a lone filler phrase after the committed text, on quiet audio, is a hallucination
                if !committed.isEmpty, Hallucination.isFiller(tail.joined(separator: " ")), Self.rms(snap) < Hallucination.quietRMS {
                    dlog("dropped trailing hallucination: \(tail.joined(separator: " "))")
                } else {
                    out += tail
                }
                dlog(String(format: "final pass %.2fs on buf %.1fs (offset %.1fs), tail %d words, fb %d", nowS() - tStart, Double(snap.count) / 16000, cutTotal, tail.count, engine.lastFallbacks))
                return out.joined(separator: " ")
            }
            let bufSec = Double(snap.count) / 16000
            if words.isEmpty {
                // an empty pass (window skipped as "no speech") carries no information: keep `prev`,
                // otherwise passes that alternate empty/non-empty never agree and nothing is committed
                dlog(String(format: "pass %.2fs buf %.1fs empty, fb %d", nowS() - tStart, bufSec, engine.lastFallbacks))
                while nowS() - tStart < step && !buf.finished { try await Task.sleep(nanoseconds: 30_000_000) }
                continue
            }
            var n = bufCommitted.count
            if let p = prev {
                var i = n
                while i < p.count && i < words.count && wordKey(p[i]) == wordKey(words[i]) { i += 1 }
                if i > n {
                    committed.append(contentsOf: words[n..<i])
                    bufCommitted.append(contentsOf: words[n..<i])
                    n = i
                    afterCut = false
                }
            }
            prev = words
            let shown = (committed + (n < words.count ? Array(words[n...]) : [])).joined(separator: " ")
            if shown != lastShown { lastShown = shown; onPartial?(shown) }
            // Trim at the end of the last segment whose words are all committed. If the buffer still grows past
            // maxBuf (hypotheses keep changing on unclear speech, so nothing agrees), commit everything but the
            // last segment of the current hypothesis: otherwise every pass, and the final one, re-decodes an
            // ever longer buffer (several 30 s windows) and falls further behind.
            var cum = 0, cutEnd: Double? = nil, cutWords = 0
            for (idx, sg) in segs.enumerated() {
                cum += sg.words.count
                let fits = sg.end >= Self.minCut && bufSec - sg.end >= Self.minKeep
                if cum <= n { if fits && bufSec > Self.trimAfter { cutEnd = sg.end; cutWords = cum }; continue }
                guard bufSec > Self.maxBuf, idx < segs.count - 1 else { break }
                if fits { cutEnd = sg.end; cutWords = cum }
            }
            var forced = ""
            if cutWords > n {
                committed.append(contentsOf: words[n..<cutWords])
                bufCommitted.append(contentsOf: words[n..<cutWords])
                forced = String(format: " forced %d words", cutWords - n)
                n = cutWords
            }
            var cutNote = ""
            if let e = cutEnd, e >= Self.minCut, bufSec - e >= Self.minKeep {
                let at = Self.quietPoint(snap, near: e)
                buf.dropFirst(min(at, snap.count))
                cutTotal += Double(at) / 16000
                bufCommitted.removeFirst(min(cutWords, bufCommitted.count))
                prev = Array(words.dropFirst(cutWords))
                afterCut = true
                cutNote = String(format: " cut %.2fs%@", e, forced)
            }
            dlog(String(format: "pass %.2fs buf %.1fs words %d committed %d segs %d fb %d%@", nowS() - tStart, bufSec, words.count, committed.count, segs.count, engine.lastFallbacks, cutNote))
            // sleep the rest of the step, but wake immediately when the audio ends
            while nowS() - tStart < step && !buf.finished { try await Task.sleep(nanoseconds: 30_000_000) }
        }
    }

    /// Words of the final hypothesis that follow the already committed ones. The final pass may split or
    /// merge words differently, so the committed end is located by its last few words near the expected index.
    static func tail(of words: [String], after done: [String]) -> [String] {
        let n = done.count
        guard n > 0 else { return words }
        let m = min(3, n)
        let key = done.suffix(m).map(wordKey)
        for d in [0, -1, 1, -2, 2, -3, 3] {
            let j = n + d
            guard j >= m, j <= words.count else { continue }
            if words[(j - m)..<j].map(wordKey) == key { return Array(words[j...]) }
        }
        return n < words.count ? Array(words[n...]) : []
    }

    /// After a cut Whisper sometimes re-recognises the last words before the cut point (`before`) at the
    /// start of the new buffer; drop such a repeated head (up to 4 words, at least 2 letters of overlap).
    static func dropRepeatedHead(_ segs: inout [WhisperEngine.Seg], before committed: ArraySlice<String>) {
        let words = segs.flatMap { $0.words }
        var k = min(4, committed.count, words.count)
        while k > 0 {
            let a = committed.suffix(k).map(wordKey), b = words.prefix(k).map(wordKey)
            if a == b && a.joined().count >= 2 { break }
            k -= 1
        }
        guard k > 0 else { return }
        dlog("dropped repeated head: \(words.prefix(k).joined(separator: " "))")
        var left = k
        while left > 0, !segs.isEmpty {
            let take = min(left, segs[0].words.count)
            segs[0].words.removeFirst(take)
            left -= take
            if segs[0].words.isEmpty { segs.removeFirst() }
        }
    }

    static func rms(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        var s: Float = 0
        for v in x { s += v * v }
        return (Double(s) / Double(x.count)).squareRoot()
    }
}

/// Whisper's well-known "subtitle credits" hallucinations on silence or very short clips.
enum Hallucination {
    /// Audio shorter than this is treated as "short".
    static let shortClip = 3.0
    /// Mean RMS below this is treated as "quiet" (speech into a MacBook mic is ~0.01-0.03, silence ~0.002).
    static let quietRMS = 0.003

    static let phrases = [
        "продолжение следует", "спасибо за просмотр", "подписывайтесь на канал",
        "thanks for watching", "thank you for watching", "please subscribe",
    ]
    /// Credits lines: the whole text starting with one of these is a hallucination.
    static let prefixes = [
        "субтитры сделал", "субтитры делал", "субтитры создавал", "субтитры подготовил", "субтитры подогнал",
        "редактор субтитров", "subtitles by", "amara org",
    ]

    /// True when the text consists only of filler phrases (repeated or combined) or a credits line.
    static func isFiller(_ text: String) -> Bool {
        var t = " " + text.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
            .split(separator: " ").joined(separator: " ") + " "
        if t.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        let bare = t.trimmingCharacters(in: .whitespaces)
        if prefixes.contains(where: { bare.hasPrefix($0) }) || bare.contains("dimatorzok") { return true }
        for p in phrases { t = t.replacingOccurrences(of: " \(p) ", with: " ") }
        for p in phrases { t = t.replacingOccurrences(of: " \(p) ", with: " ") }
        return t.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
