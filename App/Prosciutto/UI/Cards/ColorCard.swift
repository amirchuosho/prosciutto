import SwiftUI
import ProsciuttoKit

struct ColorCard: View {
    let item: ClipItem
    private var hex: String { item.textPlain ?? "#000000" }

    var body: some View {
        ZStack(alignment: .bottom) {
            (Color(hex: hex) ?? .gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(hex.uppercased())
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.vertical, 6).frame(maxWidth: .infinity)
                .background(.black.opacity(0.35))
        }
    }
}
