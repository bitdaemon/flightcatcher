import Foundation

public struct IssuedCommand: Equatable {
    public var callsign: String
    public var command: Command
    public init(callsign: String, command: Command) {
        self.callsign = callsign
        self.command = command
    }
}

public struct CommandBarResult: Equatable {
    public enum Status: Equatable { case empty, incomplete, ready, error }
    public var status: Status
    public var message: String
    /// First command of the line (kept for single-command callers).
    public var issued: IssuedCommand?
    /// Every command on the line, in order. Chains like `ein d70 s180 h270` produce several.
    public var issuedAll: [IssuedCommand]
    /// Set when the input is just a fragment that resolves to one aircraft: Enter selects it.
    public var selects: String?
    /// Set for `mac NAME` (run a macro) and `mac-` (cancel the aircraft's macro).
    public var macro: MacroRequest?

    public init(status: Status, message: String, issued: IssuedCommand? = nil,
                issuedAll: [IssuedCommand]? = nil, selects: String? = nil, macro: MacroRequest? = nil) {
        self.macro = macro
        self.status = status
        self.message = message
        self.issued = issued
        self.issuedAll = issuedAll ?? (issued.map { [$0] } ?? [])
        self.selects = selects
    }
}

/// What `j ID` needs to know about an approach procedure: its runway and first fix.
public struct ApproachJoin: Equatable {
    public var procedure: String
    public var runway: String
    public var via: String
    public init(procedure: String, runway: String, via: String) {
        self.procedure = procedure; self.runway = runway; self.via = via
    }
}

extension AirportPackage {
    /// Approach procedures that can be joined with `j ID`, by procedure ID ("I04R", "I27.AYBEE").
    public var approachJoins: [String: ApproachJoin] {
        var table: [String: ApproachJoin] = [:]
        for p in procedures where p.kind == .approach {
            guard let runway = p.runways.first, let via = p.legs.first?.fixId else { continue }
            table[p.id.uppercased()] = ApproachJoin(procedure: p.id, runway: runway, via: via)
        }
        return table
    }
}

/// A macro request typed on the command bar. The app checks the name against the airport's macros.
public enum MacroRequest: Equatable {
    case run(callsign: String, name: String)
    case cancel(callsign: String)
}

/// State for cycling through Tab completions. Pure data so the behaviour can be unit tested.
public struct TabState: Equatable {
    public var matches: [String] = []
    public var index = 0
    public var suffix = ""
    public var lastOutput: String?
    public init() {}
}

/// Command-bar logic: parse "[callsign fragment] code+number", resolve the aircraft, validate, preview.
/// Examples: `ein d70`, `ryr h270l` (turn left), `s180` when an aircraft is already selected,
/// or a chain such as `ein d70 s180 h270l`.
public enum CommandBar {
    static let codeLetters: Set<Character> = ["d", "c", "h", "s", "i", "p", "x"]

    /// A lone token such as "d70" or "h270l": a code letter, at least one digit, and for h an optional l or r.
    /// Words that are commands on their own: maintain present state, line up and wait, cleared for take-off, hand off.
    static let wordCommands: [String: Command] = ["lu": .lineUp, "to": .takeoff, "ho": .handoff, "m": .maintain]

