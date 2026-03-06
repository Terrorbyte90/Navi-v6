import Foundation

// MARK: - iCloud storage for pure chat conversations
// Path: iCloud Drive/Navi/Chats/{conversation-id}.json

@MainActor
final class iCloudChatStore: ObservableObject {
    static let shared = iCloudChatStore()

    private var containerURL: URL? {
        iCloudSyncEngine.shared.chatsDirectory
    }

    private init() {}

    // MARK: - Save

    func save(_ conversation: ChatConversation) async throws {
        guard let dir = containerURL else { throw ChatStoreError.iCloudUnavailable }

        let fileURL = dir.appendingPathComponent("\(conversation.id.uuidString).json")
        let data = try JSONEncoder().encode(conversation)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordError) { url in
                    blockRan = true
                    do {
                        try data.write(to: url, options: .atomic)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan, let err = coordError { cont.resume(throwing: err) }
            }
        }
    }

    // MARK: - Load one

    func load(id: UUID) async throws -> ChatConversation {
        guard let dir = containerURL else { throw ChatStoreError.iCloudUnavailable }
        let fileURL = dir.appendingPathComponent("\(id.uuidString).json")

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordError) { url in
                    blockRan = true
                    do {
                        let data = try Data(contentsOf: url)
                        let conv = try JSONDecoder().decode(ChatConversation.self, from: data)
                        cont.resume(returning: conv)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan, let err = coordError { cont.resume(throwing: err) }
            }
        }
    }

    // MARK: - Load all

    func loadAll() async throws -> [ChatConversation] {
        guard let dir = containerURL else { return [] }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil
                ) else {
                    cont.resume(returning: [])
                    return
                }

                let jsonFiles = files.filter { $0.pathExtension == "json" }
                var conversations: [ChatConversation] = []
                let coordinator = NSFileCoordinator()

                for fileURL in jsonFiles {
                    var coordError: NSError?
                    coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordError) { url in
                        if let data = try? Data(contentsOf: url),
                           let conv = try? JSONDecoder().decode(ChatConversation.self, from: data) {
                            conversations.append(conv)
                        }
                    }
                }

                cont.resume(returning: conversations.sorted { $0.updatedAt > $1.updatedAt })
            }
        }
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        guard let dir = containerURL else { return }
        let fileURL = dir.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Search

    func search(query: String) async -> [ChatConversation] {
        guard let all = try? await loadAll() else { return [] }
        let q = query.lowercased()
        return all.filter { conv in
            conv.title.lowercased().contains(q) ||
            conv.messages.contains { $0.content.lowercased().contains(q) }
        }
    }
}

// MARK: - iCloudSyncEngine extension for chats directory

extension iCloudSyncEngine {
    var chatsDirectory: URL? {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("Chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum ChatStoreError: LocalizedError {
    case iCloudUnavailable
    var errorDescription: String? { "iCloud är inte tillgängligt" }
}
