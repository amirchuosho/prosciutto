import SwiftUI
import MapKit
import ProsciuttoKit

/// Process-wide cache of rendered map snapshots, keyed by the clip text + theme.
/// The gallery's LazyHStack recreates cards as they scroll in and out; without a
/// cache each re-appearance would re-geocode + re-snapshot, hitching the scroll.
@MainActor private enum MapSnapshotCache {
    static var store: [String: NSImage] = [:]
    static let limit = 60
    static func get(_ key: String) -> NSImage? { store[key] }
    static func set(_ key: String, _ image: NSImage) {
        if store.count >= limit { store.removeAll() }   // simple bound
        store[key] = image
    }
}

/// Renders a map preview for a location clip — coordinates ("lat, long") shown
/// directly, or a postal address geocoded to a point. Falls back to a pin icon
/// if the point can't be resolved.
struct LocationCard: View {
    let item: ClipItem

    @State private var snapshot: NSImage?
    @State private var failed = false
    @Environment(\.colorScheme) private var scheme

    private var text: String { (item.textPlain ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let snapshot {
                    Image(nsImage: snapshot)
                        .resizable().aspectRatio(contentMode: .fill)
                        .overlay(
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.red)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                        )
                } else if failed {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 34)).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.42))
        }
        .task(id: text) { await load() }
    }

    private var cacheKey: String { "\(text)|\(scheme == .dark ? "d" : "l")" }

    private func load() async {
        if let cached = MapSnapshotCache.get(cacheKey) { snapshot = cached; failed = false; return }
        snapshot = nil; failed = false
        guard let coord = await resolveCoordinate() else { failed = true; return }
        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(center: coord,
                                         latitudinalMeters: 700, longitudinalMeters: 700)
        opts.size = CGSize(width: DS.CardSize.width, height: 210)
        opts.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        if let result = try? await MKMapSnapshotter(options: opts).start() {
            MapSnapshotCache.set(cacheKey, result.image)
            snapshot = result.image
        } else {
            failed = true
        }
    }

    /// A "lat, long" pair, else geocode the string as an address.
    private func resolveCoordinate() async -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",")
        if parts.count == 2,
           let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
           let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)),
           (-90...90).contains(lat), (-180...180).contains(lon) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let placemarks = try? await CLGeocoder().geocodeAddressString(text),
           let loc = placemarks.first?.location {
            return loc.coordinate
        }
        return nil
    }
}
