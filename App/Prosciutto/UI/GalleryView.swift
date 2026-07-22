import SwiftUI
import ProsciuttoKit

/// Each card reports its frame (in the strip's coordinate space) so the strip can
/// tell which card the cursor is over from one central hover tracker.
private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The previewed card's id + on-screen (SwiftUI global) frame, or nil when no preview
/// is up. Only the card matching `previewID` emits it, so the whole strip reports at
/// most one anchor — the floating image preview positions itself from it.
struct PreviewAnchor: Equatable { let id: UUID; let rect: CGRect }
private struct PreviewAnchorKey: PreferenceKey {
    static var defaultValue: PreviewAnchor? = nil
    static func reduce(value: inout PreviewAnchor?, nextValue: () -> PreviewAnchor?) {
        value = value ?? nextValue()
    }
}

struct GalleryView: View {
    @ObservedObject var model: GalleryViewModel
    @EnvironmentObject var theme: ThemeManager
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingSection: ClipSection?
    @State private var showingAddSection = false
    @State private var newSectionName = ""
    @State private var dropPulse: UUID?
    /// The section chip a drag is currently hovering, highlighted as the drop target.
    @State private var dropTarget: UUID?
    /// The single card currently under the pointer, computed from the cursor position
    /// against each card's frame — one tracker, so it can't miss enter/exit events.
    @State private var hoveredID: UUID?
    @State private var cardFrames: [UUID: CGRect] = [:]
    /// Last cursor position reported by the hover tracker (strip coords). Kept so the
    /// hovered tile can be recomputed after a reflow when the cursor hasn't moved.
    @State private var lastHoverPoint: CGPoint?

