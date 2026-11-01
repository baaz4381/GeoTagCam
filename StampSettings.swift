import SwiftUI
import UIKit
import AVFoundation

// MARK: - Option enums

enum StampTemplate: String, Codable, CaseIterable, Identifiable {
    case classic, advanced, compact, compass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .advanced: return "Advanced"
        case .compact: return "Compact"
        case .compass: return "Compass"
        }
    }
    var detail: String {
        switch self {
        case .classic: return "Map, address, coordinates, date and time. Nothing to set up."
        case .advanced: return "You choose every field: weather, compass, altitude, note, logo and more."
        case .compact: return "A slim strip with coordinates and date only."
        case .compass: return "A live compass dial with heading, address, coordinates and time."
        }
    }
}

enum VideoQuality: String, Codable, CaseIterable, Identifiable {
    case hd720, hd1080
    var id: String { rawValue }
    var title: String { self == .hd720 ? "720p" : "1080p" }
    var preset: AVCaptureSession.Preset { self == .hd720 ? .hd1280x720 : .hd1920x1080 }
    /// Portrait frame size the stamp overlay is drawn at.
    var frameSize: CGSize {
        self == .hd720 ? CGSize(width: 720, height: 1280) : CGSize(width: 1080, height: 1920)
    }
    var bitrate: Int { self == .hd720 ? 4_000_000 : 8_000_000 }
}

enum MapKind: String, Codable, CaseIterable, Identifiable {
    case standard, satellite, hybrid
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CoordFormat: String, Codable, CaseIterable, Identifiable {
    case decimal, dms
    var id: String { rawValue }
    var title: String { self == .decimal ? "Decimal degrees" : "Degrees, minutes, seconds" }
}

enum DateStyle: String, Codable, CaseIterable, Identifiable {
    case dmy12, dmy24, ymd24, long, us
    var id: String { rawValue }
    var pattern: String {
        switch self {
        case .dmy12: return "dd/MM/yyyy hh:mm a"
        case .dmy24: return "dd/MM/yyyy HH:mm:ss"
        case .ymd24: return "yyyy-MM-dd HH:mm:ss"
        case .long: return "EEEE, dd MMM yyyy hh:mm a"
        case .us: return "MM/dd/yyyy hh:mm a"
        }
    }
    func example(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? "Metric (°C, km/h, m)" : "Imperial (°F, mph, ft)" }
}

enum StampPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, top
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AspectOption: String, Codable, CaseIterable, Identifiable {
    case r4x3, r1x1, r16x9
    var id: String { rawValue }
    var title: String {
        switch self {
        case .r4x3: return "4:3"
        case .r1x1: return "1:1"
        case .r16x9: return "16:9"
        }
    }
    /// width / height when the photo is held in portrait
    var portraitRatio: CGFloat? {
        switch self {
        case .r4x3: return 3.0 / 4.0
        case .r1x1: return 1.0
        case .r16x9: return 9.0 / 16.0
        }
    }
    var next: AspectOption {
        switch self {
        case .r4x3: return .r1x1
        case .r1x1: return .r16x9
        case .r16x9: return .r4x3
        }
    }
}

enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case yellow, white, cyan, green, orange
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var uiColor: UIColor {
        switch self {
        case .yellow: return UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
        case .white: return .white
        case .cyan: return UIColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 1)
        case .green: return UIColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 1)
        case .orange: return UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        }
    }
    var color: Color { Color(uiColor) }
}

// MARK: - Settings model

struct StampSettings: Codable, Equatable {
    var template: StampTemplate = .advanced

    // Fields (Advanced template)
    var showMap = true
    var mapKind: MapKind = .hybrid
    var showAddress = true
    var showFlag = true
    var showLatLong = true
    var showDateTime = true
    var showAltitude = true
    var showAccuracy = true
    var showCompass = true
    var showMagnetic = false
    var showWeather = true
    var showHumidity = false
    var showWind = false
    var showPressure = false
    var showProject = true
    var project = ""
    var showNote = true
    var note = ""
    var showHashtags = true
    var hashtags = ""
    var showLogo = false

    // Extras (all templates)
    var showQR = false
    var showSerial = false
    var projects: [String] = []
    var videoQuality: VideoQuality = .hd1080

    // Formats (all templates)
    var coordFormat: CoordFormat = .decimal
    var dateStyle: DateStyle = .dmy12
    var showTimeZone = true
    var units: UnitSystem = .metric

    // Look
    var position: StampPosition = .bottom
    var scale: Double = 1.0
    var opacity: Double = 0.55
    var accent: AccentChoice = .yellow

    // Camera
    var aspect: AspectOption = .r4x3
    var showGrid = false
    var mirrorFront = true
    var lockPortrait = false

    // Saving / trust
    var saveToPhotos = true
    var saveOriginal = false
    var embedExif = true
    var useVerifiedTime = true
}

// MARK: - Persistence

final class SettingsStore: ObservableObject {
    @Published var cfg: StampSettings {
        didSet { persist() }
    }
    @Published private(set) var logo: UIImage? = nil

    private static let key = "geostamp.settings.v1"
    private static var logoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("logo.png")
    }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(StampSettings.self, from: d) {
            cfg = s
        } else {
            cfg = StampSettings()
        }
        logo = UIImage(contentsOfFile: Self.logoURL.path)
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }

    func setLogo(_ image: UIImage?) {
        guard let image else {
            try? FileManager.default.removeItem(at: Self.logoURL)
            logo = nil
            cfg.showLogo = false
            return
        }
        let maxSide: CGFloat = 512
        let longest = max(image.size.width, image.size.height, 1)
        let k = min(1, maxSide / longest)
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try? small.pngData()?.write(to: Self.logoURL, options: .atomic)
        logo = small
        cfg.showLogo = true
    }
}
