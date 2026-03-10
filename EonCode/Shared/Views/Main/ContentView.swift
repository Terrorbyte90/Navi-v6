import SwiftUI

enum AppSection: String, Hashable { case pureChat, code, artifacts, github, agents, media, profile, voice }

struct ContentView: View {
    @StateObject private var projectStore = ProjectStore.shared
    @StateObject private var agentPool = AgentPool.shared
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var statusBroadcaster = DeviceStatusBroadcaster.shared

    @State private var showSettings = false
    @State private var showNewProject = false
    @State private var selectedTab: AppTab = .chat
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var macSection: AppSection = .pureChat

    var activeProject: NaviProject? { projectStore.activeProject }
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
            NaviOrchestrator.shared.setActiveView(macSection)
            NaviOrchestrator.shared.setActiveProject(activeProject)
        }
        .onChange(of: macSection) { _, newSection in
            NaviOrchestrator.shared.setActiveView(newSection)
        }
        .onChange(of: activeProject) { _, newProject in
            NaviOrchestrator.shared.setActiveProject(newProject)
        }
    }

    @ViewBuilder
    var macDetailView: some View {
        switch macSection {
        case .pureChat:  PureChatView()
        case .code:      CodeView()
        case .artifacts: ArtifactView()
        case .github:    GitHubView()
        case .agents:    AgentView()
        case .media:     MediaView()
        case .profile:   ProfileView()
        case .voice:     VoiceView()
        }
    }
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    @State private var showSidebar = false
    @StateObject private var browserAgent = BrowserAgent.shared

    var iOSLayout: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                iOSTopBar
                iOSMainContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.chatBackground)

            if showSidebar {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { closeSidebar() }
                    .transition(.opacity)
                    .zIndex(10)
            }

            if showSidebar {
                ChatHistorySidebar(
                    showSidebar: $showSidebar,
                    showNewProject: $showNewProject,
                    selectedTab: $selectedTab
                )
                .frame(width: 300)
                .transition(.move(edge: .leading))
                .zIndex(11)
            }
        }
        .animation(NaviTheme.Spring.responsive, value: showSidebar)
        .sheet(isPresented: $showNewProject) { NewProjectView() }
        .onAppear {
            updateViewContext()
            NaviOrchestrator.shared.setActiveView(appSectionForTab(selectedTab))
            NaviOrchestrator.shared.setActiveProject(activeProject)
        }
        .onChange(of: selectedTab) { _, newTab in
            dismissKeyboard()
            updateViewContext()
            NaviOrchestrator.shared.setActiveView(appSectionForTab(newTab))
        }
        .onChange(of: activeProject) { _, newProject in
            NaviOrchestrator.shared.setActiveProject(newProject)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenGitHubProject)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedTab = .github
                showSidebar = false
            }
        }
    }

    private func updateViewContext() {
        let viewName: String
        let viewPurpose: String
        switch selectedTab {
        case .chat:      viewName = "Chatt"; viewPurpose = "Fri konversation utan projektkoppling."
        case .code:      viewName = "Code"; viewPurpose = "Kodning med AI-agenter: spec, research, bygg och push."
        case .artifacts: viewName = "Artefakter"; viewPurpose = "Hantera genererade filer och resurser."
        case .github:    viewName = "GitHub"; viewPurpose = "Hantera repos, PRs och issues."
        case .agents:    viewName = "Agenter"; viewPurpose = "Autonoma agenter som arbetar mot långsiktiga mål."
        case .media:     viewName = "Media"; viewPurpose = "Generera bilder och video via xAI."
        case .profile:   viewName = "Profil"; viewPurpose = "AI-syntetiserad användarprofil baserad på minnen."
        case .voice:     viewName = "Röst"; viewPurpose = "Text-till-tal, ljudgenerering och röstdesign via ElevenLabs."
        }
        MessageBuilder.currentViewContext = "\(viewName) — \(viewPurpose)"
    }

    // MARK: - Top bar — Claude iOS: clean, minimal

    var iOSTopBar: some View {
        HStack(spacing: 0) {
            Button { openSidebar() } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }

            Spacer()

            iOSCenterTitle

            Spacer()

            iOSTrailingButton
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
        .background(Color.chatBackground)
    }

    @ViewBuilder
    var iOSCenterTitle: some View {
        switch selectedTab {
        case .chat:
            ChatNavTitle()
        default:
            HStack(spacing: 5) {
                Text("Navi")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentNavi)
                Text(tabLabel(selectedTab))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func tabLabel(_ tab: AppTab) -> String {
        switch tab {
        case .chat:      return "Chatt"
        case .code:      return "Code"
        case .artifacts: return "Artefakter"
        case .github:    return "GitHub"
        case .agents:    return "Agenter"
        case .media:     return "Media"
        case .profile:   return "Profil"
        case .voice:     return "Röst"
        }
    }

    @ViewBuilder
    var iOSTrailingButton: some View {
        switch selectedTab {
        case .chat:
            Button { _ = ChatManager.shared.newConversation() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary.opacity(0.6))
            }
        default:
            Color.clear.frame(width: 1, height: 1)
        }
    }

    @ViewBuilder
    var iOSMainContent: some View {
        switch selectedTab {
        case .chat:      PureChatView()
        case .code:      CodeView()
        case .artifacts: ArtifactView()
        case .github:    GitHubView()
        case .agents:    AgentView()
        case .media:     MediaView()
        case .profile:   ProfileView()
        case .voice:     VoiceView()
        }
    }

    private func appSectionForTab(_ tab: AppTab) -> AppSection {
        switch tab {
        case .chat:      return .pureChat
        case .code:      return .code
        case .artifacts: return .artifacts
        case .github:    return .github
        case .agents:    return .agents
        case .media:     return .media
        case .profile:   return .profile
        case .voice:     return .voice
        }
    }

    private func openSidebar() {
        dismissKeyboard()
        withAnimation(NaviTheme.Spring.responsive) { showSidebar = true }
    }

    private func closeSidebar() {
        withAnimation(NaviTheme.Spring.responsive) { showSidebar = false }
    }
    #endif
}

