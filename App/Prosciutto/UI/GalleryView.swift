import SwiftUI
import ProsciuttoKit

struct GalleryView: View {
    @ObservedObject var model: GalleryViewModel
    @EnvironmentObject var theme: ThemeManager
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var editingSection: ClipSection?
    @State private var showingAddSection = false
    @State private var newSectionName = ""
    @State private var dropPulse: UUID?

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
                    .scaleEffect(dropPulse == section.id ? 1.18 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: dropPulse)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let s = ids.first, let uuid = UUID(uuidString: s) else { return false }
                        Task { await model.assignID(uuid, to: section.id) }
                        dropPulse = section.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            if dropPulse == section.id { dropPulse = nil }
                        }
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
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
                }
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 9, height: 9)
                        .shadow(color: dotColor.opacity(0.6), radius: active ? 3 : 0)
                }
                Text(label).font(DS.Font.sectionPill)
            }
            .foregroundStyle(active ? Color.primary : .secondary)
            .padding(.horizontal, DS.Space.md).padding(.vertical, 7)
            .background(active ? color.opacity(0.22) : Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? color.opacity(0.55) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Background

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous).fill(.ultraThinMaterial)
            if scheme == .light {
                RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                    .fill(DS.panelFill(.light).opacity(0.86))
            } else {
                RadialGradient(colors: [theme.accent.opacity(0.10), .clear],
                               center: .bottom, startRadius: 4, endRadius: 480)
            }
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08), lineWidth: 1)
        }
        .compositingGroup()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image("HamGlyph")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
                    .foregroundStyle(theme.accent)
                Text("Prosciutto").font(DS.Font.brand)
            }

            searchField

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { ForEach(kinds, id: \.self) { filterPill($0) } }
            }
            Spacer(minLength: 0)
            Text("⌘1–9 · ⏎ · esc")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Button { model.onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.secondary.opacity(0.16)))
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
            if !model.query.text.isEmpty {
                Button {
                    model.query.text = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
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
            Image(systemName: style.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(on ? style.onColor : style.color)
                .frame(width: 27, height: 27)
                .background(Circle().fill(on ? AnyShapeStyle(style.color) : AnyShapeStyle(style.color.opacity(0.16))))
        }
        .buttonStyle(.plain)
        .help(kind.rawValue.capitalized)
    }

    /// Visual break between pinned cards and the rest.
    private var pinnedDivider: some View {
        VStack(spacing: 8) {
            Image(systemName: "pin.fill").font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.accent)
            RoundedRectangle(cornerRadius: 1).fill(DS.hairline(scheme))
                .frame(width: 2)
        }
        .frame(width: 28)
        .frame(maxHeight: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.lg) {
                    let list = model.filtered()
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0, list[idx - 1].isPinned, !item.isPinned {
                            pinnedDivider
                        }
                        ClipCard(item: item,
                                 index: model.slot(for: item),
                                 slotCount: model.slotCount,
                                 isSelected: idx == model.selection,
                                 accent: theme.accent,
                                 accentGradient: theme.accentGradient,
                                 section: sectionTag(for: item),
                                 onPin: { Task { await model.togglePin(item) } },
                                 onDelete: { Task { await model.delete(item) } },
                                 onRename: { newTitle in Task { await model.setTitle(item, newTitle) } },
                                 onEditBody: { newText in Task { await model.updateText(item, newText: newText) } },
                                 onAssignSlot: { n in Task { await model.assignSlot(item, slot: n) } },
                                 onEditingChanged: { model.isEditingTitle = $0 })
                            .id(item.id)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .draggable(item.id.uuidString) { dragPreview(item) }
                            .onTapGesture {
                                model.selection = idx
                                model.pasteSelected()
                            }
                            .contextMenu { cardMenu(item) }
                    }
                }
                .padding(.horizontal, DS.Space.lg).padding(.vertical, DS.Space.lg)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82),
                           value: model.items)
            }
            .scrollClipDisabled()
            .frame(height: DS.CardSize.height + 2 * DS.Space.lg)
            .onChange(of: model.selection) { _, _ in scrollToSelection(proxy) }
        }
    }

    /// Compact preview so the dragged tile shrinks and doesn't cover the groups.
    private func dragPreview(_ item: ClipItem) -> some View {
        let style = KindStyle.of(item.kind)
        return HStack(spacing: 6) {
            Image(systemName: style.icon).font(.system(size: 11, weight: .bold))
            Text(item.textPlain?.prefix(24).description ?? style.label)
                .font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(style.color.gradient))
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        let list = model.filtered()
        guard list.indices.contains(model.selection) else { return }
        let id = list[model.selection].id
        if reduceMotion { proxy.scrollTo(id, anchor: .center) }
        else { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) } }
    }

    /// The section a card is filed in, as a (name, colour) tag. Type stays the
    /// header colour; the section shows as a separate tag.
    private func sectionTag(for item: ClipItem) -> (name: String, color: Color)? {
        guard let id = item.sectionID,
              let s = model.sections.first(where: { $0.id == id }) else { return nil }
        return (s.name, Color(hex: s.colorHex) ?? .gray)
    }

    @ViewBuilder private func cardMenu(_ item: ClipItem) -> some View {
        Button(item.isPinned ? "Unpin" : "Pin to front") { Task { await model.togglePin(item) } }
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
        .frame(height: DS.CardSize.height + 2 * DS.Space.lg)
        .frame(maxWidth: .infinity)
    }
}
