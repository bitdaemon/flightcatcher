import Foundation
import SimCore
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct RadioRewrite {
    @Guide(description: "The same radio call in natural ICAO phraseology, one line, with identical numbers, fixes and callsign.")
    var text: String
}

/// Rewords radio calls with Apple's on-device model. Every result still goes through `RadioVerifier`.
@available(macOS 26.0, *)
struct FoundationRadioVoice: RadioVoice {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func variant(for utterance: RadioUtterance) async -> String? {
        guard Self.isAvailable else { return nil }
        let role = utterance.speaker == .pilot ? "an airline pilot" : "an air traffic controller"
        let session = LanguageModelSession(instructions: """
            You reword one radio call spoken by \(role). Keep every number, direction, fix name and the callsign \
            exactly as given, in the same spoken form. Do not add, remove or change any fact. Use short, standard \
            ICAO phraseology, one line, no quotation marks.
            """)
        do {
            let result = try await session.respond(to: "Reword: \(utterance.template)", generating: RadioRewrite.self)
            return result.content.text
        } catch {
            return nil
        }
    }
}
#endif
