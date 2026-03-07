#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

// MARK: - iOS Sidebar (ChatGPT-style, context-aware history)

struct ChatHistorySidebar: View {
    @Binding var showSidebar: Bool
    @Binding var showNewProject: Bool
    @Binding var selectedTab: AppTab

    @StateObject private var chatManager = ChatManager.shared
    @StateObject private var planManager = PlanManager.shared
    @StateObject private var projectStore = ProjectStore.shared
    @StateObject private var artifactStore = ArtifactStore.shared
    @StateObject private var statusBroadcaster = DeviceStatusBroadcaster.shared
    @StateObject private var ghManager = GitHubManager.shared
    @StateObject private var agentPool = AgentPool.shared

    @State private var searchText = ""
    @State private var showSettings = false
    @State private var showOpenProject = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    navShortcuts
                    Divider().opacity(0.08).padding(.vertical, 8)
                    contextualHistory
                }
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)
            Divider().opacity(0.1)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sidebarBackground)
        .ignoresSafeArea(edges: .vertical)   // let topBar/bottomBar handle safe area manually
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showOpenProject) {
            iCloudProjectPicker { url in openProjectFromURL(url) }
        }
    }

    // MARK: - Top bar (Mockup11 / ChatGPT-style)

    var topBar: some View {
        VStack(spacing: 0) {
            // App name row + new item
            HStack {
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.primary)
                }
                Spacer()
                // New item button — context-aware
                Button {
                    switch selectedTab {
                    case .chat:
                        _ = chatManager.newConversation()
                        showSidebar = false
                    case .plan:
                        _ = planManager.newPlan()
                        showSidebar = false
                    case .project:
                        if let activeProject = projectStore.activeProject {
                            let agent = agentPool.agent(for: activeProject)
                            agent.newConversation()
                        }
                        showSidebar = false
                    default:
                        break
                    }
                } label: {
                    Image(systemName: newItemIcon)
                        .font(.system(size: 16))
                        .foregroundColor(Color.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .opacity(selectedTab == .chat || selectedTab == .plan || selectedTab == .project ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, topSafeArea + 8)
            .padding(.bottom, 10)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(Color.secondary.opacity(0.6))
                TextField("Sök", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundColor(Color.primary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.secondary.opacity(0.6))
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surfaceHover, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private var newItemIcon: String {
        switch selectedTab {
        case .plan: return "map.badge.plus"
        default:    return "square.and.pencil"
        }
    }

    // MARK: - Nav shortcuts

    var navShortcuts: some View {
        VStack(alignment: .leading, spacing: 2) {
            navItem(icon: "bubble.left.and.bubble.right.fill", label: "Chatt", isActive: selectedTab == .chat) {
                selectedTab = .chat; showSidebar = false
            }
            navItem(icon: "folder.fill", label: "Projekt", isActive: selectedTab == .project) {
                selectedTab = .project; showSidebar = false
            }
            navItem(icon: "map.fill", label: "Planera", isActive: selectedTab == .plan) {
                selectedTab = .plan; showSidebar = false
            }
            navItem(icon: "globe", label: "Webb", isActive: selectedTab == .browser) {
                selectedTab = .browser; showSidebar = false
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
                icon: "chevron.left.forwardslash.chevron.right",
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

            Divider().opacity(0.08).padding(.vertical, 4)

            navItem(icon: "plus.rectangle.on.folder", label: "Nytt projekt", isActive: false) {
                showSidebar = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showNewProject = true }
            }
            navItem(icon: "folder.badge.plus", label: "Öppna från iCloud", isActive: false) {
                showOpenProject = true
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
        case .project:
            projectHistory
        case .plan:
            planHistory
        case .browser:
            browserHistory
        case .artifacts:
            artifactHistory
        case .github:
            githubHistory
        case .agents:
            agentsHistory
        }
    }

    // MARK: - Chat history

    var filteredChats: [ChatConversation] {
        searchText.isEmpty
            ? chatManager.conversations
            : chatManager.conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    var chatHistory: some View {
        if !filteredChats.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Chattar")
                ForEach(filteredChats) { conv in
                    chatRow(conv)
                }
            }
        } else if searchText.isEmpty {
            emptyHistoryHint(icon: "bubble.left.and.bubble.right", text: "Inga chattar ännu")
        }
    }

    @ViewBuilder
    private func chatRow(_ conv: ChatConversation) -> some View {
        Button {
            chatManager.activeConversation = conv
            selectedTab = .chat
            showSidebar = false
        } label: {
            historyRowContent(
                title: conv.title,
                subtitle: "\(conv.messages.count) meddelanden",
                isActive: chatManager.activeConversation?.id == conv.id
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await chatManager.delete(conv) }
            } label: { Label("Radera", systemImage: "trash") }
        }
    }

    // MARK: - Project history

    var filteredProjects: [EonProject] {
        searchText.isEmpty
            ? projectStore.projects
            : projectStore.projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    var projectHistory: some View {
        if !filteredProjects.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Projekt")
                ForEach(filteredProjects) { project in
                    projectRow(project)
                }

                // Show conversation history for the active project
                if let activeProject = projectStore.activeProject {
                    let agent = agentPool.agents[activeProject.id]
                    let convHistory = agent?.conversationHistory ?? []
                    let filteredConvs = searchText.isEmpty
                        ? convHistory
                        : convHistory.filter { $0.title.localizedCaseInsensitiveContains(searchText) }

                    if !filteredConvs.isEmpty {
                        sectionHeader("Konversationer")
                        ForEach(filteredConvs) { conv in
                            conversationRow(conv, agent: agent)
                        }
                    }
                }
            }
        } else if searchText.isEmpty {
            emptyHistoryHint(icon: "folder", text: "Inga projekt ännu")
        }
    }

    @ViewBuilder
    private func conversationRow(_ conv: Conversation, agent: ProjectAgent?) -> some View {
        Button {
            agent?.switchToConversation(conv)
            selectedTab = .project
            showSidebar = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.title)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(conv.messages.count) meddelanden · \(conv.modifiedAt.relativeString)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if agent?.conversation.id == conv.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                agent?.conversation.id == conv.id
                    ? Color.white.opacity(0.08) : Color.clear
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                agent?.newConversation()
            } label: { Label("Ny konversation", systemImage: "plus.bubble") }
            Divider()
            Button(role: .destructive) {
                Task { await ConversationStore.shared.delete(conv) }
            } label: { Label("Radera", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: EonProject) -> some View {
        Button {
            projectStore.activeProject = project
            selectedTab = .project
            showSidebar = false
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(project.color.color)
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if projectStore.activeProject?.id == project.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                projectStore.activeProject?.id == project.id
                    ? Color.white.opacity(0.08) : Color.clear
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await projectStore.delete(project) }
            } label: { Label("Ta bort", systemImage: "trash") }
        }
    }

    // MARK: - Plan history

    var filteredPlans: [ProjectPlan] {
        searchText.isEmpty
            ? planManager.plans
            : planManager.plans.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    var planHistory: some View {
        if !filteredPlans.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Group by status
                let active = filteredPlans.filter { $0.status == .active }
                let drafts = filteredPlans.filter { $0.status == .draft }
                let completed = filteredPlans.filter { $0.status == .completed }
                let archived = filteredPlans.filter { $0.status == .archived }

                if !active.isEmpty {
                    sectionHeader("Aktiva")
                    ForEach(active) { plan in planRow(plan) }
                }
                if !drafts.isEmpty {
                    sectionHeader("Utkast")
                    ForEach(drafts) { plan in planRow(plan) }
                }
                if !completed.isEmpty {
                    sectionHeader("Klara")
                    ForEach(completed) { plan in planRow(plan) }
                }
                if !archived.isEmpty {
                    sectionHeader("Arkiverade")
                    ForEach(archived) { plan in planRow(plan) }
                }
            }
        } else if searchText.isEmpty {
            emptyHistoryHint(icon: "map", text: "Inga planer ännu")
        }
    }

    @ViewBuilder
    private func planRow(_ plan: ProjectPlan) -> some View {
        Button {
            planManager.activePlan = plan
            selectedTab = .plan
            showSidebar = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: plan.status.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !plan.summary.isEmpty {
                        Text(plan.summary)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("\(plan.messages.count) meddelanden · \(plan.updatedAt.relativeString)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if planManager.activePlan?.id == plan.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                planManager.activePlan?.id == plan.id
                    ? Color.white.opacity(0.08) : Color.clear
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { planManager.updateStatus(plan, status: .active) } label: {
                Label("Markera som aktiv", systemImage: "bolt")
            }
            Button { planManager.updateStatus(plan, status: .completed) } label: {
                Label("Markera som klar", systemImage: "checkmark.seal")
            }
            Button { planManager.updateStatus(plan, status: .archived) } label: {
                Label("Arkivera", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                planManager.delete(plan)
            } label: { Label("Radera", systemImage: "trash") }
        }
    }

    // MARK: - Browser history

    @ViewBuilder
    var browserHistory: some View {
        let navEntries = BrowserAgent.shared.log.filter { $0.type == .navigate }
        if navEntries.isEmpty {
            emptyHistoryHint(icon: "globe", text: "Webbläsarhistorik visas här")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(navEntries.reversed()) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.displayText)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Text(entry.timestamp, style: .time)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.top, 8)
            }
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
        case .running:   return .green
        case .paused:    return .orange
        case .completed: return .blue
        case .failed:    return .red
        case .idle:      return .secondary
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

    // MARK: - Artifact history (recent artifacts)

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
    private func historyRowContent(title: String, subtitle: String, isActive: Bool) -> some View {
        Text(title)
            .font(.system(size: 14))
            .foregroundColor(isActive ? Color.primary : Color.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.surfaceHover : Color.clear)
            )
    }

    @ViewBuilder
    private func emptyHistoryHint(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Color.secondary.opacity(0.6).opacity(0.3))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color.secondary.opacity(0.6).opacity(0.5))
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
                    .foregroundColor(isActive ? Color.primary : Color.secondary)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? Color.primary : Color.secondary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.surfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color.secondary.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }

    // MARK: - Bottom bar (Mockup11 / ChatGPT-style user row)

    var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.08)
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
                        Text(statusBroadcaster.remoteMacIsOnline
                             ? "Mac ansluten (\(statusBroadcaster.connectionMethod.rawValue))"
                             : "Offline")
                            .font(.system(size: 10))
                            .foregroundColor(Color.secondary.opacity(0.6))
                    }
                }

                Spacer()

                Button { showSettings = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.bottom, bottomSafeArea)
        }
    }

    // MARK: - Open project from URL

    private func openProjectFromURL(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        var project = EonProject(name: name, rootPath: url.path, iCloudPath: url.path)
        project.localPath = url.path

        Task {
            await projectStore.save(project)
            await MainActor.run {
                projectStore.activeProject = project
                selectedTab = .project
                showSidebar = false
            }
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

// MARK: - iCloud Document Picker

struct iCloudProjectPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

#endif
