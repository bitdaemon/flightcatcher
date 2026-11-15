import Foundation

/// Spoken forms for the radio log. Wording follows Doc 4444 chapter 12 (see phraseology-ifr.md).
/// Numbers follow SERA.14035 as applied in Ireland and the UK: digits one at a time, whole thousands and hundreds
/// as "thousand" and "hundred". All numbers come from code, never a model.
public enum Phraseology {
    public enum NumberStyle {
        /// zero, one, two, three, four, five, six, seven, eight, niner. The default.
        case plain
        /// ICAO pronunciation guide: tree, fower, fife, niner (also niner for nine).
        case icao
    }

    /// Global switch, set once at startup. Not touched while the simulation runs.
    public static var numberStyle: NumberStyle = .plain

    static var digitWords: [String] {
        switch numberStyle {
        case .plain: return ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
        case .icao: return ["zero", "one", "two", "tree", "fower", "fife", "six", "seven", "eight", "niner"]
        }
    }
    static let phonetic: [Character: String] = [
        "A": "Alfa", "B": "Bravo", "C": "Charlie", "D": "Delta", "E": "Echo", "F": "Foxtrot",
        "G": "Golf", "H": "Hotel", "I": "India", "J": "Juliett", "K": "Kilo", "L": "Lima",
        "M": "Mike", "N": "November", "O": "Oscar", "P": "Papa", "Q": "Quebec", "R": "Romeo",
        "S": "Sierra", "T": "Tango", "U": "Uniform", "V": "Victor", "W": "Whiskey",
        "X": "X-ray", "Y": "Yankee", "Z": "Zulu",
    ]

    public static func pad3(_ n: Int) -> String {
        let s = String(max(0, n))
        return String(repeating: "0", count: max(0, 3 - s.count)) + s
    }

    /// Each character on its own: digits as words, letters as the phonetic alphabet.
    public static func spokenDigits(_ text: String) -> String {
        text.compactMap { ch -> String? in
            if ch.isASCII, let d = ch.wholeNumberValue, d >= 0, d <= 9 { return digitWords[d] }
            guard let upper = ch.uppercased().first else { return nil }
            return phonetic[upper]
        }.joined(separator: " ")
    }

    /// "28L" becomes "two eight left".
    public static func spokenRunway(_ id: String) -> String {
        let digits = id.prefix(while: { $0.isNumber })
        let suffix = id.dropFirst(digits.count).uppercased()
        var words = spokenDigits(String(digits))
        switch suffix {
        case "L": words += " left"
        case "R": words += " right"
        case "C": words += " centre"
        default: break
        }
        return words
    }

    public static func spokenCallsign(_ aircraft: Aircraft) -> String {
        if let radio = aircraft.radioName {
            let number = aircraft.callsignNumber
            return number.isEmpty ? radio : "\(radio) \(spokenDigits(number))"
        }
        return spokenDigits(aircraft.callsign)
    }

    /// At or below the transition altitude: "two thousand five hundred feet".
    /// Above: "flight level seven zero", and whole hundreds as "flight level one hundred".
    public static func spokenLevel(feet: Int, transitionAltitudeFt: Int) -> String {
        if feet > transitionAltitudeFt {
            let level = feet / 100
            if level % 100 == 0 { return "flight level " + spokenDigits(String(level / 100)) + " hundred" }
            return "flight level " + spokenDigits(String(level))
        }
        let thousands = feet / 1000
        let hundreds = (feet % 1000) / 100
        var parts: [String] = []
        if thousands > 0 { parts.append(spokenDigits(String(thousands)) + " thousand") }
        if hundreds > 0 { parts.append(spokenDigits(String(hundreds)) + " hundred") }
        if parts.isEmpty { parts.append("zero") }
        return parts.joined(separator: " ") + " feet"
    }

    /// The instruction without a callsign, for example "descend to flight level seven zero".
    public static func instruction(_ command: Command, for aircraft: Aircraft, transitionAltitudeFt: Int) -> String {
        switch command {
        case .descend(let feet):
            return "descend to " + spokenLevel(feet: feet, transitionAltitudeFt: transitionAltitudeFt)
        case .climb(let feet):
            return "climb to " + spokenLevel(feet: feet, transitionAltitudeFt: transitionAltitudeFt)
        case .heading(let degrees, let turn):
            let lead = turn.map { "turn \($0.rawValue) heading " } ?? "fly heading "
            return lead + spokenDigits(pad3(degrees))
        case .approach(let runway):
            return "cleared ILS approach runway " + spokenRunway(runway)
        case .visualApproach(let runway):
            return "cleared visual approach runway " + spokenRunway(runway)
        case .expedite(let inner):
            switch inner {
            case .descend(let feet):
                return "expedite descent to " + spokenLevel(feet: feet, transitionAltitudeFt: transitionAltitudeFt)
            case .climb(let feet):
                return "expedite climb to " + spokenLevel(feet: feet, transitionAltitudeFt: transitionAltitudeFt)
            case .heading(let degrees, let turn):
                let lead = turn.map { "turn \($0.rawValue) immediately heading " } ?? "turn immediately heading "
                return lead + spokenDigits(pad3(degrees))
            case .speed(let knots):
                let words = spokenDigits(String(knots))
                return (Double(knots) < aircraft.speedKt ? "reduce" : "increase") + " speed immediately to \(words) knots"
            default:
                return instruction(inner, for: aircraft, transitionAltitudeFt: transitionAltitudeFt)
            }
        case .direct(let fix):
            return "proceed direct " + fix.uppercased()
        case .cross(let fix, let feet):
            return "cross \(fix.uppercased()) at " + spokenLevel(feet: feet, transitionAltitudeFt: transitionAltitudeFt)
        case .route(let fixes):
            return "proceed direct " + fixes.map { $0.uppercased() }.joined(separator: ", then ")
        case .joinApproach(let procedure, let runway, let via):
            return "proceed direct \(via.uppercased()), cleared \(ApproachType(procedureId: procedure).spoken) approach runway "
                + spokenRunway(runway)
        case .maintain:
            return "maintain present heading, altitude and speed"
        case .lineUp:
            return "line up and wait runway " + spokenRunway(aircraft.departure?.runway ?? "")
        case .takeoff:
            let clearance = "runway \(spokenRunway(aircraft.departure?.runway ?? "")), cleared for take-off"
            // The departure instruction goes with the take-off clearance. With a SID the aircraft follows its track
            // but SID altitude restrictions are not modelled, so "climb and maintain" (which cancels them), not
            // "climb via SID". Change to "climb via SID except maintain" once the restrictions are flown.
            guard let d = aircraft.departure else { return clearance }
            let level = spokenLevel(feet: d.initialAltitudeFt, transitionAltitudeFt: transitionAltitudeFt)
            if d.sid.isEmpty {
                return "fly runway heading, climb to \(level), " + clearance
            }
            return "\(spokenProcedure(d.sid)) departure, climb and maintain \(level), " + clearance
        case .handoff:
            return aircraft.departure == nil ? "contact tower" : "contact area control, good day"
        case .speed(let knots):
            let words = spokenDigits(String(knots))
            let delta = Double(knots) - aircraft.speedKt
            if abs(delta) < 0.5 { return "maintain \(words) knots" }
            return (delta < 0 ? "reduce" : "increase") + " speed to \(words) knots"
        }
    }

