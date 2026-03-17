import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Models

struct GitHubRepo: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let defaultBranch: String
    let htmlURL: String
    let cloneURL: String
    let sshURL: String
    let language: String?
    let stargazersCount: Int
    let updatedAt: Date
    var currentBranch: String  // mutable — user can change

    enum CodingKeys: String, CodingKey {
        case id, name, description, language
        case fullName = "full_name"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case sshURL = "ssh_url"
        case stargazersCount = "stargazers_count"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fullName = try c.decode(String.self, forKey: .fullName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        isPrivate = try c.decode(Bool.self, forKey: .isPrivate)
        defaultBranch = try c.decode(String.self, forKey: .defaultBranch)
        htmlURL = try c.decode(String.self, forKey: .htmlURL)
        cloneURL = try c.decode(String.self, forKey: .cloneURL)
        sshURL = try c.decode(String.self, forKey: .sshURL)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        stargazersCount = try c.decode(Int.self, forKey: .stargazersCount)
        let dateStr = try c.decode(String.self, forKey: .updatedAt)
        updatedAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
        currentBranch = defaultBranch
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(fullName, forKey: .fullName)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(isPrivate, forKey: .isPrivate)
        try c.encode(defaultBranch, forKey: .defaultBranch)
        try c.encode(htmlURL, forKey: .htmlURL)
        try c.encode(cloneURL, forKey: .cloneURL)
        try c.encode(sshURL, forKey: .sshURL)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encode(stargazersCount, forKey: .stargazersCount)
        try c.encode(ISO8601DateFormatter().string(from: updatedAt), forKey: .updatedAt)
    }
}

struct GitHubBranch: Identifiable, Codable {
    var id: String { name }
    let name: String
    let protected: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case protected
    }
}

struct GitHubUser: Codable {
    let login: String
    let name: String?
    let avatarURL: String
    let publicRepos: Int
    let totalPrivateRepos: Int?

    enum CodingKeys: String, CodingKey {
        case login, name
        case avatarURL = "avatar_url"
        case publicRepos = "public_repos"
        case totalPrivateRepos = "total_private_repos"
    }
}

struct GitHubCommit: Identifiable, Codable {
    var id: String { sha }
    let sha: String
    let commit: CommitDetail
    let htmlURL: String

    struct CommitDetail: Codable {
        let message: String
        let author: CommitAuthor
    }
    struct CommitAuthor: Codable {
        let name: String
        let date: String
    }

    enum CodingKeys: String, CodingKey {
        case sha, commit
        case htmlURL = "html_url"
    }
}

