import Foundation
import SimCore

/// Writes the simulation's debug log to ~/Library/Logs/flightcATCher/ as JSON lines, one file per session.
final class DebugLogFile {
    private(set) var url: URL?
    private var handle: FileHandle?

    static var folder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/flightcATCher")
    }

    func open(airport: String) {
        close()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "sim-\(formatter.string(from: Date()))-\(airport).jsonl"
        let file = Self.folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: nil)
            handle = try FileHandle(forWritingTo: file)
            url = file
        } catch {
            handle = nil
            url = nil
        }
    }

    func write(_ entry: DebugEntry) {
        guard let handle, var data = try? JSONEncoder().encode(entry) else { return }
        data.append(0x0A)
        try? handle.write(contentsOf: data)
    }

    func close() {
        try? handle?.close()
        handle = nil
    }

    deinit { close() }
}
