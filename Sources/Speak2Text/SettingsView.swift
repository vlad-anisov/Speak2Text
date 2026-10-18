import SwiftUI

/// Selected tab id; the window controller and the views share it (e.g. to open the Permissions tab).
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab: String = {
        let t = UserDefaults.standard.string(forKey: "settingsTab") ?? "general"
        return ["general", "history", "about"].contains(t) ? t : "general"
    }() {
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
    @ObservedObject var m = EngineManager.shared
    @StateObject private var perms = PermissionsModel()
    @StateObject private var capture = HotkeyCapture()

    var body: some View {
        Form {
            if !perms.allOK { permissionsSection }
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
                    Text(L("Hold")).tag("hold")
                    Text(L("Press")).tag("toggle")
                }
                Picker(L("Language"), selection: $s.language) {
                    Text(L("Same as system")).tag("system")
                    Text(L("Auto-detect")).tag("auto")
                    Divider()
                    ForEach(WhisperLanguages.all, id: \.code) { Text($0.name).tag($0.code) }
                }
            }
            Section {
                Toggle(L("Mute other sounds while recording"), isOn: $s.muteEnabled)
                HStack {
                    Text(L("Start and stop sounds"))
                    Spacer()
                    if s.soundsEnabled {
                        Picker(L("Sound"), selection: $s.soundVariant) {
                            ForEach(Sounds.variants, id: \.id) { Text(L($0.en)).tag($0.id) }
                        }
                        .labelsHidden().fixedSize()
                        .onChange(of: s.soundVariant) { _, v in Sounds.preview(v) }
                    }
                    Toggle(L("Start and stop sounds"), isOn: $s.soundsEnabled).labelsHidden()
                }
                Toggle(L("Show overlay while recording"), isOn: $s.overlayEnabled)
                Toggle(L("Remove filler words"), isOn: $s.fillersEnabled)
                Toggle(L("Launch at login"), isOn: $s.launchAtLogin)
            }
            Section {
                HStack(spacing: 8) {
                    Text(L("Accelerator"))
                    Spacer()
                    statusLine.font(.callout).foregroundStyle(.secondary)
                    Picker(L("Accelerator"), selection: $s.accelerator) {
                        Text("Neural Engine").tag(Accelerator.ane)
                        Text("GPU").tag(Accelerator.gpu)
                        Text("CPU").tag(Accelerator.cpu)
                    }
                    .labelsHidden().fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { perms.startPolling() }
        .onDisappear { stopCapture(); perms.stopPolling() }
    }

    // MARK: permissions (only while something is missing)

    private var permissionsSection: some View {
        Section {
            permRow(L("Microphone"), L("to record your voice"), perms.mic, perms.openMic)
            permRow(L("Input Monitoring"), L("to see the hotkey"), perms.input, perms.openInput)
            permRow(L("Accessibility"), L("to paste the text with Cmd+V"), perms.ax, perms.openAX)
            HStack {
                Text(L("Granted but still showing ✗? The app must be restarted.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Restart")) { Permissions.relaunch() }
            }
        } header: {
            Text(L("Permissions needed"))
        } footer: {
            Text(L("Speak2Text is not in the Input Monitoring list? Quit System Settings (⌘Q) and press the button again.") + " " + L("If the app is already in the list, remove it with the − button and add it again.")).footerStyle()
        }
    }

    private func permRow(_ title: String, _ why: String, _ ok: Bool, _ action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red).font(.title3)
            VStack(alignment: .leading) { Text(title); Text(why).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if !ok { Button(L("Open Settings")) { action() } }
        }
    }

    // MARK: engine status

    @ViewBuilder private var statusLine: some View {
        if let p = m.downloads[ModelCatalog.modelID] {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("\(L("Downloading")) \(Int(p * 100))%").monospacedDigit()
            }
        } else {
            switch m.status {
            case .preparing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let secs = Int(ctx.date.timeIntervalSince(m.preparingSince ?? ctx.date))
                        Text(String(format: "%@ %d:%02d", L("Preparing…"), secs / 60, secs % 60)).monospacedDigit()
                    }
                }
            case .ready: Text(L("Ready"))
            case .needsDownload:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("Downloading")) }
            case .failed(let e):
                HStack { Text(e).lineLimit(1).help(e); Button(L("Retry")) { m.reload() } }
            }
        }
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
            Text(String(format: L("Version %@"), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"))
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
