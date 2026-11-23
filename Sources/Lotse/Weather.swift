import Foundation

struct Weather: Equatable {
    var city: String
    var temperature: Int
    var high: Int
    var low: Int
    var symbol: String
}

/// Eine Stunde der Vorschau.
struct HourWeather: Identifiable, Equatable {
    var id: Date { time }
    var time: Date
    var temperature: Int
    var symbol: String
    var rain: Int            // Regenwahrscheinlichkeit in Prozent
}

/// Wetter für einen von dir festgelegten Ort. Lotse fragt dafür den Dienst Open-Meteo (ohne Anmeldung):
/// Der Ortsname und seine Koordinaten verlassen dabei den Mac – sonst nichts. Ohne festgelegten Ort passiert nichts.
final class WeatherSource {
    private let model: IslandModel
    private var timer: Timer?
    private var place: (name: String, lat: Double, lon: Double)?

    init(model: IslandModel) { self.model = model }

    func start() {
        model.setWeatherCity = { [weak self] city in
            UserDefaults.standard.set(city, forKey: "weatherCity")
            self?.place = nil
            self?.model.weather = nil
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private var city: String { (UserDefaults.standard.string(forKey: "weatherCity") ?? "").trimmingCharacters(in: .whitespaces) }

    private func get(_ url: URL, _ done: @escaping ([String: Any]) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if let error { log("Wetter: \(error.localizedDescription)") }
                return
            }
            DispatchQueue.main.async { done(j) }
        }.resume()
    }

    private func refresh() {
        model.weatherCity = city
        guard !city.isEmpty else { return }
        if let place { load(place); return }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "de")]
        get(c.url!) { [weak self] j in
            guard let self, let r = (j["results"] as? [[String: Any]])?.first,
                  let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else {
                log("Wetter: Ort nicht gefunden"); return
            }
            let p = (r["name"] as? String ?? self.city, lat, lon)
            self.place = p
            self.load(p)
        }
    }

    private func load(_ p: (name: String, lat: Double, lon: Double)) {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [.init(name: "latitude", value: String(format: "%.2f", p.lat)), .init(name: "longitude", value: String(format: "%.2f", p.lon)),
                        .init(name: "current", value: "temperature_2m,weather_code,is_day"),
                        .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                        .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
                        .init(name: "forecast_hours", value: "9"), .init(name: "timeformat", value: "unixtime"),
                        .init(name: "forecast_days", value: "1"), .init(name: "timezone", value: "auto")]
        get(c.url!) { [weak self] j in
            guard let cur = j["current"] as? [String: Any], let t = cur["temperature_2m"] as? Double else { return }
            let daily = j["daily"] as? [String: Any]
            let hi = (daily?["temperature_2m_max"] as? [Double])?.first ?? t
            let lo = (daily?["temperature_2m_min"] as? [Double])?.first ?? t
            let code = cur["weather_code"] as? Int ?? 0
            let day = (cur["is_day"] as? Int ?? 1) == 1
            if let h = j["hourly"] as? [String: Any], let times = h["time"] as? [Double],
               let temps = h["temperature_2m"] as? [Double], let codes = h["weather_code"] as? [Int] {
                let rain = h["precipitation_probability"] as? [Any] ?? []
                let light = h["is_day"] as? [Int] ?? []
                var hours: [HourWeather] = []
                let cutoff = Date().addingTimeInterval(-1800)
                for i in 0..<min(times.count, temps.count, codes.count) {
                    let time = Date(timeIntervalSince1970: times[i])
                    guard time > cutoff else { continue }
                    let isDay: Bool = i < light.count ? light[i] == 1 : true
                    let chance: Int = i < rain.count ? (rain[i] as? Int ?? 0) : 0
                    let temp = Int(temps[i].rounded())
                    hours.append(HourWeather(time: time, temperature: temp, symbol: Self.symbol(codes[i], day: isDay), rain: chance))
                }
                self?.model.forecast = hours
            }
            self?.model.weather = Weather(city: p.name, temperature: Int(t.rounded()), high: Int(hi.rounded()), low: Int(lo.rounded()),
                                          symbol: Self.symbol(code, day: day))
        }
    }

    static func symbol(_ code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