    static func isCode(_ rawToken: String, knownFixes: Set<String> = [], approaches: [String: ApproachJoin] = [:]) -> Bool {
        if ["mac", "mac-"].contains(rawToken.lowercased()) { return true }
        if rawToken.count > 1, rawToken.lowercased().hasPrefix("j") {
            return approaches[String(rawToken.dropFirst()).uppercased()] != nil
        }
        if wordCommands[rawToken.lowercased()] != nil { return true }
        var token = rawToken
        if token.hasSuffix("!") { token.removeLast() } // "d50!" is an expedited descent
        guard let first = token.lowercased().first, codeLetters.contains(first) else { return false }
        if first == "x" {
            guard let fix = token.dropFirst().uppercased().split(separator: "@", omittingEmptySubsequences: false).first else { return false }
            return knownFixes.contains(String(fix))
        }
        if first == "p" {
            let fixes = token.dropFirst().uppercased().split(separator: ",")
            return !fixes.isEmpty && fixes.allSatisfy { knownFixes.contains(String($0)) }
        }
        if first == "i" { return parseRunway(token.dropFirst()) != nil }
        var rest = Substring(token.dropFirst())
        if first == "h", let last = rest.last, "lrLR".contains(last) { rest = rest.dropLast() }
        return !rest.isEmpty && rest.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // MARK: Matching

    /// Aircraft matching a fragment of the callsign or radio name, best match first.
    public static func rankedMatches(_ fragment: String, in aircraft: [Aircraft]) -> [Aircraft] {
        let f = fragment.lowercased()
        guard !f.isEmpty else { return [] }
        var scored: [(Int, Aircraft)] = []
        for ac in aircraft {
            let callsign = ac.callsign.lowercased()
            var rank: Int?
            if callsign.hasPrefix(f) {
                rank = 0
            } else if let radio = ac.radioName?.lowercased(), (radio + ac.callsignNumber.lowercased()).hasPrefix(f) {
                rank = 1
            } else if callsign.contains(f) {
                rank = 2
            }
            if let rank { scored.append((rank, ac)) }
        }
        return scored.sorted { ($0.0, $0.1.callsign) < ($1.0, $1.1.callsign) }.map { $0.1 }
    }

    // MARK: Evaluate

    /// Splits a line into tokens, folding "x kerav 50" into "xKERAV@50" and "p kerav pizsa" into "pKERAV,PIZSA".
    static func tokenize(_ input: String, knownFixes: Set<String>) -> [String] {
        var tokens: [String] = []
        let raw = input.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var index = 0
        while index < raw.count {
            // "x kerav 50" or "xkerav 50": cross KERAV at 5000 ft.
            let word = raw[index].lowercased()
            var crossFix: String?
            var after = index + 1
            if word == "x", index + 1 < raw.count, knownFixes.contains(raw[index + 1].uppercased()) {
                crossFix = raw[index + 1].uppercased(); after = index + 2
            } else if word.count > 1, word.hasPrefix("x"), knownFixes.contains(String(raw[index].dropFirst()).uppercased()) {
                crossFix = String(raw[index].dropFirst()).uppercased()
            }
            // "j i27.aybee" is the same as "ji27.aybee": join that approach.
            if word == "j" {
                tokens.append(index + 1 < raw.count ? "j" + raw[index + 1] : "j")
                index += 2
                continue
            }
            if let crossFix {
                if after < raw.count, Int(raw[after]) != nil {
                    tokens.append("x\(crossFix)@\(raw[after])"); index = after + 1
                } else {
                    tokens.append("x\(crossFix)@"); index = after
                }
                continue
            }
            // "p kerav" is the same as "pkerav" when the next word is a known fix.
            // Known fixes that follow are further legs of the same route: "p kerav pizsa lamba".
            var start = -1
            if raw[index].lowercased() == "p", index + 1 < raw.count, knownFixes.contains(raw[index + 1].uppercased()) {
                start = index + 1
            } else if raw[index].count > 1, raw[index].lowercased().hasPrefix("p"),
                      knownFixes.contains(raw[index].dropFirst().uppercased()) {
                start = index
            }
            if start >= 0 {
                var fixes = [raw[start].uppercased()]
                if start == index { fixes = [String(raw[index].dropFirst()).uppercased()] }
                var next = (start == index) ? index + 1 : index + 2
                while next < raw.count {
                    let word = raw[next].uppercased()
                    if knownFixes.contains(word) { fixes.append(word); next += 1 }
                    else if word.count > 1, word.hasPrefix("P"), knownFixes.contains(String(word.dropFirst())) {
                        fixes.append(String(word.dropFirst())); next += 1
                    } else { break }
                }
                tokens.append("p" + fixes.joined(separator: ","))
                index = next
            } else {
                tokens.append(raw[index]); index += 1
            }
        }
        return tokens
    }

    /// Parses a chain of codes with no callsign, such as "d30 s180" or "d30, s180" (macro steps).
    /// Checks syntax and fixes only; whether an aircraft can accept the commands is decided when they are sent.
    public static func parseChain(_ text: String, knownFixes: Set<String>, approaches: [String: ApproachJoin] = [:]) -> Result<[Command], ParseFailure> {
        let tokens = tokenize(text.replacingOccurrences(of: ",", with: " "), knownFixes: knownFixes)
        var commands: [Command] = []
        for token in tokens {
            if ["mac", "mac-"].contains(token.lowercased()) { return .failure(ParseFailure("a macro cannot start another macro")) }
            switch parseCode(token, knownFixes: knownFixes, approaches: approaches) {
            case .command(let command): commands.append(command)
            case .incomplete(let message): return .failure(ParseFailure(message))
            case .error(let message): return .failure(ParseFailure(message))
            }
        }
        return .success(commands)
    }

    public static func evaluate(input: String, aircraft: [Aircraft], selected: String?,
                                knownFixes: Set<String> = [], approaches: [String: ApproachJoin] = [:]) -> CommandBarResult {
        let tokens = tokenize(input, knownFixes: knownFixes)
        if tokens.isEmpty { return CommandBarResult(status: .empty, message: "") }

        // First token is a callsign fragment unless it is itself a code; the rest are chained codes.
        let fragment: String? = isCode(tokens[0], knownFixes: knownFixes, approaches: approaches) ? nil : tokens[0]
        let codeTokens = Array(fragment == nil ? tokens[...] : tokens.dropFirst())

        // Resolve the aircraft. Enter never guesses on an ambiguous fragment.
        let target: Aircraft
        if let fragment {
            let matches = rankedMatches(fragment, in: aircraft)
            if matches.isEmpty {
                return CommandBarResult(status: .error, message: "No aircraft matches '\(fragment)'")
            }
            if let exact = matches.first(where: { $0.callsign.lowercased() == fragment.lowercased() }) {
                target = exact
            } else if matches.count > 1 {
                let names = matches.prefix(6).map(\.callsign).joined(separator: ", ")
                return CommandBarResult(status: .incomplete, message: "Ambiguous: \(names). Tab to complete")
            } else {
                target = matches[0]
            }
        } else if let selected, let ac = aircraft.first(where: { $0.callsign == selected }) {
            target = ac
        } else {
            return CommandBarResult(status: .error, message: "No aircraft selected. Type a callsign first")
        }

        if codeTokens.isEmpty {
            return CommandBarResult(status: .incomplete,
                                    message: "\(target.callsign): Enter to select, or add d, c, h or s with a number",
                                    selects: target.callsign)
        }

        if codeTokens[0].lowercased() == "mac-" {
            return CommandBarResult(status: .ready, message: "\(target.callsign): cancel macro. Enter to send",
                                    macro: .cancel(callsign: target.callsign))
        }
        if codeTokens[0].lowercased() == "mac" {
            guard codeTokens.count >= 2 else {
                return CommandBarResult(status: .incomplete, message: "\(target.callsign): type a macro name after mac")
            }
            if codeTokens.count > 2 {
                return CommandBarResult(status: .error, message: "mac takes one macro name and nothing after it")
            }
            let name = codeTokens[1].uppercased()
            return CommandBarResult(status: .ready, message: "\(target.callsign): run macro \(name). Enter to send",
                                    macro: .run(callsign: target.callsign, name: name))
        }

        var commands: [Command] = []
        for token in codeTokens {
            switch parseCode(token, knownFixes: knownFixes, approaches: approaches) {
            case .command(let command):
                if let reason = command.refusal(for: target) {
                    return CommandBarResult(status: .error, message: "\(target.callsign): unable, \(reason)")
                }
                commands.append(command)
            case .incomplete(let message):
                return CommandBarResult(status: .incomplete, message: "\(target.callsign): \(message)")
            case .error(let message):
                return CommandBarResult(status: .error, message: message)
            }
        }

        let all = commands.map { IssuedCommand(callsign: target.callsign, command: $0) }
        let summary = commands.map(\.summary).joined(separator: ", then ")
        return CommandBarResult(status: .ready,
                                message: "\(target.callsign): \(summary). Enter to send",
                                issued: all[0],
                                issuedAll: all)
    }

    private enum CodeParse {
        case command(Command)
        case incomplete(String)
        case error(String)
    }

    /// "28l" becomes "28L", "9" becomes "09". Two digits at most, optional l, r or c.
    static func parseRunway(_ text: Substring) -> String? {
        var digits = text
        var suffix = ""
        if let last = digits.last, "lrcLRC".contains(last) {
            suffix = last.uppercased()
            digits = digits.dropLast()
        }
        guard (1...2).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(digits), (1...36).contains(number) else { return nil }
        return (number < 10 ? "0" : "") + String(number) + suffix
    }

    /// One code token such as "d70", "s180", "h270l" or "i28l".
    /// A trailing "!" expedites a heading, altitude or speed code: "d50!", "h270l!", "s180!".
    private static func parseCode(_ token: String, knownFixes: Set<String>, approaches: [String: ApproachJoin] = [:]) -> CodeParse {
        guard token.hasSuffix("!") else { return parseCodeCore(token, knownFixes: knownFixes, approaches: approaches) }
        switch parseCodeCore(String(token.dropLast()), knownFixes: knownFixes, approaches: approaches) {
        case .command(let command):
            switch command {
            case .descend, .climb, .heading, .speed: return .command(.expedite(command))
            default: return .error("Only heading, altitude and speed can be expedited")
            }
        case let other:
            return other
        }
    }

    private static func parseCodeCore(_ token: String, knownFixes: Set<String>, approaches: [String: ApproachJoin] = [:]) -> CodeParse {
        if let word = wordCommands[token.lowercased()] { return .command(word) }
        if token.lowercased().hasPrefix("j") {
            let id = String(token.dropFirst()).uppercased()
            if id.isEmpty { return .incomplete("type an approach after j, for example j I27.AYBEE") }
            guard let join = approaches[id] else {
                let some = approaches.keys.sorted().prefix(6).joined(separator: ", ")
                return .error("Unknown approach '\(id)'" + (some.isEmpty ? "" : ". Approaches: \(some)"))
            }
            return .command(.joinApproach(procedure: join.procedure, runway: join.runway, via: join.via))
        }
        guard let letter = token.lowercased().first, codeLetters.contains(letter) else {
            return .error("Unknown code '\(token)'. Use d, c, h, s, i, p, x, j, m, lu, to or ho")
        }
        if letter == "x" {
            let parts = token.dropFirst().uppercased().split(separator: "@", omittingEmptySubsequences: false).map(String.init)
            let fix = parts.first ?? ""
            if fix.isEmpty { return .incomplete("type a fix after x, for example x kerav 50") }
            if !knownFixes.contains(fix) { return .error("Unknown fix '\(fix)'") }
            guard parts.count == 2, !parts[1].isEmpty else { return .incomplete("type a level after \(fix), for example x \(fix.lowercased()) 50") }
            guard parts[1].allSatisfy({ $0.isASCII && $0.isNumber }), parts[1].count <= 3, let value = Int(parts[1]) else {
                return .error("Bad level '\(parts[1])'")
            }
            return .command(.cross(fix: fix, altitudeFt: value * 100))
        }
        if letter == "p" {
            let fixes = token.dropFirst().uppercased().split(separator: ",").map(String.init)
            if fixes.isEmpty { return .incomplete("type a fix after p, for example p kerav pizsa") }
            if let bad = fixes.first(where: { !knownFixes.contains($0) }) { return .error("Unknown fix '\(bad)'") }
            return .command(fixes.count == 1 ? .direct(fix: fixes[0]) : .route(fixes: fixes))
        }
        if letter == "i" {
            guard let runway = parseRunway(token.dropFirst()) else {
                return token.count == 1 ? .incomplete("type a runway after i, for example i28l")
                                        : .error("Bad runway in '\(token)'")
            }
            return .command(.approach(runway: runway))
        }
        var digits = Substring(token.dropFirst())
        var turn: TurnDirection?
        if letter == "h", digits.count > 1, let last = digits.last, "lrLR".contains(last) {
            turn = last.lowercased() == "l" ? .left : .right
            digits = digits.dropLast()
        }
        if digits.isEmpty { return .incomplete("type a number after \(letter)") }
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), digits.count <= 3, let value = Int(digits) else {
            return .error("Bad number in '\(token)'")
        }
        switch letter {
        case "d": return .command(.descend(feet: value * 100))
        case "c": return .command(.climb(feet: value * 100))
        case "h": return .command(.heading(degrees: value == 0 ? 360 : value, turn: turn))
        default: return .command(.speed(knots: value))
        }
    }

