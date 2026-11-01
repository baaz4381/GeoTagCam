import SwiftUI
import PhotosUI
import CoreLocation

struct SettingsScreen: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var vm: CameraViewModel
    @Environment(\.closeToCamera) private var closeToCamera
    @State private var logoItem: PhotosPickerItem?
    @State private var newProject = ""
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                templateSection
                formatSection
                if settings.cfg.template == .advanced {
                    fieldsSection
                    textSection
                }
                extrasSection
                projectsSection
                logoSection
                appearanceSection
                cameraSection
                savingSection
                resetSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { closeToCamera() } label: { Label("Camera", systemImage: "chevron.backward") }
                }
            }
            .onChange(of: logoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        settings.setLogo(img)
                    }
                    logoItem = nil
                }
            }
            .confirmationDialog("Reset all settings to defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset settings", role: .destructive) { settings.cfg = StampSettings() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your photos, videos and logo are not touched.")
            }
        }
    }

    // MARK: Preview

    private var previewContent: StampContent {
        var snap = vm.makeSnapshot(serial: settings.cfg.showSerial ? vm.nextSerial : nil)
        if snap.location == nil {
            snap.location = CLLocation(latitude: 28.6139, longitude: 77.2090)
            snap.address = AddressInfo(title: "New Delhi, Delhi, India", detail: "Connaught Place", countryCode: "IN")
            snap.headingDeg = 45
            snap.magneticUT = 48
            snap.weather = Weather(tempC: 27, humidity: 48, windKmh: 9, pressureHpa: 1012)
        }
        return StampComposer.build(snap, cfg: settings.cfg, logo: settings.logo)
    }

    private var previewSection: some View {
        Section {
            StampPreviewView(content: previewContent, cfg: settings.cfg)
                .listRowInsets(EdgeInsets())
                .listRowBackground(
                    LinearGradient(colors: [Color(white: 0.35), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                )
        } header: {
            Text("Live preview")
        }
    }

    // MARK: Sections

    private var templateSection: some View {
        Section("Template") {
            Picker("Template", selection: $settings.cfg.template) {
                ForEach(StampTemplate.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(settings.cfg.template.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var formatSection: some View {
        Section("Formats") {
            Picker("Coordinates", selection: $settings.cfg.coordFormat) {
                ForEach(CoordFormat.allCases) { Text($0.title).tag($0) }
            }
            Picker("Date and time", selection: $settings.cfg.dateStyle) {
                ForEach(DateStyle.allCases) { Text($0.example()).tag($0) }
            }
            Toggle("Show time zone", isOn: $settings.cfg.showTimeZone)
            Picker("Units", selection: $settings.cfg.units) {
                ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private var fieldsSection: some View {
        Section("Fields") {
            Toggle("Map", isOn: $settings.cfg.showMap)
            if settings.cfg.showMap {
                Picker("Map type", selection: $settings.cfg.mapKind) {
                    ForEach(MapKind.allCases) { Text($0.title).tag($0) }
                }
            }
            Toggle("Address", isOn: $settings.cfg.showAddress)
            if settings.cfg.showAddress {
                Toggle("Country flag", isOn: $settings.cfg.showFlag)
            }
            Toggle("Latitude and longitude", isOn: $settings.cfg.showLatLong)
            Toggle("Date and time", isOn: $settings.cfg.showDateTime)
            Toggle("Altitude", isOn: $settings.cfg.showAltitude)
            Toggle("GPS accuracy", isOn: $settings.cfg.showAccuracy)
            Toggle("Compass direction", isOn: $settings.cfg.showCompass)
            Toggle("Magnetic field", isOn: $settings.cfg.showMagnetic)
            Toggle("Temperature", isOn: $settings.cfg.showWeather)
            Toggle("Humidity", isOn: $settings.cfg.showHumidity)
            Toggle("Wind speed", isOn: $settings.cfg.showWind)
            Toggle("Air pressure", isOn: $settings.cfg.showPressure)
        }
    }

    private var textSection: some View {
        Section {
            Toggle("Project name", isOn: $settings.cfg.showProject)
            if settings.cfg.showProject {
                TextField("e.g. Site A, Block 2", text: $settings.cfg.project)
            }
            Toggle("Note", isOn: $settings.cfg.showNote)
            if settings.cfg.showNote {
                TextField("Note on every photo", text: $settings.cfg.note, axis: .vertical)
                    .lineLimit(1...3)
            }
            Toggle("Hashtags", isOn: $settings.cfg.showHashtags)
            if settings.cfg.showHashtags {
                TextField("travel, survey, site1", text: $settings.cfg.hashtags)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Text")
        } footer: {
            Text("Weather uses your location and the internet. Without a connection it is left out.")
        }
    }

    private var extrasSection: some View {
        Section {
            Toggle("QR code to the location", isOn: $settings.cfg.showQR)
            Toggle("Running photo number", isOn: $settings.cfg.showSerial)
            if settings.cfg.showSerial {
                HStack {
                    Text("Next number: \(vm.nextSerial)")
                    Spacer()
                    Button("Restart at 1", role: .destructive) { vm.resetSerial() }
                }
            }
            Picker("Video quality", selection: $settings.cfg.videoQuality) {
                ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Extras")
        } footer: {
            Text("The QR code opens the exact spot in a maps app. Videos are recorded the way you hold the phone (upright or sideways), with the stamp updating every second. Change video quality before switching to Video mode.")
        }
    }

    private var projectsSection: some View {
        Section {
            ForEach(settings.cfg.projects, id: \.self) { p in
                HStack {
                    Text(p)
                    Spacer()
                    if settings.cfg.project == p {
                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { settings.cfg.project = p }
            }
            .onDelete { offsets in
                settings.cfg.projects.remove(atOffsets: offsets)
            }
            HStack {
                TextField("Add a project", text: $newProject)
                Button("Add") {
                    let name = newProject.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    if !settings.cfg.projects.contains(name) { settings.cfg.projects.append(name) }
                    settings.cfg.project = name
                    newProject = ""
                }
                .disabled(newProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Projects")
        } footer: {
            Text("Tap a project to use it on new photos. Swipe left to delete. The gallery can be filtered by project.")
        }
    }

    private var logoSection: some View {
        Section("Logo") {
            PhotosPicker(selection: $logoItem, matching: .images) {
                Label(settings.logo == nil ? "Choose logo" : "Change logo", systemImage: "photo")
            }
            if let logo = settings.logo {
                HStack {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 36)
                    Spacer()
                    Button("Remove", role: .destructive) { settings.setLogo(nil) }
                }
                Toggle("Show logo on photos", isOn: $settings.cfg.showLogo)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Stamp look") {
            Picker("Position", selection: $settings.cfg.position) {
                ForEach(StampPosition.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                Text("Size \(Int(settings.cfg.scale * 100))%")
                Slider(value: $settings.cfg.scale, in: 0.8...1.6, step: 0.05)
            }
            VStack(alignment: .leading) {
                Text("Background \(Int(settings.cfg.opacity * 100))%")
                Slider(value: $settings.cfg.opacity, in: 0.2...0.9, step: 0.05)
            }
            Picker("Highlight colour", selection: $settings.cfg.accent) {
                ForEach(AccentChoice.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private var cameraSection: some View {
        Section("Camera") {
            Picker("Photo shape", selection: $settings.cfg.aspect) {
                ForEach(AspectOption.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Grid lines", isOn: $settings.cfg.showGrid)
            Toggle("Mirror front camera photos", isOn: $settings.cfg.mirrorFront)
            Toggle("Lock stamp to portrait", isOn: $settings.cfg.lockPortrait)
        }
    }

    private var savingSection: some View {
        Section {
            Toggle("Save to Photos", isOn: $settings.cfg.saveToPhotos)
            Toggle("Also save the unstamped original", isOn: $settings.cfg.saveOriginal)
                .disabled(!settings.cfg.saveToPhotos)
            Toggle("Write GPS into photo metadata", isOn: $settings.cfg.embedExif)
            Toggle("Use network time if phone clock is wrong", isOn: $settings.cfg.useVerifiedTime)
        } header: {
            Text("Saving and trust")
        } footer: {
            Text("Every photo and video is also kept in this app's gallery with a SHA-256 fingerprint, so you can check later that the file was not changed. The gallery folder is also visible in the Files app under On My iPhone > GeoStamp Cam.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset settings to defaults", role: .destructive) { confirmReset = true }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("Photos, locations and settings stay on your phone. The app contacts Apple (address and map), Open-Meteo (weather) and apple.com (clock check). No account, no ads, no tracking.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
