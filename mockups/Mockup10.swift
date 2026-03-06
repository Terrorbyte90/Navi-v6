// Mockup10 — "macOS Native"
// Looks like a native macOS app. Apple HIG. System colors, system fonts. Toolbar. Professional.
import SwiftUI

struct Mockup10: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]

    let projects: [(String, [String])] = [
        ("Eon X", ["App.swift", "ConsciousnessEngine.swift", "SensorBridge.swift", "Views/MainView.swift"]),
        ("Eon Y", ["CognitiveEngine.swift", "SwedishLLM.swift", "ThoughtSpace.swift"]),
        ("WeatherApp", ["WeatherApp.swift", "Models/Forecast.swift", "Views/HomeView.swift"])
    ]
    let chatMessages: [(Bool, String)] = [
        (true, "Skapa en ny vy som visar medvetandenivån i realtid med en cirkulär gauge"),
        (false, "Jag skapar `ConsciousnessGaugeView.swift` med en cirkulär progress-indikator…\n```swift\nstruct ConsciousnessGaugeView: View {\n    @ObservedObject var engine: ConsciousnessEngine\n    var body: some View {\n        ZStack {\n            Circle().stroke(lineWidth: 12).opacity(0.2)\n            Circle().trim(from: 0, to: engine.awarenessLevel)\n                .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))\n        }\n    }\n}\n```"),
        (true, "Byt färg till gradient från blå till lila baserat på nivån"),
        (false, "Uppdaterat! Jag lade till en `LinearGradient` som interpolerar…\n```swift\n.stroke(\n    AngularGradient(\n        colors: [.blue, .purple, .blue],\n        center: .center\n    ), style: StrokeStyle(lineWidth: 12, lineCap: .round)\n)\n```"),
        (true, "Perfekt. Bygg projektet")
    ]
    let codeContent = "import SwiftUI\n\nstruct ConsciousnessEngine: ObservableObject {\n    @Published var awarenessLevel: Double = 0.0\n    @Published var cognitiveLoad: Double = 0.0\n\n    func processInput(_ input: SensorData) async {\n        let processed = await neuralBridge.forward(input)\n        awarenessLevel = processed.attention\n        cognitiveLoad = processed.complexity\n    }\n}"

    // Platform-adaptive colors
    static var controlBg: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
    static var windowBg: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    static var textBg: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    static var sysPink: Color {
        #if os(macOS)
        Color(nsColor: .systemPink)
        #else
        Color(uiColor: .systemPink)
        #endif
    }
    static var sysCyan: Color {
        #if os(macOS)
        Color(nsColor: .systemCyan)
        #else
        Color(uiColor: .systemCyan)
        #endif
    }
    static var sysBlue: Color {
        #if os(macOS)
        Color(nsColor: .systemBlue)
        #else
        Color(uiColor: .systemBlue)
        #endif
    }

    var body: some View {
        NavigationSplitView {
            nativeSidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            mainContent
        }
    }

    var nativeSidebar: some View {
        List(selection: $selectedTab) {
            Section("Navigation") {
                Button { selectedTab = 0 } label: { Label("Projekt", systemImage: "folder") }
                    .listRowBackground(selectedTab == 0 ? Color.accentColor.opacity(0.15) : nil)
                Button { selectedTab = 1 } label: { Label("Chatt", systemImage: "bubble.left.and.bubble.right") }
                    .listRowBackground(selectedTab == 1 ? Color.accentColor.opacity(0.15) : nil)
                Button { selectedTab = 2 } label: { Label("Webbläsare", systemImage: "globe") }
                    .listRowBackground(selectedTab == 2 ? Color.accentColor.opacity(0.15) : nil)
                Button { selectedTab = 3 } label: { Label("Inställningar", systemImage: "gearshape") }
                    .listRowBackground(selectedTab == 3 ? Color.accentColor.opacity(0.15) : nil)
            }

            if selectedTab == 0 {
                Section("Projekt") {
                    ForEach(projects, id: \.0) { name, files in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedProjects.contains(name) },
                                set: { if $0 { expandedProjects.insert(name) } else { expandedProjects.remove(name) } }
                            )
                        ) {
                            ForEach(files, id: \.self) { file in
                                Button {
                                    selectedFile = file
                                    selectedProject = name
                                    selectedTab = 0
                                } label: {
                                    Label(file, systemImage: "doc.text").font(.callout)
                                }
                                .listRowBackground(selectedFile == file ? Color.accentColor.opacity(0.1) : nil)
                            }
                        } label: {
                            Label(name, systemImage: "folder.fill").font(.callout.weight(.medium))
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.orange)
                        Text("Agent: Bygger Eon X — 7/12").font(.caption)
                    }
                    Text("Kostnad: 2.45 SEK").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.listStyle(.sidebar)
    }

    @ViewBuilder var mainContent: some View {
        VStack(spacing: 0) {
            toolbarBar
            Divider()
            if selectedTab == 1 { chatView }
            else if selectedTab == 2 { browserView }
            else if selectedTab == 3 { settingsView }
            else if selectedFile != nil { editorView }
            else { welcomeView }
        }
    }

    var toolbarBar: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                Text("Projekt").tag(0)
                Text("Chatt").tag(1)
                Text("Webb").tag(2)
            }.pickerStyle(.segmented).frame(width: 240)
            Spacer()
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu").font(.caption)
                    Text("Haiku 4.5").font(.caption)
                }.foregroundStyle(.secondary)
                Text("142.50 SEK").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Mac Online").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 8)
    }

    var editorView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
                    Text(selectedFile ?? "").font(.callout)
                }.padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Self.controlBg, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
                Text("Swift").font(.caption).foregroundStyle(.tertiary)
            }.padding(.horizontal, 12).padding(.vertical, 4).background(Self.windowBg)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text("\(i + 1)").font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary).frame(width: 32, alignment: .trailing)
                            Divider().frame(height: 16).padding(.horizontal, 8)
                            nativeSyntax(line)
                        }.padding(.vertical, 1)
                    }
                }.padding(12)
            }.background(Self.textBg)
        }
    }

    func nativeSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(Self.sysPink)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(Self.sysCyan)
            } else if w.contains("0.0") {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(Self.sysBlue)
            } else {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(.primary)
            }
        }
        return result
    }

    var chatView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(chatMessages.enumerated()), id: \.0) { _, msg in
                        chatBubble(isUser: msg.0, text: msg.1)
                    }
                }.padding(16)
            }
            Divider()
            HStack(spacing: 8) {
                Button { } label: {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }.buttonStyle(.borderless)
                TextField("Skriv ett meddelande…", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                Button { } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title3)
                }.buttonStyle(.borderless)
            }.padding(12)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                Image(systemName: "brain.head.profile").font(.caption)
                    .foregroundStyle(.white).frame(width: 26, height: 26)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
            }
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(.caption, design: .monospaced))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Self.controlBg, in: RoundedRectangle(cornerRadius: 6))
                    } else if !part.isEmpty {
                        Text(part).font(.callout)
                    }
                }
            }.padding(10)
                .background(
                    isUser ? Color.accentColor.opacity(0.1) : Self.controlBg.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            if !isUser { Spacer(minLength: 60) }
        }
    }

    var browserView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Button { } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                Button { } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                TextField("", text: .constant("https://developer.apple.com"))
                    .textFieldStyle(.roundedBorder)
            }.padding(8)
            Divider()
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "globe").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text("Webbläsare").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    var settingsView: some View {
        Form {
            Section("Konto") {
                LabeledContent("API-nyckel") { Text("●●●●●●●●").foregroundStyle(.secondary) }
                LabeledContent("Saldo") { Text("142.50 SEK") }
            }
            Section("Modell") {
                Picker("Aktiv modell", selection: .constant(0)) {
                    Text("Haiku 4.5").tag(0)
                    Text("Sonnet 4.5").tag(1)
                    Text("Opus 4.6").tag(2)
                }
            }
            Section("Synkronisering") {
                Toggle("iCloud Sync", isOn: .constant(true))
                Toggle("Bonjour P2P", isOn: .constant(false))
            }
            Section("Utseende") {
                LabeledContent("Tema") { Text("macOS Native") }
            }
        }.formStyle(.grouped)
    }

    var welcomeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("Välkommen till EonCode").font(.title3)
            Text("Välj ett projekt i sidofältet för att börja.").font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview { Mockup10() }
