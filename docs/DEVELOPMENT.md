# flightcATCher development notes

A personal, fully local 2D radar approach and departure control game for macOS, written in native Swift (SwiftUI Canvas scope, deterministic `SimCore` engine). You vector arrivals onto the runway in use, clear them for ILS or visual approaches, hand them to the tower, and release departures to the next sector, using ICAO phraseology. It runs at any of 160 FAA airports (CIFP data), with runways chosen by wind. The simulation decides everything; the planned Apple Foundation Models layer only varies the wording of radio calls behind a verifier with a template fallback, and is not built yet. See the build plan doc in the project for what is next.

## Run in Xcode
1. Open `Package.swift` (double-click, or File > Open on this folder).
2. Choose the `FlightcatcherApp` scheme and "My Mac", then Cmd+R. Cmd+U runs the tests.

## Layout
- `SimCore`: UI-free, deterministic simulation (fixed one-second tick, seeded RNG), airport package model, flat-earth projection.
- `FlightcatcherApp`: SwiftUI app. The Compass button toggles a heading ring around the window (true headings, marks every 5 degrees, labels every 30). `SimRunner` drives ticks from a timer; `ScopeView` draws range rings, the runways and extended centrelines with pan and zoom.

Command line: `swift test`, `swift run FlightcatcherApp`.

This is a package-built executable, so it has no app bundle, icon or entitlements. A proper app project that imports `SimCore` can replace it later.

## Command bar
Type `[callsign fragment] code+number`, for example `ein d50`, then Enter. After a command the aircraft stays selected, so `h270` alone works. Tab completes or cycles the callsign (callsign or radio name, e.g. `sham`). Esc clears.
`d` descend, `c` climb (level in hundreds of feet), `h` heading (add `l` or `r` to force the turn direction, e.g. `h270l`; without it the pilot turns the shorter way, exactly 180 turns right), `s` speed in knots. Pilots read back after a 3 to 6 second delay. Level, speed and turn-rate limits are placeholders.

## Selecting aircraft
Click a track (symbol or label) on the scope, click a row in the side list (chevron tab, top right, collapses it), or type a callsign or radio-name fragment and press Enter once it resolves to one aircraft. Clicking empty space deselects. The selected aircraft is yellow, and its callsign shows in the command-bar prompt.
Start-up traffic: five arrivals on different STARs, with random types and callsigns that suit the airport (see "Random traffic and aircraft types"). When several callsigns share a prefix, Tab cycles through them.

## Map data

The Layers menu toggles the compass, fixes, STARs, SIDs and approaches. The selected aircraft's remaining route is drawn dashed yellow.

## Flying
Demo aircraft start on their STARs and follow them to the approach start (OBINU or PIZSA). At the end of a route they hold their heading. A heading command leaves the route. Select an aircraft and press "ILS 28L" or "ILS 28R" in the list panel to clear it: it joins the approach legs, captures the localiser and glidepath, slows, and lands, or goes around if it is not established or is faster than 190 kt inside 2.5 NM. Altitude and speed on a STAR are not flown automatically; you give the descents and speeds.

## Separation monitor
`SeparationMonitor` (SimCore) flags pairs that are inside 3 NM and 1000 ft at the same time (loss, red) or will be within 120 s if both fly straight on their current heading and speed, with altitude moving toward its target (predicted, amber). The scope draws a line between the pair and rings both aircraft. The radio log gets one line when a pair becomes predicted and one when separation is actually lost. The minima in `SeparationMinima` are placeholders. The prediction ignores turns still to come, so it can raise alerts for aircraft that are about to turn away.

The panel at top right shows airport elevation, transition altitude, a wind row (placeholder, there is no wind model) and the current conflicts.

## FAA airports from CIFP
`Tools/cifp_to_package.py` converts the FAA CIFP file (ARINC 424 v18, `Data/cifp/FAACIFP18`) into the airport package format:

    python3 Tools/cifp_to_package.py --cifp ../Data/cifp/FAACIFP18 --stats        # how many airports have ILS, STAR, SID
    python3 Tools/cifp_to_package.py --cifp ../Data/cifp/FAACIFP18 KBOS KJFK KLAX  # writes kbos.json etc. into Resources/Airports

