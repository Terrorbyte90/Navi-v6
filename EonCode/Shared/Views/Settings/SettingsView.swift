import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var keychain = KeychainManagerObservable.shared

    @State private var anthropicKey = ""
    @State private var elevenLabsKey = ""
    @State private var muxKey = ""
    @State private var githubToken = ""
    @State private var macServerURL = ""
    @State private var showAnthropicKey = false
    @State private var saveMessage = ""
    @State private var showAddKeySheet = false

    var body: some View {
        #if os(macOS)
        macSettings
        #else
        NavigationView { iOSSettings }
        #endif
    }

    var macSettings: some View {
        TabView {
            apiKeysSection
                .tabItem { Label("API-nycklar", systemImage: "key") }
                .padding()

            VStack(alignment: .leading, spacing: 20) {
                modelSection
                Divider().opacity(0.2)
                parallelWorkersSection
            }
            .padding()
            .tabItem { Label("Modell", systemImage: "cpu") }

            syncSection
                .tabItem { Label("Synk", systemImage: "arrow.triangle.2.circlepath") }
                .padding()

            costSection
                .tabItem { Label("Kostnad", systemImage: "chart.bar") }
                .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    memoriesSection
                    Divider().opacity(0.2)
                    NavigationLink("Visa och redigera alla minnen →") {
                        MemoryView()
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.accentEon)
                }
                .padding()
            }
            .tabItem { Label("Minnen", systemImage: "brain") }
        }
        .frame(width: 560, height: 640)
        .background(Color.chatBackground)
    }

    var iOSSettings: some View {
        Form {
            Section("API-nycklar") { apiKeysSection }
            Section("Claude-modell") { modelSection }
            Section("iOS Agent-läge") { iOSAgentModeSection }
            Section("Parallella workers") { parallelWorkersSection }
            Section("Synk") { syncSection }
            Section("Röst (ElevenLabs)") {
                Toggle("Aktivera text-till-tal", isOn: $settings.ttsEnabled)
                VoicePickerRow()
            }
            Section("Minnen") { memoriesSection }
        }
        .navigationTitle("Inställningar")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(Color.chatBackground)
        .scrollContentBackground(.hidden)
    }

    var iOSAgentModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Läge", selection: $settings.iosAgentMode) {
                Text("Autonom").tag(AgentMode.autonomous)
                Text("Remote").tag(AgentMode.remoteOnly)
            }
            .pickerStyle(.segmented)

            Group {
                if settings.iosAgentMode == .autonomous {
                    Label(
                        "iOS kör fil-operationer direkt. Terminal-kommandon köas automatiskt till Mac.",
                        systemImage: "iphone"
                    )
                } else {
                    Label(
                        "Alla instruktioner köas till Mac. iOS agerar som fjärrkontroll.",
                        systemImage: "desktopcomputer"
                    )
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
    }

    var parallelWorkersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Aktivera parallella workers", isOn: $settings.parallelAgentsEnabled)

            if settings.parallelAgentsEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Max workers: \(settings.maxParallelWorkers)")
                            .font(.system(size: 13))
                        Spacer()
                        Text("2–10")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxParallelWorkers) },
                            set: { settings.maxParallelWorkers = Int($0) }
                        ),
                        in: 2...10,
                        step: 1
                    )
                    .tint(.accentEon)
                }

                Text("Komplexa uppgifter delas upp i parallella deluppgifter. Fler workers = snabbare men fler API-anrop.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Extrahera minnen automatiskt", isOn: Binding(
                get: { settings.autoExtractMemories },
                set: { settings.autoExtractMemories = $0 }
            ))

            Text("Claude lär sig om dig med varje konversation — namn, preferenser, projekt. Minnen injiceras i system-prompten.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))

            let count = MemoryManager.shared.memories.count
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.accentEon)
                    .font(.system(size: 13))
                Text("\(count) minne\(count == 1 ? "" : "n") sparade")
                    .font(.system(size: 13))
                Spacer()
                #if os(iOS)
                NavigationLink("Hantera →") { MemoryView() }
                    .font(.system(size: 13))
                    .foregroundColor(.accentEon)
                #endif
            }
        }
    }

    var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API-nycklar")
                .font(.system(size: 16, weight: .bold))

            // ── Anthropic ────────────────────────────────────────────────────
            APIKeyRow(
                label: "Anthropic",
                icon: "key.fill",
                placeholder: "sk-ant-…",
                text: $anthropicKey,
                hint: "Betalas per token direkt till Anthropic.",
                isRevealable: true
            )

            // ── ElevenLabs ───────────────────────────────────────────────────
            APIKeyRow(
                label: "ElevenLabs (valfri)",
                icon: "waveform",
                placeholder: "Nyckel för text-till-tal",
                text: $elevenLabsKey
            )

            // ── Mux ──────────────────────────────────────────────────────────
            APIKeyRow(
                label: "Mux (valfri)",
                icon: "video.fill",
                placeholder: "Mux token ID eller secret key",
                text: $muxKey,
                hint: "Används för video-streaming och media-hantering."
            )

            // ── GitHub ───────────────────────────────────────────────────────
            APIKeyRow(
                label: "GitHub Token",
                icon: "chevron.left.forwardslash.chevron.right",
                placeholder: "ghp_…",
                text: $githubToken,
                hint: "Personal Access Token med repo, read:org och workflow-behörigheter. Synkas via iCloud Keychain.",
                isRevealable: true
            )

            // ── Custom keys ──────────────────────────────────────────────────
            customKeysSection

            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }

            HStack {
                GlassButton("Spara nycklar", icon: "checkmark", isPrimary: true) {
                    saveKeys()
                }
                Spacer()
            }
        }
        .onAppear {
            anthropicKey = KeychainManager.shared.anthropicAPIKey ?? ""
            elevenLabsKey = KeychainManager.shared.elevenLabsAPIKey ?? ""
            muxKey = KeychainManager.shared.muxAPIKey ?? ""
            githubToken = KeychainManager.shared.githubToken ?? ""
            macServerURL = settings.macServerURL
        }
        .sheet(isPresented: $showAddKeySheet) {
            AddAPIKeySheet { name, value in
                try? KeychainManager.shared.saveCustomKey(name: name, value: value)
                keychain.reload()
            }
        }
    }

    // MARK: - Custom keys list

    var customKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Egna nycklar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    showAddKeySheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.accentEon)
                }
                .buttonStyle(.plain)
                .help("Lägg till API-nyckel")
            }

            if keychain.customKeys.isEmpty {
                Text("Inga egna nycklar ännu. Tryck + för att lägga till.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(keychain.customKeys, id: \.name) { entry in
                        CustomKeyRow(entry: entry) {
                            KeychainManager.shared.deleteCustomKey(name: entry.name)
                            keychain.reload()
                        }
                    }
                }
            }

            Text("Sparas krypterat i Apple Keychain och synkas automatiskt via iCloud Keychain till alla dina enheter.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.top, 4)
    }

    var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Standard Claude-modell")
                .font(.system(size: 16, weight: .bold))

            ModelPickerView(currentModel: settings.defaultModel) { model in
                settings.defaultModel = model
            }

            Divider().opacity(0.2)

            Toggle("Bekräfta destruktiva agentkommandon", isOn: $settings.agentConfirmDestructive)
        }
    }

    var syncSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Synkronisering")
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Sync-prioritet:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    SyncMethodRow(n: 1, title: "iCloud Drive", icon: "icloud", description: "Primär — alltid aktiv")
                    SyncMethodRow(n: 2, title: "Bonjour/P2P", icon: "wifi", description: "Sekundär — lokal WiFi")
                    SyncMethodRow(n: 3, title: "Lokal HTTP", icon: "network", description: "Reserv — port 52731")
                }
            }

            Divider().opacity(0.2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Mac-server URL (iOS → Mac)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                GlassTextField(placeholder: "http://192.168.1.x:52731", text: $macServerURL)
                Text("Används när Bonjour inte hittar din Mac automatiskt.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                GlassButton("Spara URL", icon: "checkmark") {
                    settings.macServerURL = macServerURL
                    if let url = URL(string: macServerURL) {
                        LocalNetworkClient.shared.setMacAddress(url)
                    }
                }
            }

            Divider().opacity(0.2)

            Toggle("Automatiska versionssnapshotar", isOn: $settings.autoSnapshot)
                .font(.system(size: 13))

            Divider().opacity(0.2)

            Toggle("Auto-synka med GitHub efter agent-körning", isOn: $settings.autoGitHubSync)
                .font(.system(size: 13))
            if settings.autoGitHubSync {
                Text("Agenten pushar automatiskt ändringar till GitHub och skapar ett repo om inget finns.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    var costSection: some View {
        CostDashboardView()
    }

    private func saveKeys() {
        var saved = false

        if !anthropicKey.isBlank {
            try? KeychainManager.shared.saveAnthropicKey(anthropicKey)
            saved = true
        }
        if !elevenLabsKey.isBlank {
            try? KeychainManager.shared.saveElevenLabsKey(elevenLabsKey)
            saved = true
            ElevenLabsClient.shared.isEnabled = true
        }
        if !muxKey.isBlank {
            try? KeychainManager.shared.saveMuxKey(muxKey)
            saved = true
        }
        if !githubToken.isBlank {
            try? KeychainManager.shared.saveGitHubToken(githubToken)
            saved = true
            Task { await GitHubManager.shared.verifyToken() }
        }

        saveMessage = saved ? "✓ Sparade" : "Ange en nyckel"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saveMessage = ""
        }
    }
}

