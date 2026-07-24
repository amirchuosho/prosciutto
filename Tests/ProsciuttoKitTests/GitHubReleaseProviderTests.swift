import XCTest
@testable import ProsciuttoKit

final class GitHubReleaseProviderTests: XCTestCase {
    private func provider(status: Int, body: String) -> GitHubReleaseProvider {
        GitHubReleaseProvider(fetch: { url in
            let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), resp)
        })
    }

    func testParsesTagName() async throws {
        let v = try await provider(status: 200, body: #"{"tag_name":"v0.5.0"}"#).latestVersion()
        XCTAssertEqual(v, "v0.5.0")
    }
    func testRateLimited() async {
        await assertThrows(provider(status: 403, body: ""), .rateLimited)
    }
    func testRateLimitedOn429() async {
        await assertThrows(provider(status: 429, body: ""), .rateLimited)
    }
    func testUnexpectedStatusIsBadResponse() async {
        await assertThrows(provider(status: 500, body: ""), .badResponse)
    }
    func testNonHTTPResponseIsBadResponse() async {
        let p = GitHubReleaseProvider(fetch: { url in
            (Data(#"{"tag_name":"v0.5.0"}"#.utf8), URLResponse(url: url, mimeType: nil,
                                                              expectedContentLength: 0, textEncodingName: nil))
        })
        await assertThrows(p, .badResponse)
    }
    func testNoRelease() async {
        await assertThrows(provider(status: 404, body: ""), .noRelease)
    }
    func testMalformedBody() async {
        await assertThrows(provider(status: 200, body: "not json"), .badResponse)
    }
    func testOfflineWhenFetchThrows() async {
        let p = GitHubReleaseProvider(fetch: { _ in throw URLError(.notConnectedToInternet) })
        await assertThrows(p, .offline)
    }

    private func assertThrows(_ p: GitHubReleaseProvider, _ expected: UpdateError,
                              file: StaticString = #file, line: UInt = #line) async {
        do { _ = try await p.latestVersion(); XCTFail("expected throw", file: file, line: line) }
        catch let e as UpdateError { XCTAssertEqual(e, expected, file: file, line: line) }
        catch { XCTFail("wrong error type: \(error)", file: file, line: line) }
    }
}
