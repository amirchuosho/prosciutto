import SwiftUI
import ProsciuttoKit

struct GalleryView: View {
    @ObservedObject var model: GalleryViewModel
    let onDismiss: () -> Void
    @FocusState private var searchFocused: Bool

    private let kinds: [ClipKind] = [.text, .link, .image, .color, .code, .file]

    var body: some View {
        VStack(spacing: 10) {
            header
            cards
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard…", text: $model.query.text)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(8)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: 280)

            ForEach(kinds, id: \.self) { kind in
                filterPill(kind)
            }
            Spacer()
        }
    }

    private func filterPill(_ kind: ClipKind) -> some View {
        let on = model.query.kinds.contains(kind)
        return Button {
            if on { model.query.kinds.remove(kind) } else { model.query.kinds.insert(kind) }
        } label: {
            Text(kind.rawValue.capitalized)
                .font(.caption2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(on ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    let list = model.filtered()
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, item in
                        ClipCard(item: item, index: idx + 1, isSelected: idx == model.selection)
                            .id(idx)
                            .onTapGesture {
                                model.selection = idx
                                model.pasteSelected()
                            }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 140)
            .onChange(of: model.selection) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
            .background(keyHandlers)
        }
    }

    private var keyHandlers: some View {
        ZStack {
            Button("") { model.moveSelection(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { model.moveSelection(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.pasteSelected() }.keyboardShortcut(.return, modifiers: [])
            Button("") { onDismiss() }.keyboardShortcut(.escape, modifiers: [])
            Button("") { model.pasteSelected(asPlainText: true) }.keyboardShortcut("v", modifiers: [.command, .option])
            ForEach(1...9, id: \.self) { n in
                Button("") { model.pasteIndex(n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
