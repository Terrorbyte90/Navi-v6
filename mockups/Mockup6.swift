// Mockup6 — "Sunset Gradient"
// Warm, soft design with gradient backgrounds from deep orange to dark purple. Colored shadows, inviting.
import SwiftUI

struct Mockup6: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]

    let sunsetStart = Color(red: 1.0, green: 0.45, blue: 0.2)
    let sunsetMid = Color(red: 0.85, green: 0.25, blue: 0.45)
    let sunsetEnd = Color(red: 0.35, green: 0.15, blue: 0.55)
    let cardBg = Color.white.opacity(0.12)
    let textPrimary = Color.white
    let textSecondary = Color.white.opacity(0.7)
    let textDim = Color.white.opacity(0.4)

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

    var bgGradient: LinearGradient {
        LinearGradient(colors: [sunsetEnd, sunsetMid.opacity(0.6), sunsetEnd.opacity(0.9)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            bgGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                statusBar
                HStack(spacing: 1) {
                    sidebar.frame(width: 260)
                    mainContent
                }
            }
        }.preferredColorScheme(.dark)
    }

    var statusBar: some View {
        HStack {
            Text("EonCode").font(.headline).foregroundStyle(textPrimary)
                .shadow(color: sunsetStart.opacity(0.5), radius: 4)
            Spacer()
            HStack(spacing: 14) {
                Label("Haiku 4.5", systemImage: "cpu").font(.caption).foregroundStyle(textSecondary)
                Text("142.50 SEK").font(.caption).foregroundStyle(sunsetStart)
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                        .shadow(color: .green, radius: 3)
                    Text("Mac Online").font(.caption).foregroundStyle(textSecondary)
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.black.opacity(0.2))
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Array(["Projekt", "Chatt", "Webb", "Inst."].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.caption).fontWeight(selectedTab == i ? .bold : .regular)
                            .foregroundStyle(selectedTab == i ? textPrimary : textDim)
                            .padding(.vertical, 6).frame(maxWidth: .infinity)
                            .background(selectedTab == i ? cardBg : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }.padding(8)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if selectedTab == 0 { projectList }
                    else if selectedTab == 1 { chatListView }
                    else if selectedTab == 2 {
                        Label("Webbläsare", systemImage: "globe").font(.caption).foregroundStyle(textDim).padding(.top, 20)
                    } else { settingsList }
                }.padding(12)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(sunsetStart).frame(width: 7, height: 7).shadow(color: sunsetStart, radius: 4)
                    Text("Agent: Bygger Eon X — 7/12").font(.caption2).foregroundStyle(textSecondary)
                }
                Text("Session: 2.45 SEK").font(.caption2).foregroundStyle(textDim)
            }.padding(12)
        }.background(Color.black.opacity(0.25))
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) } else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    HStack {
                        Image(systemName: expandedProjects.contains(name) ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundStyle(textDim)
                        Image(systemName: "folder.fill").font(.caption)
                            .foregroundStyle(sunsetStart)
                            .shadow(color: sunsetStart.opacity(0.4), radius: 3)
                        Text(name).font(.callout).foregroundStyle(selectedProject == name ? textPrimary : textSecondary)
                        Spacer()
                    }.padding(6).background(selectedProject == name ? cardBg : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text").font(.caption2).foregroundStyle(textDim)
                                Text(file).font(.caption).foregroundStyle(selectedFile == file ? sunsetStart : textSecondary)
                            }.padding(.leading, 24).padding(.vertical, 2)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var chatListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { c in
                Button { selectedTab = 1 } label: {
                    HStack {
                        Image(systemName: "bubble.left.fill").font(.caption).foregroundStyle(sunsetStart.opacity(0.7))
                        Text(c).font(.caption).foregroundStyle(textSecondary)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: sunsetMid.opacity(0.15), radius: 4)
                }.buttonStyle(.plain)
            }
        }
    }
    var settingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inställningar").font(.callout).bold().foregroundStyle(textPrimary)
            ForEach(["API-nyckel", "Modell", "Synk", "Tema"], id: \.self) { s in
                HStack {
                    Image(systemName: "gearshape").font(.caption).foregroundStyle(sunsetStart)
                    Text(s).font(.caption).foregroundStyle(textSecondary)
                }
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
                Label(selectedFile ?? "", systemImage: "doc.text").font(.callout).foregroundStyle(textPrimary)
                Spacer()
                Text("Swift").font(.caption).foregroundStyle(textDim)
            }.padding(.horizontal, 16).padding(.vertical, 8).background(Color.black.opacity(0.2))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i+1)").font(.system(.caption, design: .monospaced))
                                .foregroundStyle(textDim).frame(width: 28, alignment: .trailing)
                            sunsetSyntax(line)
                        }.padding(.vertical, 1)
                    }
                }.padding(16)
            }.background(Color.black.opacity(0.3))
        }
    }

    func sunsetSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(sunsetStart)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(sunsetMid)
            } else if w.contains("0.0") {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(.yellow)
            } else {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(textPrimary.opacity(0.85))
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
            HStack(spacing: 8) {
                Image(systemName: "photo").foregroundStyle(textDim)
                TextField("Skriv…", text: .constant("")).font(.callout).foregroundStyle(textPrimary)
                    .padding(10).background(cardBg, in: RoundedRectangle(cornerRadius: 14))
                Button { } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                        .foregroundStyle(sunsetStart).shadow(color: sunsetStart.opacity(0.6), radius: 4)
                }.buttonStyle(.plain)
            }.padding(12).background(Color.black.opacity(0.2))
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                Circle().fill(LinearGradient(colors: [sunsetStart, sunsetMid], startPoint: .top, endPoint: .bottom))
                    .frame(width: 28, height: 28)
                    .overlay(Text("E").font(.caption).bold().foregroundStyle(.white))
                    .shadow(color: sunsetStart.opacity(0.4), radius: 4)
            }
            if isUser { Spacer(minLength: 50) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(.caption, design: .monospaced)).foregroundStyle(textPrimary.opacity(0.9))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    } else if !part.isEmpty {
                        Text(part).font(.callout).foregroundStyle(textPrimary.opacity(0.9))
                    }
                }
            }.padding(10)
                .background(
                    isUser ?
                    AnyShapeStyle(LinearGradient(colors: [sunsetStart.opacity(0.2), sunsetMid.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                    AnyShapeStyle(cardBg),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .shadow(color: isUser ? sunsetStart.opacity(0.2) : .clear, radius: 6)
            if !isUser { Spacer(minLength: 50) }
        }
    }

    var browserView: some View {
        VStack {
            HStack {
                Image(systemName: "chevron.left").foregroundStyle(textDim)
                Image(systemName: "chevron.right").foregroundStyle(textDim)
                TextField("", text: .constant("https://developer.apple.com"))
                    .font(.caption).foregroundStyle(textPrimary).padding(8)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 8))
            }.padding(12)
            Spacer()
            Image(systemName: "globe").font(.system(size: 44)).foregroundStyle(textDim)
            Spacer()
        }.background(Color.black.opacity(0.3))
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Inställningar").font(.title2).bold().foregroundStyle(textPrimary)
                ForEach(["API-nyckel: ●●●●●", "Modell: Haiku 4.5", "Synk: iCloud", "Tema: Sunset Gradient"], id: \.self) { s in
                    HStack {
                        Text(s).font(.callout).foregroundStyle(textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(textDim)
                    }.padding(12).background(cardBg, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: sunsetMid.opacity(0.1), radius: 4)
                }
            }.padding(20)
        }.background(Color.black.opacity(0.2))
    }

    var welcomeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill").font(.system(size: 48))
                .foregroundStyle(LinearGradient(colors: [sunsetStart, sunsetMid], startPoint: .leading, endPoint: .trailing))
                .shadow(color: sunsetStart.opacity(0.5), radius: 8)
            Text("EonCode").font(.largeTitle).bold().foregroundStyle(textPrimary)
            Text("Välj ett projekt").font(.callout).foregroundStyle(textDim)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.2))
    }
}

#Preview { Mockup6() }
