import Foundation
import CoreLocation

/// Handles location updates and retrieves local temperature and altitude.
/// If available, publishes values in degrees Celsius and feet respectively.
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var fetchedTemperature: Double?
    @Published var fetchedAltitude: Double?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Request permission and a one‑time location update.
    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        fetchWeather(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    /// Calls a simple weather service to obtain temperature and site elevation.
    private func fetchWeather(for location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current_weather=true") else {
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let temperature = (json["current_weather"] as? [String: Any])?["temperature"] as? Double
            let elevation = json["elevation"] as? Double
            DispatchQueue.main.async {
                if let temperature = temperature { self.fetchedTemperature = temperature }
                if let elevation = elevation { self.fetchedAltitude = elevation * 3.28084 }
            }
        }.resume()
    }
}
