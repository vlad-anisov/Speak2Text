import Foundation
import CoreAudio

/// Mutes (volume 0) the default output device while recording and restores it afterwards.
/// The original volume is written to disk first, so a crash during recording is repaired on the next launch.
final class AudioMuter {
    private struct Saved: Codable {
        var uid: String
        var volumes: [UInt32: Float]   // element -> original volume
    }

    private var active = false

    private static func addr(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
    }

    private static func defaultOutput() -> AudioDeviceID? {
        var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
        return st == noErr && dev != 0 ? dev : nil
    }

    private static func uid(of dev: AudioDeviceID) -> String? {
        var a = addr(kAudioDevicePropertyDeviceUID)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &cf) == noErr, let s = cf?.takeRetainedValue() else { return nil }
        return s as String
    }

    private static func device(forUID uid: String) -> AudioDeviceID? {
        var a = addr(kAudioHardwarePropertyTranslateUIDToDevice)
        var cf = uid as CFString
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let st = withUnsafeMutablePointer(to: &cf) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), $0, &size, &dev)
        }
        return st == noErr && dev != 0 ? dev : nil
    }

    /// Elements of the device that have a settable output volume (master, or the individual channels).
    private static func volumeElements(_ dev: AudioDeviceID) -> [UInt32] {
        func settable(_ e: UInt32) -> Bool {
            var a = addr(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: e)
            guard AudioObjectHasProperty(dev, &a) else { return false }
            var ok: DarwinBoolean = false
            return AudioObjectIsPropertySettable(dev, &a, &ok) == noErr && ok.boolValue
        }
        if settable(0) { return [0] }
        return [1, 2].filter(settable)
    }

    private static func volume(_ dev: AudioDeviceID, _ e: UInt32) -> Float? {
        var a = addr(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: e)
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    @discardableResult
    private static func setVolume(_ dev: AudioDeviceID, _ e: UInt32, _ v: Float) -> Bool {
        var a = addr(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: e)
        var x = Float32(min(max(v, 0), 1))
        return AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &x) == noErr
    }

    /// Current volume of the default output (for tests); nil if the device has no volume control.
    static func currentVolume() -> Float? {
        guard let dev = defaultOutput(), let e = volumeElements(dev).first else { return nil }
        return volume(dev, e)
    }

    func mute() {
        let level: Float = 0
        guard !active, let dev = AudioMuter.defaultOutput(), let uid = AudioMuter.uid(of: dev) else { return }
        let els = AudioMuter.volumeElements(dev)
        guard !els.isEmpty else { appLog("mute: output device has no volume control, skipped"); return }
        var orig: [UInt32: Float] = [:]
        for e in els { if let v = AudioMuter.volume(dev, e) { orig[e] = v } }
        guard orig.values.contains(where: { $0 > level }) else { return }
        // persist before touching anything
        if let d = try? JSONEncoder().encode(Saved(uid: uid, volumes: orig)) {
            try? FileManager.default.createDirectory(atPath: Paths.supportDir, withIntermediateDirectories: true)
            try? d.write(to: URL(fileURLWithPath: Paths.muteStateFile), options: .atomic)
        }
        for (e, v) in orig where v > level { AudioMuter.setVolume(dev, e, level) }
        active = true
    }

    func restore() {
        guard active else { return }
        active = false
        AudioMuter.restoreFromDisk()
    }

    /// Puts the saved volume back and deletes the state file. Also used at launch after a crash.
    @discardableResult
    static func restoreFromDisk() -> Bool {
        let url = URL(fileURLWithPath: Paths.muteStateFile)
        guard let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: d) else { return false }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let dev = device(forUID: s.uid) else { return false }
        for (e, v) in s.volumes { setVolume(dev, e, v) }
        return true
    }

    static var hasPendingRestore: Bool { FileManager.default.fileExists(atPath: Paths.muteStateFile) }
}
