// Mockup9 — "Brutalist"
// Raw, brutalist web design. Large heavy fonts. Hard contrasts (black/white/red). Thick borders. Anti-design.
import SwiftUI

struct Mockup9: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]

    let red = Color(red: 0.9, green: 0.1, blue: 0.1)
    let black = Color.black
    let white = Color.white
    let grey = Color(white: 0.6)

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
                sidebar.frame(width: 270)
                Rectangle().fill(black).frame(width: 3)
                mainContent
            }
        }.background(white).preferredColorScheme(.light)
    }

    var statusBar: some View {
        HStack {
            Text("EONCODE").font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundStyle(black).textCase(.uppercase)
            Spacer()
            HStack(spacing: 12) {
                Text("HAIKU 4.5").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(red)
                Text("142.50 SEK").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(black)
                HStack(spacing: 3) {
                    Rectangle().fill(red).frame(width: 8, height: 8)
                    Text("MAC").font(.system(size: 10, weight: .black, design: .monospaced))
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .background(white).border(black, width: 3)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            // Tabs - brutalist buttons
            HStack(spacing: 0) {
                ForEach(Array(["PROJ", "CHAT", "WEBB", "INST"].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(selectedTab == i ? white : black)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(selectedTab == i ? black : white)
                            .border(black, width: 2)
                    }.buttonStyle(.plain)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if selectedTab == 0 { projectList }
                    else if selectedTab == 1 { chatListView }
                    else if selectedTab == 2 {
                        Text("BROWSER").font(.system(size: 24, weight: .black)).foregroundStyle(grey).padding(.top, 30)
                    } else { settingsList }
                }.padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Rectangle().fill(black).frame(height: 2)
                Text("● AGENT: BYGGER EON X — 7/12").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(red)
                Text("KOSTNAD: 2.45 SEK").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(black)
            }.padding(10)
        }.background(white).border(black, width: 2)
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) } else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    HStack {
                        Text(name.uppercased()).font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundStyle(selectedProject == name ? white : black)
                        Spacer()
                        Text(expandedProjects.contains(name) ? "−" : "+")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(selectedProject == name ? white : red)
                    }.padding(6)
                        .background(selectedProject == name ? black : white)
                        .border(black, width: 2)
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            Text(file).font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(selectedFile == file ? red : black)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedFile == file ? Color(white: 0.95) : .clear)
                                .border(black.opacity(selectedFile == file ? 1 : 0), width: 1)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.bottom, 4)
        }
    }

    var chatListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONVERSATIONS").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(red)
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { c in
                Button { selectedTab = 1 } label: {
                    Text(c.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .border(black, width: 2)
                }.buttonStyle(.plain)
            }
        }
    }
    var settingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SETTINGS").font(.system(size: 18, weight: .black)).foregroundStyle(red)
            ForEach(["API-NYCKEL", "MODELL", "SYNK", "TEMA"], id: \.self) { s in
                Text(s).font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(4).border(black, width: 1)
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
                Text("FILE: \(selectedFile?.uppercased() ?? "")").font(.system(size: 11, weight: .black, design: .monospaced))
                Spacer()
                Text("SWIFT").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(red)
            }.padding(8).background(Color(white: 0.95)).border(black, width: 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text(String(format: "%02d", i+1))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(grey).frame(width: 28, alignment: .trailing)
                            Text(" | ").font(.system(size: 12, design: .monospaced)).foregroundStyle(grey)
                            brutalistSyntax(line)
                        }.padding(.vertical, 1)
                    }
                }.padding(12)
            }
        }
    }

    func brutalistSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundColor(red)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(black)
            } else {
                result = result + Text(w + " ").font(.system(size: 13, design: .monospaced)).foregroundColor(black.opacity(0.7))
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
            Rectangle().fill(black).frame(height: 3)
            HStack(spacing: 8) {
                TextField("", text: .constant(""))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .padding(8).border(black, width: 2)
                Button { } label: {
                    Text("SEND").font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(white).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(red)
                }.buttonStyle(.plain)
            }.padding(10)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "YOU" : "EONCODE").font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(isUser ? red : black)
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(size: 10, design: .monospaced)).foregroundStyle(black)
                            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.95)).border(black, width: 1)
                    } else if !part.isEmpty {
                        Text(part).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(black.opacity(0.85))
                    }
                }
            }.padding(8)
                .border(isUser ? red : black, width: 2)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    var browserView: some View {
        VStack {
            HStack {
                TextField("", text: .constant("https://developer.apple.com"))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(8).border(black, width: 2)
            }.padding(12)
            Spacer()
            Text("NO\nCONTENT").font(.system(size: 48, weight: .black)).foregroundStyle(grey.opacity(0.3))
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("SETTINGS").font(.system(size: 28, weight: .black)).foregroundStyle(red)
                ForEach(["API-NYCKEL: ●●●●●", "MODELL: HAIKU 4.5", "SYNK: ICLOUD", "TEMA: BRUTALIST"], id: \.self) { s in
                    Text(s).font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .border(black, width: 2)
                }
            }.padding(16)
        }
    }

    var welcomeView: some View {
        VStack(spacing: 4) {
            Text("EON").font(.system(size: 72, weight: .black)).foregroundStyle(black)
            Text("CODE").font(.system(size: 72, weight: .black)).foregroundStyle(red)
            Rectangle().fill(black).frame(width: 100, height: 4)
            Text("SELECT A PROJECT").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(grey)
                .padding(.top, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview { Mockup9() }
