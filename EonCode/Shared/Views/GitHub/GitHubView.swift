import SwiftUI

// MARK: - GitHubView

struct GitHubView: View {
    @StateObject private var gh = GitHubManager.shared
    @State private var searchText = ""
    @State private var selectedRepo: GitHubRepo?
    @State private var showTokenEntry = false

    var body: some View {
        Group {
            switch gh.authState {
            case .notAuthorized:
                authGateView
            case .loading:
                loadingView
            case .error(let msg):
                errorView(msg)
            case .authorized:
                #if os(macOS)
                macLayout
                #else
                iOSLayout
                #endif
            }
        }
        .onAppear {
            Task { await gh.verifyToken() }
        }
        .sheet(isPresented: $showTokenEntry) {
            GitHubTokenSheet()
        }
    }

    // MARK: - Auth gate

    var authGateView: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 52))
                    .foregroundColor(.primary.opacity(0.7))
                Text("GitHub")
                    .font(.system(size: 32, weight: .bold))
                Text("Anslut ditt GitHub-konto för att komma åt alla dina repos, byta branch och koda direkt i Navi.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            VStack(spacing: 12) {
                Button { showTokenEntry = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                        Text("Anslut med GitHub Token")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
                    .background(Color.accentNavi)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                Text("Kräver en Personal Access Token med repo, read:org och workflow-behörigheter.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text("Ansluter till GitHub…").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }

    func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40)).foregroundColor(.orange)
            Text("Anslutningsfel").font(.system(size: 18, weight: .semibold))
            Text(msg).font(.system(size: 13)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("Försök igen") { Task { await gh.verifyToken() } }
                    .buttonStyle(.plain).foregroundColor(.accentNavi)
                Button("Byt token") { showTokenEntry = true }
                    .buttonStyle(.plain).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }

    // MARK: - macOS layout

    #if os(macOS)
    var macLayout: some View {
        HSplitView {
            repoListPanel.frame(minWidth: 260, maxWidth: 340)
            if let repo = selectedRepo {
                RepoWorkView(repo: repo)
            } else {
                repoEmptyDetail
            }
        }
    }

    var repoListPanel: some View {
        VStack(spacing: 0) {
            repoListHeader
            Divider().opacity(0.12)
            repoSearchBar.padding(.horizontal, 10).padding(.vertical, 8)
            Divider().opacity(0.08)
            repoList
        }
        .background(Color.sidebarBackground)
    }

    var repoListHeader: some View {
        HStack {
            if case .authorized(let user) = gh.authState {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 16)).foregroundColor(.accentNavi)
                    Text(user.login).font(.system(size: 13, weight: .semibold))
                }
            }
            Spacer()
            Button { Task { await gh.fetchRepos() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .buttonStyle(.plain).help("Uppdatera repos")

            Button { Task { await gh.syncAllReposToiCloud() } } label: {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 12)).foregroundColor(.accentNavi)
            }
            .buttonStyle(.plain).help("Synka ALLA repos till iCloud")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    var repoEmptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.2))
            Text("Välj ett repo att arbeta på")
                .font(.system(size: 15)).foregroundColor(.secondary.opacity(0.4))
            Text("Välj repo → välj branch → Börja arbeta")
                .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }
    #endif

    // MARK: - iOS layout

    var iOSLayout: some View {
        VStack(spacing: 0) {
            iOSHeader
            Divider().opacity(0.12)
            repoSearchBar.padding(.horizontal, 14).padding(.vertical, 8)
            Divider().opacity(0.08)
            repoList
        }
        .background(Color.chatBackground)
        .sheet(item: $selectedRepo) { repo in
            RepoWorkView(repo: repo)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    var iOSHeader: some View {
        HStack {
            if case .authorized(let user) = gh.authState {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 18)).foregroundColor(.accentNavi)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("GitHub").font(.system(size: 16, weight: .bold))
                        Text(user.login).font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button { Task { await gh.syncAllReposToiCloud() } } label: {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 16)).foregroundColor(.accentNavi)
            }
            .buttonStyle(.plain)

            Button { Task { await gh.fetchRepos() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16)).foregroundColor(.secondary)
                    .rotationEffect(.degrees(gh.isLoadingRepos ? 360 : 0))
                    .animation(gh.isLoadingRepos ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: gh.isLoadingRepos)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Shared: search bar

    var repoSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.6))
            TextField("Sök repos…", text: $searchText)
                .font(.system(size: 13)).textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.white.opacity(0.07))
        .cornerRadius(7)
    }

    // MARK: - Shared: repo list

    var filteredRepos: [GitHubRepo] {
        searchText.isEmpty ? gh.repos : gh.repos.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var repoList: some View {
        Group {
            if gh.isLoadingRepos && gh.repos.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Hämtar repos…").font(.system(size: 13)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = gh.repoError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text(err).font(.system(size: 12)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredRepos) { repo in
                            RepoRow(
                                repo: repo,
                                isSelected: selectedRepo?.id == repo.id
                            ) {
                                selectedRepo = repo
                            }
                        }
                        if filteredRepos.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 24)).foregroundColor(.secondary.opacity(0.2))
                                Text(searchText.isEmpty ? "Inga repos" : "Inga träffar")
                                    .font(.system(size: 13)).foregroundColor(.secondary.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity).padding(.top, 32)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

