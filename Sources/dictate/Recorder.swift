import Foundation
import AVFoundation

/// Captures the mic and delivers 16 kHz mono Float32 pieces.
final class Recorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    var onSamples: (([Float]) -> Void)?

    func start() throws {
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        guard inFmt.sampleRate > 0 else { throw NSError(domain: "rec", code: 1, userInfo: [NSLocalizedDescriptionKey: "no input device / mic permission"]) }
        converter = AVAudioConverter(from: inFmt, to: outFmt)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFmt) { [weak self] buf, _ in
            self?.convert(buf)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func convert(_ buf: AVAudioPCMBuffer) {
        guard let conv = converter else { return }
        let ratio = outFmt.sampleRate / buf.format.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return }
        var given = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return buf
        }
        if err == nil, out.frameLength > 0, let p = out.floatChannelData {
            onSamples?(Array(UnsafeBufferPointer(start: p[0], count: Int(out.frameLength))))
        }
    }
}
