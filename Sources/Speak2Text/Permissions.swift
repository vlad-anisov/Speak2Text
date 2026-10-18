import SwiftUI
import AVFoundation
import ServiceManagement

final class PermissionsModel: ObservableObject {
    @Published var mic = false
    @Published var input = false
    @Published var ax = false
    private var timer: Timer?

    var allOK: Bool { mic && input && ax }

    func refresh() {
        mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        input = CGPreflightListenEventAccess()
        ax = AXIsProcessTrusted()
    }
    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func stopPolling() { timer?.invalidate(); timer = nil }

    func openMic() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.refresh() } }
        } else { Permissions.open("Privacy_Microphone") }
    }
    func openInput() {
        Permissions.registerInputMonitoring()
        // Give TCC a moment to add the row, otherwise the pane opens with a stale list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Permissions.open("Privacy_ListenEvent") }
    }
    func openAX() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        Permissions.open("Privacy_Accessibility")
    }
}

enum Permissions {
    static func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// Adds the app to the Input Monitoring list (unchecked) and shows the system prompt,
    /// so the user only has to flip the switch instead of adding the app with +.
    static func registerInputMonitoring() {
        guard !CGPreflightListenEventAccess() else { return }
        _ = CGRequestListenEventAccess()
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let cb: CGEventTapCallBack = { _, _, e, _ in Unmanaged.passUnretained(e) }
        if let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                     eventsOfInterest: mask, callback: cb, userInfo: nil) { CFMachPortInvalidate(t) }
        appLog("input monitoring requested")
    }

    /// Starts a fresh copy of the app and quits this one (a granted permission is only seen by a new process).
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open -n \"\(Bundle.main.bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}

struct PermissionsView: View {
    @StateObject private var m = PermissionsModel()

    var body: some View {
        Form {
            Section {
                row(L("Microphone"), L("to record your voice"), m.mic, m.openMic)
                row(L("Input Monitoring"), L("to see the hotkey"), m.input, m.openInput)
                row(L("Accessibility"), L("to paste the text with Cmd+V"), m.ax, m.openAX)
            } header: {
                Text(L("Speak2Text needs three permissions"))
            } footer: {
                if !m.allOK {
                    Text(L("Speak2Text is not in the Input Monitoring list? Quit System Settings (⌘Q) and press the button again.") + " " + L("If the app is already in the list, remove it with the − button and add it again.")).footerStyle()
                }
            }
            Section {
                if !m.allOK {
                    HStack {
                        Text(L("Granted but still showing ✗? The app must be restarted.")).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Restart")) { Permissions.relaunch() }
                    }
                } else {
                    Label(L("All set. You can close this window."), systemImage: "checkmark.seal").foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { m.startPolling() }
        .onDisappear { m.stopPolling() }
    }

    private func row(_ title: String, _ why: String, _ ok: Bool, _ action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red).font(.title3)
            VStack(alignment: .leading) { Text(title); Text(why).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if !ok { Button(L("Open Settings")) { action() } }
        }
    }
}

enum LoginItem {
    /// Registers or unregisters the app as a login item; only meaningful for an installed .app.
    static func apply(_ enabled: Bool) {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let svc = SMAppService.mainApp
        do {
            if enabled, svc.status != .enabled { try svc.register(); appLog("login item registered") }
            else if !enabled, svc.status == .enabled { try svc.unregister(); appLog("login item removed") }
        } catch { appLog("login item error: \(error)") }
    }
}
