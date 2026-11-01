import CoreLocation
import Combine

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: CLHeading?
    @Published private(set) var address = AddressInfo()
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocoded: CLLocation?
    private var lastGeocodeTime = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        manager.headingFilter = 2
        manager.activityType = .other
        authorization = manager.authorizationStatus
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// True when iOS reports the fix came from a software simulation (e.g. Xcode or a spoofing tool).
    var isSimulated: Bool {
        guard let info = location?.sourceInformation else { return false }
        return info.isSimulatedBySoftware
    }

    func start() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        if abs(l.timestamp.timeIntervalSinceNow) > 20 { return }   // ignore stale cached fixes
        location = l
        geocodeIfNeeded(l)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }

    // MARK: Reverse geocoding

    private func geocodeIfNeeded(_ l: CLLocation) {
        // Never keep showing an address from a place the user has already left.
        if let last = lastGeocoded, l.distance(from: last) > 200 {
            address = AddressInfo()
            lastGeocoded = nil
        }
        guard !geocoder.isGeocoding else { return }
        if let last = lastGeocoded, l.distance(from: last) < 25,
           Date().timeIntervalSince(lastGeocodeTime) < 120 { return }
        if Date().timeIntervalSince(lastGeocodeTime) < 5 { return }
        lastGeocodeTime = Date()

        geocoder.reverseGeocodeLocation(l) { [weak self] marks, _ in
            guard let self, let p = marks?.first else { return }
            self.lastGeocoded = l
            self.address = AddressInfo(placemark: p)
        }
    }
}

// MARK: - Helpers

extension CLHeading {
    /// True north when available, otherwise magnetic north.
    var bestHeading: Double { trueHeading >= 0 ? trueHeading : magneticHeading }
    /// Total magnetic field strength in microtesla.
    var totalField: Double { (x * x + y * y + z * z).squareRoot() }
}

func compassName(_ degrees: Double) -> String {
    let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    var d = degrees.truncatingRemainder(dividingBy: 360)
    if d < 0 { d += 360 }
    return names[Int((d / 22.5).rounded()) % 16]
}
