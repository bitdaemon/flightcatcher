# flightcATCher user manual

flightcATCher is a radar approach and departure control game. You sit at the scope of a busy airport, sequence arrivals onto the runway in use, release departures, and keep everything separated. This manual covers the screen, the controls, and a step-by-step tutorial for both arrivals and departures.

> A game, not a training tool. Procedures and data are approximations.

## Contents
1. [Quick start](#1-quick-start)
2. [The screen](#2-the-screen)
3. [Giving instructions](#3-giving-instructions)
4. [Command reference](#4-command-reference)
5. [Tutorial: your first arrival](#5-tutorial-your-first-arrival)
6. [Tutorial: your first departure](#6-tutorial-your-first-departure)
7. [Wind and runways](#7-wind-and-runways)
8. [Random events](#8-random-events)
9. [Scoring and the debrief](#9-scoring-and-the-debrief)
10. [Settings](#10-settings)
11. [When something goes wrong](#11-when-something-goes-wrong)
12. [Glossary](#12-glossary)

---

## 1. Quick start

1. Launch the app. Boston (KBOS) loads by default. Change airport from the airport list (search by city, name, ICAO or IATA code); your choice is remembered.
2. Check the **Airport info** panel: it shows the wind and which runways are open. Only one direction of each runway is in use, the one facing the wind.
3. Aircraft appear on the scope. Click one to select it, type a command in the command bar (for example `d70 s180`), and press Enter.
4. Arrivals: bring them down and line them up, clear the approach, then hand them to the tower. Departures: line up, clear for take-off, climb to the plan level, then hand them off.

Press Cmd+, for Settings, and use the Commands and scoring panel for a cheat sheet at any time. Your score is in Airport info; press **END** (top right) to finish the session and see the debrief.

---

## 2. The screen

### The scope
- **Drag** to pan; **pinch** or the **+ / -** buttons to zoom. Esc clears the selection.
- Each aircraft has a **tag** (callsign, altitude, speed and so on). Drag a tag to move it. Settings can declutter tags.
- **Velocity vectors**, **range rings** and an optional **compass ring** help you judge distances and turns.
- **Warnings**: predicted conflicts (amber) and losses of separation (red) are flagged. The prediction follows each aircraft's route, turning at its fixes; aircraft on vectors are projected straight on.
- **Departures waiting** at the holding point or lined up show only their symbol. Their tag appears once you clear them for take-off. Right-click the symbol, or use the strip, to work with them.
- **Departure tags** show the exit fix: `RWY HDG → BCE` while still on runway heading (amber once airborne without a vector), `EXIT → BCE` after. Select a departure to see a dotted line to its exit fix.
- With an aircraft selected, its **remaining route** is drawn, and a small **arc** shows where it will reach its target altitude at its current speed. Hover a level in the ALT picker to preview where that level would be reached.
- Aircraft you have **handed over** to the tower are greyed out.
- **STAR**, **SID** and **APP** in the control bar show or hide all STARs, SIDs and approaches; Settings > Layers switches them individually, and fixes too.

### The control bar
Across the top: the airport and clock, **Pause / Run**, a speed slider from **1x to 20x**, the **+ / -** zoom buttons, the airport picker, the **STAR / SID / APP** layer toggles, one button per panel, the settings gear and, after a divider, **END**. Pause freezes the simulation, which is useful for planning a vector. END pauses and opens the debrief (see [section 9](#9-scoring-and-the-debrief)).

### Panels
Panels float over the scope. Drag a title bar to move, use the pin to lock one in place, resize from the corner. Show and hide them in Settings > Panels, which also has Reset layout.

| Panel | What it shows |
|---|---|
| **Aircraft** | Strips for arrivals and departures with the last instruction given. Departures show their plan level and handoff level. `...` means the pilot has not yet complied. Handed-over aircraft shrink to a greyed line. |
| **Radio** | Your calls, pilot readbacks and system notices, colour-coded by speaker and importance (red emergencies, amber go-arounds and refusals, green good news). Under each of your calls, a dim line shows it as you would type it (`> aal123 d70 s180`); a chain appears once, on its first call. With an aircraft selected, all its calls are highlighted. |
| **Airport info** | In sections: the airport (elevation, transition altitude, open runways with head and crosswind, closed runways with the reason); the wind, its source (real METAR or random) and the next update; the current traffic rates (TRAF); the score (SCORE with multiplier and grade, LAST change); the separation monitor. |
| **Runways** | A zoomed-in runway chart. Green: free. Yellow: an arrival is cleared to land there. Red: a take-off or landing is using it. |
| **Commands and scoring** | The command cheat sheet and the scoring table. Resizable and scrolling. |
| **Debug log** | Only when enabled in Settings > Debug. |

---

## 3. Giving instructions

There are three ways, and they do the same thing. Use whichever feels quickest.

### The command bar
Type an optional callsign followed by one or more codes, then press Enter.

- `ein d70` sends one command to EIN...
- `ein d70 s180 h270l` chains three commands in one line.
- With an aircraft selected you can leave out the callsign: `d70 s180`.
- Press **Tab** to complete a callsign. Esc clears the line.

### The radial menu
Right-click an aircraft. A ring appears with **HDG, ALT, SPD, DCT, APP** and **HO**, and a small outer arc with **XNG, MAINT, OWN, MAC** and **COL**. OWN is "resume own navigation" (see `own` below); MAC runs a macro. MAINT tells the aircraft to maintain its present heading, altitude and speed; it cancels a route, a crossing, an expedite and an approach still being intercepted, and is refused once the aircraft is established on the approach. Departures on the ground get **LUP** and **T/O** instead of the approach options.

- Pick a value (a heading, an altitude, a speed, a fix) and it is collected as a **chip**. Pick several, then press Enter to send them together. Esc backs out.
- **HDG**: point and click on the scope. Hold Option to turn the other way.
- **ALT**: a departure's flight-plan level is marked with a star and an outline, so you don't need to check the strip.
- **APP**: a list opens beside the aircraft, one line per open runway: first the ILS clearance (VIS for a runway without an ILS), then up to three approaches to join, with the distance in NM to each one's first fix. An approach that starts at a fix already on the aircraft's route comes first and is marked •. Pick one; it works at any zoom, which helps at airports with many parallel runways. The buttons on the scope still work too.
- **COL** sets the colour of that aircraft's marker.

### Strips and buttons
Click a strip to select an aircraft. The ILS and VIS buttons do the same as `i` followed by the runway.

### Pilots answer back
Pilots read back every instruction after a short delay of a few seconds, so don't expect an instant turn. They refuse what they cannot do, and the reason appears in the Radio panel: "Unable: ...". Common refusals are a closed runway, a level below the minimum altitude, a speed outside the aircraft's range, or a climb above its ceiling.

---

## 4. Command reference

The number after `d` or `c` is in hundreds of feet. Above 5,000 ft it is a flight level.

| Code | Example | Meaning |
|---|---|---|
| `d` | `d70` | Descend to 7,000 ft |
| `c` | `c120` | Climb to 12,000 ft (FL120) |
| `h` | `h270` | Fly heading 270 by the shorter turn |
| `hNNNl` / `hNNNr` | `h270l` | Turn left / right to the heading |
| `s` | `s180` | Speed 180 kt |
| `i` | `i27` | Cleared ILS approach to the runway (a runway without an ILS gets a visual approach) |
| `j` + runway | `j01l`, `j01l.2` | Join the best approach to runway 01L for this aircraft (one starting on its route, else the nearest first fix); `.2`, `.3` pick the next choices. The preview lists them as you type |
| `j` + ID | `j r01ly.welet` | Join a named approach: direct to its first fix, fly it, cleared (I = ILS, R = RNAV, H = RNAV RNP) |
| `p` | `p kerav` | Proceed direct to a fix. `p fixa fixb` goes through each in turn. `p exit` sends a departure to its exit fix |
| `x` | `x kerav 50` | Cross a fix at 5,000 ft (the fix must be on the route) |
| `m` | `m` | Maintain present heading, altitude and speed. Cancels route, crossing, expedite and an approach still being intercepted |
| `own` / `rn` | `own` | Resume own navigation: back onto the assigned STAR, SID or direct-to-fix route at the next fix after the nearest part of it; a departure then continues to its exit fix |
| `mac` | `mac appr`, `mac-` | Run an airport macro on the aircraft / stop it |
| `lu` | `lu` | Departure: line up and wait |
| `to` | `to` | Departure: cleared for take-off, from the hold or lined up |
| `ho` | `ho` | Handoff (conditions below) |
| `!` | `d50! h270l!` | Add to a descent, climb, turn or speed change to expedite it |

Examples of chains: `ein d70 s180 h270l` (descend, slow and turn), `ryr c120 p kerav` (climb and go direct), `rpa5601 s180 d30 j01l` (slow, descend and join the best approach to 01L).

**Limits.** Controllers can assign altitudes down to the airport's floor (field elevation plus 2,000 ft, rounded up to a whole thousand). An aircraft already cleared for the approach may go down to field elevation plus 1,000 ft, rounded down. Each type has its own speed range and ceiling.

**Handoff rules.**
- A **departure** can be handed off once it is above its handoff level and cleared to its plan level.
- An **arrival** can be handed to the tower once it is established on the localiser and no more than 300 ft above the glidepath. It stays on the scope, greyed, until it lands.

---

## 5. Tutorial: your first arrival

Goal: bring one arrival from the STAR to a landing.

### Step 1. Know the runway in use
Open the **Airport info** panel. Note the open runways. Only these accept approaches, and the closed ones tell you why ("runway 27 in use", "tailwind", "crosswind"). Use an open runway.

### Step 2. Pick an arrival
Arrivals appear on STARs and are listed in the Aircraft panel. Click one. Its route is drawn on the scope and its strip shows its altitude, speed and last instruction.

### Step 3. Descend and slow down
Give it a descent and a sensible speed, for example:

```
ein d70 s220
```

Pilots read back after a few seconds. Aim to be at 3,000 to 4,000 ft and about 180 to 200 kt by the time you turn it toward the runway. Watch the other traffic: keep aircraft at least 3 NM or 1,000 ft apart (the separation monitor warns you).

### Step 4. Vector it onto the extended centreline
Turn the aircraft so it flies toward the extended runway centreline and meets it at an angle. For an aircraft to **capture** the localiser it must be:

- between **2.5 NM and 30 NM** from the runway threshold (no later than that: inside 2.5 NM it is too late);
- heading within **60 degrees** of the runway course;
- **closing** on the centreline and close enough that its turn will end on it.

A good intercept is 30 to 45 degrees to the course, 8 to 12 NM out, at about 3,000 ft. For example, with runway 27 (course about 270) from the north: `ein h240l` puts it on a heading that crosses the extended centreline. The runway chart and the drawn approach path show where the centreline is.

### Step 5. Clear the approach
Once the aircraft is lined up for an intercept, give the clearance:

```
ein i27
```

A runway with an ILS flies the localiser then the glideslope; a runway without one gets a visual approach built from the runway itself. You can also use the APP list on the radial menu or the ILS and VIS buttons. To fly a published approach from its first fix instead (RNAV or ILS with a transition), use `ein j27` for the best one for this aircraft, or `ein j r27.aybee` for a named one. The pilot reads back, then **intercepts** and the strip changes to show the phase.

You may clear the approach slightly early: the aircraft keeps flying its heading until it reaches the localiser, then turns on. If it never turns, see [section 11](#11-when-something-goes-wrong).

### Step 6. Make sure it is stable
Inside 2.5 NM the aircraft must be on the glidepath and slower than 190 kt, or it **goes around** automatically ("unstable", "not established", or too high). Reduce speed with `s180` early, and descend to be at or below the glidepath when it captures. The aircraft limits its own speed along the final approach: slower inside 8 NM, slower again inside 5 NM.

### Step 7. Hand over to the tower
When the aircraft is established (on the localiser or the glideslope) and not more than 300 ft above the glidepath, send:

```
ein ho
```

It greys out on the scope and strip and lands by itself. The Runways panel turns red while it lands. Landing is complete when it disappears from the scope.

### If it goes around
A go-around is announced on the Radio panel (amber). The aircraft climbs and flies the missed approach on its own. Re-vector it for another approach, or hand it back into the pattern with a heading and altitude.

### If you vectored it off its route
Send `own` (or OWN on the radial menu) and it rejoins its STAR at the next fix ahead.

### Airports without STARs
Many airports have no STARs in the FAA data. Arrivals there are handed in at the edge of the approach area heading direct for an initial approach fix ("DCT FIX" on the strip). Vector them, or clear them for an approach; an arrival that reaches its fix with no clearance flies on and costs points.

---

## 6. Tutorial: your first departure

Goal: take one aircraft from the holding point to the handoff.

### Step 1. Find a departure
Departures wait at the **holding point** of an open runway (up to three per runway) and announce "ready for departure". They appear in the Aircraft panel. Click one. Its strip shows the runway, the assigned SID (if the runway has any), its flight-plan level, its handoff level and its **exit fix**. On the scope they show only a symbol until cleared for take-off.

### Step 2. Check the runway
Look at the **Runways** panel. Red means a take-off or landing is using the runway. Line-up and take-off are refused while the runway is occupied ("runway 27 is occupied"), and take-off is refused when an arrival is within 4 NM on final ("EIN is on final, 3.2 NM"). Yellow means an arrival is cleared to land there, so plan the gap before you release the departure.

### Step 3. Line up
With the departure selected:

```
lu
```

(Or use the radial menu: LUP.) The aircraft taxis onto the runway and waits.

### Step 4. Clear for take-off
When the runway is free and the final is clear:

```
to
```

You can clear for take-off straight from the holding point without lining up first; the same runway checks apply. The clearance includes the departure instruction: "BOFUM one Alfa departure, climb and maintain three thousand feet, runway zero four right, cleared for take-off" with a SID, or "fly runway heading, climb to three thousand feet, ..." without one. The aircraft accelerates, rotates and climbs; its tag appears.

- **With a SID** it follows the SID automatically and climbs to its initial altitude.
- **Without a SID** it flies runway heading (RWY HDG in its tag, amber once airborne) until you give it a heading, a direct, or `p exit` to its exit fix.

### Step 5. Climb to the plan level
The ALT picker highlights the flight-plan level with a star, so you can pick it without checking the strip. Or type the climb, for example:

```
ryr c120
```

Keep it clear of arrivals; the initial altitude is low, so cross-traffic is your main concern in the first few minutes. Use `x fix level` or a heading to separate it from an arrival flow.

### Step 6. Hand off
Once the aircraft is above its **handoff level**, its target altitude is the plan level, and ideally it is heading for its exit fix, send:

```
ryr ho
```

The aircraft leaves your area. If the handoff is refused the radio log says why: "climbing through 3,200 ft, handoff at 4,000 ft" or "not cleared to its plan level". Handing off a departure heading for its exit fix (within 30°, or routed through it) earns a bonus; more than 90° away costs points.

### Running departures and arrivals together
- Leave a gap on the runway. A departure that is lined up or rolling when an arrival is within 1.5 NM of the threshold makes the arrival go around ("runway occupied"), and a take-off clearance is refused if an arrival is within 4 NM on final.
- Send departures off a different runway from arrivals where the airport has several.
- A good rhythm: one departure for every one to two arrivals, released while the next arrival is still 6 to 8 NM out.

---

## 7. Wind and runways

- The runway in use is chosen from the **mean wind**: the end facing the wind. Closures use the **gusts**. The limits are 5 kt tailwind and 25 kt crosswind.
- Runways close and reopen with hysteresis, so a small wind shift does not flip the active runway.
- The wind can be **live** (NOAA Aviation Weather Center METAR, refreshed every 15 minutes, with a notice after each fetch), **random** drifting, or **fixed**. Settings > Weather chooses. If a METAR fetch fails, the wind drifts randomly.
- The Airport info panel shows which source is active and a countdown to the next update.
- When the active runway changes, procedures for the closed runway become unavailable. An aircraft already inbound for that runway is refused the approach with "closed": give it another runway or vector it round.

---

## 8. Random events

A configurable share of arrivals will have an event:

| Event | What happens |
|---|---|
| **Pilot go-around** | Pilot's decision on final (not stable, no visual references, not comfortable). Shown amber. |
| **Windshear** | A windshear go-around on final. |
| **Emergency** | One of eight kinds, declared a few minutes after entering the area: engine failure, medical emergency, low fuel, hydraulic failure, smoke in the cabin, bird strike, loss of pressurisation or an unsafe landing gear indication. The pilot calls MAYDAY or PAN PAN in red, and the aircraft gets a red double ring and a red tag on the scope, a MAYDAY or PAN PAN line in its tag, and a red badge on its strip. |

Settings > Events sets each percentage (defaults 3%, 2% and 2%). Set them to 0 for a calm session.

---

## 9. Scoring and the debrief

A session starts when the airport loads. The score, its multiplier, the grade and the last change are shown in Airport info; changes of 100 points or more are also announced on the radio.

| Gains | Points |
|---|---|
| Arrival handed to the tower, established | +100 |
| Arrival lands | +20 |
| Efficient arrival (up to 1.2 times its clean time; less up to 2 times) | up to +30 |
| Departure handed off | +80 |
| … cleared to its plan level | +20 |
| … heading for its exit fix (within 30°, or routed through it) | +20 |
| Emergency aircraft landed (extra) | +30 |

| Penalties | Points |
|---|---|
| Loss of separation | −300, and −50 every 10 s it lasts |
| Departure leaves the area without a handoff | −150 |
| Go-around you caused (unstable, too high, too fast, runway occupied) | −100 |
| Arrival reaches the end of its route with no clearance | −50 |
| Emergency given no instruction for 2 minutes | −50 |
| Departure handed off more than 90° from its exit | −30 |
| Runway-heading departure not vectored by 10 NM | −20 |
| Conflict alert (predicted loss) | −10 |
| Instruction refused by the pilot | −5 |
| Each minute a departure waits at the hold after 3 minutes | −1 |

Not your fault, so free: pilot's-decision and windshear go-arounds, and any loss of separation between two arrivals that are both with the tower.

**Separation.** 3 NM or 1,000 ft. Two aircraft both established on approaches to **parallel runways** use the parallel rules instead: no minimum between runways 4,300 ft or more apart (independent approaches), 1.5 NM diagonal between closer ones (dependent). While either is still intercepting, the normal minimum applies, so keep 1,000 ft between them until both are established.

**Multiplier.** Score = points × a multiplier from the average traffic rate, a Moderate or Lively variation, random events, live weather and gusts. Busier sessions are worth more.

**Grade.** Points against the most the aircraft you handled could have earned: A 85% and over (Supervisor), B 70% (Senior controller), C 50% (Controller), D 30% (Trainee), E below (Removed from position). One loss of separation caps the grade at C, three give E.

**END and the debrief.** END at the top right pauses the game and shows the debrief: the score and grade, a breakdown by category, throughput and counts, charts of score and traffic over the session, the worst moments with times, the best and worst arrival for efficiency, and this airport's best five scores. Then:
- **Resume** carries on; points count again.
- **New session** starts again at the same airport.
- **Replay this seed** starts again with exactly the same traffic (the seed is fixed in Settings > Traffic) so you can beat your score.
- **Quit** closes the game. Sessions with at least one aircraft handled are already saved in the best-scores table.

---

## 10. Settings

Open with Cmd+, or the gear button.

- **Display**: text size (Cmd+= larger, Cmd+- smaller, Cmd+0 reset), colour scheme, compass, tag options.
- **Layers**: fixes, STARs, SIDs and approaches.
- **Panels**: show or hide, reset layout.
- **Traffic**: arrivals and departures per hour as a **Low–High range** each (set both equal for a fixed rate), **Variation** (Steady: a new rate every 20–30 min; Moderate: 8–15; Lively: 3–8 with bigger jumps), presets (Quiet, Moderate, Busy, Rush and others), the approach area radius and ceiling, aircraft categories and types, optional fixed seed to repeat a session. The window can be resized and the tabs scroll.
- **Weather**: live, random or fixed wind.
- **Events**: go-around, windshear and emergency percentages.
- **Debug**: the optional debug log and the test spawner (see below).

---

## 11. When something goes wrong

**Radio tags.** Notable calls carry a tag column between the callsign and the message: MAYDAY, PAN PAN and EMERG (red), LOSS and CONFLICT (separation), G/A (go-around), WSHEAR, REFUSED (a clearance the simulation will not accept, such as a closed or occupied runway), UNABLE (the pilot cannot comply) and HIGH (above the glidepath). Red tags are urgent, amber ones are warnings.

**The pilot says "unable to intercept" or "above the glidepath".** These are the pilot's way of telling you the clearance cannot work yet. "Unable to intercept the localiser… we're heading 090, we'll need a vector" means you need to give a heading that brings the aircraft within 60° of the course and closing on the centreline. "We're above the glidepath, request lower" means it is more than 300 ft above the glidepath on the localiser, so give it a descent (down to the approach floor) or it will not capture the glideslope and will go around at 2.5 NM.

**The aircraft does not turn onto the approach.** The clearance is accepted but capture needs the aircraft to be 2.5 to 30 NM out, within 60 degrees of the course, closing on it, and near enough to the centreline. If you cleared it late or at a bad angle it will stay on its heading. Send a new heading to set up a better intercept, then clear it again.

**A command was refused.** Read the Radio panel: the reason is given ("Unable: ..."). Fix it and resend. A refusal costs 5 points.

**Orange conflict warnings.** These are predictions: the two aircraft would lose separation within two minutes if they carry on as they are (along their routes, or straight on when on vectors). Give one of them 1,000 ft or a turn now. Each new warning costs 10 points.

**Nothing seems to happen after a command.** Pilots comply after a short delay. The strip shows `...` until they do.

**An aircraft keeps going around.** It is probably too fast or too high at 2.5 NM. Slow to 180 kt and descend earlier.

**I can't find an approach / a runway is closed.** Check the Airport info panel. Only the runway facing the wind is in use.

### The test spawner
For reproducing a situation, switch on **Settings > Debug > Show the test spawner panel**. In the panel, choose a callsign (blank gives TST1, TST2 and so on), a type, and a position as a bearing and distance from the airport centre or a runway threshold. Alternatively click "Place by clicking the scope" and then click the scope. Then set heading, altitude and speed (all true headings) and press Spawn aircraft. The **Final approach** presets put an aircraft on the extended centreline of a runway, 5 to 20 NM out at 3,000 ft and 190 kt, heading for the runway. The new aircraft has no route, flies what you set until you instruct it, and is selected for you. It is a normal arrival after that.

### The debug log
For hard cases, turn on **Settings > Debug**. A Debug log panel appears and a log file is written to `~/Library/Logs/flightcATCher/`. It records commands (accepted, refused, dropped), approach progress and the exact reason an aircraft has not captured ("heading 140 is 95 degrees off the course 270 (limit 60)", "inside the 2.5 NM gate", and so on), plus a warning when an intercept stalls. Use the "selected aircraft only" filter, or copy the last 200 lines to share when reporting a bug.

---

## 12. Glossary

- **ILS**: instrument landing system. Localiser (lateral) and glideslope (vertical).
- **Localiser / centreline**: the line extended from the runway.
- **Established**: on the localiser (or glideslope) of the approach.
- **STAR / SID**: standard arrival / departure route.
- **Fix**: a named point on the scope.
- **Vectors**: headings you give to steer an aircraft.
- **Expedite**: a faster than normal descent, climb, turn or speed change (`!`).
- **Handoff**: passing the aircraft to the next controller (tower for arrivals, centre for departures).
- **Go-around**: aborted landing; the aircraft climbs and flies the missed approach.
- **Plan level**: the cruise level a departure expects (shown on its strip).
- **Exit fix**: where a departure leaves your area: the end of its SID, or a fix near the area edge picked for it.
- **Resume own navigation**: return to the assigned route after vectors (`own`).
- **RNAV / RNP**: approaches flown by GPS waypoints instead of a radio beam (IDs start with R or H).
