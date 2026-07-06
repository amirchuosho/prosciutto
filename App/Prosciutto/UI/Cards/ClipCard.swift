import SwiftUI
import ProsciuttoKit

struct ClipCard: View {
    let item: ClipItem
    /// Quick-paste slot (1–9) this card occupies, or nil if it isn't pinned.
    /// Only pinned cards get a number bubble.
    let index: Int?
    /// Total assignable slots (= pinned count, capped at 9). Bounds the picker.
    var slotCount: Int = 0
    var isSelected: Bool = false
    var accent: Color = .accentColor
    var accentGradient: LinearGradient = LinearGradient(colors: [.accentColor], startPoint: .top, endPoint: .bottom)
    var palette: ThemePalette = ThemePalette(AppTheme.prosciutto.spec(customAccentHex: "#F56B8C"))
    /// The section this card is filed in, shown as a tag. Type stays the header colour.
    var section: (name: String, color: Color)? = nil
    var onPin: () -> Void = {}
    var onDelete: () -> Void = {}
    var onRename: (String) -> Void = { _ in }
    var onEditBody: (String) -> Void = { _ in }
    /// Assign this card to quick-paste slot 1–9 (from the footer slot picker).
    var onAssignSlot: (Int) -> Void = { _ in }
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onEditMedia: () -> Void = {}
    var onCropMedia: () -> Void = {}
    /// Whether the pointer is over this card. Computed centrally by the strip from
    /// the cursor position (see GalleryView), so hover can't miss enter/exit events.
    var isHovered: Bool = false

    @State private var pickingSlot = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool
    @State private var editingBody = false
    @State private var bodyDraft = ""
    @FocusState private var bodyFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: KindStyle { KindStyle.of(item.kind) }
    private var bandColor: Color { palette.color(for: item.kind) }
    private var onBand: Color { bandColor.readableText }
    private var titleLine: String { item.title ?? style.title }
    private var showActions: Bool { isHovered }

