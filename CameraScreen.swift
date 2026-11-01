import SwiftUI
import AVFoundation
import UIKit

struct CameraScreen: View {
    @EnvironmentObject var vm: CameraViewModel
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var location: LocationService
    @Environment(\.scenePhase) private var scenePhase
    @Binding var tab: Int
    @State private var pinchStart: CGFloat = 1
    @State private var showNote = false

    private typealias Insets = (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat)
    private static let topH: CGFloat = 52

    var body: some View {
        GeometryReader { geo in
            let cfg = settings.cfg
            let videoMode = vm.camera.mode == .video
            let aspect: AspectOption = videoMode ? .r16x9 : cfg.aspect
            let ratio = aspect.portraitRatio ?? 0.75
            let insets = Self.safeInsets(geo.safeAreaInsets)
            let isLandscape = geo.size.width > geo.size.height

            ZStack(alignment: .top) {
                Color.black

                if isLandscape {
                    landscapeLayout(geo.size, cfg: cfg, ratio: ratio, insets: insets)
                } else {
                    portraitLayout(geo.size, cfg: cfg, aspect: aspect, ratio: ratio, insets: insets)
                }

                if let n = vm.countdown {
                    Text("\(n)")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(radius: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                if let t = vm.toast {
                    Text(t)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, isLandscape ? 16 : insets.top + Self.topH + 8)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 0.2), value: vm.toast)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { vm.stopRecordingIfNeeded() }
        }
        .sheet(isPresented: $showNote) { QuickNoteSheet() }
    }

    // MARK: Layouts

    /// Phone held upright: preview on top, controls along the bottom.
    private func portraitLayout(_ size: CGSize, cfg: StampSettings, aspect: AspectOption,
                                ratio: CGFloat, insets: Insets) -> some View {
        let w = size.width
        let ph = w / ratio
        let y0: CGFloat = aspect == .r16x9 ? 0 : insets.top + Self.topH
        let barH: CGFloat = 170 + insets.bottom
        let overlap = max(0, y0 + ph - (size.height - barH))

        return ZStack(alignment: .top) {
            previewArea(width: w, height: ph, cfg: cfg, stampInset: overlap)
                .frame(width: w, height: ph)
                .offset(y: y0)

            VStack(spacing: 0) {
                Group {
                    if vm.camera.isRecording {
                        recordingBar
                    } else {
                        topBar(cfg)
                    }
                }
                .frame(height: Self.topH)
                .padding(.top, insets.top)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0.7), Color.clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                Spacer(minLength: 0)
                bottomBar(bottomInset: insets.bottom)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Phone held sideways: preview on the left, controls in a column on the right.
    private func landscapeLayout(_ size: CGSize, cfg: StampSettings,
                                 ratio: CGFloat, insets: Insets) -> some View {
        let panelW: CGFloat = 200
        let availW = max(size.width - insets.left - insets.right - panelW, 100)
        let availH = max(size.height - max(insets.bottom, 8) - 8, 100)
        let wide = 1 / ratio                         // width / height when sideways
        let pw = min(availW, availH * wide)
        let ph = pw / wide

        return HStack(spacing: 0) {
            previewArea(width: pw, height: ph, cfg: cfg, stampInset: 0)
                .frame(width: pw, height: ph)
                .frame(width: availW, height: size.height)
            landscapePanel(cfg)
                .frame(width: panelW, height: size.height)
        }
        .padding(.leading, insets.left)
        .padding(.trailing, insets.right)
        .frame(width: size.width, height: size.height, alignment: .leading)
    }

    private func landscapePanel(_ cfg: StampSettings) -> some View {
        VStack(spacing: 10) {
            if vm.camera.isRecording {
                recordingBar
            } else {
                HStack(spacing: 6) { flashButton; timerButton; tagButton }
                HStack(spacing: 6) { noteButton; gearButton; aspectButton(cfg) }
            }
            zoomChips(size: 34, spacing: 4)
            if !vm.camera.isRecording { modeSwitch }
            HStack(spacing: 6) {
                thumbButton
                shutterButton
                flipButton
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .frame(maxHeight: .infinity)
    }

    /// Real notch and home-indicator sizes. The GeometryReader above ignores the
    /// safe area, so its own insets come back as zero; read them from the window.
    private static func safeInsets(_ proxy: EdgeInsets) -> Insets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        let w = window?.safeAreaInsets ?? .zero
        return (max(proxy.top, w.top), max(proxy.bottom, w.bottom),
                max(proxy.leading, w.left), max(proxy.trailing, w.right))
    }

    // MARK: Preview area

    private func previewArea(width: CGFloat, height: CGFloat, cfg: StampSettings, stampInset: CGFloat) -> some View {
        ZStack {
            if vm.camera.permissionDenied {
                permissionView
            } else {
                CameraPreview(
                    session: vm.camera.session,
                    onTap: { device, layerPoint in vm.tapFocus(device: device, layer: layerPoint) },
                    onPinch: { scale, state in
                        if state == .began { pinchStart = vm.camera.displayZoom }
                        vm.camera.setZoom(pinchStart * scale)
                    },
                    onShutter: { vm.shutterTapped() }
                )
            }

            if cfg.showGrid { GridLines() }

            if let p = vm.focusPoint {
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 1.5)
                    .frame(width: 70, height: 70)
                    .position(x: p.x, y: p.y)
                    .allowsHitTesting(false)
            }

            statusChips(cfg)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: cfg.position == .bottom ? .topLeading : .bottomLeading)
                .padding(10)

            StampPreviewView(content: vm.previewContent, cfg: cfg)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: cfg.position == .bottom ? .bottom : .top)
                .padding(.bottom, cfg.position == .bottom ? stampInset : 0)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var permissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("Camera access is off").font(.headline)
            Text("Allow camera access in Settings to take stamped photos.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Open Settings") { openSettings() }
                .buttonStyle(.borderedProminent)
        }
        .foregroundColor(.white)
        .padding()
    }

    // MARK: Status chips

    private func statusChips(_ cfg: StampSettings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if location.isDenied {
                Button { openSettings() } label: {
                    chip("Location is off. Tap to enable", color: .red, icon: "location.slash.fill")
                }
            } else if let l = location.location {
                let acc = l.horizontalAccuracy
                chip(String(format: "GPS ±%.0f m", acc),
                     color: acc <= 20 ? .green : (acc <= 65 ? .yellow : .orange),
                     icon: "location.fill")
            } else {
                chip("Locating…", color: .orange, icon: "location")
            }
            if location.isSimulated {
                chip("Simulated location", color: .red, icon: "exclamationmark.triangle.fill")
            }
            if vm.timeVerifier.clockSuspect {
                chip(cfg.useVerifiedTime ? "Phone clock is wrong. Using network time" : "Phone clock looks wrong",
                     color: .orange, icon: "clock.badge.exclamationmark")
            }
            if vm.camera.micDenied && vm.camera.mode == .video {
                Button { openSettings() } label: {
                    chip("Microphone is off. Video will have no sound", color: .orange, icon: "mic.slash.fill")
                }
            }
        }
    }

