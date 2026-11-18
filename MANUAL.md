# Snipe Sim: Union Reservoir

A Snipe dinghy racing simulator set on Union Reservoir in Longmont, Colorado, sailed under the
Union Sailing Club's 2026 series sailing instructions. Built with Godot 4.7.2 (GDScript).

## Play

Double-click `play.bat` (it starts borderless full screen), or run Godot with this folder:

```
"%USERPROFILE%\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe" --path C:\Users\dm\snipe-sim
```

Pick the wind, fleet (10 boats at most, yours included), course and realism on the start menu
and press **Go sailing**. You start five minutes before the gun, reaching in toward the committee
boat with flag L up for check-in.

### Simulator (the default) and Assisted

Simulator mode gives you what a Snipe sailor has:

- **Instruments:** a compass and a watch, which is all Snipe class rules allow, plus boat speed
  in knots beside the compass (Doug asked for it, 18 Nov; a real Snipe racing wouldn't have it).
  There is no wind readout and no trim advice. You read the jib telltales, the main leech
  telltales, the cassette tape and yarn tied on the shrouds and the darker puffs on the water (no masthead wind indicator: Doug, 18 Nov, they aren't allowed). The I key turns on coach
  numbers (speed, true and apparent wind, VMG, trim hints) while you learn.
- **Controls:** you steer with the tiller, not the bow: push it to port and she turns to
  starboard. The tiller stays where you leave it. Pulling the main in gets slower as the load
  builds; letting it out is quick. You trim the main and set the rig: outhaul, cunningham,
  vang, traveler, the mast pusher/puller, jib halyard, jib lead and centreboard (Y shows them
  all; see Rig tuning below). As in a real Snipe, your crew trims the jib, handles the whisker
  pole and hikes. Touch any of their controls and you have it; the pause menu hands it back.
- **The chart (M):** shows the shore, the marks, the course and your own position. It doesn't
  show puffs, laylines or the other boats; look around for those.
- **Standings (Tab):** show finishers only.
- **Capsizes:** it takes the crew about 20 seconds to right her, and she sails slower until
  the water is bailed out.
- **Chop:** builds with the wind and with the fetch of open water upwind, so the far shore is
  bumpier than water close under a windward shore.

Assisted mode gives the crew the jib, hiking and rig, turns on the full instruments and map aids,
highlights the next mark, and lets the helm centre itself.

| Keys | |
|---|---|
| A / D, ← / → | push the tiller to port / starboard: the bow swings the other way, as on a real Snipe (Alt for fine adjustments; menu: Steering has an arcade point-the-bow option) |
| Left mouse drag | your hand on the tiller extension and the mainsheet: sideways moves the tiller, drawing back pulls the main in, pushing forward lets it out |
| Space | tiller back to the centreline (in Simulator it stays wherever you leave it) |
| W / S, ↑ / ↓ | pull the main in (slower as the load builds in a breeze) / let it run out |
| Q / E | ease / sheet the jib yourself (J gives it back to the crew) |
| Shift / Ctrl | hike out / move in yourself (H gives it back to the crew) |
| Z / X | vang: ease / on (slack until hiking hard, then take the slack out) |
| V / F | outhaul: ease / tighten (tight upwind, eased 2-3 in downwind) |
| L / O | cunningham: ease / pull on (loose until overpowered) |
| [ / ] | traveler: drop to leeward / back to the centre |
| , / . | mast at the deck: pull aft / push forward (guide marks 3/8 in aft, neutral, 3/8, 3/4 and 1 in forward) |
| - / = | jib halyard: ease / tighten (rig tension; right off dead downwind) |
| ; / ' | jib lead: aft / forward (top luff telltales break first: forward) |
| K | auto main on/off |
| B, U / N | daggerboard: B switches between down and raised to its limit band; U raises it, N lowers it |
| G | whisker pole: set it (running), stow it, or swap it to the new side after a gybe |
| Y | rig panel: every control, its setting and keys, and what the sails look like |
| R | crew rights the boat after a capsize (once they've reached the board) |
| C | camera: helm, start line, overhead, chase (right-drag to look, wheel to zoom) |
| M | chart |
| I | coach numbers |
| Tab | finishers (live standings in coach or Assisted mode) |
| T | time warp x1 / x2 / x4 / x8 |
| Enter | after you finish or retire, skip ahead to the results |
| F1 | help card |
| Esc | pause: restart, retire, assists, menu |

The helm camera is the skipper's eye on the side deck at the back of the cockpit, looking a
little inboard and down, toward the jib, with the cockpit in sight. The sailors themselves aren't
drawn: their weight (150 kg together) and how far out they sit are in the physics, and the eye
moves with the skipper: out to the deck edge and leaning out as you hike, across in a tack, and
down when the boom comes over.

### PS5 controller (or any pad with the standard layout, such as an Xbox pad)

| Pad | |
|---|---|
| Left stick | the tiller handle: where the stick is, the handle is (push to port, the bow goes to starboard); let go and it centres |
| R2 / L2 | pull the main in / ease it; how hard you squeeze sets how fast. It comes in slower under load and over the last of it to the centreline, and the trigger rumbles harder as the boom gets close |
| L1 / R1 | ease / sheet the jib |
| Circle / Square | hike out / move in |
| D-pad up / down | daggerboard raised to its limit band / down |
| D-pad left / right | vang ease / on |
| Right stick | look the way you push it: left, right (right round to the stern at full stick), up, down; let go and the view comes back ahead |
| Cross | camera |
| Triangle | whisker pole while racing; right a capsized boat; after the finish, skip to the results |
| R3, L3 | chart, time warp |
| Touchpad, Create, Options | coach numbers, help, pause |

The rest of the rig (outhaul, cunningham, traveler, mast, halyard, lead) and the finishers (Tab) are on
the keyboard; the pad keeps the controls you need while sailing. The pad rumbles: a buzz that
builds with the load on the rudder, a flutter when the main luffs, R2 stiffening as you pull the
main in toward the centreline (harder still when the sail is loaded, and a thump at the stop),
and a thump for a capsize, a collision or running aground. Godot can't set the PS5 pad's
adaptive trigger resistance, so the rumble motors stand in for it. The lightbar takes your hull
colour. Menus work with the D-pad and Cross. In the replay: Triangle plays and pauses, D-pad
left / right jump 5 s, L1/R1 jump 30 s, Cross changes camera, R3 picks the next boat. The HUD
and the help card show pad or key controls, whichever you used last.

### Debrief and replay

Every race you sail is recorded. The results sheet has a Debrief and replay button that shows:

- the start: where your bow was at the gun, how fast you were going, how late you crossed, and
  how far behind a perfect start you were 30 s in
- steady sailing by wind strength (light, medium, fresh, heavy) and sector (upwind, reaching,
  downwind), with the rest of the fleet's VMG beside yours
- every tack, gybe and rounding, with the distance it cost and the time bin where most of it
  went. Moves too close to another move are listed but not scored.

Watch replays from 12 s before a move. In the replay, Space plays and pauses, T changes speed,
A/D or the arrows jump 5 s (Shift for 30 s), C changes camera, Tab follows the next boat and Esc
goes back to the debrief. The replay shows the mean wind but not the puffs.

Sessions are saved in `%APPDATA%\Godot\app_userdata\Snipe Sim- Union Reservoir\sessions\`: a CSV
of every boat five times a second, and a JSON file with the events, course, line, wind and
results (the start menu's ashore rig is in it, under cfg). Since 17 Nov the CSV also has every
rig control in the guide's units, the pole, and what the shape came to (main twist, mast bend,
forestay sag), so the replay shows them; older sessions still load. A 30-minute race with 10
boats was about 13 MB before those columns and is now about 18 MB (estimated from the column
count, not measured).

## The place

- Shoreline: OpenStreetMap way 43241479 "Union Reservoir" (© OpenStreetMap contributors,
  ODbL), fetched once from overpass-api.de and kept in `tools/union_osm_raw.json`. The water is
  about 2.4 km north–south and 1.9 km east–west, 692 acres, at 1,511 m, so the air is about 16%
  thinner than at sea level and the sails make correspondingly less force.
- Marks 1–9: the SIs only say the marks sit "approximately as shown" on the Appendix A reference
  map. `tools/build_lake.gd` fits that map to the OSM shoreline and reads where the numbers are
  painted. Mark 1 is in the middle; marks 2–9 ring it about 420–475 m out, like a compass rose.
- The USC dock is on the south-east shore, where the reference map puts it.

## The rules (USC 2026 series SIs)

- Check-in (SI 12): while the RC flies flag L, sail past the RC boat's transom on starboard.
  A boat that never checks in and doesn't finish is scored DNC.
- Appendix U audible start (SI 10.1): Attention signal at 3:00 with the class flag (yellow
  Portsmouth for summer and fall, green LMS for the spring series), then 2:00, 1:30, 1:00, 0:30,
  0:20, 0:10 and 5-4-3-2-1 before the long start horn.
- The start and finish line runs from the RC boat, moored to mark 1, to an orange pin (SI 11).
- The course goes on the RC's board at the Attention signal (SI 8): marks in order, `G` for
  the start/finish line used as a gate, and `F` for the finish. Every mark is rounded to port.
  The RC picks the windward mark as the ring mark most directly upwind of mark 1.
- Over the line at the gun: flag X and one sound. Get your whole hull back behind the line, then
  start. X comes down when everyone is back or after four minutes. After five minutes a boat that
  hasn't started is DNS (SI 10.3).
- Penalties (SI 14, RRS 44.1): touching a mark costs one turn, and a Part 2 foul costs two. The
  game calls rule 10 (port/starboard), rule 11 (windward boat), rule 12 (clear astern) and rule 13
  (tacking). One turn is a 360° with one tack and one gybe. Finishing with a penalty still owed is
  scored DSQ.
- Boats finishing more than 20 minutes after the first finisher are TLE (SI 15.1).
- Results show places and status codes. The day tally uses simple low-point scoring. The club's
  CHIP3 series scoring isn't modelled.

Not modelled yet: mark-room (rule 18), obstructions, protests and arbitration, the leeward gate,
flags C, S and AP.

## The boat

`scripts/boat_sim.gd` is a four-degree-of-freedom model (surge, sway, yaw, heel) at 120 Hz:

- The main, jib, centreboard and rudder are lifting surfaces with lift and drag against angle of
  attack, fed by the local flow (apparent wind heeled onto the sail plane, water flow including
  yaw rate at each foil).
- A hard-chine hull resistance curve, heeled-hull drag, weather helm when heeled, and windage
  ahead of the board so a stalled boat falls off.
- The crew's weight (150 kg for the two) fore and aft as well as out to the side. Moving them
  1 m trims her about 2 degrees (worked out from the hull's lines). They sit forward in light
  air (bow down about half a degree, transom clear), on their usual seats around hull speed, and
  aft once she planes; off the best trim costs drag, and trimmed bow down the hull grips further
  forward, for a touch more weather helm. Hiked out, they also make her slower to roll and to
  turn. The trim numbers are estimates.
- Crew hiking to about 1 m outboard. The hull and rig's righting arm starts like a GM of about
  0.66 m, peaks at about 30° as the leeward rail goes under, and is gone by 69°. The wide side
  decks keep the cockpit edge above still water until she's nearly over, so water comes in with
  the waves: past about 31° in a breeze with chop, not until about 50° in flat water. It runs to
  the low side and holds her down, and the boat gets heavier. Heeled toward the boom far enough
  (about 32° on a
  beam reach), the boom end digs in and drags. She is capsized at 80°, when the sails are on the
  water. Righting takes about 20 seconds, then the water drains through the bailers as she
  moves. These are estimates for a Snipe, not measurements; `tests/capsize_test.gd` checks she
  goes over when overpowered and nobody eases (a puff close-hauled with the sheets cleated, the
  crew not hiking in a breeze, the crew hiked out when the sheets are let go) and stays up when
  she is sailed well.
  In irons the crew backs the jib.
- Sail shape: each sail is three horizontal strips with its own depth, draft position and
  twist, set by the rig controls (see Rig tuning below). Easing the sheet to depower costs
  flogging drag, so flattening and twisting off beat easing in a breeze.
- Chop from fetch adds resistance upwind.
- Snipe numbers: 4.72 m long, 1.52 m beam, 172 kg hull, 8.8 m² main and 3.0 m² jib, 150 kg of crew.

Speeds from `tests/polar_test.gd`, with the crew setting the rig and the pole: upwind velocity
made good is about 2.2 kn in 6 kn of wind, 3.5 kn in 10 kn and 4.0 kn in 14 and 18 kn, at 38–46°
to the true wind, inside the 38–46° expected of a dinghy. Beam reaching gives about 4 kn in 6 kn
of wind and 9.4 kn in 18 kn; running with the pole, 2.6 kn in 6 kn and 6.4 kn in 18 kn. The crew
changes from the upwind tune to the reaching tune as she cracks off between 55 and 75° true, and
on to the running tune between 120 and 160°. These are a model, not measured Snipe polars.

Before the rig model (16 Nov) the same test gave 2.4, 3.6, 4.4 and 4.7 kn upwind at 34–42°. The
upwind numbers came down mainly because the sails' centre of effort is now worked out from their
shape (about 3.1 m above the water, against a fixed 2.35–2.75 m before), so she is overpowered
sooner, and because the jib's twist takes some angle off it. Downwind she is faster, with the
pole.


The race committee's horn is a synthesized canned air horn: a reed tone near 415 Hz with a
flared-horn blare between 1 and 4 kHz, a second slightly sharp reed for the rasp, a pitch blat at
the start, and slap-back echoes off the water. It sounds from the committee boat, fading with
distance and arriving late at the speed of sound. `tests/horn_export.gd` writes it to WAV files.

The wind (`scripts/wind.gd`) oscillates and drifts, bends a few degrees across the reservoir,
drops off near a windward shore, and carries puffs and lulls that drift downwind. Puffs show as
darker water. Boats to windward throw a wind shadow.

## Rig tuning

The controls are the ones the North Sails Snipe tuning guide talks about. Numbers from the guide
are marked (guide); every other number is an estimate for a Snipe, not a measurement, and is
marked (est) in `scripts/boat_sim.gd` under "Rig and sail shape". `tests/tune_test.gd` checks
that the guide's directions come out of the physics.

Set ashore, on the start menu's right-hand panel:

| Setting | Choices | What it does |
|---|---|---|
| Mast | soft, medium, stiff | how much it bends under load (est: 0.8, 1 and 1.25 times as stiff) |
| Spreaders, mast to shroud | 16 1/4 to 17 1/4 in (guide 16 3/4) | longer pushes the middle of the mast to leeward under load, shorter lets it go to windward (guide). To leeward it opens the top of the main and sags the forestay. This mast stands straight at 16 3/4 (est) |
| Spreaders, tip to tip | 28 3/4 to 29 3/4 in (guide 29 1/4; 29 3/4 in heavy air or with a heavier crew) | more is a stiffer mast fore and aft (guide; est 10% per half inch) |
| Shrouds, aft of the stem | 70 to 72 in (guide: no further forward than 70) | further aft is a stiffer mast, for when power is lacking (guide; est 3% per half inch) |
| Mast rake | 4 in forward to 4 in aft of the base, at the masthead | moves the sails' centre of effort aft or forward. Aft gives more weather helm (guide: rake aft for lee helm, forward for weather helm). The guide gives no rake number, only "neutral helm with the boat hiked flat", so the base here is the rake that gives a light weather helm, about half a degree of rudder, hiked flat in 10 kn. About 0.07° of rudder per inch |

Set afloat (the rig panel, Y, lists them all with their settings in the guide's units):

| Control | Keys | Range | What it does in the sim |
|---|---|---|---|
| Mainsheet | W / S, R2 / L2 | | sets the boom angle, and while the boom is over the traveler car it holds the leech down too ("the mainsheet is the throttle") |
| Vang | Z / X, D-pad left / right | slack to hard on | holds the leech down whatever the sheet does, so a puff can be eased without the main twisting open (guide). With the mast free to go forward at the deck it bends the lower mast |
| Outhaul | V / F | at the black band to 4 in eased | deepens the foot of the main. Guide: tight upwind except the very lightest air, eased 2-3 in downwind |
| Cunningham | L / O | 0 to 3 in on | pulls the draft forward, flattens the main a little and, once it's loaded, opens the leech. Guide: loose until overpowered |
| Traveler | [ / ] | centred to 8 in down | how far out the boom can go with the sheet still pulling down. Guide: mostly centred even in heavy air; drop it until the helm is neutral and she's flat |
| Mast at the deck | , / . | 3/8 in aft to 1 in forward (guide marks: 3/8 aft, neutral, 3/8, 3/4 and 1 in forward) | forward bends the mast low: flattens the middle of the main, opens the leech, sags the forestay (guide). Aft holds the lower mast straight against the vang. Guide: forward mark in light air with the crew inside, neutral with the crew to windward, back as the breeze builds, soft masts to the aft mark in 15 kn and up |
| Jib halyard | - / = | 0 to 11 in eased (guide: 10-12 in of throw) | rig tension. Eased, the forestay sags (fuller jib, rounder entry) and the mast goes forward (est: about 6 in at the head with it right off); a few inches off wrinkles the jib luff and lets the draft go aft; tight opens the jib leech. Guide: very slight wrinkles upwind, smooth in very heavy air, 1/3 to 1/2 on reaching with the pole, right off dead downwind |
| Jib lead | ; / ' | 2 in either way of neutral | forward closes the jib leech and fills its foot, aft opens the top. Guide: set it so the luff telltales break evenly (top first: move it forward) |
| Daggerboard | B, U / N, D-pad up / down | two places: down, or raised to the limit band | a Snipe's board lifts straight up through the trunk. Class rules: at most 851 mm below the keel when down; raised, a painted band on the board may come no higher than the deck, and a safety line of at most 610 mm holds it. Raised, 305 mm (12 in) is left below the keel, as the class drawings show. In 10 kn that costs about 3.5 degrees more leeway upwind (4.1 to 7.6) for a quarter of a knot more speed, and gains about 0.05 kn on a run. The board is drawn to the class drawing: a flat aluminium plate 521 mm wide at the top and 254 mm at the bottom, with a handle bar and two rubber stoppers that rest on the case. The crew raises it on a run and puts it down again on a reach |
| Whisker pole | G, Triangle | | see below |

Touch a control's keys and you have it; the pause menu's "Crew sets the rig" hands the rig back.
The crew's settings (`auto_rig`, used by the AI too) follow the guide's wind ranges and point of
sail, and blend from one to the next rather than switching. In coach mode the rig panel shows
them beside yours.

How the shape is worked out:

- Mast bend (mid-height bow, in): pushing the mast forward at the deck bends it low; the vang bends
  it low too unless the puller holds it back; leech tension from the sheet bends the top. A stiffer
  rig bends less. Past the main's luff curve (est 2 in) the front of the main inverts and costs
  drag, which is why soft masts go to the aft mark in a breeze.
- Forestay sag (in): grows with the jib's load against the rig tension the halyard gives, with the
  halyard eased, and with low mast bend.
- Main: depth for each third of its height (est 9.5 to 12.5% of the chord with the outhaul at the
  band and a straight mast), the draft position (est 44% of the chord, aft with load and bend,
  forward with the cunningham), and twist (a free leech opens about 23°).
- Jib: depth from forestay sag and the lead, twist from the sheet, the lead and the halyard.
- Each sail is three strips, the lower, middle and top third, each in the wind at its own height.
  The wind grows with height over the water (a power law, steeper in light air, est), so the
  apparent wind is freer aloft, and a triangle's head works harder than its foot (est: about 7° of
  twist evens it out). So twist decides whether the top or the bottom luffs or stalls first, which
  is what the jib and leech telltales show.
- Shape to forces (all est): depth adds lift, less so in light air; a flatter entry fills at a
  lower angle, so it points higher; depth, a deep section's leech and a draft aft of halfway add
  drag; induced drag grows as twist brings the centre of lift down; in light air a deep or closed
  leech loses its flow. The heeling arm and the yaw moment come from where the force on each strip
  acts.

The whisker pole (est 1.75 m, about the jib foot) holds the jib out wing and wing about 67° off the
centreline, in clean air on the side away from the main. It is on a launcher line, so it takes about 1.5 s to set, 1.2 s
to stow and 3 s to swap through a gybe (est), with the jib half let go meanwhile; the jib's clew
is pulled across to the pole as it goes out and the pole's tip stays on it. It can't be
set closer than 110° to the true wind; left up as she heads up past a reach, the jib backs and
slows her. The crew (when it has the jib) sets it past 158° true and stows it once she has been inside 150° for 3 s (a brief luff
doesn't bring it down), which is
where the sim says it starts to pay; the AI also takes it down 35 m before a mark.

What `tests/tune_test.gd` shows (one control changed, the rest the crew's):

| Guide says | Sim (from `tune_test`) |
|---|---|
| Cunningham on when overpowered | 18 kn, averaged over 38-44° true: VMG 3.97 kn with it 3 in on, 3.94 loose, and 0.6° less heel. In 6 kn loose is faster (2.22 against 2.19 kn) |
| Light air, crew inside: mast to the forward mark | 5 kn: VMG 1.83 kn at the 3/4 in forward mark, 1.82 at neutral, 1.80 at the aft mark. Forward bends the mast about 1 in, sags the forestay from 0.9 to 1.5 in and opens the main 2° more |
| Outhaul eased 2-3 in downwind | 10 kn, TWA 170: 4.14 kn eased 2 1/2 in, 4.10 at the band |
| Whisker pole running | 10 kn: +1.2% at TWA 165, +1.5% at 170, +1.8% at 175. It loses below about 155° (-2.3% at 150, -5.4% at 140); up to +2.8% dead downwind in 18 kn |
| Jib halyard right off dead downwind | 10 kn, TWA 178 on the pole: 4.20 kn off, 4.17 kn at full tension |
| Rake aft for lee helm (aft adds weather helm) | 10 kn hiked flat: +0.1° of rudder at 4 in forward, +0.4° at the base, +0.7° at 4 in aft |
| Vang on so a puff can be eased | main eased to 0.35: 25° of twist with the vang slack, 11.5° with it on 6/10 |
| Jib lead so the telltales break evenly | the crew's lead in 10 kn puts the bottom and top thirds of the jib within 0.1° of each other |
| More tip to tip is stiffer | 14 kn: 2.9 in of mast bend on a soft mast, 1.6 in on a stiff one with 29 3/4 in tips |
| Board part way up downwind (not in the guide) | 10 kn, TWA 170: 4.21 kn 40% down, 4.16 kn fully down |

The pole costs time to set (1.5 s), and gybing with it up costs a little more than gybing without
it (0.6 m against 0.4 m in 10 kn, run to run). Heading up from a run to TWA 100 with it still up,
she does 5.0 kn against 5.8 kn with it stowed.

These are small numbers, and they come from estimated coefficients: the test shows the model
does what the guide says, not how much it's worth on a real Snipe. Two things the model doesn't
do yet: in 10 kn it has an outhaul eased 3 in about even with tight upwind (3.48 against 3.45 kn
VMG; the guide says tight), and in a breeze the steady state moves by a few percent with small
changes, because the crew's trim has a flat optimum when she's overpowered.

## AI

`scripts/ai.gd`: before the start, the AI boats reach back and forth below the line, then time a
run at their chosen spot on it. Upwind they tack on laylines and headers, and they round marks to
port. They give way when rules 10, 11 or 12 say they must, and they take their penalty turns. They
also avoid the shore, the marks and the RC boat. Skill changes how well they trim and steer.

## Tests

Run them all with `run_tests.bat`, or one at a time:

```
godot --headless --path . --script res://tests/polar_test.gd   # speeds, no capsizes
godot --headless --path . --script res://tests/tack_test.gd    # tacks, gybes, getting out of irons
godot --headless --path . --script res://tests/rules_test.gd   # check-in, OCS, roundings, finish, penalties, right of way
godot --headless --path . --script res://tests/controls_test.gd  # the real game with synthetic keys and mouse: tiller, sheet, mouse
godot --headless --path . --script res://tests/session_test.gd # records an AI race, reads it back, runs the analytics
godot --headless --path . --script res://tests/capsize_test.gd # when she goes over and when she doesn't
godot --headless --path . --script res://tests/tune_test.gd    # the tuning guide's directions, the whisker pole
godot --headless --path . --script res://tests/race_test.gd    # four full AI races in different winds
```

`polar_test` and `tack_test` also check the sim against `data/targets.json`. Targets are split
into wind bins (light 4–8 kn, medium 8–12, fresh 12–16, heavy 16–20) and, for tacks and gybes,
into time bins around the move (seconds from head to wind or dead downwind). Every target names
its source. A missed `measured` or `model check` target fails the test. A missed `estimate` or
`first principles` target prints WARN, because nobody has checked it on a real Snipe yet. Most
targets are still null (no target yet) until there's real-boat data.

`scripts/moves.gd` finds the tacks and gybes in any time series of speed and true wind angle and
scores each time bin as metres lost to a boat that kept going at the baseline VMG. The baseline
is the average of steady sailing 20 to 10 s before the move and 20 to 30 s after it, so tacking
on a wind shift isn't counted as a gain or a loss. `scripts/analysis.gd` uses it on a recorded
session and adds:

- clean moves only: a tack or gybe is scored only when no other move, penalty turn or capsize
  reaches into its window
- roundings, timed from the closest approach to the mark and scored against the boat's own
  steady VMG for each leg's sector in that wind bin (VMC to the mark on a reach). Tacks and
  gybes inside a rounding count as part of it.
- the start, against a boat that crossed at the gun at her steady upwind VMG
- steady sailing by wind bin and sector, leaving out the time around every move

The same code is meant for real-boat logs once they're converted to the session CSV columns.

`tests/trace.gd` prints a time trace of chosen AI boats for debugging.

Screenshots of the running game (windowed, not headless):

```
godot --path . --script res://tests/game_shot.gd -- out=C:/tmp/shots plan=race    # also plan=menu, free, finish, rig
godot --path . res://tests/view_test.tscn -- cam=close shot=C:/tmp/close.png   # 3D views only
```

## Files

- `scripts/lake.gd`: shoreline, marks and the shore distance field
- `scripts/wind.gd`: wind field and puffs
- `scripts/boat_sim.gd`: boat physics, the rig and sail shape model, the whisker pole, and the
  crew's trim, hiking, rig and pole handling
- `scripts/moves.gd`, `scripts/targets.gd`, `data/targets.json`: move analysis, and the target
  numbers the tests check against
- `scripts/recorder.gd`: writes and reads session files. `scripts/analysis.gd`: the debrief
  numbers. `scripts/replay.gd`, `scripts/replay_bar.gd`: replay through the normal views.
- `scripts/race.gd`, `course.gd`, `rules.gd`: the sailing instructions and Part 2 calls
- `scripts/ai.gd`: AI skippers
- `scripts/fleet.gd`: steps everything together, including contact with boats, marks and the shore
- `scripts/world_view.gd`: sky, water (wind chop, puffs, shallows), farmland, the Front Range,
  the USC club and dock, marks 1–9, the committee boat with its flags and course board, and the pin
- `scripts/boat_view.gd`: the Snipe model, built in code: a moulded hard-chine hull with sheer
  spring, a full bow that closes into a rounded tip, a raked stem, a flat transom raked a little,
  slightly convex panels, a rolled deck edge of the same radius all round, a rubrail right round
  the bow and a pinstripe; floating at rest on the class's 3.86 m waterline and 0.15 m draft,
  with the transom just clear of the water; a cambered foredeck with the V-shaped splash guard
  ahead of the mast and the mast slot; wide side decks (about 0.45 m) for the crew to sit on,
  with grey non-skid pads that run on past the cockpit; a long smooth aft deck (about 1.2 m,
  as on a real Snipe) with an inspection port, the V-shaped mainsheet bridle and the tiller
  running forward under it; a narrow moulded cockpit (about 0.6 m across, as in an overhead
  photo of a modern Snipe) with nearly square corners, sloping tank sides, a filleted floor,
  trunk, straps, bailers and ratchet block;
  aerofoil centreboard and rudder with an aluminium head and carbon tiller; an oval mast with
  aerofoil spreaders and a compass; cambered sails with the insignia and sail number; jib and
  leech telltales; the running rigging (mainsheet from the ratchet block up to the boom, along it
  and down to the bridle, the working jib sheet, the vang, the whisker pole stowed along the boom
  with its launcher line to the jib's clew) and a window in the jib. Gelcoat, non-skid, aluminium and black fittings each have their
  own material. The two sailors aren't drawn; their weight and how far out they sit are in the
  physics.
- `shaders/`: water, land, sails, mountains, flags, telltales. The water is four layers of
  seamless noise at unrelated scales, each running slightly off the wind with crests stretched
  across it, so the chop never visibly repeats. Puffs roughen it into dark cat's paws, lulls go
  glassy, and small whitecaps break from about 13 kn. Screen-space reflections put the boats in
  the water. Wakes come from each boat's actual track, so they curve through tacks and gybes:
  wash behind the transom, a feathered V at the Kelvin angle, transverse waves, a bow wave, and
  a lingering slick. Each Snipe's heeled hull is cut out of the surface so the cockpit stays dry.
- `scripts/main.gd`, `hud.gd`, `minimap.gd`, `menu.gd`, `overlay.gd`, `camera_rig.gd`, `audio.gd`: the game
- `tools/build_lake.gd`: rebuilds `data/` from the OSM file and the reference map