struct SyncMethodRow: View {
    let n: Int
    let title: String
    let icon: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentEon)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text("·")
                .foregroundColor(.secondary.opacity(0.4))
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
}

// MARK: - API Keychain observable wrapper

final class KeychainManagerObservable: ObservableObject {
    static let shared = KeychainManagerObservable()

    @Published var customKeys: [(name: String, value: String)] = []

    private init() {
        reload()
    }

    var hasAnthropicKey: Bool {
        KeychainManager.shared.anthropicAPIKey?.isEmpty == false
    }

    func reload() {
        customKeys = KeychainManager.shared.allCustomKeys()
    }
}

// MARK: - Reusable API key row

struct APIKeyRow: View {
    let label: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var hint: String? = nil
    var isRevealable: Bool = false

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                GlassTextField(
                    placeholder: placeholder,
                    text: $text,
                    isSecure: isRevealable ? !isRevealed : true
                )
                if isRevealable {
                    Button { isRevealed.toggle() } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.55))
            }
        }
    }
}

// MARK: - Custom key row (in list)

struct CustomKeyRow: View {
    let entry: (name: String, value: String)
    let onDelete: () -> Void

    @State private var isRevealed = false

    var maskedValue: String {
        guard !entry.value.isEmpty else { return "—" }
        let visible = entry.value.prefix(4)
        return "\(visible)••••••••"
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(isRevealed ? entry.value : maskedValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button { isRevealed.toggle() } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.05))
        .cornerRadius(9)
    }
}

