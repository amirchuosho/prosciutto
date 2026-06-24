import SwiftUI
import ProsciuttoKit

struct LinkCard: View {
    let item: ClipItem
    private var url: URL? { item.textPlain.flatMap { URL(string: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                favicon
                Text(url?.host ?? "Link")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Text(item.textPlain ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 30, leading: 11, bottom: 10, trailing: 11))
    }

    @ViewBuilder private var favicon: some View {
        if let host = url?.host, let faviconURL = URL(string: "https://\(host)/favicon.ico") {
            AsyncImage(url: faviconURL) { image in
                image.resizable().frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 3))
            } placeholder: {
                Image(systemName: "link").font(.caption)
            }
        } else {
            Image(systemName: "link").font(.caption)
        }
    }
}
