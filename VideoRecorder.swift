import AVFoundation
import CoreImage
import UIKit

/// Writes camera frames to an MP4 and draws the stamp overlay onto every frame.
/// All writer state lives on `queue`, which is also the queue the capture outputs deliver samples on.
final class VideoRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "geostamp.video.samples")

    private let ciContext = CIContext()
    private let overlayLock = NSLock()
    private var overlay: CIImage?

    // Everything below is only touched on `queue`.
    private var recording = false
    private var url: URL?
    private var wantsAudio = false
    private var bitrate = 8_000_000
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var started = false
    private var firstPTS = CMTime.invalid
    private var lastPTS = CMTime.invalid

    // MARK: Control

    /// Thread-safe. Call about once a second so the time in the stamp keeps moving.
    func setOverlay(_ image: UIImage?) {
        let ci = image.flatMap { CIImage(image: $0) }
        overlayLock.lock()
        overlay = ci
        overlayLock.unlock()
    }

    func start(url: URL, withAudio: Bool, bitrate: Int) {
        queue.sync {
            self.url = url
            self.wantsAudio = withAudio
            self.bitrate = bitrate
            self.writer = nil
            self.videoInput = nil
            self.audioInput = nil
            self.adaptor = nil
            self.started = false
            self.firstPTS = .invalid
            self.lastPTS = .invalid
            self.recording = true
        }
    }

    func stop(completion: @escaping (Result<(URL, Double), Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.recording = false

            guard let writer = self.writer, let url = self.url, self.started else {
                self.writer?.cancelWriting()
                let err = NSError(domain: "GeoStampCam", code: 10,
                                  userInfo: [NSLocalizedDescriptionKey: "No video frames were recorded"])
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }

            var duration = 0.0
            if self.firstPTS.isValid && self.lastPTS.isValid {
                duration = max(0, CMTimeGetSeconds(CMTimeSubtract(self.lastPTS, self.firstPTS)))
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    if writer.status == .completed {
                        completion(.success((url, duration)))
                    } else {
                        let err = writer.error ?? NSError(domain: "GeoStampCam", code: 11,
                                                          userInfo: [NSLocalizedDescriptionKey: "Could not finish the video"])
                        completion(.failure(err))
                    }
                }
            }
        }
    }

    // MARK: Sample delivery (runs on `queue`)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard recording else { return }
        if output is AVCaptureVideoDataOutput {
            appendVideo(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            appendAudio(sampleBuffer)
        }
    }

    private func setupWriter(width: Int, height: Int) -> Bool {
        guard let url else { return false }
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vIn.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: attrs)
        guard w.canAdd(vIn) else { return false }
        w.add(vIn)

        if wantsAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 64000
            ]
            let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aIn.expectsMediaDataInRealTime = true
            if w.canAdd(aIn) {
                w.add(aIn)
                audioInput = aIn
            }
        }

        writer = w
        videoInput = vIn
        adaptor = ad
        return true
    }

    private func appendVideo(_ sb: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)

        if writer == nil {
            guard setupWriter(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb)) else {
                recording = false
                return
            }
        }
        guard let writer, let vIn = videoInput, let adaptor else { return }

        if writer.status == .unknown {
            guard writer.startWriting() else { recording = false; return }
            writer.startSession(atSourceTime: pts)
            started = true
            firstPTS = pts
        }
        guard writer.status == .writing, vIn.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }

        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let outBuffer = out else { return }

        var image = CIImage(cvPixelBuffer: pb)
        overlayLock.lock()
        let ov = overlay
        overlayLock.unlock()
        if let ov, ov.extent.width > 0, ov.extent.height > 0 {
            let sx = image.extent.width / ov.extent.width
            let sy = image.extent.height / ov.extent.height
            let fitted = (abs(sx - 1) < 0.001 && abs(sy - 1) < 0.001)
                ? ov
                : ov.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            image = fitted.composited(over: image)
        }
        ciContext.render(image, to: outBuffer)

        if adaptor.append(outBuffer, withPresentationTime: pts) {
            lastPTS = pts
        }
    }

    private func appendAudio(_ sb: CMSampleBuffer) {
        guard started, let writer, writer.status == .writing,
              let aIn = audioInput, aIn.isReadyForMoreMediaData else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if firstPTS.isValid && CMTimeCompare(pts, firstPTS) < 0 { return }   // audio from before the first video frame
        aIn.append(sb)
    }
}
