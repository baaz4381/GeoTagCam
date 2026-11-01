import SwiftUI
import AVKit
import CoreLocation

struct PhotoDetailView: View {
    @EnvironmentObject var store: PhotoStore
    @Environment(\.dismiss) private var dismiss
    let record: PhotoRecord

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var verifyText: String?
    @State private var verifyOK = true
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                media
                details
                actions
            }
            .padding()
        }
        .navigationTitle(record.isVideo ? "Video" : "Photo")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let u = store.url(for: record)
            if record.isVideo {
                player = AVPlayer(url: u)
            } else {
                image = await Task.detached(priority: .userInitiated) {
                    PhotoStore.downsample(url: u, maxPixel: 2200)
                }.value
            }
        }
        .onDisappear { player?.pause() }
        .confirmationDialog("Delete this from GeoStamp gallery?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(record)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A copy saved in your Photos library is not removed.")
        }
    }

    // MARK: Media

    @ViewBuilder
    private var media: some View {
        if record.isVideo {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if record.isImported { row("Source", "Imported from your photo library") }
            if !record.phase.isEmpty { row("Tag", record.phase) }
            if let n = record.serial { row("Number", "\(n)") }
            row("Date", record.date.formatted(date: .abbreviated, time: .standard))
            if let d = record.duration { row("Length", String(format: "%.0f s", d)) }
            if !record.address.isEmpty { row("Address", record.address) }
            if let la = record.latitude, let lo = record.longitude {
                row("Coordinates", String(format: "%.6f, %.6f", la, lo))
            }
            if let a = record.altitude { row("Altitude", String(format: "%.0f m", a)) }
            if let acc = record.accuracy { row("Accuracy", String(format: "±%.0f m", acc)) }
            if !record.project.isEmpty { row("Project", record.project) }
            if !record.note.isEmpty { row("Note", record.note) }
            row("File", record.filename)
            row("SHA-256", record.sha256)
            if record.simulated {
                Label("The phone reported a simulated location for this capture.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
        }
        .font(.system(size: 14))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ShareLink(item: store.url(for: record)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                if let la = record.latitude, let lo = record.longitude,
                   let url = URL(string: "http://maps.apple.com/?ll=\(la),\(lo)&q=Location") {
                    Link(destination: url) {
                        Label("Maps", systemImage: "map")
                    }
                }
                Button { verify() } label: {
                    Label("Verify", systemImage: "checkmark.shield")
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                if let la = record.latitude, let lo = record.longitude {
                    Button {
                        UIPasteboard.general.string = String(format: "%.6f, %.6f", la, lo)
                        message = "Coordinates copied"
                    } label: {
                        Label("Copy coordinates", systemImage: "doc.on.doc")
                    }
                }
                Button { saveToPhotos() } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.bordered)

            if let t = verifyText {
                Text(t)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(verifyOK ? .green : .red)
            }
            if let m = message {
                Text(m).font(.footnote).foregroundStyle(.secondary)
            }

            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private func verify() {
        let u = store.url(for: record)
        let expected = record.sha256
        Task {
            let hash = await Task.detached(priority: .userInitiated) {
                PhotoStore.sha256Hex(of: u)
            }.value
            if hash == expected {
                verifyOK = true
                verifyText = "✓ File is unchanged since it was captured."
            } else {
                verifyOK = false
                verifyText = "✗ File does not match the original capture."
            }
        }
    }

    private func saveToPhotos() {
        let u = store.url(for: record)
        let loc: CLLocation? = {
            guard let la = record.latitude, let lo = record.longitude else { return nil }
            return CLLocation(latitude: la, longitude: lo)
        }()
        let isVideo = record.isVideo
        let date = record.date
        Task {
            do {
                if isVideo {
                    try await PhotosSaver.saveVideo(at: u, location: loc, date: date)
                } else {
                    let data = try Data(contentsOf: u)
                    try await PhotosSaver.save(jpeg: data, location: loc, date: date)
                }
                message = "Saved to Photos"
            } catch {
                message = "Could not save. Allow Photos access in Settings."
            }
        }
    }
}
