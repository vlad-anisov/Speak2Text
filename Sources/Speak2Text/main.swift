import Cocoa
import AVFoundation

func loadWav(_ path: String) throws -> [Float] {
    let f = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let conv = AVAudioConverter(from: f.processingFormat, to: fmt)!
    let inBuf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try f.read(into: inBuf)
    let cap = AVAudioFrameCount(Double(f.length) * 16000 / f.processingFormat.sampleRate) + 1024
    let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap)!
    var given = false
    var err: NSError?
    conv.convert(to: out, error: &err) { _, st in
        if given { st.pointee = .endOfStream; return nil }
        given = true; st.pointee = .haveData; return inBuf
    }
    if let e = err { throw e }
    return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
}

func runFile(_ path: String) async {
    let st = Settings.shared
    guard let folder = ModelCatalog.folder(for: st.model) else { print("error: model \(st.model) not found"); exit(1) }
    let engine = WhisperEngine(modelFolder: folder, accelerator: st.accelerator, language: st.language, step: st.step)
    do {
        let t = nowS()
        try await engine.load()
        print(String(format: "model loaded+warmed in %.1f s", nowS() - t))
        let samples = try loadWav(path)
        let s = engine.newSession()
        s.start()
        let t0 = nowS()
        var pos = 0, last = t0
        while pos < samples.count {
            let end = min(pos + 1600, samples.count)
            let wait = t0 + Double(end) / 16000 - nowS()
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            s.feed(Array(samples[pos..<end])); last = nowS(); pos = end
        }
        let raw = await s.finish()
        let wait = nowS() - last
        let text = normalizeText(raw)
        print(String(format: "audio=%.2fs final_wait=%.2fs", Double(samples.count) / 16000, wait))
        print("text: \(text)")
    } catch { print("error: \(error)") }
    exit(0)
}

let args = CommandLine.arguments
if args.contains("--test-dictionary") { exit(TextProcessor.selfTest() ? 0 : 1) }
if args.contains("--test-mute") {
    // measured check: mute to 0, read back, restore, read back
    let before = AudioMuter.currentVolume()
    let mu = AudioMuter()
    print("volume before: \(before.map { String($0) } ?? "n/a")")
    mu.mute(to: 0)
    print("volume muted: \(AudioMuter.currentVolume().map { String($0) } ?? "n/a"), state file: \(AudioMuter.hasPendingRestore)")
    if args.contains("--crash") { print("simulating crash"); kill(getpid(), SIGKILL) }
    mu.restore()
    print("volume restored: \(AudioMuter.currentVolume().map { String($0) } ?? "n/a"), state file: \(AudioMuter.hasPendingRestore)")
    exit(0)
}
if args.contains("--test-mute-recover") {
    print("pending: \(AudioMuter.hasPendingRestore), volume now: \(AudioMuter.currentVolume().map { String($0) } ?? "n/a")")
    print("restored: \(AudioMuter.restoreFromDisk()), volume now: \(AudioMuter.currentVolume().map { String($0) } ?? "n/a")")
    exit(0)
}
if let i = args.firstIndex(of: "--demo-overlay") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let d = OverlayDemo(dir: i + 1 < args.count ? args[i + 1] : nil)
    app.delegate = d
    app.run()
} else if let i = args.firstIndex(of: "--file"), i + 1 < args.count {
    Task { await runFile(args[i + 1]) }
    dispatchMain()
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let d = AppDelegate()
    app.delegate = d
    app.run()
}
