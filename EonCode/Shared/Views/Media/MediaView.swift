import SwiftUI
#if os(iOS)
import PhotosUI
#endif

// MARK: - MediaView (matches app-wide ChatGPT-style design)

struct MediaView: View {
    @ObservedObject private var manager = MediaGenerationManager.shared

    @State private var prompt = ""
    @State private var selectedMode: MediaType = .image
    @State private var imageSize = "1080x1920"
    @State private var imageVariations = 1
    @State private var useProModel = false
    @State private var videoDuration = 5
    @State private var videoRatio = "720:1280"
    @State private var selectedGeneration: MediaGeneration?
    @FocusState private var promptFocused: Bool

    // Reference image (image-to-video / image-to-image)
    @State private var referenceImageData: Data? = nil
    #if os(iOS)
    @State private var referencePickerItems: [PhotosPickerItem] = []
    #else
    @State private var showReferenceImagePicker = false
    #endif

    var body: some View {
        ZStack(alignment: .top) {
            #if os(macOS)
            macLayout
            #else
            iOSLayout
            #endif

            if manager.showLimitReachedToast {
                Text("Max 10 simultana genereringar nådda")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.showLimitReachedToast)
                    .padding(.top, 12)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.showLimitReachedToast)
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
        .onAppear { Task { await manager.loadHistory() } }
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
            // Show gallery as soon as any generation exists (active, failed, or completed)
            if manager.generations.isEmpty {
                emptyStateWithPrompt
            } else {
                galleryWithPrompt
            }
        }
        .background(Color.chatBackground)
        .onAppear { Task { await manager.loadHistory() } }
        .onChange(of: referencePickerItems) { _, items in
            guard let item = items.first else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { referenceImageData = data }
                }
                await MainActor.run { referencePickerItems = [] }
            }
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
                Text(selectedMode == .image
                     ? "Beskriv en bild så genererar Grok den åt dig."
                     : "Beskriv en video så genererar Grok den åt dig.")
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
                // Settings menu — quality/size/duration only, NO PhotosPicker inside
                // (PhotosPicker inside Menu causes _UIReparentingView via UIContextMenuInteraction)
                Menu {
                    if selectedMode == .image {
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
                    } else {
                        Section("Längd") {
                            Picker("Längd", selection: $videoDuration) {
                                Text("5 sekunder").tag(5)
                                Text("10 sekunder").tag(10)
                            }
                        }
                        Section("Format") {
                            Picker("Format", selection: $videoRatio) {
                                Text("Stående 9:16").tag("720:1280")
                                Text("Liggande 16:9").tag("1280:720")
                                Text("Kvadrat 1:1").tag("1280:1280")
                            }
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.surfaceHover)
                            .frame(width: 30, height: 30)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.secondary)
                    }
                }

                #if os(iOS)
                // Reference image button — standalone PhotosPicker, NEVER inside Menu
                PhotosPicker(selection: $referencePickerItems, maxSelectionCount: 1, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(referenceImageData != nil ? Color.orange.opacity(0.15) : Color.surfaceHover)
                            .frame(width: 30, height: 30)
                        Image(systemName: referenceImageData != nil ? "photo.badge.checkmark" : "photo.badge.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(referenceImageData != nil ? .orange : .secondary)
                    }
                }
                .buttonStyle(.plain)
                if referenceImageData != nil {
                    Button { referenceImageData = nil } label: {
                        ZStack {
                            Circle().fill(Color.red.opacity(0.1)).frame(width: 24, height: 24)
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .buttonStyle(.plain)
                }
                #endif

                TextField(selectedMode == .image ? "Beskriv bilden du vill skapa..." : "Beskriv videon du vill skapa...", text: $prompt, axis: .vertical)
                    .focused($promptFocused)
                    .font(.callout)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)

                // Always show generate button — concurrent requests allowed up to maxConcurrent
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

        }
    }
    #endif

    // MARK: - Gallery Content

    var galleryContent: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

        return VStack(alignment: .leading, spacing: 12) {
            // Active (generating) rows
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

            // Failed generation rows (dismissable)
            let failedGens = manager.generations.filter { $0.status == .failed }
            if !failedGens.isEmpty {
                ForEach(failedGens) { gen in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red).font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gen.displayTitle)
                                .font(.system(size: 12)).lineLimit(1)
                            Text(gen.error ?? "Okänt fel")
                                .font(.system(size: 11)).foregroundColor(.red.opacity(0.8)).lineLimit(2)
                        }
                        Spacer()
                        Button { Task { await manager.delete(gen) } } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                }
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
                modeSelector
                promptInput
                parameterControls
                generateButton

                if !manager.activeGenerations.isEmpty || manager.generations.contains(where: { $0.status == .failed }) {
                    activeGenerationsList
                }
            }
            .padding(20)
        }
        .background(Color.sidebarBackground)
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
                    #if os(macOS)
                    Button { showReferenceImagePicker = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.arrow.down").font(.system(size: 13))
                            Text("Välj referensbild…").font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.08)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    #else
                    PhotosPicker(selection: $referencePickerItems, maxSelectionCount: 1, matching: .images) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.arrow.down").font(.system(size: 13))
                            Text("Välj referensbild…").font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.08)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    #endif
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
        VStack(alignment: .leading, spacing: 12) {
            // Duration
            HStack {
                Text("Längd").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $videoDuration) {
                    Text("5 sekunder").tag(5)
                    Text("10 sekunder").tag(10)
                }
                .pickerStyle(.menu).font(.system(size: 12))
            }

            // Aspect ratio
            HStack {
                Text("Format").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $videoRatio) {
                    Text("Stående (9:16)").tag("720:1280")
                    Text("Liggande (16:9)").tag("1280:720")
                    Text("Kvadrat (1:1)").tag("1280:1280")
                }
                .pickerStyle(.menu).font(.system(size: 12))
            }

            Divider().opacity(0.15)

            // Reference image (optional seed frame)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Startbild (valfri)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if referenceImageData != nil {
                        Button("Ta bort") { referenceImageData = nil }
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                            .buttonStyle(.plain)
                    }
                }

                if let imgData = referenceImageData {
                    #if os(macOS)
                    if let ns = NSImage(data: imgData) {
                        Image(nsImage: ns)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    #endif
                } else {
                    #if os(macOS)
                    Button { showReferenceImagePicker = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.arrow.down").font(.system(size: 13))
                            Text("Välj startbild…").font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.08)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    #else
                    PhotosPicker(selection: $referencePickerItems, maxSelectionCount: 1, matching: .images) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.arrow.down").font(.system(size: 13))
                            Text("Välj startbild…").font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.08)).cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    #endif
                    Text("Utan startbild genereras en automatiskt via xAI.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }

            // xAI badge
            HStack(spacing: 5) {
                Image(systemName: "film.stack")
                    .font(.system(size: 10))
                Text("Drivs av grok-imagine-video")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .background(Color.userBubble)
        .cornerRadius(8)
    }

    // MARK: - Generate Button

    var generateButton: some View {
        Button(action: generate) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").font(.system(size: 14, weight: .medium))
                Text("Generera")
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
        let inProgress = manager.activeGenerations
        let failed = manager.generations.filter { $0.status == .failed }.prefix(3)
        return VStack(alignment: .leading, spacing: 6) {
            if !inProgress.isEmpty {
                Text("Pågående (\(inProgress.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(inProgress) { gen in
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
            ForEach(Array(failed)) { gen in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gen.displayTitle).font(.system(size: 12)).lineLimit(1)
                        Text(gen.error ?? "Okänt fel").font(.system(size: 10)).foregroundColor(.red).lineLimit(2)
                    }
                    Spacer()
                    Button { Task { await manager.delete(gen) } } label: {
                        Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.red.opacity(0.06))
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
                        ThumbnailImage(data: thumbData)
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
                    Text(gen.createdAt.relativeString)
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

    // Prompt is non-empty, API key set, and manager hasn't hit max concurrent (10)
    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && manager.canGenerate
            && KeychainManager.shared.xaiAPIKey?.isEmpty == false
    }

    // MARK: - Generate Action

    private func generate() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canGenerate, !trimmed.isEmpty else { return }

        // Capture parameters before clearing state
        let model = "grok-2-aurora"
        let capturedImageData = referenceImageData
        let capturedMode = selectedMode
        let capturedVariations = imageVariations
        let capturedSize = imageSize
        let capturedDuration = videoDuration
        let capturedRatio = videoRatio

        // Clear prompt & reference image immediately — allows starting next generation right away
        prompt = ""
        referenceImageData = nil

        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        promptFocused = false

        // Fire-and-forget — the manager tracks state; errors show as dismissable cards in gallery
        Task {
            switch capturedMode {
            case .image:
                await manager.generateImage(
                    prompt: trimmed,
                    model: model,
                    size: capturedSize,
                    variations: capturedVariations
                )
            case .video:
                await manager.generateVideo(
                    prompt: trimmed,
                    referenceImageData: capturedImageData,
                    duration: capturedDuration,
                    ratio: capturedRatio
                )
            }
        }
    }
}

// MARK: - ThumbnailImage
// Caches the decoded UIImage/NSImage in @State so it is only created once per card.

private struct ThumbnailImage: View {
    let data: Data

    #if os(macOS)
    @State private var image: NSImage? = nil
    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.surfaceHover
                    .onAppear { image = NSImage(data: data) }
            }
        }
    }
    #else
    @State private var image: UIImage? = nil
    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.surfaceHover
                    .onAppear { image = UIImage(data: data) }
            }
        }
    }
    #endif
}

// MARK: - Preview

#Preview("MediaView") {
    MediaView()
        .frame(width: 900, height: 600)
}
