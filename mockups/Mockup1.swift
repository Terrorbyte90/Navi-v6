// Mockup1 — "Liquid Glass"
// iOS 26 liquid glass aesthetic. Translucent panels, frosted blur, visionOS-feel.
import SwiftUI

struct Mockup1: View {
    @State private var selectedTab = 0 // 0=Project, 1=Chat, 2=Browser, 3=Settings
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
    let codeContent = """
    import SwiftUI

    struct ConsciousnessEngine: ObservableObject {
        @Published var awarenessLevel: Double = 0.0
        @Published var cognitiveLoad: Double = 0.0

        func processInput(_ input: SensorData) async {
            let processed = await neuralBridge.forward(input)
            awarenessLevel = processed.attention
            cognitiveLoad = processed.complexity
        }
    }
    """

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(colors: [Color(white: 0.92), Color(white: 0.96), Color.white.opacity(0.9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                statusBar
                HStack(spacing: 0) {
                    sidebar.frame(width: 260)
                    mainContent
                }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Status Bar
    var statusBar: some View {
        HStack {
            Text("EonCode").font(.headline).fontWeight(.semibold)
            Spacer()
            HStack(spacing: 16) {
                Label("Haiku 4.5", systemImage: "cpu").font(.caption)
                Text("Saldo: 142.50 SEK").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("Mac Online").font(.caption)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 0))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Sidebar
    var sidebar: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 2) {
                ForEach(Array(["Projekt", "Chatt", "Webb", "Inst."].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.caption).fontWeight(selectedTab == i ? .semibold : .regular)
                            .padding(.vertical, 6).frame(maxWidth: .infinity)
                            .background(selectedTab == i ?
                                AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }.padding(8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if selectedTab == 0 {
                        projectList
                    } else if selectedTab == 1 {
                        chatList
                    } else if selectedTab == 2 {
                        webPlaceholder
                    } else {
                        settingsPlaceholder
                    }
                }.padding(12)
            }

            // Agent status
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                    Text("Agent: Bygger Eon X — Steg 7/12").font(.caption2)
                }
                Text("Kostnad denna session: 2.45 SEK").font(.caption2).foregroundStyle(.secondary)
            }.padding(12)
        }
        .background(.ultraThinMaterial, in: Rectangle())
        .overlay(Divider(), alignment: .trailing)
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) }
                    else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    HStack {
                        Image(systemName: expandedProjects.contains(name) ? "chevron.down" : "chevron.right")
                            .font(.caption2).frame(width: 14)
                        Image(systemName: "folder.fill").foregroundStyle(.blue.opacity(0.7)).font(.caption)
                        Text(name).font(.callout)
                        Spacer()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 6)
                    .background(selectedProject == name ? Color.blue.opacity(0.1) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            HStack {
                                Image(systemName: "doc.text").font(.caption2).foregroundStyle(.secondary)
                                Text(file).font(.caption)
                            }.padding(.leading, 30).padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedFile == file ? Color.blue.opacity(0.08) : .clear,
                                            in: RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var chatList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Konversationer").font(.caption).foregroundStyle(.secondary)
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { c in
                Button { selectedTab = 1 } label: {
                    HStack {
                        Image(systemName: "bubble.left.fill").foregroundStyle(.blue.opacity(0.5))
                        Text(c).font(.callout)
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
    }
    var webPlaceholder: some View {
        VStack { Image(systemName: "globe").font(.largeTitle).foregroundStyle(.secondary); Text("Webbläsare").font(.caption) }.frame(maxWidth: .infinity).padding(.top, 40)
    }
    var settingsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inställningar").font(.headline)
            ForEach(["API-nyckel", "Modellval", "Synkronisering", "Utseende"], id: \.self) { s in
                HStack { Image(systemName: "gearshape"); Text(s) }.font(.callout)
            }
        }
    }

    // MARK: - Main Content
    @ViewBuilder var mainContent: some View {
        VStack(spacing: 0) {
            if selectedTab == 1 {
                chatView
            } else if selectedTab == 2 {
                browserView
            } else if selectedTab == 3 {
                settingsView
            } else if let file = selectedFile {
                editorView(file)
            } else {
                welcomeView
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func editorView(_ file: String) -> some View {
        VStack(spacing: 0) {
            // File tab
            HStack {
                Label(file, systemImage: "doc.text").font(.callout)
                Spacer()
                Text("Swift").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.vertical, 8)
                .background(.ultraThinMaterial).overlay(Divider(), alignment: .bottom)
            // Code
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                            syntaxLine(line)
                        }.padding(.vertical, 1)
                    }
                }.padding(16)
            }.background(Color(white: 0.98))
        }
    }

    func syntaxLine(_ line: String) -> some View {
        let keywords = ["import", "struct", "func", "var", "let", "@Published", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if keywords.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(.purple)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(.blue)
            } else {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(.primary)
            }
        }
        return result
    }

    var chatView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(chatMessages.enumerated()), id: \.0) { _, msg in
                        chatBubble(isUser: msg.0, text: msg.1)
                    }
                }.padding(16)
            }
            // Input
            HStack(spacing: 8) {
                Image(systemName: "photo").foregroundStyle(.secondary)
                TextField("Skriv ett meddelande…", text: .constant(""))
                    .textFieldStyle(.plain).padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                Button { } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(.blue)
                }.buttonStyle(.plain)
            }.padding(12).background(.ultraThinMaterial).overlay(Divider(), alignment: .top)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                Circle().fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                    .frame(width: 28, height: 28).overlay(Text("E").font(.caption).bold().foregroundStyle(.white))
            }
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Parse code blocks
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(.caption, design: .monospaced))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 8))
                    } else if !part.isEmpty {
                        Text(part).font(.callout)
                    }
                }
            }
            .padding(10)
            .background(
                isUser ? AnyShapeStyle(Color.blue.opacity(0.12)) : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
            if !isUser { Spacer(minLength: 60) }
        }
    }

    var browserView: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chevron.left"); Image(systemName: "chevron.right")
                TextField("https://", text: .constant("https://developer.apple.com"))
                    .textFieldStyle(.plain).padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }.padding(.horizontal)
            Spacer()
            Image(systemName: "globe").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Webbläsare (Placeholder)").foregroundStyle(.secondary)
            Spacer()
        }.padding(.top, 12)
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Inställningar").font(.title2).bold()
                ForEach(["API-nyckel (Anthropic)", "Modell: Haiku 4.5", "Synkronisering: iCloud", "Tema: Liquid Glass"], id: \.self) { s in
                    HStack {
                        Text(s).font(.callout)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(20)
        }
    }

    var welcomeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.blue.opacity(0.6))
            Text("Välj ett projekt och en fil").font(.title3).foregroundStyle(.secondary)
            Text("eller starta en chatt").font(.callout).foregroundStyle(.tertiary)
        }
    }
}

#Preview { Mockup1() }
