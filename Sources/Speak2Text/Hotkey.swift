import Cocoa

/// Push-to-talk on a modifier key (flagsChanged). CGEventTap (listen only), fallback NSEvent global monitor.
final class Hotkey {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onCancel: ((String) -> Void)?
    private var cancelled = false
    private var keyCode: Int64 = 61
    private var mask: UInt64 = 0x40
    private var down = false
    private var tap: CFMachPort?
    private var monitor: Any?
    private(set) var mode = "none"

    static let table: [String: (Int64, UInt64)] = [
        "right_option": (61, 0x40), "left_option": (58, 0x20),
        "right_command": (54, 0x10), "left_command": (55, 0x08),
        "right_control": (62, 0x2000), "left_control": (59, 0x01),
        "right_shift": (60, 0x04), "left_shift": (56, 0x02),
        "fn": (63, 0x800000),
    ]

    init(name: String) {
        let e = Hotkey.table[name] ?? Hotkey.table["right_option"]!
        keyCode = e.0; mask = e.1
    }

    private func handle(code: Int64, flags: UInt64) {
        guard code == keyCode else { return }
        let pressed = (flags & mask) != 0
        if pressed && !down { appLog("hotkey down"); down = true; cancelled = false; DispatchQueue.main.async { self.onDown?() } }
        else if !pressed && down {
            appLog("hotkey up")
            down = false
            if cancelled { cancelled = false } else { DispatchQueue.main.async { self.onUp?() } }
        }
    }

    /// Another key / mouse click while the hotkey is held: the modifier is part of a combo.
    private func interrupted(_ reason: String) {
        guard down, !cancelled else { return }
        cancelled = true
        DispatchQueue.main.async { self.onCancel?(reason) }
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t); tap = nil }
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        down = false; cancelled = false; mode = "none"
    }

    func start() {
        stop()
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
            } else if type == .keyDown {
                me.interrupted("key \(event.getIntegerValueField(.keyboardEventKeycode)) pressed with hotkey")
            } else if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                me.interrupted("mouse click with hotkey")
            } else if type == .flagsChanged {
                me.handle(code: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags.rawValue)
            }
            return Unmanaged.passUnretained(event)
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                     eventsOfInterest: [CGEventType.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }, callback: cb, userInfo: me) {
            tap = t
            let src = CFMachPortCreateRunLoopSource(nil, t, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            mode = "CGEventTap"
        } else {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] ev in
                switch ev.type {
                case .flagsChanged: self?.handle(code: Int64(ev.keyCode), flags: UInt64(ev.modifierFlags.rawValue))
                case .keyDown: self?.interrupted("key \(ev.keyCode) pressed with hotkey")
                default: self?.interrupted("mouse click with hotkey")
                }
            }
            mode = "NSEvent global monitor"
        }
    }
}
