import Foundation

/// Spreadsheet (CSV) and Google Earth (KML) exports of the selected photos and videos.
enum Exporter {

    private static func tempURL(_ name: String, ext: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(f.string(from: Date())).\(ext)")
    }

    static func csv(_ records: [PhotoRecord]) -> URL? {
        let iso = ISO8601DateFormatter()
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func num(_ v: Double?, _ f: String) -> String { v.map { String(format: f, $0) } ?? "" }

        var rows = ["file,type,date,latitude,longitude,altitude_m,accuracy_m,address,project,tag,note,number,imported,simulated_location,sha256"]
        for r in records.sorted(by: { $0.date < $1.date }) {
            let cols: [String] = [
                esc(r.filename),
                r.isVideo ? "video" : "photo",
                iso.string(from: r.date),
                num(r.latitude, "%.7f"),
                num(r.longitude, "%.7f"),
                num(r.altitude, "%.1f"),
                num(r.accuracy, "%.1f"),
                esc(r.address),
                esc(r.project),
                esc(r.phase),
                esc(r.note),
                r.serial.map { String($0) } ?? "",
                r.isImported ? "yes" : "no",
                r.simulated ? "yes" : "no",
                r.sha256
            ]
            rows.append(cols.joined(separator: ","))
        }
        // Byte-order mark so Excel reads non-English text correctly.
        let text = "\u{FEFF}" + rows.joined(separator: "\n")
        let url = tempURL("GeoStamp-Data", ext: "csv")
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func kml(_ records: [PhotoRecord]) -> URL? {
        func xml(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let iso = ISO8601DateFormatter()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>GeoStamp Cam</name>

        """
        for r in records.sorted(by: { $0.date < $1.date }) {
            guard let lat = r.latitude, let lon = r.longitude else { continue }
            var desc = iso.string(from: r.date)
            if !r.address.isEmpty { desc += "\n" + r.address }
            if !r.project.isEmpty { desc += "\nProject: " + r.project }
            if !r.note.isEmpty { desc += "\n" + r.note }
            let alt = r.altitude ?? 0
            out += "<Placemark><name>\(xml(r.filename))</name><description>\(xml(desc))</description>"
            out += "<TimeStamp><when>\(iso.string(from: r.date))</when></TimeStamp>"
            out += String(format: "<Point><coordinates>%.7f,%.7f,%.1f</coordinates></Point></Placemark>\n", lon, lat, alt)
        }
        out += "</Document></kml>\n"

        let url = tempURL("GeoStamp-Map", ext: "kml")
        do {
            try Data(out.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
