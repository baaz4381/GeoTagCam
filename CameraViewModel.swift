import SwiftUI
import Combine
import CoreLocation
import UIKit
import PhotosUI

@MainActor
final class CameraViewModel: ObservableObject {
    let camera = CameraService()
    let weather = WeatherService()
    let mapService = MapSnapshotService()
    let timeVerifier = TimeVerifier()
    let settings: SettingsStore
    let store: PhotoStore
    let location: LocationService

    @Published var countdown: Int?
    @Published var isSaving = false
    @Published var toast: String?
    @Published var lastThumb: UIImage?
    @Published var phase = ""               // "", "Before", "After"
    @Published var timerSeconds = 0         // 0, 3, 10
    @Published var focusPoint: CGPoint?
    @Published var recordSeconds = 0

    private var cancellables = Set<AnyCancellable>()
    private var toastTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var recordTask: Task<Void, Never>?
    private var recordSnapshot: CaptureSnapshot?

    private static let serialKey = "geostamp.serial"

    init(settings: SettingsStore, store: PhotoStore, location: LocationService) {
        self.settings = settings
        self.store = store
        self.location = location

        // Re-render the camera screen when any child object changes.
        let forwards: [ObservableObjectPublisher] = [
            camera.objectWillChange, location.objectWillChange, weather.objectWillChange,
            mapService.objectWillChange, timeVerifier.objectWillChange,
            settings.objectWillChange, store.objectWillChange
        ]
        for p in forwards {
            p.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }

        // Refresh map and weather as the user moves.
        location.$location
            .compactMap { $0 }
            .throttle(for: .seconds(3), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] loc in
                guard let self else { return }
                Task { @MainActor in self.refreshContext(loc, cfg: self.settings.cfg) }
            }
            .store(in: &cancellables)

        // ...and when settings change (e.g. map type).
        settings.$cfg
            .removeDuplicates()
            .sink { [weak self] cfg in
                guard let self else { return }
                Task { @MainActor in
                    self.timeVerifier.useVerified = cfg.useVerifiedTime
                    self.refreshContext(self.location.location, cfg: cfg)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    func start() {
        UIApplication.shared.isIdleTimerDisabled = true
        timeVerifier.useVerified = settings.cfg.useVerifiedTime
        location.start()
        camera.start()
        refreshContext(location.location, cfg: settings.cfg)

        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.timeVerifier.check()
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
        if lastThumb == nil, let r = store.records.first {
            Task { lastThumb = await store.loadThumbnail(r, maxPixel: 160) }
        }
    }

    func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        stopRecordingIfNeeded()
        camera.stop()
        clockTask?.cancel()
    }

    private func refreshContext(_ loc: CLLocation?, cfg: StampSettings) {
        guard let loc else { return }
        let needMap = cfg.template == .classic || (cfg.template == .advanced && cfg.showMap)
        let needWeather = cfg.template == .advanced &&
            (cfg.showWeather || cfg.showHumidity || cfg.showWind || cfg.showPressure)
        Task {
            if needMap { await mapService.refresh(coordinate: loc.coordinate, kind: cfg.mapKind) }
            if needWeather { await weather.refresh(for: loc) }
        }
    }

    // MARK: Numbering

    private var serialPeek: Int { UserDefaults.standard.integer(forKey: Self.serialKey) + 1 }
    private func commitSerial(_ n: Int) { UserDefaults.standard.set(n, forKey: Self.serialKey) }

    var nextSerial: Int { serialPeek }

    func resetSerial() {
        UserDefaults.standard.set(0, forKey: Self.serialKey)
        objectWillChange.send()
    }

    // MARK: Snapshot

    func makeSnapshot(serial: Int? = nil, video: Bool = false) -> CaptureSnapshot {
        var s = CaptureSnapshot(
            date: timeVerifier.now,
            location: location.location,
            address: location.address,
            headingDeg: location.heading?.bestHeading,
            magneticUT: location.heading?.totalField,
            weather: weather.weather,
            map: mapService.image,
            simulated: location.isSimulated,
            phase: phase
        )
        s.serial = serial
        s.isVideo = video
        return s
    }

    var previewContent: StampContent {
        let cfg = settings.cfg
        let serial = cfg.showSerial ? serialPeek : nil
        var snap = makeSnapshot(serial: serial, video: camera.mode == .video)
        snap.withSeconds = camera.isRecording
        return StampComposer.build(snap, cfg: cfg, logo: settings.logo)
    }

    // MARK: Controls

    func setMode(_ mode: CaptureMode) {
        camera.setMode(mode, quality: settings.cfg.videoQuality)
    }

    func cycleTimer() {
        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
    }

    func cyclePhase() {
        switch phase {
        case "": phase = "Before"
        case "Before": phase = "After"
        default: phase = ""
        }
    }

    func tapFocus(device: CGPoint, layer: CGPoint) {
        camera.focus(at: device)
        focusPoint = layer
        focusTask?.cancel()
        focusTask = Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            if !Task.isCancelled { focusPoint = nil }
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: Shutter

    func shutterTapped() {
        guard camera.isConfigured, countdown == nil else { return }

        if camera.mode == .video {
            if camera.isRecording { stopRecording() } else if !isSaving { beginVideoWithTimer() }
            return
        }
        guard !isSaving else { return }
        if timerSeconds > 0 {
            runCountdown { [weak self] in self?.capture() }
        } else {
            capture()
        }
    }

    private func runCountdown(then action: @escaping () -> Void) {
        let secs = timerSeconds
        Task {
            for i in stride(from: secs, to: 0, by: -1) {
                countdown = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdown = nil
            action()
        }
    }

    // MARK: Photo capture

    private func capture() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSaving = true
        let cfg = settings.cfg
        let snapshot = makeSnapshot(serial: cfg.showSerial ? serialPeek : nil)   // frozen at the moment of the shutter
        let logo = settings.logo
        let mirror = camera.position == .front && cfg.mirrorFront

        camera.capture(lockPortrait: cfg.lockPortrait) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.isSaving = false
                self.showToast("Capture failed. Please try again.")
            case .success(let data):
                Task { await self.process(data: data, snapshot: snapshot, cfg: cfg, logo: logo, mirror: mirror) }
            }
        }
    }

