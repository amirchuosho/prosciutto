import SwiftUI
import ProsciuttoKit

struct FileCard: View {
    let item: ClipItem
    private var path: String { item.textPlain ?? "" }
    private var name: String { (path as NSString).lastPathComponent }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 38, height: 38)
            Text(name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(EdgeInsets(top: 28, leading: 10, bottom: 10, trailing: 10))
    }
}
