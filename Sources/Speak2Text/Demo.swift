import Cocoa

/// Screenshot helper: capture one window with the system tool.
func captureWindow(_ w: NSWindow, to path: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    // Capture at 2x: move the window to a Retina screen if it sits on a 1x one.
    if (w.screen?.backingScaleFactor ?? 1) < 2, let retina = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }) {
        let v = retina.visibleFrame
        w.setFrameOrigin(NSPoint(x: v.midX - w.frame.width / 2, y: v.midY - w.frame.height / 2))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // -o: no window shadow, so the image has no extra frame around the window.
    p.arguments = ["-x", "-o", "-l", String(w.windowNumber), path]
    try? p.run(); p.waitUntilExit()
    print("screenshot: \(path) exit=\(p.terminationStatus)")
}

/// `--demo-overlay [dir]`: shows the overlay for ~5 s with a fake mic level and checks that focus is not stolen.
final class OverlayDemo: NSObject, NSApplicationDelegate {
    let dir: String?
    let oc = OverlayController()
    var front0: String?
    let t0 = nowS()
    var shots = Set<String>()
    init(dir: String?) { self.dir = dir }

    func applicationDidFinishLaunching(_ n: Notification) {
        front0 = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        print("frontmost before: \(front0 ?? "nil")")
        oc.show()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [self] _ in tick() }
    }

    func tick() {
        let t = nowS() - t0
        let speaking = t < 1.6 || (t > 2.7 && t < 3.8)
        if t < 3.8 {
            oc.setLevel(speaking ? Float(0.01 + 0.06 * abs(sin(t * 9) * cos(t * 3.7))) : 0.0003)
        }
        if t >= 3.8 && oc.model.state == .listening { oc.processing() }
        if t >= 4.4 && oc.model.state == .processing { oc.done() }
        func shot(_ name: String, at: Double) {
            if t >= at, !shots.contains(name), let d = dir { shots.insert(name); captureWindow(oc.panel, to: "\(d)/\(name).png") }
        }
        shot("overlay-listening", at: 1.2)
        shot("overlay-silence", at: 2.5)
        shot("overlay-processing", at: 4.1)
        shot("overlay-done", at: 4.75)
        if t >= 5.3 {
            let after = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            print("frontmost after: \(after ?? "nil")")
            print("panel isKey=\(oc.panel.isKeyWindow) isMain=\(oc.panel.isMainWindow) appActive=\(NSApp.isActive) ignoresMouse=\(oc.panel.ignoresMouseEvents) frame=\(oc.panel.frame)")
            print(after == front0 && !NSApp.isActive && !oc.panel.isKeyWindow ? "FOCUS OK: overlay did not take focus" : "FOCUS CHANGED")
            exit(0)
        }
    }
}
