import SwiftUI
import ProsciuttoKit

struct ImageCard: View {
    let item: ClipItem
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 160, height: 120)
                    .clipped()
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(byteString)
                .font(.caption2)
                .padding(4)
                .background(.thinMaterial, in: Capsule())
                .padding(6)
        }
    }
    private var byteString: String {
        let bytes = item.imageData?.count ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
