import Foundation
import SimCore

/// Drives the simulation from a timer. The simulation itself stays UI-free and deterministic;
/// this class only decides how often `tick()` is called.
@MainActor
final class SimRunner: ObservableObject {
    @Published private(set) var tickCount = 0
    @Published private(set) var aircraft: [Aircraft] = []
    @Published private(set) var radioLog: [RadioMessage] = []
    @Published private(set) var conflicts: [Conflict] = []
    @Published private(set) var lossCount = 0
    @Published private(set) var wind: Wind = .calm
    @Published private(set) var commandHistory: [String: [CommandRecord]] = [:]
    @Published private(set) var runwayStatuses: [RunwayStatus] = []
    /// Debug logging (Settings > Debug): the simulation records commands, approach progress and why an aircraft has
    /// not captured its approach, to a file and to the Debug log panel.
    @Published var debugLogging: Bool = UserDefaults.standard.bool(forKey: "debugLogging") {
        didSet {
            guard debugLogging != oldValue else { return }
            UserDefaults.standard.set(debugLogging, forKey: "debugLogging")
            sim.debugEnabled = debugLogging
            configureDebugLog()
            publish()
        }
    }
    /// Shows the test spawner panel (Settings > Debug): places an aircraft at a chosen position, heading, altitude and speed.
    @Published var testSpawner: Bool = UserDefaults.standard.bool(forKey: "testSpawner") {
        didSet { UserDefaults.standard.set(testSpawner, forKey: "testSpawner") }
    }
    @Published private(set) var debugEntries: [DebugEntry] = []
    @Published private(set) var debugFilePath = ""
    private let debugFile = DebugLogFile()
    /// Runways in use by a take-off or a landing, keyed by the runway end.
    @Published private(set) var runwayUses: [String: RunwayUse] = [:]
    /// Procedures with at least one runway the wind currently allows.
    @Published private(set) var availableProcedures: Set<String> = []
    @Published var selectedCallsign: String?
    /// Colour chosen for an aircraft (index into `AircraftMarkers.palette`), by callsign. Lasts until it leaves.
    @Published private(set) var markerColours: [String: Int] = [:]
    /// Aircraft whose assigned STAR or SID is drawn on the scope, whatever the layer switches say.
    @Published private(set) var shownProcedures: Set<String> = []
    /// Random traffic settings, saved between runs.
    @Published var traffic: TrafficSettings = SimRunner.loadTraffic() {
        didSet {
            SimRunner.saveTraffic(traffic)
            if traffic.fixedSeed != oldValue.fixedSeed { chooseTrafficSeed() }
            sim.traffic = traffic
        }
    }
    /// Random event rates (go-around, windshear, emergency), saved between runs.
    @Published var events: EventSettings = SimRunner.loadEvents() {
        didSet {
            if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: Self.eventsKey) }
            sim.events = events
        }
    }
    /// Where the wind comes from, saved between runs.
    @Published var weatherMode: WeatherMode = SimRunner.loadWeatherMode() {
        didSet {
            guard weatherMode != oldValue else { return }
            UserDefaults.standard.set(weatherMode.rawValue, forKey: Self.weatherKey)
            sim.weatherMode = weatherMode
        sim.areaRadiusNM = areaRadiusNM
        sim.areaCeilingFt = areaCeilingFt
            // The picker can set this during a view update; publish the status change on the next run-loop turn.
            DispatchQueue.main.async { [weak self] in self?.startWeather(spawnTraffic: false) }
        }
    }
    /// What the weather feed is doing, for the settings panel.
    @Published private(set) var weatherStatus = ""
    /// Short wind source for the info panel: "Live METAR KBOS", "Random drift", "Fixed"...
    @Published private(set) var windSource = "Random drift"
    /// When the next live observation is fetched (also the retry time after a failure); nil when there is no live feed.
    @Published private(set) var nextWeatherUpdate: Date?
    /// Short message after each weather fetch, shown for a few seconds at the top of the scope like the mode prompts.
    @Published private(set) var weatherNotice: String?
    private var noticeTask: Task<Void, Never>?
    /// The seed the traffic generator is using now.
    @Published private(set) var trafficSeed: UInt64 = 0
    @Published var isRunning = true {
        didSet { reschedule() }
    }
    /// Simulated seconds per real second.
    @Published var speed = 1 {
        didSet { reschedule() }
    }

    @Published private(set) var airport: AirportPackage?
    @Published private(set) var loadError: String?
    /// Fix identifiers of the current airport, for the command bar's direct-to-fix code.
    @Published private(set) var fixIds: Set<String> = []
    /// Approaches that `j ID` can join, by procedure ID.
    @Published private(set) var approachJoins: [String: ApproachJoin] = [:]
    /// The player's airspace (saved between runs): arrivals are handed in at its edge, departures handed off inside it.
    @Published var areaRadiusNM: Double = UserDefaults.standard.object(forKey: "areaRadiusNM") as? Double ?? 40 {
        didSet { UserDefaults.standard.set(areaRadiusNM, forKey: "areaRadiusNM"); sim.areaRadiusNM = areaRadiusNM }
    }
    @Published var areaCeilingFt: Int = UserDefaults.standard.object(forKey: "areaCeilingFt") as? Int ?? 15000 {
        didSet { UserDefaults.standard.set(areaCeilingFt, forKey: "areaCeilingFt"); sim.areaCeilingFt = areaCeilingFt }
    }
    /// Macros running now, by callsign.
    @Published private(set) var macroRuns: [String: MacroRun] = [:]
    /// The current airport's macros, saved to disk on every change.
    @Published var macros: [Macro] = [] {
        didSet { if let icao = airport?.icao, macros != oldValue { MacroStore.save(macros, icao: icao) } }
    }
    /// Names of the bundled airports, for the picker.
    let airportNames = AirportPackage.bundledNames()
    /// Index with city names, sorted by city, for the picker.
    let airportIndex = AirportIndex.loadBundled()
    private(set) var sim: Simulation
    private var timer: Timer?
    private let seed: UInt64
    private static let airportKey = "airportCode"
    private static let trafficKey = "trafficSettings"
    private static let eventsKey = "eventSettings"
    private static func loadEvents() -> EventSettings {
        if let data = UserDefaults.standard.data(forKey: eventsKey),
           let saved = try? JSONDecoder().decode(EventSettings.self, from: data) { return saved }
        return .gameDefault
    }
    private static let weatherKey = "weatherMode"
    private var weatherTask: Task<Void, Never>?

    private static func loadWeatherMode() -> WeatherMode {
        UserDefaults.standard.string(forKey: weatherKey).flatMap(WeatherMode.init(rawValue:)) ?? .live
    }

    private static func loadTraffic() -> TrafficSettings {
        if let data = UserDefaults.standard.data(forKey: trafficKey),
           let saved = try? JSONDecoder().decode(TrafficSettings.self, from: data) { return saved }
        return TrafficSettings(enabled: true, arrivalsPerHour: 15)
    }

    private static func saveTraffic(_ settings: TrafficSettings) {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: trafficKey) }
    }

    /// Opens (or closes) the log file for the current simulation and routes entries to it.
    private func configureDebugLog() {
        sim.debugEnabled = debugLogging
        if debugLogging {
            debugFile.open(airport: airport?.icao ?? "none")
            debugFilePath = debugFile.url?.path ?? ""
            let file = debugFile
            sim.debugSink = { entry in file.write(entry) }
            sim.debugNote("session", "airport \(airport?.icao ?? "none"), seed \(seed), traffic seed \(trafficSeed), wind \(sim.wind.text)")
        } else {
            sim.debugSink = nil
            debugFile.close()
            debugFilePath = ""
            debugEntries = []
        }
    }

    func clearDebugLog() {
        sim.clearDebugLog()
        debugEntries = []
    }

    private func chooseTrafficSeed() {
        trafficSeed = traffic.fixedSeed ?? UInt64.random(in: 1...UInt64.max)
        sim.reseedTraffic(trafficSeed)
    }

    init(seed: UInt64) {
        self.seed = seed
        sim = Simulation(seed: seed)
        let saved = UserDefaults.standard.string(forKey: Self.airportKey) ?? "kbos"
        // Boston if it is bundled, otherwise the first airport there is.
        let fallback = airportNames.contains("kbos") ? "kbos" : (airportNames.first ?? "kbos")
        loadAirport(airportNames.contains(saved) ? saved : fallback)
        reschedule()
    }

    /// Starts a fresh simulation at the named bundled airport. The old traffic and radio log are discarded.
    func loadAirport(_ name: String) {
        var loaded: AirportPackage?
        loadError = nil
        do {
            loaded = try AirportPackage.loadBundled(name)
        } catch {
            loadError = "\(error)"
        }
        airport = loaded
        fixIds = Set((loaded?.fixes ?? []).map(\.id))
        approachJoins = loaded?.approachJoins ?? [:]
        macros = loaded.map { MacroStore.load(icao: $0.icao) } ?? []
        sim = Simulation(seed: seed, transitionAltitudeFt: loaded?.transitionAltitudeFt ?? 5000, airport: loaded)
        sim.weatherMode = weatherMode
        selectedCallsign = nil
        if loaded != nil { UserDefaults.standard.set(name, forKey: Self.airportKey) }
        chooseTrafficSeed()
        sim.traffic = traffic
        sim.events = events
        if debugLogging { configureDebugLog() }
        startWeather(spawnTraffic: true)
        publish()
    }

    private func notifyWeather(_ text: String) {
        weatherNotice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.weatherNotice = nil
        }
    }

    /// Starts (or stops) the live weather feed for the current simulation. With `spawnTraffic` the start-up traffic is
    /// placed once the first observation is in, or at once if live weather is off or cannot be had.
    private func startWeather(spawnTraffic: Bool) {
        weatherTask?.cancel()
        weatherTask = nil
        let current = sim
        guard weatherMode == .live, let icao = airport?.icao else {
            weatherStatus = weatherMode == .fixed ? "Wind fixed" : "Wind drifts randomly"
            windSource = weatherMode == .fixed ? "Fixed" : "Random drift"
            nextWeatherUpdate = nil
            if spawnTraffic { spawnDemoTraffic() }
            return
        }
        weatherStatus = "Fetching METAR for \(icao)…"
        windSource = "Live, fetching…"
        nextWeatherUpdate = nil
        weatherTask = Task { [weak self] in
            var first = true
            while !Task.isCancelled {
                let report = await WeatherService.fetch(icao: icao)
                guard let self, !Task.isCancelled, self.sim === current else { return }
                if let report {
                    current.setLiveWeather(report, immediately: first && spawnTraffic)
                    self.weatherStatus = "Live: " + (report.raw.isEmpty ? report.icao : report.raw)
                    self.windSource = "Real, METAR \(icao)"
                    let wind = Wind(fromDeg: report.fromDeg ?? current.wind.fromDeg, speedKt: report.speedKt, gustKt: report.gustKt)
                    self.notifyWeather("Weather updated, \(icao): wind " + (wind.text == "calm" ? "calm" : wind.text + " kt"))
                } else {
                    self.weatherStatus = "METAR unavailable, wind drifts randomly"
                    self.windSource = "Random, METAR failed"
                    self.notifyWeather("Weather update failed for \(icao), wind drifts randomly")
                }
                if first && spawnTraffic { self.spawnDemoTraffic() }
                first = false
                self.nextWeatherUpdate = Date().addingTimeInterval(15 * 60)
                self.publish()
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
            }
        }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard isRunning else { return }
        let interval = 1.0 / Double(max(speed, 1))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    func setMarker(_ index: Int?, for callsign: String) {
        if let index { markerColours[callsign] = index } else { markerColours[callsign] = nil }
    }

    func cycleMarker(for callsign: String) {
        setMarker(AircraftMarkers.next(after: markerColours[callsign]), for: callsign)
    }

    func toggleProcedure(for callsign: String) {
        if shownProcedures.contains(callsign) { shownProcedures.remove(callsign) } else { shownProcedures.insert(callsign) }
    }

    private func pruneMarkers() {
        let present = Set(aircraft.map(\.callsign))
        if markerColours.keys.contains(where: { !present.contains($0) }) {
            markerColours = markerColours.filter { present.contains($0.key) }
        }
        if !shownProcedures.isSubset(of: present) { shownProcedures = shownProcedures.intersection(present) }
    }

    private func step() {
        sim.tick()
        publish()
    }

    private func publish() {
        tickCount = sim.tickCount
        aircraft = sim.aircraft
        pruneMarkers()
        radioLog = sim.radioLog
        conflicts = sim.conflicts
        lossCount = sim.lossOfSeparationCount
        wind = sim.wind
        commandHistory = sim.commandHistory
        runwayStatuses = sim.runwayStatuses
        macroRuns = sim.macroRuns
        runwayUses = sim.runwayUses()
        if debugLogging { debugEntries = Array(sim.debugLog.suffix(400)) }
        availableProcedures = Set((airport?.procedures ?? []).filter { sim.isAvailable($0) }.map(\.id))
    }

    /// Places a test aircraft and selects it.
    func spawnTest(_ spec: TestSpawn) {
        selectedCallsign = sim.spawnTest(spec)
        publish()
    }

    /// Deletes the selected aircraft (test spawner).
    func deleteSelected() {
        guard let callsign = selectedCallsign, sim.removeAircraft(callsign: callsign) else { return }
        selectedCallsign = nil
        publish()
    }

    func referencePoint(runway: String?) -> (east: Double, north: Double) {
        sim.referencePoint(runway: runway)
    }

    /// The airport's macros that suit this aircraft, by name.
    func macros(for ac: Aircraft) -> [Macro] {
        let phase = MacroPhase.of(ac)
        return macros.filter { $0.phase == phase }.sorted { $0.name < $1.name }
    }

    /// Compiles the named macro and starts it on the aircraft. Returns why it cannot run, or nil.
    @discardableResult
    func runMacro(named name: String, on callsign: String) -> String? {
        guard let macro = macros.first(where: { $0.name.uppercased() == name.uppercased() }) else {
            return "no macro called \(name.uppercased()) at this airport"
        }
        let result: String?
        switch MacroCompiler.compile(macro, knownFixes: fixIds, approaches: approachJoins) {
        case .success(let compiled): result = sim.assignMacro(compiled, to: callsign)
        case .failure(let error): result = "\(macro.name): \(error)"
        }
        publish()
        return result
    }

    @discardableResult
    func cancelMacro(on callsign: String) -> Bool {
        let cancelled = sim.cancelMacro(callsign: callsign)
        publish()
        return cancelled
    }

    func issue(_ issued: IssuedCommand) -> IssueResult {
        let result = sim.issue(issued)
        publish()
        return result
    }

    /// Start-up traffic: a random number of arrivals already flying STARs, at random points, with random types and
    /// callsigns that suit the airport's country. Repeats exactly when a fixed traffic seed is set.
    private func spawnDemoTraffic() {
        sim.placeStartTraffic()
    }
}
