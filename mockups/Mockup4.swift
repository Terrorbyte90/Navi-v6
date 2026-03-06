// Mockup4 — "Paper & Ink"
// Minimalist, paper-like. Light textured background, black text, thin lines, serif headers. Notion/Obsidian clean.
import SwiftUI

struct Mockup4: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]

    let ink = Color(red: 0.15, green: 0.12, blue: 0.1)
    let paper = Color(red: 0.97, green: 0.95, blue: 0.92)
    let paperDark = Color(red: 0.94, green: 0.91, blue: 0.87)
    let accent = Color(red: 0.6, green: 0.3, blue: 0.15)

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

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            HStack(spacing: 0) {
                sidebar.frame(width: 250)
                Rectangle().fill(ink.opacity(0.15)).frame(width: 0.5)
                mainContent
            }
        }
        .background(paper)
        .preferredColorScheme(.light)
    }

    var statusBar: some View {
        HStack {
            Text("EonCode").font(.system(.subheadline, design: .serif)).italic().foregroundStyle(ink)
            Spacer()
            HStack(spacing: 16) {
                Text("Haiku 4.5").font(.system(.caption, design: .serif)).foregroundStyle(ink.opacity(0.5))
                Text("Saldo: 142.50 SEK").font(.system(.caption, design: .serif)).foregroundStyle(ink.opacity(0.5))
                HStack(spacing: 4) {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text("Mac Online").font(.system(.caption, design: .serif)).foregroundStyle(ink.opacity(0.5))
                }
            }
        }.padding(.horizontal, 20).padding(.vertical, 10)
            .overlay(Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5), alignment: .bottom)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            // Tabs
            HStack(spacing: 0) {
                ForEach(Array(["Projekt", "Chatt", "Webb", "Inst."].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.system(.caption, design: .serif))
                            .foregroundStyle(selectedTab == i ? accent : ink.opacity(0.4))
                            .padding(.vertical, 8).frame(maxWidth: .infinity)
                            .overlay(selectedTab == i ?
                                Rectangle().fill(accent).frame(height: 1.5) : nil, alignment: .bottom)
                    }.buttonStyle(.plain)
                }
            }
            Rectangle().fill(ink.opacity(0.1)).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if selectedTab == 0 { projectList }
                    else if selectedTab == 1 { chatListView }
                    else if selectedTab == 2 { Text("Webbläsare").font(.system(.caption, design: .serif)).foregroundStyle(ink.opacity(0.4)).padding(.top, 30) }
                    else { settingsList }
                }.padding(16)
            }

            Rectangle().fill(ink.opacity(0.1)).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent: Bygger Eon X — Steg 7/12").font(.system(.caption2, design: .serif)).foregroundStyle(ink.opacity(0.5))
                Text("Kostnad: 2.45 SEK").font(.system(.caption2, design: .serif)).foregroundStyle(ink.opacity(0.35))
            }.padding(16)
        }.background(paperDark)
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) } else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    HStack(spacing: 6) {
                        Text(expandedProjects.contains(name) ? "▾" : "▸").font(.caption2).foregroundStyle(ink.opacity(0.3))
                        Text(name).font(.system(.callout, design: .serif))
                            .foregroundStyle(selectedProject == name ? accent : ink)
                    }.padding(.vertical, 3)
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            Text(file).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(selectedFile == file ? accent : ink.opacity(0.55))
                                .padding(.leading, 20).padding(.vertical, 1)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var chatListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Konversationer").font(.system(.caption, design: .serif)).italic().foregroundStyle(ink.opacity(0.4))
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { c in
                Button { selectedTab = 1 } label: {
                    Text(c).font(.system(.caption, design: .serif)).foregroundStyle(ink.opacity(0.7))
                        .padding(.vertical, 4)
                        .overlay(Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5), alignment: .bottom)
                }.buttonStyle(.plain)
            }
        }
    }
    var settingsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inställningar").font(.system(.subheadline, design: .serif)).italic()
            ForEach(["API-nyckel", "Modell", "Synkronisering", "Utseende"], id: \.self) { s in
                Text(s).font(.system(.caption, design: .serif)).foregroundStyle(ink.opacity(0.6))
                    .overlay(Rectangle().fill(ink.opacity(0.06)).frame(height: 0.5), alignment: .bottom)
            }
        }
    }

    @ViewBuilder var mainContent: some View {
        if selectedTab == 1 { chatView }
        else if selectedTab == 2 { browserView }
        else if selectedTab == 3 { settingsView }
        else if selectedFile != nil { editorView }
        else { welcomeView }
    }

    var editorView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedFile ?? "").font(.system(.caption, design: .monospaced)).foregroundStyle(ink.opacity(0.6))
                Spacer()
                Text("Swift").font(.system(.caption2, design: .serif)).italic().foregroundStyle(ink.opacity(0.3))
            }.padding(.horizontal, 20).padding(.vertical, 8)
                .overlay(Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 16) {
                            Text("\(i + 1)").font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(ink.opacity(0.2)).frame(width: 24, alignment: .trailing)
                            paperSyntax(line)
                        }.padding(.vertical, 2)
                    }
                }.padding(20)
            }.background(paper)
        }
    }

    func paperSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).bold().foregroundColor(accent)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).italic().foregroundColor(ink.opacity(0.7))
            } else {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(ink.opacity(0.8))
            }
        }
        return result
    }

    var chatView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Array(chatMessages.enumerated()), id: \.0) { _, msg in
                        chatBubble(isUser: msg.0, text: msg.1)
                    }
                }.padding(20)
            }
            Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5)
            HStack(spacing: 10) {
                TextField("Skriv ett meddelande…", text: .constant(""))
                    .font(.system(.callout, design: .serif))
                    .textFieldStyle(.plain).padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ink.opacity(0.15), lineWidth: 0.5))
                Button { } label: {
                    Text("Skicka").font(.system(.caption, design: .serif)).foregroundStyle(accent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(accent.opacity(0.5), lineWidth: 0.5))
                }.buttonStyle(.plain)
            }.padding(16).background(paperDark)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack(alignment: .top) {
            if !isUser {
                Text("E").font(.system(.caption, design: .serif)).bold()
                    .foregroundStyle(.white).frame(width: 24, height: 24)
                    .background(accent, in: Circle())
            }
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(.caption, design: .monospaced)).foregroundStyle(ink.opacity(0.7))
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(paperDark, in: RoundedRectangle(cornerRadius: 3))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ink.opacity(0.08), lineWidth: 0.5))
                    } else if !part.isEmpty {
                        Text(part).font(.system(.callout, design: .serif)).foregroundStyle(ink.opacity(0.85))
                    }
                }
            }.padding(12)
                .background(isUser ? accent.opacity(0.05) : paper, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ink.opacity(isUser ? 0.1 : 0.06), lineWidth: 0.5))
            if !isUser { Spacer(minLength: 60) }
        }
    }

    var browserView: some View {
        VStack {
            HStack {
                TextField("", text: .constant("https://developer.apple.com"))
                    .font(.system(.caption, design: .monospaced)).padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ink.opacity(0.15)))
            }.padding(16)
            Spacer()
            Text("Webbläsare").font(.system(.title3, design: .serif)).italic().foregroundStyle(ink.opacity(0.2))
            Spacer()
        }
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inställningar").font(.system(.title2, design: .serif)).italic().foregroundStyle(ink)
                ForEach(["API-nyckel: ●●●●●", "Modell: Haiku 4.5", "Synk: iCloud", "Tema: Paper & Ink"], id: \.self) { s in
                    VStack(alignment: .leading) {
                        Text(s).font(.system(.callout, design: .serif)).foregroundStyle(ink.opacity(0.7))
                        Rectangle().fill(ink.opacity(0.06)).frame(height: 0.5)
                    }
                }
            }.padding(24)
        }
    }

    var welcomeView: some View {
        VStack(spacing: 8) {
            Text("EonCode").font(.system(.largeTitle, design: .serif)).italic().foregroundStyle(ink.opacity(0.3))
            Text("Välj ett projekt för att börja").font(.system(.callout, design: .serif)).foregroundStyle(ink.opacity(0.2))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview { Mockup4() }
