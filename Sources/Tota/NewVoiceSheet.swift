import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Record or import audio, pick the part to use, transcribe it, and save it as a voice.
struct NewVoiceSheet: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: Player
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = Recorder()

    @State private var sourceURL: URL?
    @State private var sourceDuration = 0.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var name = ""
    @State private var transcript = ""
    @State private var trimmedURL: URL?
    @State private var transcribedRange: ClosedRange<Double>?
    @State private var working = false
    @State private var error: String?

    private var selection: Double { max(0, end - start) }
    private var isStale: Bool { transcribedRange != start...end }
    private var canSave: Bool {
        trimmedURL != nil && !isStale && !working
            && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Voice").font(.title2.bold())
            Text("Talk the way you normally do for 30 to 60 seconds, about anything, without reading. Then pick the best 5 to 15 seconds as the sample. Maya's makers recommend 3 to 10 seconds.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sourceRow

            if sourceURL != nil && sourceDuration > 0 && !recorder.isRecording {
                selectionBox
                transcriptBox
                TextField("Voice name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    recorder.stop()
                    player.stop()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save Voice") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    // MARK: - Recording or importing

    private var sourceRow: some View {
        HStack(spacing: 12) {
            if recorder.isRecording {
                Button(role: .destructive) { stopRecording() } label: {
                    Label("Stop Recording", systemImage: "stop.fill")
                }
                .controlSize(.large)
                Text(formatSeconds(recorder.elapsed)).monospacedDigit()
                ProgressView(value: recorder.level)
                    .frame(width: 160)
                    .tint(recorder.level > 0.9 ? .red : .green)
            } else {
                Button { Task { await startRecording() } } label: {
                    Label(sourceURL == nil ? "Record" : "Record Again", systemImage: "mic.fill")
                }
                .controlSize(.large)
                Button("Choose Audio File…") { importFile() }
                if let sourceURL {
                    Text("\(sourceURL.lastPathComponent), \(formatSeconds(sourceDuration))")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func startRecording() async {
        error = nil
        player.stop()
        guard await recorder.requestPermission() else {
            error = "Tota can't use the microphone. Allow it in System Settings > Privacy & Security > Microphone."
            return
        }
        let url = Paths.rawRecordings.appendingPathComponent("recording_\(Paths.timestamp()).wav")
        do {
            try recorder.start(to: url)
            sourceURL = url
            sourceDuration = 0
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stopRecording() {
        recorder.stop()
        guard let url = sourceURL else { return }
        loadSource(url)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        // Copy it into the tota folder so the helper never needs access elsewhere.
        let dest = Paths.rawRecordings.appendingPathComponent("import_\(Paths.timestamp())_\(picked.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: picked, to: dest)
            loadSource(dest)
        } catch {
            self.error = "Couldn't copy \(picked.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func loadSource(_ url: URL) {
        let d = audioDuration(url)
        guard d >= 1 else {
            error = "That recording is shorter than 1 second."
            sourceURL = nil
            return
        }
        error = nil
        sourceURL = url
        sourceDuration = d
        start = 0
        end = min(d, 12)
        transcript = ""
        trimmedURL = nil
        transcribedRange = nil
    }

    // MARK: - Picking the part to use

    private var selectionBox: some View {
        GroupBox("Part to use") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Start").frame(width: 40, alignment: .leading)
                    Slider(value: $start, in: 0...sourceDuration)
                    Text(formatSeconds(start)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text("End").frame(width: 40, alignment: .leading)
                    Slider(value: $end, in: 0...sourceDuration)
                    Text(formatSeconds(end)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text("Selected: \(formatSeconds(selection))").monospacedDigit()
                    if selection < 3 {
                        Text("Shorter than 3 seconds").foregroundStyle(.orange)
                    } else if selection > 20 {
                        Text("Longer than 20 seconds is slower and may not help").foregroundStyle(.orange)
                    }
                    Spacer()
                    let id = "selection"
                    Button {
                        player.toggle(id, [.init(url: sourceURL!, start: start, end: end)])
                    } label: {
                        Label(player.playingID == id ? "Stop" : "Play Selection",
                              systemImage: player.playingID == id ? "stop.fill" : "play.fill")
                    }
                    Button("Whole Recording") { start = 0; end = sourceDuration }
                }
            }
            .padding(4)
        }
        .onChange(of: start) { _, s in if s > end - 1 { end = min(sourceDuration, s + 1) } }
        .onChange(of: end) { _, e in if e < start + 1 { start = max(0, e - 1) } }
    }

    // MARK: - Transcript

    private var transcriptBox: some View {
        GroupBox("Words in the selection") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(transcribedRange == nil ? "Transcribe Selection" : "Transcribe Again") {
                        Task { await transcribe() }
                    }
                    .disabled(working || selection < 1)
                    if working {
                        ProgressView().controlSize(.small)
                        Text("Transcribing with Whisper…").foregroundStyle(.secondary)
                    } else if transcribedRange != nil && isStale {
                        Text("You changed the selection. Transcribe it again.").foregroundStyle(.orange)
                    }
                }
                TextEditor(text: $transcript)
                    .frame(height: 70)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Text("Fix any words Whisper got wrong. The text must match exactly what you say in the selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private func transcribe() async {
        guard let src = sourceURL else { return }
        working = true
        error = nil
        defer { working = false }
        let range = start...end
        let out = Paths.samples.appendingPathComponent("voice_\(Paths.timestamp()).wav")
        do {
            let t = try await model.worker.request("trim", [
                "audio": src.path, "start": range.lowerBound, "end": range.upperBound, "out": out.path,
            ])
            let path = t["path"] as? String ?? out.path
            let r = try await model.worker.request("transcribe", ["audio": path, "language": "en"])
            if let old = trimmedURL, old.path != path { try? FileManager.default.removeItem(at: old) }
            trimmedURL = URL(fileURLWithPath: path)
            transcript = r["text"] as? String ?? ""
            transcribedRange = range
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        guard let url = trimmedURL else { return }
        player.stop()
        model.addVoice(Voice(name: name.trimmingCharacters(in: .whitespaces), audioPath: url.path,
                             transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                             duration: selection))
        dismiss()
    }
}
