// Mockup2 — "Midnight Terminal"
// Hardcore terminal aesthetic. Black bg, green monospace, sharp edges, blinking cursor.
import SwiftUI

struct Mockup2: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]
    @State private var cursorVisible = true

    let green = Color(red: 0.0, green: 0.9, blue: 0.2)
    let dimGreen = Color(red: 0.0, green: 0.5, blue: 0.1)
    let bg = Color(red: 0.02, green: 0.02, blue: 0.02)
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
            bg.ignoresSafeArea()
            // Scanlines
            Canvas { ctx, size in
                for y in stride(from: 0, to: size.height, by: 3) {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    ctx.fill(Path(rect), with: .color(.black.opacity(0.15)))
                }
            }.ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                statusBar
                HStack(spacing: 0) {
                    sidebar.frame(width: 260)
                    Rectangle().fill(dimGreen.opacity(0.3)).frame(width: 1)
                    mainContent
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in cursorVisible.toggle() } }
    }

    var statusBar: some View {
        HStack {
            Text("EONCODE v2.0").font(.system(.caption, design: .monospaced)).foregroundStyle(green)
            Spacer()
            Text("MODEL: HAIKU-4.5").font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen)
            Text("|").foregroundStyle(dimGreen.opacity(0.5))
            Text("SALDO: 142.50 SEK").font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen)
            Text("|").foregroundStyle(dimGreen.opacity(0.5))
            HStack(spacing: 4) {
                Circle().fill(green).frame(width: 6, height: 6)
                Text("MAC ONLINE").font(.system(.caption, design: .monospaced)).foregroundStyle(green)
            }
        }.padding(.horizontal, 12).padding(.vertical, 6)
            .background(bg).overlay(Rectangle().fill(dimGreen.opacity(0.3)).frame(height: 1), alignment: .bottom)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["PRJ", "CHT", "WEB", "CFG"].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(selectedTab == i ? bg : green)
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                            .background(selectedTab == i ? green : .clear)
                    }.buttonStyle(.plain)
                }
            }
            Rectangle().fill(dimGreen.opacity(0.3)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if selectedTab == 0 { projectList }
                    else if selectedTab == 1 { chatListView }
                    else if selectedTab == 2 { termText("[ BROWSER MODULE ]") }
                    else { settingsListView }
                }.padding(8)
            }

            Rectangle().fill(dimGreen.opacity(0.3)).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("● AGENT: BYGGER EON X — STEG 7/12").font(.system(.caption2, design: .monospaced)).foregroundStyle(green)
                Text("  KOSTNAD: 2.45 SEK").font(.system(.caption2, design: .monospaced)).foregroundStyle(dimGreen)
            }.padding(8)
        }.background(bg)
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) } else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    Text((expandedProjects.contains(name) ? "[-] " : "[+] ") + name.uppercased())
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(selectedProject == name ? bg : green)
                        .padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedProject == name ? green : .clear)
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            Text("  ├─ " + file).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(selectedFile == file ? bg : dimGreen)
                                .padding(.vertical, 1).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedFile == file ? dimGreen : .clear)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var chatListView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CONVERSATIONS:").font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen)
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { c in
                Button { selectedTab = 1 } label: {
                    Text("> " + c).font(.system(.caption, design: .monospaced)).foregroundStyle(green)
                        .padding(.vertical, 1)
                }.buttonStyle(.plain)
            }
        }
    }
    var settingsListView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(["API-NYCKEL", "MODELL", "SYNK", "UTSEENDE"], id: \.self) { s in
                Text("> " + s).font(.system(.caption, design: .monospaced)).foregroundStyle(green).padding(.vertical, 1)
            }
        }
    }
    func termText(_ t: String) -> some View {
        Text(t).font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen).padding(.top, 20)
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
                Text("FILE: \(selectedFile ?? "")").font(.system(.caption, design: .monospaced)).foregroundStyle(green)
                Spacer()
                Text("[SWIFT]").font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen)
            }.padding(8).background(bg).overlay(Rectangle().fill(dimGreen.opacity(0.3)).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text(String(format: "%3d", i + 1)).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(dimGreen.opacity(0.5)).frame(width: 36, alignment: .trailing)
                            Text(" │ ").font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen.opacity(0.3))
                            syntaxLine(line)
                        }
                    }
                }.padding(8)
            }.background(bg)
        }
    }

    func syntaxLine(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(.caption, design: .monospaced)).foregroundColor(green)
            } else if w.contains("0.0") || w.contains("Double") {
                result = result + Text(w + " ").font(.system(.caption, design: .monospaced)).foregroundColor(.cyan)
            } else {
                result = result + Text(w + " ").font(.system(.caption, design: .monospaced)).foregroundColor(dimGreen)
            }
        }
        return result
    }

    var chatView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(chatMessages.enumerated()), id: \.0) { _, msg in
                        chatBubble(isUser: msg.0, text: msg.1)
                    }
                }.padding(12)
            }
            Rectangle().fill(dimGreen.opacity(0.3)).frame(height: 1)
            HStack(spacing: 8) {
                Text(">").font(.system(.callout, design: .monospaced)).foregroundStyle(green)
                TextField("", text: .constant("")).font(.system(.callout, design: .monospaced))
                    .foregroundStyle(green)
                if cursorVisible { Text("█").font(.system(.callout, design: .monospaced)).foregroundStyle(green) }
            }.padding(8).background(bg)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isUser ? "[USER]>" : "[EONCODE]>").font(.system(.caption, design: .monospaced))
                .foregroundStyle(isUser ? green : .cyan)
            let parts = text.components(separatedBy: "```")
            ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                if i % 2 == 1 {
                    let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                    Text(code).font(.system(.caption2, design: .monospaced)).foregroundStyle(green.opacity(0.8))
                        .padding(4).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.05))
                        .border(dimGreen.opacity(0.3), width: 1)
                } else if !part.isEmpty {
                    Text(part).font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen)
                }
            }
        }.padding(.vertical, 4)
    }

    var browserView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("URL:").font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen)
                Text("https://developer.apple.com").font(.system(.caption, design: .monospaced)).foregroundStyle(green)
                    .padding(4).frame(maxWidth: .infinity, alignment: .leading).border(dimGreen.opacity(0.3), width: 1)
            }.padding(8)
            Spacer()
            Text("[ BROWSER MODULE - NO CONTENT ]").font(.system(.body, design: .monospaced)).foregroundStyle(dimGreen)
            Spacer()
        }.background(bg)
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("=== SETTINGS ===").font(.system(.callout, design: .monospaced)).foregroundStyle(green)
                ForEach(["API_KEY:  ●●●●●●●●", "MODEL:    HAIKU-4.5", "SYNC:     ICLOUD", "THEME:    MIDNIGHT TERMINAL"], id: \.self) { s in
                    Text(s).font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen)
                }
            }.padding(12)
        }.background(bg)
    }

    var welcomeView: some View {
        VStack(spacing: 8) {
            Text("EONCODE v2.0 READY").font(.system(.title3, design: .monospaced)).foregroundStyle(green)
            Text("> SELECT A PROJECT OR FILE TO BEGIN_").font(.system(.caption, design: .monospaced)).foregroundStyle(dimGreen)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(bg)
    }
}

#Preview { Mockup2() }
