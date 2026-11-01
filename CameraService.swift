import AVFoundation
import UIKit

enum CaptureMode { case photo, video }

/// Photo and video camera. The microphone is only added to the session while Video mode is selected,
/// so taking photos never interrupts the user's music or podcasts.
final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    let recorder = VideoRecorder()

    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published private(set) var displayZoom: CGFloat = 1
    @Published private(set) var zoomPresets: [CGFloat] = [1]
    @Published private(set) var permissionDenied = false
    @Published private(set) var isConfigured = false
    @Published private(set) var hasFlash = false
    @Published private(set) var mode: CaptureMode = .photo
    @Published private(set) var isRecording = false
    @Published private(set) var micDenied = false

    private let queue = DispatchQueue(label: "geostamp.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var configured = false
    private var micActive = false
    private var zoomBase: CGFloat = 1
    private var minDisplayZoom: CGFloat = 1
    private var maxDisplayZoom: CGFloat = 10
    private var completion: ((Result<Data, Error>) -> Void)?
    private var lastValidOrientation: UIDeviceOrientation = .portrait

    // MARK: Lifecycle

    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureAndRun() } else { self?.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configureAndRun() {
        permissionDenied = false
        let pos = position
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.session.automaticallyConfiguresApplicationAudioSession = false
                if let d = Self.bestDevice(pos),
                   let input = try? AVCaptureDeviceInput(device: d),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.input = input
                    self.device = d
                }
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                self.videoOutput.setSampleBufferDelegate(self.recorder, queue: self.recorder.queue)
                self.audioOutput.setSampleBufferDelegate(self.recorder, queue: self.recorder.queue)
                self.session.commitConfiguration()
                self.configured = true
                if let d = self.device { self.applyZoomSetup(d) }
                DispatchQueue.main.async { self.isConfigured = self.device != nil }
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private static func bestDevice(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera
        ]
        for t in types {
            if let d = AVCaptureDevice.default(t, for: .video, position: .back) { return d }
        }
        return nil
    }

    // MARK: Photo / Video mode

    func setMode(_ newMode: CaptureMode, quality: VideoQuality) {
        guard newMode != mode, !isRecording else { return }
        if newMode == .video {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                applyMode(.video, quality: quality, withMic: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    DispatchQueue.main.async { self?.applyMode(.video, quality: quality, withMic: granted) }
                }
            default:
                applyMode(.video, quality: quality, withMic: false)
            }
        } else {
            applyMode(.photo, quality: quality, withMic: false)
        }
    }

    private func applyMode(_ m: CaptureMode, quality: VideoQuality, withMic: Bool) {
        mode = m
        micActive = (m == .video && withMic)
        micDenied = (m == .video && !withMic)
        let torchOn = (m == .video && flashMode == .on)
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if m == .video {
                self.session.automaticallyConfiguresApplicationAudioSession = withMic
                let preset = quality.preset
                self.session.sessionPreset = self.session.canSetSessionPreset(preset) ? preset : .high
                if !self.session.outputs.contains(self.videoOutput), self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }
                if withMic {
                    if self.audioInput == nil,
                       let mic = AVCaptureDevice.default(for: .audio),
                       let micInput = try? AVCaptureDeviceInput(device: mic),
                       self.session.canAddInput(micInput) {
                        self.session.addInput(micInput)
                        self.audioInput = micInput
                    }
                    if !self.session.outputs.contains(self.audioOutput), self.session.canAddOutput(self.audioOutput) {
                        self.session.addOutput(self.audioOutput)
                    }
                }
            } else {
                if self.session.outputs.contains(self.videoOutput) { self.session.removeOutput(self.videoOutput) }
                if self.session.outputs.contains(self.audioOutput) { self.session.removeOutput(self.audioOutput) }
                if let a = self.audioInput {
                    self.session.removeInput(a)
                    self.audioInput = nil
                }
                self.session.sessionPreset = .photo
                self.session.automaticallyConfiguresApplicationAudioSession = false
            }
            self.session.commitConfiguration()

            if m == .video {
                self.configureVideoConnection()
            } else {
                // Give audio focus back so music can resume.
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            if let d = self.device { self.applyZoomSetup(d) }
            self.setTorchLocked(on: torchOn)
        }
    }

    /// Video frames are always delivered upright (portrait) and not mirrored.
    private func configureVideoConnection() {
        guard let c = videoOutput.connection(with: .video) else { return }
        if c.isVideoOrientationSupported { c.videoOrientation = .portrait }
        if c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = false
        }
    }

    private func setTorchLocked(on: Bool) {
        guard let d = device, d.hasTorch else { return }
        do {
            try d.lockForConfiguration()
            d.torchMode = on ? .on : .off
            d.unlockForConfiguration()
        } catch {}
    }

    // MARK: Recording

    /// Orientation a new video will use: follows how the phone is held.
    func recordingOrientation() -> AVCaptureVideoOrientation {
        currentVideoOrientation(lockPortrait: false)
    }

    func startRecording(url: URL, bitrate: Int, orientation: AVCaptureVideoOrientation) {
        // Must be set before the first frame so the writer sees the right frame size.
        queue.sync {
            if let c = self.videoOutput.connection(with: .video), c.isVideoOrientationSupported {
                c.videoOrientation = orientation
            }
        }
        recorder.start(url: url, withAudio: micActive, bitrate: bitrate)
        isRecording = true
    }

    func stopRecording(completion: @escaping (Result<(URL, Double), Error>) -> Void) {
        recorder.stop { [weak self] result in
            self?.isRecording = false
            completion(result)
        }
    }

    // MARK: Zoom, focus, flash, flip

    /// Display zoom 1.0 = main camera. 0.5 = ultra-wide on phones that have one.
    private func applyZoomSetup(_ d: AVCaptureDevice) {
        var base: CGFloat = 1
        if d.position == .back,
           d.constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera }),
           let first = d.virtualDeviceSwitchOverVideoZoomFactors.first {
            base = CGFloat(truncating: first)
        }
        zoomBase = base
        do {
            try d.lockForConfiguration()
            d.videoZoomFactor = max(base, d.minAvailableVideoZoomFactor)
            d.unlockForConfiguration()
        } catch {}

        minDisplayZoom = d.minAvailableVideoZoomFactor / base
        maxDisplayZoom = min(d.maxAvailableVideoZoomFactor / base, 10)
        let lo = minDisplayZoom, hi = maxDisplayZoom
        let presets = [CGFloat(0.5), 1, 2, 3, 5].filter { $0 >= lo - 0.01 && $0 <= hi + 0.01 }
        let flash = d.hasFlash || d.hasTorch
        DispatchQueue.main.async {
            self.zoomPresets = presets.isEmpty ? [1] : presets
            self.displayZoom = 1
            self.hasFlash = flash
        }
    }

    func setZoom(_ requested: CGFloat) {
        queue.async { [weak self] in
            guard let self, let d = self.device else { return }
            let z = max(self.minDisplayZoom, min(requested, self.maxDisplayZoom))
            do {
                try d.lockForConfiguration()
                d.videoZoomFactor = z * self.zoomBase
                d.unlockForConfiguration()
            } catch { return }
            DispatchQueue.main.async { self.displayZoom = z }
        }
    }

    /// `point` is in capture-device coordinates (0...1), from the preview layer converter.
    func focus(at point: CGPoint) {
        queue.async { [weak self] in
            guard let d = self?.device else { return }
            do {
                try d.lockForConfiguration()
                if d.isFocusPointOfInterestSupported {
                    d.focusPointOfInterest = point
                    d.focusMode = .continuousAutoFocus
                }
                if d.isExposurePointOfInterestSupported {
                    d.exposurePointOfInterest = point
                    d.exposureMode = .continuousAutoExposure
                }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func cycleFlash() {
        if mode == .video {
            flashMode = (flashMode == .on) ? .off : .on
            let on = flashMode == .on
            queue.async { [weak self] in self?.setTorchLocked(on: on) }
            return
        }
        switch flashMode {
        case .off: flashMode = .auto
        case .auto: flashMode = .on
        default: flashMode = .off
        }
    }

    func flip() {
        guard !isRecording else { return }
        let newPos: AVCaptureDevice.Position = position == .back ? .front : .back
        let videoMode = (mode == .video)
        let torchOn = videoMode && flashMode == .on
        queue.async { [weak self] in
            guard let self,
                  let d = Self.bestDevice(newPos),
                  let newInput = try? AVCaptureDeviceInput(device: d) else { return }
            self.session.beginConfiguration()
            let old = self.input
            if let old { self.session.removeInput(old) }
            var switched = false
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
                self.device = d
                switched = true
            } else if let old {
                self.session.addInput(old)
            }
            self.session.commitConfiguration()
            if switched {
                if videoMode { self.configureVideoConnection() }
                self.applyZoomSetup(d)
                self.setTorchLocked(on: torchOn)
                DispatchQueue.main.async { self.position = newPos }
            }
        }
    }

    // MARK: Photo capture

    func capture(lockPortrait: Bool, completion: @escaping (Result<Data, Error>) -> Void) {
        let orientation = currentVideoOrientation(lockPortrait: lockPortrait)
        let flash = flashMode
        queue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            if self.photoOutput.supportedFlashModes.contains(flash) {
                settings.flashMode = flash
            }
            if let c = self.photoOutput.connection(with: .video), c.isVideoOrientationSupported {
                c.videoOrientation = orientation
            }
            self.completion = completion
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func currentVideoOrientation(lockPortrait: Bool) -> AVCaptureVideoOrientation {
        if lockPortrait { return .portrait }
        let o = UIDevice.current.orientation
        if o.isValidInterfaceOrientation { lastValidOrientation = o }
        switch lastValidOrientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let done = completion
        completion = nil
        if let error {
            DispatchQueue.main.async { done?(.failure(error)) }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                done?(.failure(NSError(domain: "GeoStampCam", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image data"])))
            }
            return
        }
        DispatchQueue.main.async { done?(.success(data)) }
    }
}