// MARK: - Repo row

struct RepoRow: View {
    let repo: GitHubRepo
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentNavi : .secondary.opacity(0.6))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(repo.name)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white : .primary)
                            .lineLimit(1)
                        if repo.isPrivate {
                            Text("privat")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                            Text(repo.currentBranch).font(.system(size: 10))
                        }
                        .foregroundColor(.secondary.opacity(0.6))
                        if let lang = repo.language {
                            Text(lang).font(.system(size: 10)).foregroundColor(.secondary.opacity(0.5))
                        }
                        Spacer()
                        Text(repo.updatedAt.relativeString)
                            .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

// MARK: - RepoWorkView
// The main "work on this repo" view: branch picker, clone/open, commits, files, info.

struct RepoWorkView: View {
    let repo: GitHubRepo
    @StateObject private var gh = GitHubManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var branches: [GitHubBranch] = []
    @State private var commits: [GitHubCommit] = []
    @State private var isLoadingBranches = false
    @State private var isLoadingCommits = false
    @State private var isWorking = false          // cloning / opening
    @State private var showCreateBranch = false
    @State private var selectedTab = 0
    @State private var workStarted = false        // after "Börja arbeta" tapped
    @State private var showCommitSheet = false
    @State private var commitMessage = ""
    @State private var pullRequests: [GitHubPullRequest] = []
    @State private var isLoadingPRs = false
    @State private var showCreatePR = false

    var currentRepo: GitHubRepo {
        gh.repos.first(where: { $0.id == repo.id }) ?? repo
    }
    var localPath: String? { gh.clonedRepos[repo.fullName] }
    var syncStatus: String? { gh.syncStatus[repo.fullName] }
    var isLinkedToProject: Bool {
        gh.clonedRepos[repo.fullName] != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.12)

