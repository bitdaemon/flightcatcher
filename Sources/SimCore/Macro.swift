import Foundation

/// Which aircraft a macro is meant for. The ring only offers macros that match the aircraft.
public enum MacroPhase: String, Codable, CaseIterable, Equatable {
    case arrival, departure, ground

    public static func of(_ ac: Aircraft) -> MacroPhase {
        if ac.isOnGround { return .ground }
        return ac.departure == nil ? .arrival : .departure
    }

    public var label: String {
        switch self {
        case .arrival: return "Arrival"
        case .departure: return "Departure"
        case .ground: return "Ground"
        }
    }
}

/// A macro as the player writes it and as it is saved (JSON per airport). `text` holds the steps, one per line
/// (a ";" also ends a step). It is compiled against the airport's fixes before it can run.
///
/// Step syntax: `[trigger:] codes`, codes as on the command bar, separated by spaces or commas.
///   s210
///   at CAPE: d30, s180
///   when alt<4000: i4r
///   when spd<=180: h270l
/// Triggers: `at FIX` (passing the fix), `when alt` or `when spd` with <, <=, > or >=. The colon is optional.
/// Altitudes in triggers are feet; a number below 1000 is read as hundreds, like the codes (alt<40 = 4000 ft).
public struct Macro: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var phase: MacroPhase
    public var text: String

    public init(id: UUID = UUID(), name: String, phase: MacroPhase, text: String) {
        self.id = id
        self.name = name
        self.phase = phase
        self.text = text
    }
}

public enum MacroComparison: String, Equatable, CaseIterable {
    case lessOrEqual = "<=", greaterOrEqual = ">=", less = "<", greater = ">"

    func holds(_ value: Double, _ limit: Int) -> Bool {
        let l = Double(limit)
        switch self {
        case .less: return value < l
        case .lessOrEqual: return value <= l
        case .greater: return value > l
        case .greaterOrEqual: return value >= l
        }
    }
}

public enum MacroTrigger: Equatable {
    case atFix(String)
    case altitude(MacroComparison, Int)
    case speed(MacroComparison, Int)

    /// Short form for the track tag: "@CAPE", "A<4000", "S<=180".
    public var tagLabel: String {
        switch self {
        case .atFix(let fix): return "@\(fix)"
        case .altitude(let c, let v): return "A\(c.rawValue)\(v)"
        case .speed(let c, let v): return "S\(c.rawValue)\(v)"
        }
    }
}

public struct MacroStep: Equatable {
    public var trigger: MacroTrigger?
    /// Sent together as one transmission when the trigger fires.
    public var commands: [Command]
}

public struct CompiledMacro: Equatable {
    public var name: String
    public var phase: MacroPhase
    public var steps: [MacroStep]
}

/// A parse error with a message for the player.
public struct ParseFailure: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public struct MacroError: Error, Equatable, CustomStringConvertible {
    /// 1-based step number, or 0 for the macro as a whole (name, empty body).
    public var step: Int
    public var message: String
    public var description: String { step == 0 ? message : "step \(step): \(message)" }
}

