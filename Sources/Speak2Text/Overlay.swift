import Cocoa
import SwiftUI

enum OverlayState { case listening, processing, done }

final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .listening
    @Published var visible = false
    /// Latest microphone RMS (0...1); the view smooths it at 60 fps.
    var level: Float = 0
    var stateSince = Date()
}

/// Non-activating capsule near the bottom of the screen with the pointer.
/// It never becomes key and ignores the mouse, so focus stays in the app the text goes to.
final class OverlayController {
    static let size = NSSize(width: 220, height: 44)
    let model = OverlayModel()
    private(set) var panel: NSPanel!
    private var hideWork: DispatchWorkItem?

    init() {
        let p = OverlayPanel(contentRect: NSRect(origin: .zero, size: OverlayController.size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: OverlayController.size))
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        let r = OverlayController.size.height / 2
        let mask = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        fx.maskImage = mask
        let host = NSHostingView(rootView: OverlayView(model: model))
        host.frame = fx.bounds
        host.autoresizingMask = [.width, .height]
        fx.addSubview(host)
        p.contentView = fx
        panel = p
    }

    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let s = OverlayController.size
        panel.setFrame(NSRect(x: screen.frame.midX - s.width / 2, y: screen.visibleFrame.minY + 24, width: s.width, height: s.height), display: true)
    }

    private func set(_ st: OverlayState) { model.state = st; model.stateSince = Date() }

    func show() {
        hideWork?.cancel()
        set(.listening)
        model.level = 0
        place()
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        DispatchQueue.main.async { self.model.visible = true }
    }

    func setLevel(_ v: Float) { model.level = v }
    func processing() { if model.visible { set(.processing) } }

    func done() {
        guard model.visible else { return }
        set(.done)
        scheduleHide(after: 0.6)
    }

    func hide() { scheduleHide(after: 0) }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.visible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if !self.model.visible { self.panel.orderOut(nil) } }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WaveState {
    var smooth: Float = 0
    var quietSince: Date?
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @State private var wave = WaveState()
    private let bars = 26

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                draw(ctx, size, tl.date)
            }
        }
        .frame(width: OverlayController.size.width, height: OverlayController.size.height)
        .scaleEffect(model.visible ? 1 : 0.8)
        .opacity(model.visible ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: model.visible)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ date: Date) {
        let t = date.timeIntervalSinceReferenceDate
        let fg = Color.primary
        switch model.state {
        case .listening:
            // RMS -> 0...1 on a dB scale, then attack/release smoothing
            let raw = model.level
            let db = 20 * log10(max(raw, 1e-5))
            let target = Float(min(max((db + 52) / 40, 0), 1))
            let k: Float = target > wave.smooth ? 0.45 : 0.12
            wave.smooth += (target - wave.smooth) * k
            if target > 0.12 { wave.quietSince = nil } else if wave.quietSince == nil { wave.quietSince = date }
            let smooth = wave.smooth
            let quiet = wave.quietSince.map { date.timeIntervalSince($0) > 0.8 } ?? false
            let gap: CGFloat = 3, w = (size.width - 44 - gap * CGFloat(bars - 1)) / CGFloat(bars)
            for i in 0..<bars {
                let x = 22 + CGFloat(i) * (w + gap)
                let pos = Double(i) / Double(bars - 1)
                let env = 0.35 + 0.65 * sin(pos * .pi)
                var h: CGFloat
                if quiet {
                    h = 3 + CGFloat(2.5 * (1 + sin(t * 2.2 - pos * 2.0)) * (0.5 + 0.5 * env))
                } else {
                    let wob = 0.55 + 0.45 * abs(sin(t * 7.0 + Double(i) * 0.9) * cos(t * 3.3 + Double(i) * 0.37))
                    h = 3 + CGFloat(Double(smooth) * 26 * env * wob)
                }
                let r = CGRect(x: x, y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(fg.opacity(quiet ? 0.45 : 0.85)))
            }
        case .processing:
            let n = 9
            let head = (t * 1.8).truncatingRemainder(dividingBy: 1.0) * Double(n + 4) - 2
            for i in 0..<n {
                let x = size.width / 2 + (CGFloat(i) - CGFloat(n - 1) / 2) * 16
                let d = abs(Double(i) - head)
                let a = 0.2 + 0.8 * exp(-d * d / 1.6)
                let r: CGFloat = 3 + CGFloat(a) * 1.5
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: size.height / 2 - r, width: r * 2, height: r * 2)), with: .color(fg.opacity(a)))
            }
        case .done:
            let p = min(1, date.timeIntervalSince(model.stateSince) / 0.25)
            var path = Path()
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            path.move(to: CGPoint(x: c.x - 9, y: c.y + 0))
            path.addLine(to: CGPoint(x: c.x - 3, y: c.y + 6))
            path.addLine(to: CGPoint(x: c.x + 9, y: c.y - 7))
            ctx.stroke(path.trimmedPath(from: 0, to: CGFloat(p)), with: .color(fg),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}
