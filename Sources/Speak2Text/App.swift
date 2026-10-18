import Cocoa
import AVFoundation
import Combine
import SwiftUI
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var shared: AppDelegate?
    var settingsWindow: NSWindow?
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    let overlay = OverlayController()
    let muter = AudioMuter()
    var signalSources: [DispatchSourceSignal] = []
    enum State { case loading, idle, recording, finishing }
    var item: NSStatusItem!
    var state: State = .loading { didSet { updateIcon() } }
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
    }

    /// Left click opens the settings; right click shows a tiny menu with Settings and Quit.
    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let m = NSMenu()
            m.addItem(withTitle: L("Settings…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
            m.addItem(.separator())
            m.addItem(withTitle: L("Quit"), action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = m
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            openSettings(tab: nil)
        }
    }

    /// Accessory apps have no menu bar, so text fields would lack Cmd+C/V/X/A without an Edit menu.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: L("Quit"), action: #selector(quit), keyEquivalent: "q").target = self
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

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
        installEditMenu()
        Sounds.prepare()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
        appLog("start: hotkey=\(settings.hotkey.displayName) model=\(ModelCatalog.modelID) mode=\(settings.mode) accelerator=\(settings.accelerator.rawValue)")

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
        if !settings.onboarded || !pm.allOK { settings.onboarded = true; openSettings(tab: "permissions") }
        manager.$status.receive(on: DispatchQueue.main).sink { [weak self] st in
            guard let self else { return }
            if st == .ready { if self.state == .loading { self.state = .idle } }
            else if self.state == .idle { self.state = .loading }
        }.store(in: &cancellables)
        settings.$accelerator.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.manager.reload()
        }.store(in: &cancellables)
        manager.reload()
        if let i = CommandLine.arguments.firstIndex(of: "--screenshots"), i + 1 < CommandLine.arguments.count { runScreenshots(CommandLine.arguments[i + 1]) }
    }

    /// `--screenshots <dir> [--lang en|ru]`: captures every settings tab (History with dummy items), then quits.
    func runScreenshots(_ dir: String) {
        let tabs = ["general", "model", "dictionary", "history", "permissions", "about"]
        var delay = 2.0
        openSettings(tab: "general")
        for t in tabs {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.openSettings(tab: t) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.2) {
                if let w = self.settingsWindow { captureWindow(w, to: "\(dir)/settings-\(t).png") }
            }
            delay += 2.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { NSApp.terminate(nil) }
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

    var audio: SampleBox?
    var muteWork: DispatchWorkItem?

    func startRecording() {
        guard state == .idle, let engine else { return }
        engine.language = settings.language
        let s = engine.newSession()
        let r = Recorder()
        let box = SampleBox()
        // The start blip is played by this process: the microphone is ignored while it sounds, so it never reaches the model or the history.
        let blip = settings.soundsEnabled ? Sounds.startDuration + 0.04 : 0
        let gate = nowS() + blip
        r.onSamples = { [weak s] x in
            if nowS() < gate { return }
            s?.feed(x); box.append(x)
        }
        r.onLevel = { [weak self] v in self?.overlay.setLevel(v) }
        do { try r.start() } catch { appLog("record start failed: \(error)"); return }
        s.start()
        session = s; recorder = r; audio = box; recStart = nowS()
        hotkey.recording = true
        if settings.overlayEnabled { overlay.show() }
        if settings.soundsEnabled { Sounds.playStart() }
        if settings.muteEnabled {
            // mute only after the blip, otherwise it would be silenced as well
            let w = DispatchWorkItem { [weak self] in self?.muter.mute() }
            muteWork = w
            if blip > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + blip, execute: w) } else { w.perform() }
        }
        state = .recording
    }

    func cancelRecording(_ reason: String) {
        guard state == .recording, let s = session, let r = recorder else { return }
        r.stop(); recorder = nil; session = nil; audio = nil
        hotkey.recording = false
        muteWork?.cancel(); muteWork = nil
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
        let box = audio; audio = nil
        hotkey.recording = false
        muteWork?.cancel(); muteWork = nil
        muter.restore()
        if settings.soundsEnabled { Sounds.playStop() }
        state = .finishing
        overlay.processing()
        Task {
            let dur = Double(s.totalSamples) / 16000.0
            let raw = normalizeText(await s.finish())
            let text = TextProcessor.current(raw)
            if let box { HistoryStore.shared.add(samples: box.snapshot(), raw: raw, text: text) }
            await MainActor.run {
                if text.isEmpty { appLog("empty result, nothing inserted"); self.overlay.hide() } else { Inserter.insert(text); self.overlay.done() }
                let wait = nowS() - tRelease
                appLog(String(format: "audio=%.2fs final_wait=%.2fs len=%d text=%@", dur, wait, text.count, text))
                self.state = self.manager.status == .ready ? .idle : .loading
            }
        }
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: Paths.logFile) { appLog("log opened") }
        NSWorkspace.shared.open(URL(fileURLWithPath: Paths.logFile))
    }
    func applicationWillTerminate(_ n: Notification) { muter.restore() }
    @objc func quit() { NSApp.terminate(nil) }
}
