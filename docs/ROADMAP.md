# flightcATCher roadmap

Status: 14 Nov 2026. Items are ordered within each group by how much they would improve the existing game. Voice (speech output and recognition) is parked until the issues and features below are settled.

## Now
- **Debug logging** (working): a switch in Settings > Debug records commands (accepted, refused, dropped), approach progress and why an aircraft has not captured its approach. Log file in `~/Library/Logs/flightcATCher/`, live panel in the app. Use it to find why some aircraft never capture an approach.
- **Approach capture**: the capture fix, the pilot's "unable to intercept" call and the "above the glidepath" call are done. Still open: the ILS auto-intercept (an ILS clearance that turns the aircraft onto the localiser by itself).
- **Departure and visual-approach test coverage on KBOS**: the old airport-specific tests are now on KBOS; add more KBOS flow tests (departure sequencing, go-arounds, handoff).

## Done recently
- MAINT button on the radial menu; radio tag column (MAYDAY, PAN PAN, EMERG, LOSS, CONFLICT, G/A, WSHEAR, REFUSED, UNABLE, HIGH); refusals carry the aircraft's callsign.
- Emergency scope marker, eight emergency kinds, pilot warnings, test spawner with delete, user manual, Dublin removed, tests ported to KBOS.

## Known gaps
- Give emergency aircraft priority handling (the scope marker is done).
- A realism setting: intercept angle limit (60, 45 or 30 degrees), how soon pilots speak up, and whether clearances are checked against the glidepath.
- Visibility- and cloud-based rule for visual approaches.
- Move the transport row into the window toolbar.

## Traffic flow and realism
- **Arrival sequencing aid**: a list of arrivals per runway in landing order, with spacing in NM or seconds, and wake-turbulence spacing (heavy ahead of light needs more).
- **Holding patterns**: holds at fixes, "established in the hold", expected-further-clearance time.
- **Missed approach routing and re-sequencing**: go-arounds follow a proper missed approach and rejoin the sequence.
- **Runway changes**: when the wind shifts, prompt the player to switch the active runway and re-clear arrivals mid-approach.
- **Visibility and cloud**: decides visual versus ILS; low-visibility procedures reduce the arrival rate.
- Parallel and crossing runways: dependent approaches, converging runways, the separation monitor taking them into account.
- Departure planning strip: the next departures, sequence and expected take-off time.

## More ways for things to go wrong
- Departure events: rejected take-off, engine failure after take-off, bird strike.
- Wrong altimeter setting.
- Windshear that changes the wind for a while, so it affects speed and the glidepath instead of only triggering a go-around.
- Emergencies that stay unresolved, with consequences for other traffic.

## Gameplay and feedback
- Scoring and an end-of-session debrief: throughput, delays, separation losses, go-arounds, missed handoffs.
- Replay a session from its seed (pairs with the debug log).
- Difficulty modes: a gentle mode with hints; a hard mode with higher rates and more events.
- Scenarios and a tutorial: a guided first approach and short authored scenarios.
- Save and load a session.

## Scope and interface
- Sector and airspace display: boundaries, minimum safe altitude areas, terrain and obstacle warnings.
- Speed-change preview like the level arc (where an aircraft reaches its target speed); time to reach the level next to the arc.
- Predicted-conflict lines between aircraft.
- Keyboard-only control and macros.
- Select an aircraft by clicking its radio line (the reverse of the existing highlight of the selected aircraft's lines).

## Controller layer (from the earlier plan)
1. Controller positions per airport: tower, approach, departure and en-route sectors, with handover points. Facility names only, no frequencies.
2. Handovers: arrivals handed in from the centre at the STAR entry, departures handed out at the SID end.
3. Later: RNAV and LOC approaches from the FAA data, "expect visual" on arrivals, VFR traffic design.

## Airports and data
- More airports outside the US only if the data can be redistributed legally.
- Spot-check converter geometry at a few airports; the converter's column positions were verified only against Boston records.

## Parked
- **Voice**: text-to-speech for pilot calls, then push-to-talk speech recognition with a confirm chip, bounded by the Foundation Models verifier rules in `docs/DEVELOPMENT.md`. Needs an app bundle with microphone and speech-recognition permissions.
