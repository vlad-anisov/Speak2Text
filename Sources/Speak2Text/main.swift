import Cocoa
import AVFoundation

func runFile(_ path: String) async {
    let st = Settings.shared
    guard let folder = ModelCatalog.folder(for: ModelCatalog.modelID) else { print("error: model \(ModelCatalog.modelID) not found"); exit(1) }
    let engine = WhisperEngine(modelFolder: folder, accelerator: st.accelerator, language: st.recognitionLanguage, step: st.step)
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
        if let it = HistoryStore.shared.add(samples: samples, raw: text, text: TextProcessor.current(text)) { print("history item: \(it.id)") }
    } catch { print("error: \(error)") }
    exit(0)
}

let args = CommandLine.arguments
if args.contains("--test-language") { print("system languages:", systemLanguages(), "-> system =", WhisperLanguages.resolve("system"), "; count:", WhisperLanguages.all.count, "; first:", WhisperLanguages.all.prefix(4).map { $0.name }, "; en:", WhisperLanguages.resolve("en")); exit(0) }
if args.contains("--test-dictionary") { exit(TextProcessor.selfTest() ? 0 : 1) }
if args.contains("--test-mute") {
    // measured check: mute to 0, read back, restore, read back
    let before = AudioMuter.currentVolume()
    let mu = AudioMuter()
    print("volume before: \(before.map { String($0) } ?? "n/a")")
    mu.mute()
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
    if args.contains("--light") { app.appearance = NSAppearance(named: .aqua) }
    app.setActivationPolicy(.accessory)
    let d = OverlayDemo(dir: i + 1 < args.count ? args[i + 1] : nil)
    app.delegate = d
    app.run()
} else if let i = args.firstIndex(of: "--file"), i + 1 < args.count {
    Task { await runFile(args[i + 1]) }
    dispatchMain()
} else {
    let app = NSApplication.shared
    if args.contains("--light") { app.appearance = NSAppearance(named: .aqua) }   // screenshots only
    app.setActivationPolicy(.accessory)
    let d = AppDelegate()
    app.delegate = d
    app.run()
}
