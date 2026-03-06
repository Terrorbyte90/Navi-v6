import Foundation

// MARK: - iCloud storage for memories
// Path: iCloud Drive/Navi/Memories/memories.json

@MainActor
final class iCloudMemoryStore {
    static let shared = iCloudMemoryStore()
    private init() {}

    private var fileURL: URL? {
        guard let base = iCloudSyncEngine.shared.containerURL else { return nil }
        let dir = base.appendingPathComponent("Memories", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("memories.json")
    }

    // MARK: - Load

    func loadAll() async throws -> [Memory] {
        guard let url = fileURL else { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { u in
                    blockRan = true
                    do {
                        let data = try Data(contentsOf: u)
                        let memories = try JSONDecoder().decode([Memory].self, from: data)
                        cont.resume(returning: memories)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan, let err = coordError { cont.resume(throwing: err) }
            }
        }
    }

    // MARK: - Save (full list)

    private func saveAll(_ memories: [Memory]) async throws {
        guard let url = fileURL else { return }
        let data = try JSONEncoder().encode(memories)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
                    blockRan = true
                    do {
                        try data.write(to: u, options: .atomic)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan, let err = coordError { cont.resume(throwing: err) }
            }
        }
    }

    // MARK: - CRUD

    func save(_ memory: Memory) async throws {
        var all = (try? await loadAll()) ?? []
        all.removeAll { $0.id == memory.id }
        all.append(memory)
        try await saveAll(all)
    }

    func delete(id: UUID) async throws {
        var all = (try? await loadAll()) ?? []
        all.removeAll { $0.id == id }
        try await saveAll(all)
    }

    func update(id: UUID, fact: String) async throws {
        var all = (try? await loadAll()) ?? []
        if let idx = all.firstIndex(where: { $0.id == id }) {
            all[idx].fact = fact
        }
        try await saveAll(all)
    }
}

// MARK: - iCloudSyncEngine containerURL exposure

extension iCloudSyncEngine {
    var containerURL: URL? {
        // Use the existing iCloud container root
        FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        )?.appendingPathComponent("Documents/Navi", isDirectory: true)
    }
}