    /// Pretty-printed JSON for a code card whose content is valid JSON and not
    /// already formatted; nil otherwise (the Format action is hidden then).
    private var formattableJSON: String? {
        guard item.kind == .code, let raw = item.textPlain,
              let pretty = JSONTools.pretty(raw), pretty != raw else { return nil }
        return pretty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.surface)
                .clipped()
                .overlay(alignment: .bottomTrailing) { if showActions && !editingBody { actionBar } }
            footer
        }
        .frame(width: DS.CardSize.width, height: DS.CardSize.height)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        // Bound the card's tap/drag hit area to its own frame, so nothing inside
        // (e.g. an image) can extend the hittable region over a neighbouring tile.
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(accentGradient) : AnyShapeStyle(palette.hairline),
                              lineWidth: isSelected ? 3 : 1)
        )
        .shadow(color: isSelected ? accent.opacity(0.5) : .black.opacity(scheme == .dark ? 0.4 : 0.12),
                radius: isSelected ? 18 : 12, y: isSelected ? 8 : 6)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.8), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        // Hover is tracked centrally by the strip (GalleryView) via cursor position,
        // not per-card — a single tracking area can't miss enter/exit events or fight
        // a re-render feedback loop the way per-card .onHover/.onContinuousHover did.
        .onChange(of: isHovered) { _, h in
            if !h { withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { pickingSlot = false } }
        }
        // A card can be torn down mid-edit — LazyHStack recycling it off-screen, a
        // filter/section change removing it, or a reload after a new capture. Its
        // local editing @State vanishes with the view, but `vm.isEditingTitle` (the
        // key-monitor guard) is set via a callback and would stay stuck `true`,
        // silently killing arrows AND paste until an app restart. Abandoning any
        // active edit here fires `onEditingChanged(false)`, keeping the guard synced
        // to the editor's real lifecycle.
        .onDisappear {
            if editingTitle { cancelTitleEdit() }
            if editingBody { cancelBodyEdit() }
        }
    }

    // MARK: Header band

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: style.icon).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(onBand.opacity(0.9))
                    titleView
                    if isHovered && !editingTitle {
                        Button { startTitleEdit() } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(onBand.opacity(0.7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Rename")
                    }
                }
                HStack(spacing: 6) {
                    Text(relativeTime).font(DS.Font.cardTime).foregroundStyle(onBand.opacity(0.78))
                    if let section { sectionTag(section) }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(onBand.opacity(0.9))
                }
                appIcon
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm + 1)
        .frame(height: DS.CardSize.header)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            bandColor
            LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
        }
    }

    /// Inline-editable title: click to rename in place, no dialog.
    @ViewBuilder private var titleView: some View {
        if editingTitle {
            TextField(style.title, text: $titleDraft)
                .textFieldStyle(.plain)
                .font(DS.Font.cardTitle)
                .foregroundStyle(onBand)
                .tint(onBand)
                .focused($titleFocused)
                .onSubmit(commitTitle)
                .onExitCommand(perform: cancelTitleEdit)
                .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
        } else {
            Button { startTitleEdit() } label: {
                Text(titleLine).font(DS.Font.cardTitle).foregroundStyle(onBand).lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Click to rename")
        }
    }

    private func startTitleEdit() {
        titleDraft = item.title ?? ""
        editingTitle = true
        titleFocused = true
        onEditingChanged(true)
    }

    private func commitTitle() {
        guard editingTitle else { return }
        editingTitle = false
        onEditingChanged(false)
        onRename(titleDraft)
    }

    private func cancelTitleEdit() {
        guard editingTitle else { return }
        editingTitle = false
        onEditingChanged(false)
    }

    /// Distinct colored chip for the section, so section ≠ type colour.
    private func sectionTag(_ s: (name: String, color: Color)) -> some View {
        HStack(spacing: 3) {
            Circle().fill(s.color.readableText.opacity(0.9)).frame(width: 5, height: 5)
            Text(s.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(s.color.readableText)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(s.color))
    }

    /// A file-backed image (screenshot / edited / Finder image) has no meaningful
    /// copied-from app — the poller just recorded whatever happened to be frontmost,
    /// which often resolves to a blank/generic icon. These are image files, so show
    /// Preview's icon (the app that opens them) instead.
    private var fileBackedImage: Bool { item.kind == .image && item.imageData == nil }

    private var headerIcon: NSImage? {
        if fileBackedImage { return AppIconProvider.icon(forBundleID: "com.apple.Preview") }
        // A recording's recorded-from app is meaningless (whatever was frontmost) —
        // show QuickTime's icon, the app that opens it, like Preview for images.
        if item.kind == .video { return AppIconProvider.icon(forBundleID: "com.apple.QuickTimePlayerX") }
        return AppIconProvider.icon(forBundleID: item.sourceAppBundleID)
    }

    @ViewBuilder private var appIcon: some View {
        if let icon = headerIcon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: DS.CardSize.appIcon, height: DS.CardSize.appIcon)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
        } else {
            Image(systemName: style.icon).font(.system(size: 15, weight: .bold))
                .foregroundStyle(onBand.opacity(0.85))
                .frame(width: DS.CardSize.appIcon, height: DS.CardSize.appIcon)
        }
    }

    // MARK: Footer

    private var footer: some View {
        ZStack {
            HStack(spacing: DS.Space.sm) {
                Text(meta).font(DS.Font.meta).foregroundStyle(palette.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if index != nil { slotChip }          // only pinned cards have a slot
            }
            .opacity(pickingSlot ? 0 : 1)

            if index != nil { slotPicker.allowsHitTesting(pickingSlot) }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    /// The slot bubble (only on pinned cards). Shows the card's ⌘-number; tap to
    /// open the picker and move it to a different slot.
    private var slotChip: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) { pickingSlot = true }
        } label: {
            // Show the actual keystroke — ⌘N — not a bare number, so it's obvious the
            // tile is pasteable with that shortcut while the gallery is open.
            HStack(spacing: 0) {
                Image(systemName: "command").font(.system(size: 8, weight: .heavy))
                Text(index.map(String.init) ?? "").font(DS.Font.shortcut)
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 6).frame(height: 18)
            .background(Capsule().fill(accent.opacity(0.16)))
            .overlay(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Paste with ⌘\(index.map(String.init) ?? "") · click to change slot")
    }

    /// Circles 1…n (n = pinned count) fly out across the footer with a staggered
    /// spring, cascading from the chip (right) outward. Tapping one moves this
    /// card to that slot.
    private var slotPicker: some View {
        let count = max(1, slotCount)
        return HStack(spacing: 4) {
            ForEach(1...count, id: \.self) { n in
                let isCurrent = index == n
                Button {
                    onAssignSlot(n)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { pickingSlot = false }
                } label: {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isCurrent ? .white : .primary.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .background(
                            Circle().fill(isCurrent ? AnyShapeStyle(accentGradient)
                                                     : AnyShapeStyle(Color.primary.opacity(0.08))))
                        .overlay(Circle().strokeBorder(isCurrent ? AnyShapeStyle(accentGradient)
                                                                 : AnyShapeStyle(Color.clear),
                                                       lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .scaleEffect(pickingSlot ? 1 : 0.1)
                .opacity(pickingSlot ? 1 : 0)
                .animation(.spring(response: 0.36, dampingFraction: 0.66)
                            .delay(Double(count - n) * 0.03), value: pickingSlot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 2) {
            actionButton(item.isPinned ? "pin.slash.fill" : "pin.fill", onPin)
            if let pretty = formattableJSON { actionButton("curlybraces") { onEditBody(pretty) } }
            if item.kind.isEditable { actionButton("pencil") { startBodyEdit() } }
            if item.kind == .image { actionButton("pencil.tip.crop.circle", onEditMedia) }
            if item.kind == .video {
                actionButton("arrow.up.forward.app", onEditMedia)   // open/play in QuickTime
                actionButton("scissors", onCropMedia)               // trim in QuickTime
            }
            actionButton("trash.fill", onDelete, destructive: true)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
        .padding(DS.Space.sm)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private func actionButton(_ icon: String, _ action: @escaping () -> Void,
                              destructive: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(destructive ? Color.red.opacity(0.9) : .primary)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Content + meta

    @ViewBuilder private var bodyContent: some View {
        if editingBody {
            if item.kind == .color { colorEditor } else { inlineEditor }
        } else {
            kindContent
        }
    }

    /// Colour-clip editor: native colour wheel (with RGB/HSB tabs) + a hex field,
    /// both bound to `bodyDraft`, with a live preview that updates as you go.
    private var colorEditor: some View {
        VStack(spacing: DS.Space.sm) {
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(Color(hex: bodyDraft) ?? .gray)
                .frame(maxWidth: .infinity).frame(height: 54)
                .overlay(
                    Text((Color(hex: bodyDraft)?.toHex() ?? bodyDraft).uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle((Color(hex: bodyDraft) ?? .gray).readableText)
                )
            HStack(spacing: DS.Space.sm) {
                ColorPicker("", selection: $bodyDraft.asColor(), supportsOpacity: false).labelsHidden()
                TextField("#RRGGBB", text: $bodyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($bodyFocused)
                    .onSubmit(commitColor)
                    .onExitCommand(perform: cancelBodyEdit)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel", action: cancelBodyEdit).font(.system(size: 11))
                Button("Save", action: commitColor)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(DS.Space.sm)
    }

    private func commitColor() {
        let normalized = Color(hex: bodyDraft)?.toHex() ?? bodyDraft   // clean #RRGGBB
        editingBody = false
        onEditingChanged(false)
        onEditBody(normalized)
    }

    @ViewBuilder private var kindContent: some View {
        switch item.kind {
        case .image: ImageCard(item: item)
        case .video: VideoCard(item: item)
        case .link:  LinkCard(item: item)
        case .color: ColorCard(item: item)
        case .code:  CodeCard(item: item)
        case .file:  FileCard(item: item)
        case .location: LocationCard(item: item)
        case .text, .rtf: TextCard(item: item)
        }
    }

    // MARK: Inline body editor (replaces the modal)

    private var inlineEditor: some View {
        VStack(spacing: 0) {
            TextEditor(text: $bodyDraft)
                .font(item.kind == .code ? DS.Font.contentMono : DS.Font.content)
                .scrollContentBackground(.hidden)
                .focused($bodyFocused)
                .onExitCommand(perform: cancelBodyEdit)
                .padding(.horizontal, DS.Space.sm).padding(.top, DS.Space.sm)
            HStack(spacing: DS.Space.sm) {
                if item.kind == .code, JSONTools.pretty(bodyDraft) != nil {
                    Button("Format") { if let p = JSONTools.pretty(bodyDraft) { bodyDraft = p } }
                        .font(.system(size: 11))
                }
                Spacer(minLength: 0)
                Button("Cancel", action: cancelBodyEdit).font(.system(size: 11))
                Button("Save", action: commitBodyEdit)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, DS.Space.sm).padding(.vertical, 6)
        }
    }

    func startBodyEdit() {
        bodyDraft = item.textPlain ?? ""
        editingBody = true
        bodyFocused = true
        onEditingChanged(true)
    }
    private func commitBodyEdit() {
        editingBody = false
        onEditingChanged(false)
        onEditBody(bodyDraft)
    }
    private func cancelBodyEdit() {
        editingBody = false
        onEditingChanged(false)
    }

    private var relativeTime: String {
        let now = Date()
        if now.timeIntervalSince(item.lastUsedAt) < 5 { return "now" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: item.lastUsedAt, relativeTo: now)
    }

    private var meta: String {
        switch item.kind {
        case .text, .rtf, .code: return "\(item.textPlain?.count ?? 0) characters"
        case .link:  return URL(string: item.textPlain ?? "")?.host ?? "Link"
        case .image:
            if let d = item.imageData {
                return ByteCountFormatter.string(fromByteCount: Int64(d.count), countStyle: .file)
            }
            if let p = item.textPlain { return (p as NSString).lastPathComponent }
            return "Image"
        case .color: return item.textPlain ?? "Color"
        case .file:
            let count = (item.textPlain ?? "").split(separator: "\n").count
            return count > 1 ? "\(count) files" : (item.sourceAppName ?? "File")
        case .video:
            if let p = item.textPlain { return (p as NSString).lastPathComponent }
            return "Recording"
        case .location: return "Location"
        }
    }
}

extension ClipCard: Equatable {
    /// Skip re-rendering cards whose render-affecting inputs didn't change. Without
    /// this, every arrow-key selection change re-runs GalleryView.body and hands
    /// each visible card fresh (non-equatable) action closures, so SwiftUI can't
    /// bail out and rebuilds ALL ~7 card bodies per tap — a ~33ms main-thread
    /// stall that drops a frame. Comparing only the value inputs (closures and
    /// imageData excluded) lets only the two cards whose `isSelected` flips rebuild.
    static func == (lhs: ClipCard, rhs: ClipCard) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.isHovered == rhs.isHovered &&
        lhs.index == rhs.index &&
        lhs.slotCount == rhs.slotCount &&
        lhs.accent == rhs.accent &&
        lhs.section?.name == rhs.section?.name &&
        lhs.section?.color == rhs.section?.color &&
        lhs.item.id == rhs.item.id &&
        lhs.item.contentHash == rhs.item.contentHash &&
        lhs.item.title == rhs.item.title &&
        lhs.item.isPinned == rhs.item.isPinned &&
        lhs.item.pinOrder == rhs.item.pinOrder &&
        lhs.item.sectionID == rhs.item.sectionID &&
        lhs.item.lastUsedAt == rhs.item.lastUsedAt &&
        lhs.palette.surface == rhs.palette.surface &&
        lhs.palette.color(for: lhs.item.kind) == rhs.palette.color(for: rhs.item.kind) &&
        lhs.palette.hairline == rhs.palette.hairline &&
        lhs.palette.secondary == rhs.palette.secondary
    }
}
