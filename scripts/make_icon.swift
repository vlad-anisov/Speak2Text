// Генератор иконок Speak2Text.
// Запуск: swift scripts/make_icon.swift <A|B|C|menubar|preview> <outdir>
//   A|B|C    -> <outdir>/icon-<V>.png (1024x1024)
//   menubar  -> <outdir>/MenuBarIcon.png (18x18) и MenuBarIcon@2x.png (36x36), template: чёрный + альфа
//   preview  -> <outdir>/preview.png (читает <outdir>/icon-A|B|C.png)
import AppKit
import CoreGraphics
import Foundation

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [
        CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a,
    ])!
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.setAllowsAntialiasing(true)
    return c
}

func writePNG(_ img: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    if !CGImageDestinationFinalize(d) { fatalError("не удалось записать \(path)") }
}

func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
}

/// Суперэллипс (n=5) — близко к «континуальному» скруглению Apple.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

func bar(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h),
           cornerWidth: w / 2, cornerHeight: min(w, h) / 2, transform: nil)
}

func lineBar(_ x: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: cy - h / 2, width: w, height: h),
           cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)
}

let S: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

/// Подложка: тень, градиент, подсветка. Возвращает контекст с клипом не оставляет.
func drawBase(_ c: CGContext, top: UInt32, bottom: UInt32, glow: UInt32? = nil) {
    let path = squircle(body)
    // тень
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 32, color: col(0x000000, 0.38))
    c.addPath(path); c.setFillColor(col(bottom)); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(path); c.clip()
    c.drawLinearGradient(gradient([col(top), col(bottom)]),
                         start: CGPoint(x: 300, y: body.maxY), end: CGPoint(x: 724, y: body.minY),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    if let g = glow {
        c.drawRadialGradient(gradient([col(g, 0.55), col(g, 0)]),
                             startCenter: CGPoint(x: 330, y: 820), startRadius: 0,
                             endCenter: CGPoint(x: 330, y: 820), endRadius: 520, options: [])
    }
    // мягкий блик сверху
    c.drawLinearGradient(gradient([col(0xFFFFFF, 0.20), col(0xFFFFFF, 0)]),
                         start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: 560), options: [.drawsAfterEndLocation])
    // лёгкое затемнение снизу
    c.drawLinearGradient(gradient([col(0x000000, 0), col(0x000000, 0.14)]),
                         start: CGPoint(x: 0, y: 420), end: CGPoint(x: 0, y: body.minY), options: [.drawsAfterEndLocation])
    // внутренняя подсветка по краю
    c.addPath(path)
    c.setLineWidth(5)
    c.replacePathWithStrokedPath()
    c.clip()
    c.drawLinearGradient(gradient([col(0xFFFFFF, 0.60), col(0xFFFFFF, 0.05), col(0xFFFFFF, 0.0), col(0xFFFFFF, 0.12)],
                                  [0, 0.35, 0.7, 1]),
                         start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    c.restoreGState()
}

/// Заливка группы фигур с общей мягкой тенью.
func fillShapes(_ c: CGContext, _ paths: [CGPath], color: CGColor, shadow: CGFloat = 0.28) {
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: col(0x000000, shadow))
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    c.setFillColor(color)
    for p in paths { c.addPath(p); c.fillPath() }
    c.endTransparencyLayer()
    c.restoreGState()
}

func iconA() -> CGImage {
    let c = makeContext(1024, 1024)
    drawBase(c, top: 0x7B7CFF, bottom: 0x5B1FC4, glow: 0xB9A6FF)
    let cy: CGFloat = 512
    // волна
    let hs: [CGFloat] = [150, 270, 390, 250, 130]
    var bars: [CGPath] = []
    for (i, h) in hs.enumerated() { bars.append(bar(214 + CGFloat(i) * 70, cy, 44, h)) }
    fillShapes(c, bars, color: col(0xFFFFFF))
    // строки текста
    let x0: CGFloat = 556
    let lines: [(CGFloat, CGFloat, CGFloat)] = [(cy + 82, 280, 0.95), (cy, 220, 0.8), (cy - 82, 130, 0.65)]
    for (y, w, a) in lines { fillShapes(c, [lineBar(x0, y, w, 40)], color: col(0xFFFFFF, a), shadow: 0.2) }
    // курсор
    fillShapes(c, [bar(x0 + 130 + 30, cy - 82, 16, 84)], color: col(0xFFD25E))
    return c.makeImage()!
}

