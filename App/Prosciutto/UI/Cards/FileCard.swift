import SwiftUI
import ProsciuttoKit
import UniformTypeIdentifiers

struct FileCard: View {
    let item: ClipItem
    /// A file clip stores one path, or several newline-joined (multi-file copy).
    private var paths: [String] {
        (item.textPlain ?? "").split(separator: "\n").map(String.init)
    }
    private var path: String { paths.first ?? "" }
    private var url: URL { URL(fileURLWithPath: path) }
    private var name: String { (path as NSString).lastPathComponent }

    private var isImage: Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    var body: some View {
        if paths.count > 1 {
            multiFile                                   // several files → names + count, no preview
        } else if isImage, let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .bottom) {
                    Text(name).font(.system(size: 10, weight: .medium))
                        .lineLimit(1).foregroundStyle(.white)
                        .padding(.vertical, 4).frame(maxWidth: .infinity)
                        .background(.black.opacity(0.4))
                }
        } else {
            VStack(spacing: 9) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable().frame(width: 46, height: 46)
                Text(name)
                    .font(.system(size: 11.5))
                    .lineLimit(2).multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(11)
        }
    }

    /// Multiple copied files: a stacked-doc glyph, the count, and the first few
    /// names — no single-image preview (which was confusing for a batch of pics).
    private var multiFile: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text("\(paths.count) files")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(paths.prefix(4), id: \.self) { p in
                    Text((p as NSString).lastPathComponent)
                        .font(.system(size: 10.5)).lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                if paths.count > 4 {
                    Text("+ \(paths.count - 4) more")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(11)
    }
}
