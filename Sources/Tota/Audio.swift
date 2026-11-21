import AVFoundation
import Foundation

/// Plays one file, part of a file, or several files in a row (sample, then take).
@MainActor
final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    struct Item {
        var url: URL
        var start: Double = 0
        var end: Double? = nil
    }

    @Published private(set) var playingID: String?
    private var player: AVAudioPlayer?
    private var queue: [Item] = []
    private var timer: Timer?

    func toggle(_ id: String, _ items: [Item]) {
        if playingID == id { stop(); return }
        play(id, items)
    }

    func play(_ id: String, _ items: [Item]) {
        stop()
        playingID = id
        queue = items
        playNext()
    }

    func stop() {
        queue = []
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        playingID = nil
    }

    private func playNext() {
        timer?.invalidate()
        timer = nil
        guard !queue.isEmpty else { player = nil; playingID = nil; return }
        let item = queue.removeFirst()
        guard let p = try? AVAudioPlayer(contentsOf: item.url) else { playNext(); return }
        p.delegate = self
        p.currentTime = item.start
        player = p
        p.play()
        if let end = item.end {
            timer = Timer.scheduledTimer(withTimeInterval: max(0, end - item.start), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.player?.stop()
                    self?.advance()
                }
            }
        }
    }

    private func advance() {
        timer?.invalidate()
        timer = nil
        if queue.isEmpty { playNext(); return }
        // Short pause between the sample and the take so they're easy to tell apart.
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.playNext() }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard p === self.player else { return }
                self.advance()
            }
        }
    }
}

/// Records the microphone to a 24 kHz mono WAV, the format the voice model uses.
@MainActor
final class Recorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var level: Double = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        guard r.record() else {
            throw WorkerError(message: "Recording didn't start. Check that a microphone is connected.")
        }
        recorder = r
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    @discardableResult
    func stop() -> Double {
        let d = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        level = 0
        return d
    }

    private func tick() {
        guard let r = recorder else { return }
        r.updateMeters()
        elapsed = r.currentTime
        let db = Double(r.averagePower(forChannel: 0))
        level = max(0, min(1, (db + 50) / 50))
    }
}

func audioDuration(_ url: URL) -> Double {
    (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
}
