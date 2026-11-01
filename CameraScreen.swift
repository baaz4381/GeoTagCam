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

    var body: some View {
        GeometryReader { geo in
            let cfg = settings.cfg
            let videoMode = vm.camera.mode == .video
            let aspect: AspectOption = videoMode ? .r16x9 : cfg.aspect
            let w = geo.size.width
            let ratio = aspect.portraitRatio ?? 0.75
            let ph = w / ratio
            let topH: CGFloat = 52
            let topInset = geo.safeAreaInsets.top
            let y0: CGFloat = aspect == .r16x9 ? 0 : topInset + topH
            let barH: CGFloat = 170 + geo.safeAreaInsets.bottom
            let overlap = max(0, y0 + ph - (geo.size.height - barH))

            ZStack(alignment: .top) {
                Color.black

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
                    .frame(height: topH)
                    .padding(.top, topInset)
                    Spacer(minLength: 0)
                    bottomBar(bottomInset: geo.safeAreaInsets.bottom)
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
                        .padding(.top, topInset + topH + 8)
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

    // MARK: Top bar

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

    private func topBar(_ cfg: StampSettings) -> some View {
        HStack {
            Button { vm.camera.cycleFlash() } label: {
                Image(systemName: flashIcon)
                    .foregroundColor(vm.camera.flashMode == .off ? .white : .yellow)
                    .frame(width: 40, height: 40)
            }
            .opacity(vm.camera.hasFlash ? 1 : 0.35)
            .disabled(!vm.camera.hasFlash)

            Spacer()

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

            Spacer()

            Button { vm.cyclePhase() } label: {
                Text(vm.phase.isEmpty ? "Tag" : vm.phase)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(vm.phase.isEmpty ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(vm.phase.isEmpty ? Color.white.opacity(0.2) : Color.yellow))
            }

            Spacer()

            Button { showNote = true } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
            }

            Spacer()

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
        .font(.system(size: 18, weight: .semibold))
        .padding(.horizontal, 14)
    }

    // MARK: Bottom bar

    private func bottomBar(bottomInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            zoomChips
            if !vm.camera.isRecording { modeSwitch }
            HStack {
                thumbButton.frame(maxWidth: .infinity)
                shutterButton
                Button { vm.camera.flip() } label: {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .disabled(vm.camera.isRecording)
                .opacity(vm.camera.isRecording ? 0.35 : 1)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, bottomInset + 6)
        .background(
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        )
    }

    private var modeSwitch: some View {
        HStack(spacing: 26) {
            modeButton("PHOTO", .photo)
            modeButton("VIDEO", .video)
        }
    }

    private func modeButton(_ title: String, _ m: CaptureMode) -> some View {
        Button { vm.setMode(m) } label: {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(vm.camera.mode == m ? Color.yellow : Color.white.opacity(0.8))
        }
    }

    private func zoomLabel(_ z: CGFloat) -> String {
        z < 1 ? "0.5x" : "\(Int(z))x"
    }

    private var zoomChips: some View {
        HStack(spacing: 8) {
            ForEach(vm.camera.zoomPresets, id: \.self) { z in
                let active = abs(vm.camera.displayZoom - z) < 0.12
                Button { vm.camera.setZoom(z) } label: {
                    Text(zoomLabel(z))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(active ? .yellow : .white)
                        .frame(width: 40, height: 40)
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
            Color.clear.frame(width: 48, height: 48)
        }
    }

    private func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(u)
        }
    }
}