The converter takes the ILS approaches only (plus their transitions), builds each STAR and SID once per transition and runway combination, skips heading and course legs, flies arcs as straight legs, and sets no holds. Runway true bearing is computed from the thresholds. Takeoff and landing distances are set to the runway length (placeholder). Column positions were checked against sample KBOS records, not against the ARINC 424 specification. The file is cycle 2612 (CIFP_261126).

The airport button (top bar) opens a searchable list of 160 bundled airports, shown as city first ("Boston (KBOS)"), searchable by city, name, ICAO or IATA code. Choosing one restarts the simulation there and remembers the choice. Every airport starts five aircraft part-way along the first STAR of five different families. To add an airport, run the converter for its code and rebuild.

## Wind and runway availability
`Weather.swift` holds a simple wind: one surface wind for the whole airspace (direction it blows from, degrees true, and speed), stronger aloft (1x at the surface up to 3x from 30000 ft). It starts within 40 degrees of a runway heading at 6 to 20 kt and then does a small random walk once a minute (a change is only kept if at least one runway stays usable). Aircraft are blown downwind: heading and indicated speed give the air track, the wind is added to the position, and the separation prediction includes it.

A runway is closed when the tailwind exceeds 5 kt or the crosswind exceeds 25 kt (placeholders in `WindLimits`), and reopens when both are 1 kt inside the limits. Of the two ends of a strip only the one facing the wind is open (the runway in use; calm wind goes to the runway listed first); the other end shows "runway 28L in use". The direction in use changes only when the other end's headwind is better by more than 2 kt. A procedure is available when at least one runway it serves is open. Closed runways are listed in the info panel, their ILS buttons are disabled, clearances to them are refused ("Unable: runway 28L is closed: tailwind 8 kt"), and their STARs, SIDs and approaches are not drawn, not listed in the Layers menu, not in the Join approach menu and not used for demo traffic. Aircraft already cleared keep going.

## Routes through several fixes

Type `ein p kerav pizsa lamba` (or `pkerav pizsa`): known fixes after `p` are flown direct in order, and the next code ends the route, for example `ein p kerav pizsa i28l`. With the mouse, choose DCT and click fixes in order; the route is drawn with numbers. Click the last fix again or press Done to add it as one chip (`DCT KERAV›PIZSA`); Undo removes the last fix and Esc clears the route. A route replaces the aircraft's current route and does not fly procedure altitude or speed restrictions.

## Colour schemes

The Colours menu switches between 14 schemes (Slate, Midnight, Graphite, Phosphor, Amber, Daylight, Paper, High contrast, Colour-blind safe, Solar dark, Nord, Dracula, Ocean, Dusk); the choice is saved. Light schemes also switch the system controls to the light appearance. The colours are in `Sources/SimCore/DisplayScheme.swift`. In every scheme the STAR, SID, approach, projected-route and runway colours are kept a set distance apart (CIE L*a*b* distance, enforced by `DisplaySchemeTests`), and each is far from the background. The colour-blind scheme uses the Okabe-Ito palette and was also checked under simulated protanopia and deuteranopia.

The selected aircraft's projected route has its own colour and style so it can be told from an approach line, even when the aircraft flies along one: a background-coloured casing, a bold dashed line, and a diamond at every remaining fix. Procedure lines are 1.5 px and drawn almost opaque.

## Track tags

Every aircraft has a boxed tag (callsign, speed and altitude, plus the last instructions on a third line for the selected aircraft) joined to its symbol by a leader line. Drag a tag to move it; tags you place by hand stay where you put them. Layers > Auto-declutter tags (on by default) moves the other tags apart from each other and from aircraft symbols, and keeps a tag where it is as long as that spot is clear so tags don't jump about. "Declutter tags now" rearranges every tag, including hand-placed ones; "Reset tag positions" puts them all back to the default. Clicking a tag selects its aircraft.

## Panels and last instructions

