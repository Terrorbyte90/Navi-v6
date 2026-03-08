import SwiftUI

// MARK: - MediaView (matches app-wide ChatGPT-style design)

struct MediaView: View {
    @StateObject private var manager = MediaGenerationManager.shared
    @StateObject private var exchange = ExchangeRateService.shared

    @State private var prompt = ""
    @State private var selectedMode: MediaType = .image
    @State private var imageSize = "1080x1920"
    @State private var imageVariations = 1
    @State private var useProModel = false
    @State private var selectedGeneration: MediaGeneration?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @FocusState private var promptFocused: Bool

    // Reference image (image-to-video / image-to-image)
    @State private var referenceImageData: Data? = nil
    @State private var showReferenceImagePicker = false

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    var macLayout: some View {
        HSplitView {
            controlsPanel
                .frame(minWidth: 320, maxWidth: 400)
            galleryPanel
                .frame(minWidth: 400)
        }
        .background(Color.chatBackground)
        .onAppear { Task { await manager.refreshBalance() } }
        .sheet(isPresented: $showReferenceImagePicker) {
            ImagePicker(selectedImages: Binding(
                get: { referenceImageData.map { [$0] } ?? [] },
                set: { referenceImageData = $0.first }
            ))
            .frame(minWidth: 500, minHeight: 400)
        }
    }
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    var iOSLayout: some View {
        VStack(spacing: 0) {
            if manager.completedGenerations.isEmpty && !isGenerating {
                emptyStateWithPrompt
            } else {
                galleryWithPrompt
            }
        }
        .background(Color.chatBackground)
        .onAppear { Task { await manager.refreshBalance() } }
        .sheet(isPresented: $showReferenceImagePicker) {
            ImagePicker(selectedImages: Binding(
                get: { referenceImageData.map { [$0] } ?? [] },
                set: { referenceImageData = $0.first }
            ))
        }
    }

    var emptyStateWithPrompt: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.orange.opacity(0.7), Color.orange.opacity(0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text("Skapa med AI")
                    .font(.system(size: 22, weight: .semibold))
                Text("Beskriv en bild så genererar Grok den åt dig.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            promptBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
    }

    var galleryWithPrompt: some View {
        VStack(spacing: 0) {
            ScrollView {
                galleryContent
            }
            .scrollDismissesKeyboard(.interactively)

            promptBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.chatBackground)
        }
    }
    #endif

    // MARK: - Prompt Bar (iOS — ChatGPT-style pill)

