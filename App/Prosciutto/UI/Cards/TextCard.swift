import SwiftUI
import ProsciuttoKit

struct TextCard: View {
    let item: ClipItem
    var body: some View {
        Text(item.textPlain ?? "")
            .font(.system(size: 12))
            .lineLimit(6)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(11)
    }
}