// MARK: - Add API key sheet

struct AddAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, String) -> Void

    @State private var keyName = ""
    @State private var keyValue = ""
    @State private var isRevealed = false
    @State private var errorMessage = ""

    var canSave: Bool { !keyName.isBlank && !keyValue.isBlank }

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        NavigationView { iOSLayout }
        #endif
    }

    var macLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "key.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.accentEon)
                Text("Lägg till API-nyckel")
                    .font(.system(size: 18, weight: .bold))
            }

            formContent

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }

            HStack {
                Button("Avbryt") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Spara") { save() }
                    .buttonStyle(.plain)
                    .foregroundColor(canSave ? .accentEon : .secondary)
                    .disabled(!canSave)
                    .fontWeight(.semibold)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color.chatBackground)
    }

    var iOSLayout: some View {
        Form {
            Section {
                formContent
            } footer: {
                Text("Sparas krypterat i Apple Keychain och synkas via iCloud till alla dina enheter.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.system(size: 13))
                }
            }
        }
        .navigationTitle("Ny API-nyckel")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Spara") { save() }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
            }
        }
        .background(Color.chatBackground)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    var formContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Namn på nyckeln")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                GlassTextField(placeholder: "t.ex. OpenAI, Stripe, GitHub", text: $keyName)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API-nyckel")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    GlassTextField(
                        placeholder: "Klistra in din nyckel här",
                        text: $keyValue,
                        isSecure: !isRevealed
                    )
                    Button { isRevealed.toggle() } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("Lagras krypterat i Apple Keychain och synkas via iCloud Keychain.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.55))
            }
        }
    }

    private func save() {
        let trimmedName = keyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = keyValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { errorMessage = "Ange ett namn."; return }
        guard !trimmedValue.isEmpty else { errorMessage = "Ange en nyckel."; return }

        // Prevent overwriting built-in keys
        let reserved = [Constants.Keychain.anthropicKey, Constants.Keychain.elevenLabsKey, Constants.Keychain.muxKey]
        if reserved.contains(trimmedName.lowercased()) {
            errorMessage = "Det namnet är reserverat. Välj ett annat."
            return
        }

        onSave(trimmedName, trimmedValue)
        dismiss()
    }
}

// MARK: - Model Picker View