public enum MacroCompiler {
    /// Macro names: letters, digits, - and _, up to 12 characters, so they fit in a track tag and on the command bar.
    public static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 12 && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// The step lines of a macro body: split on new lines and ";", blank lines and `#` comments dropped.
    static func stepLines(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    public static func compile(_ macro: Macro, knownFixes: Set<String>,
                               approaches: [String: ApproachJoin] = [:]) -> Result<CompiledMacro, MacroError> {
        if !validName(macro.name) {
            return .failure(MacroError(step: 0, message: "name must be 1 to 12 letters, digits, - or _"))
        }
        let lines = stepLines(macro.text)
        if lines.isEmpty { return .failure(MacroError(step: 0, message: "the macro has no steps")) }
        var steps: [MacroStep] = []
        for (index, line) in lines.enumerated() {
            let n = index + 1
            var trigger: MacroTrigger?
            var body = Substring(line)
            if let colon = line.firstIndex(of: ":") {
                switch parseTrigger(String(line[..<colon]), knownFixes: knownFixes) {
                case .success(let t): trigger = t
                case .failure(let f): return .failure(MacroError(step: n, message: f.message))
                }
                body = line[line.index(after: colon)...]
            } else if let first = line.split(separator: " ").first?.lowercased(), first == "at" || first == "when" {
                // The colon is optional: "at CAPE d30 s180", "when alt<4000 i4r", "when alt < 4000 i4r".
                let words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                var found: (MacroTrigger, Int)?
                var lastError = "write a trigger as: at FIX, or when alt<4000"
                for count in stride(from: min(4, words.count), through: 2, by: -1) {
                    switch parseTrigger(words.prefix(count).joined(separator: " "), knownFixes: knownFixes) {
                    case .success(let t): found = (t, count)
                    case .failure(let f): lastError = f.message
                    }
                    if found != nil { break }
                }
                guard let hit = found else { return .failure(MacroError(step: n, message: lastError)) }
                trigger = hit.0
                body = Substring(words.dropFirst(hit.1).joined(separator: " "))
            }
            let commands: [Command]
            switch CommandBar.parseChain(String(body), knownFixes: knownFixes, approaches: approaches) {
            case .success(let c): commands = c
            case .failure(let f): return .failure(MacroError(step: n, message: f.message))
            }
            if commands.isEmpty {
                return .failure(MacroError(step: n, message: trigger == nil ? "no instruction"
                    : "add the instruction to send after the trigger, for example: \(lines[index]) s180"))
            }
            for command in commands {
                if let reason = phaseProblem(command, macro.phase) {
                    return .failure(MacroError(step: n, message: reason))
                }
            }
            steps.append(MacroStep(trigger: trigger, commands: commands))
        }
        return .success(CompiledMacro(name: macro.name, phase: macro.phase, steps: steps))
    }

    static func parseTrigger(_ raw: String, knownFixes: Set<String>) -> Result<MacroTrigger, ParseFailure> {
        let words = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = words.first?.lowercased() else { return .failure(ParseFailure("empty trigger before ':'")) }
        if first == "at" {
            guard words.count == 2 else { return .failure(ParseFailure("write the trigger as: at FIX")) }
            let fix = words[1].uppercased()
            guard knownFixes.contains(fix) else { return .failure(ParseFailure("fix \(fix) is not on this airport's map")) }
            return .success(.atFix(fix))
        }
        if first == "when" {
            let expression = words.dropFirst().joined().lowercased() // "alt < 4000" and "alt<4000" both work
            for (prefix, isAltitude) in [("alt", true), ("spd", false)] where expression.hasPrefix(prefix) {
                let rest = expression.dropFirst(prefix.count)
                guard let comparison = MacroComparison.allCases.first(where: { rest.hasPrefix($0.rawValue) }) else {
                    return .failure(ParseFailure("use <, <=, > or >= after \(prefix)"))
                }
                let number = rest.dropFirst(comparison.rawValue.count)
                guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(number) else {
                    return .failure(ParseFailure("bad number in '\(raw.trimmingCharacters(in: .whitespaces))'"))
                }
                if isAltitude { return .success(.altitude(comparison, value < 1000 ? value * 100 : value)) }
                return .success(.speed(comparison, value))
            }
            return .failure(ParseFailure("after 'when' use alt or spd, for example when alt<4000"))
        }
        return .failure(ParseFailure("a trigger starts with 'at' or 'when'"))
    }

    /// Instructions that can never be accepted by an aircraft of this phase.
    static func phaseProblem(_ command: Command, _ phase: MacroPhase) -> String? {
        switch (phase, command) {
        case (.ground, .lineUp), (.ground, .takeoff): return nil
        case (.ground, _): return "a ground macro can only use lu and to"
        case (_, .lineUp), (_, .takeoff): return "lu and to are for ground macros"
        case (.departure, .approach), (.departure, .visualApproach), (.departure, .joinApproach):
            return "a departure macro cannot clear an approach"
        default: return nil
        }
    }
}

/// A macro running on one aircraft. One per aircraft; a new one replaces it.
public struct MacroRun: Equatable {
    public let macro: CompiledMacro
    /// Index of the next step to send.
    public internal(set) var stepIndex: Int = 0
    /// Tick at which the current step started waiting, for the timeout.
    public internal(set) var stepStartTick: Int
    /// Route fix the aircraft was flying to on the previous tick, to notice it passing an `at FIX` trigger.
    var lastTarget: String?

    public var nextStep: MacroStep? { macro.steps.indices.contains(stepIndex) ? macro.steps[stepIndex] : nil }

    /// Track tag line: "M APPR 2/4 @CAPE".
    public var tagText: String {
        var text = "M \(macro.name) \(min(stepIndex + 1, macro.steps.count))/\(macro.steps.count)"
        if let trigger = nextStep?.trigger { text += " " + trigger.tagLabel }
        return text
    }
}
