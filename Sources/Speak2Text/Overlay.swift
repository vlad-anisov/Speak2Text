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
    /// Bars like on the app icon: few and chunky. Hidden setting `overlayBars` (3...16), e.g. `-overlayBars 10`.
    static let bars: Int = {
        let n = UserDefaults.standard.integer(forKey: "overlayBars")
        return n == 0 ? 4 : min(max(n, 3), 16)
    }()
    static let barWidth: CGFloat = 6, barGap: CGFloat = 4
    static let size: NSSize = {
        let content = CGFloat(bars) * barWidth + CGFloat(bars - 1) * barGap
        return NSSize(width: max(84, content + 44), height: 44)
    }()
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
            let smooth = Double(wave.smooth)
            let quiet = wave.quietSince.map { date.timeIntervalSince($0) > 0.8 } ?? false
            drawBars(ctx, size, opacity: quiet ? 0.5 : 0.9) { i, shape in
                if quiet { return 0.14 * shape * (0.5 + 0.5 * sin(t * 2.4 - Double(i) * 0.7)) }
                let wob = 0.6 + 0.4 * abs(sin(t * 6.5 + Double(i) * 1.7) * cos(t * 3.1 + Double(i) * 0.8))
                return min(1, smooth * 1.6 * shape * wob)
            }
        case .processing:
            // a bump runs across the bars
            let n = Double(OverlayController.bars)
            let head = (t * 1.6).truncatingRemainder(dividingBy: 1.0) * (n + 2) - 1
            drawBars(ctx, size, opacity: 0.9) { i, shape in
                let d = Double(i) - head
                return 0.12 + 0.5 * shape * exp(-d * d / 0.8)
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

    /// Icon proportions: rest heights 0.54 / 1 / 0.69 like the three bars of m1, then repeated.
    private static let shapes: [Double] = [0.54, 1.0, 0.69, 0.85, 0.62, 0.93]

    /// `f(i, shape)` returns 0...1 of the free height; 0 is a round dot.
    private func drawBars(_ ctx: GraphicsContext, _ size: CGSize, opacity: Double, _ f: (Int, Double) -> Double) {
        let n = OverlayController.bars, w = OverlayController.barWidth, gap = OverlayController.barGap
        let total = CGFloat(n) * w + CGFloat(n - 1) * gap
        let x0 = (size.width - total) / 2, maxH = size.height - 14
        for i in 0..<n {
            let h = w + (maxH - w) * CGFloat(max(0, min(1, f(i, Self.shapes[i % Self.shapes.count]))))
            let r = CGRect(x: x0 + CGFloat(i) * (w + gap), y: (size.height - h) / 2, width: w, height: h)
            ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(Color.primary.opacity(opacity)))
        }
    }
}