    private func makeRecord(snapshot s: CaptureSnapshot,
                            cfg: StampSettings,
                            filename: String,
                            sha: String,
                            video: Bool,
                            duration: Double?,
                            imported: Bool) -> PhotoRecord {
        let advanced = cfg.template == .advanced
        return PhotoRecord(
            id: UUID(),
            filename: filename,
            date: s.date,
            latitude: s.location?.coordinate.latitude,
            longitude: s.location?.coordinate.longitude,
            altitude: s.location.flatMap { $0.verticalAccuracy >= 0 ? $0.altitude : nil },
            accuracy: s.location.flatMap { $0.horizontalAccuracy >= 0 ? $0.horizontalAccuracy : nil },
            address: s.address.full,
            note: advanced && cfg.showNote ? cfg.note : "",
            project: advanced && cfg.showProject ? cfg.project : "",
            phase: s.phase,
            sha256: sha,
            simulated: s.simulated,
            kind: video ? "video" : "photo",
            serial: s.serial,
            duration: duration,
            imported: imported ? true : nil
        )
    }

    private func process(data: Data, snapshot: CaptureSnapshot, cfg: StampSettings, logo: UIImage?, mirror: Bool) async {
        let result = await Task.detached(priority: .userInitiated) { () -> ProcessedPhoto? in
            PhotoPipeline.process(data: data, snapshot: snapshot, cfg: cfg, logo: logo, mirror: mirror)
        }.value

        guard let out = result else {
            isSaving = false
            showToast("Could not create the photo.")
            return
        }

        let record = makeRecord(
            snapshot: snapshot, cfg: cfg,
            filename: PhotoStore.makeFilename(date: snapshot.date, ext: "jpg"),
            sha: PhotoStore.sha256Hex(data: out.stamped),
            video: false, duration: nil, imported: false
        )
        store.add(jpeg: out.stamped, record: record)
        if let n = snapshot.serial { commitSerial(n) }
        lastThumb = await store.loadThumbnail(record, maxPixel: 160)

        var savedToPhotos = false
        if cfg.saveToPhotos {
            do {
                try await PhotosSaver.save(jpeg: out.stamped, location: snapshot.location, date: snapshot.date)
                if let original = out.original {
                    try await PhotosSaver.save(jpeg: original, location: snapshot.location, date: snapshot.date)
                }
                savedToPhotos = true
            } catch {
                savedToPhotos = false
            }
        }

        isSaving = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if !cfg.saveToPhotos {
            showToast("Saved in GeoStamp gallery")
        } else if savedToPhotos {
            showToast("Saved to Photos and gallery")
        } else {
            showToast("Saved in gallery. Allow Photos access to also save there.")
        }
    }

