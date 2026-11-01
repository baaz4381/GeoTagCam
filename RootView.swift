import SwiftUI

/// Camera is full screen with nothing on top of the shutter button.
/// Gallery and Settings get a simple bottom bar so you can switch back.
struct RootView: View {
    @State private var tab = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch tab {
            case 1:
                withTabBar { GalleryScreen() }
            case 2:
                withTabBar { SettingsScreen() }
            default:
                CameraScreen(tab: $tab)
            }
        }
        .tint(.yellow)
    }

    private func withTabBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
            tabBar
        }
    }

    private var tabBar: some View {
        HStack {
            tabButton("Camera", "camera.fill", 0)
            tabButton("Gallery", "photo.on.rectangle", 1)
            tabButton("Settings", "slider.horizontal.3", 2)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(white: 0.1).ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(_ title: String, _ icon: String, _ index: Int) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(tab == index ? Color.yellow : Color.gray)
            .frame(maxWidth: .infinity)
        }
    }
}
