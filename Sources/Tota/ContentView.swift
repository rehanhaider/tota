import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = true
    @State private var showNewVoice = false
    @State private var showSavePreset = false
    @State private var presetName = ""

    var body: some View {
        NavigationSplitView {
            Sidebar(showNewVoice: $showNewVoice, showSavePreset: $showSavePreset)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            DetailView()
        }
        .inspector(isPresented: $showSettings) {
            SettingsPanel()
                .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
        .toolbar {
            ToolbarItem {
                Button { showSettings.toggle() } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .help("Show or hide the settings panel")
            }
        }
        .sheet(isPresented: $showNewVoice) { NewVoiceSheet() }
        .alert("Save settings as a preset", isPresented: $showSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") { model.savePreset(named: presetName); presetName = "" }
            Button("Cancel", role: .cancel) { presetName = "" }
        } message: {
            Text("A preset with the same name is replaced.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: Player
    @Binding var showNewVoice: Bool
    @Binding var showSavePreset: Bool

    var body: some View {
        List(selection: $model.selectedVoiceID) {
            Section("Voices") {
                ForEach(model.voices) { v in
                    HStack {
                        Label(v.name, systemImage: "person.wave.2")
                        Spacer()
                        Text(formatSeconds(v.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(v.id as UUID?)
                    .contextMenu {
                        Button("Play Sample") { player.toggle("voice-\(v.id)", [.init(url: v.url)]) }
                        Button("Show in Finder") { model.reveal(v.url) }
                        Divider()
                        Button("Remove from List") { model.removeVoice(v) }
                    }
                }
                Button { showNewVoice = true } label: {
                    Label("New Voice…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            Section("Presets") {
                ForEach(model.presets) { p in
                    Button { model.apply(p) } label: {
                        HStack {
                            Label(p.name, systemImage: "slider.horizontal.below.rectangle")
                            Spacer()
                            if p.settings == model.settings {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(p.settings.summary(seed: p.settings.seed))
                    .contextMenu {
                        Button("Delete Preset") { model.deletePreset(p) }
                    }
                }
                Button { showSavePreset = true } label: {
                    Label("Save Current Settings…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Main area

struct DetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let v = model.selectedVoice {
                VoiceHeader(voice: v)
            } else {
                Text("No voice yet. Click New Voice… in the sidebar to record one.")
                    .foregroundStyle(.secondary)
            }
            ScriptEditor()
            GenerateBar()
            Divider()
            TakesList()
        }
        .padding(16)
        .navigationTitle(model.selectedVoice?.name ?? "Tota")
    }
}

struct VoiceHeader: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: Player
    let voice: Voice
    @State private var transcript = ""
    @State private var showTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                let id = "voice-\(voice.id)"
                Button {
                    player.toggle(id, [.init(url: voice.url)])
                } label: {
                    Label(player.playingID == id ? "Stop" : "Play Sample",
                          systemImage: player.playingID == id ? "stop.fill" : "play.fill")
                }
                Text("\(formatSeconds(voice.duration)) sample")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(showTranscript ? "Hide Sample's Words" : "Sample's Words") { showTranscript.toggle() }
                    .buttonStyle(.link)
            }
            if showTranscript {
                TextEditor(text: $transcript)
                    .font(.callout)
                    .frame(height: 54)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: transcript) { _, t in model.updateTranscript(t, for: voice.id) }
                Text("These must be exactly the words spoken in the sample. Fix any mistakes here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { transcript = voice.transcript }
        .onChange(of: voice.id) { _, _ in transcript = voice.transcript }
    }
}

struct ScriptEditor: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Text to speak").font(.headline)
                Spacer()
                Button("Use Sample's Words") {
                    if let v = model.selectedVoice { model.text = v.transcript }
                }
                .help("Fill in the words from your sample, so you can compare the take with your own recording")
                .disabled(model.selectedVoice == nil)
                Button("Open Text File…") { model.openTextFile() }
                Button("Clear") { model.text = "" }
                    .disabled(model.text.isEmpty)
            }
            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Type or paste text, or open a text file.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 110, idealHeight: 150, maxHeight: 220)
            let chars = model.text.trimmingCharacters(in: .whitespacesAndNewlines).count
            Text("\(chars) characters, about \(formatSeconds(Double(chars) * 0.075)) of speech")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct GenerateBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var worker: Worker

    var body: some View {
        HStack(spacing: 12) {
            if model.isGenerating {
                Button(role: .destructive) { model.stopGenerating() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
                ProgressView().controlSize(.small)
                if let p = model.progress {
                    Text("Chunk \(p.chunk) of \(p.total)")
                        .monospacedDigit()
                } else {
                    Text(worker.status == .loading ? "Loading the voice model…" : "Starting…")
                }
            } else {
                Button { model.generate() } label: {
                    Label("Generate", systemImage: "waveform")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedVoice == nil)
                Text("⌘↩").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Play when done", isOn: $model.playWhenDone)
                .toggleStyle(.checkbox)
            StatusLabel()
        }
    }
}

struct StatusLabel: View {
    @EnvironmentObject var worker: Worker

    var body: some View {
        switch worker.status {
        case .ready:
            Label("Model ready", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .loading:
            Label("Loading model", systemImage: "circle.dotted")
                .foregroundStyle(.orange)
                .font(.caption)
        case .stopped:
            Button("Start Model") { worker.start() }
                .font(.caption)
        case .failed(let msg):
            HStack(spacing: 6) {
                Label("Model stopped", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .help(msg)
                Button("Restart") { worker.restart() }
                    .font(.caption)
            }
        }
    }
}

// MARK: - Takes

struct TakesList: View {
    @EnvironmentObject var model: AppModel
    @State private var starredOnly = false

    var shown: [Take] { starredOnly ? model.takes.filter(\.starred) : model.takes }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Takes").font(.headline)
                Text("\(model.takes.count)").foregroundStyle(.secondary)
                Spacer()
                Toggle("Starred only", isOn: $starredOnly).toggleStyle(.checkbox)
            }
            if shown.isEmpty {
                Text(starredOnly ? "No starred takes." : "Takes you generate appear here, with the settings each one used.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(shown) { take in
                    TakeRow(take: take)
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds()
            }
        }
    }
}

struct TakeRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: Player
    let take: Take

    var voice: Voice? { model.voices.first { $0.id == take.voiceID } }

    var body: some View {
        let playID = take.id.uuidString
        let compareID = "\(take.id.uuidString)-compare"
        HStack(alignment: .top, spacing: 10) {
            Button {
                player.toggle(playID, [.init(url: take.url)])
            } label: {
                Image(systemName: player.playingID == playID ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.borderless)
            .help("Play this take")

            Button {
                if let v = voice { player.toggle(compareID, [.init(url: v.url), .init(url: take.url)]) }
            } label: {
                Image(systemName: player.playingID == compareID ? "stop.circle" : "person.line.dotted.person")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(voice == nil)
            .help("Play your sample, then this take")

            VStack(alignment: .leading, spacing: 3) {
                Text(take.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(take.settings.summary(seed: take.seed))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("\(take.voiceName) · \(formatSeconds(take.duration)) · made in \(formatSeconds(take.elapsed))\(take.retries > 0 ? " · \(take.retries) chunk retries" : "") · \(take.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button { model.toggleStar(take) } label: {
                Image(systemName: take.starred ? "star.fill" : "star")
                    .foregroundStyle(take.starred ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(take.starred ? "Unstar" : "Star this take")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Use These Settings") { model.useSettings(of: take) }
            Button("Put Text Back in Editor") { model.text = take.text }
            Divider()
            Button("Show in Finder") { model.reveal(take.url) }
            Button("Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(take.path, forType: .string)
            }
            Divider()
            Button("Move to Trash") { model.trash(take) }
        }
    }
}