            if workStarted || isLinkedToProject {
                // Full detail view once working
                tabBar
                Divider().opacity(0.08)
                tabContent
            } else {
                // "Start working" picker
                startWorkingView
            }
        }
        .background(Color.chatBackground)
        .onAppear { loadData() }
        .onChange(of: currentRepo.currentBranch) { _ in reloadCommits() }
        .sheet(isPresented: $showCreateBranch) {
            CreateBranchSheet(repo: currentRepo, baseBranch: currentRepo.currentBranch)
        }
        .sheet(isPresented: $showCommitSheet) {
            CommitAndPushSheet(repo: currentRepo) {
                Task {
                    commits = await gh.fetchCommits(for: currentRepo, forceRefresh: true)
                }
            }
        }
        .sheet(isPresented: $showCreatePR) {
            CreatePRSheet(repo: currentRepo, branches: branches) {
                Task { pullRequests = await gh.fetchPullRequests(for: currentRepo, forceRefresh: true) }
            }
        }
    }

    // MARK: - Header

    var header: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            #endif

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(repo.name).font(.system(size: 18, weight: .bold))
                    if repo.isPrivate {
                        Label("Privat", systemImage: "lock.fill")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.white.opacity(0.08)).cornerRadius(6)
                    }
                }
                Text(repo.fullName).font(.system(size: 12)).foregroundColor(.secondary)
            }

            Spacer()

            // Sync status badge
            if let status = syncStatus {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundColor(status.contains("✓") ? .green : .secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Start working view (branch picker + action)

    var startWorkingView: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Branch picker card
                VStack(alignment: .leading, spacing: 14) {
                    Label("Välj branch", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    if isLoadingBranches {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("Hämtar branches…").font(.system(size: 13)).foregroundColor(.secondary)
                        }
                    } else {
                        // Branch list
                        VStack(spacing: 2) {
                            ForEach(branches) { branch in
                                BranchPickerRow(
                                    branch: branch,
                                    isSelected: branch.name == currentRepo.currentBranch,
                                    isDefault: branch.name == repo.defaultBranch
                                ) {
                                    gh.setBranch(branch.name, for: repo.id)
                                }
                            }
                        }
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(10)

                        // Create new branch
                        Button {
                            showCreateBranch = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 13))
                                Text("Ny branch…")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(.accentNavi.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)

                // Selected branch summary
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 13)).foregroundColor(.accentNavi)
                        Text(currentRepo.currentBranch)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text("av \(repo.fullName)")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }

                // Primary action button
                Button {
                    Task { await startWorking() }
                } label: {
                    HStack(spacing: 10) {
                        if isWorking {
                            ProgressView().scaleEffect(0.8).tint(.white)
                            Text(localPath == nil ? "Klonar…" : "Öppnar…")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: localPath == nil ? "arrow.down.circle.fill" : "play.fill")
                                .font(.system(size: 15))
                            Text(localPath == nil ? "Klona & börja arbeta" : "Börja arbeta")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentNavi)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                // Quick info
                HStack(spacing: 20) {
                    if let lang = repo.language {
                        Label(lang, systemImage: "doc.text")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Label(repo.isPrivate ? "Privat" : "Publik",
                          systemImage: repo.isPrivate ? "lock" : "globe")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Label("\(repo.stargazersCount) ★", systemImage: "star")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Tab bar (after working)

    var tabBar: some View {
        HStack(spacing: 0) {
            tabPill("Commits", idx: 0)
            tabPill("PRs", idx: 1)
            tabPill("Filer", idx: 2)
            tabPill("Info", idx: 3)

            Spacer()

            // Branch picker inline
            Menu {
                ForEach(branches) { branch in
                    Button {
                        gh.setBranch(branch.name, for: repo.id)
                        if let path = localPath {
                            Task {
                                await gh.switchBranch(to: branch.name, at: path)
                                // Reload commits for new branch
                                isLoadingCommits = true
                                commits = await gh.fetchCommits(for: currentRepo, forceRefresh: true)
                                isLoadingCommits = false
                            }
                        }
                    } label: {
                        HStack {
                            Text(branch.name)
                            if branch.name == currentRepo.currentBranch {
                                Image(systemName: "checkmark")
                            }
                            if branch.protected { Image(systemName: "lock.fill") }
                        }
                    }
                }
                Divider()
                Button { showCreateBranch = true } label: {
                    Label("Ny branch…", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                    Text(currentRepo.currentBranch).font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Refresh commits
            Button {
                Task {
                    isLoadingCommits = true
                    commits = await gh.fetchCommits(for: currentRepo, forceRefresh: true)
                    isLoadingCommits = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .frame(width: 24, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Uppdatera")

            // Pull / Push
            Button {
                Task {
                    await gh.pull(repo: currentRepo)
                    // Refresh commits after pull
                    commits = await gh.fetchCommits(for: currentRepo, forceRefresh: true)
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Pull")

            Button { showCommitSheet = true } label: {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Commit & Push")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case 0: commitsTab
        case 1: pullRequestsTab
        case 2: filesTab
        default: infoTab
        }
    }

    // MARK: - Commits tab

    var commitsTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoadingCommits {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                } else if commits.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 24)).foregroundColor(.secondary.opacity(0.2))
                        Text("Inga commits").font(.system(size: 13)).foregroundColor(.secondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 32)
                } else {
                    // Summary row
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                        Text(currentRepo.currentBranch)
                            .font(.system(size: 11, weight: .semibold))
                        Text("·").foregroundColor(.secondary.opacity(0.3))
                        Text("\(commits.count) commits")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Divider().opacity(0.08)

                    // Grouped by date
                    ForEach(groupedCommits, id: \.0) { (dayLabel, dayCommits) in
                        CommitDayHeader(label: dayLabel)
                        ForEach(dayCommits) { commit in CommitRow(commit: commit) }
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// Commits grouped by calendar day
    var groupedCommits: [(String, [GitHubCommit])] {
        let cal = Calendar.current
        let iso = ISO8601DateFormatter()
        var groups: [(String, [GitHubCommit])] = []
        var seen: [String: Int] = [:]  // label → index in groups
        for commit in commits {
            let date = iso.date(from: commit.commit.author.date) ?? Date.distantPast
            let label: String
            if cal.isDateInToday(date) { label = "Idag" }
            else if cal.isDateInYesterday(date) { label = "Igår" }
            else {
                let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; f.locale = Locale(identifier: "sv_SE")
                label = f.string(from: date)
            }
            if let idx = seen[label] {
                groups[idx].1.append(commit)
            } else {
                seen[label] = groups.count
                groups.append((label, [commit]))
            }
        }
        return groups
    }

    // MARK: - Pull Requests tab

    var pullRequestsTab: some View {
        VStack(spacing: 0) {
            // Create PR button
            HStack {
                Spacer()
                Button { showCreatePR = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12))
                        Text("Ny PR").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.accentNavi)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.accentNavi.opacity(0.12))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider().opacity(0.08)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if isLoadingPRs {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                    } else if pullRequests.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.pull")
                                .font(.system(size: 24)).foregroundColor(.secondary.opacity(0.2))
                            Text("Inga öppna PRs").font(.system(size: 13)).foregroundColor(.secondary.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity).padding(.top, 32)
                    } else {
                        ForEach(pullRequests) { pr in
                            PRRow(pr: pr, repo: currentRepo) {
                                Task { pullRequests = await gh.fetchPullRequests(for: currentRepo, forceRefresh: true) }
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            Task {
                isLoadingPRs = true
                pullRequests = await gh.fetchPullRequests(for: currentRepo, forceRefresh: true)
                isLoadingPRs = false
            }
        }
    }

    // MARK: - Files tab

    var filesTab: some View {
        Group {
            if let path = localPath {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lokal sökväg:")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .padding(.horizontal, 16).padding(.top, 12)
                        Text(path)
                            .font(.system(size: 11, design: .monospaced)).foregroundColor(.accentNavi)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                        Divider().opacity(0.1)
                        LocalFileList(path: path)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36)).foregroundColor(.secondary.opacity(0.3))
                    Text("Klona repot för att se filer")
                        .font(.system(size: 13)).foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Info tab

    var infoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let desc = repo.description, !desc.isEmpty {
                    infoRow("Beskrivning", value: desc)
                }
                infoRow("Standard-branch", value: repo.defaultBranch)
                if let lang = repo.language { infoRow("Språk", value: lang) }
                infoRow("Stjärnor", value: "\(repo.stargazersCount)")
                infoRow("Synlighet", value: repo.isPrivate ? "Privat" : "Publik")
                infoRow("Senast uppdaterad", value: repo.updatedAt.relativeString)
                Divider().opacity(0.12)
                Link("Öppna på GitHub →", destination: URL(string: repo.htmlURL)!)
                    .font(.system(size: 13)).foregroundColor(.accentNavi)
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func loadData() {
        Task {
            isLoadingBranches = true
            branches = await gh.fetchBranches(for: repo, forceRefresh: true)
            isLoadingBranches = false
            isLoadingCommits = true
            async let commitsTask = gh.fetchCommits(for: currentRepo, forceRefresh: true)
            async let prsTask = gh.fetchPullRequests(for: currentRepo, forceRefresh: true)
            commits = await commitsTask
            pullRequests = await prsTask
            isLoadingCommits = false
        }
    }

    private func reloadCommits() {
        Task {
            isLoadingCommits = true
            commits = await gh.fetchCommits(for: currentRepo, forceRefresh: true)
            isLoadingCommits = false
        }
    }

    private func startWorking() async {
        isWorking = true
        // Pull latest if already cloned, else clone fresh
        if localPath != nil {
            await gh.switchBranch(to: currentRepo.currentBranch, at: localPath!)
            await gh.pull(repo: currentRepo)
        } else {
            _ = await gh.cloneOrOpen(repo: currentRepo)
        }
        // Open as NaviProject
        _ = await gh.openAsProject(repo: currentRepo)
        isWorking = false
        workStarted = true
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value).font(.system(size: 13)).foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private func tabPill(_ title: String, idx: Int) -> some View {
        Button { selectedTab = idx } label: {
            Text(title)
                .font(.system(size: 12, weight: selectedTab == idx ? .semibold : .regular))
                .foregroundColor(selectedTab == idx ? .white : .secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selectedTab == idx ? Color.white.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Branch picker row

struct BranchPickerRow: View {
    let branch: GitHubBranch
    let isSelected: Bool
    let isDefault: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentNavi : .secondary.opacity(0.3))

                Text(branch.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 4) {
                    if isDefault {
                        Text("default")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(4)
                    }
                    if branch.protected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(isSelected ? Color.accentNavi.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Commit day header

struct CommitDayHeader: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.55))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - Commit row

struct CommitRow: View {
    let commit: GitHubCommit
    @State private var shaCopied = false

    var shortSHA: String { String(commit.sha.prefix(7)) }
    var message: String { commit.commit.message.components(separatedBy: "\n").first ?? commit.commit.message }
    var author: String { commit.commit.author.name }
    var time: String {
        let formatter = ISO8601DateFormatter()
        if let d = formatter.date(from: commit.commit.author.date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
        }
        return ""
    }

    var body: some View {
        HStack(spacing: 10) {
            // Copyable SHA pill
            Button {
                #if os(iOS)
                UIPasteboard.general.string = commit.sha
                #else
                NSPasteboard.general.setString(commit.sha, forType: .string)
                #endif
                shaCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shaCopied = false }
            } label: {
                Text(shaCopied ? "✓" : shortSHA)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(shaCopied ? .green : .accentNavi)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(shaCopied ? Color.green.opacity(0.1) : Color.accentNavi.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 52, alignment: .leading)
            .animation(.easeInOut(duration: 0.15), value: shaCopied)

            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.system(size: 13)).foregroundColor(.primary).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "person").font(.system(size: 9))
                    Text(author).font(.system(size: 10)).foregroundColor(.secondary.opacity(0.6)).lineLimit(1)
                    if !time.isEmpty {
                        Text("·").foregroundColor(.secondary.opacity(0.3))
                        Text(time).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary.opacity(0.45))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// MARK: - Local file list

struct LocalFileList: View {
    let path: String
    @State private var files: [String] = []

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(files, id: \.self) { file in
                HStack(spacing: 8) {
                    Image(systemName: fileIcon(file))
                        .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.5))
                    Text(file)
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(.primary).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 5)
            }
        }
        .onAppear {
            files = (try? FileManager.default.contentsOfDirectory(atPath: path))?.sorted() ?? []
        }
    }

    private func fileIcon(_ name: String) -> String {
        if name.hasPrefix(".") { return "eye.slash" }
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "js", "ts": return "doc.text"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        case "": return "folder"
        default: return "doc"
        }
    }
}

// MARK: - Create branch sheet

struct CreateBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gh = GitHubManager.shared
    let repo: GitHubRepo
    let baseBranch: String

    @State private var branchName = ""
    @State private var isCreating = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "arrow.triangle.branch").foregroundColor(.accentNavi)
                Text("Ny branch").font(.system(size: 18, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Branch-namn").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                GlassTextField(placeholder: "feature/min-funktion", text: $branchName)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Baseras på").font(.system(size: 12)).foregroundColor(.secondary)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                    Text(baseBranch).font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.accentNavi)
            }
            if !error.isEmpty {
                Text(error).font(.system(size: 12)).foregroundColor(.red)
            }
            HStack {
                Button("Avbryt") { dismiss() }.buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button {
                    Task {
                        isCreating = true
                        let ok = await gh.createBranch(name: branchName, from: baseBranch, in: repo)
                        isCreating = false
                        if ok { dismiss() } else { error = "Kunde inte skapa branch." }
                    }
                } label: {
                    if isCreating { ProgressView().scaleEffect(0.7) }
                    else { Text("Skapa").fontWeight(.semibold) }
                }
                .buttonStyle(.plain)
                .foregroundColor(branchName.isBlank ? .secondary : .accentNavi)
                .disabled(branchName.isBlank || isCreating)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.chatBackground)
    }
}

// MARK: - Commit & Push Sheet

struct CommitAndPushSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gh = GitHubManager.shared
    let repo: GitHubRepo
    var onComplete: (() -> Void)?

    @State private var commitMessage = ""
    @State private var gitStatus = ""
    @State private var isPushing = false
    @State private var result = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill").foregroundColor(.accentNavi)
                Text("Commit & Push").font(.system(size: 18, weight: .bold))
            }

            // Git status
            VStack(alignment: .leading, spacing: 6) {
                Text("Ändringar").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                if gitStatus.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("Kontrollerar…").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        Text(gitStatus == "Rent" ? "Inga ändringar att pusha" : gitStatus)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(gitStatus == "Rent" ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(Color.codeBackground)
                    .cornerRadius(8)
                }
            }

            // Commit message
            VStack(alignment: .leading, spacing: 6) {
                Text("Commit-meddelande").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                TextField("Beskriv dina ändringar…", text: $commitMessage, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.inputBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                    )
            }

            if !result.isEmpty {
                Text(result)
                    .font(.system(size: 12))
                    .foregroundColor(result.contains("✓") ? .green : .red)
            }

            HStack {
                Button("Avbryt") { dismiss() }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button {
                    Task { await pushChanges() }
                } label: {
                    HStack(spacing: 6) {
                        if isPushing {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(isPushing ? "Pushar…" : "Push")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(gitStatus == "Rent" || isPushing ? .secondary : .accentNavi)
                .disabled(gitStatus == "Rent" || isPushing)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color.chatBackground)
        .onAppear {
            Task { gitStatus = await gh.gitStatus(repo: repo) }
        }
    }

    private func pushChanges() async {
        isPushing = true
        let msg = commitMessage.trimmed.isEmpty ? nil : commitMessage.trimmed
        await gh.push(repo: repo, message: msg)
        isPushing = false
        if let status = gh.syncStatus[repo.fullName] {
            result = status
            if status.contains("✓") {
                onComplete?()
                try? await Task.sleep(for: .seconds(0.8))
                dismiss()
            }
        }
    }
}

// MARK: - PR Row

struct PRRow: View {
    let pr: GitHubPullRequest
    let repo: GitHubRepo
    let onMerged: () -> Void
    @StateObject private var gh = GitHubManager.shared
    @State private var isMerging = false
    @State private var mergeError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: pr.draft == true ? "circle.dashed" : "arrow.triangle.pull")
                    .font(.system(size: 13))
                    .foregroundColor(pr.state == "open" ? .green : .purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("#\(pr.number)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.accentNavi)
                        Text(pr.user.login)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("·").foregroundColor(.secondary.opacity(0.3))
                        Text("\(pr.head.ref) → \(pr.base.ref)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }

                Spacer()

                if pr.state == "open" && pr.draft != true {
                    Button {
                        Task { await merge() }
                    } label: {
                        if isMerging {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Text("Merge")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.green.opacity(0.8))
                                .cornerRadius(6)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isMerging)
                }
            }

            if !mergeError.isEmpty {
                Text(mergeError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func merge() async {
        isMerging = true
        mergeError = ""
        do {
            try await gh.mergePullRequest(repo: repo, number: pr.number)
            onMerged()
        } catch {
            mergeError = error.localizedDescription
        }
        isMerging = false
    }
}

// MARK: - Create PR Sheet

struct CreatePRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gh = GitHubManager.shared
    let repo: GitHubRepo
    let branches: [GitHubBranch]
    var onCreated: (() -> Void)?

    @State private var title = ""
    @State private var prBody = ""
    @State private var headBranch: String
    @State private var baseBranch: String
    @State private var isCreating = false
    @State private var error = ""

    init(repo: GitHubRepo, branches: [GitHubBranch], onCreated: (() -> Void)? = nil) {
        self.repo = repo
        self.branches = branches
        self.onCreated = onCreated
        _headBranch = State(initialValue: repo.currentBranch)
        _baseBranch = State(initialValue: repo.defaultBranch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.pull").foregroundColor(.accentNavi)
                Text("Skapa Pull Request").font(.system(size: 18, weight: .bold))
            }

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Titel").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                TextField("PR-titel…", text: $title)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.inputBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.inputBorder, lineWidth: 0.5))
            }

            // Description
            VStack(alignment: .leading, spacing: 6) {
                Text("Beskrivning").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                TextField("Vad ändrar denna PR?", text: $prBody, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.inputBackground)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.inputBorder, lineWidth: 0.5))
            }

            // Branch pickers
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Från").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                    Menu {
                        ForEach(branches) { branch in
                            Button(branch.name) { headBranch = branch.name }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                            Text(headBranch).font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 8))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: "arrow.right").font(.system(size: 12)).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Till").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                    Menu {
                        ForEach(branches) { branch in
                            Button(branch.name) { baseBranch = branch.name }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                            Text(baseBranch).font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.down").font(.system(size: 8))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !error.isEmpty {
                Text(error).font(.system(size: 12)).foregroundColor(.red)
            }

            HStack {
                Button("Avbryt") { dismiss() }.buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button {
                    Task { await create() }
                } label: {
                    HStack(spacing: 6) {
                        if isCreating { ProgressView().scaleEffect(0.7) }
                        Text(isCreating ? "Skapar…" : "Skapa PR").fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(canCreate ? .accentNavi : .secondary)
                .disabled(!canCreate || isCreating)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color.chatBackground)
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && headBranch != baseBranch
    }

    private func create() async {
        isCreating = true
        error = ""
        do {
            let _ = try await gh.createPullRequest(
                repo: repo,
                title: title.trimmingCharacters(in: .whitespaces),
                body: prBody.trimmingCharacters(in: .whitespaces),
                head: headBranch,
                base: baseBranch
            )
            onCreated?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - GitHub Token Sheet

struct GitHubTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gh = GitHubManager.shared

    @State private var tokenInput = ""
    @State private var isVerifying = false
    @State private var error = ""
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 20)).foregroundColor(.accentNavi)
                Text("Anslut GitHub").font(.system(size: 20, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Personal Access Token")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    GlassTextField(placeholder: "ghp_…", text: $tokenInput, isSecure: !isRevealed)
                    Button { isRevealed.toggle() } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kräver följande behörigheter:")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    ForEach(["repo (full access)", "read:org", "workflow", "delete_repo (valfri)"], id: \.self) { perm in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10)).foregroundColor(.green.opacity(0.7))
                            Text(perm).font(.system(size: 11)).foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 4)
                Link("Skapa token på GitHub →",
                     destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=Navi")!)
                    .font(.system(size: 12)).foregroundColor(.accentNavi)
            }
            if !error.isEmpty {
                Text(error).font(.system(size: 12)).foregroundColor(.red)
            }
            if gh.token != nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green).font(.system(size: 12))
                    Text("Token sparad och synkad via iCloud Keychain")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            HStack {
                if gh.token != nil {
                    Button("Ta bort token") { gh.deleteToken(); dismiss() }
                        .buttonStyle(.plain).foregroundColor(.red.opacity(0.7))
                }
                Spacer()
                Button("Avbryt") { dismiss() }.buttonStyle(.plain).foregroundColor(.secondary)
                Button {
                    Task { await saveAndVerify() }
                } label: {
                    if isVerifying { ProgressView().scaleEffect(0.7) }
                    else { Text("Anslut").fontWeight(.semibold) }
                }
                .buttonStyle(.plain)
                .foregroundColor(tokenInput.isBlank ? .secondary : .accentNavi)
                .disabled(tokenInput.isBlank || isVerifying)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color.chatBackground)
        .onAppear { tokenInput = gh.token ?? "" }
    }

    private func saveAndVerify() async {
        isVerifying = true
        error = ""
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainManager.shared.saveGitHubToken(trimmed)
            await gh.verifyToken()
            if case .authorized = gh.authState { dismiss() }
            else if case .error(let msg) = gh.authState { error = msg }
        } catch {
            self.error = error.localizedDescription
        }
        isVerifying = false
    }
}
