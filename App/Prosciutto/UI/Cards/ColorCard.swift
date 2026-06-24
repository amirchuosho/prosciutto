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
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
        }
    }
}

extension Color {
    init?(hex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            return nil
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
