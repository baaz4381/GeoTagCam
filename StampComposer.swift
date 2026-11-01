import UIKit
import CoreLocation

/// Turns a capture snapshot plus the user's settings into the lines of text for the stamp.
enum StampComposer {

    static func build(_ s: CaptureSnapshot, cfg: StampSettings, logo: UIImage?) -> StampContent {
        var c = StampContent()
        let t = cfg.template
        let classic = t == .classic
        let advanced = t == .advanced
        let compact = t == .compact
        let compass = t == .compass

        let wantMap = classic || (advanced && cfg.showMap)
        let wantAddress = classic || compass || (advanced && cfg.showAddress)
        let wantCoords = classic || compass || compact || (advanced && cfg.showLatLong)
        let wantDate = classic || compass || compact || (advanced && cfg.showDateTime)

        if compass {
            c.map = CompassDial.image(heading: s.headingDeg ?? 0)
        } else {
            c.map = wantMap ? s.map : nil
        }
        c.logo = cfg.showLogo ? logo : nil

        var badges: [String] = []
        if s.imported { badges.append("IMPORTED") }
        if !s.phase.isEmpty { badges.append(s.phase.uppercased()) }
        if !badges.isEmpty { c.badge = badges.joined(separator: " · ") }

        // Address
        if wantAddress {
            if s.location == nil {
                c.title = "Location unavailable"
            } else {
                let flag = ((advanced && cfg.showFlag) || compass || classic) ? (s.address.flag.map { $0 + " " } ?? "") : ""
                c.title = flag + (s.address.title ?? "")
                if let d = s.address.detail, !d.isEmpty { c.lines.append(d) }
            }
        }

        // Coordinates
        if wantCoords {
            if let l = s.location {
                c.lines.append(coordinateText(l.coordinate, format: cfg.coordFormat))
            } else if !wantAddress {
                c.lines.append("Location unavailable")
            }
        }

        // Date and time
        if wantDate {
            c.lines.append(dateText(s.date, cfg: cfg, withSeconds: s.withSeconds))
        }

        // Running number
        if let n = s.serial {
            c.lines.append("\(s.isVideo ? "Video" : "Photo") No. \(n)")
        }

        // Compass heading line
        if compass, let h = s.headingDeg {
            c.metrics = [String(format: "Facing %@ %.0f°", compassName(h), h)]
        }

        // Metrics (Advanced only)
        if advanced {
            var m: [String] = []
            let metric = cfg.units == .metric
            if let l = s.location {
                if cfg.showAltitude, l.verticalAccuracy >= 0 {
                    let v = metric ? l.altitude : l.altitude * 3.28084
                    m.append(String(format: "Alt %.0f %@", v, metric ? "m" : "ft"))
                }
                if cfg.showAccuracy, l.horizontalAccuracy >= 0 {
                    let v = metric ? l.horizontalAccuracy : l.horizontalAccuracy * 3.28084
                    m.append(String(format: "Acc ±%.0f %@", v, metric ? "m" : "ft"))
                }
            }
            if cfg.showCompass, let h = s.headingDeg {
                m.append(String(format: "%@ %.0f°", compassName(h), h))
            }
            if cfg.showMagnetic, let mu = s.magneticUT {
                m.append(String(format: "Mag %.0f µT", mu))
            }
            if let w = s.weather {
                if cfg.showWeather {
                    let temp = metric ? w.tempC : w.tempC * 9 / 5 + 32
                    m.append(String(format: "%.0f°%@", temp, metric ? "C" : "F"))
                }
                if cfg.showHumidity {
                    m.append(String(format: "Hum %.0f%%", w.humidity))
                }
                if cfg.showWind {
                    let v = metric ? w.windKmh : w.windKmh * 0.621371
                    m.append(String(format: "Wind %.0f %@", v, metric ? "km/h" : "mph"))
                }
                if cfg.showPressure {
                    m.append(String(format: "%.0f hPa", w.pressureHpa))
                }
            }
            c.metrics = m

            // Free text
            let project = cfg.project.trimmingCharacters(in: .whitespacesAndNewlines)
            if cfg.showProject, !project.isEmpty { c.tags.append("Project: " + project) }
            let note = cfg.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if cfg.showNote, !note.isEmpty { c.tags.append(note) }
            if cfg.showHashtags {
                let tags = cfg.hashtags
                    .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" })
                    .map { $0.hasPrefix("#") ? String($0) : "#" + $0 }
                    .joined(separator: " ")
                if !tags.isEmpty { c.tags.append(tags) }
            }
        }

        // QR code to the position (any template)
        if cfg.showQR, let l = s.location {
            c.qr = QRMaker.image(for: QRMaker.mapsLink(lat: l.coordinate.latitude, lon: l.coordinate.longitude))
        }

        if s.simulated {
            c.warning = "⚠︎ Simulated location detected"
        }
        return c
    }

    // MARK: Formatting

    static func coordinateText(_ coord: CLLocationCoordinate2D, format: CoordFormat) -> String {
        switch format {
        case .decimal:
            return String(format: "Lat %.6f°  Long %.6f°", coord.latitude, coord.longitude)
        case .dms:
            return dms(coord.latitude, pos: "N", neg: "S") + "  " + dms(coord.longitude, pos: "E", neg: "W")
        }
    }

    private static func dms(_ value: Double, pos: String, neg: String) -> String {
        let ref = value >= 0 ? pos : neg
        let a = abs(value)
        let d = Int(a)
        let minutesFull = (a - Double(d)) * 60
        let m = Int(minutesFull)
        let s = (minutesFull - Double(m)) * 60
        return String(format: "%d°%02d'%04.1f\"%@", d, m, s, ref)
    }

    static func dateText(_ date: Date, cfg: StampSettings, withSeconds: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        var pattern = cfg.dateStyle.pattern
        if withSeconds && !pattern.contains(":ss") {
            pattern = pattern.replacingOccurrences(of: "mm", with: "mm:ss")
        }
        f.dateFormat = pattern
        var text = f.string(from: date)
        if cfg.showTimeZone {
            let secs = TimeZone.current.secondsFromGMT(for: date)
            let sign = secs >= 0 ? "+" : "-"
            let h = abs(secs) / 3600
            let m = (abs(secs) % 3600) / 60
            text += String(format: " GMT %@%02d:%02d", sign, h, m)
        }
        return text
    }
}
