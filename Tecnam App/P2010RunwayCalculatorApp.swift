import SwiftUI

/// The main entry point for the Tecnam P2010 runway calculator application.
///
/// This file bootstraps a simple SwiftUI application that provides a user
/// interface for computing take‑off ground roll and distance to clear a 50 ft
/// obstacle for the Tecnam P2010 Mk2 fitted with the Lycoming IO‑390 engine.
/// Users can input the expected outside air temperature, pressure altitude,
/// headwind or tailwind component, runway surface type (paved or grass) and
/// take‑off weight in kilograms.  The app uses performance tables derived
/// from the 2021 Aircraft Flight Manual (AFM) supplement for this aircraft
/// and performs bilinear interpolation across weight, altitude and
/// temperature to produce realistic estimates.  Corrections for wind and
/// grass runways are applied according to the AFM instructions.
@main
struct P2010RunwayCalculatorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}