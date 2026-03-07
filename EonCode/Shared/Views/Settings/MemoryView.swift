import SwiftUI

// MARK: - MemoryView
// View and manage all user memories.

struct MemoryView: View {
    @StateObject private var manager = MemoryManager.shared
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingMemory: Memory?
    @State private var editText = ""

    var filtered: [Memory] {
        if searchText.isEmpty { return manager.memories }
        return manager.memories.filter { $0.fact.localizedCaseInsensitiveContains(searchText) }
    }

    var grouped: [MemoryCategory: [Memory]] {
        Dictionary(grouping: filtered, by: \.category)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search + add
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Sök minnen…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.accentEon)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))

            Divider().opacity(0.15)

            if manager.memories.isEmpty {
                emptyState
            } else {
                memoriesList
            }
        }
        .background(Color.chatBackground)
        .sheet(isPresented: $showingAddSheet) {
            AddMemorySheet(manager: manager)
        }
        .sheet(item: $editingMemory) { memory in
            EditMemorySheet(memory: memory, manager: manager)
        }
        .onAppear { Task { await manager.reload() } }
        #if os(iOS)
        .navigationTitle("Minnen")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Memories list

    var memoriesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(MemoryCategory.allCases, id: \.self) { category in
                    if let memories = grouped[category], !memories.isEmpty {
                        MemoryCategorySection(
                            category: category,
                            memories: memories,
                            onEdit: { editingMemory = $0 },
                            onDelete: { memory in
                                Task { await manager.deleteMemory(id: memory.id) }
                            }
                        )
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Empty state

    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(.accentEon.opacity(0.3))
            Text("Inga minnen ännu")
                .font(.system(size: 20, weight: .bold))
            Text("Minnen extraheras automatiskt från dina konversationer och hjälper Claude att bli bättre på att hjälpa just dig.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            GlassButton("Lägg till manuellt", icon: "plus", isPrimary: true) {
                showingAddSheet = true
            }
            Spacer()
        }
    }
}

// MARK: - Category section

struct MemoryCategorySection: View {
    let category: MemoryCategory
    let memories: [Memory]
    let onEdit: (Memory) -> Void
    let onDelete: (Memory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 11))
                    .foregroundColor(.accentEon)
                Text(category.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text("(\(memories.count))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            }

            // Memory rows
            ForEach(memories) { memory in
                MemoryRow(memory: memory, onEdit: { onEdit(memory) }, onDelete: { onDelete(memory) })
            }
        }
    }
}

struct MemoryRow: View {
    let memory: Memory
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(memory.fact)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
        .contextMenu {
            Button("Redigera", action: onEdit)
            Button("Radera", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Add memory sheet

struct AddMemorySheet: View {
    @ObservedObject var manager: MemoryManager
    @Environment(\.dismiss) private var dismiss
    @State private var fact = ""
    @State private var category: MemoryCategory = .other

    var body: some View {
        NavigationView {
            Form {
                Section("Fakta") {
                    TextField("Skriv ett faktum om dig själv…", text: $fact, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Kategori") {
                    Picker("Kategori", selection: $category) {
                        ForEach(MemoryCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Nytt minne")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        Task {
                            await manager.addMemory(fact: fact, category: category)
                            dismiss()
                        }
                    }
                    .disabled(fact.isBlank)
                }
            }
        }
    }
}

// MARK: - Edit memory sheet

struct EditMemorySheet: View {
    let memory: Memory
    @ObservedObject var manager: MemoryManager
    @Environment(\.dismiss) private var dismiss
    @State private var fact: String

    init(memory: Memory, manager: MemoryManager) {
        self.memory = memory
        self.manager = manager
        _fact = State(initialValue: memory.fact)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Redigera fakta") {
                    TextField("Fakta", text: $fact, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Redigera minne")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        Task {
                            await manager.updateMemory(id: memory.id, newFact: fact)
                            dismiss()
                        }
                    }
                    .disabled(fact.isBlank)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("MemoryView – tom") {
    MemoryView()
        .frame(width: 400, height: 500)
}

#Preview("MemoryCategorySection") {
    let memories = [
        Memory(fact: "Heter Ted och jobbar på Futura Luna", category: .personal, source: .manual),
        Memory(fact: "Föredrar SwiftUI framför UIKit", category: .personal, source: .manual),
    ]
    MemoryCategorySection(
        category: .personal,
        memories: memories,
        onEdit: { _ in },
        onDelete: { _ in }
    )
    .padding()
    .background(Color.black)
}
