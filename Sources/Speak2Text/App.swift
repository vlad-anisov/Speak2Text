import Cocoa
import AVFoundation
import Combine
import SwiftUI
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var shared: AppDelegate?
    var settingsWindow: NSWindow?
    var permWindow: NSWindow?
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    let overlay = OverlayController()
    let muter = AudioMuter()
    var signalSources: [DispatchSourceSignal] = []
    enum State { case loading, idle, recording, finishing }
    var item: NSStatusItem!
    var state: State = .loading { didSet { updateIcon(); if oldValue != state { rebuildMenu() } } }
    let manager = EngineManager.shared
    let settings = Settings.shared
    var engine: WhisperEngine? { manager.engine }
    var hotkey: Hotkey!
    var recorder: Recorder?
    var session: LiveTranscriber?
    var recStart = 0.0
    var inputOK = false, axOK = false
    var permTimer: Timer?
    var iconPulse: Timer?
    var cancellables = Set<AnyCancellable>()

    func checkPerms(prompt: Bool) {
        let oldIn = inputOK, oldAX = axOK
        inputOK = CGPreflightListenEventAccess()
        if prompt && !inputOK { _ = CGRequestListenEventAccess(); inputOK = CGPreflightListenEventAccess() }
        axOK = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
        if prompt || oldIn != inputOK || oldAX != axOK {
            appLog("input monitoring: \(inputOK)")
            appLog("accessibility: \(axOK)")
        }
        if inputOK && (hotkey.mode == "none" || oldIn != inputOK || oldAX != axOK) {
            hotkey.start()
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
        let st: String
        switch manager.status {
        case .needsDownload: st = L("Model is not downloaded")
        case .failed: st = L("Model failed to load")
        case .preparing: st = L("Preparing model…")
        case .ready: st = state == .recording ? L("Recording…") : state == .finishing ? L("Recognizing…") : L("Ready")
        }
        let si = m.addItem(withTitle: L("Status: ") + st, action: nil, keyEquivalent: ""); si.isEnabled = false
        m.addItem(.separator())
        m.addItem(withTitle: L("Permissions…"), action: #selector(openPermissions), keyEquivalent: "").target = self
        m.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        let up = m.addItem(withTitle: L("Check for Updates…"), action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        up.target = updater
        m.addItem(withTitle: L("Open Log"), action: #selector(openLog), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: L("Quit"), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = m
    }
    @objc func openInput() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!) }
    @objc func openAX() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        if AudioMuter.restoreFromDisk() { appLog("restored output volume left over from an interrupted recording") }
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in self?.muter.restore(); exit(0) }
            src.resume()
            signalSources.append(src)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        appLog("start: hotkey=\(settings.hotkey.displayName) model=\(settings.model) accelerator=\(settings.accelerator.rawValue)")

        hotkey = Hotkey()
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.stopRecording(allowShort: false) }
        hotkey.onToggle = { [weak self] in
            guard let self else { return }
            if self.state == .recording { self.stopRecording(allowShort: true) } else { self.startRecording() }
        }
        hotkey.onInterrupt = { [weak self] r in self?.cancelRecording(r) }
        hotkey.onEscape = { [weak self] in self?.cancelRecording("Esc") }
        hotkey.configure(spec: settings.hotkey, toggleMode: settings.mode == "toggle")
        settings.$hotkey.combineLatest(settings.$mode).sink { [weak self] spec, mode in
            self?.hotkey.configure(spec: spec, toggleMode: mode == "toggle")
        }.store(in: &cancellables)
        Permissions.registerInputMonitoring()
        checkPerms(prompt: false)
        permTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkPerms(prompt: false) }
        appLog("microphone access: \(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)")
        LoginItem.apply(settings.launchAtLogin)
        settings.$launchAtLogin.dropFirst().receive(on: DispatchQueue.main).sink { LoginItem.apply($0) }.store(in: &cancellables)
        let pm = PermissionsModel(); pm.refresh()
        if !settings.onboarded || !pm.allOK { settings.onboarded = true; openPermissions() }
        manager.$status.receive(on: DispatchQueue.main).sink { [weak self] st in
            guard let self else { return }
            if st == .ready { if self.state == .loading { self.state = .idle } }
            else if self.state == .idle { self.state = .loading }
            self.rebuildMenu()
        }.store(in: &cancellables)
        settings.$model.combineLatest(settings.$accelerator).dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.manager.reload()
        }.store(in: &cancellables)
        manager.reload()
        if let i = CommandLine.arguments.firstIndex(of: "--screenshots"), i + 1 < CommandLine.arguments.count { runScreenshots(CommandLine.arguments[i + 1]) }
    }

    /// `--screenshots <dir>`: captures the settings tabs and the permissions window, then quits.
    func runScreenshots(_ dir: String) {
        let tabs = ["general", "model", "dictionary", "about"]
        var delay = 2.0
        openSettings()
        for t in tabs {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                SettingsNav.shared.tab = t
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.0) {
                if let w = self.settingsWindow { captureWindow(w, to: "\(dir)/settings-\(t).png") }
            }
            delay += 1.6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.openPermissions()
            self.settingsWindow?.orderOut(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.5) {
            if let w = self.permWindow { captureWindow(w, to: "\(dir)/permissions.png") }
            NSApp.terminate(nil)
        }
    }

    private func menuIcon(_ name: String) -> NSImage? {
        // MenuBarIcon.png + @2x from the bundle (template); SF Symbol as a fallback
        let img = Bundle.main.path(forResource: name, ofType: "png").flatMap { NSImage(contentsOfFile: $0) }
        if let img {
            if let rep2 = Bundle.main.path(forResource: name + "@2x", ofType: "png").flatMap({ NSImageRep(contentsOfFile: $0) }) { img.addRepresentation(rep2) }
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        return NSImage(systemSymbolName: "waveform", accessibilityDescription: "Speak2Text")
    }

    /// Normal icon; the Rec variant while recording; loading and recognizing pulse the normal icon.
    func updateIcon() {
        item.button?.image = menuIcon(state == .recording ? "MenuBarIconRec" : "MenuBarIcon")
        item.button?.title = ""
        iconPulse?.invalidate(); iconPulse = nil
        item.button?.alphaValue = 1
        if state == .loading || state == .finishing {
            iconPulse = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                let t = Date.timeIntervalSinceReferenceDate
                let k: Double = 0.5 + 0.5 * sin(t * 5)
                self?.item.button?.alphaValue = CGFloat(0.55 + 0.45 * k)
            }
        }
    }

    func startRecording() {
        guard state == .idle, let engine else { return }
        engine.language = settings.language
        engine.promptTokens = settings.promptEnabled ? engine.tokens(forPrompt: settings.promptTerms) : nil
        let s = engine.newSession()
        let r = Recorder()
        r.onSamples = { [weak s] x in s?.feed(x) }
        r.onLevel = { [weak self] v in self?.overlay.setLevel(v) }
        do { try r.start() } catch { appLog("record start failed: \(error)"); return }
        s.start()
        session = s; recorder = r; recStart = nowS()
        hotkey.recording = true
        if settings.overlayEnabled { overlay.show() }
        if settings.soundsEnabled { NSSound(named: "Tink")?.play() }
        if settings.muteEnabled { muter.mute(to: Float(settings.muteLevel) / 100) }
        state = .recording
    }

    func cancelRecording(_ reason: String) {
        guard state == .recording, let s = session, let r = recorder else { return }
        r.stop(); recorder = nil; session = nil
        hotkey.recording = false
        muter.restore()
        overlay.hide()
        s.cancel()
        appLog(String(format: "cancelled (%@) after %.2fs", reason, nowS() - recStart))
        state = .idle
    }

    func stopRecording(allowShort: Bool) {
        guard state == .recording, let s = session, let r = recorder else { return }
        let tRelease = nowS()
        if !allowShort && tRelease - recStart < 0.4 { cancelRecording("short hold < 0.4s"); return }
        r.stop(); recorder = nil; session = nil
        hotkey.recording = false
        muter.restore()
        if settings.soundsEnabled { NSSound(named: "Pop")?.play() }
        state = .finishing
        overlay.processing()
        Task {
            let dur = Double(s.totalSamples) / 16000.0
            let raw = await s.finish()
            await MainActor.run {
                let text = TextProcessor.current(normalizeText(raw))
                if text.isEmpty { appLog("empty result, nothing inserted"); self.overlay.hide() } else { Inserter.insert(text); self.overlay.done() }
                let wait = nowS() - tRelease
                appLog(String(format: "audio=%.2fs final_wait=%.2fs len=%d text=%@", dur, wait, text.count, text))
                self.state = self.manager.status == .ready ? .idle : .loading
            }
        }
    }

    @objc func openPermissions() {
        if permWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PermissionsView()))
            w.title = "Speak2Text"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            permWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        permWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Speak2Text"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: Paths.logFile) { appLog("log opened") }
        NSWorkspace.shared.open(URL(fileURLWithPath: Paths.logFile))
    }
    func applicationWillTerminate(_ n: Notification) { muter.restore() }
    @objc func quit() { NSApp.terminate(nil) }
}
