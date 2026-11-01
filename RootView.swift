import SwiftUI

struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CameraScreen(tab: $tab)
                .tabItem { Label("Camera", systemImage: "camera.fill") }
                .tag(0)
            GalleryScreen()
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }
                .tag(1)
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(2)
        }
        .tint(.yellow)
    }
}
