import SwiftUI

enum AppSection: String, Hashable { case project, pureChat, browser, artifacts, planning, github }

struct ContentView: View {
    @StateObject private var projectStore = ProjectStore.shared
    @StateObject private var agentPool = AgentPool.shared
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var statusBroadcaster = DeviceStatusBroadcaster.shared

    @State private var showSettings = false
    @State private var showNewProject = false
    @State private var selectedTab: AppTab = .chat
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var macSection: AppSection = .project

    var activeProject: EonProject? { projectStore.activeProject }
    var activeAgent: ProjectAgent? {
        guard let project = activeProject else { return nil }
        return agentPool.agent(for: project)
    }

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    var macLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedProject: $projectStore.activeProject,
                showNewProject: $showNewProject,
                section: $macSection
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            macDetailView
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .windowToolbar)
        .sheet(isPresented: $showNewProject) {
            NewProjectView()
        }
        .onAppear {
            BackgroundDaemon.shared.start()
        }
    }

    @ViewBuilder
    var macDetailView: some View {
        switch macSection {
        case .pureChat:
            PureChatView()
        case .browser:
            BrowserView()
        case .artifacts:
            ArtifactView()
        case .planning:
            PlanView()
        case .github:
            GitHubView()
        case .project:
            if let project = activeProject, let agent = activeAgent {
                MacMainView(project: project, agent: agent)
            } else {
                WelcomeView(showNewProject: $showNewProject)
            }
        }
    }
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    @State private var showSidebar = false
    // Reactive chat manager so model name updates live
    @StateObject private var chatMgr = ChatManager.shared
    @StateObject private var planMgr = PlanManager.shared
    @StateObject private var browserAgent = BrowserAgent.shared

    var iOSLayout: some View {
        ZStack(alignment: .leading) {
            // ── Main content ────────────────────────────────────────────────
            VStack(spacing: 0) {
                iOSTopBar
                Divider().opacity(0.12)
                iOSMainContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.chatBackground)

            // ── Dim overlay ─────────────────────────────────────────────────
            if showSidebar {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { closeSidebar() }
                    .transition(.opacity)
                    .zIndex(10)
            }

            // ── Sidebar panel ───────────────────────────────────────────────
            ChatHistorySidebar(
                showSidebar: $showSidebar,
                showNewProject: $showNewProject,
                selectedTab: $selectedTab
            )
            .frame(width: 300)
            .offset(x: showSidebar ? 0 : -300)
            .zIndex(11)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSidebar)
        .sheet(isPresented: $showNewProject) { NewProjectView() }
        .onAppear {
            PeerSyncEngine.shared.startBrowsing()
            updateViewContext()
        }
        .onChange(of: selectedTab) { updateViewContext() }
    }

    private func updateViewContext() {
        let viewName: String
        let viewPurpose: String
        switch selectedTab {
        case .chat:
            viewName = "Chatt"
            viewPurpose = "Fri konversation utan projektkoppling."
        case .project:
            let name = activeProject?.name ?? "inget valt"
            viewName = "Projekt (\(name))"
            viewPurpose = "Kodning och filhantering i projektet."
        case .browser:
            viewName = "Webb"
            viewPurpose = "Webbsurfning och research."
        case .artifacts:
            viewName = "Artefakter"
            viewPurpose = "Hantera genererade filer och resurser."
        case .plan:
            viewName = "Planera"
            viewPurpose = "Skapa och hantera projektplaner."
        case .github:
            viewName = "GitHub"
            viewPurpose = "Hantera repos, PRs och issues."
        }
        MessageBuilder.currentViewContext = "\(viewName) — \(viewPurpose)"
    }

    // MARK: - Top bar

    var iOSTopBar: some View {
        HStack(spacing: 0) {
            // Hamburger
            Button { openSidebar() } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }

            Spacer()

            // Center title / model picker
            iOSCenterTitle

            Spacer()

            // Trailing action
            iOSTrailingButton
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
        .background(Color.chatBackground)
    }

    // MARK: - Center title (reactive)

    @ViewBuilder
    var iOSCenterTitle: some View {
        switch selectedTab {
        case .chat:
            // Model picker — reads from @StateObject so it updates reactively
            Menu {
                ForEach(ClaudeModel.allCases) { model in
                    Button {
                        if let conv = chatMgr.activeConversation,
                           let idx = chatMgr.conversations.firstIndex(where: { $0.id == conv.id }) {
                            chatMgr.conversations[idx].model = model
                            chatMgr.activeConversation?.model = model
                        }
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if model == chatMgr.activeConversation?.model {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(chatMgr.activeConversation?.model.displayName ?? "Claude")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }

        case .project:
            Text(activeProject?.name ?? "Projekt")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

        case .browser:
            Text("Webb")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

        case .artifacts:
            Text("Artefakter")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

        case .plan:
            Text(planMgr.activePlan?.title ?? "Planera")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

        case .github:
            Text("GitHub")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Trailing button

    @ViewBuilder
    var iOSTrailingButton: some View {
        switch selectedTab {
        case .chat:
            Button { _ = chatMgr.newConversation() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
            }

        case .project:
            HStack(spacing: 4) {
                Circle()
                    .fill(statusBroadcaster.remoteMacIsOnline ? Color.green : Color.red.opacity(0.6))
                    .frame(width: 7, height: 7)
                Text(statusBroadcaster.remoteMacIsOnline ? "Mac" : "Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusBroadcaster.remoteMacIsOnline ? .green : .secondary)
            }

        case .browser:
            Circle()
                .fill(browserAgent.status == .working ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

        case .plan:
            Button { _ = planMgr.newPlan() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
            }

        default:
            Color.clear.frame(width: 1, height: 1)
        }
    }

    // MARK: - Main content

    @ViewBuilder
    var iOSMainContent: some View {
        switch selectedTab {
        case .chat:
            PureChatView()
        case .project:
            if let project = activeProject, let agent = activeAgent {
                ChatView(agent: agent)
            } else {
                iOSWelcome
            }
        case .browser:
            BrowserView()
        case .artifacts:
            ArtifactView()
        case .plan:
            PlanView()
        case .github:
            GitHubView()
        }
    }

    // MARK: - Welcome

    var iOSWelcome: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundColor(.accentEon.opacity(0.7))
            VStack(spacing: 8) {
                Text("EonCode")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Välj ett projekt i sidomenyn")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            Button { openSidebar() } label: {
                Label("Öppna sidomenyn", systemImage: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accentEon)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentEon.opacity(0.1))
                    .cornerRadius(12)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }

    // MARK: - Sidebar helpers

    private func openSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showSidebar = true
        }
    }

    private func closeSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showSidebar = false
        }
    }
    #endif
}

// MARK: - Tabs

enum AppTab: Int, Hashable {
    case chat, project, browser, artifacts, plan, github
}

// MARK: - macOS Main View

enum MacEditorTab: Int, Hashable { case editor, agents }

#if os(macOS)
struct MacMainView: View {
    let project: EonProject
    @ObservedObject var agent: ProjectAgent

    @State private var macEditorTab: MacEditorTab = .editor
    @State private var selectedNode: FileNode?
    @State private var fileContent = ""

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar ─────────────────────────────────────────────────────
            macProjectTopBar

            Divider().opacity(0.12)

            // ── Content ──────────────────────────────────────────────────────
            HSplitView {
                // Left: file tree + editor / agent status
                VStack(spacing: 0) {
                    if macEditorTab == .editor {
                        HSplitView {
                            FileTreeView(project: project, selectedNode: $selectedNode)
                                .frame(minWidth: 160, maxWidth: 260)
                            editorPane
                        }
                    } else {
                        AgentStatusView(agent: agent)
                    }
                }
                .frame(minWidth: 380)

                // Right: chat
                ChatView(agent: agent)
                    .frame(minWidth: 300, maxWidth: 480)
            }
        }
        .background(Color.chatBackground)
    }

    var macProjectTopBar: some View {
        HStack(spacing: 12) {
            // Project color dot + name
            HStack(spacing: 7) {
                Circle()
                    .fill(project.color.color)
                    .frame(width: 9, height: 9)
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Editor / Agent tabs
            HStack(spacing: 2) {
                MacTabPill(title: "Filer", icon: "folder", tab: .editor, selected: $macEditorTab)
                MacTabPill(title: "Agent", icon: "gearshape.2", tab: .agents, selected: $macEditorTab)
            }
            .padding(3)
            .background(Color.white.opacity(0.06))
            .cornerRadius(9)

            // Running indicator
            if agent.isRunning {
                HStack(spacing: 5) {
                    ProgressView().scaleEffect(0.6)
                    Text(agent.currentStatus.prefix(30))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    var editorPane: some View {
        if let node = selectedNode, !node.isDirectory {
            CodeEditorView(
                content: $fileContent,
                fileType: node.fileType,
                onSave: { newContent in
                    try? newContent.write(toFile: node.path, atomically: true, encoding: .utf8)
                }
            )
            .onAppear { fileContent = (try? String(contentsOfFile: node.path)) ?? "" }
            .onChange(of: selectedNode?.id) {
                if let n = selectedNode, !n.isDirectory {
                    fileContent = (try? String(contentsOfFile: n.path)) ?? ""
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.2))
                Text("Välj en fil att redigera")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MacTabPill: View {
    let title: String
    let icon: String
    let tab: MacEditorTab
    @Binding var selected: MacEditorTab

    var isSelected: Bool { selected == tab }

    var body: some View {
        Button { selected = tab } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
            .foregroundColor(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// Keep old TabButton for any remaining usages
struct TabButton: View {
    let title: String
    let icon: String
    let tab: MacEditorTab
    @Binding var selected: MacEditorTab

    var isSelected: Bool { selected == tab }

    var body: some View {
        MacTabPill(title: title, icon: icon, tab: tab, selected: $selected)
    }
}
#endif

// MARK: - iOS file tree + editor

#if os(iOS)
struct FileTreeAndEditorView: View {
    let project: EonProject
    @State private var selectedNode: FileNode?
    @State private var fileContent = ""

    var body: some View {
        HSplitOrStack {
            FileTreeView(project: project, selectedNode: $selectedNode)
                .frame(maxWidth: 260)

            if let node = selectedNode, !node.isDirectory {
                CodeEditorView(
                    content: $fileContent,
                    fileType: node.fileType,
                    onSave: { newContent in
                        try? newContent.write(toFile: node.path, atomically: true, encoding: .utf8)
                    }
                )
                .onAppear {
                    fileContent = (try? String(contentsOfFile: node.path)) ?? ""
                }
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Välj en fil")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(selectedNode?.name ?? project.name)
    }
}

// Adaptive layout: split on iPad, stack on iPhone
struct HSplitOrStack<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder let content: () -> Content

    var body: some View {
        if sizeClass == .regular {
            HStack(spacing: 0) { content() }
        } else {
            content()
        }
    }
}
#endif

// MARK: - Welcome View

struct WelcomeView: View {
    @Binding var showNewProject: Bool
    @StateObject private var store = ProjectStore.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundColor(.accentEon)
                Text("EonCode")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("AI-driven kodningsagent")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            if store.projects.isEmpty {
                VStack(spacing: 16) {
                    GlassButton("Skapa nytt projekt", icon: "plus", isPrimary: true) {
                        showNewProject = true
                    }
                    Text("Eller öppna ett befintligt projekt från sidopanelen")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Senaste projekt")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)

                    ForEach(store.projects.prefix(5)) { project in
                        Button {
                            store.activeProject = project
                        } label: {
                            HStack {
                                Circle()
                                    .fill(project.color.color)
                                    .frame(width: 10, height: 10)
                                Text(project.name)
                                    .font(.system(size: 14))
                                Spacer()
                                Text(project.modifiedAt.relativeString)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }

                    GlassButton("Nytt projekt", icon: "plus") {
                        showNewProject = true
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: 400)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }
}

// MARK: - New Project View

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ProjectStore.shared

    @State private var name = ""
    @State private var projectType = "swift"
    @State private var useICloud = true
    @State private var isCreating = false

    let projectTypes = ["swift", "python", "node", "generic"]

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                GlassTextField(placeholder: "Projektnamn", text: $name)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Projekttyp")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Picker("Typ", selection: $projectType) {
                        ForEach(projectTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("Spara i iCloud Drive", isOn: $useICloud)
                    .toggleStyle(.switch)

                Spacer()

                GlassButton("Skapa projekt", icon: "plus", isPrimary: true) {
                    Task { await createProject() }
                }
                .disabled(name.isBlank || isCreating)
            }
            .padding()
            .navigationTitle("Nytt projekt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            #endif
        }
        .background(Color.chatBackground)
        .preferredColorScheme(.dark)
    }

    private func createProject() async {
        isCreating = true
        defer { isCreating = false }

        let baseURL: URL
        if useICloud, let icloudRoot = iCloudSyncEngine.shared.projectsRoot {
            baseURL = icloudRoot
        } else {
            #if os(macOS)
            baseURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("EonCode/Projects")
            #else
            baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("EonCode/Projects")
            #endif
        }

        let project = await store.create(name: name, at: baseURL.appendingPathComponent(name))

        #if os(macOS)
        if let url = project.resolvedURL {
            try? await FileSystemAgent.shared.createNewProject(
                name: name,
                type: FileSystemAgent.ProjectType(rawValue: projectType) ?? .generic,
                at: url.deletingLastPathComponent()
            )
        }
        #endif

        store.activeProject = project
        dismiss()
    }
}

// MARK: - Previews

#Preview("WelcomeView – inga projekt") {
    WelcomeView(showNewProject: .constant(false))
        .preferredColorScheme(.dark)
}

#Preview("WelcomeView – med projekt") {
    let store = ProjectStore.shared
    let p1 = EonProject(name: "EonCode v2", rootPath: "/tmp/eon", color: .blue)
    let p2 = EonProject(name: "Lunaflix iOS", rootPath: "/tmp/luna", color: .purple)
    store.projects = [p1, p2]
    return WelcomeView(showNewProject: .constant(false))
        .preferredColorScheme(.dark)
}

#Preview("NewProjectView") {
    NewProjectView()
        .preferredColorScheme(.dark)
}