struct GitHubPullRequest: Identifiable, Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String          // "open", "closed"
    let htmlURL: String
    let createdAt: String
    let updatedAt: String
    let user: PRUser
    let head: PRRef
    let base: PRRef
    let merged: Bool?
    let draft: Bool?

    struct PRUser: Codable {
        let login: String
        let avatarURL: String?
        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }
    struct PRRef: Codable {
        let ref: String
        let label: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user, head, base, merged, draft
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum GitHubAuthState {
    case notAuthorized
    case authorized(user: GitHubUser)
    case loading
    case error(String)
}

// MARK: - GitHubManager

@MainActor
final class GitHubManager: ObservableObject {
    static let shared = GitHubManager()

    @Published var authState: GitHubAuthState = .notAuthorized
    @Published var repos: [GitHubRepo] = []
    @Published var isLoadingRepos = false
    @Published var repoError: String?
    @Published var branchCache: [String: [GitHubBranch]] = [:]  // fullName → branches
    @Published var commitCache: [String: [GitHubCommit]] = [:]  // "fullName/branch" → commits
    @Published var clonedRepos: [String: String] = [:]          // fullName → localPath
    @Published var syncStatus: [String: String] = [:]           // fullName → status message
    @Published var prCache: [String: [GitHubPullRequest]] = [:] // fullName → PRs

    private let baseURL = "https://api.github.com"
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Task<Void, Never>?

    deinit {
        syncTimer?.cancel()
    }

    private init() {
        // Load cached repos from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "github_repos_cache"),
           let cached = try? JSONDecoder().decode([GitHubRepo].self, from: data) {
            repos = cached
        }
        if let paths = UserDefaults.standard.dictionary(forKey: "github_cloned_repos") as? [String: String] {
            clonedRepos = paths
        }
        
        // Auto-verify token on init
        Task { await verifyToken() }
        
        // AUTO-SYNC: När appen startar, synka automatiskt till iCloud
        Task {
            // Vänta lite så att iCloud hinner bli tillgängligt
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 sekunder
            await autoSyncToiCloud()
        }
    }
    
    // AUTO-SYNC: Körs automatiskt vid start och när repos hämtas
    func autoSyncToiCloud() async {
        guard let token = token, !token.isEmpty else { return }
        
        let icloudRoot = iCloudSyncEngine.shared.githubReposRoot
        guard let root = icloudRoot else {
            NaviLog.info("GitHub: iCloud inte tillgänglig ännu, väntar...")
            // Försök igen senare
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await autoSyncToiCloud()
            return
        }
        
        // Skapa iCloud-mappen om den inte finns
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        // Hämta alla repos först
        await fetchRepos()
        
        guard !repos.isEmpty else { return }
        
        NaviLog.info("GitHub: Synkar \(repos.count) repos till iCloud...")
        
        for repo in repos {
            await syncRepoToiCloud(repo: repo, root: root)
        }
        
        // Spara metadata
        await saveRepoMetadata()
        
        NaviLog.info("GitHub: Auto-sync klar för \(repos.count) repos")

        // GitHub → Server: tell the server to pull latest code
        await NaviBrainService.shared.triggerServerGitSync()
        NaviLog.info("GitHub: Server git-sync triggered")

        // Starta periodisk synkning var 5:e minut
        startPeriodicSync()
    }
    
    // Periodisk synkning var 5:e minut
    private func startPeriodicSync() {
        syncTimer?.cancel()
        syncTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minuter
                guard !Task.isCancelled else { break }
                NaviLog.info("GitHub: Periodisk synkning...")
                await autoSyncToiCloud()
            }
        }
    }
    
    // MARK: - iCloud Sync for GitHub Repos
    
    /// Sync ALL repos to iCloud - clones/pulls all branches
    func syncAllReposToiCloud() async {
        guard let token = token, !token.isEmpty else { return }
        
        let icloudRoot = iCloudSyncEngine.shared.githubReposRoot
        guard let root = icloudRoot else {
            NaviLog.error("GitHub: iCloud root not available")
            return
        }
        
        // Ensure the directory exists
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        isLoadingRepos = true
        syncStatus["_all"] = "Hämtar alla repos från GitHub..."
        
        // First fetch all repos from GitHub
        await fetchRepos()
        
        let allRepos = repos
        syncStatus["_all"] = "Synkar \(allRepos.count) repos till iCloud..."
        
        for repo in allRepos {
            syncStatus[repo.fullName] = "Synkar \(repo.fullName)..."
            await syncRepoToiCloud(repo: repo, root: root)
        }
        
        isLoadingRepos = false
        syncStatus["_all"] = "Synk klar!"
        
        // Save sync metadata
        await saveRepoMetadata()
        
        NaviLog.info("GitHub: Synkade \(allRepos.count) repos till iCloud")
    }
    
    /// Sync a single repo to iCloud - clone or pull if exists
    func syncRepoToiCloud(repo: GitHubRepo, root: URL) async {
        let repoPath = root.appendingPathComponent(sanitizeRepoName(repo.fullName))
        let branch = repo.currentBranch
        
        if FileManager.default.fileExists(atPath: repoPath.path) {
            // Already exists - pull latest
            syncStatus[repo.fullName] = "Uppdaterar \(repo.fullName)..."
            await pull(repo: repo)
        } else {
            // Clone fresh
            syncStatus[repo.fullName] = "Klonar \(repo.fullName)..."
            let result = await runGit(["clone", "--branch", branch, repo.cloneURL, repoPath.path])
            if result.success {
                clonedRepos[repo.fullName] = repoPath.path
                UserDefaults.standard.set(clonedRepos, forKey: "github_cloned_repos")
                NaviLog.info("GitHub: Cloned \(repo.fullName) to iCloud")
            } else {
                NaviLog.error("GitHub: Failed to clone \(repo.fullName): \(result.output)")
            }
        }
        
        // Fetch all branches
        await fetchBranches(for: repo)
        
        // Save branch info locally
        if let branches = branchCache[repo.fullName] {
            await saveBranchInfo(repoName: repo.fullName, branches: branches)
        }
        
        syncStatus[repo.fullName] = "Klar"
    }
    
    /// Get local iCloud path for a repo
    func getLocalRepoPath(for fullName: String) -> URL? {
        let icloudRoot = iCloudSyncEngine.shared.githubReposRoot
        guard let root = icloudRoot else { return nil }
        return root.appendingPathComponent(sanitizeRepoName(fullName))
    }

    /// Check if repo exists locally in iCloud
    func hasLocalRepo(fullName: String) -> Bool {
        guard let path = getLocalRepoPath(for: fullName) else { return false }
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Get list of all local repos in iCloud
    func getLocalRepos() -> [String] {
        let icloudRoot = iCloudSyncEngine.shared.githubReposRoot
        guard let root = icloudRoot else { return [] }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        
        return contents.filter { !$0.hasPrefix(".") }
    }
    
    /// Get files in a local repo
    func getLocalRepoFiles(fullName: String, path: String = "") -> [String] {
        guard let basePath = getLocalRepoPath(for: fullName) else { return [] }
        
        let fullPath = path.isEmpty ? basePath : basePath.appendingPathComponent(path)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: fullPath.path) else {
            return []
        }
        
        return contents
    }
    
    /// Get file content from local repo
    func getLocalFileContent(fullName: String, filePath: String) -> String? {
        guard let basePath = getLocalRepoPath(for: fullName) else { return nil }
        let full = basePath.appendingPathComponent(filePath)
        return try? String(contentsOf: full, encoding: .utf8)
    }
    
    /// Get current branch for local repo
    func getLocalCurrentBranch(fullName: String) -> String? {
        guard let basePath = getLocalRepoPath(for: fullName) else { return nil }
        
        let result = runGitSync(["rev-parse", "--abbrev-ref", "HEAD"], at: basePath.path)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Get latest commit hash
    func getLocalLatestCommit(fullName: String, branch: String? = nil) -> String? {
        guard let basePath = getLocalRepoPath(for: fullName) else { return nil }
        
        let branchArg = branch ?? "HEAD"
        let result = runGitSync(["log", "-1", "--format=%H", branchArg], at: basePath.path)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Get commit history
    func getLocalCommitHistory(fullName: String, limit: Int = 10) -> [GitHubCommit] {
        guard let basePath = getLocalRepoPath(for: fullName) else { return [] }
        
        let result = runGitSync([
            "log", "-\(limit)",
            "--format=%H|%s|%an|%ai",
            "--date=iso"
        ], at: basePath.path)
        
        let lines = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        return lines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 3)
            guard parts.count >= 4 else { return nil }
            
            let sha = String(parts[0])
            let message = String(parts[1])
            let author = String(parts[2])
            let dateStr = String(parts[3])
            
            return GitHubCommit(
                sha: sha,
                commit: GitHubCommit.CommitDetail(
                    message: message,
                    author: GitHubCommit.CommitAuthor(name: author, date: dateStr)
                ),
                htmlURL: ""
            )
        }
    }
    
    /// Push changes for a repo
    func push(repo: GitHubRepo, message: String?) async -> Bool {
        guard let path = getLocalRepoPath(for: repo.fullName) else { return false }
        
        // Stage all changes
        _ = runGitSync(["add", "-A"], at: path.path)
        
        // Commit if message provided
        if let msg = message, !msg.isEmpty {
            _ = runGitSync(["commit", "-m", msg], at: path.path)
        }
        
        // Push
        let currentBranch = getLocalCurrentBranch(fullName: repo.fullName) ?? repo.currentBranch
        let result = runGitSync(["push", "origin", currentBranch], at: path.path)
        
        if result.success {
            NaviLog.info("GitHub: Pushed \(repo.fullName)")
            return true
        } else {
            NaviLog.error("GitHub: Push failed for \(repo.fullName): \(result.output)")
            return false
        }
    }
    
    /// Get git status for local repo
    func getLocalStatus(fullName: String) -> String {
        guard let path = getLocalRepoPath(for: fullName) else { return "" }
        let result = runGitSync(["status", "--porcelain"], at: path.path)
        return result.output
    }
    
    /// Create and push a new branch
    func createAndPushBranch(repoFullName: String, branchName: String, fromBranch: String) async -> Bool {
        guard let path = getLocalRepoPath(for: repoFullName) else { return false }
        
        // Create branch
        _ = runGitSync(["checkout", "-b", branchName, "origin/\(fromBranch)"], at: path.path)
        
        // Push
        let result = runGitSync(["push", "-u", "origin", branchName], at: path.path)
        
        return result.success
    }
    
    // MARK: - Helper functions
    
    private func sanitizeRepoName(_ fullName: String) -> String {
        return fullName.replacingOccurrences(of: "/", with: "_")
    }
    
    private func saveRepoMetadata() async {
        let icloudRoot = iCloudSyncEngine.shared.githubReposRoot
        guard let root = icloudRoot else { return }
        
        let metaPath = root.appendingPathComponent("_repos_metadata.json")
        
        let metadata = repos.map { repo in
            [
                "fullName": repo.fullName,
                "defaultBranch": repo.defaultBranch,
                "currentBranch": repo.currentBranch,
                "language": repo.language ?? "",
                "updatedAt": ISO8601DateFormatter().string(from: repo.updatedAt),
                "hasLocal": hasLocalRepo(fullName: repo.fullName)
            ] as [String : Any]
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
            try? data.write(to: metaPath)
        }
    }
    
    private func saveBranchInfo(repoName: String, branches: [GitHubBranch]) async {
        let icloudRoot = iCloudSyncEngine.shared.githubReposRoot
        guard let root = icloudRoot else { return }
        
        let branchPath = root.appendingPathComponent("\(sanitizeRepoName(repoName))_branches.json")
        
        if let data = try? JSONEncoder().encode(branches) {
            try? data.write(to: branchPath)
        }
    }
    
    /// Run git command synchronously (macOS only)
    private func runGitSync(_ args: [String], at path: String) -> (success: Bool, output: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            return (process.terminationStatus == 0, output + error)
        } catch {
            return (false, error.localizedDescription)
        }
        #else
        // iOS doesn't support Process - queue to Mac
        let cmd = "git -C \"\(path)\" " + args.joined(separator: " ")
        return (false, "Git on iOS: \(cmd) needs Mac execution")
        #endif
    }

    // MARK: - Token management (iCloud Keychain synced)

    var token: String? {
        get { KeychainSync.getSync(key: Constants.Keychain.githubKey) }
    }

    func saveToken(_ token: String) throws {
        try KeychainSync.saveSync(key: Constants.Keychain.githubKey, value: token)
    }

    func deleteToken() {
        KeychainSync.deleteSync(key: Constants.Keychain.githubKey)
        authState = .notAuthorized
        repos = []
    }

    // MARK: - Auth verification

    func verifyToken() async {
        guard let token, !token.isEmpty else {
            authState = .notAuthorized
            return
        }
        authState = .loading
        do {
            let user = try await fetchUser(token: token)
            authState = .authorized(user: user)
            await fetchRepos()
        } catch {
            authState = .error(error.localizedDescription)
        }
    }

    private func fetchUser(token: String) async throws -> GitHubUser {
        let req = try makeRequest(path: "/user", token: token)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    // MARK: - Fetch repos (all pages)

    func fetchRepos() async {
        guard let token else { return }
        isLoadingRepos = true
        repoError = nil
        do {
            var all: [GitHubRepo] = []
            var page = 1
            while true {
                let req = try makeRequest(path: "/user/repos?per_page=100&page=\(page)&sort=updated&affiliation=owner,collaborator,organization_member", token: token)
                let (data, resp) = try await URLSession.shared.data(for: req)
                try checkResponse(resp, data: data)
                let decoder = JSONDecoder()
                let batch = try decoder.decode([GitHubRepo].self, from: data)
                if batch.isEmpty { break }
                all.append(contentsOf: batch)
                page += 1
                if batch.count < 100 { break }
            }
            // Preserve user-selected branches
            repos = all.map { repo in
                var r = repo
                if let existing = repos.first(where: { $0.id == repo.id }) {
                    r.currentBranch = existing.currentBranch
                }
                return r
            }
            // Cache
            if let data = try? JSONEncoder().encode(repos) {
                UserDefaults.standard.set(data, forKey: "github_repos_cache")
            }
        } catch {
            repoError = error.localizedDescription
        }
        isLoadingRepos = false
    }

    // MARK: - Branches

    func fetchBranches(for repo: GitHubRepo, forceRefresh: Bool = false) async -> [GitHubBranch] {
        if !forceRefresh, let cached = branchCache[repo.fullName] { return cached }
        guard let token else { return [] }
        do {
            var all: [GitHubBranch] = []
            var page = 1
            while true {
                let req = try makeRequest(path: "/repos/\(repo.fullName)/branches?per_page=100&page=\(page)", token: token)
                let (data, resp) = try await URLSession.shared.data(for: req)
                try checkResponse(resp, data: data)
                let batch = try JSONDecoder().decode([GitHubBranch].self, from: data)
                all.append(contentsOf: batch)
                if batch.count < 100 { break }
                page += 1
            }
            branchCache[repo.fullName] = all
            return all
        } catch { return [] }
    }

    func setBranch(_ branch: String, for repoID: Int) {
        if let idx = repos.firstIndex(where: { $0.id == repoID }) {
            repos[idx].currentBranch = branch
            if let data = try? JSONEncoder().encode(repos) {
                UserDefaults.standard.set(data, forKey: "github_repos_cache")
            }
        }
    }

    // MARK: - Recent commits

    func fetchCommits(for repo: GitHubRepo, branch: String? = nil, forceRefresh: Bool = false) async -> [GitHubCommit] {
        let b = branch ?? repo.currentBranch
        let cacheKey = "\(repo.fullName)/\(b)"
        if !forceRefresh, let cached = commitCache[cacheKey] { return cached }
        guard let token else { return [] }
        do {
            let req = try makeRequest(path: "/repos/\(repo.fullName)/commits?sha=\(b)&per_page=20", token: token)
            let (data, resp) = try await URLSession.shared.data(for: req)
            try checkResponse(resp, data: data)
            let commits = try JSONDecoder().decode([GitHubCommit].self, from: data)
            commitCache[cacheKey] = commits
            return commits
        } catch { return [] }
    }

    // MARK: - Pull Requests

    func fetchPullRequests(for repo: GitHubRepo, state: String = "open", forceRefresh: Bool = false) async -> [GitHubPullRequest] {
        if !forceRefresh, let cached = prCache[repo.fullName] { return cached }
        guard let token else { return [] }
        do {
            let req = try makeRequest(path: "/repos/\(repo.fullName)/pulls?state=\(state)&per_page=30&sort=updated&direction=desc", token: token)
            let (data, resp) = try await URLSession.shared.data(for: req)
            try checkResponse(resp, data: data)
            let prs = try JSONDecoder().decode([GitHubPullRequest].self, from: data)
            prCache[repo.fullName] = prs
            return prs
        } catch { return [] }
    }

    func createPullRequest(
        repo: GitHubRepo,
        title: String,
        body: String,
        head: String,
        base: String
    ) async throws -> GitHubPullRequest {
        guard let token else { throw GitHubError.unauthorized }

        var req = try makeRequest(path: "/repos/\(repo.fullName)/pulls", token: token)
        req.httpMethod = "POST"
        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "head": head,
            "base": base
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        let pr = try JSONDecoder().decode(GitHubPullRequest.self, from: data)
        // Invalidate cache
        prCache[repo.fullName] = nil
        return pr
    }

    func mergePullRequest(repo: GitHubRepo, number: Int) async throws {
        guard let token else { throw GitHubError.unauthorized }

        var req = try makeRequest(path: "/repos/\(repo.fullName)/pulls/\(number)/merge", token: token)
        req.httpMethod = "PUT"
        let payload: [String: Any] = ["merge_method": "squash"]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        // Invalidate caches
        prCache[repo.fullName] = nil
        commitCache = commitCache.filter { !$0.key.hasPrefix(repo.fullName) }
    }

    // MARK: - Clone / open repo locally

    func cloneOrOpen(repo: GitHubRepo) async -> String? {
        if let localPath = clonedRepos[repo.fullName],
           FileManager.default.fileExists(atPath: localPath) {
            // Already cloned — switch to correct branch
            await switchBranch(to: repo.currentBranch, at: localPath)
            return localPath
        }

        // Clone fresh
        let dest = localRepoPath(for: repo)
        syncStatus[repo.fullName] = "Klonar…"
        let result = await runGit(["clone", "--branch", repo.currentBranch, repo.cloneURL, dest])
        if result.success {
            clonedRepos[repo.fullName] = dest
            UserDefaults.standard.set(clonedRepos, forKey: "github_cloned_repos")
            syncStatus[repo.fullName] = "Klonad ✓"
            return dest
        } else {
            syncStatus[repo.fullName] = "Kloning misslyckades: \(result.output)"
            return nil
        }
    }

    // MARK: - Branch switch

    func switchBranch(to branch: String, at path: String) async {
        let fetch = await runGit(["-C", path, "fetch", "--all"])
        let checkout = await runGit(["-C", path, "checkout", branch])
        if !checkout.success {
            // Branch doesn't exist locally — track remote
            let _ = await runGit(["-C", path, "checkout", "-b", branch, "origin/\(branch)"])
        }
        let pull = await runGit(["-C", path, "pull", "--rebase"])
        _ = fetch; _ = pull
    }

    // MARK: - Pull

    func pull(repo: GitHubRepo) async {
        guard let localPath = clonedRepos[repo.fullName] else { return }
        syncStatus[repo.fullName] = "Hämtar…"
        await ensureAuthRemote(repo: repo, at: localPath)
        let result = await runGit(["-C", localPath, "pull", "--rebase", "origin", repo.currentBranch])
        syncStatus[repo.fullName] = result.success ? "Uppdaterad ✓" : "Pull misslyckades: \(result.output)"
        // Refresh commit cache after pull
        if result.success {
            commitCache["\(repo.fullName)/\(repo.currentBranch)"] = nil
        }
    }

    /// Ensure the remote origin URL contains auth credentials
    private func ensureAuthRemote(repo: GitHubRepo, at localPath: String) async {
        guard let tok = token else { return }
        let authURL = repo.cloneURL.replacingOccurrences(
            of: "https://github.com/",
            with: "https://x-access-token:\(tok)@github.com/"
        )
        let _ = await runGit(["-C", localPath, "remote", "set-url", "origin", authURL])
    }

    // MARK: - Auto sync (pull on open, push on save)

    func autoPull(repo: GitHubRepo) async {
        guard clonedRepos[repo.fullName] != nil else { return }
        await pull(repo: repo)
    }

    func autoCommitAndPush(repo: GitHubRepo, changedFiles: [String]) async {
        guard let localPath = clonedRepos[repo.fullName] else { return }
        await ensureAuthRemote(repo: repo, at: localPath)
        // Stage all or specific files
        if changedFiles.isEmpty {
            let _ = await runGit(["-C", localPath, "add", "-A"])
        } else {
            for file in changedFiles {
                let _ = await runGit(["-C", localPath, "add", file])
            }
        }
        let statusResult = await runGit(["-C", localPath, "status", "--porcelain"])
        guard !statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let msg = changedFiles.isEmpty
            ? "Navi: agent-ändringar \(Date().formatted(.dateTime.hour().minute()))"
            : "Navi: uppdaterar \(changedFiles.prefix(3).joined(separator: ", "))"
        let _ = await runGit(["-C", localPath, "commit", "-m", msg])
        let pushResult = await runGit(["-C", localPath, "push", "origin", repo.currentBranch])
        syncStatus[repo.fullName] = pushResult.success ? "Auto-pushad ✓" : "Push misslyckades: \(pushResult.output)"
        // Invalidate commit cache so UI refreshes
        commitCache["\(repo.fullName)/\(repo.currentBranch)"] = nil
    }

    // MARK: - Auto-create repo for new project

    /// Creates a new GitHub repo for a project (if no repo is linked) and pushes initial content.
    func ensureRepoExists(for project: NaviProject) async -> GitHubRepo? {
        // Already linked
        if let fullName = project.githubRepoFullName,
           let existing = repos.first(where: { $0.fullName == fullName }) {
            return existing
        }

        guard let token, !token.isEmpty else { return nil }

        // Create repo via API
        let repoName = project.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let body: [String: Any] = [
            "name": repoName,
            "description": project.description.isEmpty ? "Skapad av Navi" : project.description,
            "private": true,
            "auto_init": true
        ]

        do {
            var req = try makeRequest(path: "/user/repos", token: token)
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, resp) = try await URLSession.shared.data(for: req)
            try checkResponse(resp, data: data)
            let newRepo = try JSONDecoder().decode(GitHubRepo.self, from: data)

            // Add to local list
            repos.insert(newRepo, at: 0)
            if let encoded = try? JSONEncoder().encode(repos) {
                UserDefaults.standard.set(encoded, forKey: "github_repos_cache")
            }

            // Clone it locally
            _ = await cloneOrOpen(repo: newRepo)

            return newRepo
        } catch {
            return nil
        }
    }

    /// Creates a feature branch for the current agent task and switches to it.
    func createFeatureBranch(name: String, in repo: GitHubRepo) async -> Bool {
        let safeName = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(50)
        return await createBranch(name: "feature/\(safeName)", from: repo.defaultBranch, in: repo)
    }

    /// Full auto-sync: pull latest, then push any local changes.
    func fullSync(repo: GitHubRepo) async {
        await pull(repo: repo)
        await autoCommitAndPush(repo: repo, changedFiles: [])
    }

    // MARK: - Create branch

    func createBranch(name: String, from base: String, in repo: GitHubRepo) async -> Bool {
        guard let localPath = clonedRepos[repo.fullName] else { return false }
        let _ = await runGit(["-C", localPath, "fetch", "--all"])
        let result = await runGit(["-C", localPath, "checkout", "-b", name, "origin/\(base)"])
        if result.success {
            let _ = await runGit(["-C", localPath, "push", "-u", "origin", name])
            branchCache[repo.fullName] = nil  // invalidate cache
        }
        return result.success
    }

    // MARK: - Git status for a repo

    func gitStatus(repo: GitHubRepo) async -> String {
        guard let localPath = clonedRepos[repo.fullName] else { return "Ej klonad" }
        let result = await runGit(["-C", localPath, "status", "--short"])
        return result.output.isEmpty ? "Rent" : result.output
    }

    // MARK: - Open repo as NaviProject

    func openAsProject(repo: GitHubRepo) async -> NaviProject? {
        guard let localPath = await cloneOrOpen(repo: repo) else { return nil }

        // Check if this repo is already linked to an existing project
        if let existing = ProjectStore.shared.projects.first(where: { $0.githubRepoFullName == repo.fullName }) {
            var updated = existing
            updated.rootPath = localPath
            updated.githubBranch = repo.currentBranch
            await ProjectStore.shared.save(updated)
            ProjectStore.shared.activeProject = updated
            NotificationCenter.default.post(name: .didOpenGitHubProject, object: nil)
            return updated
        }

        var project = NaviProject(name: repo.name, rootPath: localPath)
        project.githubRepoFullName = repo.fullName
        project.githubBranch = repo.currentBranch
        await ProjectStore.shared.save(project)
        ProjectStore.shared.activeProject = project
        // Notify UI to switch to project tab
        NotificationCenter.default.post(name: .didOpenGitHubProject, object: nil)
        return project
    }

    // MARK: - Helpers

    private func localRepoPath(for repo: GitHubRepo) -> String {
        #if os(macOS)
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Navi/GitHub")
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Navi/GitHub")
        #endif
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(repo.fullName.replacingOccurrences(of: "/", with: "_")).path
    }

    private func makeRequest(path: String, token: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 15
        return req
    }

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            authState = .notAuthorized
            throw GitHubError.unauthorized
        }
        if http.statusCode == 403 {
            throw GitHubError.forbidden
        }
        if http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode(GitHubAPIError.self, from: data))?.message ?? "HTTP \(http.statusCode)"
            throw GitHubError.apiError(msg)
        }
    }

    // MARK: - Run git command

    struct GitResult {
        let success: Bool
        let output: String
    }

    func runGit(_ args: [String]) async -> GitResult {
        #if os(macOS)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")

                // Rewrite clone URLs to embed token for HTTPS auth
                var adjustedArgs = args
                if let tok = self.token {
                    adjustedArgs = args.map { arg in
                        if arg.hasPrefix("https://github.com/") {
                            return arg.replacingOccurrences(
                                of: "https://github.com/",
                                with: "https://x-access-token:\(tok)@github.com/"
                            )
                        }
                        return arg
                    }
                }
                proc.arguments = adjustedArgs

                // Environment for git
                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"
                if let tok = self.token {
                    // Credential helper that provides token
                    env["GIT_ASKPASS"] = "/usr/bin/true"
                    env["GIT_USERNAME"] = "x-access-token"
                    env["GIT_PASSWORD"] = tok
                }
                proc.environment = env

                let pipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = errPipe

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let combined = [out, err].filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(returning: GitResult(success: proc.terminationStatus == 0, output: combined))
                } catch {
                    cont.resume(returning: GitResult(success: false, output: error.localizedDescription))
                }
            }
        }
        #else
        // iOS: queue to Mac via InstructionQueue
        let cmd = "git " + args.joined(separator: " ")
        let instr = Instruction(instruction: cmd, projectID: nil)
        await InstructionQueue.shared.enqueue(instr)
        return GitResult(success: true, output: "Köad till Mac: \(cmd)")
        #endif
    }
}

// MARK: - Error types

enum GitHubError: LocalizedError {
    case unauthorized
    case forbidden
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Ogiltig GitHub-token. Kontrollera din token i Inställningar."
        case .forbidden: return "Åtkomst nekad. Kontrollera token-behörigheter."
        case .apiError(let msg): return "GitHub API-fel: \(msg)"
        }
    }
}

private struct GitHubAPIError: Codable {
    let message: String
}

extension Notification.Name {
    static let didOpenGitHubProject = Notification.Name("didOpenGitHubProject")
}
