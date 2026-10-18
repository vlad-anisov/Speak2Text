import SwiftUI

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab = "general"
}

struct SettingsView: View {
    @ObservedObject var nav = SettingsNav.shared
    var body: some View {
        TabView(selection: $nav.tab) {
            GeneralTab().tabItem { Label(L("General"), systemImage: "gearshape") }.tag("general")
            ModelTab().tabItem { Label(L("Model"), systemImage: "cpu") }.tag("model")
            DictionaryTab().tabItem { Label(L("Dictionary"), systemImage: "text.book.closed") }.tag("dictionary")
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
                Toggle(L("Start and stop sounds"), isOn: $s.soundsEnabled)
                Toggle(L("Launch at login"), isOn: $s.launchAtLogin)
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

struct ModelTab: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var m = EngineManager.shared
    @StateObject private var test = SpeedTest()
    @State private var useMic = false
    @State private var testNote: String?

    var body: some View {
        Form {
            Section(L("Model")) {
                ForEach(ModelCatalog.all) { info in modelRow(info) }
                Picker(L("Accelerator"), selection: $s.accelerator) {
                    Text("Neural Engine").tag(Accelerator.ane)
                    Text("GPU").tag(Accelerator.gpu)
                    Text("CPU").tag(Accelerator.cpu)
                }
                statusLine
                Text(L("Changing the model or accelerator recompiles CoreML: the first load can take up to about 3 minutes. Do not quit the app meanwhile."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Speed test")) {
                Picker(L("Sample"), selection: $useMic) {
                    Text(L("Built-in sample")).tag(false)
                    Text(L("Microphone, 5 s")).tag(true)
                }.pickerStyle(.segmented)
                HStack {
                    Button(test.running ? L("Testing…") : L("Run test")) { runTest() }
                        .disabled(test.running || test.recordingLeft != nil || ModelCatalog.folder(for: s.model) == nil || AppDelegate.shared?.state == .recording)
                    if let left = test.recordingLeft { Text(String(format: L("Speak now: %d s"), left)) }
                    if let n = testNote { Text(n).foregroundStyle(.red).font(.caption) }
                    Spacer()
                    if let b = test.best, !test.running {
                        Button(String(format: L("Use best: %@"), name(b))) { s.accelerator = b }.disabled(s.accelerator == b)
                    }
                }
                if !test.rows.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text(L("Accelerator")).bold(); Text(L("Load, s")).bold(); Text(L("Recognize, s")).bold(); Text(L("Text")).bold()
                        }
                        ForEach(test.rows) { r in
                            GridRow {
                                Text(name(r.id))
                                Text(r.running ? "…" : r.loadS.map { String(format: "%.1f", $0) } ?? "–").monospacedDigit()
                                Text(r.running ? "…" : r.recogS.map { String(format: "%.2f", $0) } ?? "–").monospacedDigit()
                                Text(r.error ?? r.text).lineLimit(2).font(.caption).foregroundStyle(r.error == nil ? Color.primary : Color.red)
                            }
                        }
                    }
                }
                Text(L("The first run on each accelerator is slow: CoreML compiles the model for it (up to a few minutes). Later runs are fast."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func name(_ a: Accelerator) -> String { a == .ane ? "Neural Engine" : a == .gpu ? "GPU" : "CPU" }

    @ViewBuilder private func modelRow(_ info: ModelInfo) -> some View {
        let have = ModelCatalog.folder(for: info.id) != nil
        HStack {
            Image(systemName: s.model == info.id ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(have ? Color.accentColor : Color.secondary)
                .onTapGesture { if have { s.model = info.id } }
            VStack(alignment: .leading) {
                Text(info.title)
                Text("\(info.sizeMB) MB").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let p = m.downloads[info.id] {
                ProgressView(value: p).frame(width: 90)
                Text("\(Int(p * 100))%").monospacedDigit().font(.caption)
            } else if have {
                Text(L("Downloaded")).font(.caption).foregroundStyle(.secondary)
            } else {
                if let e = m.downloadErrors[info.id] { Text(e).font(.caption).foregroundStyle(.red).lineLimit(1) }
                Button(L("Download")) { m.download(info.id) }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var statusLine: some View {
        switch m.status {
        case .preparing:
            HStack {
                ProgressView().controlSize(.small)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let secs = Int(ctx.date.timeIntervalSince(m.preparingSince ?? ctx.date))
                    Text(String(format: "%@ %d:%02d", L("Preparing model…"), secs / 60, secs % 60)).monospacedDigit()
                }
            }
        case .ready:
            Label(m.lastLoadSeconds.map { String(format: L("Ready (loaded in %.1f s)"), $0) } ?? L("Ready"), systemImage: "checkmark.circle").foregroundStyle(.green)
        case .needsDownload:
            Label(L("Model is not downloaded"), systemImage: "arrow.down.circle").foregroundStyle(.orange)
        case .failed(let e):
            Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).lineLimit(3)
        }
    }

    private func runTest() {
        testNote = nil
        guard let folder = ModelCatalog.folder(for: s.model) else { return }
        let lang = s.language
        if useMic {
            test.recordSample { samples in
                guard let samples, samples.count > 16000 else { testNote = L("No audio from the microphone"); return }
                test.run(samples: samples, modelFolder: folder, language: lang)
            }
        } else if let samples = SpeedTest.builtInSample() {
            test.run(samples: samples, modelFolder: folder, language: lang)
        } else { testNote = L("Built-in sample not found") }
    }
}
