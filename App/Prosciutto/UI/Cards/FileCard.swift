import SwiftUI
import ProsciuttoKit
import UniformTypeIdentifiers

struct FileCard: View {
    let item: ClipItem
    private var path: String { item.textPlain ?? "" }
    private var url: URL { URL(fileURLWithPath: path) }
    private var name: String { (path as NSString).lastPathComponent }

    private var isImage: Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    var body: some View {
        if isImage, let img = NSImage(contentsOf: url) {
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
}
