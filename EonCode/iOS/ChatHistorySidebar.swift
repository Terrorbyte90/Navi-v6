#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

// MARK: - iOS Sidebar (Claude iOS-style, context-aware history)

struct ChatHistorySidebar: View {
    @Binding var showSidebar: Bool
    @Binding var showNewProject: Bool
    @Binding var selectedTab: AppTab

    @StateObject private var chatManager = ChatManager.shared
    @StateObject private var projectStore = ProjectStore.shared
    @StateObject private var artifactStore = ArtifactStore.shared
    @StateObject private var statusBroadcaster = DeviceStatusBroadcaster.shared
    @StateObject private var ghManager = GitHubManager.shared
    @StateObject private var mediaManager = MediaGenerationManager.shared

    @State private var searchText = ""
    @State private var showSettings = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.08)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    navShortcuts
                    Divider().opacity(0.06).padding(.vertical, 8)
                    contextualHistory
                }
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)
            Divider().opacity(0.08)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sidebarBackground)
        .ignoresSafeArea(edges: .vertical)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Top bar

    var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    ThinkingOrb(size: 22, isAnimating: false)
                    Text("Navi")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Spacer()
                // New conversation button
                Button {
                    switch selectedTab {
                    case .chat:
                        _ = chatManager.newConversation()
                        showSidebar = false
                    default:
                        break
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .opacity(selectedTab == .chat ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, topSafeArea + 8)
            .padding(.bottom, 10)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.5))
                TextField("Sök", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surfaceHover, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Nav shortcuts

    var navShortcuts: some View {
        VStack(alignment: .leading, spacing: 2) {
            navItem(icon: "bubble.left.and.bubble.right.fill", label: "Chatt", isActive: selectedTab == .chat) {
                selectedTab = .chat; showSidebar = false
            }
            navItem(icon: "terminal.fill", label: "Code", isActive: selectedTab == .code) {
                selectedTab = .code; showSidebar = false
            }
            navItem(icon: "tray.2.fill", label: "Artefakter", isActive: selectedTab == .artifacts,
                    badge: artifactStore.artifacts.isEmpty ? nil : "\(artifactStore.artifacts.count)") {
                selectedTab = .artifacts; showSidebar = false
            }
            navItem(icon: "cpu.fill", label: "Agenter", isActive: selectedTab == .agents,
                    badge: { let n = AutonomousAgentRunner.shared.agents.filter { $0.status.isActive }.count; return n > 0 ? "\(n)" : nil }()) {
                selectedTab = .agents; showSidebar = false
            }
            navItem(
                icon: "arrow.triangle.branch",
                label: "GitHub",
                isActive: selectedTab == .github,
                badge: {
                    if case .authorized = ghManager.authState, !ghManager.repos.isEmpty {
                        return "\(ghManager.repos.count)"
                    }
                    return nil
                }()
            ) {
                selectedTab = .github; showSidebar = false
            }
            navItem(icon: "photo.stack.fill", label: "Media", isActive: selectedTab == .media,
                    badge: { let n = mediaManager.activeGenerations.count; return n > 0 ? "\(n)" : nil }()) {
                selectedTab = .media; showSidebar = false
            }
            navItem(icon: "person.crop.circle.fill", label: "Profil", isActive: selectedTab == .profile) {
                selectedTab = .profile; showSidebar = false
            }
            navItem(icon: "waveform", label: "Röst", isActive: selectedTab == .voice) {
                selectedTab = .voice; showSidebar = false
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: - Context-aware history

    @ViewBuilder
    var contextualHistory: some View {
        switch selectedTab {
        case .chat:
            chatHistory
        case .code:
            codeHistory
        case .artifacts:
            artifactHistory
        case .github:
            githubHistory
        case .agents:
            agentsHistory
        case .media:
            mediaHistory
        case .profile:
            emptyHistoryHint(icon: "person.crop.circle", text: "AI-syntetiserad profil")
        case .voice:
            emptyHistoryHint(icon: "waveform", text: "Text till tal · Ljud · Röstdesign")
        }
    }

    @ViewBuilder
    var codeHistory: some View {
        emptyHistoryHint(icon: "chevron.left.forwardslash.chevron.right.circle", text: "Code-projekt visas här")
    }

    // MARK: - Chat history

    var filteredChats: [ChatConversation] {
        searchText.isEmpty
            ? chatManager.conversations
            : chatManager.conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private enum ChatDateBucket: String {
        case today     = "Idag"
        case yesterday = "Igår"
        case lastWeek  = "Förra 7 dagarna"
        case older     = "Äldre"
    }

    private func dateBucket(for date: Date) -> ChatDateBucket {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return .lastWeek
        }
        return .older
    }

    private var groupedChats: [(ChatDateBucket, [ChatConversation])] {
        let order: [ChatDateBucket] = [.today, .yesterday, .lastWeek, .older]
        var grouped: [ChatDateBucket: [ChatConversation]] = [:]
        for conv in filteredChats {
            let b = dateBucket(for: conv.updatedAt)
            grouped[b, default: []].append(conv)
        }
        return order.compactMap { b in
            guard let convs = grouped[b], !convs.isEmpty else { return nil }
            return (b, convs)
        }
    }

    @ViewBuilder
    var chatHistory: some View {
        if filteredChats.isEmpty {
            if searchText.isEmpty {
                emptyHistoryHint(icon: "bubble.left.and.bubble.right", text: "Inga chattar ännu")
            }
        } else if !searchText.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredChats) { conv in chatRow(conv) }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groupedChats, id: \.0.rawValue) { bucket, convs in
                    sectionHeader(bucket.rawValue)
                    ForEach(convs) { conv in chatRow(conv) }
                }
            }
        }
    }

    @ViewBuilder
    private func chatRow(_ conv: ChatConversation) -> some View {
        let isActive = chatManager.activeConversation?.id == conv.id
        Button {
            chatManager.activeConversation = conv
            selectedTab = .chat
            showSidebar = false
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.title)
                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                        .foregroundColor(.primary.opacity(isActive ? 1.0 : 0.85))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(conv.updatedAt.relativeString)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                        if conv.totalCostSEK > 0 {
                            Text("·").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.3))
                            Text(CostCalculator.shared.formatSEK(conv.totalCostSEK))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.surfaceHover : Color.clear)
            )
            .overlay(
                isActive
                    ? Rectangle()
                        .fill(Color.accentNavi)
                        .frame(width: 2.5)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .frame(maxHeight: .infinity, alignment: .leading)
                    : nil,
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Öppna") {
                chatManager.activeConversation = conv
                selectedTab = .chat
                showSidebar = false
            }
            Divider()
            Button(role: .destructive) {
                Task { await chatManager.delete(conv) }
            } label: { Label("Radera", systemImage: "trash") }
        }
    }

    // MARK: - Agents history

    @ViewBuilder
    var agentsHistory: some View {
        let runner = AutonomousAgentRunner.shared
        if runner.agents.isEmpty {
            emptyHistoryHint(icon: "cpu.fill", text: "Skapa en agent för att börja")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let running = runner.agents.filter { $0.status.isActive }
                    let other   = runner.agents.filter { !$0.status.isActive }
                    if !running.isEmpty {
                        sectionHeader("Aktiva")
                        ForEach(running) { agent in agentHistoryRow(agent) }
                    }
                    if !other.isEmpty {
                        sectionHeader("Övriga")
                        ForEach(other) { agent in agentHistoryRow(agent) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func agentHistoryRow(_ agent: AgentDefinition) -> some View {
        Button { selectedTab = .agents; showSidebar = false } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(agentHistoryColor(agent).opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: agent.status.isActive ? "cpu.fill" : "cpu")
                        .font(.system(size: 11))
                        .foregroundColor(agentHistoryColor(agent))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(agent.currentTaskDescription.isEmpty ? agent.status.displayName : agent.currentTaskDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if agent.status.isActive { ProgressView().scaleEffect(0.6) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func agentHistoryColor(_ agent: AgentDefinition) -> Color {
        switch agent.status {
        case .running:   return NaviTheme.success
        case .paused:    return NaviTheme.warning
        case .completed: return Color(naviHex: "5B8DEF")
        case .failed:    return NaviTheme.error
        case .idle:      return .secondary
        }
    }

    // MARK: - Media history

    @ViewBuilder
    var mediaHistory: some View {
        let active = mediaManager.activeGenerations
        let completed = mediaManager.completedGenerations.filter {
            searchText.isEmpty || $0.prompt.localizedCaseInsensitiveContains(searchText)
        }

        if active.isEmpty && completed.isEmpty {
            emptyHistoryHint(icon: "photo.stack", text: "Ingen media ännu")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !active.isEmpty {
                    sectionHeader("Aktiva")
                    ForEach(active) { gen in
                        Button { selectedTab = .media; showSidebar = false } label: {
                            HStack(spacing: 10) {
                                Image(systemName: gen.type.icon)
                                    .font(.system(size: 13))
                                    .foregroundColor(NaviTheme.warning)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gen.displayTitle)
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(gen.status.displayName)
                                        .font(.system(size: 11))
                                        .foregroundColor(NaviTheme.warning)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                ProgressView().scaleEffect(0.6)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !completed.isEmpty {
                    sectionHeader("Historik")
                    ForEach(completed.prefix(20)) { gen in
                        Button { selectedTab = .media; showSidebar = false } label: {
                            HStack(spacing: 10) {
                                Image(systemName: gen.type.icon)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gen.displayTitle)
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(gen.createdAt.relativeString)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - GitHub history

    var filteredGitHubRepos: [GitHubRepo] {
        let repos = ghManager.repos
        if searchText.isEmpty { return repos }
        return repos.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    var githubHistory: some View {
        if case .notAuthorized = ghManager.authState {
            emptyHistoryHint(icon: "chevron.left.forwardslash.chevron.right",
                             text: "Anslut GitHub i GitHub-vyn")
        } else if ghManager.isLoadingRepos {
            VStack(spacing: 8) {
                ProgressView()
                Text("Hämtar repos…")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else if !filteredGitHubRepos.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Repos")
                ForEach(filteredGitHubRepos) { repo in
                    Button {
                        selectedTab = .github
                        showSidebar = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 10))
                                    Text(repo.currentBranch)
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            emptyHistoryHint(icon: "chevron.left.forwardslash.chevron.right",
                             text: searchText.isEmpty ? "Inga repos" : "Inga träffar")
        }
    }

    // MARK: - Artifact history

    var filteredArtifacts: [Artifact] {
        let all = searchText.isEmpty
            ? Array(artifactStore.artifacts.prefix(20))
            : artifactStore.search(searchText)
        return all
    }

    @ViewBuilder
    var artifactHistory: some View {
        if !filteredArtifacts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Senaste artefakter")
                ForEach(filteredArtifacts) { artifact in
                    Button {
                        selectedTab = .artifacts
                        showSidebar = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: artifact.displayIcon)
                                .font(.system(size: 13))
                                .foregroundColor(artifact.displayColor)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artifact.title)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text("\(artifact.type.displayName) · \(artifact.sizeDescription)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if searchText.isEmpty {
            emptyHistoryHint(icon: "tray.2", text: "Inga artefakter ännu")
        }
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private func emptyHistoryHint(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.25))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func navItem(icon: String, label: String, isActive: Bool, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .accentNavi : .secondary)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.surfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.5))
            .tracking(0.3)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }

    // MARK: - Bottom bar

    var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.06)
            HStack(spacing: 10) {
                // ThinkingOrb avatar
                ThinkingOrb(size: 28, isAnimating: false)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Navi")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusBroadcaster.remoteMacIsOnline ? NaviTheme.success : .secondary.opacity(0.4))
                            .frame(width: 5, height: 5)
                        Text(statusBroadcaster.remoteMacIsOnline
                             ? "Mac ansluten (\(statusBroadcaster.connectionMethod.rawValue))"
                             : "Offline")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }

                Spacer()

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.bottom, bottomSafeArea)
        }
    }

    // MARK: - Safe area helpers

    private var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44
    }

    private var bottomSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }
}

#endif