    // MARK: Video

    private func beginVideoWithTimer() {
        if timerSeconds > 0 {
            runCountdown { [weak self] in self?.startRecording() }
        } else {
            startRecording()
        }
    }

    private func overlayContent(_ snap: CaptureSnapshot) -> StampContent {
        StampComposer.build(snap, cfg: settings.cfg, logo: settings.logo)
    }

    private func refreshOverlay() {
        guard var base = recordSnapshot else { return }
        let cfg = settings.cfg
        var live = makeSnapshot(serial: base.serial, video: true)
        live.withSeconds = true
        live.phase = base.phase
        base = live
        let content = overlayContent(base)
        camera.recorder.setOverlay(StampRenderer.overlay(size: cfg.videoQuality.frameSize, content: content, cfg: cfg))
    }

    private func startRecording() {
        let cfg = settings.cfg
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        var start = makeSnapshot(serial: cfg.showSerial ? serialPeek : nil, video: true)
        start.withSeconds = true
        recordSnapshot = start

        refreshOverlay()                                    // overlay must exist before the first frame
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        camera.startRecording(url: url, bitrate: cfg.videoQuality.bitrate)
        recordSeconds = 0

        recordTask?.cancel()
        recordTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.recordSeconds += 1
                self.refreshOverlay()                       // keeps seconds and position live
            }
        }
    }

    func stopRecordingIfNeeded() {
        if camera.isRecording { stopRecording() }
    }

    private func stopRecording() {
        recordTask?.cancel()
        isSaving = true
        let start = recordSnapshot
        let cfg = settings.cfg
        camera.stopRecording { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.isSaving = false
                self.showToast("Video was not saved. Please try again.")
            case .success(let (url, duration)):
                Task { await self.finishVideo(url: url, duration: duration, start: start, cfg: cfg) }
            }
        }
    }

    private func finishVideo(url: URL, duration: Double, start: CaptureSnapshot?, cfg: StampSettings) async {
        guard let snap = start else {
            isSaving = false
            return
        }
        let sha = await Task.detached(priority: .userInitiated) { PhotoStore.sha256Hex(of: url) }.value ?? ""
        let record = makeRecord(
            snapshot: snap, cfg: cfg,
            filename: PhotoStore.makeFilename(date: snap.date, ext: "mp4"),
            sha: sha, video: true, duration: duration, imported: false
        )
        store.addFile(at: url, record: record)
        if let n = snap.serial { commitSerial(n) }
        lastThumb = await store.loadThumbnail(record, maxPixel: 160)

        var saved = false
        if cfg.saveToPhotos {
            do {
                try await PhotosSaver.saveVideo(at: store.url(for: record), location: snap.location, date: snap.date)
                saved = true
            } catch {
                saved = false
            }
        }
        isSaving = false
        recordSeconds = 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if !cfg.saveToPhotos {
            showToast("Video saved in GeoStamp gallery")
        } else {
            showToast(saved ? "Video saved to Photos and gallery" : "Video saved in gallery. Allow Photos access to also save there.")
        }
    }

    // MARK: Import existing photos

    func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        let cfg = settings.cfg
        let logo = settings.logo
        var done = 0

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let snap = await ImportService.snapshot(from: data, cfg: cfg)

            let result = await Task.detached(priority: .userInitiated) { () -> ProcessedPhoto? in
                PhotoPipeline.process(data: data, snapshot: snap, cfg: cfg, logo: logo,
                                      mirror: false, crop: false, maxSide: 4096)
            }.value
            guard let out = result else { continue }

            let record = makeRecord(
                snapshot: snap, cfg: cfg,
                filename: PhotoStore.makeFilename(date: snap.date, ext: "jpg"),
                sha: PhotoStore.sha256Hex(data: out.stamped),
                video: false, duration: nil, imported: true
            )
            store.add(jpeg: out.stamped, record: record)
            if cfg.saveToPhotos {
                try? await PhotosSaver.save(jpeg: out.stamped, location: snap.location, date: snap.date)
            }
            done += 1
        }

        if let r = store.records.first {
            lastThumb = await store.loadThumbnail(r, maxPixel: 160)
        }
        showToast("Stamped \(done) of \(items.count) photos")
    }
}
