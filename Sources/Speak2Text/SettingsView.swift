import SwiftUI

/// Selected tab id; the window controller and the views share it (e.g. to open the Permissions tab).
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab = UserDefaults.standard.string(forKey: "settingsTab") ?? "general" {
        didSet { UserDefaults.standard.set(tab, forKey: "settingsTab") }
    }
}

// MARK: - General

/// Keycap-like chip with the current hotkey; turns into "Press a key…" while recording.
struct KeycapChip: View {
    let text: String
    let recording: Bool

    var body: some View {
        Text(text)
            .foregroundStyle(recording ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .frame(minWidth: 72)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(recording ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1))
    }
}

struct GeneralTab: View {
    @ObservedObject var s = Settings.shared
    @StateObject private var capture = HotkeyCapture()

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Hotkey")) {
                    HStack(spacing: 8) {
                        Button { toggleCapture() } label: {
                            KeycapChip(text: capture.capturing ? L("Press a key…") : s.hotkey.chipLabel, recording: capture.capturing)
                        }
                        .buttonStyle(.plain)
                        .help(L("Click to change. Esc cancels."))
                        Button { s.hotkey = .default } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless)
                            .help(L("Reset to default"))
                            .opacity(s.hotkey == .default || capture.capturing ? 0 : 1)
                            .disabled(s.hotkey == .default || capture.capturing)
                    }
                }
                if isPlainTypingKey {
                    Text(L("This key will no longer type its character while Speak2Text runs. Prefer F13, a modifier or a combination."))
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker(L("Mode"), selection: $s.mode) {
                    Text(L("Hold to talk")).tag("hold")
                    Text(L("Press to start/stop")).tag("toggle")
                }
                Picker(L("Language"), selection: $s.language) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                    Text(L("Auto-detect")).tag("auto")
                }
            } footer: {
                Text(s.mode == "hold" ? L("Hold the key while you speak, release it to insert the text.")
                                      : L("Press once to start, again to stop and insert the text. Esc cancels the recording."))
                    .footerStyle()
            }
            Section {
                Toggle(L("Mute other sounds while recording"), isOn: $s.muteEnabled)
                Toggle(L("Start and stop sounds"), isOn: $s.soundsEnabled)
                Toggle(L("Show overlay while recording"), isOn: $s.overlayEnabled)
                Toggle(L("Launch at login"), isOn: $s.launchAtLogin)
            }
            Section {
                HStack {
                    Spacer()
                    Button(L("Quit Speak2Text")) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopCapture() }
    }

    private func toggleCapture() {
        if capture.capturing { stopCapture(); return }
        AppDelegate.shared?.hotkey.suspended = true
        capture.start { spec in
            AppDelegate.shared?.hotkey.suspended = false
            if let spec { s.hotkey = spec }
        }
    }

    private func stopCapture() {
        if capture.capturing { capture.stop() }
        AppDelegate.shared?.hotkey.suspended = false
    }

    private var isPlainTypingKey: Bool {
        let h = s.hotkey
        guard !h.modifierOnly, h.mods == 0, let n = HotkeySpec.keyNames[h.keyCode] else { return false }
        return n.count == 1 || ["Space", "Return", "Tab", "Delete"].contains(n)
    }
}

// MARK: - Model