    /// "wind two six zero degrees one two knots", or "wind calm".
    public static func spokenWind(_ wind: Wind) -> String {
        guard wind.speedKt >= 0.5 else { return "wind calm" }
        let rounded = Int(wind.fromDeg.rounded()) % 360
        return "wind \(spokenDigits(pad3(rounded == 0 ? 360 : rounded))) degrees \(spokenDigits(String(Int(wind.speedKt.rounded())))) knots"
    }

    /// Take-off clearance with the wind first, as Doc 4444 has it.
    public static func takeoffCall(for aircraft: Aircraft, wind: Wind, transitionAltitudeFt: Int = 18000) -> String {
        "\(spokenCallsign(aircraft)), \(spokenWind(wind)), "
            + instruction(.takeoff, for: aircraft, transitionAltitudeFt: transitionAltitudeFt)
    }

    /// "BOFUM1A" becomes "BOFUM one Alfa"; anything after a dot (the runway transition) is dropped.
    public static func spokenProcedure(_ id: String) -> String {
        let base = String(id.split(separator: ".").first ?? Substring(id))
        let name = base.prefix(while: { $0.isLetter })
        let rest = base.dropFirst(name.count)
        let digits = rest.prefix(while: { $0.isNumber })
        let suffix = rest.dropFirst(digits.count)
        return [String(name), spokenDigits(String(digits)), spokenDigits(String(suffix))].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Departure pilot's first call: "Departure, American one two three, passing one thousand five hundred feet,
    /// climbing three thousand feet, BOFUM one Alfa departure".
    /// First call from an arrival handed over by the centre: "Boston Approach, Speedbird one two three, flight level one one zero".
    public static func approachCheckIn(for aircraft: Aircraft, facility: String, altitudeFt: Int,
                                       transitionAltitudeFt: Int) -> String {
        "\(facility), \(spokenCallsign(aircraft)), \(spokenLevel(feet: altitudeFt, transitionAltitudeFt: transitionAltitudeFt))"
    }

    public static func departureCheckIn(for aircraft: Aircraft, passingFt: Int, climbingToFt: Int, sid: String,
                                        transitionAltitudeFt: Int) -> String {
        "Departure, \(spokenCallsign(aircraft)), passing \(spokenLevel(feet: passingFt, transitionAltitudeFt: transitionAltitudeFt)), "
        + "climbing \(spokenLevel(feet: climbingToFt, transitionAltitudeFt: transitionAltitudeFt)), "
        + (sid.isEmpty ? "runway heading" : "\(spokenProcedure(sid)) departure")
    }

    /// Pilot call when a route runs out with no approach clearance, for example
    /// "Overhead KERAV, maintaining heading two seven zero, American one two three".
    public static func routeEnded(fix: String, headingDeg: Int, for aircraft: Aircraft) -> String {
        "Overhead \(fix.uppercased()), maintaining heading \(spokenDigits(pad3(headingDeg))), \(spokenCallsign(aircraft))"
    }

    public static func crossingUnable(fix: String, altitudeFt: Int, for aircraft: Aircraft, transitionAltitudeFt: Int) -> String {
        "Unable to cross \(fix.uppercased()) at \(spokenLevel(feet: altitudeFt, transitionAltitudeFt: transitionAltitudeFt)), \(spokenCallsign(aircraft))"
    }

    public static func controllerCall(_ command: Command, for aircraft: Aircraft, transitionAltitudeFt: Int) -> String {
        "\(spokenCallsign(aircraft)), " + instruction(command, for: aircraft, transitionAltitudeFt: transitionAltitudeFt)
    }

    public static func readback(_ command: Command, for aircraft: Aircraft, transitionAltitudeFt: Int) -> String {
        let text = instruction(command, for: aircraft, transitionAltitudeFt: transitionAltitudeFt)
        return text.prefix(1).uppercased() + text.dropFirst() + ", " + spokenCallsign(aircraft)
    }
}