func iconB() -> CGImage {
    let c = makeContext(1024, 1024)
    drawBase(c, top: 0x3A3F4B, bottom: 0x0E1B3D, glow: 0x4B6AA8)
    let teal: UInt32 = 0x2DE0CF
    // keycap
    let baseR = CGRect(x: 196, y: 252, width: 632, height: 520)
    let faceR = CGRect(x: 226, y: 296, width: 572, height: 472)
    let basePath = CGPath(roundedRect: baseR, cornerWidth: 118, cornerHeight: 118, transform: nil)
    let facePath = CGPath(roundedRect: faceR, cornerWidth: 100, cornerHeight: 100, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -16), blur: 28, color: col(0x000000, 0.5))
    c.addPath(basePath); c.setFillColor(col(0x151C2E)); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(basePath); c.clip()
    c.drawLinearGradient(gradient([col(0x2B3550), col(0x0F1526)]),
                         start: CGPoint(x: 0, y: baseR.maxY), end: CGPoint(x: 0, y: baseR.minY), options: [])
    c.restoreGState()
    // грань
    c.saveGState()
    c.addPath(facePath); c.clip()
    c.drawLinearGradient(gradient([col(0xEEF3FA), col(0xB9C6DC)]),
                         start: CGPoint(x: 0, y: faceR.maxY), end: CGPoint(x: 0, y: faceR.minY), options: [])
    c.restoreGState()
    // подсветка грани
    c.saveGState()
    c.addPath(facePath); c.setLineWidth(5); c.replacePathWithStrokedPath(); c.clip()
    c.drawLinearGradient(gradient([col(0xFFFFFF, 0.95), col(0xFFFFFF, 0)]),
                         start: CGPoint(x: 0, y: faceR.maxY), end: CGPoint(x: 0, y: faceR.midY), options: [])
    c.restoreGState()
    // волна и курсор на грани
    let cy = faceR.midY
    let hs: [CGFloat] = [90, 190, 290, 190, 90]
    var bars: [CGPath] = []
    for (i, h) in hs.enumerated() { bars.append(bar(300 + CGFloat(i) * 68, cy, 42, h)) }
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: col(0x0B3B4A, 0.25))
    c.setFillColor(col(0x1F2A44))
    for p in bars { c.addPath(p); c.fillPath() }
    c.restoreGState()
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 0), blur: 14, color: col(teal, 0.6))
    c.setFillColor(col(teal))
    c.addPath(bar(300 + 5 * 68 + 12, cy, 20, 250)); c.fillPath()
    c.restoreGState()
    return c.makeImage()!
}

func iconC() -> CGImage {
    let c = makeContext(1024, 1024)
    drawBase(c, top: 0x34E3D0, bottom: 0x1C5FE0, glow: 0xB8FFF4)
    let cy: CGFloat = 540
    let x0: CGFloat = 190, xEnd: CGFloat = 834
    let wave = CGMutablePath()
    let steps = 500
    let waveLen: CGFloat = 450  // длина зоны синусоиды, дальше — прямая строка
    for i in 0...steps {
        let x = x0 + (xEnd - x0) * CGFloat(i) / CGFloat(steps)
        let t = min(1, (x - x0) / waveLen)
        let env = sin(.pi * t)
        let y = cy + 150 * env * sin(2 * .pi * 2 * t)
        if i == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
    }
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -9), blur: 18, color: col(0x00205A, 0.35))
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    c.setStrokeColor(col(0xFFFFFF)); c.setLineWidth(46); c.setLineCap(.round); c.setLineJoin(.round)
    c.addPath(wave); c.strokePath()
    c.endTransparencyLayer()
    c.restoreGState()
    // подчёркивание
    fillShapes(c, [lineBar(x0 + waveLen + 10, cy - 105, xEnd - x0 - waveLen - 10 + 23, 30)], color: col(0xFFFFFF, 0.6), shadow: 0.18)
    return c.makeImage()!
}

/// Template-иконка меню-бара (чёрный + альфа): миниатюра столбиков иконки приложения m1 (84/56 при высотах 210/390/270/330 из 1024):
/// ширина:зазор = 3:2, высоты 0.54/1/0.69/0.85. На сетке 18 pt: столбик 3, зазор 2, ширина группы 18, высота 14 (8/14/10/12 pt,
/// чётные пиксели @2x: 16/28/20/24 → центр по вертикали на целых пикселях). Полностью скруглённые торцы.
/// rec — тот же рисунок: отдельной точки нет (её принимали за столбик); запись macOS и так показывает оранжевым индикатором.
func menuBar(_ px: Int, rec: Bool, ink: UInt32 = 0x000000) -> CGImage {
    let c = makeContext(px, px)
    let k = CGFloat(px) / 18
    c.scaleBy(x: k, y: k)
    c.setFillColor(col(ink))
    let hs: [CGFloat] = [8, 14, 10, 12]
    let w: CGFloat = 3, pitch: CGFloat = 5
    for (i, h) in hs.enumerated() {
        let r = CGRect(x: CGFloat(i) * pitch, y: (18 - h) / 2, width: w, height: h)
        c.addPath(CGPath(roundedRect: r, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)); c.fillPath()
    }
    return c.makeImage()!
}

