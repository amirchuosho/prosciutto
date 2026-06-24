import SwiftUI
import ProsciuttoKit

struct TextCard: View {
    let item: ClipItem
    var body: some View {
        Text(item.textPlain ?? "")
            .font(.system(size: 14))
            .lineLimit(8)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(13)
    }
}
