import UIKit
import CoreLocation

struct AddressInfo: Equatable {
    var title: String? = nil        // "City, State, Country"
    var detail: String? = nil       // "Street / area, postcode"
    var countryCode: String? = nil

    init(title: String? = nil, detail: String? = nil, countryCode: String? = nil) {
        self.title = title
        self.detail = detail
        self.countryCode = countryCode
    }

    init(placemark p: CLPlacemark) {
        let titleParts = [p.locality, p.administrativeArea, p.country].compactMap { $0 }
        let detailRaw = [p.name, p.subLocality, p.postalCode].compactMap { $0 }
        var detail: [String] = []
        for d in detailRaw where !detail.contains(d) && !titleParts.contains(d) {
            detail.append(d)
        }
        self.title = titleParts.isEmpty ? nil : titleParts.joined(separator: ", ")
        self.detail = detail.isEmpty ? nil : detail.joined(separator: ", ")
        self.countryCode = p.isoCountryCode
    }

    var flag: String? {
        guard let cc = countryCode, cc.count == 2 else { return nil }
        let scalars = cc.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
        guard scalars.count == 2 else { return nil }
        return scalars.map { String($0) }.joined()
    }

    var full: String {
        [detail, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var isEmpty: Bool { (title ?? "").isEmpty && (detail ?? "").isEmpty }
}

struct Weather: Equatable {
    var tempC: Double
    var humidity: Double
    var windKmh: Double
    var pressureHpa: Double
}

/// Everything known at the moment the shutter is pressed.
struct CaptureSnapshot {
    var date: Date
    var location: CLLocation?
    var address: AddressInfo
    var headingDeg: Double?
    var magneticUT: Double?
    var weather: Weather?
    var map: UIImage?
    var simulated: Bool
    var phase: String
    // Added later, all optional-by-default so older call sites keep working.
    var serial: Int? = nil
    var isVideo = false
    var imported = false
    var withSeconds = false
}

/// The text and images that go into the stamp. Used by both the live preview and the final render.
struct StampContent {
    var badge: String? = nil
    var title: String = ""
    var lines: [String] = []
    var metrics: [String] = []
    var tags: [String] = []
    var warning: String? = nil
    var map: UIImage? = nil
    var logo: UIImage? = nil
    var qr: UIImage? = nil
}
