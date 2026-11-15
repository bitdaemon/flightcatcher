# flightcATCher

By Richard T. ([bitdaemon](https://github.com/bitdaemon)).

A 2D radar approach and departure control game for macOS. You vector arrivals onto the runway in use, clear them for ILS, RNAV or visual approaches, hand them to the tower, and release departures, all with ICAO-style phraseology. Runways are chosen from the wind, and the wind can follow live METARs.

Native Swift, SwiftUI Canvas scope, deterministic simulation engine. No accounts, no telemetry; the only network call is the optional METAR fetch.

> **Not for real-world navigation or training.** This is a game. Procedures and data are approximations and may be wrong or out of date.

## Features

### Airports and procedures
- 506 US airports with scheduled airline service, built from FAA CIFP data, including Alaska, Hawaii and the US territories: runways, ILS and RNAV approaches, STARs and SIDs. Pick one from the searchable airport list (by city, name, ICAO or IATA code); the choice is remembered. Boston (KBOS) is the default.
- Many airports have no STAR or no SID in the FAA data (radar-vector arrivals and departures are not coded). There you vector the traffic yourself: arrivals are handed in at the edge of the approach area heading for an initial approach fix, and departures fly runway heading.
- Approaches: ILS, RNAV (GPS) and RNAV (RNP), with their transitions and missed approaches. RNAV finals are flown down the runway centreline at the published path angle; offset or curved finals are not included yet.
- Procedures are drawn on the scope (STARs, SIDs, approaches, fixes) and can be switched on and off individually. An aircraft's assigned procedure can be shown on request.

### Traffic
- Random arrivals and departures, each with a low-high range per hour. The rates wander inside their ranges (Steady, Moderate or Lively) and the current rates are shown in Airport info. Presets (Quiet, Moderate, Busy, Rush and others), selectable aircraft categories and types, and an optional fixed seed to repeat a session.
- Start-up traffic: a random number of arrivals already inside the approach area, on STARs or heading for an initial approach fix, placed with a spawn-conflict check so nothing starts in a collision.
- Departures wait at the holding point of a runway in use until you line them up and clear them for take-off. The wind decides the runway; a runway with SIDs gives the departure a SID, one without means runway heading.
- Aircraft types with their own climb, descent, turn and speed performance, and airline callsigns that suit the airport's country.

### Controlling aircraft
- **Command bar** with short codes that chain in one line, for example `ein d70 s180 h270l`:
  - `d` descend, `c` climb, `h` heading (`l`/`r` for turn direction), `s` speed
  - `i` ILS approach (a runway without an ILS gets a visual approach)
  - `j` join an approach by its procedure ID, for example `j I27.AYBEE` (ILS) or `j R27.AYBEE` (RNAV); also in the Join approach menu
  - `p` proceed direct, `x` cross a fix at an altitude
  - `m` maintain present heading, altitude and speed (cancels route, crossing, expedite and an approach still being intercepted)
  - `lu` line up, `to` cleared for take-off, `ho` handoff
  - `!` expedites a descent, climb, turn or speed change
- **Radial menu** (right-click an aircraft): HDG, ALT, SPD, DCT, APP, XNG, HO and COL, with pick-and-collect command chips. Departures on the ground get LUP and T/O.
  - Values you pick collect as chips; Enter sends, Esc backs out.
  - The ALT picker marks a departure's flight-plan level with a star and outline.
  - COL sets an aircraft's marker colour.
- Pilots read back instructions with a short delay, and refuse what they can't do ("Unable: ..."), including the minimum vectoring altitude and closed runways. A pilot who cannot make an intercept says so ("we're heading 090, we'll need a vector"), and one established but too high asks for lower.
- Approach logic: localiser and glideslope capture, a stable-approach gate with go-around, and a tower handoff once established. Visual approaches are built from the runway itself.
- Take-off clearances carry the departure instruction: "BOFUM one Alfa departure, climb and maintain three thousand feet, runway zero four right, cleared for take-off", or for a runway without a SID, "fly runway heading, climb to three thousand feet, ...".
- A departure without a SID shows RWY HDG in its tag until you give it a heading, direct or route; the line turns to the warning colour once it is airborne and still waiting for a vector.
- Departures handed off once above their handoff level and cleared to their plan level.

### The scope
- Pan and zoom, range rings, optional compass ring, track tags that can be dragged, and optional tag declutter.
- Selected aircraft: its remaining route is drawn, and an arc with the level shows where it will reach its target altitude at its current speed. Hovering a level in the ALT picker previews where that level would be reached.
- Velocity vectors, conflict and loss-of-separation warnings, and colour markers per aircraft.
- Aircraft handed to the tower are greyed out on the scope and in the strip list.

### Panels (movable, pinnable, resizable)
- **Radio:** controller calls, pilot readbacks and sim notices, colour-coded by speaker and importance (red emergencies, amber go-arounds and refusals, green good news). With an aircraft selected, all its calls are highlighted.
- **Aircraft:** arrival and departure strips with the last instructions; departures show their plan level and handoff level. Handed-over aircraft shrink to a greyed line.
- **Airport info:** elevation, transition altitude, wind and its source (real METAR or random) with a countdown to the next update, open runways with head and crosswind, closed runways, and the separation monitor.
- **Runways:** a zoomed-in runway chart. Green means free, yellow means an arrival is cleared for an approach to it, red means a take-off or landing is using it. Aircraft near the runways are shown.
- **Commands:** a cheat sheet for the command bar and mouse actions.

### Weather
- Wind from live METARs (NOAA Aviation Weather Center, no key needed), refreshed every 15 minutes, with a short notice at the top of the scope after each fetch. If a fetch fails the wind drifts randomly.
- Alternatively random drifting wind or a fixed wind.
- Gusts are included. The runway in use is chosen from the mean wind, with closure limits (tailwind, crosswind) checked against gusts. Runways close and reopen with hysteresis.

### Random events
- A configurable percentage of arrivals have an event: a pilot-decision go-around, a windshear go-around, or an emergency (engine failure, medical, low fuel, hydraulic failure, smoke, bird strike, loss of pressurisation, unsafe gear) declared a few minutes after entering the area. Emergency aircraft get a red ring and tag on the scope and a red badge on the strip.
- Set the percentages in Settings > Events (3%, 2% and 2% by default).

### Scoring and debrief
- Points for moving traffic safely: +100 an arrival handed to the tower, +20 when it lands, up to +30 for an efficient arrival, +80 a departure handed off (+20 more if cleared to its plan level), +30 extra for a landed emergency.
- Penalties: −300 a loss of separation (and −50 for every 10 s it lasts), −150 a departure leaving the area without a handoff, −100 a go-around you caused, −50 an arrival left at the end of its route, −50 an emergency ignored for 2 minutes, smaller ones for conflict alerts, refusals, waiting departures and unvectored runway-heading departures. Pilot and windshear go-arounds are free.
- Score = points × a difficulty multiplier from the traffic rate and variation, random events, live weather and gusts.
- The score, multiplier, grade and last change are shown in Airport info; big changes also go on the radio.
- **END** (top right of the control bar) pauses and opens the debrief: grade (A Supervisor to E Removed from position), breakdown, score and traffic chart, worst moments, arrival efficiency and the airport's best scores. Resume, start a new session, or replay the same traffic seed to beat your score.

### Settings (Cmd+,)
- Display: text size (Cmd+= larger, Cmd+- smaller, Cmd+0 reset), colour scheme, compass, tag options.
- Layers: fixes, STARs, SIDs and approaches, individually.
- Panels: show and hide panels, reset layout.
- Traffic, Weather and Events.
- Test spawner: a panel (Settings > Debug) that places an aircraft at a chosen bearing and distance, heading, altitude and speed, or on a chosen final approach, for troubleshooting.
- Debug: an optional debug log (commands, approach progress, why an aircraft has not captured its approach), written to `~/Library/Logs/flightcATCher/` and shown in a live panel.

## Requirements
- macOS 14 or later
- Xcode 15 or later, or a Swift 5.9+ toolchain

## Build and run
```sh
git clone https://github.com/bitdaemon/flightcatcher.git
cd flightcatcher
swift run FlightcatcherApp
```
Or open `Package.swift` in Xcode, choose the `FlightcatcherApp` scheme and "My Mac", then Cmd+R. Cmd+U runs the tests.

## Layout
- `Sources/SimCore`: UI-free simulation engine and airport packages (JSON resources).
- `Sources/FlightcatcherApp`: SwiftUI app.
- `Tests/SimCoreTests`: unit tests.
- `Tools`: Python scripts that generate airport packages from FAA CIFP data (`cifp_to_package.py --airline` builds the bundled set).
- `docs/DEVELOPMENT.md`: development notes.
- `docs/ROADMAP.md`: planned features.
- `docs/USER-MANUAL.md`: user manual with arrival and departure tutorials.

## Data and attribution
See [DATA-SOURCES.md](DATA-SOURCES.md). Airline names and callsigns are used only as flavour; this project is not affiliated with or endorsed by any airline, air navigation service provider, or aviation authority.

## Licence
Copyright 2026 Richard T. Licensed under the Apache License, Version 2.0, see [LICENSE](LICENSE).

flightcATCher is the original work of Richard T. If you redistribute it or build on it, keep the [NOTICE](NOTICE) file with your copy and credit Richard T. as the original author, and mark any files you changed (Apache License, section 4). Data sets keep their own terms, listed in DATA-SOURCES.md.
