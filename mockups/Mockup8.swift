// Mockup8 — "Deep Ocean"
// Dark marine tones. Deep blue background. Bioluminescent accents (turquoise/cyan). Calm, meditative.
import SwiftUI

struct Mockup8: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]
    @State private var wavePhase: CGFloat = 0

    let deepBlue = Color(red: 0.03, green: 0.06, blue: 0.15)
    let oceanBlue = Color(red: 0.05, green: 0.1, blue: 0.22)
    let panelBlue = Color(red: 0.06, green: 0.1, blue: 0.2)
    let bioGlow = Color(red: 0.0, green: 0.9, blue: 0.8)
    let bioSoft = Color(red: 0.1, green: 0.6, blue: 0.7)
    let biolum = Color(red: 0.2, green: 0.8, blue: 0.9)
    let foam = Color.white

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
            deepBlue.ignoresSafeArea()
            // Subtle wave pattern overlay
            Canvas { ctx, size in
                for i in 0..<3 {
                    var path = Path()
                    let amplitude: CGFloat = 8
                    let freq: CGFloat = 0.01
                    let yOffset = size.height * 0.3 + CGFloat(i) * 60
                    path.move(to: CGPoint(x: 0, y: yOffset))
                    for x in stride(from: 0, to: size.width, by: 2) {
                        let y = yOffset + sin(x * freq + wavePhase + CGFloat(i)) * amplitude
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    ctx.stroke(path, with: .color(bioGlow.opacity(0.04)), lineWidth: 1)
                }
            }.ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                statusBar
                HStack(spacing: 0) {
                    sidebar.frame(width: 256)
                    Rectangle().fill(bioGlow.opacity(0.1)).frame(width: 1)
                        .shadow(color: bioGlow.opacity(0.2), radius: 3)
                    mainContent
                }
            }
        }.preferredColorScheme(.dark)
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { wavePhase = .pi * 2 }
            }
    }

    var statusBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(bioGlow).frame(width: 8, height: 8)
                    .shadow(color: bioGlow, radius: 4)
                Text("EonCode").font(.callout).fontWeight(.medium).foregroundStyle(foam.opacity(0.9))
            }
            Spacer()
            HStack(spacing: 16) {
                Label("Haiku 4.5", systemImage: "drop.fill").font(.caption).foregroundStyle(bioSoft)
                Text("142.50 SEK").font(.caption).foregroundStyle(biolum.opacity(0.7))
                HStack(spacing: 4) {
                    Circle().fill(bioGlow).frame(width: 5, height: 5).shadow(color: bioGlow, radius: 3)
                    Text("Mac Online").font(.caption).foregroundStyle(bioSoft)
                }
            }
        }.padding(.horizontal, 14).padding(.vertical, 9)
            .background(oceanBlue.opacity(0.9))
            .overlay(Rectangle().fill(bioGlow.opacity(0.15)).frame(height: 1).shadow(color: bioGlow.opacity(0.2), radius: 2), alignment: .bottom)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Array(["Projekt", "Chatt", "Webb", "Inst."].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.caption2).fontWeight(selectedTab == i ? .semibold : .regular)
                            .foregroundStyle(selectedTab == i ? foam : foam.opacity(0.35))
                            .padding(.vertical, 6).frame(maxWidth: .infinity)
                            .background(selectedTab == i ? bioGlow.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(selectedTab == i ?
                                RoundedRectangle(cornerRadius: 8).strokeBorder(bioGlow.opacity(0.2)) : nil)
                    }.buttonStyle(.plain)
                }
            }.padding(8)
            Rectangle().fill(bioGlow.opacity(0.08)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if selectedTab == 0 { projectList }
                    else if selectedTab == 1 { chatListView }
                    else if selectedTab == 2 {
                        Image(systemName: "globe").font(.title2).foregroundStyle(bioSoft.opacity(0.3)).padding(.top, 30)
                    } else { settingsList }
                }.padding(12)
            }

            Rectangle().fill(bioGlow.opacity(0.08)).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(biolum).frame(width: 6, height: 6).shadow(color: biolum, radius: 3)
                    Text("Agent: Bygger Eon X — 7/12").font(.caption2).foregroundStyle(biolum)
                }
                Text("Session: 2.45 SEK").font(.caption2).foregroundStyle(bioSoft.opacity(0.5))
            }.padding(12)
        }.background(panelBlue)
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) } else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expandedProjects.contains(name) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8)).foregroundStyle(bioSoft.opacity(0.5))
                        Image(systemName: "folder.fill").font(.caption2).foregroundStyle(biolum)
                            .shadow(color: biolum.opacity(0.3), radius: 2)
                        Text(name).font(.caption).foregroundStyle(selectedProject == name ? biolum : foam.opacity(0.7))
                    }.padding(5).background(selectedProject == name ? bioGlow.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            Text(file).font(.caption2).foregroundStyle(selectedFile == file ? bioGlow : foam.opacity(0.45))
                                .padding(.leading, 24).padding(.vertical, 2)
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
                        Circle().fill(bioGlow.opacity(0.15)).frame(width: 20, height: 20)
                            .overlay(Image(systemName: "bubble.left").font(.system(size: 9)).foregroundStyle(bioGlow))
                        Text(c).font(.caption).foregroundStyle(foam.opacity(0.6))
                    }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(oceanBlue.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
    }
    var settingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inställningar").font(.caption).fontWeight(.medium).foregroundStyle(biolum)
            ForEach(["API-nyckel", "Modell", "Synk", "Tema"], id: \.self) { s in
                Text(s).font(.caption).foregroundStyle(foam.opacity(0.5))
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
                Text(selectedFile ?? "").font(.caption).foregroundStyle(biolum)
                    .shadow(color: biolum.opacity(0.3), radius: 2)
                Spacer()
                Text("Swift").font(.caption2).foregroundStyle(foam.opacity(0.3))
            }.padding(.horizontal, 16).padding(.vertical, 8).background(oceanBlue)
                .overlay(Rectangle().fill(bioGlow.opacity(0.1)).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i+1)").font(.system(.caption, design: .monospaced))
                                .foregroundStyle(bioSoft.opacity(0.25)).frame(width: 28, alignment: .trailing)
                            oceanSyntax(line)
                        }.padding(.vertical, 1)
                    }
                }.padding(16)
            }.background(deepBlue)
        }
    }

    func oceanSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(bioGlow)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(biolum)
            } else if w.contains("0.0") {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(Color(red: 0.4, green: 0.7, blue: 1.0))
            } else {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(foam.opacity(0.65))
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
            Rectangle().fill(bioGlow.opacity(0.1)).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "photo").foregroundStyle(bioSoft.opacity(0.4))
                TextField("Skriv…", text: .constant("")).font(.callout).foregroundStyle(foam)
                    .padding(10).background(oceanBlue, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(bioGlow.opacity(0.15)))
                Button { } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(bioGlow)
                        .shadow(color: bioGlow.opacity(0.5), radius: 4)
                }.buttonStyle(.plain)
            }.padding(12).background(panelBlue)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if !isUser {
                Circle().fill(LinearGradient(colors: [bioGlow, biolum], startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 26)
                    .overlay(Text("E").font(.caption2).bold().foregroundStyle(deepBlue))
                    .shadow(color: bioGlow.opacity(0.4), radius: 4)
            }
            if isUser { Spacer(minLength: 50) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(.caption, design: .monospaced)).foregroundStyle(bioGlow.opacity(0.85))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(deepBlue.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(bioGlow.opacity(0.1)))
                    } else if !part.isEmpty {
                        Text(part).font(.callout).foregroundStyle(foam.opacity(0.85))
                    }
                }
            }.padding(10)
                .background(isUser ? biolum.opacity(0.08) : oceanBlue.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(bioGlow.opacity(isUser ? 0.1 : 0.05)))
            if !isUser { Spacer(minLength: 50) }
        }
    }

    var browserView: some View {
        VStack {
            HStack {
                TextField("", text: .constant("https://developer.apple.com")).font(.caption).foregroundStyle(foam)
                    .padding(8).background(oceanBlue, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(bioGlow.opacity(0.15)))
            }.padding(16)
            Spacer()
            Image(systemName: "water.waves").font(.system(size: 40)).foregroundStyle(bioSoft.opacity(0.2))
            Spacer()
        }.background(deepBlue)
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Inställningar").font(.title3).fontWeight(.medium).foregroundStyle(biolum)
                ForEach(["API-nyckel: ●●●●●", "Modell: Haiku 4.5", "Synk: iCloud", "Tema: Deep Ocean"], id: \.self) { s in
                    HStack {
                        Text(s).font(.callout).foregroundStyle(foam.opacity(0.7))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(bioSoft.opacity(0.4))
                    }.padding(12).background(oceanBlue.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(bioGlow.opacity(0.08)))
                }
            }.padding(20)
        }.background(deepBlue)
    }

    var welcomeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "drop.fill").font(.system(size: 40)).foregroundStyle(bioGlow)
                .shadow(color: bioGlow.opacity(0.6), radius: 10)
            Text("EonCode").font(.title2).fontWeight(.medium).foregroundStyle(foam.opacity(0.8))
            Text("Välj ett projekt för att dyka ner").font(.caption).foregroundStyle(bioSoft.opacity(0.5))
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(deepBlue)
    }
}

#Preview { Mockup8() }
