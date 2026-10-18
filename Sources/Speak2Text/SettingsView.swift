import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label(L("General"), systemImage: "gearshape") }
            DictionaryTab().tabItem { Label(L("Dictionary"), systemImage: "text.book.closed") }
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
                Toggle(L("Mute other sounds while recording"), isOn: $s.muteEnabled)
                if s.muteEnabled {
                    HStack {
                        Text(L("Volume while recording"))
                        Slider(value: Binding(get: { Double(s.muteLevel) }, set: { s.muteLevel = Int($0) }), in: 0...50, step: 5)
                        Text("\(s.muteLevel)%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle(L("Show overlay while recording"), isOn: $s.overlayEnabled)
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

/// Comma / newline separated list of terms; the text is kept locally so typing a trailing comma is not eaten.
struct TermsEditor: View {
    @Binding var terms: [String]
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
            .onAppear { if !loaded { text = terms.joined(separator: ", "); loaded = true } }
            .onChange(of: text) { _, new in
                terms = new.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
    }
}

struct DictionaryTab: View {
    @ObservedObject var s = Settings.shared

    var body: some View {
        Form {
            Section(L("Replacements")) {
                Text(L("Applied to the final text, ignoring case, on whole words only."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($s.replacements) { $r in
                    HStack {
                        TextField(L("Recognized as"), text: $r.from).textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField(L("Replace with"), text: $r.to).textFieldStyle(.roundedBorder)
                        Button { s.replacements.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button { s.replacements.append(Replacement(from: "", to: "")) } label: { Label(L("Add"), systemImage: "plus") }
            }
            Section(L("Filler words")) {
                Toggle(L("Remove filler words"), isOn: $s.fillersEnabled)
                if s.fillersEnabled {
                    TermsEditor(terms: $s.fillers)
                    Text(L("Separated by commas. Removed together with the commas around them."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Model hints")) {
                Toggle(L("Pass terms to the model as a prompt"), isOn: $s.promptEnabled)
                if s.promptEnabled {
                    TermsEditor(terms: $s.promptTerms)
                    Text(L("May skip or duplicate words (confirmed in the benchmark). Use only if names are recognized badly."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}
