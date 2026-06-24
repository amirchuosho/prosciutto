import SwiftUI
import ProsciuttoKit

struct CodeCard: View {
    let item: ClipItem
    var body: some View {
        Text(item.textPlain ?? "")
            .font(.system(size: 10.5, design: .monospaced))
            .lineLimit(7)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(11)
            .background(Color.black.opacity(0.18))
    }
}
