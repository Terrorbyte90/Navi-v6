// Mockup5 — "Monokai Pro"
// Classic Monokai color scheme: #272822 bg, yellow classes, green strings, orange functions, pink keywords.
import SwiftUI

struct Mockup5: View {
    @State private var selectedTab = 0
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]

    let bg = Color(red: 0.153, green: 0.157, blue: 0.133)        // #272822
    let bgLight = Color(red: 0.2, green: 0.2, blue: 0.17)
    let bgDark = Color(red: 0.12, green: 0.12, blue: 0.1)
    let pink = Color(red: 0.973, green: 0.149, blue: 0.427)       // #F92672 keywords
    let green = Color(red: 0.651, green: 0.886, blue: 0.180)      // #A6E22E functions/strings
    let yellow = Color(red: 0.902, green: 0.859, blue: 0.455)     // #E6DB74 strings
    let orange = Color(red: 0.992, green: 0.592, blue: 0.122)     // #FD971F params
    let blue = Color(red: 0.392, green: 0.851, blue: 0.937)       // #66D9EF types
    let purple = Color(red: 0.682, green: 0.506, blue: 1.0)       // #AE81FF numbers
    let fg = Color(red: 0.973, green: 0.973, blue: 0.949)         // #F8F8F2
    let comment = Color(red: 0.467, green: 0.467, blue: 0.404)    // #75715E

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
                Rectangle().fill(bgDark).frame(width: 1)
                mainContent
            }
        }.background(bg).preferredColorScheme(.dark)
    }

    var statusBar: some View {
        HStack {
            Text("EonCode").font(.system(.caption, design: .monospaced)).bold().foregroundStyle(green)
            Spacer()
            HStack(spacing: 14) {
                Text("Haiku 4.5").font(.system(.caption2, design: .monospaced)).foregroundStyle(blue)
                Text("142.50 SEK").font(.system(.caption2, design: .monospaced)).foregroundStyle(yellow)
                HStack(spacing: 4) {
                    Circle().fill(green).frame(width: 6, height: 6)
                    Text("Mac Online").font(.system(.caption2, design: .monospaced)).foregroundStyle(green)
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 7)
            .background(bgDark).overlay(Rectangle().fill(comment.opacity(0.3)).frame(height: 1), alignment: .bottom)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(["Projekt", "Chatt", "Webb", "Inst."].enumerated()), id: \.0) { i, label in
                    Button { selectedTab = i } label: {
                        Text(label).font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(selectedTab == i ? bg : comment)
                            .padding(.vertical, 5).frame(maxWidth: .infinity)
                            .background(selectedTab == i ? yellow : .clear, in: Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Rectangle().fill(comment.opacity(0.2)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if selectedTab == 0 { projectList }
                    else if selectedTab == 1 { chatListView }
                    else if selectedTab == 2 {
                        Text("// browser").font(.system(.caption, design: .monospaced)).foregroundStyle(comment).padding(.top, 20)
                    } else { settingsList }
                }.padding(10)
            }

            Rectangle().fill(comment.opacity(0.2)).frame(height: 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Circle().fill(orange).frame(width: 6, height: 6)
                    Text("Agent: Bygger Eon X — 7/12").font(.system(.caption2, design: .monospaced)).foregroundStyle(orange)
                }
                Text("Session: 2.45 SEK").font(.system(.caption2, design: .monospaced)).foregroundStyle(comment)
            }.padding(10)
        }.background(bgDark)
    }

    var projectList: some View {
        ForEach(projects, id: \.0) { name, files in
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if expandedProjects.contains(name) { expandedProjects.remove(name) } else { expandedProjects.insert(name) }
                    selectedProject = name
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expandedProjects.contains(name) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8)).foregroundStyle(comment)
                        Image(systemName: "folder.fill").font(.caption2).foregroundStyle(yellow)
                        Text(name).font(.system(.caption, design: .monospaced)).foregroundStyle(
                            selectedProject == name ? yellow : fg)
                    }.padding(.vertical, 3).padding(.horizontal, 4)
                        .background(selectedProject == name ? yellow.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 3))
                }.buttonStyle(.plain)

                if expandedProjects.contains(name) {
                    ForEach(files, id: \.self) { file in
                        Button { selectedFile = file; selectedTab = 0 } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text").font(.system(size: 9)).foregroundStyle(blue)
                                Text(file).font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(selectedFile == file ? green : fg.opacity(0.7))
                            }.padding(.leading, 20).padding(.vertical, 1)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var chatListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("// conversations").font(.system(.caption2, design: .monospaced)).foregroundStyle(comment)
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { c in
                Button { selectedTab = 1 } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left").font(.caption2).foregroundStyle(blue)
                        Text(c).font(.system(.caption2, design: .monospaced)).foregroundStyle(fg.opacity(0.7))
                    }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
                        .background(bgLight, in: RoundedRectangle(cornerRadius: 3))
                }.buttonStyle(.plain)
            }
        }
    }
    var settingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(["API-nyckel", "Modell", "Synk", "Tema"], id: \.self) { s in
                HStack { Image(systemName: "gearshape").font(.caption2).foregroundStyle(comment); Text(s).font(.system(.caption, design: .monospaced)).foregroundStyle(fg.opacity(0.7)) }
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
            // Tab bar
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.caption2).foregroundStyle(blue)
                    Text(selectedFile ?? "").font(.system(.caption, design: .monospaced)).foregroundStyle(fg)
                }.padding(.horizontal, 12).padding(.vertical, 6).background(bg)
                Spacer()
            }.background(bgDark).overlay(Rectangle().fill(comment.opacity(0.2)).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text("\(i + 1)").font(.system(.caption, design: .monospaced))
                                .foregroundStyle(comment.opacity(0.5)).frame(width: 35, alignment: .trailing)
                            Text("  ").font(.caption)
                            monokaiSyntax(line)
                        }.padding(.vertical, 1)
                    }
                }.padding(12)
            }.background(bg)
        }
    }

    func monokaiSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(pink)
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(blue)
            } else if w.contains("0.0") {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(purple)
            } else if w.contains("(") || w.contains(")") {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(green)
            } else {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(fg)
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
                }.padding(14)
            }
            Rectangle().fill(comment.opacity(0.2)).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: "photo").foregroundStyle(comment)
                TextField("", text: .constant("")).font(.system(.callout, design: .monospaced)).foregroundStyle(fg)
                    .padding(8).background(bgDark, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(comment.opacity(0.3)))
                Button { } label: {
                    Image(systemName: "arrow.up").font(.caption).bold().foregroundStyle(bg)
                        .padding(8).background(green, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }.padding(10).background(bgDark)
        }
    }

    func chatBubble(isUser: Bool, text: String) -> some View {
        HStack(alignment: .top) {
            if !isUser {
                Text("E").font(.system(.caption2, design: .monospaced)).bold().foregroundStyle(bg)
                    .frame(width: 22, height: 22).background(green, in: RoundedRectangle(cornerRadius: 4))
            }
            if isUser { Spacer(minLength: 50) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                let parts = text.components(separatedBy: "```")
                ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                    if i % 2 == 1 {
                        let code = part.hasPrefix("swift\n") ? String(part.dropFirst(6)) : part
                        Text(code).font(.system(.caption2, design: .monospaced)).foregroundStyle(fg.opacity(0.9))
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(bgDark, in: RoundedRectangle(cornerRadius: 4))
                    } else if !part.isEmpty {
                        Text(part).font(.system(.callout, design: .default)).foregroundStyle(fg.opacity(0.9))
                    }
                }
            }.padding(10)
                .background(isUser ? yellow.opacity(0.08) : bgLight, in: RoundedRectangle(cornerRadius: 8))
            if !isUser { Spacer(minLength: 50) }
        }
    }

    var browserView: some View {
        VStack {
            HStack {
                TextField("", text: .constant("https://developer.apple.com"))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(fg).padding(6)
                    .background(bgDark, in: RoundedRectangle(cornerRadius: 4))
            }.padding(12)
            Spacer()
            Text("// browser placeholder").font(.system(.callout, design: .monospaced)).foregroundStyle(comment)
            Spacer()
        }.background(bg)
    }

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings").font(.system(.title3, design: .monospaced)).foregroundStyle(green)
                ForEach(["API-nyckel: ●●●●●", "Modell: Haiku 4.5", "Synk: iCloud", "Tema: Monokai Pro"], id: \.self) { s in
                    Text(s).font(.system(.callout, design: .monospaced)).foregroundStyle(fg.opacity(0.8))
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(bgLight, in: RoundedRectangle(cornerRadius: 4))
                }
            }.padding(16)
        }.background(bg)
    }

    var welcomeView: some View {
        VStack(spacing: 8) {
            Text("EonCode").font(.system(.largeTitle, design: .monospaced)).foregroundStyle(green)
            Text("// select a project").font(.system(.callout, design: .monospaced)).foregroundStyle(comment)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(bg)
    }
}

#Preview { Mockup5() }
