import SwiftUI

@main
struct GeoStampCamApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var store: PhotoStore
    @StateObject private var location: LocationService
    @StateObject private var camera: CameraViewModel

    init() {
        let s = SettingsStore()
        let st = PhotoStore()
        let l = LocationService()
        _settings = StateObject(wrappedValue: s)
        _store = StateObject(wrappedValue: st)
        _location = StateObject(wrappedValue: l)
        _camera = StateObject(wrappedValue: CameraViewModel(settings: s, store: st, location: l))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(camera)
                .preferredColorScheme(.dark)
        }
    }
}
