import SwiftUI
import ProsciuttoKit

struct CodeCard: View {
    let item: ClipItem
    var body: some View {
        Text(item.textPlain ?? "")
            .font(.system(size: 11.5, design: .monospaced))
            .lineLimit(9)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(13)
            .background(Color.black.opacity(0.22))
    }
}
