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

    private let scoreRows: [(String, String)] = [
        ("arrival handed to the tower, established", "+100"),
        ("arrival lands", "+20"),
        ("arrival flown efficiently: up to 1.2 times its clean time, less up to 2 times", "up to +30"),
        ("departure handed off", "+80"),
        ("departure handed off cleared to its plan level", "+20"),
        ("emergency aircraft landed (extra)", "+30"),
        ("loss of separation", "\u{2212}300"),
        ("every 10 s a loss of separation lasts", "\u{2212}50"),
        ("conflict alert (predicted loss)", "\u{2212}10"),
        ("departure leaves the area without a handoff", "\u{2212}150"),
        ("go-around you caused (unstable, high, fast, runway occupied); pilot and windshear go-arounds are free", "\u{2212}100"),
        ("arrival reaches the end of its route with no clearance", "\u{2212}50"),
        ("emergency given no instruction for 2 min", "\u{2212}50"),
        ("runway-heading departure not vectored by 10 NM", "\u{2212}20"),
        ("instruction refused by the pilot", "\u{2212}5"),
        ("each minute a departure waits at the hold after 3 min", "\u{2212}1"),
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

            Text("SCORING").font(mono).foregroundStyle(theme.heading).padding(.top, 8)
            ForEach(scoreRows, id: \.0) { what, points in
                HStack(alignment: .top, spacing: 8) {
                    Text(points).font(mono).foregroundStyle(points.hasPrefix("+") ? theme.ok : theme.alert)
                        .frame(width: 110 * UIScale.factor, alignment: .leading)
                    Text(what).font(mono).foregroundStyle(theme.text)
                }
            }
            Text("Score = points \u{00D7} multiplier. The multiplier grows with the traffic rate (Settings > Traffic), a Moderate or Lively variation, random events, live weather and gusts.")
                .font(mono).foregroundStyle(theme.dimText).padding(.top, 4)
            Text("The score, multiplier, grade and last change are in Airport info. Changes of 100 points or more are also on the radio.")
                .font(mono).foregroundStyle(theme.dimText)
            Text("END (top right) pauses and shows the debrief: grade, breakdown, chart, worst moments, efficiency, best scores. Resume carries on; Replay this seed repeats the same traffic.")
                .font(mono).foregroundStyle(theme.dimText)
            Text("Grade: points against the most the handled aircraft could earn. A 85%+ Supervisor, B 70% Senior controller, C 50% Controller, D 30% Trainee, E Removed from position. One loss of separation caps it at C, three give E.")
                .font(mono).foregroundStyle(theme.dimText)
        }
        .padding(10)
    }
}
