import SwiftUI

/// Always-available cheat sheet for the command bar and mouse actions. Toggled from the top-left controls.
struct HelpView: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    private let mono = Font.ui(size: 11, design: .monospaced)

    private let rows: [(String, String)] = [
        ("d70", "descend to 7000 ft (number is hundreds of ft)"),
        ("c120", "climb to 12000 ft (above 5000 ft it is a flight level)"),
        ("h270", "fly heading 270, shorter turn"),
        ("h270l / h270r", "turn left / right to heading 270"),
        ("s180", "speed 180 kt"),
        ("d50! h270l! s180!", "add ! to expedite a descent, climb, turn or speed change"),
        ("i28l / i28r", "cleared ILS approach runway 28L / 28R (a runway without an ILS gets a visual approach)"),
        ("p kerav", "proceed direct to fix KERAV"),
        ("p kerav pizsa", "direct to each fix in order (any number of fixes)"),
        ("j i27.aybee", "join approach I27.AYBEE: direct to its first fix, fly the approach, cleared ILS (the same as the Join approach menu)"),
        ("x kerav 50", "cross KERAV at 5000 ft (fix must be on the route)"),
        ("m", "maintain present heading, altitude and speed: cancels route, crossing, expedite and an approach still being intercepted"),
        ("mac appr", "run the airport's macro APPR on the aircraft (edit macros in the Macros panel)"),
        ("mac-", "stop the aircraft's macro; any instruction you give it also stops it"),
        ("lu", "departure: line up and wait"),
        ("to", "departure: cleared for take-off (from the hold or lined up)"),
        ("mouse", "drag to pan, pinch or the + and - buttons to zoom, Esc clears the selection; settings are in the gear button or Cmd+,"),
        ("ho", "handoff: a departure leaves your area once it is above its handoff level and cleared to its plan level; an established arrival goes to the tower and stays on the scope until landed"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("COMMANDS").font(mono).foregroundStyle(theme.heading)
            ForEach(rows, id: \.0) { code, meaning in
                HStack(alignment: .top, spacing: 8) {
                    Text(code).font(mono).foregroundStyle(theme.selected).frame(width: 110 * UIScale.factor, alignment: .leading)
                    Text(meaning).font(mono).foregroundStyle(theme.text)
                }
            }
            Text("Type: [callsign or name] code, e.g. ein d70, ryr h270l.")
                .font(mono).foregroundStyle(theme.dimText).padding(.top, 4)
            Text("Chain codes in one line: ein d70 s180 h270l")
                .font(mono).foregroundStyle(theme.dimText)
            Text("With an aircraft selected the callsign can be left out.")
                .font(mono).foregroundStyle(theme.dimText)
            Text("Tab completes a callsign, Enter sends, Esc clears.")
                .font(mono).foregroundStyle(theme.dimText)
            Text("Right-click an aircraft: ring with HDG ALT SPD DCT APP XNG MAINT MAC HO (departures: no APP; on the ground: LUP T/O MAC).")
                .font(mono).foregroundStyle(theme.dimText).padding(.top, 4)
            Text("Pick values; they collect as chips. Enter sends, Esc backs out.")
                .font(mono).foregroundStyle(theme.dimText)
            Text("HDG: point and click (Option = turn the other way).")
                .font(mono).foregroundStyle(theme.dimText)
            Text("Mouse: click an aircraft or list row to select;")
                .font(mono).foregroundStyle(theme.dimText).padding(.top, 4)
            Text("ILS / VIS buttons do the same as i28l / i28r;")
                .font(mono).foregroundStyle(theme.dimText)
            Text("\"Join approach\" menu: direct to an approach's first fix, cleared.")
                .font(mono).foregroundStyle(theme.dimText)
            Text("Drag pans, pinch or +/- zooms.")
                .font(mono).foregroundStyle(theme.dimText)
            Text("Panels: drag a title bar to move, pin to lock, resize from the corner.")
                .font(mono).foregroundStyle(theme.dimText).padding(.top, 4)
            Text("List row 2 shows the last instructions; ... = pilot not yet complying.")
                .font(mono).foregroundStyle(theme.dimText)
        }
        .padding(10)
    }
}
