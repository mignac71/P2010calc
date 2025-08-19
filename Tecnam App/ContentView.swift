import SwiftUI

/// Represents the available runway surface types.  Values correspond to
/// correction factors as described in the AFM.  Grass runways require a
/// 10 percent increase to the ground roll (and obstacle distance) while
/// paved surfaces do not.
enum RunwaySurface: String, CaseIterable, Identifiable {
    case paved = "Paved"
    case grass = "Grass"

    var id: String { rawValue }
}

/// A single performance record for a given altitude and temperature.
/// Distances are stored in metres.
struct PerformanceEntry {
    let groundRoll: Double
    let over50ft: Double
}

/// Encapsulates the performance table for a particular weight.  Each
/// table stores distances for a grid of altitudes (ft) and temperatures
/// (°C).  To keep the data compact and typed we use nested arrays rather
/// than nested dictionaries.  The index of an altitude or temperature in
/// the outer arrays corresponds to its position in the `altitudes` and
/// `temperatures` lists.
struct PerformanceTable {
    let weight: Double // kilograms
    let altitudes: [Double] // feet
    let temperatures: [Double] // °C
    let groundRoll: [[Double]] // [altitudeIndex][temperatureIndex] in metres
    let over50ft: [[Double]]  // same layout as groundRoll
}

/// Performs bilinear interpolation on a grid of values.  Given a 2‑D
/// array `values` indexed by altitude and temperature, together with
/// sorted lists of altitudes and temperatures, this helper returns a
/// distance for the specified altitude and temperature.  Values outside
/// the range of the tables are clamped to the nearest available row or
/// column.
private func interpolateValue(from values: [[Double]],
                              altitudes: [Double],
                              temperatures: [Double],
                              altitude: Double,
                              temperature: Double) -> Double {
    // Find bounding indices for altitude
    let lowerAltIndex = max(0, altitudes.firstIndex(where: { $0 >= altitude }) ?? (altitudes.count - 1))
    let upperAltIndex = min(lowerAltIndex, altitudes.count - 1)
    // If altitude is below the first entry, clamp to first; if above last, clamp to last
    var altLowIdx = 0
    var altHighIdx = 0
    if altitude <= altitudes.first! {
        altLowIdx = 0
        altHighIdx = 0
    } else if altitude >= altitudes.last! {
        altLowIdx = altitudes.count - 1
        altHighIdx = altitudes.count - 1
    } else {
        // altitude is between two points; find indexes
        for i in 0..<(altitudes.count - 1) {
            if altitude >= altitudes[i] && altitude <= altitudes[i + 1] {
                altLowIdx = i
                altHighIdx = i + 1
                break
            }
        }
    }
    let altLow = altitudes[altLowIdx]
    let altHigh = altitudes[altHighIdx]
    let altRatio: Double = altHighIdx == altLowIdx ? 0.0 : (altitude - altLow) / (altHigh - altLow)

    // Find bounding indices for temperature
    var tempLowIdx = 0
    var tempHighIdx = 0
    if temperature <= temperatures.first! {
        tempLowIdx = 0
        tempHighIdx = 0
    } else if temperature >= temperatures.last! {
        tempLowIdx = temperatures.count - 1
        tempHighIdx = temperatures.count - 1
    } else {
        for i in 0..<(temperatures.count - 1) {
            if temperature >= temperatures[i] && temperature <= temperatures[i + 1] {
                tempLowIdx = i
                tempHighIdx = i + 1
                break
            }
        }
    }
    let tempLow = temperatures[tempLowIdx]
    let tempHigh = temperatures[tempHighIdx]
    let tempRatio: Double = tempHighIdx == tempLowIdx ? 0.0 : (temperature - tempLow) / (tempHigh - tempLow)

    // Retrieve distances at the four surrounding corners
    let v00 = values[altLowIdx][tempLowIdx]
    let v01 = values[altLowIdx][tempHighIdx]
    let v10 = values[altHighIdx][tempLowIdx]
    let v11 = values[altHighIdx][tempHighIdx]

    // Interpolate along temperature for low and high altitude rows
    let v0 = v00 + (v01 - v00) * tempRatio
    let v1 = v10 + (v11 - v10) * tempRatio
    // Interpolate along altitude
    let v = v0 + (v1 - v0) * altRatio
    return v
}

