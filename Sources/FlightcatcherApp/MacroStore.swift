import Foundation
import SimCore

/// Reads and writes an airport's macros: ~/Library/Application Support/flightcATCher/Macros/<ICAO>.json.
enum MacroStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("flightcATCher/Macros", isDirectory: true)
    }

    static func url(icao: String) -> URL { folder.appendingPathComponent("\(icao.uppercased()).json") }

    static func load(icao: String) -> [Macro] {
        guard let data = try? Data(contentsOf: url(icao: icao)),
              let macros = try? JSONDecoder().decode([Macro].self, from: data) else { return [] }
        return macros
    }

    static func save(_ macros: [Macro], icao: String) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(macros).write(to: url(icao: icao), options: .atomic)
        } catch {
            print("flightcATCher: could not save macros for \(icao): \(error)")
        }
    }
}
