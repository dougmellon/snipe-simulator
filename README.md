# Snipe Sim: Union Reservoir

A Snipe dinghy training simulator for Union Sailing Club sailors, set on Union Reservoir in
Longmont, Colorado. You helm, trim and race a Snipe against up to nine AI boats, then review
your sailing in a debrief and replay.

This page is the short version. The full manual (rules, physics, rig tuning, tests) is in
[MANUAL.md](MANUAL.md).

## Run it

You need **Godot 4.7.2** (the standard build, not .NET). Download it from
[godotengine.org](https://godotengine.org/download/archive/) and unzip it anywhere. The sim uses
Godot's Forward+ renderer, so it needs a graphics card that supports Vulkan (Windows, Linux) or
Metal (Mac).

In the commands below, replace the Godot path with wherever you put it. Run them from this
folder. The first command imports the project once; after that, only the second is needed.

So far the sim has only been run on Windows. The Mac and Linux steps are the standard way to
run a Godot project and have not been tried on this one.

### Windows

```powershell
& "C:\path\to\Godot_v4.7.2-stable_win64.exe" --path . --import
```

```powershell
& "C:\path\to\Godot_v4.7.2-stable_win64.exe" --path . --fullscreen
```

Or double-click `play.bat`. It expects Godot at
`%USERPROFILE%\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe`; edit the path in the file if
yours is somewhere else.

### Mac

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --import
```

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --fullscreen
```

### Linux

```sh
./Godot_v4.7.2-stable_linux.x86_64 --path . --import
```

```sh
./Godot_v4.7.2-stable_linux.x86_64 --path . --fullscreen
```

Leave off `--fullscreen` to run in a window.

## Controls

The HUD and the help card (F1, or Create on the pad) show keys or pad buttons, whichever you
used last.

### PS5 controller

Any pad with the standard layout works, such as an Xbox pad.

| Pad | What it does |
|---|---|
| Left stick | The tiller handle. Push it to port and the bow goes to starboard. Let go and it centres. |
| R2 / L2 | Pull the mainsheet in / ease it. Squeeze harder to go faster. It gets slower and rumbles more as the boom nears the centreline. |
| L1 / R1 | Ease / sheet the jib. |
| Circle / Square | Hike out / move in. |
| D-pad up / down | Daggerboard raised to its limit band / down. |
| D-pad left / right | Vang ease / on. |
| Right stick | Look around: left, right, up, down. Full sideways looks right round to the stern. Let go to look ahead. |
| Cross | Change camera: helm, start line, overhead, chase. |
| Triangle | Whisker pole: set, stow, or swap after a gybe. Capsized: the crew rights her. After you finish: skip to the results. |
| R3 | Chart. |
| L3 | Time warp: x1, x2, x4, x8. |
| Touchpad | Coach numbers on / off. |
| Create | Help card. |
| Options | Pause menu. |

Menus use the D-pad and Cross. The pad rumbles with the load on the rudder, when the main
luffs, and for a capsize, a collision or running aground.

### Keyboard and mouse

| Key | What it does |
|---|---|
| A / D, or Left / Right | Move the tiller handle. It stays where you leave it. |
| Space | Bring the tiller back to the centre. |
| W / S, or Up / Down | Pull the mainsheet in / ease it. |
| E / Q | Sheet / ease the jib. |
| Shift / Ctrl | Hike out / move in. |
| B | Daggerboard: switch between down and raised. |
| U / N | Daggerboard raised / down. |
| G | Whisker pole: set, stow, or swap after a gybe. |
| R | Crew rights the boat after a capsize. |
| C | Change camera. |
| M | Chart. |
| I | Coach numbers on / off. |
| Y | Rig panel: every control, its setting and its keys. |
| Tab | Finishers. |
| T | Time warp. |
| Enter | After you finish or retire, skip to the results. |
| F1 or / | Help card. |
| Esc or P | Pause menu. |
| K / J / H | Auto main / auto jib / auto hike on or off. |

Rig tuning keys:

| Key | Control |
|---|---|
| X / Z | Vang on / ease |
| F / V | Outhaul tighten / ease |
| O / L | Cunningham on / ease |
| [ / ] | Traveler down / up |
| . / , | Mast at the deck forward / aft |
| = / - | Jib halyard tighten / ease |
| ' / ; | Jib lead forward / aft |

Mouse: hold the left button and move sideways for the tiller, back and forth for the mainsheet.
Hold the right button and drag to look around. The wheel zooms the chase and overhead cameras.

## What you can do

**Sail**
- Free sail on the reservoir with marks 1 to 9 laid, or race a fleet of up to 10 boats
  including yours.
- Choose the wind direction and strength, the course, the number of AI boats and their skill
  from the start menu.
- Sail in Simulator mode (compass, boat speed in knots and a watch, and you read the telltales
  and the water) or turn on coach numbers for wind, VMG and trim hints.
- Let the crew trim the jib, hike and set the rig for you, or take any of them over yourself.

**Handle the boat**
- Steer with a tiller that behaves like one, and feel the rudder load through the pad.
- Trim the main and jib; a luffing or stalled sail shows in the telltales and slows her.
- Hike to hold her flat. The crew's weight counts side to side and fore and aft.
- Raise the daggerboard on a run and put it down again to go upwind.
- Set, gybe and stow the whisker pole downwind.
- Tune the rig under way: vang, outhaul, cunningham, traveler, mast at the deck, jib halyard
  and jib lead. Set spreaders, shrouds, rake and mast stiffness ashore from the start menu.
- Capsize if you get it wrong, then right her and bail.

**Race**
- Race under the Union Sailing Club's 2026 sailing instructions: check in with the committee
  boat, the starting sequence with flags and horn, recalls if you are over early, port
  roundings, the gate and the finish.
- Right-of-way rules between boats are judged (port and starboard, windward and leeward, clear
  astern, tacking) and penalties are given as turns.
- Four course types: windward-leeward (two laps or short), triangle, and triangle plus
  windward-leeward.

**Review**
- After a race, read the debrief: your start, your steady sailing by wind strength and point
  of sail, and every tack, gybe and mark rounding with the distance it cost.
- Compare your numbers with the rest of the fleet.
- Watch the replay of the whole race from any camera, following any boat.
- Every race is saved as a session file you can keep.

**See it your way**
- Four cameras: from the helm, chase, down the start line from the committee boat, and
  overhead.
- A chart of the reservoir with the marks and the course.
- Time warp up to x8 for long legs.
