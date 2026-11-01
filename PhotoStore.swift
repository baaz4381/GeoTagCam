import UIKit
import ImageIO
import CryptoKit
import Photos
import AVFoundation
import CoreLocation

struct PhotoRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var filename: String
    var date: Date
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var accuracy: Double?
    var address: String
    var note: String
    var project: String
    var phase: String          // "", "Before" or "After"
    var sha256: String         // hash of the saved file, to prove it was not edited later
    var simulated: Bool
    // Added in version 2; optional so older saved indexes still load.
    var kind: String?          // "photo" or "video"
    var serial: Int?
    var duration: Double?
    var imported: Bool?

    var isVideo: Bool { kind == "video" }
    var isImported: Bool { imported == true }
}

/// App-private library of stamped photos and videos (Documents/GeoStampCam) plus a JSON index.
/// The folder is visible in the Files app under "On My iPhone".
final class PhotoStore: ObservableObject {
    @Published private(set) var records: [PhotoRecord] = []

    private let cache = NSCache<NSString, UIImage>()

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeoStampCam", isDirectory: true)
    }
    private static var indexURL: URL { directory.appendingPathComponent("index.json") }

    init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        load()
    }

    func url(for record: PhotoRecord) -> URL {
        Self.directory.appendingPathComponent(record.filename)
    }

    static func makeFilename(date: Date, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        let rnd = String(UUID().uuidString.prefix(4))
        return "GSC_\(f.string(from: date))_\(rnd).\(ext)"
    }

    // MARK: Index

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let list = try? dec.decode([PhotoRecord].self, from: data) {
            records = list.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        }
    }

    private func saveIndex() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(records) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }

    // MARK: Add / delete

    func add(jpeg: Data, record: PhotoRecord) {
        do {
            try jpeg.write(to: url(for: record), options: .atomic)
            records.insert(record, at: 0)
            saveIndex()
        } catch {
            // Disk full or similar; the photo may still be saved to Photos by the caller.
        }
    }

    /// Moves a finished video file into the library.
    func addFile(at source: URL, record: PhotoRecord) {
        let dest = url(for: record)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: source, to: dest)
            records.insert(record, at: 0)
            saveIndex()
        } catch {
            // Leave the temp file; caller reports the failure.
        }
    }

    func delete(_ record: PhotoRecord) {
        try? FileManager.default.removeItem(at: url(for: record))
        records.removeAll { $0.id == record.id }
        cache.removeObject(forKey: record.id.uuidString as NSString)
        saveIndex()
    }

    func delete(ids: Set<UUID>) {
        for r in records where ids.contains(r.id) {
            try? FileManager.default.removeItem(at: url(for: r))
        }
        records.removeAll { ids.contains($0.id) }
        saveIndex()
    }

    // MARK: Thumbnails

    func loadThumbnail(_ record: PhotoRecord, maxPixel: Int) async -> UIImage? {
        let key = "\(record.id.uuidString)-\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let u = url(for: record)
        let video = record.isVideo
        let img = await Task.detached(priority: .utility) { () -> UIImage? in
            video ? Self.videoThumbnail(url: u, maxPixel: maxPixel) : Self.downsample(url: u, maxPixel: maxPixel)
        }.value
        if let img { cache.setObject(img, forKey: key) }
        return img
    }

    static func downsample(url: URL, maxPixel: Int) -> UIImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func videoThumbnail(url: URL, maxPixel: Int) -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.2, preferredTimescale: 600), actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: Hashing

    static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Streams the file so large videos do not have to fit in memory.
    static func sha256Hex(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Save to the system Photos library

enum PhotosSaver {
    enum SaveError: Error { case denied, failed }

    private static func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
    }

    static func save(jpeg: Data, location: CLLocation?, date: Date) async throws {
        try await authorize()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = "public.jpeg"
            request.addResource(with: .photo, data: jpeg, options: options)
            request.location = location
            request.creationDate = date
        }
    }

    static func saveVideo(at url: URL, location: CLLocation?, date: Date) async throws {
        try await authorize()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            request?.location = location
            request?.creationDate = date
        }
    }
}