    private func chip(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.85)))
    }

    // MARK: Top controls (shared by the portrait bar and the landscape panel)

    private var flashIcon: String {
        if vm.camera.mode == .video { return vm.camera.flashMode == .on ? "flashlight.on.fill" : "flashlight.off.fill" }
        if vm.camera.flashMode == .on { return "bolt.fill" }
        if vm.camera.flashMode == .auto { return "bolt.badge.automatic.fill" }
        return "bolt.slash.fill"
    }

    private var recordingBar: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 12, height: 12)
            Text(String(format: "%02d:%02d", vm.recordSeconds / 60, vm.recordSeconds % 60))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private var flashButton: some View {
        Button { vm.camera.cycleFlash() } label: {
            Image(systemName: flashIcon)
                .foregroundColor(vm.camera.flashMode == .off ? .white : .yellow)
                .frame(width: 40, height: 40)
        }
        .opacity(vm.camera.hasFlash ? 1 : 0.35)
        .disabled(!vm.camera.hasFlash)
    }

    private var timerButton: some View {
        Button { vm.cycleTimer() } label: {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                if vm.timerSeconds > 0 {
                    Text("\(vm.timerSeconds)s").font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundColor(vm.timerSeconds > 0 ? .yellow : .white)
            .frame(minWidth: 40, minHeight: 40)
        }
    }

    private var tagButton: some View {
        Button { vm.cyclePhase() } label: {
            Text(vm.phase.isEmpty ? "Tag" : vm.phase)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(vm.phase.isEmpty ? .white : .black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(vm.phase.isEmpty ? Color.white.opacity(0.2) : Color.yellow))
        }
    }

    private var noteButton: some View {
        Button { showNote = true } label: {
            Image(systemName: "square.and.pencil")
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
        }
    }

    private var gearButton: some View {
        Button { tab = 2 } label: {
            Image(systemName: "gearshape.fill")
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
        }
    }

    @ViewBuilder
    private func aspectButton(_ cfg: StampSettings) -> some View {
        if vm.camera.mode == .photo {
            Button { settings.cfg.aspect = cfg.aspect.next } label: {
                Text(cfg.aspect.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 40, minHeight: 40)
            }
        } else {
            Text(cfg.videoQuality.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(minWidth: 40, minHeight: 40)
        }
    }

    private func topBar(_ cfg: StampSettings) -> some View {
        HStack {
            flashButton
            Spacer()
            timerButton
            Spacer()
            tagButton
            Spacer()
            noteButton
            Spacer()
            gearButton
            Spacer()
            aspectButton(cfg)
        }
        .font(.system(size: 18, weight: .semibold))
        .padding(.horizontal, 14)
    }

    // MARK: Bottom controls

    private func bottomBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            zoomChips()
            if !vm.camera.isRecording { modeSwitch }
            HStack {
                thumbButton.frame(maxWidth: .infinity)
                shutterButton
                flipButton.frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, max(bottomInset, 16) + 6)
        .background(
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        )
    }

    private var flipButton: some View {
        Button { vm.camera.flip() } label: {
            Image(systemName: "camera.rotate.fill")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.15)))
        }
        .disabled(vm.camera.isRecording)
        .opacity(vm.camera.isRecording ? 0.35 : 1)
    }

    private var modeSwitch: some View {
        HStack(spacing: 4) {
            modeButton("PHOTO", .photo)
            modeButton("VIDEO", .video)
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private func modeButton(_ title: String, _ m: CaptureMode) -> some View {
        let selected = vm.camera.mode == m
        return Button { vm.setMode(m) } label: {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(selected ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.yellow : Color.clear))
        }
    }

    private func zoomLabel(_ z: CGFloat) -> String {
        z < 1 ? "0.5x" : "\(Int(z))x"
    }

    private func zoomChips(size: CGFloat = 40, spacing: CGFloat = 8) -> some View {
        HStack(spacing: spacing) {
            ForEach(vm.camera.zoomPresets, id: \.self) { z in
                let active = abs(vm.camera.displayZoom - z) < 0.12
                Button { vm.camera.setZoom(z) } label: {
                    Text(zoomLabel(z))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(active ? .yellow : .white)
                        .frame(width: size, height: size)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
            }
        }
    }

    private var shutterButton: some View {
        Button { vm.shutterTapped() } label: {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                if vm.camera.mode == .video {
                    if vm.camera.isRecording {
                        RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(Color.red).frame(width: 60, height: 60).opacity(vm.isSaving ? 0.4 : 1)
                    }
                } else {
                    Circle().fill(Color.white).frame(width: 60, height: 60).opacity(vm.isSaving ? 0.4 : 1)
                }
                if vm.isSaving { ProgressView().tint(.black) }
            }
        }
        .disabled(vm.isSaving || vm.countdown != nil || !vm.camera.isConfigured)
    }

    @ViewBuilder
    private var thumbButton: some View {
        if let t = vm.lastThumb {
            Button { tab = 1 } label: {
                Image(uiImage: t)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.6), lineWidth: 1))
            }
        } else {
            Button { tab = 1 } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.15)))
            }
        }
    }

    private func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(u)
        }
    }
}
