import Foundation

public protocol Clock: Sendable { func now() -> Date }
