# Training roadmap

## Goal

On 16 Nov 2026 Doug set the direction: this is a training simulator for Union Sailing Club sailors, not a game. It should train boat handling, starts and tactics, rules and race procedure, and rig tuning. For now it's driven with an Xbox controller plus keys. Later Doug wants a real Snipe hull as the cockpit. There's no real-boat data yet, and Doug plans to record some.

The rule that follows from this is simple. The sim must not reward anything the real boat punishes, or the other way round, because sailors will take those habits onto the water. Anything that hasn't been checked against a real Snipe gets labelled as unchecked in the app.

## Where it falls short today

The physics is force-based, which is a good start, but the tests only check wide sanity ranges. `polar_test` passes any upwind VMG from 1.2 to 5 kn. In 14 to 18 kn the best upwind angle comes out at 34 to 36 degrees true, tighter than the 38 to 46 we'd expect of a dinghy. We can't tell which guessed input causes it (the hull drag table, or sails that don't affect each other) without real data, so the tests warn about it rather than fail. A settings switch at 109 degrees made reaching speed jump in 18 kn; step 1 fixed that. Rocking the boat gives no drive, waves don't move the hull, there's no planing, and capsize recovery is a timer. (The whisker pole was added on 17 Nov.)

The wind is one slow oscillation plus a random drift and some puffs (`wind.gd`). It isn't fitted to how the wind actually behaves on Union. Rules are only judged when two boats touch, and only rules 10, 11, 12 and 13 (`rules.gd`). Until 17 Nov the only sail controls were the vang and outhaul, with no rig tuning. Nothing is recorded, so there's no replay or debrief. The gamepad code reads one controller and has no rumble.

## Plan

1. Put the project under git. Fix the two polar problems above, and change the tests to check target numbers with a source noted next to each one.
2. Record every session and add a replay with a few measures: distance lost per tack, distance from the line and speed at the gun, and upwind VMG against the target. Analytics are split into targets by wind bin and time bins around moves (Doug, 16 Nov). Done on 16 Nov for races: recording, a debrief of the start, steady sailing and every tack, gybe and rounding, and a replay. Still to do: a browser for past sessions, recording free sailing, and puffs in the replay.
3. Xbox controls: tiller on the left stick, mainsheet on the right stick, hiking on the triggers, and rumble for helm load and a luffing sail. Inputs go into the physics as physical amounts (tiller angle, sheet length, crew position), so the Snipe hull rig can plug into the same place later. A second controller can sail as crew. On 17 Nov Doug connected a PS5 pad, so the pad layout, rumble and lightbar are done for that (the same layout works on an Xbox pad). Still to do: the physical-amounts input layer and the second controller for the crew.
4. Rules: judge keep-clear before boats touch, add mark-room (rule 18) and rules 15, 16 and 17, and explain each call on the replay. The step 2 analytics also showed the AI overstanding windward marks by 10 to 30 m, which needs fixing so the fleet is a fair comparison.
5. Drills for starts, tacks, mark roundings and shifty beats, scored against the targets.
6. When data arrives: a tool to import GPS and phone logs, then fit the polars, tack losses and Union's wind patterns to them.
7. Deeper physics, each piece checked against data: rocking and roll tacks (within rule 42, which limits pumping and rocking), waves moving the hull and planing. The whisker pole is in (17 Nov, step 8); its gain still needs data.
8. Rig tuning: a proper sail shape model first, then mast rake, rig tension, spreaders and jib lead. Published Snipe tuning guides give the first targets. Started 17 Nov: every control in the North Sails Snipe tuning guide (outhaul, cunningham, vang, traveler, mast pusher/puller, jib halyard, jib lead, spreaders, shrouds, rake, mast stiffness), a continuous centreboard and the whisker pole, with a three-strip sail shape model, a rig panel, recording and `tests/tune_test.gd` checking the guide's directions. Still to do: check the coefficients against real-boat data (they're estimates), a slot effect between jib and main, the pole to leeward on a reach, crew weight on the menu, and drills that score a sailor's rig choices.
9. Club release: a Windows build, a check that it runs on an ordinary laptop, sailor profiles and a first-time lesson.
10. The Snipe hull cockpit.

## Recording real-boat data

Speed and position need a GPS logger at 5 Hz or faster, because a phone's 1 Hz track smears the tacks. A phone fixed in the boat can give heading and heel. True wind is the hard part. The committee boat's or the club's anemometer, logged with times, would do. Without a wind reference the polars can't be checked, only the tacks and acceleration. Note the crew weights and rig settings each time.

The most useful sails are a few minutes of steady sailing at set angles on each tack, a run of tacks and gybes, and accelerating from a stop. Repeat them in as many wind strengths as the season gives.

## Decisions still open

- The Xbox button layout beyond the sticks and triggers.
- What computers club members will run it on.
- Whether Assisted mode stays as training wheels.
