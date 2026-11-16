# flightcATCher roadmap

Status: 16 Nov 2026. By Richard T. (github.com/bitdaemon/flightcatcher), Apache 2.0 with a NOTICE file. Renamed from flycATCher on 15 Nov. `README.md` describes the features; this file is the plan. Voice is parked until the items below are settled.

## Now
- Build and test the work of 15 to 16 Nov listed below. Last full run (20:53, 15 Nov): 235 tests, 0 failures. Everything from scoring onwards came after that run and has not been built yet.
- Put the `ATCSim` folder on GitHub (repository flightcatcher).
- Update `docs/USER-MANUAL.md` to match the README.
- Approach capture: ILS auto-intercept is still open.
- More KBOS flow tests: departure sequencing, go-arounds, handoff.

## Written 15 to 16 Nov 2026, not yet built or tested
- **Scoring and debrief** (`Scoring.swift`, `DebriefView.swift`, `ScoreHistory.swift`):
  - gains: arrival to tower +100, landed +20, efficiency up to +30, departure handed off +80, cleared to plan level +20, heading for its exit +20, emergency landed +30 extra
  - penalties: loss of separation −300 and −50 every 10 s, conflict alert −10, missed departure handoff −150, controller-caused go-around −100, route ended without a clearance −50, emergency ignored 2 min −50, handed off the wrong way −30, runway-heading departure unvectored at 10 NM −20, refused instruction −5, departure waiting −1 a minute after 3 min
  - multiplier from traffic rate and variation, random events, live weather and gusts; grades A Supervisor to E Removed from position (one loss caps at C, three give E); big changes on the radio
  - SCORE and LAST in Airport info; END button at the right of the control bar (divider after the settings gear); debrief with breakdown, charts, worst moments, efficiency, best five scores per airport; Resume, New session, Replay this seed, Quit
- **Separation rules**: pairs both handed to the tower are not counted (still shown); established on parallel approaches: none between independent runways (4,300 ft apart or more), 1.5 NM diagonal between dependent ones; same runway and anyone still intercepting keep 3 NM / 1,000 ft.
- **Conflict prediction follows routes**: aircraft with fixes ahead are projected along them, turning at each fix; others straight on.
- **Stable-approach gate fix**: only on the final approach (within 1 NM of the centreline, not past the threshold) while intercepting; aircraft cleared from off to the side no longer go around at once.
- **Debug log**: no "not captured" or "STALLED" lines while the aircraft is still flying route fixes to its final; the stall timer starts when the route runs out.
- **Exit fixes**: every departure has one (SID's last fix, or a fix 60 to 130% of the area radius out, not behind the departure over the final); tag `RWY HDG → BCE` / `EXIT → BCE`, strip `exit BCE`, dotted line when selected, `p exit`, check-in "requesting direct BCE". Direct-to for departures goes straight to the fix (no STAR tails).
- **Resume own navigation**: `own` or `rn`, OWN on the radial outer arc; rejoins the assigned STAR, SID or direct-to-fix route at the next fix after the nearest segment, departures on to their exit.
- **Approach choice**:
  - APP on the radial opens a list beside the aircraft: per open runway the ILS (or VIS) clearance and up to three approaches to join, ranked by "starts on its route" then distance to the first fix
  - `j01l` picks the best approach to runway 01L for the aircraft, `j01l.2` the second; the command-bar preview lists the choices; runways not in use are refused
- **Radio log** shows each instruction's command-bar form (`> aal123 d70 s180`); a chain once on its first call; every code parses back to the same instruction.
- **Traffic ranges**: low-high sliders for arrivals and departures, variation Steady / Moderate / Lively, TRAF line in Airport info, presets set arrival ranges (new Rush), own random sequence so fixed rates and seeds repeat.
- **Start-up traffic without STARs** starts beyond its fix, inbound.
- **Interface**: APP toggle next to STAR and SID; Airport info split into sections (airport and runways, wind, traffic, score, separation); departures at the hold or lined up show no tag until cleared for take-off; Settings window resizable with scrolling tabs; Commands panel renamed "Commands and scoring", resizable and scrolling.
- Backups of every changed file in `Claude outputs/` (scoring, traffic-variation, exit-fix, resume-nav, prediction, radio-code, runway-join folders).

## Written 15 Nov 2026, built and tested
- Rename flycATCher → flightcATCher; Apache 2.0 licence and NOTICE.
- 506 airline airports (`cifp_to_package.py --airline`), SIDs and STARs optional; RNAV and RNP approaches.
- Departures by wind with SID or runway heading, take-off clearance with the departure instruction ("climb and maintain"), RWY HDG tag; arrivals without a STAR direct to an initial approach fix.
- Macros v1 (see `claude/macro-spec.md`), `j ID` command, top control bar, panel auto-placement, ring layout, approach area.

## Known gaps
- Emergency priority handling beyond the scoring rule; realism setting (intercept angle 60/45/30, pilot call timing, glidepath checks); visibility and cloud rule for visual approaches; transport row into the window toolbar.
- SIDs: altitude and speed restrictions not flown (take-off clearance says "climb and maintain"; change to "climb via SID except maintain" when they are); heading and course legs skipped by the converter.
- RNAV: offset and curved (RF) finals skipped (Aspen, Juneau and others missing); LOC approaches not imported.
- Arrivals that reach the end of their route without a clearance fly on; no holds yet.
- No explicit visual approach code (`v27`) at runways with an ILS; no drawn approach plan for cleared aircraft.
- Parallel-approach rules are simplified approximations of the FAA rules; separation on final does not use the reduced 2.5 NM.
- Handing off two arrivals already too close is not penalised.
- Exit fixes are random, not by the airline's likely direction.
- Converter geometry verified only against Boston; spot-check a few airports.
- Settings saved under the old app name are not carried over.

## Ideas raised, not decided
- Click a runway in the Runways panel to type `j01l` for the selected aircraft; Tab to cycle `.1` / `.2` / `.3`; `i01l.2`.
- Click a radio code line to put it back on the command bar; up-arrow history.
- OWN preview of the rejoin route; predicted-conflict meeting point marker.
- Entry fixes for arrivals; destination airports for departures.
- Scoring on/off switch; timed sessions (30, 60, 90 min); smaller radio announcements.

## Traffic flow and realism
- Hub waves (departure busy spells following arrival ones); arrival sequencing aid with wake spacing; holding patterns; missed approach routing and re-sequencing; runway change prompts; visibility and cloud; departure planning strip.

## More ways for things to go wrong
- Rejected take-off, engine failure after take-off, bird strike; wrong altimeter; windshear that changes the wind; unresolved emergencies affecting other traffic.
- Dropped (14 Nov 2026): radio failure and transponder loss.

## Gameplay and feedback
- Difficulty modes; scenarios and tutorial; save and load.

## Scope and interface
- Real airspace shapes in place of the circle, minimum safe altitude areas, terrain warnings; drawn approach plan (heading → intercept → final); no transgression zone between independent parallel finals; speed-change preview and time-to-level on the arc; keyboard shortcuts for macros; click a radio line to select the aircraft.

## Controller layer
- Controller positions, handovers (facility names only), LOC approaches, "expect visual", VFR design.
- Controller and pilot voice with Apple Foundation Models: `FoundationRadioVoice` and `RadioVerifier` exist but are not wired in.

## Airports and data
- Airports outside the US only if the data can be redistributed legally.

## Parked
- Voice: text-to-speech for pilot calls, then push-to-talk recognition with a confirm chip. Needs an app bundle with microphone and speech permissions.