/// Сравнение: иконка приложения (m1) и иконка меню-бара в 12-кратном увеличении (чёрное на светлом, белое на тёмном).
func menuBarCompare() -> CGImage {
    let W = 1300, H = 560
    let c = makeContext(W, H)
    c.setFillColor(col(0xE9E9EB)); c.fill(CGRect(x: 0, y: 0, width: 880, height: H))
    c.setFillColor(col(0x2B2B2E)); c.fill(CGRect(x: 880, y: 0, width: W - 880, height: H))
    c.draw(minIcon(1), in: CGRect(x: 40, y: 28, width: 504, height: 504))
    c.interpolationQuality = .none
    c.draw(menuBar(36, rec: false), in: CGRect(x: 612, y: 172, width: 216, height: 216))
    c.draw(menuBar(36, rec: false, ink: 0xFFFFFF), in: CGRect(x: 960, y: 172, width: 216, height: 216))
    return c.makeImage()!
}

/// m1 для мелких размеров: подложка масштабируется, столбики рисуются по целым пикселям.
func m1Pixel(_ px: Int) -> CGImage {
    let big = makeContext(1024, 1024)
    drawFlatBase(big, 0xFFFFFF)
    let c = makeContext(px, px)
    c.draw(big.makeImage()!, in: CGRect(x: 0, y: 0, width: px, height: px))
    let k = CGFloat(px) / 1024
    let w = max(1, (84 * k).rounded()), gap = max(1, (56 * k).rounded())
    let total = 4 * w + 3 * gap
    let x0 = ((CGFloat(px) - total) / 2).rounded()
    c.setFillColor(col(0x111111))
    for (i, h0) in ([210, 390, 270, 330] as [CGFloat]).enumerated() {
        let h = max(w, (h0 * k).rounded())
        let y = ((CGFloat(px) - h) / 2).rounded()
        let r = CGRect(x: x0 + CGFloat(i) * (w + gap), y: y, width: w, height: h)
        c.addPath(CGPath(roundedRect: r, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)); c.fillPath()
    }
    return c.makeImage()!
}

func scaled(_ img: CGImage, _ px: Int) -> CGImage {
    let c = makeContext(px, px)
    c.interpolationQuality = .high
    c.draw(img, in: CGRect(x: 0, y: 0, width: px, height: px))
    return c.makeImage()!
}

func preview(_ dir: String) -> CGImage {
    let W = 1860, H = 640
    let c = makeContext(W, H)
    let half = CGFloat(W) / 2
    c.setFillColor(col(0xF2F2F5)); c.fill(CGRect(x: 0, y: 0, width: half, height: CGFloat(H)))
    c.setFillColor(col(0x1C1C1E)); c.fill(CGRect(x: half, y: 0, width: half, height: CGFloat(H)))
    let nsctx = NSGraphicsContext(cgContext: c, flipped: false)
    for (hi, light) in [true, false].enumerated() {
        let ox = CGFloat(hi) * half
        for (i, v) in ["A", "B", "C"].enumerated() {
            let src = (NSImage(contentsOfFile: "\(dir)/icon-\(v).png")!).cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let cx = ox + 160 + CGFloat(i) * 300
            c.draw(src, in: CGRect(x: cx - 140, y: 330, width: 280, height: 280))
            // 128/64/32
            var x = cx - 126
            for s in [128, 64, 32] {
                c.draw(scaled(src, s), in: CGRect(x: x, y: 150, width: CGFloat(s), height: CGFloat(s)))
                x += CGFloat(s) + 14
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsctx
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: light ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.9, alpha: 1),
            ]
            NSAttributedString(string: v, attributes: attrs).draw(at: NSPoint(x: cx - 8, y: 90))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    return c.makeImage()!
}


// MARK: - Минималистичные варианты m1…m24 (плоские, 2–3 цвета)

func mix(_ hex: UInt32, _ k: CGFloat) -> UInt32 {
    func ch(_ v: UInt32) -> UInt32 { UInt32(max(0, min(255, CGFloat(v) * (1 - k)))) }
    return (ch((hex >> 16) & 255) << 16) | (ch((hex >> 8) & 255) << 8) | ch(hex & 255)
}

/// Плоская подложка: внешняя тень, заливка с едва заметным градиентом (5%).
func drawFlatBase(_ c: CGContext, _ bg: UInt32) {
    let path = squircle(body)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: col(0x000000, 0.28))
    c.addPath(path); c.setFillColor(col(bg)); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(path); c.clip()
    c.drawLinearGradient(gradient([col(bg), col(mix(bg, 0.07))]),
                         start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}

func fp(_ c: CGContext, _ p: CGPath, _ color: UInt32) {
    c.addPath(p); c.setFillColor(col(color)); c.fillPath()
}
func vbars(_ c: CGContext, _ xs: [CGFloat], _ cy: CGFloat, _ w: CGFloat, _ hs: [CGFloat], _ color: UInt32) {
    for (i, x) in xs.enumerated() { fp(c, bar(x, cy, w, hs[i]), color) }
}
func strokePath(_ c: CGContext, _ p: CGPath, _ w: CGFloat, _ color: UInt32) {
    c.saveGState()
    c.addPath(p); c.setStrokeColor(col(color)); c.setLineWidth(w)
    c.setLineCap(.round); c.setLineJoin(.round); c.strokePath()
    c.restoreGState()
}
func arcPath(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ a0: CGFloat, _ a1: CGFloat, cw: Bool = false) -> CGPath {
    let p = CGMutablePath()
    p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: a0 * .pi / 180, endAngle: a1 * .pi / 180, clockwise: cw)
    return p
}
func polyline(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
    for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
    return p
}
/// Синусоида от x0 до x1 с `periods` периодов; после x1 при желании прямая до xEnd. fade — доля длины, где амплитуда плавно гаснет.
func sinePath(_ x0: CGFloat, _ x1: CGFloat, _ cy: CGFloat, _ amp: CGFloat, _ periods: CGFloat,
              flatTo: CGFloat? = nil, fadeFrom: CGFloat = 1) -> CGPath {
    let p = CGMutablePath()
    let n = 300
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n)
        let env: CGFloat = t < fadeFrom ? 1 : 0.5 * (1 + cos(.pi * (t - fadeFrom) / (1 - fadeFrom)))
        let pt = CGPoint(x: x0 + (x1 - x0) * t, y: cy + amp * env * sin(2 * .pi * periods * t))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    if let f = flatTo { p.addLine(to: CGPoint(x: f, y: cy)) }
    return p
}
func bubble(_ c: CGContext, _ r: CGRect, _ radius: CGFloat, _ color: UInt32) {
    fp(c, CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil), color)
    let tail = polyline([(r.minX + 90, r.minY + 20), (r.minX + 90, r.minY - 90), (r.minX + 215, r.minY + 20)])
    c.addPath(tail); c.setFillColor(col(color)); c.setLineJoin(.round); c.setLineWidth(30)
    c.setStrokeColor(col(color)); c.drawPath(using: .fillStroke)
}

