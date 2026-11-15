import Foundation
import FoundationModels

// 1. Is the model usable at all?
let model = SystemLanguageModel.default
switch model.availability {
case .available:
    print("Model available.")
case .unavailable(let reason):
    print("Model NOT available: \(reason)")
    print("Check System Settings > Apple Intelligence & Siri, and that the model has finished downloading.")
    exit(1)
}

// 2. The rule we want: the model only rewords; every number and name must come through untouched.
let instructions = """
You voice air traffic radio calls. You receive one call, already correct, and you say it \
in standard ICAO phraseology as it would be spoken in the United States. Do not change, add or remove any \
number, callsign, fix name, runway or altitude. Digits are spoken one at a time. \
Reply with the call only, one line, no quotes and no explanation.
"""

struct Case {
    let role: String
    let call: String
    /// Strings that must appear in the reply, lower-cased.
    let mustContain: [String]
}

let cases: [Case] = [
    Case(role: "approach controller", call: "American one two three, descend flight level seven zero",
         mustContain: ["american", "one two three", "seven zero"]),
    Case(role: "approach controller", call: "Speedbird four five six, turn left heading two seven zero, reduce speed two one zero knots",
         mustContain: ["speedbird", "four five six", "two seven zero", "two one zero"]),
    Case(role: "tower controller", call: "Southwest seven four two, wind two six zero degrees one two knots, runway two seven, cleared to land",
         mustContain: ["southwest", "seven four two", "two six zero", "one two", "two seven", "cleared to land"]),
    Case(role: "tower controller", call: "Delta one eight, line up and wait runway zero four right",
         mustContain: ["delta", "one eight", "line up and wait", "zero four right"]),
    Case(role: "area control centre", call: "American one two three, contact Boston Approach one two zero decimal five",
         mustContain: ["american", "one two three", "boston approach", "one two zero", "five"]),
    Case(role: "pilot", call: "Descending flight level seven zero, American one two three",
         mustContain: ["descending", "seven zero", "american", "one two three"]),
]

var passed = 0
var times: [Double] = []
for c in cases {
    // A fresh session per call: no memory between calls, as the game would do for independent events.
    let session = LanguageModelSession(instructions: instructions)
    let prompt = "Role: \(c.role).\nCall: \(c.call)"
    let start = ContinuousClock.now
    do {
        let response = try await session.respond(to: prompt)
        let seconds = Double((ContinuousClock.now - start).components.seconds)
            + Double((ContinuousClock.now - start).components.attoseconds) / 1e18
        times.append(seconds)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let missing = c.mustContain.filter { !lower.contains($0) }
        if missing.isEmpty { passed += 1 }
        print("--")
        print("in : \(c.call)")
        print("out: \(text)")
        print(String(format: "time: %.2f s  %@", seconds, missing.isEmpty ? "OK" : "MISSING: \(missing.joined(separator: ", "))"))
    } catch {
        print("--\nin : \(c.call)\nerror: \(error)")
    }
}

print("\nPassed \(passed) of \(cases.count).")
if !times.isEmpty {
    print(String(format: "Time per call: min %.2f s, mean %.2f s, max %.2f s", times.min()!, times.reduce(0, +) / Double(times.count), times.max()!))
}
