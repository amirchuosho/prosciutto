import Foundation

public enum UpdateError: Error, Equatable {
    case offline, rateLimited, noRelease, badResponse
}

public protocol ReleaseProvider {
    /// The latest published (non-draft, non-prerelease) version tag, e.g. "v0.5.0".
    func latestVersion() async throws -> String
}

/// Reads the latest GitHub release tag. `/releases/latest` already excludes drafts and
/// pre-releases server-side. The `fetch` seam is injected so tests feed canned responses.
public struct GitHubReleaseProvider: ReleaseProvider {
    public typealias Fetch = (URL) async throws -> (Data, URLResponse)
    private let url: URL
    private let fetch: Fetch

    public init(owner: String = "amirchuosho", repo: String = "prosciutto",
                fetch: @escaping Fetch = { try await URLSession.shared.data(from: $0) }) {
        self.url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        self.fetch = fetch
    }

    public func latestVersion() async throws -> String {
        let data: Data, response: URLResponse
        do { (data, response) = try await fetch(url) }
        catch { throw UpdateError.offline }
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        switch http.statusCode {
        case 200: break
        case 403, 429: throw UpdateError.rateLimited
        case 404: throw UpdateError.noRelease
        default: throw UpdateError.badResponse
        }
        struct Release: Decodable { let tag_name: String }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.tag_name.isEmpty else { throw UpdateError.badResponse }
        return release.tag_name
    }
}
