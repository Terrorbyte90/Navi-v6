import SwiftUI

// MARK: - SidebarView
// ChatGPT macOS-style sidebar: nav items at top, contextual history list below,
// new-item + settings at bottom.

struct SidebarView: View {
    @Binding var selectedProject: NaviProject?
    @Binding var showNewProject: Bool
    @Binding var section: AppSection

    @StateObject private var store = ProjectStore.shared
    @StateObject private var agentPool = AgentPool.shared
    @StateObject private var chatManager = ChatManager.shared
    @StateObject private var artifactStore = ArtifactStore.shared
    @StateObject private var statusBroadcaster = DeviceStatusBroadcaster.shared
    @StateObject private var ghManager = GitHubManager.shared
    @StateObject private var mediaManager = MediaGenerationManager.shared

    @State private var searchText = ""
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Top: app name + new-item button ──────────────────────────────
            sidebarHeader

            // ── Search ───────────────────────────────────────────────────────
            searchBar
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            Divider().opacity(0.12)

            // ── Nav shortcuts ────────────────────────────────────────────────
            navSection
                .padding(.top, 4)

            Divider().opacity(0.08)
                .padding(.vertical, 6)

            // ── Contextual history list ──────────────────────────────────────
            contextualList

            Spacer(minLength: 0)

            Divider().opacity(0.12)

