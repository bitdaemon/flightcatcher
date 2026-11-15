import SwiftUI
import SimCore

/// Settings for the random traffic generator.
struct TrafficView: View {
    @ObservedObject var runner: SimRunner
    @State private var seedText = ""

    /// A low and a high slider. Moving one past the other pushes the other along.
    private func rateRange(_ title: String, low: Binding<Double>, high: Binding<Double>, limit: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            HStack {
                Text("Low").frame(width: 34, alignment: .leading).foregroundStyle(.secondary)
                Slider(value: low, in: 0...limit, step: 1)
                Text("\(Int(low.wrappedValue))").monospacedDigit().frame(width: 28, alignment: .trailing)
            }
            HStack {
                Text("High").frame(width: 34, alignment: .leading).foregroundStyle(.secondary)
                Slider(value: high, in: 0...limit, step: 1)
                Text("\(Int(high.wrappedValue))").monospacedDigit().frame(width: 28, alignment: .trailing)
            }
        }
    }

    private var arrivalLow: Binding<Double> {
        Binding(get: { runner.traffic.arrivalRange.lowerBound }, set: { v in
            var t = runner.traffic
            t.arrivalsMaxPerHour = max(v, t.arrivalRange.upperBound)
            t.arrivalsPerHour = v
            runner.traffic = t
        })
    }

    private var arrivalHigh: Binding<Double> {
        Binding(get: { runner.traffic.arrivalRange.upperBound }, set: { v in
            var t = runner.traffic
            t.arrivalsMaxPerHour = v
            t.arrivalsPerHour = min(t.arrivalsPerHour, v)
            runner.traffic = t
        })
    }

    private var departureLow: Binding<Double> {
        Binding(get: { runner.traffic.departureRange.lowerBound }, set: { v in
            var t = runner.traffic
            t.departuresMaxPerHour = max(v, t.departureRange.upperBound)
            t.departuresPerHour = v
            runner.traffic = t
        })
    }

    private var departureHigh: Binding<Double> {
        Binding(get: { runner.traffic.departureRange.upperBound }, set: { v in
            var t = runner.traffic
            t.departuresMaxPerHour = v
            t.departuresPerHour = min(t.departuresPerHour, v)
            runner.traffic = t
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RANDOM TRAFFIC").font(.ui(size: 13, weight: .semibold))
            Toggle("Generate traffic", isOn: $runner.traffic.enabled)

            rateRange("Arrivals per hour", low: arrivalLow, high: arrivalHigh, limit: 60)
            rateRange("Departures per hour", low: departureLow, high: departureHigh, limit: 40)
            HStack {
                Text("Variation")
                Picker("", selection: $runner.traffic.variation) {
                    ForEach(TrafficVariation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text("The rates wander inside each range: Steady picks a new rate every 20 to 30 minutes, Moderate every 8 to 15, Lively every 3 to 8 with bigger jumps. Set Low and High equal for a fixed rate. The current rates are shown in Airport info.")
                .font(.ui(size: 10)).foregroundStyle(.secondary)

            Divider()
            Text("APPROACH AREA").font(.ui(size: 13, weight: .semibold))
            HStack {
                Text("Radius")
                Slider(value: $runner.areaRadiusNM, in: 20...80, step: 5)
                Text("\(Int(runner.areaRadiusNM)) NM").monospacedDigit().frame(width: 52, alignment: .trailing)
            }
            Stepper(value: $runner.areaCeilingFt, in: 6000...24000, step: 1000) {
                Text("Ceiling  \(runner.areaCeilingFt) ft").monospacedDigit()
            }
            Text("Arrivals are handed to you where their STAR crosses the edge of the area, at or below the ceiling, and call in on first contact. Departures must be handed off before they leave it. Applies to new traffic and start-up traffic at the next airport load.")
                .font(.ui(size: 10)).foregroundStyle(.secondary)
            Divider()

            Menu("Presets") {
                ForEach(TrafficPreset.all) { preset in
                    Button(preset.name) { preset.apply(to: &runner.traffic) }
                }
            }

            Divider()
            Toggle("IFR traffic", isOn: $runner.traffic.ifr)
            Toggle("VFR traffic", isOn: $runner.traffic.vfr)
            Text("VFR is off by default. The switch is saved, but no VFR aircraft are generated yet. Departures wait at the holding point (three per runway) until you clear them.")
                .font(.ui(size: 10)).foregroundStyle(.secondary)

            Text("Aircraft types").font(.ui(size: 12))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(AircraftCategory.allCases) { category in
                        DisclosureGroup {
                            ForEach(AircraftCatalog.types(in: category)) { type in
                                Toggle(type.canFlyIFR ? "\(type.code)  \(type.name)" : "\(type.code)  \(type.name) (VFR only)",
                                       isOn: typeBinding(type))
                                    .disabled(!type.canFlyIFR)
                                    .padding(.leading, 8)
                            }
                        } label: {
                            Toggle(category.title, isOn: categoryBinding(category))
                        }
                    }
                }
            }
            .frame(height: 190)

            Divider()
            HStack {
                Text("Seed")
                TextField("random each start", text: $seedText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applySeedText() }
                Button("Set") { applySeedText() }
            }
            Text("Current seed \(String(runner.trafficSeed)). Enter it to repeat the same traffic; empty means a new seed on each start.")
                .font(.ui(size: 10)).foregroundStyle(.secondary)
        }
        .onAppear { seedText = runner.traffic.fixedSeed.map(String.init) ?? "" }
    }

    private func applySeedText() {
        let trimmed = seedText.trimmingCharacters(in: .whitespaces)
        runner.traffic.fixedSeed = trimmed.isEmpty ? nil : UInt64(trimmed)
        seedText = runner.traffic.fixedSeed.map(String.init) ?? ""
    }

    private func categoryBinding(_ category: AircraftCategory) -> Binding<Bool> {
        Binding(get: { runner.traffic.enabledCategories.contains(category) },
                set: { on in
                    if on { runner.traffic.enabledCategories.insert(category) }
                    else { runner.traffic.enabledCategories.remove(category) }
                })
    }

    private func typeBinding(_ type: AircraftType) -> Binding<Bool> {
        Binding(get: { !runner.traffic.disabledTypes.contains(type.code) },
                set: { on in
                    if on { runner.traffic.disabledTypes.remove(type.code) }
                    else { runner.traffic.disabledTypes.insert(type.code) }
                })
    }
}
