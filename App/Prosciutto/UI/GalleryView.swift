import SwiftUI
import ProsciuttoKit

struct GalleryView: View {
    @ObservedObject var model: GalleryViewModel
    @EnvironmentObject var theme: ThemeManager
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingItem: ClipItem?
    @State private var editingSection: ClipSection?
    @State private var showingAddSection = false
    @State private var newSectionName = ""

    private let kinds: [ClipKind] = [.text, .link, .image, .color, .code, .file]

    var body: some View {
        VStack(spacing: 10) {
            header
            sectionBar
            Group {
                if model.filtered().isEmpty {
                    emptyState
                } else {
                    cards
                }
            }
        }
        .padding(18)
        .background(panelBackground)
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .onAppear { searchFocused = true }
        .sheet(item: $editingItem) { item in
            EditSheet(item: item) { newText in
                Task { await model.updateText(item, newText: newText) }
            }
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
        }
        .sheet(item: $editingSection) { section in
            EditSectionSheet(section: section, palette: model.sectionColors) { name, hex in
                Task { await model.updateSection(section, name: name, hex: hex) }
            }
            .tint(theme.accent)
            .preferredColorScheme(theme.colorScheme)
        }
        .onChange(of: model.sectionFilter) { _, _ in model.selection = 0 }
        .alert("New section", isPresented: $showingAddSection) {
            TextField("Name", text: $newSectionName)
            Button("Create") {
                let name = newSectionName; newSectionName = ""
                Task { await model.createSection(name: name) }
            }
            Button("Cancel", role: .cancel) { newSectionName = "" }
        }
    }

    // MARK: Section bar

    private var sectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                sectionChip(label: "All", systemImage: "square.stack",
                            color: theme.accent, active: model.sectionFilter == .all) {
                    model.sectionFilter = .all
                }
                sectionChip(label: "Pinned", systemImage: "pin.fill",
                            color: theme.accent, active: model.sectionFilter == .pinned) {
                    model.sectionFilter = .pinned
                }
                ForEach(model.sections) { section in
                    let color = Color(hex: section.colorHex) ?? .gray
                    sectionChip(label: section.name, dotColor: color,
                                color: color, active: model.sectionFilter == .section(section.id)) {
                        model.sectionFilter = .section(section.id)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        guard let s = ids.first, let uuid = UUID(uuidString: s) else { return false }
                        Task { await model.assignID(uuid, to: section.id) }
                        return true
                    }
                    .contextMenu {
                        Button("Edit section…") { editingSection = section }
                        Button("Delete section", role: .destructive) {
                            Task { await model.deleteSection(section) }
                        }
                    }
                }
                Button { showingAddSection = true } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
    }

    private func sectionChip(label: String, systemImage: String? = nil, dotColor: Color? = nil,
                             color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
                if let dotColor { Circle().fill(dotColor).frame(width: 7, height: 7) }
                Text(label).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(active ? color : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(active ? color.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? color.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Background

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial)
            // accent glow pooled at the bottom
            RadialGradient(colors: [theme.accent.opacity(0.28), .clear],
                           center: .bottom, startRadius: 4, endRadius: 520)
                .blendMode(.plusLighter)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .compositingGroup()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Prosciutto").font(.system(size: 15, weight: .heavy, design: .rounded))
            }

            searchField

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { ForEach(kinds, id: \.self) { filterPill($0) } }
            }
            Spacer(minLength: 0)
            Text("⌘1–9 · ⏎ · esc")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            Button { model.onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.secondary.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close (esc)")
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(searchFocused ? theme.accent : .secondary)
            TextField("Search clipboard…", text: $model.query.text)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.accent.opacity(searchFocused ? 0.8 : 0), lineWidth: 1.5))
        .shadow(color: theme.accent.opacity(searchFocused ? 0.35 : 0), radius: 8)
        .frame(maxWidth: 250)
        .animation(.easeOut(duration: 0.18), value: searchFocused)
    }

    private func filterPill(_ kind: ClipKind) -> some View {
        let style = KindStyle.of(kind)
        let on = model.query.kinds.contains(kind)
        return Button {
            if on { model.query.kinds.remove(kind) } else { model.query.kinds.insert(kind) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: style.icon).font(.system(size: 9, weight: .bold))
                Text(kind.rawValue.capitalized).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(on ? style.color : .secondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(on ? style.color.opacity(0.18) : Color.secondary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    let list = model.filtered()
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, item in
                        ClipCard(item: item,
                                 index: idx + 1,
                                 isSelected: idx == model.selection,
                                 accent: theme.accent,
                                 onPin: { Task { await model.togglePin(item) } },
                                 onDelete: { Task { await model.delete(item) } },
                                 onEdit: editClosure(for: item))
                            .id(item.id)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .draggable(item.id.uuidString)
                            .onTapGesture {
                                model.selection = idx
                                model.pasteSelected()
                            }
                            .contextMenu { cardMenu(item) }
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 8)
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
                           value: model.items)
            }
            .frame(height: 236)
            .onChange(of: model.selection) { _, _ in scrollToSelection(proxy) }
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        let list = model.filtered()
        guard list.indices.contains(model.selection) else { return }
        let id = list[model.selection].id
        if reduceMotion { proxy.scrollTo(id, anchor: .center) }
        else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
    }

    private func editClosure(for item: ClipItem) -> (() -> Void)? {
        switch item.kind {
        case .text, .rtf, .code, .link, .color: return { editingItem = item }
        default: return nil
        }
    }

    @ViewBuilder private func cardMenu(_ item: ClipItem) -> some View {
        Button(item.isPinned ? "Unpin" : "Pin to front") { Task { await model.togglePin(item) } }
        if editClosure(for: item) != nil {
            Button("Edit…") { editingItem = item }
        }
        if !model.sections.isEmpty {
            Menu("Move to") {
                Button("None") { Task { await model.assign(item, to: nil) } }
                Divider()
                ForEach(model.sections) { section in
                    Button(section.name) { Task { await model.assign(item, to: section.id) } }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { Task { await model.delete(item) } }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.text.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(model.query.text.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(height: 236)
        .frame(maxWidth: .infinity)
    }
}
