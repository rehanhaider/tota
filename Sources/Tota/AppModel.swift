import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var voices: [Voice] = [] { didSet { save(voices, to: Paths.voicesFile) } }
    @Published var takes: [Take] = [] { didSet { save(takes, to: Paths.takesFile) } }
    @Published var presets: [Preset] = [] { didSet { save(presets, to: Paths.presetsFile) } }
    @Published var selectedVoiceID: UUID? {
        didSet { UserDefaults.standard.set(selectedVoiceID?.uuidString, forKey: "selectedVoice") }
    }
    @Published var settings: GenSettings {
        didSet {
            if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: "settings") }
        }
    }
    @Published var text: String { didSet { UserDefaults.standard.set(text, forKey: "draft") } }
    @Published var playWhenDone: Bool { didSet { UserDefaults.standard.set(playWhenDone, forKey: "playWhenDone") } }
    @Published var isGenerating = false
    @Published var progress: (chunk: Int, total: Int)?
    @Published var errorMessage: String?

    let worker = Worker()
    let player = Player()

    init() {
        let fm = FileManager.default
        for dir in [Paths.data, Paths.output, Paths.samples, Paths.rawRecordings] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let defaults = UserDefaults.standard
        if let d = defaults.data(forKey: "settings"), let s = try? JSONDecoder().decode(GenSettings.self, from: d) {
            settings = s
        } else {
            settings = GenSettings()
        }
        text = defaults.string(forKey: "draft") ?? ""
        playWhenDone = defaults.object(forKey: "playWhenDone") as? Bool ?? true

        voices = Self.load([Voice].self, from: Paths.voicesFile) ?? []
        if voices.isEmpty {
            // First run: start with the sample saved earlier in ~/Music/tota.
            let wav = Paths.data.appendingPathComponent("my_voice_natural.wav")
            let txt = Paths.data.appendingPathComponent("my_voice_natural.txt")
            if fm.fileExists(atPath: wav.path), let t = try? String(contentsOf: txt, encoding: .utf8) {
                voices = [Voice(name: "My voice (natural)", audioPath: wav.path,
                                transcript: t.trimmingCharacters(in: .whitespacesAndNewlines),
                                duration: audioDuration(wav))]
                save(voices, to: Paths.voicesFile)
            }
        }
        takes = Self.load([Take].self, from: Paths.takesFile) ?? []
        presets = Self.load([Preset].self, from: Paths.presetsFile) ?? []
        if presets.isEmpty {
            presets = [Preset(name: "My pick (icl, 0.4)", settings: GenSettings())]
            save(presets, to: Paths.presetsFile)
        }
        let saved = defaults.string(forKey: "selectedVoice").flatMap(UUID.init(uuidString:))
        selectedVoiceID = voices.contains { $0.id == saved } ? saved : voices.first?.id

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.worker.stop() }
        }
    }

    var selectedVoice: Voice? { voices.first { $0.id == selectedVoiceID } }

    // MARK: - Generating

    func generate() {
        guard !isGenerating else { return }
        guard let voice = selectedVoice else { errorMessage = "Pick or record a voice first."; return }
        let script = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { errorMessage = "Type some text or open a text file first."; return }
        let s = settings
        let seed = s.useSeed ? s.seed : Int.random(in: 1...999_999)
        let out = Paths.output.appendingPathComponent("\(Paths.timestamp()).wav")
        let params: [String: Any] = [
            "text": script,
            "ref_audio": voice.audioPath,
            "ref_text": voice.transcript,
            "conditioning": s.conditioning,
            "temperature": s.temperature,
            "depth_temperature": s.depthTemperature,
            "top_k": s.topK,
            "top_p": s.topP,
            "depth_top_k": s.depthTopK,
            "presence_penalty": s.presencePenalty,
            "presence_window": s.presenceWindow,
            "max_chars": s.splitText ? s.maxChars : 0,
            "gap": s.gap,
            "seed": seed,
            "out": out.path,
        ]
        isGenerating = true
        progress = nil
        player.stop()
        Task {
            defer { isGenerating = false; progress = nil }
            do {
                let r = try await worker.request("generate", params) { [weak self] c, t in
                    self?.progress = (c, t)
                }
                let take = Take(date: Date(), text: script, voiceID: voice.id, voiceName: voice.name,
                                settings: s, seed: seed, path: r["path"] as? String ?? out.path,
                                duration: r["duration"] as? Double ?? 0, elapsed: r["elapsed"] as? Double ?? 0,
                                retries: r["retries"] as? Int ?? 0)
                takes.insert(take, at: 0)
                if playWhenDone { player.play(take.id.uuidString, [.init(url: take.url)]) }
            } catch {
                if (error as? WorkerError)?.message != WorkerError.stoppedMessage {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func stopGenerating() {
        worker.restart()
    }

    // MARK: - Takes

    func useSettings(of take: Take) {
        var s = take.settings
        s.useSeed = true
        s.seed = take.seed
        settings = s
        if voices.contains(where: { $0.id == take.voiceID }) { selectedVoiceID = take.voiceID }
    }

    func toggleStar(_ take: Take) {
        guard let i = takes.firstIndex(where: { $0.id == take.id }) else { return }
        takes[i].starred.toggle()
    }

    func trash(_ take: Take) {
        if player.playingID?.hasPrefix(take.id.uuidString) == true { player.stop() }
        try? FileManager.default.trashItem(at: take.url, resultingItemURL: nil)
        takes.removeAll { $0.id == take.id }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Voices

    func addVoice(_ v: Voice) {
        voices.append(v)
        selectedVoiceID = v.id
    }

    func removeVoice(_ v: Voice) {
        voices.removeAll { $0.id == v.id }
        if selectedVoiceID == v.id { selectedVoiceID = voices.first?.id }
    }

    func updateTranscript(_ text: String, for id: UUID) {
        guard let i = voices.firstIndex(where: { $0.id == id }), voices[i].transcript != text else { return }
        voices[i].transcript = text
    }

    func renameVoice(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = voices.firstIndex(where: { $0.id == id }) else { return }
        voices[i].name = n
    }

    // MARK: - Presets

    func savePreset(named name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let i = presets.firstIndex(where: { $0.name == n }) {
            presets[i].settings = settings
        } else {
            presets.append(Preset(name: n, settings: settings))
        }
    }

    func apply(_ p: Preset) { settings = p.settings }

    func deletePreset(_ p: Preset) { presets.removeAll { $0.id == p.id } }

    // MARK: - Text

    func openTextFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            errorMessage = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Storage

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        do {
            try enc.encode(value).write(to: url, options: .atomic)
        } catch {
            errorMessage = "Couldn't save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: d)
    }
}
