import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label(L("General"), systemImage: "gearshape") }
        }
        .frame(width: 520, height: 440)
    }
}

struct GeneralTab: View {
    @ObservedObject var s = Settings.shared
    @StateObject private var capture = HotkeyCapture()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(L("Hotkey"))
                    Spacer()
                    Text(capture.capturing ? L("Press a key or combination…") : s.hotkey.displayName)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(capture.capturing ? 0.3 : 0.15)))
                    Button(capture.capturing ? L("Cancel") : L("Record")) {
                        if capture.capturing { capture.stop(); AppDelegate.shared?.hotkey.suspended = false }
                        else {
                            AppDelegate.shared?.hotkey.suspended = true
                            capture.start { spec in
                                AppDelegate.shared?.hotkey.suspended = false
                                if let spec { s.hotkey = spec }
                            }
                        }
                    }
                    Button(L("Reset")) { s.hotkey = .default }.disabled(capture.capturing || s.hotkey == .default)
                }
                if isPlainTypingKey {
                    Text(L("This key will no longer type its character while Speak2Text runs. Prefer F13, a modifier or a combination."))
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker(L("Mode"), selection: $s.mode) {
                    Text(L("Hold to talk")).tag("hold")
                    Text(L("Press to start, press to stop")).tag("toggle")
                }
                Text(s.mode == "hold" ? L("Hold the key, speak, release: the text is inserted.") : L("Esc cancels the recording."))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L("Language"), selection: $s.language) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                    Text(L("Auto-detect")).tag("auto")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var isPlainTypingKey: Bool {
        let h = s.hotkey
        guard !h.modifierOnly, h.mods == 0, let n = HotkeySpec.keyNames[h.keyCode] else { return false }
        return n.count == 1 || ["Space", "Return", "Tab", "Delete"].contains(n)
    }
}
