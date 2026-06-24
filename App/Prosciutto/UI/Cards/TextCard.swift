import SwiftUI
import ProsciuttoKit

struct TextCard: View {
    let item: ClipItem
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.textPlain ?? "")
                .font(.system(size: 11.5))
                .lineLimit(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let app = item.sourceAppName {
                Text(app).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(EdgeInsets(top: 30, leading: 11, bottom: 10, trailing: 11))
    }
}