The aircraft list, airport info, radio log and command help are floating panels. Drag a title bar to move one (it snaps to the window edges), press the pin to lock it where it is (pinned panels have a yellow border and cannot be dragged or resized), the chevron collapses it to its title bar, the x hides it, and the corner handle resizes the radio and aircraft panels. The Panels menu brings hidden panels back and resets the layout; positions are saved between runs. A panel dragged off screen is pulled back so its title bar stays reachable.

The radio log is now its own panel and scrolls through the whole log. Each row of the aircraft list has a second line with the time and the last three instructions given to that aircraft; "..." after one means the pilot has not started on it yet. The selected aircraft's panel section lists its last six instructions with times and "waiting for pilot" where relevant. The selected aircraft's track tag on the scope shows its last two instructions in a third line; Layers > "Last instructions on all tags" shows them on every tag.

## Random traffic and aircraft types

The Traffic button opens the generator settings: on/off, arrivals per hour (a random Poisson stream, so the gaps vary), IFR on/off, aircraft categories (heavy jets, narrowbody jets, regional jets and turboprops, light aircraft) and individual types, plus presets (Quiet, Moderate, Busy, Airline only, Heavy mix, Turboprops and light). Settings are saved. New arrivals appear at the start of a randomly chosen available STAR with the altitude and speed of its first leg, and wait briefly if the entry is crowded. The seed is random each start; type one into the Seed box to repeat the same traffic, since the generator uses its own seeded random sequence.

Every generated aircraft has a type (shown in the aircraft list). The type sets its turn, climb, descent and acceleration rates, its speed range (a Cessna will refuse 250 kt, an ATR will refuse 300), its ceiling and its approach speed, which sets the speed limits on the glidepath. The figures in `AircraftType.swift` are rough round numbers for play, not real performance data. Not built yet: departures, VFR traffic, and wake spacing (the wake category is stored).

## Crossing a fix at an altitude

Type `ein x kerav 50` (or `xkerav 50`): cross KERAV at 5000 ft (level in hundreds of feet, flight level above the transition altitude). The fix must be on the aircraft's remaining route, or on a route given earlier in the same line, so `ein p kerav pizsa x pizsa 50` works. The pilot holds the present level, then leaves it as late as normal rates allow to be at the level over the fix. If that is already impossible the pilot says "unable to cross" and does its best. With the mouse, choose XNG on the ring, click a highlighted fix, then pick the level; the chip reads `X KERAV 5000`. Instructions to one aircraft are now carried out in the order they were given.

When a route runs out with no approach clearance the pilot calls "Overhead KERAV, maintaining heading two seven zero" and holds that heading.

## Expedite

Add `!` to a descend, climb, heading or speed code (`ein d50!`, `h270l!`, `s180!`) to expedite it. The pilot reads back "expedite descent to 5000 feet", "turn left immediately heading 270" or "reduce speed immediately to 180 knots". An expedited aircraft climbs and descends 1.6x, turns 1.5x and changes speed 2x as fast as normal; these factors are placeholders in `Aircraft`. The effect ends when the target is reached or a plain command of the same kind replaces it. Other codes (`i`, `p`) cannot be expedited. With the mouse, press the Expedite button while choosing a heading, altitude or speed, or hold Shift when you click; the chip shows a `!`.

## Mouse controls
Right-click an aircraft (or two-finger click on the trackpad) to get a ring of buttons around it. There are three rings: arrivals get HDG, ALT, SPD, DCT, APP, XNG and HO; departures in the air get the same without APP; departures on the ground get only LUP (line up and wait) and T/O (cleared for take-off). LUP, T/O and HO add a chip at once, like the other commands, and are sent with Enter. HO hands a departure to the next controller (it leaves the scope), or hands an arrival to the tower once it is established on the localiser: the arrival stays on the scope, tagged TWR, until it lands, takes no further instructions, and comes back to you if it goes around.
- **HDG:** a compass ring appears around the aircraft. Point and click, or drag and release; the ghost line and label follow the pointer. Pointing sends the shorter way; hold Option to turn the other way round.
- **ALT / SPD:** a scrolling column of values beside the aircraft with the current one marked. Values the aircraft would refuse are greyed out.
- **DCT:** every fix of the airport is shown; hover to preview the line to it and click to choose.
- **APP:** each open ILS runway gets a button on its extended centreline (cleared ILS, joining the localiser), and each available approach a button on its first leg (direct to its first fix and fly it).
Each choice becomes a chip beside the aircraft, for example `HDG 270L`. A second choice of the same kind replaces the first. Click a chip to remove it. Enter (with the command line empty) or the Send button sends the chips in order; Esc steps back one level and then clears. Chips are the same thing as a typed chain. The chain logic is `CommandChain` in SimCore.

