import UIKit

/// Builds an A4 PDF with each selected photo and its location details.
/// Photos tagged Before and After are paired side by side on one page.
enum PDFReport {
    typealias Item = (record: PhotoRecord, url: URL)

    static func make(items: [Item], title: String) -> URL? {
        guard !items.isEmpty else { return nil }

        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let m: CGFloat = 36
        let contentW = page.width - 2 * m
        let headerH: CGFloat = 26

        let fmt = UIGraphicsPDFRendererFormat()
        fmt.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "GeoStamp Cam"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: fmt)

        let dateF = DateFormatter()
        dateF.dateStyle = .medium
        dateF.timeStyle = .medium

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.darkGray
        ]
        let capAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: UIColor.black
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.black
        ]

        func caption(_ r: PhotoRecord) -> String {
            var lines: [String] = []
            let phase = r.phase.isEmpty ? "" : r.phase.uppercased() + "  |  "
            lines.append(phase + dateF.string(from: r.date))
            if !r.address.isEmpty { lines.append(r.address) }
            if let la = r.latitude, let lo = r.longitude {
                var s = String(format: "Lat %.6f, Long %.6f", la, lo)
                if let a = r.altitude { s += String(format: "  |  Alt %.0f m", a) }
                if let acc = r.accuracy { s += String(format: "  |  ±%.0f m", acc) }
                lines.append(s)
            }
            if !r.project.isEmpty { lines.append("Project: " + r.project) }
            if !r.note.isEmpty { lines.append(r.note) }
            lines.append("SHA-256: " + String(r.sha256.prefix(24)) + "…")
            return lines.joined(separator: "\n")
        }

        func drawPhoto(_ item: Item, in rect: CGRect) {
            UIColor(white: 0.94, alpha: 1).setFill()
            UIBezierPath(rect: rect).fill()
            guard let img = PhotoStore.downsample(url: item.url, maxPixel: 1600), img.size.width > 0, img.size.height > 0 else { return }
            let k = min(rect.width / img.size.width, rect.height / img.size.height)
            let w = img.size.width * k
            let h = img.size.height * k
            img.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        }

        // Split into before/after pairs and everything else.
        let sorted = items.sorted { $0.record.date < $1.record.date }
        let befores = sorted.filter { $0.record.phase == "Before" }
        let afters = sorted.filter { $0.record.phase == "After" }
        let others = sorted.filter { $0.record.phase != "Before" && $0.record.phase != "After" }
        let pairCount = min(befores.count, afters.count)
        let leftovers = Array(befores.dropFirst(pairCount)) + Array(afters.dropFirst(pairCount)) + others

        var pageNo = 0
        let data = renderer.pdfData { ctx in
            func newPage() {
                ctx.beginPage()
                pageNo += 1
                (title as NSString).draw(at: CGPoint(x: m, y: 14), withAttributes: headerAttrs)
                ("Page \(pageNo)" as NSString).draw(at: CGPoint(x: page.width - m - 44, y: 14), withAttributes: headerAttrs)
            }

            // Before / After pages
            let colW = (contentW - 14) / 2
            for i in 0..<pairCount {
                newPage()
                let pair = [befores[i], afters[i]]
                for (col, item) in pair.enumerated() {
                    let x = m + CGFloat(col) * (colW + 14)
                    let top = m + headerH
                    let label: NSString = (col == 0 ? "BEFORE" : "AFTER") as NSString
                    label.draw(at: CGPoint(x: x, y: top), withAttributes: labelAttrs)
                    drawPhoto(item, in: CGRect(x: x, y: top + 18, width: colW, height: 440))
                    (caption(item.record) as NSString).draw(
                        in: CGRect(x: x, y: top + 18 + 446, width: colW, height: 130),
                        withAttributes: capAttrs
                    )
                }
            }

            // Single photos, two per page
            let cardH = (page.height - 2 * m - headerH) / 2
            for (i, item) in leftovers.enumerated() {
                if i % 2 == 0 { newPage() }
                let top = m + headerH + CGFloat(i % 2) * cardH
                let imgH = cardH - 84
                drawPhoto(item, in: CGRect(x: m, y: top, width: contentW, height: imgH))
                (caption(item.record) as NSString).draw(
                    in: CGRect(x: m, y: top + imgH + 4, width: contentW, height: 76),
                    withAttributes: capAttrs
                )
            }
        }

        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeoStamp-Report-\(f.string(from: Date())).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
