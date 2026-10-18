import Cocoa
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    enum State { case loading, idle, recording, finishing }
    var item: NSStatusItem!
    var state: State = .loading { didSet { updateIcon() } }
    let settings = Settings.shared
    var engine: WhisperEngine!
    var hotkey: Hotkey!
    var recorder: Recorder?
    var session: LiveTranscriber?
    var recStart = 0.0
    var inputOK = false, axOK = false
    var permTimer: Timer?
    var tapOK = false

    func checkPerms(prompt: Bool) {
        let oldIn = inputOK, oldAX = axOK
        inputOK = CGPreflightListenEventAccess()
        if prompt && !inputOK { _ = CGRequestListenEventAccess(); inputOK = CGPreflightListenEventAccess() }
        axOK = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
        if prompt || oldIn != inputOK || oldAX != axOK {
            appLog("input monitoring: \(inputOK)")
            appLog("accessibility: \(axOK)")
        }
        if inputOK && (hotkey.mode == "none" || oldIn != inputOK) {
            hotkey.start(); tapOK = hotkey.mode == "CGEventTap"
            appLog("hotkey mode: \(hotkey.mode)")
        }
        if oldIn != inputOK || oldAX != axOK || prompt { rebuildMenu() }
    }

    func rebuildMenu() {
        let m = NSMenu()
        if !inputOK || !axOK {
            var miss: [String] = []
            if !inputOK { miss.append(L("Input Monitoring")) }
            if !axOK { miss.append(L("Accessibility")) }
            m.addItem(withTitle: "⚠️ " + L("Missing permissions: ") + miss.joined(separator: ", "), action: nil, keyEquivalent: "")
            if !inputOK { let i = m.addItem(withTitle: L("Input Monitoring") + "…", action: #selector(openInput), keyEquivalent: ""); i.target = self }
            if !axOK { let i = m.addItem(withTitle: L("Accessibility") + "…", action: #selector(openAX), keyEquivalent: ""); i.target = self }
            m.addItem(.separator())
        }
        m.addItem(withTitle: L("Open Log"), action: #selector(openLog), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: L("Quit"), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = m
    }
    @objc func openInput() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!) }
    @objc func openAX() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        appLog("start: hotkey=\(settings.hotkey.displayName) model=\(settings.model) accelerator=\(settings.accelerator.rawValue)")

        guard let folder = ModelCatalog.folder(for: settings.model) else { appLog("model not downloaded: \(settings.model)"); return }
        engine = WhisperEngine(modelFolder: folder, accelerator: settings.accelerator, language: settings.language, step: settings.step)
        hotkey = Hotkey(name: "right_option")
        hotkey.onDown = { [weak self] in self?.pressed() }
        hotkey.onUp = { [weak self] in self?.released() }
        hotkey.onCancel = { [weak self] r in self?.cancelRecording(r) }
        checkPerms(prompt: true)
        permTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkPerms(prompt: false) }
        AVCaptureDevice.requestAccess(for: .audio) { ok in appLog("microphone access: \(ok)") }
        Task {
            let t = nowS()
            do { try await engine.load(); appLog(String(format: "model loaded+warmed in %.1f s", nowS() - t)) }
            catch { appLog("model load FAILED: \(error)"); return }
            await MainActor.run { self.state = .idle }
        }
    }

    func updateIcon() {
        let (sym, title): (String, String) = {
            switch state {
            case .loading: return ("hourglass", "…")
            case .idle: return ("mic", "")
            case .recording: return ("mic.fill", " REC")
            case .finishing: return ("ellipsis.circle", " …")
            }
        }()
        item.button?.image = NSImage(systemSymbolName: sym, accessibilityDescription: title)
        item.button?.title = title
        item.button?.contentTintColor = state == .recording ? .systemRed : nil
    }

    func pressed() {
        guard state == .idle else { return }
        let s = engine.newSession()
        let r = Recorder()
        r.onSamples = { [weak s] x in s?.feed(x) }
        do { try r.start() } catch { appLog("record start failed: \(error)"); return }
        s.start()
        session = s; recorder = r; recStart = nowS()
        state = .recording
    }

    func cancelRecording(_ reason: String) {
        guard state == .recording, let s = session, let r = recorder else { return }
        r.stop(); recorder = nil; session = nil
        s.cancel()
        appLog(String(format: "cancelled (%@) after %.2fs", reason, nowS() - recStart))
        state = .idle
    }

    func released() {
        guard state == .recording, let s = session, let r = recorder else { return }
        let tRelease = nowS()
        if tRelease - recStart < 0.4 { cancelRecording("short hold < 0.4s"); return }
        r.stop(); recorder = nil; session = nil
        state = .finishing
        Task {
            let dur = Double(s.totalSamples) / 16000.0
            let raw = await s.finish()
            let text = normalizeText(raw)
            await MainActor.run {
                if text.isEmpty { appLog("empty result, nothing inserted") } else { Inserter.insert(text) }
                let wait = nowS() - tRelease
                appLog(String(format: "audio=%.2fs final_wait=%.2fs len=%d text=%@", dur, wait, text.count, text))
                self.state = .idle
            }
        }
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: Paths.logFile) { appLog("log opened") }
        NSWorkspace.shared.open(URL(fileURLWithPath: Paths.logFile))
    }
    @objc func quit() { NSApp.terminate(nil) }
}