## Bulk airport import

    Tools/fetch_places.sh                                                   # OurAirports city names (once)
    python3 Tools/cifp_to_package.py --cifp ../Data/cifp/FAACIFP18 --all   # every airport with ILS + STAR + SID

`--all` builds each candidate, skips any that fail validation or lack an ILS approach, a STAR or a SID, and writes `airports-index.json` (city, name, region, country, IATA, counts) next to the packages. The index is what the picker reads. Packages without a match in OurAirports fall back to the CIFP airport name. Not yet built: visual approaches (a new procedure kind) and tower/centre controller positions; the package schema has room for both.

## Callsigns and airlines

Arrivals get a callsign that suits the airport's country (`country` in the package). Airline weights live in `AirlineTable` (`Sources/SimCore/AircraftType.swift`) as home / abroad / at-a-US-airport weights per aircraft category. At a US airport: American, Delta, United, Southwest, JetBlue, Alaska and others on narrowbodies; SkyWest, Republic, Endeavor and other regionals with flight numbers 3000-6999; FedEx and UPS freighters; and foreign long-haul carriers (British Airways, Lufthansa, Emirates, Aer Lingus, Singapore, Japan Air and so on) on heavies, plus Air Canada, WestJet, Aeromexico and similar on narrowbodies. Short-haul European carriers such as Ryanair and easyJet never appear at US airports. Light aircraft get N-numbers in the US ("N482KB", spoken "November four eight two Kilo Bravo"), EI- registrations in Ireland. The radio name table is derived from the same list. The data is from memory of public information: check the radio names and fleets against a current source.

## Departures (first version)

Departures appear at the holding point of an open runway that has SIDs, at `departuresPerHour` (Traffic panel, default 8), three waiting per runway at most. Each gets a random type, callsign and SID, and calls "Holding point runway two eight left, ready for departure".

Commands (command bar, one word each): `lu` line up and wait, `to` cleared for take-off (from the hold or lined up; the call includes the wind), `ho` contact the next controller. Climb, heading and so on are refused on the ground.

What the simulation does:
- Take-off roll along the runway, rotation at the type's approach speed plus 10 kt (light aircraft: the approach speed), runway heading to 400 ft above the field, then the assigned SID. First level is 3000 ft or the first thousand above field elevation plus 2500 ft. The aircraft levels there until you climb it.
- At 1500 ft the pilot calls "Departure, ..., passing ..., climbing ..., BOFUM one Alfa departure".
- The runway is occupied while a departure is lined up, rolling or below 150 ft above the field (either end of the strip). Line-up and take-off are refused then, and take-off is refused with an arrival within 4 NM of the threshold. An arrival inside 1.5 NM of an occupied runway goes around.
- A departure can only be handed off once it is at or above its handoff level (field elevation + 4,000 ft rounded up, at least 4,000 ft, never above its flight-plan level) and is cleared to its flight-plan level; otherwise the command is refused ("climbing through 3000 ft, handoff at 5000 ft" or "not cleared to its plan level, 34000 ft"). Each departure carries a flight-plan level (placeholder: FL220-360 by aircraft type, from the callsign) shown on its strip as "plan FL340  handoff 5000 ft".
- Handoff removes the aircraft. A departure that reaches 45 NM without a handoff is removed and counted in `missedHandoffs`.
- Ground aircraft are not traffic for the separation monitor.

