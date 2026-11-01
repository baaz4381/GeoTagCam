import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// QR code that opens the photo's position in a maps app.
enum QRMaker {
    private static let context = CIContext()
    private static let lock = NSLock()
    private static var cache: (text: String, image: UIImage)?

    static func mapsLink(lat: Double, lon: Double) -> String {
        String(format: "https://maps.google.com/?q=%.6f,%.6f", lat, lon)
    }

    static func image(for text: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let c = cache, c.text == text { return c.image }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let scaled = out.samplingNearest().transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let img = UIImage(cgImage: cg)
        cache = (text, img)
        return img
    }
}

/// Compass dial that rotates with the phone's heading. Replaces the map in the Compass template.
enum CompassDial {
    static func image(heading: Double, side: CGFloat = 240) -> UIImage {
        let size = CGSize(width: side, height: side)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let center = CGPoint(x: side / 2, y: side / 2)
            let r = side / 2 - 8
            let discRect = CGRect(x: 6, y: 6, width: side - 12, height: side - 12)

            UIColor(white: 0.08, alpha: 1).setFill()
            UIBezierPath(ovalIn: discRect).fill()
            UIColor.white.withAlphaComponent(0.85).setStroke()
            let ring = UIBezierPath(ovalIn: discRect)
            ring.lineWidth = 3
            ring.stroke()

            c.saveGState()
            c.translateBy(x: center.x, y: center.y)
            c.rotate(by: -CGFloat(heading) * .pi / 180)

            for deg in stride(from: 0, to: 360, by: 10) {
                c.saveGState()
                c.rotate(by: CGFloat(deg) * .pi / 180)
                let major = deg % 90 == 0
                let len: CGFloat = major ? 20 : (deg % 30 == 0 ? 14 : 8)
                let tick = UIBezierPath()
                tick.move(to: CGPoint(x: 0, y: -r))
                tick.addLine(to: CGPoint(x: 0, y: -r + len))
                tick.lineWidth = major ? 4 : 2
                (deg == 0 ? UIColor.red : UIColor.white).setStroke()
                tick.stroke()
                c.restoreGState()
            }

            let letters: [(Int, String)] = [(0, "N"), (90, "E"), (180, "S"), (270, "W")]
            for (deg, letter) in letters {
                c.saveGState()
                c.rotate(by: CGFloat(deg) * .pi / 180)
                c.translateBy(x: 0, y: -r + 46)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 34, weight: .heavy),
                    .foregroundColor: deg == 0 ? UIColor.red : UIColor.white
                ]
                let text = letter as NSString
                let sz = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2), withAttributes: attrs)
                c.restoreGState()
            }
            c.restoreGState()

            // Fixed pointer at the top shows where the camera is facing.
            UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1).setFill()
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: center.x, y: 0))
            tri.addLine(to: CGPoint(x: center.x - 11, y: 22))
            tri.addLine(to: CGPoint(x: center.x + 11, y: 22))
            tri.close()
            tri.fill()

            let label = String(format: "%.0f°", heading) as NSString
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let ls = label.size(withAttributes: labelAttrs)
            label.draw(at: CGPoint(x: center.x - ls.width / 2, y: center.y - ls.height / 2), withAttributes: labelAttrs)
        }
    }
}
