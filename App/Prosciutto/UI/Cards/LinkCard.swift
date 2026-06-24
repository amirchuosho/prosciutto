import SwiftUI
import ProsciuttoKit

struct LinkCard: View {
    let item: ClipItem
    private var url: URL? { item.textPlain.flatMap { URL(string: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                favicon
                Text(url?.host ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Text(item.textPlain ?? "")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(11)
    }

    @ViewBuilder private var favicon: some View {
        if let host = url?.host, let faviconURL = URL(string: "https://\(host)/favicon.ico") {
            AsyncImage(url: faviconURL) { image in
                image.resizable().frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
            } placeholder: {
                Image(systemName: "link").font(.system(size: 13))
            }
        } else {
            Image(systemName: "link").font(.system(size: 13))
        }
    }
}
