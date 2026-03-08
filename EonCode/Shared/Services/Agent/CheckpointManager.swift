import Foundation

@MainActor
final class CheckpointManager: ObservableObject {
    static let shared = CheckpointManager()

    private let fm = FileManager.default
    private var checkpointDir: URL? {
        iCloudSyncEngine.shared.naviRoot?.appendingPathComponent(Constants.iCloud.checkpointsFolder)
    }

    private init() {}

    // MARK: - Save checkpoint

    func save(taskID: UUID, step: Int, data: [String: Any] = [:]) {
        guard let dir = checkpointDir else { return }

        let checkpoint: [String: Any] = [
            "taskID": taskID.uuidString,
            "step": step,
            "timestamp": Date().iso8601,
            "data": data
        ]

        let url = dir.appendingPathComponent("\(taskID.uuidString)-step\(step).json")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let jsonData = try JSONSerialization.data(withJSONObject: checkpoint, options: .prettyPrinted)
            try jsonData.write(to: url)
        } catch {
            // Silently fail — checkpoints are best-effort
        }
    }

    // MARK: - Load latest checkpoint

    func latestStep(for taskID: UUID) -> Int {
        guard let dir = checkpointDir,
              let files = try? fm.contentsOfDirectory(atPath: dir.path)
        else { return 0 }

        let taskFiles = files
            .filter { $0.hasPrefix(taskID.uuidString) }
            .compactMap { filename -> Int? in
                let parts = filename.components(separatedBy: "-step")
                guard parts.count == 2,
                      let step = Int(parts[1].replacingOccurrences(of: ".json", with: ""))
                else { return nil }
                return step
            }

        return taskFiles.max() ?? 0
    }

    func loadCheckpoint(taskID: UUID, step: Int) -> [String: Any]? {
        guard let dir = checkpointDir else { return nil }
        let url = dir.appendingPathComponent("\(taskID.uuidString)-step\(step).json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    // MARK: - Clean up

    func clearCheckpoints(for taskID: UUID) {
        guard let dir = checkpointDir,
              let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        for file in files where file.lastPathComponent.hasPrefix(taskID.uuidString) {
            try? fm.removeItem(at: file)
        }
    }
}
