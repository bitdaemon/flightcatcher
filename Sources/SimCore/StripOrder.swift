import Foundation

/// How the aircraft list is split and ordered: arrivals nearest the airport first, departures in the order they
/// will leave (rolling, lined up, holding in queue order, then airborne with the one furthest out first).
public enum StripOrder {
    static func distanceNM(_ ac: Aircraft) -> Double { (ac.eastNM * ac.eastNM + ac.northNM * ac.northNM).squareRoot() }

    public static func arrivals(_ list: [Aircraft]) -> [Aircraft] {
        list.filter { $0.departure == nil }.sorted {
            let a = distanceNM($0), b = distanceNM($1)
            return a != b ? a < b : $0.callsign < $1.callsign
        }
    }

    public static func departures(_ list: [Aircraft]) -> [Aircraft] {
        func rank(_ ac: Aircraft) -> Int {
            switch ac.groundPhase {
            case .takeoffRoll?: return 0
            case .linedUp?: return 1
            case .holdingShort?: return 2
            case nil: return 3
            }
        }
        let indexed = list.enumerated().filter { $0.element.departure != nil }
        return indexed.sorted { x, y in
            let rx = rank(x.element), ry = rank(y.element)
            if rx != ry { return rx < ry }
            if rx == 2 { return x.offset < y.offset }   // queue order: first to arrive at the hold first
            if rx == 3 {
                let a = distanceNM(x.element), b = distanceNM(y.element)
                if a != b { return a > b }
            }
            return x.element.callsign < y.element.callsign
        }.map(\.element)
    }
}
