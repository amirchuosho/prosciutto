import SwiftUI
import ProsciuttoKit

struct TextCard: View {
    let item: ClipItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.textPlain ?? "")
                .font(.system(size: 11))
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(10)
    }
    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.alignleft").font(.caption2)
            Text(item.sourceAppName ?? "Text").font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}
