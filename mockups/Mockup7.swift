// Mockup7 — "Arctic Minimal"
// Extremely minimalist. Almost all white/light grey. ONE accent color (ice blue). Scandinavian design.
import SwiftUI

struct Mockup7: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]

    let ice = Color(red: 0.35, green: 0.7, blue: 0.9)
    let bg = Color(red: 0.98, green: 0.98, blue: 0.99)
    let sidebarBg = Color(red: 0.96, green: 0.96, blue: 0.97)
    let text1 = Color(red: 0.15, green: 0.15, blue: 0.18)
    let text2 = Color(red: 0.45, green: 0.45, blue: 0.5)
    let text3 = Color(red: 0.7, green: 0.7, blue: 0.73)
    let border = Color(red: 0.9, green: 0.9, blue: 0.91)

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
                sidebar.frame(width: 240)
                Rectangle().fill(border).frame(width: 1)
                mainContent
            }
        }.background(bg).preferredColorScheme(.light)
    }

    var statusBar: some View {
        HStack {
            Text("EonCode").font(.system(size: 13, weight: .medium)).foregroundStyle(text1)
            Spacer()
            HStack(spacing: 20) {
                Text("Haiku 4.5").font(.system(size: 11)).foregroundStyle(text3)
                Text("142.50 SEK").font(.system(size: 11)).foregroundStyle(text3)
                HStack(spacing: 4) {
                    Circle().fill(ice).frame(width: 5, height: 5)
                    Text("Mac Online").font(.system(size: 11)).foregroundStyle(text3)
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 12)
            .overlay(Rectangle().fill(border).frame(height: 1), alignment: .bottom)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["Projekt", "Chatt", "Webb", "Inst."].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.system(size: 11, weight: selectedTab == i ? .medium : .regular))
                            .foregroundStyle(selectedTab == i ? ice : text3)
                            .padding(.vertical, 10).frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
            Rectangle().fill(border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if selectedTab == 0 { projectList }
                    else if selectedTab == 1 { chatListView }
                    else if selectedTab == 2 {
                        Text("Webbläsare").font(.system(size: 11)).foregroundStyle(text3).padding(.top, 32)
                    } else { settingsList }
                }.padding(16)
            }

            Rectangle().fill(border).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent: Bygger Eon X — 7/12").font(.system(size: 10)).foregroundStyle(text2)
                Text("2.45 SEK").font(.system(size: 10)).foregroundStyle(text3)
            }.padding(16)
        }.background(sidebarBg)
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) } else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expandedProjects.contains(name) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(text3)
                        Text(name).font(.system(size: 12, weight: selectedProject == name ? .medium : .regular))
                            .foregroundStyle(selectedProject == name ? ice : text1)
                    }.padding(.vertical, 4)
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            Text(file).font(.system(size: 11))
                                .foregroundStyle(selectedFile == file ? ice : text2)
                                .padding(.leading, 20).padding(.vertical, 2)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var chatListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { c in
                Button { selectedTab = 1 } label: {
                    Text(c).font(.system(size: 11)).foregroundStyle(text2)
                        .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }
    }
    var settingsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(["API-nyckel", "Modell", "Synk", "Tema"], id: \.self) { s in
                Text(s).font(.system(size: 12)).foregroundStyle(text2)
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
                Text(selectedFile ?? "").font(.system(size: 11)).foregroundStyle(text2)
                Spacer()
            }.padding(.horizontal, 24).padding(.vertical, 8)
                .overlay(Rectangle().fill(border).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 16) {
                            Text("\(i+1)").font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(text3).frame(width: 24, alignment: .trailing)
                            arcticSyntax(line)
                        }.padding(.vertical, 1)
                    }
                }.padding(24)
            }
        }
    }

    func arcticSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(size: 13, design: .monospaced)).foregroundColor(ice)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(size: 13, design: .monospaced)).foregroundColor(text1)
            } else {
                result = result + Text(w + " ").font(.system(size: 13, design: .monospaced)).foregroundColor(text2)
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
                }.padding(24)
            }
            Rectangle().fill(border).frame(height: 1)
            HStack(spacing: 12) {
                TextField("Skriv ett meddelande…", text: .constant(""))
                    .font(.system(size: 13)).textFieldStyle(.plain).padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border))
                Button { } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .padding(8).background(ice, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }.padding(16)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if !isUser {
                Circle().fill(ice).frame(width: 24, height: 24)
                    .overlay(Text("E").font(.system(size: 10, weight: .medium)).foregroundStyle(.white))
            }
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(size: 11, design: .monospaced)).foregroundStyle(text1)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(sidebarBg, in: RoundedRectangle(cornerRadius: 4))
                    } else if !part.isEmpty {
                        Text(part).font(.system(size: 13)).foregroundStyle(text1)
                    }
                }
            }.padding(12)
                .background(isUser ? ice.opacity(0.06) : sidebarBg, in: RoundedRectangle(cornerRadius: 8))
            if !isUser { Spacer(minLength: 80) }
        }
    }

    var browserView: some View {
        VStack {
            HStack {
                TextField("", text: .constant("https://developer.apple.com"))
                    .font(.system(size: 12)).textFieldStyle(.plain).padding(8)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border))
            }.padding(24)
            Spacer()
            Text("Webbläsare").font(.system(size: 14)).foregroundStyle(text3)
            Spacer()
        }
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inställningar").font(.system(size: 18, weight: .medium)).foregroundStyle(text1)
                ForEach(["API-nyckel: ●●●●●", "Modell: Haiku 4.5", "Synk: iCloud", "Tema: Arctic Minimal"], id: \.self) { s in
                    HStack {
                        Text(s).font(.system(size: 13)).foregroundStyle(text2)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(text3)
                    }.padding(.vertical, 8)
                        .overlay(Rectangle().fill(border).frame(height: 1), alignment: .bottom)
                }
            }.padding(24)
        }
    }

    var welcomeView: some View {
        VStack(spacing: 8) {
            Circle().fill(ice.opacity(0.1)).frame(width: 60, height: 60)
                .overlay(Image(systemName: "sparkle").font(.system(size: 22)).foregroundStyle(ice))
            Text("Välj ett projekt").font(.system(size: 14)).foregroundStyle(text3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview { Mockup7() }