            // ── Bottom bar ───────────────────────────────────────────────────
            bottomBar
        }
        .frame(maxHeight: .infinity)
        .background(Color.sidebarBackground)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(width: 560, height: 640)
        }
    }

    // MARK: - Header

    var sidebarHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red:0.455,green:0.667,blue:0.612), Color(red:0.3,green:0.55,blue:0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text("Navi")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.primary)
                Text("— By: Ted Svärd")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.5))
            }
            .padding(.leading, 14)

            Spacer()

            // Contextual new-item button
            Button {
                switch section {
                case .pureChat: _ = chatManager.newConversation()
                case .agents:   NotificationCenter.default.post(name: .showCreateAgent, object: nil)
                default: break
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundColor(Color.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(newItemTooltip)
            .opacity(canCreateNew ? 1 : 0)
            .padding(.trailing, 8)
        }
        .frame(height: 46)
    }

    private var canCreateNew: Bool {
        section == .pureChat || section == .code || section == .agents
    }

    private var newItemTooltip: String {
        switch section {
        case .pureChat: return "Ny chatt"
        case .code:     return "Nytt Code-projekt"
        case .agents:   return "Ny agent"
        default:        return "Ny"
        }
    }

    // MARK: - Search bar

    var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
            TextField(searchPlaceholder, text: $searchText)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .cornerRadius(7)
    }

    private var searchPlaceholder: String {
        switch section {
        case .pureChat:  return "Sök chattar…"
        case .code:      return "Sök Code-projekt…"
        case .artifacts: return "Sök artefakter…"
        case .github:    return "Sök repos…"
        case .agents:    return "Sök agenter…"
        case .media:     return "Sök media…"
        case .profile:   return "Profil"
        case .voice:     return "Röst"
        }
    }

    // MARK: - Nav shortcuts (ChatGPT-style)

    var navSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            navItem(icon: "bubble.left.and.bubble.right.fill", label: "Chatt",      target: .pureChat)
            navItem(icon: "chevron.left.forwardslash.chevron.right.circle.fill", label: "Code", target: .code)
            navItem(icon: "chevron.left.forwardslash.chevron.right", label: "GitHub", target: .github,
                    badge: githubBadge)
            navItem(icon: "cpu.fill",                          label: "Agenter",    target: .agents,
                    badge: agentsBadge)
            navItem(icon: "photo.stack.fill",                  label: "Media",      target: .media,
                    badge: mediaBadge)
            navItem(icon: "tray.2.fill",                       label: "Artefakter", target: .artifacts,
                    badge: artifactStore.artifacts.isEmpty ? nil : "\(artifactStore.artifacts.count)")
            navItem(icon: "person.crop.circle.fill",           label: "Profil",     target: .profile)
            navItem(icon: "waveform",                          label: "Röst",       target: .voice)
        }
        .padding(.horizontal, 6)
    }

    private var agentsBadge: String? {
        let running = AutonomousAgentRunner.shared.agents.filter { $0.status.isActive }.count
        return running > 0 ? "\(running)" : nil
    }

    private var mediaBadge: String? {
        let active = mediaManager.activeGenerations.count
        return active > 0 ? "\(active)" : nil
    }

    private var githubBadge: String? {
        if case .authorized = GitHubManager.shared.authState {
            let count = GitHubManager.shared.repos.count
            return count > 0 ? "\(count)" : nil
        }
        return nil
    }

    @ViewBuilder
    private func navItem(icon: String, label: String, target: AppSection, badge: String? = nil) -> some View {
        let isActive = section == target
        Button { section = target } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isActive ? .accentNavi : .secondary)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .primary.opacity(0.85))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contextual history list

    @ViewBuilder
    var contextualList: some View {
        switch section {
        case .pureChat:  chatList
        case .code:      codeProjectList
        case .artifacts: artifactList
        case .github:    githubRepoList
        case .agents:    agentSidebarList
        case .media:     mediaHistoryList
        case .profile:   emptyHint(icon: "person.crop.circle", text: "AI-syntetiserad profil")
        case .voice:     emptyHint(icon: "waveform", text: "Text till tal · Ljud · Röstdesign")
        }
    }

    var codeProjectList: some View {
        let agent = CodeAgent.shared
        return Group {
            if agent.projects.isEmpty {
                emptyHint(icon: "chevron.left.forwardslash.chevron.right.circle", text: "Inga Code-projekt ännu")
            } else {
                ForEach(agent.projects) { proj in
                    Button {
                        agent.selectProject(proj)
                        section = .code
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: proj.currentPhase == .done ? "checkmark.circle.fill" : proj.currentPhase == .idle ? "circle" : "bolt.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(proj.currentPhase == .done ? .green : proj.currentPhase == .idle ? .secondary : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(proj.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(proj.currentPhase.displayName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        agent.activeProject?.id == proj.id
                            ? Color.accentNavi.opacity(0.08)
                            : Color.clear
                    )
                    .overlay(
                        agent.activeProject?.id == proj.id
                            ? Rectangle().fill(Color.accentNavi).frame(width: 2).frame(maxHeight: .infinity, alignment: .leading)
                            : nil,
                        alignment: .leading
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Project list



    // MARK: - Chat list

    var filteredChats: [ChatConversation] {
        searchText.isEmpty ? chatManager.conversations
            : chatManager.conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Date-bucketed chat list

    private enum ChatDateBucket: String {
        case today      = "Idag"
        case yesterday  = "Igår"
        case lastWeek   = "Förra 7 dagarna"
        case older      = "Äldre"
    }

    private func dateBucket(for date: Date) -> ChatDateBucket {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        if let daysAgo = cal.dateComponents([.day], from: date, to: Date()).day, daysAgo < 7 {
            return .lastWeek
        }
        return .older
    }

    private var groupedChats: [(ChatDateBucket, [ChatConversation])] {
        let bucketOrder: [ChatDateBucket] = [.today, .yesterday, .lastWeek, .older]
        var grouped: [ChatDateBucket: [ChatConversation]] = [:]
        for conv in filteredChats {
            let bucket = dateBucket(for: conv.updatedAt)
            grouped[bucket, default: []].append(conv)
        }
        return bucketOrder.compactMap { bucket in
            guard let convs = grouped[bucket], !convs.isEmpty else { return nil }
            return (bucket, convs)
        }
    }

    var chatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if filteredChats.isEmpty {
                    emptyHint(icon: "bubble.left.and.bubble.right",
                              text: searchText.isEmpty ? "Inga chattar" : "Inga träffar")
                } else if !searchText.isEmpty {
                    // Flat list when searching — no date groups
                    ForEach(filteredChats) { conv in
                        ChatConversationRow(
                            conversation: conv,
                            isSelected: chatManager.activeConversation?.id == conv.id,
                            onSelect: { chatManager.activeConversation = conv }
                        )
                    }
                } else {
                    // Date-grouped list
                    ForEach(groupedChats, id: \.0.rawValue) { bucket, convs in
                        listSectionHeader(bucket.rawValue)
                        ForEach(convs) { conv in
                            ChatConversationRow(
                                conversation: conv,
                                isSelected: chatManager.activeConversation?.id == conv.id,
                                onSelect: { chatManager.activeConversation = conv }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Artifact list

    var filteredArtifacts: [Artifact] {
        searchText.isEmpty ? Array(artifactStore.artifacts.prefix(40))
            : artifactStore.search(searchText)
    }

    var artifactList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if !filteredArtifacts.isEmpty {
                    listSectionHeader("Senaste")
                    ForEach(filteredArtifacts) { artifact in
                        Button { section = .artifacts } label: {
                            HStack(spacing: 8) {
                                Image(systemName: artifact.displayIcon)
                                    .font(.system(size: 12))
                                    .foregroundColor(artifact.displayColor)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artifact.title)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text("\(artifact.type.displayName) · \(artifact.sizeDescription)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary.opacity(0.45))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                    }
                } else {
                    emptyHint(icon: "tray.2", text: searchText.isEmpty ? "Inga artefakter" : "Inga träffar")
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - GitHub repo list (sidebar)

    var filteredGitHubRepos: [GitHubRepo] {
        let repos = ghManager.repos
        if searchText.isEmpty { return repos }
        return repos.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var githubRepoList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if case .notAuthorized = ghManager.authState {
                    emptyHint(icon: "chevron.left.forwardslash.chevron.right",
                              text: "Anslut GitHub i GitHub-vyn")
                } else if ghManager.isLoadingRepos {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                } else if filteredGitHubRepos.isEmpty {
                    emptyHint(icon: "chevron.left.forwardslash.chevron.right",
                              text: searchText.isEmpty ? "Inga repos" : "Inga träffar")
                } else {
                    listSectionHeader("Repos")
                    ForEach(filteredGitHubRepos) { repo in
                        Button {
                            section = .github
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: repo.isPrivate ? "lock.fill" : "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.name)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.system(size: 9))
                                        Text(repo.currentBranch)
                                            .font(.system(size: 10))
                                    }
                                    .foregroundColor(.secondary.opacity(0.5))
                                }
                                Spacer()
                                if let status = ghManager.syncStatus[repo.fullName] {
                                    Text(status)
                                        .font(.system(size: 9))
                                        .foregroundColor(status.contains("✓") ? .green : .secondary.opacity(0.5))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Agent sidebar list

    var agentSidebarList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                let runner = AutonomousAgentRunner.shared
                let filtered = searchText.isEmpty ? runner.agents
                    : runner.agents.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.goal.localizedCaseInsensitiveContains(searchText) }

                if filtered.isEmpty {
                    emptyHint(icon: "cpu.fill", text: searchText.isEmpty ? "Inga agenter" : "Inga träffar")
                } else {
                    let running = filtered.filter { $0.status.isActive }
                    let other   = filtered.filter { !$0.status.isActive }

                    if !running.isEmpty {
                        listSectionHeader("Aktiva")
                        ForEach(running) { agent in agentSidebarRow(agent) }
                    }
                    if !other.isEmpty {
                        listSectionHeader("Övriga")
                        ForEach(other) { agent in agentSidebarRow(agent) }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func agentSidebarRow(_ agent: AgentDefinition) -> some View {
        Button { section = .agents } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(agentSidebarColor(agent).opacity(0.12))
                        .frame(width: 22, height: 22)
                    Image(systemName: agent.status.isActive ? "cpu.fill" : "cpu")
                        .font(.system(size: 10))
                        .foregroundColor(agentSidebarColor(agent))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(agent.currentTaskDescription.isEmpty ? agent.status.displayName : agent.currentTaskDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                if agent.status.isActive {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    private func agentSidebarColor(_ agent: AgentDefinition) -> Color {
        switch agent.status {
        case .running:   return .green
        case .paused:    return .orange
        case .completed: return .blue
        case .failed:    return .red
        case .idle:      return .secondary
        }
    }

    // MARK: - Media history list

    var mediaHistoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                let active = mediaManager.activeGenerations
                let completed = mediaManager.completedGenerations.filter {
                    searchText.isEmpty || $0.prompt.localizedCaseInsensitiveContains(searchText)
                }

                if !active.isEmpty {
                    listSectionHeader("Aktiva")
                    ForEach(active) { gen in
                        mediaRow(gen, isActive: true)
                    }
                }

                if !completed.isEmpty {
                    listSectionHeader("Historik")
                    ForEach(completed.prefix(30)) { gen in
                        mediaRow(gen, isActive: false)
                    }
                }

                if active.isEmpty && completed.isEmpty {
                    emptyHint(icon: "photo.stack", text: searchText.isEmpty ? "Ingen media" : "Inga träffar")
                }
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func mediaRow(_ gen: MediaGeneration, isActive: Bool) -> some View {
        Button { section = .media } label: {
            HStack(spacing: 8) {
                Image(systemName: gen.type == .image ? "photo" : "video")
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .orange : .secondary.opacity(0.5))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gen.displayTitle)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if isActive {
                            Text(gen.status.displayName)
                                .foregroundColor(.orange)
                        } else {
                            Text(gen.createdAt.relativeString)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.45))
                }
                Spacer()
                if isActive {
                    ProgressView().scaleEffect(0.55)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: - Bottom bar

    var bottomBar: some View {
        VStack(spacing: 0) {
            // Active agent indicator (ChatGPT-style status strip)
            if agentPool.activeCount > 0 {
                HStack(spacing: 7) {
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                    Text("Agent aktiv — \(agentPool.activeCount) jobb")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.04))
            }

            Divider().opacity(0.08)

            // User row (ChatGPT-style)
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Text("E")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Navi")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.primary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusBroadcaster.remoteMacIsOnline ? Color.green : Color.secondary.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(statusBroadcaster.remoteMacIsOnline ? "Mac ansluten" : "Offline")
                            .font(.system(size: 10))
                            .foregroundColor(Color.secondary.opacity(0.6))
                    }
                }

                Spacer()

                Button { showSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13))
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Inställningar")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private func listSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.45))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func emptyHint(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.2))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }
}

// MARK: - Chat conversation row

struct ChatConversationRow: View {
    let conversation: ChatConversation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(conversation.updatedAt.relativeString)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.45))
                        if conversation.totalCostSEK > 0 {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.3))
                            Text(CostCalculator.shared.formatSEK(conversation.totalCostSEK))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.white.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Öppna", action: onSelect)
            Divider()
            Button("Radera", role: .destructive) {
                Task { await ChatManager.shared.delete(conversation) }
            }
        }
    }
}

struct SidebarSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

// MARK: - ProjectRow

struct ProjectRow: View {
    let project: NaviProject
    @Binding var selectedProject: NaviProject?
    @StateObject private var agentPool = AgentPool.shared

    private var isSelected: Bool { selectedProject?.id == project.id }
    private var agent: ProjectAgent? { agentPool.agents[project.id] }
    private var isRunning: Bool { agent?.isRunning ?? false }

    var body: some View {
        Button { selectedProject = project } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(project.color.color.opacity(0.85))
                        .frame(width: 9, height: 9)
                    if isRunning {
                        Circle()
                            .stroke(Color.green, lineWidth: 1.5)
                            .frame(width: 13, height: 13)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    if isRunning, let status = agent?.currentStatus, !status.isEmpty {
                        Text(status.prefix(28))
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text(project.modifiedAt.relativeString)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.45))
                    }
                }

                Spacer()
                if isRunning { ProgressView().scaleEffect(0.55) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.white.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Öppna") { selectedProject = project }
            Button(project.isFavorite ? "Ta bort favorit" : "Markera som favorit") {
                var u = project; u.isFavorite.toggle()
                Task { await ProjectStore.shared.save(u) }
            }
            Divider()
            Button("Ta bort", role: .destructive) {
                Task { await ProjectStore.shared.delete(project) }
            }
        }
    }
}

// MARK: - Preview

#Preview("SidebarView") {
    SidebarView(
        selectedProject: .constant(nil),
        showNewProject: .constant(false),
        section: .constant(.pureChat)
    )
    .frame(width: 260, height: 700)
}
