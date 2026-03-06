// Mockup3 — "Neon Cyberpunk"
// Dark background with neon-glowing accents. Hot pink, electric blue, neon green. Blade Runner UI.
import SwiftUI

struct Mockup3: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]

    let neonPink = Color(red: 1.0, green: 0.1, blue: 0.5)
    let neonBlue = Color(red: 0.1, green: 0.5, blue: 1.0)
    let neonCyan = Color(red: 0.0, green: 1.0, blue: 0.9)
    let neonGreen = Color(red: 0.2, green: 1.0, blue: 0.3)
    let darkBg = Color(red: 0.05, green: 0.02, blue: 0.1)
    let panelBg = Color(red: 0.08, green: 0.04, blue: 0.14)

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
        ZStack {
            darkBg.ignoresSafeArea()
            VStack(spacing: 0) {
                statusBar
                HStack(spacing: 1) {
                    sidebar.frame(width: 260)
                    mainContent
                }
            }
        }.preferredColorScheme(.dark)
    }

    func neonBorder(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(color, lineWidth: 1)
            .shadow(color: color.opacity(0.6), radius: 6, x: 0, y: 0)
    }

    var statusBar: some View {
        HStack {
            Text("⚡ EONCODE").font(.system(.caption, design: .monospaced)).bold().foregroundStyle(neonPink)
                .shadow(color: neonPink.opacity(0.8), radius: 4)
            Spacer()
            HStack(spacing: 12) {
                Text("HAIKU 4.5").font(.system(.caption2, design: .monospaced)).foregroundStyle(neonCyan)
                    .shadow(color: neonCyan.opacity(0.5), radius: 3)
                Text("142.50 SEK").font(.system(.caption2, design: .monospaced)).foregroundStyle(neonGreen)
                    .shadow(color: neonGreen.opacity(0.5), radius: 3)
                HStack(spacing: 4) {
                    Circle().fill(neonGreen).frame(width: 6, height: 6).shadow(color: neonGreen, radius: 4)
                    Text("MAC").font(.system(.caption2, design: .monospaced)).foregroundStyle(neonGreen)
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .background(panelBg)
            .overlay(Rectangle().fill(neonPink.opacity(0.4)).frame(height: 1).shadow(color: neonPink, radius: 4), alignment: .bottom)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Array(["PRJ", "CHT", "WEB", "SET"].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.system(.caption2, design: .monospaced)).bold()
                            .foregroundStyle(selectedTab == i ? darkBg : neonCyan)
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(selectedTab == i ? neonCyan : .clear)
                            .shadow(color: selectedTab == i ? neonCyan.opacity(0.5) : .clear, radius: 4)
                    }.buttonStyle(.plain)
                }
            }.padding(6)

            Rectangle().fill(neonBlue.opacity(0.3)).frame(height: 1).shadow(color: neonBlue, radius: 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if selectedTab == 0 { projectList }
                    else if selectedTab == 1 { chatListView }
                    else if selectedTab == 2 { neonLabel("// BROWSER MODULE") }
                    else { settingsList }
                }.padding(10)
            }

            Rectangle().fill(neonBlue.opacity(0.3)).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(neonPink).frame(width: 6, height: 6).shadow(color: neonPink, radius: 4)
                    Text("AGENT: BYGGER EON X — 7/12").font(.system(.caption2, design: .monospaced)).foregroundStyle(neonPink)
                }
                Text("SESSION: 2.45 SEK").font(.system(.caption2, design: .monospaced)).foregroundStyle(neonCyan.opacity(0.7))
            }.padding(10)
        }.background(panelBg)
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) } else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    HStack {
                        Text(expandedProjects.contains(name) ? "▼" : "▶").font(.caption2).foregroundStyle(neonPink)
                        Text(name).font(.system(.caption, design: .monospaced)).foregroundStyle(
                            selectedProject == name ? neonPink : neonCyan)
                        Spacer()
                    }.padding(4).background(selectedProject == name ? neonPink.opacity(0.1) : .clear, in: Rectangle())
                        .overlay(selectedProject == name ? neonBorder(neonPink).opacity(0.5) : nil)
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            Text("  ├ " + file).font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(selectedFile == file ? neonGreen : neonCyan.opacity(0.6))
                                .padding(.vertical, 2).padding(.leading, 8)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var chatListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { c in
                Button { selectedTab = 1 } label: {
                    Text("▸ " + c).font(.system(.caption, design: .monospaced)).foregroundStyle(neonCyan)
                        .padding(4).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(neonBorder(neonBlue.opacity(0.3)))
                }.buttonStyle(.plain)
            }
        }
    }
    func neonLabel(_ t: String) -> some View {
        Text(t).font(.system(.caption, design: .monospaced)).foregroundStyle(neonCyan.opacity(0.5)).padding(.top, 20)
    }
    var settingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(["API-NYCKEL", "MODELL", "SYNK", "TEMA"], id: \.self) { s in
                Text("▸ " + s).font(.system(.caption, design: .monospaced)).foregroundStyle(neonCyan)
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
                Text(selectedFile ?? "").font(.system(.caption, design: .monospaced)).foregroundStyle(neonGreen)
                    .shadow(color: neonGreen.opacity(0.5), radius: 2)
                Spacer()
                Text("SWIFT").font(.system(.caption2, design: .monospaced)).foregroundStyle(neonCyan.opacity(0.5))
            }.padding(8).background(panelBg)
                .overlay(Rectangle().fill(neonGreen.opacity(0.3)).frame(height: 1).shadow(color: neonGreen, radius: 2), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text("\(i+1)").font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(neonCyan.opacity(0.3)).frame(width: 30, alignment: .trailing)
                            Text(" ").font(.caption2)
                            cyberpunkSyntax(line)
                        }
                    }
                }.padding(8)
            }.background(darkBg)
        }
    }

    func cyberpunkSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(.caption, design: .monospaced)).foregroundColor(neonPink)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(.caption, design: .monospaced)).foregroundColor(neonGreen)
            } else if w.contains("0.0") {
                result = result + Text(w + " ").font(.system(.caption, design: .monospaced)).foregroundColor(neonCyan)
            } else {
                result = result + Text(w + " ").font(.system(.caption, design: .monospaced)).foregroundColor(neonBlue.opacity(0.8))
            }
        }
        return result
    }

    var chatView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(chatMessages.enumerated()), id: \.0) { _, msg in
                        chatBubble(isUser: msg.0, text: msg.1)
                    }
                }.padding(12)
            }
            Rectangle().fill(neonPink.opacity(0.3)).frame(height: 1).shadow(color: neonPink, radius: 2)
            HStack(spacing: 8) {
                Image(systemName: "photo").foregroundStyle(neonCyan.opacity(0.5))
                TextField("", text: .constant("")).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(neonCyan).padding(8)
                    .overlay(neonBorder(neonBlue.opacity(0.4)))
                Button { } label: {
                    Text("SEND").font(.system(.caption, design: .monospaced)).bold().foregroundStyle(darkBg)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(neonPink).shadow(color: neonPink.opacity(0.6), radius: 6)
                }.buttonStyle(.plain)
            }.padding(8).background(panelBg)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "YOU" : "EONCODE").font(.system(.caption2, design: .monospaced)).bold()
                    .foregroundStyle(isUser ? neonPink : neonCyan)
                    .shadow(color: isUser ? neonPink.opacity(0.5) : neonCyan.opacity(0.5), radius: 3)
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(.caption2, design: .monospaced)).foregroundStyle(neonGreen.opacity(0.9))
                            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                            .background(darkBg).overlay(neonBorder(neonGreen.opacity(0.3)))
                    } else if !part.isEmpty {
                        Text(part).font(.system(.caption, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }.padding(8)
                .background(isUser ? neonPink.opacity(0.08) : neonBlue.opacity(0.06))
                .overlay(neonBorder(isUser ? neonPink.opacity(0.4) : neonBlue.opacity(0.3)))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    var browserView: some View {
        VStack {
            HStack {
                TextField("", text: .constant("https://developer.apple.com"))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(neonCyan)
                    .padding(6).overlay(neonBorder(neonBlue.opacity(0.4)))
            }.padding(12)
            Spacer()
            Text("// BROWSER PLACEHOLDER").font(.system(.title3, design: .monospaced)).foregroundStyle(neonCyan.opacity(0.3))
            Spacer()
        }.background(darkBg)
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("SETTINGS").font(.system(.title3, design: .monospaced)).foregroundStyle(neonPink)
                    .shadow(color: neonPink.opacity(0.5), radius: 4)
                ForEach(["API-nyckel: ●●●●●", "Modell: Haiku 4.5", "Synk: iCloud", "Tema: Neon Cyberpunk"], id: \.self) { s in
                    Text(s).font(.system(.caption, design: .monospaced)).foregroundStyle(neonCyan)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(neonBorder(neonBlue.opacity(0.3)))
                }
            }.padding(16)
        }.background(darkBg)
    }

    var welcomeView: some View {
        VStack(spacing: 12) {
            Text("⚡ EONCODE").font(.system(.largeTitle, design: .monospaced)).bold()
                .foregroundStyle(neonPink).shadow(color: neonPink.opacity(0.8), radius: 8)
            Text("SELECT A PROJECT TO BEGIN").font(.system(.caption, design: .monospaced))
                .foregroundStyle(neonCyan.opacity(0.5))
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(darkBg)
    }
}

#Preview { Mockup3() }