    private let kinds: [ClipKind] = [.text, .link, .image, .video, .color, .code, .file, .location]

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
        // Clip everything to the panel's rounded rect. The horizontal scroll strip uses
        // `scrollClipDisabled` so the selected tile's scale/glow can overflow the strip
        // frame — this panel clip is what then contains that overflow (and any card
        // scrolled to an edge) inside the panel, instead of letting it bleed past the
        // edge. Because the clip is at the panel (not the strip edge), the end cards'
        // glow has the full padding to breathe and is never cropped.
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        // Pin the panel to the bottom of its (slightly taller, see heightSafetyMargin)
        // window so the safety margin is transparent space above the panel, never a gap
        // below it — the strip stays flush at the screen's bottom edge.
        .frame(maxHeight: .infinity, alignment: .bottom)
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
        // Any change to the visible set lands at "home" (newest unpinned + strip to
        // start), exactly like opening the gallery — so section, type and search all
        // behave the same and the highlight never sticks at a stale/out-of-range slot.
        .onChange(of: model.sectionFilter) { _, _ in model.resetToHome() }
        .onChange(of: model.query.kinds) { _, _ in model.resetToHome() }
        .onChange(of: model.query.text) { _, _ in model.resetToHome() }
        // Drive the floating image preview from the previewed card's on-screen frame.
        .onPreferenceChange(PreviewAnchorKey.self) { anchor in
            model.onPreviewAnchor(anchor.map { ($0.id, $0.rect) })
        }
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
                    // Grows a touch on drop (card filed) and while a drag hovers it as the
                    // drop target, so it's clear which chip will receive the drop.
                    .scaleEffect(dropPulse == section.id ? 1.18 : (dropTarget == section.id ? 1.1 : 1))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: dropPulse)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: dropTarget)
                    // Drag a custom chip to reorder it (All/Pinned aren't draggable, so
                    // they stay fixed at the front). Custom preview keeps it clean instead
                    // of the default translucent snapshot.
                    .draggable(section.id.uuidString) { sectionDragPreview(section.name, color) }
                    .dropDestination(for: String.self) { ids, _ in
                        dropTarget = nil
                        guard let s = ids.first, let uuid = UUID(uuidString: s) else { return false }
                        // A dropped section id reorders; anything else is a card being
                        // filed into this section.
                        if model.sections.contains(where: { $0.id == uuid }) {
                            Task { await model.moveSection(uuid, before: section.id) }
                            return true
                        }
                        Task { await model.assignID(uuid, to: section.id) }
                        dropPulse = section.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            if dropPulse == section.id { dropPulse = nil }
                        }
                        return true
                    } isTargeted: { targeted in
                        dropTarget = targeted ? section.id : (dropTarget == section.id ? nil : dropTarget)
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
            // Slide the chips to their new spots when the order changes.
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.sections)
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

    /// The tile shown under the cursor while dragging a section chip to reorder — a clean
    /// filled capsule instead of the default translucent snapshot.
    private func sectionDragPreview(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(name).font(DS.Font.sectionPill)
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, DS.Space.md).padding(.vertical, 7)
        .background(color.opacity(0.9), in: Capsule())
    }

    // MARK: Background

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .fill(theme.palette.background.style)
                .opacity(theme.palette.isDark ? 0.92 : 0.96)
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(theme.palette.hairline, lineWidth: 1)
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
            Text("⌘1–9 · ⏎ · space · esc")
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
        let color = theme.palette.color(for: kind)
        let on = model.query.kinds.contains(kind)
        return Button {
            if on { model.query.kinds.remove(kind) } else { model.query.kinds.insert(kind) }
        } label: {
            Image(systemName: style.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(on ? color.readableText : color)
                .frame(width: 27, height: 27)
                .background(Circle().fill(on ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.16))))
        }
        .buttonStyle(.plain)
        .help(kind.rawValue.capitalized)
    }

    /// Visual break between pinned cards and the rest.
    private var pinnedDivider: some View {
        VStack(spacing: 8) {
            Image(systemName: "pin.fill").font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.accent)
            RoundedRectangle(cornerRadius: 1).fill(theme.palette.hairline)
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
                                 palette: theme.palette,
                                 section: sectionTag(for: item),
                                 onPin: { Task { await model.togglePin(item) } },
                                 onDelete: { Task { await model.delete(item) } },
                                 onRename: { newTitle in Task { await model.setTitle(item, newTitle) } },
                                 onEditBody: { newText in Task { await model.updateText(item, newText: newText) } },
                                 onAssignSlot: { n in Task { await model.assignSlot(item, slot: n) } },
                                 // Select the card being edited, so keyboard delete/paste
                                 // target it and not a stale selection on another tile.
                                 onEditingChanged: { editing in
                                     model.isEditingTitle = editing
                                     if editing { model.select(item) }
                                 },
                                 onEditMedia: { model.editMedia(item) },
                                 onCropMedia: { model.cropMedia(item) },
                                 isHovered: hoveredID == item.id)
                            .equatable()
                            .id(item.id)
                            .background(GeometryReader { g in
                                Color.clear
                                    .preference(key: CardFramesKey.self,
                                                value: [item.id: g.frame(in: .named("galleryStrip"))])
                                    // Only the previewed card reports an anchor, in screen
                                    // (global) coords the floating preview panel positions from.
                                    .preference(key: PreviewAnchorKey.self,
                                                value: item.id == model.previewID
                                                    ? PreviewAnchor(id: item.id, rect: g.frame(in: .global))
                                                    : nil)
                            })
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .draggable(item.id.uuidString) { dragPreview(item) }
                            // First click highlights; a click on the already-selected card pastes.
                            .onTapGesture {
                                if idx == model.selection { model.paste(item) }
                                else { model.selection = idx }
                            }
                            .contextMenu { cardMenu(item) }
                    }
                }
                // Vertical padding only. The HORIZONTAL end spacing is applied as a
                // scroll content margin (below), NOT padding — padding gets scrolled
                // off by `scrollTo(anchor: .leading)`, slamming the first/last card
                // flush against the panel edge. A content margin is respected by the
                // scroll's rest position, so the end cards keep their gap.
                .padding(.vertical, DS.Space.lg)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82),
                           value: model.items)
                // Rebuild the strip when the theme changes so cards render directly
                // in the new palette. Without this, a card that was hidden during the
                // switch keeps its old-theme render, and the next isSelected change
                // animates the colour delta — the tile visibly morphs old→new theme.
                .id(theme.theme)
                .coordinateSpace(name: "galleryStrip")
                .onPreferenceChange(CardFramesKey.self) { frames in
                    cardFrames = frames
                    // After a reflow (a tile deleted, reordered, or the strip
                    // scrolled) a DIFFERENT tile can sit under a stationary cursor
                    // with no mouseMoved to update hover — so the new tile showed no
                    // action bar until the mouse jiggled. Recompute from the last
                    // known point so it appears immediately.
                    hoveredID = lastHoverPoint.flatMap { p in frames.first { $0.value.contains(p) }?.key }
                }
                // ONE hover tracker for the whole strip, via an AppKit NSTrackingArea
                // in a click-transparent overlay. SwiftUI's .onContinuousHover tears
                // down and rebuilds its tracking area every time the strip re-renders
                // (which happens on every hoveredID change), emitting a spurious .ended
                // that cleared hover mid-move — the bar flickered and a click landing in
                // that gap fell through to paste. An NSView's tracking area survives
                // SwiftUI re-renders, so enter/move/exit are reported cleanly. The view
                // sits in the scrolling content, so its local coords match cardFrames
                // even when the strip is scrolled, and hitTest→nil lets clicks through.
                .overlay(
                    StripHoverTracker { pt in
                        lastHoverPoint = pt
                        hoveredID = pt.flatMap { p in cardFrames.first { $0.value.contains(p) }?.key }
                    }
                )
            }
            // End spacing that survives `scrollTo` (see the padding note above): the
            // first/last card rests DS.Space.lg from the edge. A content margin (not
            // padding) is respected by the scroll's rest position, so `scrollTo` can't
            // slam the end card flush against the edge.
            .contentMargins(.horizontal, DS.Space.lg, for: .scrollContent)
            // Let the selected tile's scale/glow overflow the strip frame; the panel-level
            // clip (see body) contains it inside the panel without cropping the glow.
            .scrollClipDisabled()
            .frame(height: DS.CardSize.height + 2 * DS.Space.lg)
            .onChange(of: model.selection) { _, _ in scrollToSelection(proxy) }
            // Declared AFTER the selection handler so, on open, the reset-to-start wins
            // over the selection-follow scroll (both fire in the same update) — the
            // gallery opens showing the pinned tiles from the left.
            .onChange(of: model.homeScrollToken) { _, _ in
                if let first = model.filtered().first { proxy.scrollTo(first.id, anchor: .leading) }
            }
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
        .background(Capsule().fill(theme.palette.color(for: item.kind).gradient))
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        let list = model.filtered()
        guard list.indices.contains(model.selection) else { return }
        // Minimal keep-visible scroll that FOLLOWS the selection — for every card,
        // pinned or not. (Pinned tiles are not one block: there can be up to 9, more
        // than fit on screen, so arrow-navigating among them must scroll too.)
        // anchor:nil moves the strip the minimum to keep the selected card visible, so
        // navigating among already-visible cards doesn't jump. Instant (no
        // withAnimation): an animated scroll of the rich strip drops render-server
        // frames and reads as a hiccup; instant has no motion to drop.
        proxy.scrollTo(list[model.selection].id, anchor: nil)
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

/// Reports the pointer location over the strip via an AppKit tracking area, which —
/// unlike SwiftUI's .onContinuousHover — survives the strip's re-renders and so never
/// emits a spurious exit. `onMove` gets the point in the view's own (flipped, top-left)
/// coordinates, which match the cards' `.named("galleryStrip")` frames, or nil on exit.
/// The view is invisible and transparent to clicks (`hitTest` returns nil), so it only
/// observes movement and never intercepts taps meant for the cards or action buttons.
private struct StripHoverTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackerNSView {
        let v = TrackerNSView(); v.onMove = onMove; return v
    }
    func updateNSView(_ view: TrackerNSView, context: Context) { view.onMove = onMove }

    final class TrackerNSView: NSView {
        var onMove: ((CGPoint?) -> Void)?

        override var isFlipped: Bool { true }   // top-left origin, matches SwiftUI frames
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks pass through

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self))
        }

        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }

        private func report(_ event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }
    }
}
