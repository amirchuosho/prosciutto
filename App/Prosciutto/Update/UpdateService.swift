import Foundation
import ProsciuttoKit

@MainActor
final class UpdateService: ObservableObject {
    enum Availability: Equatable {
        case unknown, checking, upToDate
        case available(String)          // the newer version tag
        case failed(UpdateError)
    }
    enum Trigger { case launch, manual }

    @Published private(set) var availability: Availability = .unknown
    let currentVersion: String

    private let provider: ReleaseProvider
    private let throttle: TimeInterval
    private let now: () -> Date
    private let launchEnabled: () -> Bool
    private let lastCheck: () -> Date?
    private let setLastCheck: (Date) -> Void

    init(provider: ReleaseProvider,
         currentVersion: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0",
         throttle: TimeInterval = 24 * 3600,
         now: @escaping () -> Date = Date.init,
         launchEnabled: @escaping () -> Bool = { Preferences.shared.checkForUpdatesOnLaunch },
         lastCheck: @escaping () -> Date? = { Preferences.shared.lastUpdateCheckAt },
         setLastCheck: @escaping (Date) -> Void = { Preferences.shared.lastUpdateCheckAt = $0 }) {
        self.provider = provider
        self.currentVersion = currentVersion
        self.throttle = throttle
        self.now = now
        self.launchEnabled = launchEnabled
        self.lastCheck = lastCheck
        self.setLastCheck = setLastCheck
    }

    /// `.launch`: silent, gated by the preference + the 24h throttle. `.manual`: always
    /// runs and always leaves a user-surfaceable result in `availability`.
    func check(_ trigger: Trigger) async {
        if trigger == .launch {
            guard launchEnabled() else { return }
            if let last = lastCheck(), now().timeIntervalSince(last) < throttle { return }
        }
        availability = .checking
        do {
            let latest = try await provider.latestVersion()
            setLastCheck(now())
            availability = VersionComparator.isNewer(latest, than: currentVersion)
                ? .available(latest) : .upToDate
        } catch let e as UpdateError {
            availability = .failed(e)
        } catch {
            availability = .failed(.badResponse)
        }
    }
}
