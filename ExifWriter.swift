import Foundation
import ImageIO
import CoreLocation

/// Writes GPS position, direction and capture time into the JPEG's EXIF/GPS metadata
/// (so the photo is "geotagged" for Photos, Maps, Google Photos, GIS tools, etc.).
enum ExifWriter {

    static func embed(jpeg: Data, snapshot s: CaptureSnapshot, comment: String) -> Data {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let type = CGImageSourceGetType(src) else { return jpeg }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return jpeg }

        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let stamp = local.string(from: s.date)

        var props: [CFString: Any] = [:]
        props[kCGImagePropertyExifDictionary] = [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
            kCGImagePropertyExifUserComment: comment
        ] as [CFString: Any]
        props[kCGImagePropertyTIFFDictionary] = [
            kCGImagePropertyTIFFSoftware: "GeoStamp Cam",
            kCGImagePropertyTIFFDateTime: stamp
        ] as [CFString: Any]

        if let l = s.location {
            let utc = DateFormatter()
            utc.locale = Locale(identifier: "en_US_POSIX")
            utc.timeZone = TimeZone(identifier: "UTC")
            utc.dateFormat = "HH:mm:ss"
            let utcDate = DateFormatter()
            utcDate.locale = Locale(identifier: "en_US_POSIX")
            utcDate.timeZone = TimeZone(identifier: "UTC")
            utcDate.dateFormat = "yyyy:MM:dd"

            var gps: [CFString: Any] = [
                kCGImagePropertyGPSLatitude: abs(l.coordinate.latitude),
                kCGImagePropertyGPSLatitudeRef: l.coordinate.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude: abs(l.coordinate.longitude),
                kCGImagePropertyGPSLongitudeRef: l.coordinate.longitude >= 0 ? "E" : "W",
                kCGImagePropertyGPSTimeStamp: utc.string(from: s.date),
                kCGImagePropertyGPSDateStamp: utcDate.string(from: s.date)
            ]
            if l.verticalAccuracy >= 0 {
                gps[kCGImagePropertyGPSAltitude] = abs(l.altitude)
                gps[kCGImagePropertyGPSAltitudeRef] = l.altitude >= 0 ? 0 : 1
            }
            if l.horizontalAccuracy >= 0 {
                gps[kCGImagePropertyGPSHPositioningError] = l.horizontalAccuracy
            }
            if let h = s.headingDeg {
                gps[kCGImagePropertyGPSImgDirection] = h
                gps[kCGImagePropertyGPSImgDirectionRef] = "T"
            }
            props[kCGImagePropertyGPSDictionary] = gps
        }

        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return jpeg }
        return out as Data
    }
}