    #if os(iOS)
    var promptBar: some View {
        VStack(spacing: 6) {
            // Reference image thumbnail (if set)
            if let imgData = referenceImageData, let ui = UIImage(data: imgData) {
                HStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Button { referenceImageData = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Referensbild")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Används som underlag")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }

            HStack(alignment: .center, spacing: 8) {
                // Settings + image upload menu
                Menu {
                    Section("Upplösning") {
                        Picker("Upplösning", selection: $imageSize) {
                            Text("720p Stående (720×1280)").tag("720x1280")
                            Text("1080p Stående (1080×1920)").tag("1080x1920")
                        }
                    }
                    Section("Antal") {
                        Picker("Bilder", selection: $imageVariations) {
                            ForEach(1...4, id: \.self) { n in
                                Text("\(n) bild\(n > 1 ? "er" : "")").tag(n)
                            }
                        }
                    }
                    Section("Kvalitet") {
                        Toggle("Pro ($0.07/bild)", isOn: $useProModel)
                    }
                    Divider()
                    Button {
                        showReferenceImagePicker = true
                    } label: {
                        Label(
                            referenceImageData == nil ? "Ladda upp referensbild" : "Byt referensbild",
                            systemImage: "photo.badge.arrow.down"
                        )
                    }
                    if referenceImageData != nil {
                        Button(role: .destructive) {
                            referenceImageData = nil
                        } label: {
                            Label("Ta bort referensbild", systemImage: "trash")
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(referenceImageData != nil ? Color.orange.opacity(0.15) : Color.surfaceHover)
                            .frame(width: 30, height: 30)
                        Image(systemName: referenceImageData != nil ? "photo.badge.checkmark" : "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(referenceImageData != nil ? .orange : .secondary)
                    }
                }

                TextField("Beskriv bilden du vill skapa...", text: $prompt, axis: .vertical)
                    .focused($promptFocused)
                    .font(.callout)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)

                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 30, height: 30)
                } else {
                    Button(action: generate) {
                        ZStack {
                            Circle()
                                .fill(canGenerate ? Color.orange : Color.secondary.opacity(0.2))
                                .frame(width: 30, height: 30)
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(canGenerate ? .white : .secondary.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGenerate)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.userBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                    )
            )

            HStack {
                let cost = estimateCostSEK()
                if cost > 0 {
                    let res = imageSize == "1080x1920" ? "1080p" : "720p"
                    Text("~\(String(format: "%.2f kr", cost)) · \(useProModel ? "Pro" : "Standard") · \(res) · \(imageVariations) bild\(imageVariations > 1 ? "er" : "")")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                Spacer()
                if let bal = manager.balance {
                    Text("Saldo: \(bal.formattedRemaining)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
    }
    #endif

    // MARK: - Gallery Content

    var galleryContent: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

        return VStack(alignment: .leading, spacing: 12) {
            if !manager.activeGenerations.isEmpty {
                ForEach(manager.activeGenerations) { gen in
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gen.displayTitle)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Text(gen.status.displayName)
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.userBubble)
                    .cornerRadius(12)
                }
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red).font(.system(size: 12))
                    Text(error).font(.system(size: 12)).foregroundColor(.red.opacity(0.9))
                }
                .padding(10)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(manager.completedGenerations) { gen in
                    galleryCard(gen)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Controls Panel (macOS)

    var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                balanceBar
                modeSelector
                promptInput
                parameterControls
                costEstimate
                generateButton

                if !manager.activeGenerations.isEmpty {
                    activeGenerationsList
                }

                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red).font(.system(size: 12))
                        Text(error).font(.system(size: 12)).foregroundColor(.red.opacity(0.9))
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding(20)
        }
        .background(Color.sidebarBackground)
    }

    // MARK: - Balance Bar

    var balanceBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("xAI Saldo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                if manager.isLoadingBalance {
                    ProgressView().scaleEffect(0.6)
                } else if let balance = manager.balance {
                    HStack(spacing: 8) {
                        Text(balance.formattedRemaining)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        Text("(\(balance.formattedRemainingInSEK))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Ange xAI API-nyckel i Inställningar")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }

            Spacer()

            Button {
                Task { await manager.refreshBalance() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.userBubble)
        .cornerRadius(10)
    }

    // MARK: - Mode Selector

    var modeSelector: some View {
        HStack(spacing: 0) {
            ForEach(MediaType.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedMode = mode }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon).font(.system(size: 12))
                        Text(mode.displayName).font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedMode == mode ? Color.orange.opacity(0.12) : Color.clear)
                    )
                    .foregroundColor(selectedMode == mode ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.userBubble)
        .cornerRadius(10)
    }

    // MARK: - Prompt Input (macOS)

    var promptInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text(selectedMode == .image
                         ? "Beskriv bilden du vill skapa…"
                         : "Beskriv videon du vill generera…")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.4))
                        .padding(.top, 12).padding(.leading, 12)
                }
                TextEditor(text: $prompt)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 160)
                    .padding(10)
            }
            .background(Color.userBubble)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.inputBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Parameter Controls

    @ViewBuilder
    var parameterControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parametrar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            switch selectedMode {
            case .image: imageParameters
            case .video: videoParameters
            }
        }
    }

    var imageParameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Resolution — portrait iPhone only
            HStack {
                Text("Upplösning").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $imageSize) {
                    Text("720p Stående (720×1280)").tag("720x1280")
                    Text("1080p Stående (1080×1920)").tag("1080x1920")
                }
                .pickerStyle(.menu).font(.system(size: 12))
            }

            // Variations 1–4
            HStack {
                Text("Bilder: \(imageVariations)").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
                Stepper("", value: $imageVariations, in: 1...4).labelsHidden()
            }

            // Pro toggle
            Toggle("Pro-modell ($0.07/bild)", isOn: $useProModel)
                .font(.system(size: 13))

            Divider().opacity(0.15)

            // Reference image upload
            VStack(alignment: .leading, spacing: 8) {
                Text("Referensbild (valfri)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                if let imgData = referenceImageData {
                    #if os(macOS)
                    if let ns = NSImage(data: imgData) {
                        HStack(spacing: 10) {
                            Image(nsImage: ns)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Referensbild inladdad")
                                    .font(.system(size: 12))
                                Button("Ta bort") { referenceImageData = nil }
                                    .font(.system(size: 11))
                                    .foregroundColor(.red.opacity(0.8))
                                    .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }
                    #endif
                } else {
                    Button {
                        showReferenceImagePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.system(size: 13))
                            Text("Välj referensbild…")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    Text("Används som underlag för bild- och videogenerering")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(Color.userBubble)
        .cornerRadius(8)
    }

    var videoParameters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Video-generering via xAI — kommer snart")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.6))
                .italic()
        }
        .padding(12)
        .background(Color.userBubble)
        .cornerRadius(8)
    }

    // MARK: - Cost Estimate

    var costEstimate: some View {
        let sek = estimateCostSEK()
        let usd = estimateCostUSD()
        let res = imageSize == "1080x1920" ? "1080p" : "720p"

        return HStack(spacing: 8) {
            Image(systemName: "banknote").font(.system(size: 12)).foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.2f kr  ($%.3f)", sek, usd))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text("\(useProModel ? "Pro" : "Standard") · \(res) stående · \(imageVariations) bild\(imageVariations > 1 ? "er" : "")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Generate Button

    var generateButton: some View {
        Button(action: generate) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "wand.and.stars").font(.system(size: 14, weight: .medium))
                }
                Text(isGenerating ? "Genererar…" : "Generera")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(canGenerate ? Color.orange : Color.secondary.opacity(0.3))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
    }

    // MARK: - Active Generations List

    var activeGenerationsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pågående (\(manager.activeGenerations.count))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(manager.activeGenerations) { gen in
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gen.displayTitle).font(.system(size: 12)).lineLimit(1)
                        Text(gen.status.displayName).font(.system(size: 10)).foregroundColor(.orange)
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color.userBubble)
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Gallery Panel (macOS)

    var galleryPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Galleri").font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(manager.completedGenerations.count) objekt")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            if manager.completedGenerations.isEmpty && manager.activeGenerations.isEmpty {
                galleryEmpty
            } else {
                ScrollView {
                    galleryContent
                }
            }
        }
        .background(Color.chatBackground)
    }

    var galleryEmpty: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.15))
            Text("Genererade bilder visas här")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Gallery Card

    @ViewBuilder
    func galleryCard(_ gen: MediaGeneration) -> some View {
        let isSelected = selectedGeneration?.id == gen.id

        Button { selectedGeneration = gen } label: {
            VStack(spacing: 0) {
                ZStack {
                    Color.surfaceHover

                    if let thumbData = gen.thumbnailData {
                        #if os(macOS)
                        if let nsImage = NSImage(data: thumbData) {
                            Image(nsImage: nsImage).resizable().scaledToFill()
                        }
                        #else
                        if let uiImage = UIImage(data: thumbData) {
                            Image(uiImage: uiImage).resizable().scaledToFill()
                        }
                        #endif
                    } else {
                        Image(systemName: gen.type == .image ? "photo" : "video")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.2))
                    }

                    if let duration = gen.durationText {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(duration)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4).padding(6)
                            }
                        }
                    }
                }
                .frame(height: 160)
                .clipped()
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(gen.displayTitle)
                        .font(.system(size: 12)).lineLimit(2)
                    HStack(spacing: 4) {
                        Text(gen.createdAt.relativeString)
                        if gen.costSEK > 0 {
                            Text("·")
                            Text(String(format: "%.2f kr", gen.costSEK))
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
            }
            .background(Color.userBubble)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            #if os(macOS)
            Button {
                if let url = manager.imageURL(for: gen) {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
            } label: {
                Label("Visa i Finder", systemImage: "folder")
            }
            #endif
            Divider()
            Button(role: .destructive) {
                Task { await manager.delete(gen) }
            } label: {
                Label("Radera", systemImage: "trash")
            }
        }
    }

    // MARK: - Cost helpers

    private func estimateCostUSD() -> Double {
        switch selectedMode {
        case .image:
            let perImage = useProModel ? 0.07 : 0.02
            return Double(imageVariations) * perImage
        case .video:
            return 0.05
        }
    }

    private func estimateCostSEK() -> Double {
        estimateCostUSD() * ExchangeRateService.shared.usdToSEK
    }

    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isGenerating
        && manager.canGenerate
        && KeychainManager.shared.xaiAPIKey?.isEmpty == false
    }

    // MARK: - Generate Action

    private func generate() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil
        isGenerating = true

        let model = useProModel ? "grok-imagine-image-pro" : "grok-imagine-image"

        Task {
            switch selectedMode {
            case .image:
                await manager.generateImage(
                    prompt: trimmed,
                    model: model,
                    size: imageSize,
                    variations: imageVariations
                )
            case .video:
                errorMessage = "Video-generering stöds ännu inte via xAI API."
            }
            isGenerating = false
            if errorMessage == nil { prompt = "" }
        }
    }
}

// MARK: - Preview

#Preview("MediaView") {
    MediaView()
        .frame(width: 900, height: 600)
}