let cream: UInt32 = 0xF4EFE6, navy: UInt32 = 0x1F2A4D, ink: UInt32 = 0x111111, graphite: UInt32 = 0x2B2D31
let sage: UInt32 = 0x8FAF9A, terra: UInt32 = 0xC2603F, mint: UInt32 = 0x7DE3C0, deepNavy: UInt32 = 0x14233F
let orange: UInt32 = 0xFF6B3D, lime: UInt32 = 0xC6F432, coral: UInt32 = 0xFF6B5E, blueGray: UInt32 = 0x8FA3B5

func minIcon(_ n: Int) -> CGImage {
    let c = makeContext(1024, 1024)
    let W: UInt32 = 0xFFFFFF
    let bgs: [Int: UInt32] = [1: W, 2: ink, 3: graphite, 4: cream, 5: sage, 6: deepNavy, 7: graphite, 8: terra,
        9: blueGray, 10: ink, 11: cream, 12: deepNavy, 13: cream, 14: sage, 15: graphite, 16: ink, 17: 0xD9DEE3,
        18: 0xE8E6E1, 19: graphite, 20: terra, 21: ink, 22: graphite, 23: 0xCFE8DC, 24: ink]
    drawFlatBase(c, bgs[n]!)
    let cy: CGFloat = 512
    switch n {
    case 1: // 3 столбика, чёрные на белом
        vbars(c, [302, 442, 582, 722], cy, 84, [210, 390, 270, 330], ink)   // 4 столбика, ритм как в оверлее (0.54/1/0.69/0.85, ширина:зазор = 3:2)
    case 2: // 3 столбика + точка-курсор
        vbars(c, [307, 437, 567], cy, 80, [200, 360, 240], W)
        fp(c, CGPath(ellipseIn: CGRect(x: 707 - 50, y: cy - 50, width: 100, height: 100), transform: nil), W)
    case 3: // курсор с дугами по бокам
        fp(c, bar(512, cy, 56, 300), W)
        for r in [130.0, 215.0] as [CGFloat] {
            strokePath(c, arcPath(512, cy, r, -38, 38), 38, orange)
            strokePath(c, arcPath(512, cy, r, 142, 218), 38, orange)
        }
    case 4: // « » из толстых штрихов
        for ax in [215.0, 325.0] as [CGFloat] { strokePath(c, polyline([(ax + 85, 650), (ax, cy), (ax + 85, 374)]), 64, navy) }
        for ax in [809.0, 699.0] as [CGFloat] { strokePath(c, polyline([(ax - 85, 650), (ax, cy), (ax - 85, 374)]), 64, navy) }
    case 5: // облачко с курсором
        bubble(c, CGRect(x: 212, y: 400, width: 600, height: 340), 120, W)
        fp(c, bar(512, 570, 48, 200), sage)
    case 6: // облачко с 3 столбиками
        bubble(c, CGRect(x: 212, y: 400, width: 600, height: 340), 120, mint)
        vbars(c, [422, 512, 602], 570, 52, [90, 190, 130], deepNavy)
    case 7: // капсула микрофона + строка
        fp(c, bar(512, 625, 170, 290), W)
        fp(c, lineBar(322, 330, 380, 56), lime)
    case 8: // S из одной плавной линии
        let p = CGMutablePath()
        p.addArc(center: CGPoint(x: 512, y: 620), radius: 110, startAngle: 30 * .pi / 180, endAngle: 270 * .pi / 180, clockwise: false)
        p.addArc(center: CGPoint(x: 512, y: 400), radius: 110, startAngle: 90 * .pi / 180, endAngle: 210 * .pi / 180, clockwise: true)
        strokePath(c, p, 84, cream)
    case 9: // волна → строка
        vbars(c, [205, 285, 365], cy, 56, [130, 260, 170], W)
        strokePath(c, polyline([(450, cy), (610, cy)]), 44, W)
        strokePath(c, polyline([(550, cy + 60), (610, cy), (550, cy - 60)]), 44, W)
        fp(c, lineBar(660, cy + 56, 170, 48), W)
        fp(c, lineBar(660, cy - 56, 120, 48), W)
    case 10: // точка записи + строки
        fp(c, CGPath(ellipseIn: CGRect(x: 315 - 96, y: cy - 96, width: 192, height: 192), transform: nil), coral)
        fp(c, lineBar(475, cy + 62, 330, 56), W)
        fp(c, lineBar(475, cy - 62, 220, 56), W)
    case 11: // keycap контуром с волной
        let r = CGRect(x: 232, y: 282, width: 560, height: 460)
        strokePath(c, CGPath(roundedRect: r.insetBy(dx: 18, dy: 18), cornerWidth: 110, cornerHeight: 110, transform: nil), 36, navy)
        vbars(c, [412, 512, 612], cy, 64, [120, 250, 170], navy)
    case 12: // толстая синусоида → линия
        strokePath(c, sinePath(180, 560, cy, 160, 1.5, flatTo: 844, fadeFrom: 0.45), 78, mint)
    case 13: // дуги звука вверх из курсора
        fp(c, bar(512, 400, 56, 200), terra)
        for r in [150.0, 240.0, 330.0] as [CGFloat] { strokePath(c, arcPath(512, 400, r, 52, 128), 40, terra) }
    case 14: // строки, первая — волна
        strokePath(c, sinePath(215, 809, 650, 34, 3), 50, W)
        fp(c, lineBar(190, 512, 560, 50), W)
        fp(c, lineBar(190, 374, 340, 50), W)
    case 15: // буква T: столбик + волна
        strokePath(c, sinePath(240, 784, 690, 36, 2), 64, lime)
        fp(c, bar(512, 495, 90, 400), W)
    case 16: // поле ввода [ | ]
        strokePath(c, polyline([(330, 700), (250, 700), (250, 324), (330, 324)]), 56, W)
        strokePath(c, polyline([(694, 700), (774, 700), (774, 324), (694, 324)]), 56, W)
        fp(c, bar(512, cy, 56, 300), coral)
    case 17: // точки + 3 линии
        for (i, w) in ([480, 400, 280] as [CGFloat]).enumerated() {
            let y = 650 - CGFloat(i) * 138
            fp(c, CGPath(ellipseIn: CGRect(x: 230 - 34, y: y - 34, width: 68, height: 68), transform: nil), navy)
            fp(c, lineBar(330, y, w, 60), navy)
        }
    case 18: // микрофон: капсула + дуга
        fp(c, bar(512, 600, 200, 340), graphite)
        strokePath(c, arcPath(512, 590, 230, 180, 360), 44, orange)
        strokePath(c, polyline([(512, 360), (512, 270)]), 44, orange)
        strokePath(c, polyline([(400, 270), (624, 270)]), 44, orange)
    case 19: // 5 столбиков, средний акцент
        for k in 0..<5 {
            fp(c, bar(512 + 110 * CGFloat(k - 2), cy, 70, [150, 270, 390, 270, 150][k]), k == 2 ? orange : W)
        }
    case 20: // облачко с волной
        bubble(c, CGRect(x: 212, y: 400, width: 600, height: 340), 120, cream)
        strokePath(c, sinePath(340, 684, 570, 50, 1.5), 34, terra)
    case 21: // I-beam
        fp(c, bar(512, cy, 56, 424), lime)
        fp(c, lineBar(402, 724, 220, 52), lime)
        fp(c, lineBar(402, 300, 220, 52), lime)
    case 22: // кольцо с волной
        c.addPath(CGPath(ellipseIn: CGRect(x: 222, y: 222, width: 580, height: 580), transform: nil))
        c.setStrokeColor(col(0x6CC4FF)); c.setLineWidth(44); c.strokePath()
        vbars(c, [412, 512, 612], cy, 64, [150, 300, 200], W)
    case 23: // 9 тонких столбиков
        let hs: [CGFloat] = [90, 200, 140, 320, 420, 260, 170, 230, 80]
        for k in 0..<9 { fp(c, bar(512 + 64 * CGFloat(k - 4), cy, 36, hs[k]), navy) }
    default: // 24: приглашение > и курсор
        strokePath(c, polyline([(324, 640), (504, cy), (324, 384)]), 70, orange)
        fp(c, bar(704, cy, 64, 260), W)
    }
    return c.makeImage()!
}

