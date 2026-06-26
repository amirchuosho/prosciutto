import SwiftUI
import ProsciuttoKit

struct TextCard: View {
    let item: ClipItem
    var body: some View {
        Text(item.textPlain ?? "")
            .font(DS.Font.content)
            .lineLimit(7)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(DS.Space.md)
    }
}
