import SwiftUI
import ProsciuttoKit

struct EditSectionSheet: View {
    let section: ClipSection
    let palette: [String]
    let onSave: (String, String) -> Void   // name, colorHex
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String

    init(section: ClipSection, palette: [String], onSave: @escaping (String, String) -> Void) {
        self.section = section
        self.palette = palette
        self.onSave = onSave
        _name = State(initialValue: section.name)
        _colorHex = State(initialValue: section.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit section").font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("Color").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(palette, id: \.self) { hex in
                    let color = Color(hex: hex) ?? .gray
                    Button { colorHex = hex } label: {
                        ZStack {
                            Circle().fill(color).frame(width: 30, height: 30)
                            if colorHex == hex {
                                Circle().strokeBorder(.primary, lineWidth: 2.5).frame(width: 36, height: 36)
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(name, colorHex); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}
