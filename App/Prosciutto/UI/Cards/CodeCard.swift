import SwiftUI
import ProsciuttoKit

struct CodeCard: View {
    let item: ClipItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.textPlain ?? "")
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.caption2)
                Text("Code").font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.black.opacity(0.04))
    }
}
