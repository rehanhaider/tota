import Foundation

struct WorkerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static let stoppedMessage = "Stopped."
}

/// Runs backend/worker.py with mlx-audio's Python and keeps it running so the model
/// stays loaded. Requests and replies are one JSON object per line.
@MainActor
final class Worker: ObservableObject {
    enum Status: Equatable {
        case stopped, loading, ready
        case failed(String)
    }

    @Published private(set) var status: Status = .stopped

    private struct Pending {
        let progress: ((Int, Int) -> Void)?
        let continuation: CheckedContinuation<[String: Any], Error>
    }

    private var process: Process?
    private var input: FileHandle?
    private var outBuffer = Data()
    private var errLines: [String] = []
    private var pending: [String: Pending] = [:]

    func start() {
        guard process == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: Paths.python) else {
            status = .failed("mlx-audio's Python isn't at \(Paths.python).")
            return
        }
        guard FileManager.default.fileExists(atPath: Paths.workerScript) else {
            status = .failed("worker.py is missing from the app. Rebuild it with build.sh.")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.python)
        p.arguments = ["-I", Paths.workerScript]
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        // Apps opened from Finder get a minimal PATH; mlx-audio uses ffmpeg from Homebrew.
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        p.currentDirectoryURL = Paths.data

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self, weak p] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let p, p === self.process else { return }
                    self.receive(d)
                }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receiveErr(d) }
            }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.terminated(proc) }
            }
        }

        do {
            try p.run()
        } catch {
            status = .failed("Couldn't start the voice helper: \(error.localizedDescription)")
            return
        }
        process = p
        input = inPipe.fileHandleForWriting
        errLines = []
        status = .loading
    }

    func stop() {
        guard let p = process else { return }
        process = nil
        input = nil
        outBuffer = Data()
        failAll(WorkerError.stoppedMessage)
        p.terminate()
        status = .stopped
    }

    func restart() {
        stop()
        start()
    }

    func request(_ cmd: String, _ params: [String: Any],
                 progress: ((Int, Int) -> Void)? = nil) async throws -> [String: Any] {
        if process == nil { start() }
        guard let input else {
            if case .failed(let m) = status { throw WorkerError(message: m) }
            throw WorkerError(message: "The voice helper isn't running.")
        }
        let id = UUID().uuidString
        var msg = params
        msg["id"] = id
        msg["cmd"] = cmd
        var data = try JSONSerialization.data(withJSONObject: msg)
        data.append(0x0A)
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = Pending(progress: progress, continuation: cont)
            do {
                try input.write(contentsOf: data)
            } catch {
                pending[id] = nil
                cont.resume(throwing: WorkerError(message: "Couldn't reach the voice helper: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Replies

    private func receive(_ data: Data) {
        outBuffer.append(data)
        while let nl = outBuffer.firstIndex(of: 0x0A) {
            let line = Data(outBuffer[outBuffer.startIndex..<nl])
            outBuffer.removeSubrange(outBuffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(obj)
        }
    }

    private func handle(_ obj: [String: Any]) {
        let type = obj["type"] as? String
        if type == "status" {
            switch obj["status"] as? String {
            case "loading": status = .loading
            case "ready": status = .ready
            default: status = .failed(obj["message"] as? String ?? "The voice model failed to load.")
            }
            return
        }
        guard let id = obj["id"] as? String, let p = pending[id] else { return }
        switch type {
        case "progress":
            p.progress?(obj["chunk"] as? Int ?? 0, obj["total"] as? Int ?? 0)
        case "result":
            pending[id] = nil
            p.continuation.resume(returning: obj)
        default:
            pending[id] = nil
            p.continuation.resume(throwing: WorkerError(message: obj["message"] as? String ?? "Unknown error."))
        }
    }

    private func receiveErr(_ data: Data) {
        guard let s = String(data: data, encoding: .utf8) else { return }
        errLines.append(contentsOf: s.split(separator: "\n").map(String.init))
        if errLines.count > 200 { errLines.removeFirst(errLines.count - 200) }
    }

    private func terminated(_ proc: Process) {
        guard proc === process else { return }
        process = nil
        input = nil
        outBuffer = Data()
        let tail = errLines.filter { !$0.contains("Warning") }.suffix(6).joined(separator: "\n")
        let msg = "The voice helper quit (code \(proc.terminationStatus)).\n\(tail)"
        failAll(msg)
        status = .failed(msg)
    }

    private func failAll(_ message: String) {
        let all = pending
        pending = [:]
        for (_, p) in all { p.continuation.resume(throwing: WorkerError(message: message)) }
    }
}
