import SwiftUI
import ProsciuttoKit

struct CodeCard: View {
    let item: ClipItem
    var body: some View {
        Text(item.textPlain ?? "")
            .font(.system(size: 10, design: .monospaced))
            .lineLimit(5)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: 30, leading: 11, bottom: 10, trailing: 11))
    }
}
