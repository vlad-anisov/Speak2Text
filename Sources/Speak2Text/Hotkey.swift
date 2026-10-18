import Cocoa

/// Global hotkey via a CGEventTap running on its own thread.
/// Supports a lone modifier (left/right aware), a regular key (F13, Caps Lock, ...) and key + modifiers.
/// Emits hold-style events (press/release) or toggle-style events depending on the mode.
final class Hotkey: @unchecked Sendable {
    /// Hold mode: key went down / up.
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Toggle mode (and Caps Lock): one activation.
    var onToggle: (() -> Void)?
    /// Hold mode, modifier hotkey: another key/click/modifier while it is held, so it is part of a normal shortcut.
    var onInterrupt: ((String) -> Void)?
    /// Esc pressed while recording (the event is swallowed).
    var onEscape: (() -> Void)?

    private let lock = NSLock()
    private var spec = HotkeySpec.default
    private var toggleMode = false
    private var _recording = false
    private var _suspended = false

    // state touched only by the tap thread
    private var down = false
    private var cancelled = false
    private var swallowedKeyUp = false

    private var tap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private(set) var mode = "none"

    func configure(spec: HotkeySpec, toggleMode: Bool) {
        lock.lock(); self.spec = spec; self.toggleMode = toggleMode; lock.unlock()
    }
    var recording: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _recording }
        set { lock.lock(); _recording = newValue; lock.unlock() }
    }
    /// True while the settings window records a new hotkey.
    var suspended: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _suspended }
        set { lock.lock(); _suspended = newValue; lock.unlock() }
    }
    private func config() -> (HotkeySpec, Bool) { lock.lock(); defer { lock.unlock() }; return (spec, toggleMode) }

    private func main(_ f: (() -> Void)?) { DispatchQueue.main.async { f?() } }

    /// Returns true if the event must be swallowed.
    private func handle(type: CGEventType, code: Int, flags: UInt64, autorepeat: Bool) -> Bool {
        if suspended { return false }
        let (spec, toggleMode) = config()
        let holdStyle = !toggleMode && !spec.isCapsLock

        switch type {
        case .keyDown:
            if code == 53 && recording {
                main(onEscape); return true
            }
            if spec.modifierOnly {
                if down && !cancelled && !autorepeat { cancelled = true; if holdStyle { let c = code; main { self.onInterrupt?("key \(c) pressed with hotkey") } } }
                else if down { cancelled = true }
                return false
            }
            guard code == spec.keyCode, !spec.isCapsLock, (flags & HotkeySpec.comboMask) == spec.mods else { return false }
            if !down {
                down = true; swallowedKeyUp = true
                appLog("hotkey down")
                if holdStyle { main(onPress) } else { main(onToggle) }
            }
            return true
        case .keyUp:
            guard !spec.modifierOnly, code == spec.keyCode, !spec.isCapsLock else { return false }
            let was = down
            down = false
            if was && holdStyle { appLog("hotkey up"); main(onRelease) }
            let sw = swallowedKeyUp; swallowedKeyUp = false
            return sw
        case .flagsChanged:
            if spec.isCapsLock {
                if code == HotkeySpec.capsLock { appLog("hotkey toggle"); main(onToggle) }
                return false
            }
            if spec.modifierOnly {
                if code == spec.keyCode, let dev = HotkeySpec.modifierKeys[code]?.device {
                    let pressed = (flags & dev) != 0
                    if pressed && !down {
                        down = true; cancelled = false
                        appLog("hotkey down")
                        if holdStyle { main(onPress) }
                    } else if !pressed && down {
                        down = false
                        appLog("hotkey up")
                        let wasCancelled = cancelled; cancelled = false
                        if !wasCancelled { if holdStyle { main(onRelease) } else { main(onToggle) } }
                    }
                } else if down, !cancelled, HotkeySpec.modifierKeys[code] != nil {
                    // a second modifier joined: Option+Shift etc.
                    cancelled = true
                    if holdStyle { main { self.onInterrupt?("modifier \(code) pressed with hotkey") } }
                }
            } else if down && (flags & spec.mods) != spec.mods {
                // required modifier released before the key
                down = false
                if holdStyle { appLog("hotkey up"); main(onRelease) }
            }
            return false
        default:
            // mouse click
            if spec.modifierOnly && down && !cancelled {
                cancelled = true
                if holdStyle { main { self.onInterrupt?("mouse click with hotkey") } }
            }
            return false
        }
    }

    func stop() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
            tap = nil
        }
        if let rl = runLoop { CFRunLoopStop(rl); runLoop = nil }
        thread = nil
        down = false; cancelled = false; mode = "none"
    }

    /// Creates the tap. Active (can swallow Esc / hotkey key) when possible, else listen-only.
    func start() {
        stop()
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let auto = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let swallow = me.handle(type: type, code: code, flags: event.flags.rawValue, autorepeat: auto)
            return swallow && me.mode == "CGEventTap (active)" ? nil : Unmanaged.passUnretained(event)
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        var options = CGEventTapOptions.defaultTap
        var t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: options, eventsOfInterest: mask, callback: cb, userInfo: me)
        var m = "CGEventTap (active)"
        if t == nil {
            options = .listenOnly
            t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: options, eventsOfInterest: mask, callback: cb, userInfo: me)
            m = "CGEventTap (listen only)"
        }
        guard let tapPort = t else { return }
        tap = tapPort; mode = m
        let ready = DispatchSemaphore(value: 0)
        let th = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            let src = CFMachPortCreateRunLoopSource(nil, tapPort, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tapPort, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        th.name = "speak2text.hotkey"
        thread = th
        th.start()
        ready.wait()
    }
}

/// Records a new hotkey from the next key press (used by the settings window).
final class HotkeyCapture: ObservableObject {
    @Published var capturing = false
    private var monitor: Any?
    private var held = Set<Int>()
    private var candidate: Int?
    private var usedInCombo = false
    private var done: ((HotkeySpec?) -> Void)?

    func start(done: @escaping (HotkeySpec?) -> Void) {
        stop()
        self.done = done
        held = []; candidate = nil; usedInCombo = false
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] ev in
            self?.handle(ev) == true ? nil : ev
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        capturing = false
    }

    private func finish(_ s: HotkeySpec?) {
        let cb = done; done = nil
        stop()
        cb?(s)
    }

    private func handle(_ ev: NSEvent) -> Bool {
        let code = Int(ev.keyCode)
        let flags = UInt64(ev.modifierFlags.rawValue)
        if ev.type == .keyDown {
            if ev.isARepeat { return true }
            if code == 53 && (flags & HotkeySpec.comboMask) == 0 { finish(nil); return true }
            usedInCombo = true
            finish(HotkeySpec(keyCode: code, mods: flags & HotkeySpec.comboMask, modifierOnly: false))
            return true
        }
        if code == HotkeySpec.capsLock {
            finish(HotkeySpec(keyCode: code, mods: 0, modifierOnly: false)); return true
        }
        guard let dev = HotkeySpec.modifierKeys[code]?.device else { return true }
        if flags & dev != 0 {
            held.insert(code)
            candidate = held.count == 1 ? code : nil
        } else {
            held.remove(code)
            if held.isEmpty, let c = candidate, !usedInCombo {
                finish(HotkeySpec(keyCode: c, mods: 0, modifierOnly: true))
            }
        }
        return true
    }
}
