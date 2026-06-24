import SwiftUI
import ProsciuttoKit

struct FileCard: View {
    let item: ClipItem
    private var path: String { item.textPlain ?? "" }
    private var name: String { (path as NSString).lastPathComponent }

    var body: some View {
        VStack(spacing: 9) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 46, height: 46)
            Text(name)
                .font(.system(size: 11.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(11)
    }
}