func labelText(_ c: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, center: Bool = true) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    let a = NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor(white: 0.2, alpha: 1)])
    let w = a.size().width
    a.draw(at: NSPoint(x: center ? x - w / 2 : x, y: y))
    NSGraphicsContext.restoreGraphicsState()
}

func loadPNG(_ path: String) -> CGImage {
    NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

func minSheets(_ dir: String) {
    let imgs = (1...24).map { loadPNG("\(dir)/m\($0).png") }
    // крупный лист: 6x4, тело иконки ~180 px (холст 224)
    let cw: CGFloat = 270, ch: CGFloat = 300
    let c = makeContext(Int(cw) * 6 + 40, Int(ch) * 4 + 40)
    c.setFillColor(col(0xE3E4E8)); c.fill(CGRect(x: 0, y: 0, width: c.width, height: c.height))
    for i in 0..<24 {
        let col_ = i % 6, row = i / 6
        let x = 20 + CGFloat(col_) * cw + (cw - 224) / 2
        let y = CGFloat(c.height) - 20 - CGFloat(row + 1) * ch + 52
        c.draw(imgs[i], in: CGRect(x: x, y: y, width: 224, height: 224))
        labelText(c, "\(i + 1)", x + 112, y - 36, size: 30)
    }
    writePNG(c.makeImage()!, "\(dir)/sheet.png")
    // мелкие: тело 64 и 32 px
    let sw: CGFloat = 150, sh: CGFloat = 130
    let s = makeContext(Int(sw) * 6 + 40, Int(sh) * 4 + 40)
    s.setFillColor(col(0xE3E4E8)); s.fill(CGRect(x: 0, y: 0, width: s.width, height: s.height))
    for i in 0..<24 {
        let x = 20 + CGFloat(i % 6) * sw, row = i / 6
        let y = CGFloat(s.height) - 20 - CGFloat(row + 1) * sh + 40
        let crop = imgs[i].cropping(to: CGRect(x: 100, y: 100, width: 824, height: 824))!
        s.draw(scaled(crop, 64), in: CGRect(x: x + 6, y: y, width: 64, height: 64))
        s.draw(scaled(crop, 32), in: CGRect(x: x + 82, y: y, width: 32, height: 32))
        labelText(s, "\(i + 1)", x + 6, y - 28, size: 18, center: false)
    }
    writePNG(s.makeImage()!, "\(dir)/sheet-small.png")
}


// MARK: - Варианты с текстом t1…t12 (контуры шрифта через CoreText)

let fRounded: NSFont = NSFont(descriptor: NSFont.systemFont(ofSize: 1000, weight: .heavy).fontDescriptor.withDesign(.rounded)!, size: 1000)!
let fBlack: NSFont = NSFont.systemFont(ofSize: 1000, weight: .black)
let fAvenir: NSFont = NSFont(name: "AvenirNext-Heavy", size: 1000)!
let fMono: NSFont = NSFont.monospacedSystemFont(ofSize: 1000, weight: .bold)

enum Item {
    case g(String, NSFont, CGFloat, CGFloat, UInt32)          // символ, шрифт, масштаб, сдвиг по y, цвет
    case bars([CGFloat], CGFloat, CGFloat, CGFloat, UInt32)   // высоты, ширина, зазор, сдвиг по y, цвет
    case gap(CGFloat)
    case sliced(String, NSFont, UInt32)                       // символ, разрезанный на 3 столбика
}

/// Раскладка по базовой линии в единицах шрифта 1000 pt; возвращает контуры с цветом и признаком «резать».
func layoutItems(_ items: [Item], track: CGFloat) -> [(CGPath, UInt32, Bool)] {
    var out: [(CGPath, UInt32, Bool)] = []
    var x: CGFloat = 0
    let cap: CGFloat = 730
    func glyph(_ ch: String, _ f: NSFont) -> (CGPath, CGFloat) {
        var u = Array(ch.utf16); var g = [CGGlyph](repeating: 0, count: u.count)
        CTFontGetGlyphsForCharacters(f, &u, &g, u.count)
        var adv = CGSize.zero
        CTFontGetAdvancesForGlyphs(f, .horizontal, g, &adv, 1)
        return (CTFontCreatePathForGlyph(f, g[0], nil) ?? CGMutablePath(), adv.width)
    }
    for it in items {
        switch it {
        case let .g(ch, f, sc, dy, color):
            let (p, adv) = glyph(ch, f)
            var t = CGAffineTransform(translationX: x, y: dy).scaledBy(x: sc, y: sc)
            if let q = p.copy(using: &t) { out.append((q, color, false)) }
            x += adv * sc + track
        case let .sliced(ch, f, color):
            let (p, adv) = glyph(ch, f)
            var t = CGAffineTransform(translationX: x, y: 0)
            if let q = p.copy(using: &t) { out.append((q, color, true)) }
            x += adv + track
        case let .bars(hs, w, gp, dy, color):
            for h in hs {
                out.append((bar(x + w / 2, cap / 2 + dy, w, h), color, false))
                x += w + gp
            }
            x += track - gp
        case let .gap(g): x += g
        }
    }
    return out
}

func drawItems(_ c: CGContext, _ items: [Item], cx: CGFloat, cy: CGFloat, width: CGFloat, maxH: CGFloat = 520, track: CGFloat = 0) {
    let parts = layoutItems(items, track: track)
    var bb = CGRect.null
    for p in parts { bb = bb.union(p.0.boundingBoxOfPath) }
    let k = min(width / bb.width, maxH / bb.height)
    let t = CGAffineTransform(translationX: cx - bb.midX * k, y: cy - bb.midY * k).scaledBy(x: k, y: k)
    for (p, color, slice) in parts {
        var tt = t
        guard let q = p.copy(using: &tt) else { continue }
        if slice {
            let b = q.boundingBoxOfPath
            c.saveGState()
            let cw = (b.width - 2 * 22) / 3
            for i in 0..<3 {
                let r = CGRect(x: b.minX + CGFloat(i) * (cw + 22), y: b.minY - 2, width: cw, height: b.height + 4)
                c.addPath(CGPath(roundedRect: r, cornerWidth: cw * 0.3, cornerHeight: cw * 0.3, transform: nil))
            }
            c.clip()
            fp(c, q, color)
            c.restoreGState()
        } else { fp(c, q, color) }
    }
}

func textIcon(_ n: Int) -> CGImage {
    let c = makeContext(1024, 1024)
    let W: UInt32 = 0xFFFFFF
    let bgs: [Int: UInt32] = [1: W, 2: ink, 3: W, 4: W, 5: ink, 6: W, 7: ink, 8: W, 9: graphite, 10: W, 11: deepNavy, 12: lime]
    drawFlatBase(c, bgs[n]!)
    let S = "S", Two = "2", T = "T"
    switch n {
    case 1: drawItems(c, [.g(S, fRounded, 1, 0, ink), .g(Two, fRounded, 1, 0, ink), .g(T, fRounded, 1, 0, ink)], cx: 512, cy: 512, width: 680, track: 10)
    case 2: drawItems(c, [.g(S, fBlack, 1, 0, W), .g(Two, fBlack, 1, 0, W), .g(T, fBlack, 1, 0, W)], cx: 512, cy: 512, width: 680, track: 10)
    case 3: drawItems(c, [.g(S, fAvenir, 1, 0, ink), .g(Two, fAvenir, 1, 0, orange), .g(T, fAvenir, 1, 0, ink)], cx: 512, cy: 512, width: 680, track: 10)
    case 4: // 2 как степень
        drawItems(c, [.g(S, fRounded, 1, 0, ink), .g(Two, fRounded, 0.58, 300, ink), .g(T, fRounded, 1, 0, ink)], cx: 512, cy: 512, width: 680, track: 10)
    case 5: // 2 как индекс, чёрная подложка
        drawItems(c, [.g(S, fRounded, 1, 0, W), .g(Two, fRounded, 0.58, -120, W), .g(T, fRounded, 1, 0, W)], cx: 512, cy: 512, width: 680, track: 10)
    case 6: // S ||| T
        drawItems(c, [.g(S, fRounded, 1, 0, ink), .gap(60), .bars([470, 730, 560], 190, 90, 0, ink), .gap(60), .g(T, fRounded, 1, 0, ink)],
                  cx: 512, cy: 512, width: 700)
    case 7: // маленькие столбики между буквами
        drawItems(c, [.g(S, fBlack, 1, 0, W), .gap(50), .bars([300, 480, 350], 100, 60, 0, orange), .gap(50), .g(T, fBlack, 1, 0, W)],
                  cx: 512, cy: 512, width: 680)
    case 8: // S из столбиков + «2T»
        drawItems(c, [.sliced(S, fRounded, ink), .gap(10), .g(Two, fRounded, 1, 0, ink), .g(T, fRounded, 1, 0, ink)], cx: 512, cy: 512, width: 680, track: 10)
    case 9: // s2t_ в моноширинном шрифте + курсор
        drawItems(c, [.g("s", fMono, 1, 0, W), .g(Two, fMono, 1, 0, W), .g(T, fMono, 1, 0, W), .gap(40),
                      .bars([760], 90, 0, 20, lime)], cx: 512, cy: 512, width: 660, track: 0)
    case 10: // m1 + подпись
        vbars(c, [432, 512, 592], 590, 60, [150, 270, 190], ink)
        drawItems(c, [.g(S, fRounded, 1, 0, ink), .g(Two, fRounded, 1, 0, ink), .g(T, fRounded, 1, 0, ink)], cx: 512, cy: 330, width: 230, maxH: 120, track: 10)
    case 11: // текст + линия поля ввода
        drawItems(c, [.g(S, fRounded, 1, 0, W), .g(Two, fRounded, 1, 0, W), .g(T, fRounded, 1, 0, W)], cx: 512, cy: 560, width: 640, track: 10)
        fp(c, lineBar(192, 280, 640, 56), mint)
    default: // 12: лаймовая подложка
        drawItems(c, [.g(S, fBlack, 1, 0, ink), .g(Two, fBlack, 1, 0, ink), .g(T, fBlack, 1, 0, ink)], cx: 512, cy: 512, width: 680, track: 10)
    }
    return c.makeImage()!
}

func textSheets(_ dir: String) {
    let imgs = (1...12).map { loadPNG("\(dir)/t\($0).png") }
    let m1 = minIcon(1)
    let cw: CGFloat = 270, ch: CGFloat = 300
    let c = makeContext(Int(cw) * 5 + 40, Int(ch) * 3 + 40)
    c.setFillColor(col(0xE3E4E8)); c.fill(CGRect(x: 0, y: 0, width: c.width, height: c.height))
    func cell(_ img: CGImage, _ label: String, _ ci: Int, _ row: Int) {
        let x = 20 + CGFloat(ci) * cw + (cw - 224) / 2
        let y = CGFloat(c.height) - 20 - CGFloat(row + 1) * ch + 52
        c.draw(img, in: CGRect(x: x, y: y, width: 224, height: 224))
        labelText(c, label, x + 112, y - 36, size: 30)
    }
    cell(m1, "m1", 0, 0)
    for i in 0..<12 { cell(imgs[i], "t\(i + 1)", 1 + i % 4, i / 4) }
    writePNG(c.makeImage()!, "\(dir)/sheet.png")
    let sw: CGFloat = 150, sh: CGFloat = 130
    let s = makeContext(Int(sw) * 5 + 40, Int(sh) * 3 + 40)
    s.setFillColor(col(0xE3E4E8)); s.fill(CGRect(x: 0, y: 0, width: s.width, height: s.height))
    func scell(_ img: CGImage, _ label: String, _ ci: Int, _ row: Int) {
        let x = 20 + CGFloat(ci) * sw
        let y = CGFloat(s.height) - 20 - CGFloat(row + 1) * sh + 40
        let crop = img.cropping(to: CGRect(x: 100, y: 100, width: 824, height: 824))!
        s.draw(scaled(crop, 64), in: CGRect(x: x + 6, y: y, width: 64, height: 64))
        s.draw(scaled(crop, 32), in: CGRect(x: x + 82, y: y, width: 32, height: 32))
        labelText(s, label, x + 6, y - 28, size: 18, center: false)
    }
    scell(m1, "m1", 0, 0)
    for i in 0..<12 { scell(imgs[i], "t\(i + 1)", 1 + i % 4, i / 4) }
    writePNG(s.makeImage()!, "\(dir)/sheet-small.png")
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: swift make_icon.swift <A|B|C|menubar|preview> <outdir>")
    exit(1)
}
let variant = args[1], out = args[2]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
switch variant {
case "A": writePNG(iconA(), "\(out)/icon-A.png")
case "B": writePNG(iconB(), "\(out)/icon-B.png")
case "C": writePNG(iconC(), "\(out)/icon-C.png")
case "menubar":
    writePNG(menuBar(18, rec: false), "\(out)/MenuBarIcon.png")
    writePNG(menuBar(36, rec: false), "\(out)/MenuBarIcon@2x.png")
    writePNG(menuBar(18, rec: true), "\(out)/MenuBarIconRec.png")
    writePNG(menuBar(36, rec: true), "\(out)/MenuBarIconRec@2x.png")
case "iconset": // m1 -> <outdir>/AppIcon.iconset (затем iconutil -c icns)
    let dir = "\(out)/AppIcon.iconset"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let full = minIcon(1)
    for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                       ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
        writePNG(px <= 64 ? m1Pixel(px) : (px == 1024 ? full : scaled(full, px)), "\(dir)/icon_\(name).png")
    }
case "menubar-compare": writePNG(menuBarCompare(), "\(out)/menubar-compare.png")
case "preview": writePNG(preview(out), "\(out)/preview.png")
case "textall":
    for n in 1...12 { writePNG(textIcon(n), "\(out)/t\(n).png") }
    textSheets(out)
case "minall":
    for n in 1...24 { writePNG(minIcon(n), "\(out)/m\(n).png") }
    minSheets(out)
default:
    if variant.hasPrefix("t"), let n = Int(variant.dropFirst()), (1...12).contains(n) {
        writePNG(textIcon(n), "\(out)/t\(n).png")
    } else if variant.hasPrefix("m"), let n = Int(variant.dropFirst()), (1...24).contains(n) {
        writePNG(minIcon(n), "\(out)/m\(n).png")
    } else { print("неизвестный вариант \(variant)"); exit(1) }
}
