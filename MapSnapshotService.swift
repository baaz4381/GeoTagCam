import MapKit
import UIKit

@MainActor
final class MapSnapshotService: ObservableObject {
    @Published private(set) var image: UIImage?

    private var lastCoordinate: CLLocationCoordinate2D?
    private var lastKind: MapKind?
    private var busy = false

    func refresh(coordinate: CLLocationCoordinate2D, kind: MapKind) async {
        if let last = lastCoordinate, lastKind == kind {
            let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if d < 15 { return }
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400)
        options.size = CGSize(width: 240, height: 240)
        switch kind {
        case .standard: options.mapType = .standard
        case .satellite: options.mapType = .satellite
        case .hybrid: options.mapType = .hybrid
        }

        do {
            let snap = try await MKMapSnapshotter(options: options).start()
            let pinned = Self.drawPin(on: snap, at: coordinate)
            image = pinned
            lastCoordinate = coordinate
            lastKind = kind
        } catch {
            // Offline: keep the last map (it is cleared by distance check on next success).
        }
    }

    private static func drawPin(on snap: MKMapSnapshotter.Snapshot, at coordinate: CLLocationCoordinate2D) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snap.image.size)
        return renderer.image { ctx in
            snap.image.draw(at: .zero)
            let p = snap.point(for: coordinate)
            let r: CGFloat = 7
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.5).cgColor)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.systemRed.setFill()
            UIBezierPath(ovalIn: rect).fill()
        }
    }
}
