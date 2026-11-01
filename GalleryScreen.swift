import SwiftUI
import PhotosUI

enum GalleryFilter: Hashable {
    case all, photos, videos, before, after
    case project(String)

    var title: String {
        switch self {
        case .all: return "All"
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .before: return "Before"
        case .after: return "After"
        case .project(let p): return p
        }
    }
}

struct GalleryScreen: View {
    @EnvironmentObject var store: PhotoStore
    @EnvironmentObject var vm: CameraViewModel
    @Environment(\.closeToCamera) private var closeToCamera

    @State private var filter: GalleryFilter = .all
    @State private var search = ""
    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var working = false
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var importItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var confirmDelete = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 2)]

    private var projects: [String] {
        Array(Set(store.records.map { $0.project }.filter { !$0.isEmpty })).sorted()
    }

    private var shown: [PhotoRecord] {
        store.records.filter { r in
            switch filter {
            case .all: return true
            case .photos: return !r.isVideo
            case .videos: return r.isVideo
            case .before: return r.phase == "Before"
            case .after: return r.phase == "After"
            case .project(let p): return r.project == p
            }
        }
        .filter { r in
            let q = search.trimmingCharacters(in: .whitespaces)
            if q.isEmpty { return true }
            return r.address.localizedCaseInsensitiveContains(q)
                || r.note.localizedCaseInsensitiveContains(q)
                || r.project.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.records.isEmpty {
                    emptyView
                } else if shown.isEmpty {
                    Text("Nothing matches").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    grid
                }
            }
            .navigationTitle("Gallery")
            .searchable(text: $search, prompt: "Address, note or project")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { closeToCamera() } label: { Image(systemName: "camera.fill") }
                    PhotosPicker(selection: $importItems, maxSelectionCount: 20, matching: .images) {
                        Image(systemName: "plus")
                    }
                    Menu {
                        Picker("Show", selection: $filter) {
                            Text("All").tag(GalleryFilter.all)
                            Text("Photos").tag(GalleryFilter.photos)
                            Text("Videos").tag(GalleryFilter.videos)
                            Text("Before").tag(GalleryFilter.before)
                            Text("After").tag(GalleryFilter.after)
                            ForEach(projects, id: \.self) { p in
                                Text("Project: " + p).tag(GalleryFilter.project(p))
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.records.isEmpty {
                        Button(selecting ? "Done" : "Select") {
                            selecting.toggle()
                            selected.removeAll()
                        }
                    }
                }
            }
            .navigationDestination(for: PhotoRecord.self) { record in
                PhotoDetailView(record: record)
            }
            .safeAreaInset(edge: .bottom) {
                if selecting { selectionBar }
            }
            .overlay {
                if importing {
                    ProgressView("Stamping photos…")
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                }
            }
            .onChange(of: importItems) { items in
                guard !items.isEmpty else { return }
                Task {
                    importing = true
                    await vm.importPhotos(items)
                    importItems = []
                    importing = false
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: shareItems)
            }
            .confirmationDialog("Delete \(selected.count) item(s) from the GeoStamp gallery?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(ids: selected)
                    selected.removeAll()
                    selecting = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Copies saved in your Photos library are not removed.")
            }
        }
    }

    // MARK: Grid

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("No photos yet").font(.headline)
            Text("Photos and videos you take appear here. Tap + to stamp photos you already have.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(shown) { r in
                    if selecting {
                        Button { toggle(r) } label: { cell(r) }
                    } else {
                        NavigationLink(value: r) { cell(r) }
                    }
                }
            }
        }
    }

    private func durationText(_ s: Double) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func cell(_ r: PhotoRecord) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(ThumbnailView(record: r))
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if !r.phase.isEmpty {
                    Text(r.phase.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.yellow))
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if r.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                        if let d = r.duration { Text(durationText(d)) }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selected.contains(r.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(selected.contains(r.id) ? .yellow : .white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
    }

    private func toggle(_ r: PhotoRecord) {
        if selected.contains(r.id) { selected.remove(r.id) } else { selected.insert(r.id) }
    }

    // MARK: Selection actions

    private func barLabel(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 20))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private var selectionBar: some View {
        VStack(spacing: 6) {
            HStack {
                Button(selected.count == shown.count ? "Clear" : "Select all") {
                    if selected.count == shown.count { selected.removeAll() } else { selected = Set(shown.map { $0.id }) }
                }
                .font(.footnote.weight(.semibold))
                Spacer()
                Text("\(selected.count) selected").font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button { shareFiles() } label: { barLabel("square.and.arrow.up", "Share") }
                Button { makeReport() } label: { barLabel(working ? "hourglass" : "doc.richtext", "PDF") }
                Menu {
                    Button("CSV spreadsheet") { exportData(csv: true) }
                    Button("KML for Google Earth") { exportData(csv: false) }
                } label: { barLabel("tablecells", "Data") }
                Button(role: .destructive) { confirmDelete = true } label: { barLabel("trash", "Delete") }
            }
            .disabled(selected.isEmpty || working)
            .opacity(selected.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var chosen: [PhotoRecord] { store.records.filter { selected.contains($0.id) } }

    private func present(_ items: [Any]) {
        shareItems = items
        showShare = true
    }

    private func shareFiles() {
        present(chosen.map { store.url(for: $0) })
    }

    private func exportData(csv: Bool) {
        let list = chosen
        if let url = csv ? Exporter.csv(list) : Exporter.kml(list) {
            present([url])
        }
    }

    private func makeReport() {
        let items: [PDFReport.Item] = chosen.filter { !$0.isVideo }.map { (record: $0, url: store.url(for: $0)) }
        guard !items.isEmpty else {
            vm.showToast("Select at least one photo for the PDF")
            return
        }
        working = true
        Task {
            let url = await Task.detached(priority: .userInitiated) {
                PDFReport.make(items: items, title: "Photo Report")
            }.value
            working = false
            if let url { present([url]) }
        }
    }
}
