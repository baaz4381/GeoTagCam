import Foundation
import CoreLocation

/// Open-Meteo response (free for non-commercial use, no API key). See README for licensing notes.
private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let relative_humidity_2m: Double
        let wind_speed_10m: Double
        let surface_pressure: Double
    }
    let current: Current
}

@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var weather: Weather?

    private var lastLocation: CLLocation?
    private var lastFetch = Date.distantPast

    func refresh(for loc: CLLocation) async {
        if let last = lastLocation, loc.distance(from: last) < 2000,
           Date().timeIntervalSince(lastFetch) < 600 { return }

        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        comps?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", loc.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", loc.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,wind_speed_10m,surface_pressure"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh")
        ]
        guard let url = comps?.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let r = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            weather = Weather(
                tempC: r.current.temperature_2m,
                humidity: r.current.relative_humidity_2m,
                windKmh: r.current.wind_speed_10m,
                pressureHpa: r.current.surface_pressure
            )
            lastLocation = loc
            lastFetch = Date()
        } catch {
            // Offline or API error: keep the previous value, stamp simply omits weather if none.
        }
    }
}