    // MARK: Tab completion

    /// Completes the callsign (first token). Repeated Tab with unchanged output cycles through the matches.
    /// Returns nil when there is nothing to complete.
    public static func tabComplete(input: String, aircraft: [Aircraft], state: inout TabState) -> String? {
        if let last = state.lastOutput, last == input, !state.matches.isEmpty {
            state.index = (state.index + 1) % state.matches.count
            let output = state.matches[state.index] + state.suffix
            state.lastOutput = output
            return output
        }

        let trimmed = String(input.drop(while: { $0.isWhitespace }))
        guard !trimmed.isEmpty else { return nil }
        let firstEnd = trimmed.firstIndex(where: { $0.isWhitespace }) ?? trimmed.endIndex
        let first = String(trimmed[..<firstEnd])
        let rest = String(trimmed[firstEnd...])

        // A lone code like "d70" has no callsign part to complete.
        if rest.allSatisfy({ $0.isWhitespace }) && isCode(first) { return nil }

        let matches = rankedMatches(first, in: aircraft).map(\.callsign)
        guard !matches.isEmpty else { return nil }

        state.matches = matches
        state.index = 0
        state.suffix = rest.isEmpty ? " " : rest
        let output = matches[0] + state.suffix
        state.lastOutput = output
        return output
    }
}
