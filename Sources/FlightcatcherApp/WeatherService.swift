import Foundation
import SimCore

/// Fetches the latest METAR for an airport from the NOAA Aviation Weather Center (no key needed; the service asks for a
/// custom User-Agent and at most 100 requests a minute, and the app asks once every 15 minutes).
enum WeatherService {
    static func fetch(icao: String) async -> WeatherReport? {
        guard let url = URL(string: "https://aviationweather.gov/api/data/metar?ids=\(icao.uppercased())&format=json") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("flightcATCher/0.1 (+https://github.com/YOUR-GITHUB-USER/flightcatcher)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return MetarParser.parse(json: data)
    }
}
