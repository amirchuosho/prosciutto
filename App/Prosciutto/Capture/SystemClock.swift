import Foundation
import ProsciuttoKit

struct SystemClock: Clock {
    func now() -> Date { Date() }
}