/// Interpolates performance between two weight tables.  It first
/// interpolates within each table over altitude and temperature using
/// `interpolateValue` and then blends the results based upon the
/// requested take‑off weight.  If the weight exactly matches one of the
/// tables, no blending occurs.
private func interpolatePerformance(for weight: Double,
                                    altitude: Double,
                                    temperature: Double,
                                    tables: [PerformanceTable]) -> (groundRoll: Double, over50ft: Double) {
    // Sort tables by weight to ensure monotonic interpolation
    let sorted = tables.sorted(by: { $0.weight < $1.weight })
    guard let firstTable = sorted.first else {
        return (0, 0)
    }
    // If weight is below the smallest table weight
    if weight <= firstTable.weight {
        let g = interpolateValue(from: firstTable.groundRoll,
                                 altitudes: firstTable.altitudes,
                                 temperatures: firstTable.temperatures,
                                 altitude: altitude,
                                 temperature: temperature)
        let o = interpolateValue(from: firstTable.over50ft,
                                 altitudes: firstTable.altitudes,
                                 temperatures: firstTable.temperatures,
                                 altitude: altitude,
                                 temperature: temperature)
        return (g, o)
    }
    // If weight is above the largest table weight
    if weight >= sorted.last!.weight {
        let table = sorted.last!
        let g = interpolateValue(from: table.groundRoll,
                                 altitudes: table.altitudes,
                                 temperatures: table.temperatures,
                                 altitude: altitude,
                                 temperature: temperature)
        let o = interpolateValue(from: table.over50ft,
                                 altitudes: table.altitudes,
                                 temperatures: table.temperatures,
                                 altitude: altitude,
                                 temperature: temperature)
        return (g, o)
    }
    // Find bounding weight tables
    var lowerIndex = 0
    var upperIndex = 0
    for i in 0..<(sorted.count - 1) {
        if weight >= sorted[i].weight && weight <= sorted[i + 1].weight {
            lowerIndex = i
            upperIndex = i + 1
            break
        }
    }
    let lower = sorted[lowerIndex]
    let upper = sorted[upperIndex]
    let weightRatio: Double = (weight - lower.weight) / (upper.weight - lower.weight)
    // Interpolate within each table first
    let gLower = interpolateValue(from: lower.groundRoll,
                                 altitudes: lower.altitudes,
                                 temperatures: lower.temperatures,
                                 altitude: altitude,
                                 temperature: temperature)
    let oLower = interpolateValue(from: lower.over50ft,
                                 altitudes: lower.altitudes,
                                 temperatures: lower.temperatures,
                                 altitude: altitude,
                                 temperature: temperature)
    let gUpper = interpolateValue(from: upper.groundRoll,
                                 altitudes: upper.altitudes,
                                 temperatures: upper.temperatures,
                                 altitude: altitude,
                                 temperature: temperature)
    let oUpper = interpolateValue(from: upper.over50ft,
                                 altitudes: upper.altitudes,
                                 temperatures: upper.temperatures,
                                 altitude: altitude,
                                 temperature: temperature)
    // Blend based on weight
    let g = gLower + (gUpper - gLower) * weightRatio
    let o = oLower + (oUpper - oLower) * weightRatio
    return (g, o)
}

struct ContentView: View {
    // MARK: - User Inputs
    @State private var temperature: Double = 15.0 // °C
    @State private var altitude: Double = 0.0     // ft
    @State private var headwind: Double = 0.0    // knots.  Positive for headwind, negative for tailwind
    @State private var weight: Double = 1060.0   // kg
    @State private var surface: RunwaySurface = .paved
    @State private var showTemperaturePicker = false
    @State private var showAltitudePicker = false
    @State private var showWindPicker = false
    @State private var showWeightPicker = false

