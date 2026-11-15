import SwiftUI
import SimCore

/// Searchable airport list. Shows the city first, then the airport name, region and ICAO code.
struct AirportPicker: View {
    let entries: [AirportIndexEntry]
    let currentICAO: String?
    let onSelect: (AirportIndexEntry) -> Void
    @State private var query = ""

    private var filtered: [AirportIndexEntry] { entries.filter { $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search city, airport, ICAO or IATA", text: $query)
                .textFieldStyle(.roundedBorder)
            Text("\(filtered.count) of \(entries.count) airports")
                .font(.ui(size: 10)).foregroundStyle(.secondary)
            List(filtered) { entry in
                Button { onSelect(entry) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.city ?? entry.name).font(.ui(size: 13, weight: entry.icao == currentICAO ? .bold : .regular))
                            Text(entry.subtitle).font(.ui(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(entry.icao).font(.ui(size: 13, design: .monospaced))
                            if entry.ilsRunways > 0 {
                                Text("ILS \(entry.ilsRunways)").font(.ui(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 320)
        }
        .padding(12)
        .frame(width: 420 * UIScale.factor, height: 440 * UIScale.factor)
    }
}
