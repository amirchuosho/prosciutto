import SwiftUI
import ProsciuttoKit

struct EditSheet: View {
    let item: ClipItem
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var formatError = false

    init(item: ClipItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _text = State(initialValue: item.textPlain ?? "")
    }

    private var isCode: Bool { item.kind == .code }
    private var canFormatJSON: Bool { isCode && Self.prettyJSON(text) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: KindStyle.of(item.kind).icon)
                    .foregroundStyle(KindStyle.of(item.kind).color)
                Text("Edit \(item.kind.rawValue)").font(.headline)
                Spacer()
                if isCode {
                    Button {
                        if let pretty = Self.prettyJSON(text) { text = pretty; formatError = false }
                        else { formatError = true }
                    } label: {
                        Label("Format JSON", systemImage: "curlybraces")
                    }
                    .disabled(!canFormatJSON && !formatError)
                    .help(canFormatJSON ? "Pretty-print JSON" : "Not valid JSON")
                }
            }

            editor

            if formatError {
                Text("Not valid JSON").font(.caption).foregroundStyle(.red)
            }

            HStack {
                Text("\(text.count) characters").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: isCode ? 560 : 440)
    }

    @ViewBuilder private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: isCode ? 12 : 13, design: isCode ? .monospaced : .default))
            .scrollContentBackground(.hidden)
            .frame(minWidth: isCode ? 520 : 380, minHeight: isCode ? 300 : 180)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(isCode ? 0.25 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.2)))
    }

    /// Pretty-print `s` as JSON, or nil if it isn't valid JSON.
    static func prettyJSON(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data,
                        options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj,
                        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let str = String(data: out, encoding: .utf8) else { return nil }
        return str
    }
}