    // Discrete options for wheel-based pickers
    private let temperatureOptions = Array(stride(from: -25.0, through: 50.0, by: 1.0))
    private let altitudeOptions = Array(stride(from: 0.0, through: 6000.0, by: 100.0))
    private let headwindOptions = Array(stride(from: -20.0, through: 20.0, by: 1.0))
    private let weightOptions = Array(stride(from: 960.0, through: 1160.0, by: 10.0))

    // Performance tables derived from the 2021 AFM supplement for
    // Tecnam P2010 Mk2 IO‑390.  Distances are provided in metres.
    private let performanceTables: [PerformanceTable] = {
        // Common altitude and temperature grid
        let alts: [Double] = [0, 1000, 2000, 3000, 4000, 5000, 6000]
        let temps: [Double] = [-25, 0, 25, 50]
        // Table for 960 kg (2116 lb)
        let groundRoll960: [[Double]] = [
            [149, 179, 211, 246], // S.L.
            [160, 191, 226, 263], // 1000 ft
            [171, 205, 242, 282], // 2000 ft
            [183, 220, 260, 303], // 3000 ft
            [197, 236, 279, 325], // 4000 ft
            [211, 253, 299, 349], // 5000 ft
            [227, 272, 321, 374]  // 6000 ft
        ]
        let over50ft960: [[Double]] = [
            [217, 260, 308, 358], // S.L.
            [233, 279, 330, 384], // 1000 ft
            [249, 299, 353, 412], // 2000 ft
            [267, 321, 379, 441], // 3000 ft
            [287, 344, 406, 474], // 4000 ft
            [308, 369, 436, 508], // 5000 ft
            [331, 397, 469, 546]  // 6000 ft
        ]
        let table960 = PerformanceTable(weight: 960, altitudes: alts, temperatures: temps, groundRoll: groundRoll960, over50ft: over50ft960)
        // Table for 1060 kg (2337 lb)
        let groundRoll1060: [[Double]] = [
            [193, 231, 273, 318], // S.L.
            [206, 248, 292, 341], // 1000 ft
            [221, 265, 314, 365], // 2000 ft
            [237, 285, 336, 392], // 3000 ft
            [254, 305, 361, 420], // 4000 ft
            [273, 328, 387, 451], // 5000 ft
            [293, 352, 416, 485]  // 6000 ft
        ]
        let over50ft1060: [[Double]] = [
            [281, 337, 398, 464], // S.L.
            [301, 361, 426, 497], // 1000 ft
            [322, 387, 457, 533], // 2000 ft
            [346, 415, 490, 571], // 3000 ft
            [371, 445, 526, 613], // 4000 ft
            [398, 478, 564, 658], // 5000 ft
            [428, 513, 606, 706]  // 6000 ft
        ]
        let table1060 = PerformanceTable(weight: 1060, altitudes: alts, temperatures: temps, groundRoll: groundRoll1060, over50ft: over50ft1060)
        // Table for 1160 kg (2557 lb)
        let groundRoll1160: [[Double]] = [
            [244, 292, 345, 402], // S.L.
            [261, 313, 370, 431], // 1000 ft
            [280, 336, 396, 462], // 2000 ft
            [300, 360, 425, 495], // 3000 ft
            [322, 386, 456, 531], // 4000 ft
            [345, 414, 489, 570], // 5000 ft
            [371, 445, 526, 613]  // 6000 ft
        ]
        let over50ft1160: [[Double]] = [
            [355, 426, 503, 586], // S.L.
            [380, 456, 539, 628], // 1000 ft
            [408, 489, 578, 673], // 2000 ft
            [437, 525, 620, 722], // 3000 ft
            [469, 563, 665, 775], // 4000 ft
            [503, 604, 714, 832], // 5000 ft
            [541, 649, 766, 893]  // 6000 ft
        ]
        let table1160 = PerformanceTable(weight: 1160, altitudes: alts, temperatures: temps, groundRoll: groundRoll1160, over50ft: over50ft1160)
        return [table960, table1060, table1160]
    }()

