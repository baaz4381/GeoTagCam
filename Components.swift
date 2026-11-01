import SwiftUI
import AVFoundation
import AVKit
import UIKit

// MARK: - Camera preview with tap-to-focus, pinch-to-zoom and volume-button shutter

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onHardwareShutter: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        installHardwareButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installHardwareButton()
    }

    private func installHardwareButton() {
        // Volume buttons take a photo (iOS 17.2 and later). Older iOS versions simply ignore this.
        #if swift(>=5.9.2)
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { [weak self] event in
                if event.phase == .began { self?.onHardwareShutter?() }
            }
            addInteraction(interaction)
        }
        #endif
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (CGPoint, CGPoint) -> Void                      // (device point, layer point)
    var onPinch: (CGFloat, UIGestureRecognizer.State) -> Void
    var onShutter: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.onHardwareShutter = { context.coordinator.parent.onShutter() }
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        v.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: CameraPreview
        init(_ parent: CameraPreview) { self.parent = parent }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? PreviewView else { return }
            let p = g.location(in: v)
            parent.onTap(v.previewLayer.captureDevicePointConverted(fromLayerPoint: p), p)
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            parent.onPinch(g.scale, g.state)
        }
    }
}

// MARK: - Rule-of-thirds grid

struct GridLines: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: g.size.height))
                    let y = g.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Thumbnail

struct ThumbnailView: View {
    @EnvironmentObject var store: PhotoStore
    let record: PhotoRecord
    var maxPixel = 360
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .task(id: record.id) {
            image = await store.loadThumbnail(record, maxPixel: maxPixel)
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Stamp preview (same content the renderer burns into the photo)

struct StampPreviewView: View {
    let content: StampContent
    let cfg: StampSettings

    var body: some View {
        let s = CGFloat(cfg.scale)
        HStack(alignment: .top, spacing: 8 * s) {
            if let map = content.map {
                Image(uiImage: map)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88 * s, height: 88 * s)
                    .clipShape(RoundedRectangle(cornerRadius: 6 * s))
            }
            VStack(alignment: .leading, spacing: 2 * s) {
                if let b = content.badge {
                    Text("● " + b)
                        .font(.system(size: 10.5 * s, weight: .heavy))
                        .foregroundColor(cfg.accent.color)
                }
                if !content.title.isEmpty {
                    Text(content.title)
                        .font(.system(size: 13.5 * s, weight: .bold))
                }
                ForEach(Array(content.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 11.5 * s, weight: .medium))
                }
                if !content.metrics.isEmpty {
                    Text(content.metrics.joined(separator: "  •  "))
                        .font(.system(size: 10.5 * s))
                        .opacity(0.85)
                }
                ForEach(Array(content.tags.enumerated()), id: \.offset) { _, tag in
                    Text(tag)
                        .font(.system(size: 10.5 * s))
                        .foregroundColor(cfg.accent.color)
                }
                if let w = content.warning {
                    Text(w).font(.system(size: 10.5 * s)).foregroundColor(.orange)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let qr = content.qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 64 * s, height: 64 * s)
                    .padding(3 * s)
                    .background(RoundedRectangle(cornerRadius: 4 * s).fill(Color.white))
            }
        }
        .padding(8 * s)
        .background(RoundedRectangle(cornerRadius: 10 * s).fill(Color.black.opacity(cfg.opacity)))
        .overlay(alignment: .topTrailing) {
            if let logo = content.logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 120 * s, maxHeight: 36 * s)
                    .offset(y: cfg.position == .bottom ? -(36 * s + 6 * s) : (36 * s + 6 * s))
            }
        }
        .padding(10 * s)
    }
}
