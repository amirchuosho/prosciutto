import Foundation

/// A user-created collection ("tab") that clips can be filed into.
public struct ClipSection: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var sortIndex: Int

    public init(id: UUID = UUID(), name: String, colorHex: String, sortIndex: Int) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}
