import Foundation

/// Compares the phone clock with the HTTP `Date` header of a trusted server.
/// If the phone clock was changed, stamps use the network time and the UI shows a warning.
@MainActor
final class TimeVerifier: ObservableObject {
    @Published private(set) var offset: TimeInterval?     // server time minus device time
    @Published private(set) var clockSuspect = false
    var useVerified = true

    /// The time to stamp on photos.
    var now: Date {
        if useVerified, let o = offset, abs(o) > 5 {
            return Date().addingTimeInterval(o)
        }
        return Date()
    }

    func check() async {
        guard let url = URL(string: "https://www.apple.com") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 6
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let t0 = Date()
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Date") else { return }
        let t1 = Date()

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let server = f.date(from: header) else { return }

        let midpoint = t0.addingTimeInterval(t1.timeIntervalSince(t0) / 2)
        let o = server.timeIntervalSince(midpoint)
        offset = o
        clockSuspect = abs(o) > 120
    }
}