struct ModelPickerView: View {
    let currentModel: ClaudeModel
    let onSelect: (ClaudeModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ClaudeModel.allCases) { model in
                Button {
                    onSelect(model)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(model.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                if model == .haiku {
                                    Text("DEFAULT")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentEon.opacity(0.2))
                                        .cornerRadius(4)
                                        .foregroundColor(.accentEon)
                                }
                            }
                            Text(model.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        Spacer()
                        if model == currentModel {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentEon)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(model == currentModel ? Color.accentEon.opacity(0.1) : Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Cost Dashboard

struct CostDashboardView: View {
    @StateObject private var exchange = ExchangeRateService.shared
    @StateObject private var tracker = CostTracker.shared
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: Totals
                VStack(alignment: .leading, spacing: 12) {
                    Text("Kostnadsspårning")
                        .font(.system(size: 16, weight: .bold))

                    HStack(spacing: 12) {
                        costCard(
                            title: "Totalt spenderat",
                            icon: "chart.bar.fill",
                            iconColor: .accentEon,
                            primary: tracker.formattedTotal().components(separatedBy: " (").first ?? "—",
                            secondary: tracker.formattedTotal().components(separatedBy: " (").last.map { String($0.dropLast()) } ?? ""
                        )
                        costCard(
                            title: "Denna session",
                            icon: "clock.fill",
                            iconColor: .green,
                            primary: tracker.formattedSession().components(separatedBy: " (").first ?? "—",
                            secondary: tracker.formattedSession().components(separatedBy: " (").last.map { String($0.dropLast()) } ?? ""
                        )
                    }

                    if tracker.lastRequestSEK > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("Senaste svar:")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(tracker.formattedLast())
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            if let model = tracker.lastRequestModel {
                                Text("·")
                                    .foregroundColor(.secondary.opacity(0.4))
                                Text(model.displayName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentEon)
                            }
                        }
                    }
                }

                Divider().opacity(0.2)

                // MARK: Token stats
                if tracker.totalRequests > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Token-statistik (totalt)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            tokenStatCard("Anrop", value: "\(tracker.totalRequests)", color: .accentEon)
                            tokenStatCard("Indata", value: formatTokens(tracker.totalInputTokens), color: .blue)
                            tokenStatCard("Utdata", value: formatTokens(tracker.totalOutputTokens), color: .purple)
                        }

                        if tracker.totalCacheReadTokens > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                Text("\(formatTokens(tracker.totalCacheReadTokens)) tokens från cache (−90% kostnad)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                    }

                    Divider().opacity(0.2)
                }

                // MARK: Exchange rate
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Växelkurs")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("1 USD = \(String(format: "%.2f", exchange.usdToSEK)) SEK")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                    Spacer()
                    GlassButton("Uppdatera", icon: "arrow.clockwise") {
                        Task { await exchange.refresh() }
                    }
                }

                Divider().opacity(0.2)

                // MARK: Pricing table
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pris per miljon tokens (USD)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    ForEach(ClaudeModel.allCases) { model in
                        HStack {
                            Text(model.displayName)
                                .font(.system(size: 12))
                            Spacer()
                            Text("In: $\(String(format: "%.2f", model.inputPricePerMTok))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.green)
                            Text("Ut: $\(String(format: "%.2f", model.outputPricePerMTok))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 2)
                    }

                    Text("Cache-läsning kostar 10% av normalpris. Prompt-caching aktiveras automatiskt.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                Divider().opacity(0.2)

                // MARK: Reset
                HStack {
                    Spacer()
                    Button {
                        showResetConfirm = true
                    } label: {
                        Label("Nollställ statistik", systemImage: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .confirmationDialog("Nollställ all kostnadsstatistik?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                    Button("Nollställ", role: .destructive) { tracker.resetAll() }
                    Button("Avbryt", role: .cancel) {}
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    @ViewBuilder
    private func costCard(title: String, icon: String, iconColor: Color, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(primary)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
            if !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func tokenStatCard(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.07))
        .cornerRadius(8)
    }
}

// MARK: - Previews

#Preview("SettingsView") {
    SettingsView()
}

#Preview("ModelPickerView") {
    ModelPickerView(currentModel: .haiku) { _ in }
        .padding()
        .frame(width: 320)
        .background(Color.black)
}

#Preview("CostDashboardView") {
    CostDashboardView()
        .padding()
        .frame(width: 400)
        .background(Color.black)
}

// MARK: - Voice Picker

struct VoicePickerRow: View {
    @StateObject private var tts = ElevenLabsClient.shared
    @StateObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Röst: \(settings.selectedVoiceName)")
                    .font(.system(size: 13))
                Spacer()
                Button("Hämta röster") {
                    Task { await tts.fetchVoices() }
                }
                .font(.system(size: 12))
                .foregroundColor(.accentEon)
            }

            if !tts.availableVoices.isEmpty {
                Picker("Röst", selection: $settings.selectedVoiceID) {
                    ForEach(tts.availableVoices) { voice in
                        Text(voice.name).tag(voice.voice_id)
                    }
                }
                .onChange(of: settings.selectedVoiceID) { newID in
                    if let voice = tts.availableVoices.first(where: { $0.voice_id == newID }) {
                        settings.selectedVoiceName = voice.name
                    }
                }
            }
        }
    }
}

#Preview("SyncMethodRow") {
    VStack(alignment: .leading, spacing: 8) {
        SyncMethodRow(n: 1, title: "iCloud Drive", icon: "icloud", description: "Primär — alltid aktiv")
        SyncMethodRow(n: 2, title: "Bonjour/P2P", icon: "wifi", description: "Sekundär — lokal WiFi")
        SyncMethodRow(n: 3, title: "Lokal HTTP", icon: "network", description: "Reserv — port 52731")
    }
    .padding()
    .background(Color.black)
}
