# Snipe Sim: Union Reservoir

A Snipe dinghy racing simulator set on Union Reservoir in Longmont, Colorado, sailed under the
Union Sailing Club's 2026 series sailing instructions. Built with Godot 4.7.2 (GDScript).

## Play

Double-click `play.bat`, or run Godot with this folder:

```
"%USERPROFILE%\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe" --path C:\Users\dm\snipe-sim
```

Pick the wind, fleet (10 boats at most, yours included), course and realism on the start menu
and press **Go sailing**. You start five minutes before the gun, reaching in toward the committee
boat with flag L up for check-in.

### Simulator (the default) and Assisted

Simulator mode gives you what a Snipe sailor has:

- **Instruments:** a compass and a watch, which is all Snipe class rules allow. There is no
  speedo, no wind readout and no trim advice. You read the jib telltales, the main leech
  telltales, the cassette tape and yarn tied on the shrouds, the masthead windex and the darker puffs on the water. The I key turns on coach
  numbers (speed, true and apparent wind, VMG, trim hints) while you learn.
- **Controls:** you steer with the tiller, not the bow: push it to port and she turns to
  starboard. The tiller stays where you leave it. Pulling the main in gets slower as the load
  builds; letting it out is quick. You trim the main and set the vang and the
  outhaul/cunningham. As in a real Snipe, your crew trims the jib and hikes. Take either over
  with Q/E or Shift/Ctrl, and hand it back from the pause menu.
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
| Z / X | vang: ease / tension (a loose vang twists the leech open) |
| V / F | outhaul + cunningham: ease for power / flatten to depower |
| K | auto main on/off |
| B | centreboard down / half / up |
| R | crew rights the boat after a capsize (once they've reached the board) |
| C | camera: helm, start line, overhead, chase (right-drag to look, wheel to zoom) |
| M | chart |
| I | coach numbers |
| Tab | finishers (live standings in coach or Assisted mode) |
| T | time warp x1 / x2 / x4 / x8 |
| Enter | after you finish or retire, skip ahead to the results |
| F1 | help card |
| Esc | pause: restart, retire, assists, menu |

A gamepad works for steering (left stick) and the main (right stick).

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
- Crew hiking to about 1 m outboard, righting arm falling away past 45°, and a capsize past 70°.
  Righting takes about 20 seconds, then the water drains through the bailers as she moves.
  In irons the crew backs the jib.
- Sail shape: the vang controls leech twist (a loose vang is less power and a lower heeling arm;
  a hard vang stalls the leech in light air), and the outhaul/cunningham controls depth (a flat
  sail makes less lift and less induced drag). Easing the sheet to depower costs flogging drag, so
  flattening and twisting off beat easing in a breeze: about 9% more upwind VMG in 18 kn, while a
  full sail is about 20% better in 6 kn.
- Chop from fetch adds resistance upwind.
- Snipe numbers: 4.72 m long, 1.52 m beam, 172 kg hull, 8.8 m² main and 3.0 m² jib, 150 kg of crew.

Speeds from `tests/polar_test.gd`, with the crew's rig tune: upwind velocity made good is about
2.4 kn in 6 kn of wind, 3.6 kn in 10 kn and 4.6 kn in 18 kn, at 34–42° to the true wind. That
angle is a little high in a breeze, where the hull is near its speed limit. Beam reaching gives
about 4 kn in 6 kn of wind and 8 kn in 18 kn. These are a model, not measured Snipe polars.

The race committee's horn is a synthesized canned air horn: a reed tone near 415 Hz with a
flared-horn blare between 1 and 4 kHz, a second slightly sharp reed for the rasp, a pitch blat at
the start, and slap-back echoes off the water. It sounds from the committee boat, fading with
distance and arriving late at the speed of sound. `tests/horn_export.gd` writes it to WAV files.

The wind (`scripts/wind.gd`) oscillates and drifts, bends a few degrees across the reservoir,
drops off near a windward shore, and carries puffs and lulls that drift downwind. Puffs show as
darker water. Boats to windward throw a wind shadow.

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
godot --headless --path . --script res://tests/race_test.gd    # four full AI races in different winds
```

`tests/trace.gd` prints a time trace of chosen AI boats for debugging.

Screenshots of the running game (windowed, not headless):

```
godot --path . --script res://tests/game_shot.gd -- out=C:/tmp/shots plan=race    # also plan=menu, free, finish
godot --path . res://tests/view_test.tscn -- cam=close shot=C:/tmp/close.png   # 3D views only
```

## Files

- `scripts/lake.gd`: shoreline, marks and the shore distance field
- `scripts/wind.gd`: wind field and puffs
- `scripts/boat_sim.gd`: boat physics and the trim and hike assists
- `scripts/race.gd`, `course.gd`, `rules.gd`: the sailing instructions and Part 2 calls
- `scripts/ai.gd`: AI skippers
- `scripts/fleet.gd`: steps everything together, including contact with boats, marks and the shore
- `scripts/world_view.gd`: sky, water (wind chop, puffs, shallows), farmland, the Front Range,
  the USC club and dock, marks 1–9, the committee boat with its flags and course board, and the pin
- `scripts/boat_view.gd`: the Snipe model: hard-chine hull, rig, cambered sails with the insignia
  and sail number, jib and leech telltales, windex, crew, rudder, centreboard, wake
- `shaders/`: water, land, sails, mountains, flags, telltales. The water is four layers of
  seamless noise at unrelated scales, each running slightly off the wind with crests stretched
  across it, so the chop never visibly repeats. Puffs roughen it into dark cat's paws, lulls go
  glassy, and small whitecaps break from about 13 kn. Screen-space reflections put the boats in
  the water. Wakes come from each boat's actual track, so they curve through tacks and gybes:
  wash behind the transom, a feathered V at the Kelvin angle, transverse waves, a bow wave, and
  a lingering slick. Each Snipe's heeled hull is cut out of the surface so the cockpit stays dry.
- `scripts/main.gd`, `hud.gd`, `minimap.gd`, `menu.gd`, `overlay.gd`, `camera_rig.gd`, `audio.gd`: the game
- `tools/build_lake.gd`: rebuilds `data/` from the OSM file and the reference map
