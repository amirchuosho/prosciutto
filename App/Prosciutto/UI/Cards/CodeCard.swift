import SwiftUI
import ProsciuttoKit

struct CodeCard: View {
    let item: ClipItem
    var body: some View {
        Text(item.textPlain ?? "")
            .font(DS.Font.contentMono)
            .lineLimit(10)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(DS.Space.lg)
            .background(Color.black.opacity(0.18))
    }
}
