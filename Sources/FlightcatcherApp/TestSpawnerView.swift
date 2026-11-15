import SwiftUI
import SimCore

/// State of the test spawner panel. The position is a bearing and distance from a reference (the airport centre or a
/// runway threshold); clicking the scope fills them in.
@MainActor
final class TestSpawnModel: ObservableObject {
    /// "" is the airport centre, otherwise a runway id.
    @Published var reference = ""
    @Published var bearing: Double = 270
    @Published var distance: Double = 10
    @Published var heading: Double = 90
    @Published var altitude: Double = 3000
    @Published var speed: Double = 190
    @Published var typeCode = "B738"
    @Published var callsign = ""
    @Published var placing = false

    func position(runner: SimRunner) -> (east: Double, north: Double) {
        let origin = runner.referencePoint(runway: reference.isEmpty ? nil : reference)
        let offset = LocalProjection.offset(bearingDeg: bearing, distanceNM: distance)
        return (origin.east + offset.east, origin.north + offset.north)
    }

    /// A click on the scope: the bearing and distance from the reference to that point.
    func place(east: Double, north: Double, runner: SimRunner) {
        let origin = runner.referencePoint(runway: reference.isEmpty ? nil : reference)
        let de = east - origin.east
        let dn = north - origin.north
        distance = (hypot(de, dn) * 10).rounded() / 10
        var b = atan2(de, dn) * 180 / .pi
        if b < 0 { b += 360 }
        bearing = b.rounded()
        placing = false
    }

    func spec(runner: SimRunner) -> TestSpawn {
        let p = position(runner: runner)
        return TestSpawn(callsign: callsign, typeCode: typeCode, eastNM: p.east, northNM: p.north,
                         headingDeg: heading, altitudeFt: altitude, speedKt: speed)
    }

    /// A preset: on the extended centreline of a runway, flying toward it.
    func final(runway: String, bearingDeg: Double, nm: Double, altitudeFt: Double, speedKt: Double) {
        reference = runway
        bearing = (bearingDeg + 180).truncatingRemainder(dividingBy: 360)
        distance = nm
        heading = bearingDeg
        altitude = altitudeFt
        speed = speedKt
    }
}

/// Settings > Debug > "Show the test spawner panel". Places an aircraft for troubleshooting.
struct TestSpawnerView: View {
    @ObservedObject var runner: SimRunner
    @ObservedObject var model: TestSpawnModel
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    private let mono = Font.ui(size: 11, design: .monospaced)

    private var runways: [Runway] { runner.airport?.runways ?? [] }
    private var types: [AircraftType] { AircraftCatalog.all }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                HStack {
                    label("Callsign")
                    TextField("auto", text: $model.callsign).textFieldStyle(.roundedBorder)
                }
                HStack {
                    label("Type")
                    Picker("", selection: $model.typeCode) {
                        ForEach(types, id: \.code) { Text("\($0.code)  \($0.name)").tag($0.code) }
                    }
                    .labelsHidden()
                }
                Divider()
                HStack {
                    label("From")
                    Picker("", selection: $model.reference) {
                        Text("Airport centre").tag("")
                        ForEach(runways, id: \.id) { Text("Runway \($0.id) threshold").tag($0.id) }
                    }
                    .labelsHidden()
                }
                number("Bearing from it", $model.bearing, unit: "deg true")
                number("Distance", $model.distance, unit: "NM")
                Button(model.placing ? "Click on the scope... (click here to cancel)" : "Place by clicking the scope") {
                    model.placing.toggle()
                }
                Divider()
                number("Heading", $model.heading, unit: "deg true")
                number("Altitude", $model.altitude, unit: "ft")
                number("Speed", $model.speed, unit: "kt")
            }
            .font(mono)

            if !runways.isEmpty {
                Text("Presets").font(mono).foregroundStyle(theme.heading)
                Menu("Final approach to a runway...") {
                    ForEach(runways, id: \.id) { runway in
                        Menu("Runway \(runway.id)") {
                            ForEach([5.0, 10.0, 15.0, 20.0], id: \.self) { nm in
                                Button("\(Int(nm)) NM out, 3000 ft, 190 kt") {
                                    model.final(runway: runway.id, bearingDeg: runway.trueBearingDeg, nm: nm,
                                                altitudeFt: 3000, speedKt: 190)
                                }
                            }
                        }
                    }
                }
            }
            let p = model.position(runner: runner)
            Text(String(format: "Position %.1f E, %.1f N of the scope origin", p.east, p.north))
                .font(mono).foregroundStyle(theme.dimText)
            HStack {
                Button("Spawn aircraft") { runner.spawnTest(model.spec(runner: runner)) }
                    .keyboardShortcut(.return, modifiers: .command)
                Button(runner.selectedCallsign.map { "Delete \($0)" } ?? "Delete selected") { runner.deleteSelected() }
                    .disabled(runner.selectedCallsign == nil)
                    .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        .padding(10)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(theme.text).frame(width: 96, alignment: .leading)
    }

    private func number(_ title: String, _ value: Binding<Double>, unit: String) -> some View {
        HStack {
            label(title)
            TextField("", value: value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text(unit).foregroundStyle(theme.dimText)
        }
    }
}
