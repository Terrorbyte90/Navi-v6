import Foundation
import Combine

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

    private let baseURL = "https://api.github.com"
    private var cancellables = Set<AnyCancellable>()

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

    // MARK: - Push

    func push(repo: GitHubRepo, message: String? = nil) async {
        guard let localPath = clonedRepos[repo.fullName] else { return }
        syncStatus[repo.fullName] = "Pushar…"

        // Ensure remote URL has token embedded for auth
        await ensureAuthRemote(repo: repo, at: localPath)

        // Stage all changes
        let _ = await runGit(["-C", localPath, "add", "-A"])

        // Commit if there are staged changes
        let status = await runGit(["-C", localPath, "status", "--porcelain"])
        if !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let msg = message ?? "EonCode auto-commit \(Date().formatted())"
            let _ = await runGit(["-C", localPath, "commit", "-m", msg])
        }

        // Push
        let push = await runGit(["-C", localPath, "push", "origin", repo.currentBranch])
        syncStatus[repo.fullName] = push.success ? "Pushad ✓" : "Push misslyckades: \(push.output)"

        // Refresh commit cache after push
        if push.success {
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
            ? "EonCode: agent-ändringar \(Date().formatted(.dateTime.hour().minute()))"
            : "EonCode: uppdaterar \(changedFiles.prefix(3).joined(separator: ", "))"
        let _ = await runGit(["-C", localPath, "commit", "-m", msg])
        let pushResult = await runGit(["-C", localPath, "push", "origin", repo.currentBranch])
        syncStatus[repo.fullName] = pushResult.success ? "Auto-pushad ✓" : "Push misslyckades: \(pushResult.output)"
        // Invalidate commit cache so UI refreshes
        commitCache["\(repo.fullName)/\(repo.currentBranch)"] = nil
    }

    // MARK: - Auto-create repo for new project

    /// Creates a new GitHub repo for a project (if no repo is linked) and pushes initial content.
    func ensureRepoExists(for project: EonProject) async -> GitHubRepo? {
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
            "description": project.description.isEmpty ? "Skapad av EonCode" : project.description,
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

    // MARK: - Open repo as EonProject

    func openAsProject(repo: GitHubRepo) async -> EonProject? {
        guard let localPath = await cloneOrOpen(repo: repo) else { return nil }
        var project = EonProject(name: repo.name, rootPath: localPath)
        project.githubRepoFullName = repo.fullName
        project.githubBranch = repo.currentBranch
        await ProjectStore.shared.save(project)
        ProjectStore.shared.activeProject = project
        return project
    }

    // MARK: - Helpers

    private func localRepoPath(for repo: GitHubRepo) -> String {
        #if os(macOS)
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("EonCode/GitHub")
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EonCode/GitHub")
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
