import SwiftUI
import ProsciuttoKit

struct GalleryView: View {
    @ObservedObject var model: GalleryViewModel
    @EnvironmentObject var theme: ThemeManager
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onEdit: (ClipItem) -> Void = { _ in }

    private let kinds: [ClipKind] = [.text, .link, .image, .color, .code, .file]

    var body: some View {
        VStack(spacing: 12) {
            header
            Group {
                if model.filtered().isEmpty {
                    emptyState
                } else {
                    cards
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08)))
        )
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .onAppear { searchFocused = true }
        .background(keyHandlers)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard…", text: $model.query.text)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: 260)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(kinds, id: \.self) { filterPill($0) }
                }
            }
            Spacer(minLength: 0)
            Text("⌘1–9 paste · ⏎ select · esc close")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
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
                            .id(idx)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
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
            .frame(height: 156)
            .onChange(of: model.selection) { _, newValue in
                guard !reduceMotion else { proxy.scrollTo(newValue, anchor: .center); return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func editClosure(for item: ClipItem) -> (() -> Void)? {
        switch item.kind {
        case .text, .rtf, .code, .link, .color: return { onEdit(item) }
        default: return nil
        }
    }

    @ViewBuilder private func cardMenu(_ item: ClipItem) -> some View {
        Button(item.isPinned ? "Unpin" : "Pin to front") { Task { await model.togglePin(item) } }
        if editClosure(for: item) != nil {
            Button("Edit…") { onEdit(item) }
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
        .frame(height: 156)
        .frame(maxWidth: .infinity)
    }

    // MARK: Keyboard

    private var keyHandlers: some View {
        ZStack {
            Button("") { model.moveSelection(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { model.moveSelection(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.pasteSelected() }.keyboardShortcut(.return, modifiers: [])
            Button("") { model.onDismiss() }.keyboardShortcut(.escape, modifiers: [])
            Button("") { model.pasteSelected(asPlainText: true) }
                .keyboardShortcut("v", modifiers: [.command, .option])
            ForEach(1...9, id: \.self) { n in
                Button("") { model.pasteIndex(n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .opacity(0).frame(width: 0, height: 0)
    }
}
