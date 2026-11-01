import UIKit

/// Burns the stamp into the pixels of the photo, so it cannot be removed without editing the image.
enum StampRenderer {

    // MARK: Pre-processing

    static func mirrored(_ img: UIImage) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let size = img.size
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            ctx.cgContext.translateBy(x: size.width, y: 0)
            ctx.cgContext.scaleBy(x: -1, y: 1)
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func crop(_ img: UIImage, to option: AspectOption) -> UIImage {
        guard let r = option.portraitRatio else { return img }
        let s = img.size
        let isPortrait = s.height >= s.width
        let target = isPortrait ? r : 1 / r          // desired width / height
        if abs(s.width / s.height - target) < 0.002 { return img }

        var cw = s.width, ch = s.height
        if s.width / s.height > target { cw = s.height * target } else { ch = s.width / target }
        let origin = CGPoint(x: (s.width - cw) / 2, y: (s.height - ch) / 2)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: cw, height: ch), format: fmt).image { _ in
            img.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
    }

    /// Shrinks very large images (e.g. 48 MP imports) so rendering cannot run out of memory.
    static func downscaled(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(img.size.width, img.size.height)
        guard longest > maxSide, longest > 0 else { return img }
        let k = maxSide / longest
        let size = CGSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Public rendering

    /// Photo with the stamp drawn on it.
    static func render(photo: UIImage, content: StampContent, cfg: StampSettings) -> UIImage {
        let size = photo.size
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            photo.draw(in: CGRect(origin: .zero, size: size))
            drawStamp(in: ctx.cgContext, size: size, content: content, cfg: cfg)
        }
    }

    /// Transparent image holding only the stamp. Used for video, where it is composited on every frame.
    static func overlay(size: CGSize, content: StampContent, cfg: StampSettings) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            drawStamp(in: ctx.cgContext, size: size, content: content, cfg: cfg)
        }
    }

    // MARK: Drawing

    private static func drawStamp(in ctx: CGContext, size: CGSize, content: StampContent, cfg: StampSettings) {
        let u = (min(size.width, size.height) / 390.0) * CGFloat(cfg.scale)
        let accent = cfg.accent.uiColor

        let margin = 10 * u
        let pad = 8 * u
        let gap = 8 * u
        let panelW = min(size.width - 2 * margin, 390 * u - 2 * margin)
        let mapSide: CGFloat = content.map == nil ? 0 : 88 * u
        let qrSide: CGFloat = content.qr == nil ? 0 : 64 * u
        let textX = pad + (mapSide > 0 ? mapSide + gap : 0)
        let textW = max(panelW - textX - pad - (qrSide > 0 ? qrSide + gap : 0), 10)

        let titleFont = UIFont.systemFont(ofSize: 13.5 * u, weight: .bold)
        let bodyFont = UIFont.systemFont(ofSize: 11.5 * u, weight: .medium)
        let smallFont = UIFont.systemFont(ofSize: 10.5 * u, weight: .regular)
        let badgeFont = UIFont.systemFont(ofSize: 10.5 * u, weight: .heavy)

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.lineSpacing = 1 * u

        func attr(_ s: String, _ f: UIFont, _ color: UIColor) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .paragraphStyle: para])
        }

        var blocks: [NSAttributedString] = []
        if let b = content.badge { blocks.append(attr("● " + b, badgeFont, accent)) }
        if !content.title.isEmpty { blocks.append(attr(content.title, titleFont, .white)) }
        for l in content.lines { blocks.append(attr(l, bodyFont, UIColor.white.withAlphaComponent(0.95))) }
        if !content.metrics.isEmpty {
            blocks.append(attr(content.metrics.joined(separator: "  •  "), smallFont, UIColor.white.withAlphaComponent(0.85)))
        }
        for t in content.tags { blocks.append(attr(t, smallFont, accent)) }
        if let w = content.warning { blocks.append(attr(w, smallFont, .orange)) }

        if blocks.isEmpty && content.map == nil && content.qr == nil { return }

        let opts: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let spacing = 2 * u
        let heights: [CGFloat] = blocks.map {
            ceil($0.boundingRect(with: CGSize(width: textW, height: .greatestFiniteMagnitude), options: opts, context: nil).height)
        }
        let textH = heights.reduce(0, +) + spacing * CGFloat(max(0, blocks.count - 1))
        let panelH = max(textH, max(mapSide, qrSide)) + 2 * pad
        let panelX = (size.width - panelW) / 2
        let panelY = cfg.position == .bottom ? size.height - margin - panelH : margin
        let panel = CGRect(x: panelX, y: panelY, width: panelW, height: panelH)

        UIColor.black.withAlphaComponent(CGFloat(cfg.opacity)).setFill()
        UIBezierPath(roundedRect: panel, cornerRadius: 10 * u).fill()

        if let map = content.map {
            let r = CGRect(x: panel.minX + pad, y: panel.minY + pad, width: mapSide, height: mapSide)
            ctx.saveGState()
            UIBezierPath(roundedRect: r, cornerRadius: 6 * u).addClip()
            map.draw(in: r)
            ctx.restoreGState()
        }

        if let qr = content.qr {
            let r = CGRect(x: panel.maxX - pad - qrSide, y: panel.minY + pad, width: qrSide, height: qrSide)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: r.insetBy(dx: -3 * u, dy: -3 * u), cornerRadius: 4 * u).fill()
            qr.draw(in: r)
        }

        var y = panel.minY + pad
        for (i, b) in blocks.enumerated() {
            let rect = CGRect(x: panel.minX + textX, y: y, width: textW, height: heights[i])
            b.draw(with: rect, options: opts, context: nil)
            y += heights[i] + spacing
        }

        if let logo = content.logo, logo.size.height > 0 {
            let aspect = logo.size.width / logo.size.height
            var lh = 36 * u
            var lw = lh * aspect
            let maxW = 120 * u
            if lw > maxW { lw = maxW; lh = lw / aspect }
            let lx = panel.maxX - lw
            let ly = cfg.position == .bottom ? panel.minY - lh - 6 * u : panel.maxY + 6 * u
            logo.draw(in: CGRect(x: lx, y: ly, width: lw, height: lh))
        }
    }
}

// MARK: - Whole pipeline (runs off the main thread)

struct ProcessedPhoto {
    let stamped: Data
    let original: Data?
}

enum PhotoPipeline {
    static func process(data: Data,
                        snapshot: CaptureSnapshot,
                        cfg: StampSettings,
                        logo: UIImage?,
                        mirror: Bool,
                        crop: Bool = true,
                        maxSide: CGFloat? = nil) -> ProcessedPhoto? {
        guard var img = UIImage(data: data) else { return nil }
        if let m = maxSide { img = StampRenderer.downscaled(img, maxSide: m) }
        if mirror { img = StampRenderer.mirrored(img) }
        if crop { img = StampRenderer.crop(img, to: cfg.aspect) }

        let content = StampComposer.build(snapshot, cfg: cfg, logo: logo)
        let stamped = StampRenderer.render(photo: img, content: content, cfg: cfg)
        guard let jpeg = stamped.jpegData(compressionQuality: 0.92) else { return nil }

        let finalData: Data
        if cfg.embedExif {
            let comment = "GeoStamp Cam | " + (snapshot.address.full.isEmpty ? "no address" : snapshot.address.full)
            finalData = ExifWriter.embed(jpeg: jpeg, snapshot: snapshot, comment: comment)
        } else {
            finalData = jpeg
        }
        return ProcessedPhoto(stamped: finalData, original: cfg.saveOriginal ? data : nil)
    }
}
