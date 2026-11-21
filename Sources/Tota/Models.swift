import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let data = home.appendingPathComponent("Music/tota")
    static let output = data.appendingPathComponent("output")
    static let samples = data.appendingPathComponent("samples")
    static let rawRecordings = samples.appendingPathComponent("raw")
    static let voicesFile = data.appendingPathComponent("voices.json")
    static let takesFile = data.appendingPathComponent("takes.json")
    static let presetsFile = data.appendingPathComponent("presets.json")
    static let python = home.appendingPathComponent(".local/share/uv/tools/mlx-audio/bin/python").path
    static var workerScript: String {
        Bundle.main.resourceURL?.appendingPathComponent("worker.py").path ?? ""
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }
}

/// Every setting the voice model takes. Defaults are the ones picked in testing:
/// icl mode at temperature 0.4.
struct GenSettings: Codable, Equatable {
    var conditioning = "icl"
    var temperature = 0.4
    var depthTemperature = 0.5
    var topK = 64
    var topP = 1.0
    var depthTopK = 64
    var presencePenalty = 0.8
    var presenceWindow = 12
    var splitText = true
    var maxChars = 150
    var gap = 0.2
    var useSeed = false
    var seed = 1

    static let defaults = GenSettings()

    var modeLabel: String {
        switch conditioning {
        case "icl_spk": return "icl + spk"
        default: return conditioning
        }
    }

    /// Short description for a take: the main settings, then anything else changed from default.
    func summary(seed: Int) -> String {
        let d = GenSettings.defaults
        var parts = [modeLabel, "temp \(fmt(temperature))", "detail \(fmt(depthTemperature))"]
        if topK != d.topK { parts.append("top K \(topK)") }
        if topP != d.topP { parts.append("top P \(fmt(topP))") }
        if depthTopK != d.depthTopK { parts.append("detail top K \(depthTopK)") }
        if presencePenalty != d.presencePenalty { parts.append("repeat penalty \(String(format: "%.1f", presencePenalty))") }
        if presenceWindow != d.presenceWindow { parts.append("window \(presenceWindow)") }
        if !splitText { parts.append("no chunks") } else if maxChars != d.maxChars { parts.append("chunk \(maxChars)") }
        if splitText && gap != d.gap { parts.append("gap \(String(format: "%.2f", gap)) s") }
        parts.append("seed \(seed)")
        return parts.joined(separator: " · ")
    }

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}

struct Voice: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var audioPath: String
    var transcript: String
    var duration: Double
    var url: URL { URL(fileURLWithPath: audioPath) }
}

struct Take: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var text: String
    var voiceID: UUID
    var voiceName: String
    var settings: GenSettings
    var seed: Int
    var path: String
    var duration: Double
    var elapsed: Double
    var retries: Int
    var starred = false
    var url: URL { URL(fileURLWithPath: path) }
}

struct Preset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var settings: GenSettings
}

func formatSeconds(_ s: Double) -> String {
    String(format: "%.1f s", s)
}