    // MARK: - Computation
    /// Calculates ground roll and 50 ft obstacle distance based on user inputs.
    private func calculateDistances() -> (groundRoll: Double, over50ft: Double) {
        // Limit temperature and altitude to within table bounds (for extrapolation we clamp to extremes)
        let alt = max(0, min(6000, altitude))
        let temp = max(-25, min(50, temperature))
        // Base interpolation across weight/alt/temp
        var result = interpolatePerformance(for: weight,
                                           altitude: alt,
                                           temperature: temp,
                                           tables: performanceTables)
        // Apply wind correction (metres).  Positive headwind reduces distance, negative (tailwind) increases.
        if headwind >= 0 {
            let correction = -10.0 * headwind
            result.groundRoll = max(0, result.groundRoll + correction)
            result.over50ft = max(0, result.over50ft + correction)
        } else {
            let correction = 20.0 * abs(headwind)
            result.groundRoll += correction
            result.over50ft += correction
        }
        // Apply grass runway correction
        if surface == .grass {
            result.groundRoll *= 1.10
            result.over50ft *= 1.10
        }
        return result
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    // Display a header image if the asset exists.
                    // The image should be added to the Xcode asset catalog with the name
                    // "splash".  A sample PNG (p2010_splash.png) is provided in the
                    // repository and can be imported into Assets.xcassets to achieve
                    // the same look as shown in the project documentation.
                    Image("splash")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(8)
                        .padding(.vertical, 8)
                }
                Section(header: Text("Input Parameters")) {
                    VStack(alignment: .leading) {
                        Text("Temperature (°C)")
                        Button(String(Int(temperature))) {
                            showTemperaturePicker = true
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sheet(isPresented: $showTemperaturePicker) {
                        VStack {
                            Picker("Temperature", selection: $temperature) {
                                ForEach(temperatureOptions, id: \.self) { value in
                                    Text("\(Int(value))").tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            Button("Done") { showTemperaturePicker = false }
                                .padding()
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Pressure Altitude (ft)")
                        Button(String(Int(altitude))) {
                            showAltitudePicker = true
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sheet(isPresented: $showAltitudePicker) {
                        VStack {
                            Picker("Altitude", selection: $altitude) {
                                ForEach(altitudeOptions, id: \.self) { value in
                                    Text("\(Int(value))").tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            Button("Done") { showAltitudePicker = false }
                                .padding()
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Headwind (+) / Tailwind (−) (kt)")
                        Button(String(Int(headwind))) {
                            showWindPicker = true
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sheet(isPresented: $showWindPicker) {
                        VStack {
                            Picker("Wind", selection: $headwind) {
                                ForEach(headwindOptions, id: \.self) { value in
                                    Text("\(Int(value))").tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            Button("Done") { showWindPicker = false }
                                .padding()
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Take‑off Weight (kg)")
                        Button(String(Int(weight))) {
                            showWeightPicker = true
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .sheet(isPresented: $showWeightPicker) {
                        VStack {
                            Picker("Weight", selection: $weight) {
                                ForEach(weightOptions, id: \.self) { value in
                                    Text("\(Int(value))").tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            Button("Done") { showWeightPicker = false }
                                .padding()
                        }
                    }
                    Picker("Runway Surface", selection: $surface) {
                        ForEach(RunwaySurface.allCases) { surface in
                            Text(surface.rawValue).tag(surface)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Section(header: Text("Results")) {
                    let result = calculateDistances()
                    HStack {
                        Text("Ground Roll")
                        Spacer()
                        Text(String(format: "%.0f m", result.groundRoll))
                        Text("(")
                        Text(String(format: "%.0f ft", result.groundRoll * 3.28084))
                        Text(")")
                    }
                    HStack {
                        Text("Distance to clear 50 ft obstacle")
                        Spacer()
                        Text(String(format: "%.0f m", result.over50ft))
                        Text("(")
                        Text(String(format: "%.0f ft", result.over50ft * 3.28084))
                        Text(")")
                    }
                }
            }
            .navigationTitle("P2010 Runway Calculator")
        }
    }
}
