import Foundation
import SimCore

/// One finished session in the best-scores table.
struct ScoreRecord: Codable, Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var total: Int
    var grade: String
    var minutes: Int
    var multiplier: Double
    var arrivals: Int
    var departures: Int
    var losses: Int
    /// Traffic seed of the session, and whether it was fixed (so the session can be replayed).
    var seed: UInt64
    var fixedSeed: Bool
    /// "ARR 12–24/h DEP 8/h, Moderate".
    var traffic: String
}

/// Best scores per airport, best first, at most ten each. Kept in UserDefaults.
enum ScoreHistory {
    private static let key = "bestScores"
    static let keep = 10

    private static func all() -> [String: [ScoreRecord]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let table = try? JSONDecoder().decode([String: [ScoreRecord]].self, from: data) else { return [:] }
        return table
    }

    static func load(icao: String) -> [ScoreRecord] { all()[icao.uppercased()] ?? [] }

    /// Adds a record and returns its place in the table (1 is best), or nil if it did not make the top ten.
    @discardableResult
    static func add(_ record: ScoreRecord, icao: String) -> Int? {
        var table = all()
        var list = table[icao.uppercased()] ?? []
        list.append(record)
        list.sort { $0.total > $1.total }
        list = Array(list.prefix(keep))
        table[icao.uppercased()] = list
        if let data = try? JSONEncoder().encode(table) { UserDefaults.standard.set(data, forKey: key) }
        return list.firstIndex(of: record).map { $0 + 1 }
    }

    static func trafficSummary(_ t: TrafficSettings) -> String {
        func range(_ r: ClosedRange<Double>) -> String {
            r.lowerBound == r.upperBound ? "\(Int(r.lowerBound))" : "\(Int(r.lowerBound))\u{2013}\(Int(r.upperBound))"
        }
        let base = "ARR \(range(t.arrivalRange))/h DEP \(range(t.departureRange))/h"
        return t.isVariable ? base + ", \(t.variation.title)" : base
    }
}
