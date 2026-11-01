import UIKit
import ImageIO
import CoreLocation

/// Reads the original GPS position and capture time from an existing photo so it can be stamped.
/// If the photo has no GPS data, the stamp says "Location unavailable" rather than guessing.
enum ImportService {

    @MainActor
    static func snapshot(from data: Data, cfg: StampSettings) async -> CaptureSnapshot {
        var location: CLLocation?
        var date = Date()
        var heading: Double?

        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {

            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy:MM:dd HH:mm:ss"
                if let d = f.date(from: text) { date = d }
            }

            if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
               var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               var lon = gps[kCGImagePropertyGPSLongitude] as? Double {
                if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
                if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }

                var altitude = 0.0
                var vertical = -1.0
                if var a = gps[kCGImagePropertyGPSAltitude] as? Double {
                    if let ref = gps[kCGImagePropertyGPSAltitudeRef] as? Int, ref == 1 { a = -a }
                    altitude = a
                    vertical = 10
                }
                let horizontal = (gps[kCGImagePropertyGPSHPositioningError] as? Double) ?? -1
                location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: altitude,
                    horizontalAccuracy: horizontal,
                    verticalAccuracy: vertical,
                    timestamp: date
                )
                heading = gps[kCGImagePropertyGPSImgDirection] as? Double
            }
        }

        var address = AddressInfo()
        var map: UIImage?
        if let loc = location {
            if let marks = try? await CLGeocoder().reverseGeocodeLocation(loc), let p = marks.first {
                address = AddressInfo(placemark: p)
            }
            let needMap = cfg.template == .classic || (cfg.template == .advanced && cfg.showMap)
            if needMap {
                let service = MapSnapshotService()
                await service.refresh(coordinate: loc.coordinate, kind: cfg.mapKind)
                map = service.image
            }
        }

        var snap = CaptureSnapshot(
            date: date,
            location: location,
            address: address,
            headingDeg: heading,
            magneticUT: nil,
            weather: nil,
            map: map,
            simulated: false,
            phase: ""
        )
        snap.imported = true
        return snap
    }
}
