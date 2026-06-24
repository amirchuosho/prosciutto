import SwiftUI
import ProsciuttoKit

struct EditSheet: View {
    let item: ClipItem
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(item: ClipItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _text = State(initialValue: item.textPlain ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: KindStyle.of(item.kind).icon)
                    .foregroundStyle(KindStyle.of(item.kind).color)
                Text("Edit \(item.kind.rawValue)").font(.headline)
            }
            TextEditor(text: $text)
                .font(.system(size: 13, design: item.kind == .code ? .monospaced : .default))
                .frame(minWidth: 380, minHeight: 180)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}