struct ModelTab: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var m = EngineManager.shared

    var body: some View {
        Form {
            Section {
                modelRow
                Picker(L("Accelerator"), selection: $s.accelerator) {
                    Text("Neural Engine").tag(Accelerator.ane)
                    Text("GPU").tag(Accelerator.gpu)
                    Text("CPU").tag(Accelerator.cpu)
                }
                statusLine
            } footer: {
                Text(L("Changing the accelerator recompiles CoreML: the first load can take up to about 3 minutes. Do not quit the app meanwhile."))
                    .footerStyle()
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var modelRow: some View {
        let id = ModelCatalog.modelID
        let have = ModelCatalog.folder(for: id) != nil
        HStack {
            VStack(alignment: .leading) {
                Text(ModelCatalog.title)
                Text("\(ModelCatalog.sizeMB) MB").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let p = m.downloads[id] {
                ProgressView(value: p).frame(width: 90)
                Text("\(Int(p * 100))%").monospacedDigit().font(.caption)
            } else if have {
                Label(L("Downloaded"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            } else {
                if let e = m.downloadErrors[id] { Text(e).font(.caption).foregroundStyle(.red).lineLimit(1) }
                Button(L("Download")) { m.download() }
            }
        }
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
}

// MARK: - Dictionary

/// Comma / newline separated list of terms; the text is kept locally so typing a trailing comma is not eaten.
struct TermsEditor: View {
    @Binding var terms: [String]
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
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
            Section {
                Text(L("Fix words the model gets wrong and cut filler words. Applied to every dictation before the text is inserted."))
                    .foregroundStyle(.secondary)
            }
            Section {
                if !s.replacements.isEmpty {
                    HStack(spacing: 8) {
                        Text(L("Heard")).frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 14)
                        Text(L("Write")).frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 18)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                ForEach($s.replacements) { $r in
                    HStack(spacing: 8) {
                        TextField("", text: $r.from).textFieldStyle(.roundedBorder).multilineTextAlignment(.leading).frame(maxWidth: .infinity)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).frame(width: 14)
                        TextField("", text: $r.to).textFieldStyle(.roundedBorder).multilineTextAlignment(.leading).frame(maxWidth: .infinity)
                        Button { s.replacements.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                    .labelsHidden()
                }
                Button { s.replacements.append(Replacement(from: "", to: "")) } label: { Label(L("Add"), systemImage: "plus") }
            } header: {
                Text(L("Replacements"))
            } footer: {
                Text(L("Applied to the final text, ignoring case, on whole words only."))
                    .footerStyle()
            }
            Section {
                Toggle(L("Remove filler words"), isOn: $s.fillersEnabled)
                if s.fillersEnabled {
                    TermsEditor(terms: $s.fillers).labelsHidden()
                }
            } header: {
                Text(L("Filler words"))
            } footer: {
                if s.fillersEnabled { Text(L("Separated by commas. Removed together with the commas around them.")).footerStyle() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - History

struct HistoryTab: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var h = HistoryStore.shared
    @ObservedObject var engine = EngineManager.shared
    @State private var query = ""
    @State private var confirmClear = false

    private var filtered: [HistoryItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return h.items }
        return h.items.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.raw.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search"), text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            .padding([.horizontal, .top], 16).padding(.bottom, 10)

            if filtered.isEmpty {
                Spacer()
                Text(h.items.isEmpty ? L("No dictations yet") : L("Nothing found")).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { it in HistoryRow(item: it, h: h, engineReady: engine.status == .ready) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }

            Divider()
            HStack {
                Toggle(L("Save history"), isOn: $s.historyEnabled)
                Spacer()
                Picker(L("Keep"), selection: $s.historyDays) {
                    Text(L("Forever")).tag(0)
                    Text(L("30 days")).tag(30)
                    Text(L("7 days")).tag(7)
                    Text(L("1 day")).tag(1)
                }
                .fixedSize()
                Button(L("Clear history")) { confirmClear = true }.disabled(h.items.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .alert(L("Clear the whole history?"), isPresented: $confirmClear) {
            Button(L("Clear"), role: .destructive) { h.clear() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("All saved texts and recordings will be deleted. This cannot be undone."))
        }
        .onChange(of: s.historyDays) { _, _ in h.prune() }
        .onDisappear { h.stopPlayback() }
    }
}

struct HistoryRow: View {
    let item: HistoryItem
    @ObservedObject var h: HistoryStore
    let engineReady: Bool

    private var durationText: String {
        let t = Int(item.duration.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(durationText).monospacedDigit()
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
            if item.text.isEmpty {
                Text(L("No text recognized")).italic().foregroundStyle(.secondary)
            } else {
                Text(item.text).lineLimit(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !item.raw.isEmpty && item.raw != item.text {
                Text(L("Raw: ") + item.raw).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 14) {
                action("doc.on.doc", L("Copy text"), enabled: !item.text.isEmpty) { h.copy(item) }
                action(h.playingID == item.id ? "stop.fill" : "play.fill", L("Play / stop audio"), enabled: item.hasAudio) { h.togglePlayback(item) }
                action("arrow.turn.down.left", L("Paste again"), enabled: !item.text.isEmpty) { h.pasteAgain(item) }
                if h.busy.contains(item.id) {
                    ProgressView().controlSize(.small).frame(width: 16)
                } else {
                    action("arrow.clockwise", L("Re-transcribe"), enabled: item.hasAudio && engineReady) { h.retranscribe(item) }
                }
                action("folder", L("Show in Finder"), enabled: true) { h.reveal(item) }
                Spacer()
                action("trash", L("Delete"), enabled: true) { h.remove(item) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

    private func action(_ symbol: String, _ help: String, enabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: symbol).frame(width: 16, height: 16) }
            .buttonStyle(.borderless)
            .help(help)
            .disabled(!enabled)
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Speak2Text").font(.title2.bold())
            Text(String(format: L("Version %@"), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"))
                .foregroundStyle(.secondary)
            Text(L("Local push-to-talk dictation. Nothing leaves your Mac.")).font(.callout)
            HStack {
                Button(L("Check for Updates…")) { AppDelegate.shared?.updater.checkForUpdates(nil) }
                Button(L("Open Log")) { AppDelegate.shared?.openLog() }
            }
            .padding(.top, 4)
            Link("github.com/vlad-anisov/Speak2Text", destination: URL(string: "https://github.com/vlad-anisov/Speak2Text")!)
            Spacer()
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Подпись секции: слева, вторичным цветом, мелким шрифтом.
    func footerStyle() -> some View {
        self.font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