Not done yet: SID altitude and speed constraints (departures hold the first level), choosing the SID or runway, intersection departures, taxiing and gates, wake-turbulence spacing, departure-to-departure separation after take-off, handoff frequencies and facility names (the call says "area control"), and the tower and sector controllers.

## Aircraft list: arrivals and departures

The aircraft list has two sections. ARRIVALS are ordered by distance from the airport, nearest first (an arrival handed to the tower stays here, marked TWR). DEPARTURES are ordered rolling, lined up, holding (in the order they reached the hold), then airborne with the one furthest out first. A departure with no instructions yet shows its runway and SID (and its initial level once airborne) on the second line. The buttons below the list follow the selected aircraft: ILS, Join approach and Handoff to tower for an arrival; Line up, Cleared for take-off and Handoff for a departure.

## Visual approaches

Every open runway can be used for landing. A runway with an ILS gets the ILS approach (button "ILS 28L"); a runway without one (most runways of small airports) gets a visual approach (button "VIS 34"). The visual approach is built from the runway itself: a 3 degree path on the extended centreline with a 50 ft threshold crossing height, and the same capture rules, stable-approach gate, go-around and tower handoff as the ILS. The command bar keeps `i26`: for a runway without an ILS it is turned into "cleared visual approach runway two six". No weather or visibility is modelled, so a visual approach is always allowed. Closed runways (tailwind or crosswind) still refuse any approach clearance. "Join approach" and the STAR-to-ILS links are unchanged and only exist for runways with an ILS procedure.

On the scope, runways in use are drawn bright and thick, with bold labels and a dashed extended centreline. Closed runways are drawn thin and dimmed, with a warning-coloured cross over the pavement, a dim label and no centreline.

## Aircraft colours and procedure toggle

Select an aircraft: the Aircraft panel shows a row of six colour swatches (and a "no colour" button). The colour fills the position symbol, adds a bar on the tag and a dot in the list, so aircraft you have already vectored, cleared for the approach or handed on stand out. A conflict still turns the track amber or red, and the selected aircraft keeps its selection colour. The six colours (`AircraftMarkers.palette`) were chosen to stay at least 25 CIE76 units from every line, alert, selection, runway and background colour in all 14 schemes; `AircraftMarkerTests` enforces it. A button next to the swatches (named after the aircraft's STAR or SID) draws that aircraft's assigned procedure on the scope, thick and with fix names, whatever the layer switches say; it uses the aircraft's colour or the STAR/SID colour. Colours and procedure switches last until the aircraft leaves the scope.

An arrival handed to the tower is drawn greyed out: dim symbol, no velocity vector, no colour marker, and a one-line tag with only the callsign (faint box). It stays on the scope until it lands, and returns to normal if it goes around.

## Vectoring floor

The lowest assignable level is per airport (once cleared for an approach it drops to field elevation + 1,000 ft rounded down, KABQ 6,000 ft, so the aircraft can be put on the glidepath): field elevation + 2,000 ft rounded up to a whole thousand (KABQ 8,000 ft, never below 2,000 ft). Descend and cross commands below it are refused with "below the minimum vectoring altitude". Start-up traffic is created at or above the floor. Go-arounds climb to field + 2,500 ft rounded up (min 3,000 ft).


## Debug log
Settings > Debug turns on a log of everything that happens to a command and an approach. `Simulation.debug(...)` records `DebugEntry` lines (tick, category, callsign, message) in a ring buffer of 2,000; the app writes each one as JSON to `~/Library/Logs/flightcATCher/sim-<time>-<ICAO>.jsonl` and shows the last 400 in the Debug log panel. Categories: `cmd` (accepted, REFUSED at issue time; applied or DROPPED when the pilot acts after the 3 to 6 s delay), `approach` (cleared, phase changes, "not captured: <reason>" whenever the reason changes, STALLED after 120 s and every 60 s), `state` (a state line every 30 s while intercepting), `event` (aircraft events). The capture reason comes from `Aircraft.captureBlocker()`, the same function the capture rule uses. Logging only reads the simulation (no random numbers, no state changes); a test checks the state digest is identical with logging on and off. See `docs/ROADMAP.md` for what comes next.
