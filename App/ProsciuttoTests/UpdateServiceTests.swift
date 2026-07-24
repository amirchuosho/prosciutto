import XCTest
import ProsciuttoKit
@testable import Prosciutto

@MainActor
final class UpdateServiceTests: XCTestCase {
    private struct StubProvider: ReleaseProvider {
        var result: Result<String, UpdateError>
        var calls: Box
        final class Box { var count = 0 }
        func latestVersion() async throws -> String {
            calls.count += 1
            switch result { case .success(let v): return v; case .failure(let e): throw e }
        }
    }

    private func make(_ result: Result<String, UpdateError>, current: String = "0.4.3",
                      enabled: Bool = true, last: Date? = nil, now: Date = Date(),
                      calls: StubProvider.Box = .init()) -> UpdateService {
        UpdateService(provider: StubProvider(result: result, calls: calls),
                      currentVersion: current, throttle: 24 * 3600,
                      now: { now }, launchEnabled: { enabled },
                      lastCheck: { last }, setLastCheck: { _ in })
    }

    func testManualNewerBecomesAvailable() async {
        let vm = make(.success("v0.5.0"))
        await vm.check(.manual)
        XCTAssertEqual(vm.availability, .available("v0.5.0"))
    }
    func testManualEqualBecomesUpToDate() async {
        let vm = make(.success("0.4.3"))
        await vm.check(.manual)
        XCTAssertEqual(vm.availability, .upToDate)
    }
    func testManualErrorBecomesFailed() async {
        let vm = make(.failure(.offline))
        await vm.check(.manual)
        XCTAssertEqual(vm.availability, .failed(.offline))
    }
    func testManualBypassesDisabledAndThrottle() async {
        // .manual must ignore both the launch preference AND the throttle window.
        let box = StubProvider.Box()
        let now = Date()
        let vm = make(.success("v0.5.0"), enabled: false, last: now, now: now, calls: box)
        await vm.check(.manual)
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(vm.availability, .available("v0.5.0"))
    }
    func testNonUpdateErrorMapsToBadResponse() async {
        // A provider throwing something other than UpdateError → .failed(.badResponse).
        struct Boom: Error {}
        struct ThrowingProvider: ReleaseProvider {
            func latestVersion() async throws -> String { throw Boom() }
        }
        let vm = UpdateService(provider: ThrowingProvider(), currentVersion: "0.4.3",
                               now: { Date() }, launchEnabled: { true },
                               lastCheck: { nil }, setLastCheck: { _ in })
        await vm.check(.manual)
        XCTAssertEqual(vm.availability, .failed(.badResponse))
    }
    func testLaunchDisabledDoesNotCheck() async {
        let box = StubProvider.Box()
        let vm = make(.success("v0.5.0"), enabled: false, calls: box)
        await vm.check(.launch)
        XCTAssertEqual(box.count, 0)
        XCTAssertEqual(vm.availability, .unknown)
    }
    func testLaunchThrottledSkips() async {
        let box = StubProvider.Box()
        let now = Date()
        let vm = make(.success("v0.5.0"), last: now.addingTimeInterval(-3600), now: now, calls: box)
        await vm.check(.launch)   // last check 1h ago, throttle 24h -> skip
        XCTAssertEqual(box.count, 0)
    }
    func testLaunchPastThrottleChecks() async {
        let box = StubProvider.Box()
        let now = Date()
        let vm = make(.success("v0.5.0"), last: now.addingTimeInterval(-25 * 3600), now: now, calls: box)
        await vm.check(.launch)
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(vm.availability, .available("v0.5.0"))
    }
}