// MARK: - Isolated chat nav title (prevents streaming redraws of ContentView)

#if os(iOS)
private struct ChatNavTitle: View {
    @StateObject private var chatMgr = ChatManager.shared

    var body: some View {
        Menu {
            Section("Anthropic") {
                ForEach(ClaudeModel.anthropicModels) { model in modelButton(model) }
            }
            Section("xAI / Grok") {
                ForEach(ClaudeModel.xaiModels) { model in modelButton(model) }
            }
            Section("OpenRouter") {
                ForEach(ClaudeModel.openRouterModels) { model in modelButton(model) }
            }
        } label: {
            HStack(spacing: 5) {
                Text("Navi")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentNavi)
                Text(chatMgr.activeConversation?.model.displayName ?? "Claude")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func modelButton(_ model: ClaudeModel) -> some View {
        let hasKey = Self.hasAPIKey(for: model)
        Button {
            if let conv = chatMgr.activeConversation {
                chatMgr.updateModel(model, for: conv.id)
            } else {
                _ = chatMgr.newConversation(model: model)
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text(model.displayName)
                        if !hasKey {
                            Image(systemName: "key.slash")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                    }
                    Text(hasKey ? model.description : "Saknar API-nyckel")
                        .font(.caption)
                        .foregroundColor(hasKey ? .secondary : .orange)
                }
                Spacer()
                if model == chatMgr.activeConversation?.model {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private static func hasAPIKey(for model: ClaudeModel) -> Bool {
        switch model.provider {
        case .anthropic:  return KeychainManager.shared.anthropicAPIKey?.isEmpty == false
        case .xai:        return KeychainManager.shared.xaiAPIKey?.isEmpty == false
        case .openRouter:  return KeychainManager.shared.openRouterAPIKey?.isEmpty == false
        }
    }
}
#endif

// MARK: - Tabs

enum AppTab: Int, Hashable {
    case chat, code, artifacts, github, agents, media, profile, voice
}

// MARK: - macOS Main View

enum MacEditorTab: Int, Hashable { case editor, agents, versions }

#if os(macOS)
struct MacMainView: View {
    let project: NaviProject
    @ObservedObject var agent: ProjectAgent

    @State private var macEditorTab: MacEditorTab = .editor
    @State private var selectedNode: FileNode?
    @State private var fileContent = ""

    var body: some View {
        VStack(spacing: 0) {
            macProjectTopBar
            Divider().opacity(0.12)
            HSplitView {
                VStack(spacing: 0) {
                    switch macEditorTab {
                    case .editor:
                        HSplitView {
                            FileTreeView(project: project, selectedNode: $selectedNode)
                                .frame(minWidth: 160, maxWidth: 260)
                            editorPane
                        }
                    case .agents:
                        AgentStatusView(agent: agent)
                    case .versions:
                        ProjectVersionsPanel(project: project)
                    }
                }
                .frame(minWidth: 380)

                ChatView(agent: agent)
                    .frame(minWidth: 300, maxWidth: 480)
            }
        }
        .background(Color.chatBackground)
    }

    var macProjectTopBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(project.color.color).frame(width: 9, height: 9)
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Spacer()
            HStack(spacing: 2) {
                MacTabPill(title: "Filer", icon: "folder", tab: .editor, selected: $macEditorTab)
                MacTabPill(title: "Agent", icon: "gearshape.2", tab: .agents, selected: $macEditorTab)
                MacTabPill(title: "Versioner", icon: "clock.arrow.circlepath", tab: .versions, selected: $macEditorTab)
            }
            .padding(3)
            .background(Color.white.opacity(0.06))
            .cornerRadius(9)

            if agent.isRunning {
                HStack(spacing: 5) {
                    ProgressView().scaleEffect(0.6)
                    Text(agent.currentStatus.prefix(30))
                        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
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
                    .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.2))
                Text("Välj en fil att redigera")
                    .font(.system(size: 13)).foregroundColor(.secondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MacTabPill: View {
    let title: String; let icon: String; let tab: MacEditorTab
    @Binding var selected: MacEditorTab
    var isSelected: Bool { selected == tab }

    var body: some View {
        Button { selected = tab } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Color.white.opacity(0.08) : Color.clear))
            .foregroundColor(isSelected ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}

struct TabButton: View {
    let title: String; let icon: String; let tab: MacEditorTab
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
    let project: NaviProject
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
                .onAppear { fileContent = (try? String(contentsOfFile: node.path)) ?? "" }
            } else {
                VStack {
                    Image(systemName: "doc.text").font(.system(size: 48)).foregroundColor(.secondary.opacity(0.3))
                    Text("Välj en fil").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(selectedNode?.name ?? project.name)
    }
}

struct HSplitOrStack<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder let content: () -> Content
    var body: some View {
        if sizeClass == .regular { HStack(spacing: 0) { content() } }
        else { content() }
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
            VStack(spacing: 12) {
                ThinkingOrb(size: 72, isAnimating: false)
                Text("Navi")
                    .font(.system(size: 32, weight: .bold))
                Text("AI-driven kodningsagent")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            if store.projects.isEmpty {
                VStack(spacing: 16) {
                    GlassButton("Skapa nytt projekt", icon: "plus", isPrimary: true) { showNewProject = true }
                    Text("Eller öppna ett befintligt projekt från sidopanelen")
                        .font(.system(size: 13)).foregroundColor(.secondary.opacity(0.6))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Senaste projekt")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    ForEach(store.projects.prefix(5)) { project in
                        Button { store.activeProject = project } label: {
                            HStack {
                                Circle().fill(project.color.color).frame(width: 10, height: 10)
                                Text(project.name).font(.system(size: 14))
                                Spacer()
                                Text(project.modifiedAt.relativeString).font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.surfaceHover))
                        }
                        .buttonStyle(.plain)
                    }
                    GlassButton("Nytt projekt", icon: "plus") { showNewProject = true }
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
                    Text("Projekttyp").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                    Picker("Typ", selection: $projectType) {
                        ForEach(projectTypes, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Spara i iCloud Drive", isOn: $useICloud).toggleStyle(.switch)
                Spacer()
                GlassButton("Skapa projekt", icon: "plus", isPrimary: true) { Task { await createProject() } }
                    .disabled(name.isBlank || isCreating)
            }
            .padding()
            .navigationTitle("Nytt projekt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } } }
            #else
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } } }
            #endif
        }
        .background(Color.chatBackground)
    }

    private func createProject() async {
        isCreating = true
        defer { isCreating = false }
        let baseURL: URL
        if useICloud, let icloudRoot = iCloudSyncEngine.shared.projectsRoot {
            baseURL = icloudRoot
        } else {
            #if os(macOS)
            baseURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Navi/Projects")
            #else
            baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Navi/Projects")
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

// MARK: - ProjectVersionsPanel

struct ProjectVersionsPanel: View {
    let project: NaviProject
    @StateObject private var store = VersionStore.shared
    @State private var selectedVersion: ProjectVersion?
    private var versions: [ProjectVersion] { store.versionsForProject(project.id).reversed() }

    var body: some View {
        #if os(macOS)
        HSplitView {
            versionList.frame(minWidth: 220, maxWidth: 280)
            versionDetail
        }
        .onAppear { Task { await store.loadVersions(for: project) } }
        #else
        NavigationStack {
            versionList
                .navigationTitle("Versioner")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: ProjectVersion.self) { v in VersionDetailPane(version: v, project: project) }
        }
        .onAppear { Task { await store.loadVersions(for: project) } }
        #endif
    }

    var versionList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 12)).foregroundColor(.secondary)
                Text("Versionshistorik").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(versions.count) snapshots").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider().opacity(0.1)
            if versions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark").font(.system(size: 32)).foregroundColor(.secondary.opacity(0.2))
                    Text("Inga versioner sparade").font(.system(size: 13)).foregroundColor(.secondary.opacity(0.4))
                    Text("Versioner skapas automatiskt av agenten.").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.3)).multilineTextAlignment(.center)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(versions) { version in
                            #if os(macOS)
                            VersionRow(version: version, isSelected: selectedVersion?.id == version.id) { selectedVersion = version }
                            #else
                            NavigationLink(value: version) { VersionRow(version: version, isSelected: false) {} }.buttonStyle(.plain)
                            #endif
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var versionDetail: some View {
        if let v = selectedVersion { VersionDetailPane(version: v, project: project) }
        else {
            VStack(spacing: 10) {
                Image(systemName: "arrow.left").font(.system(size: 28)).foregroundColor(.secondary.opacity(0.15))
                Text("Välj en version").font(.system(size: 13)).foregroundColor(.secondary.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct VersionRow: View {
    let version: ProjectVersion; let isSelected: Bool; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: version.isAutoSnapshot ? "clock" : "bookmark.fill")
                    .font(.system(size: 11))
                    .foregroundColor(version.isAutoSnapshot ? .secondary.opacity(0.4) : .accentNavi)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(version.displayName).font(.system(size: 12, weight: isSelected ? .semibold : .regular)).foregroundColor(.primary).lineLimit(1)
                    HStack(spacing: 5) {
                        if !version.filesChanged.isEmpty { Text("\(version.filesChanged.count) filer").font(.system(size: 10)).foregroundColor(.secondary.opacity(0.5)) }
                        if !version.author.isEmpty { Text("·").foregroundColor(.secondary.opacity(0.2)); Text(version.author).font(.system(size: 10)).foregroundColor(.secondary.opacity(0.4)).lineLimit(1) }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isSelected ? Color.accentNavi.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

struct VersionDetailPane: View {
    let version: ProjectVersion; let project: NaviProject
    @StateObject private var store = VersionStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: version.isAutoSnapshot ? "clock" : "bookmark.fill").foregroundColor(version.isAutoSnapshot ? .secondary : .accentNavi)
                        Text(version.displayName).font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    if !version.description.isEmpty { Text(version.description).font(.system(size: 13)).foregroundColor(.secondary) }
                    HStack(spacing: 12) {
                        Label(version.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        Label(version.branch, systemImage: "arrow.triangle.branch")
                        if !version.author.isEmpty { Label(version.author, systemImage: "desktopcomputer") }
                    }
                    .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.6))
                }
                .padding(14).background(Color.surfaceHover.opacity(0.5)).cornerRadius(10)

                if !version.filesChanged.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ändrade filer (\(version.filesChanged.count))").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(version.filesChanged.sorted(), id: \.self) { file in
                                HStack(spacing: 6) {
                                    Image(systemName: fileIcon(file)).font(.system(size: 10)).foregroundColor(.secondary.opacity(0.5))
                                    Text(file).font(.system(size: 11, design: .monospaced)).foregroundColor(.primary.opacity(0.8)).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        .padding(10).background(Color.codeBackground).cornerRadius(8)
                    }
                }
                Spacer()
            }
            .padding(14)
        }
    }

    private func fileIcon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "js", "ts": return "doc.text"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        default: return "doc"
        }
    }
}

// MARK: - ThinkingOrb — glass breathing orb (replaces sparkle/star)

struct ThinkingOrb: View {
    var size: CGFloat = 28
    var isAnimating: Bool = true
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentNavi.opacity(0.15), Color.accentNavi.opacity(0.02)],
                        center: .center, startRadius: size * 0.1, endRadius: size * 0.6
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(isAnimating ? 1.0 + 0.08 * sin(phase) : 1.0)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentNavi.opacity(0.6),
                            Color.accentNavi.opacity(0.3),
                            Color(naviHex: "e8a08a").opacity(0.5)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .topLeading, endPoint: .center))
                        .frame(width: size * 0.7, height: size * 0.7)
                        .offset(x: -size * 0.08, y: -size * 0.08)
                )
                .shadow(color: Color.accentNavi.opacity(0.3), radius: size * 0.2)
        }
        .drawingGroup()
        .onChange(of: isAnimating) { _, animating in
            if animating {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    phase = .pi * 2
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { phase = 0 }
            }
        }
        .onAppear {
            guard isAnimating else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }
}
