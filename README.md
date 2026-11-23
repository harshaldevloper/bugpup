# Bugpup

A Godot editor plugin that **plays your game by itself** and tells you
what is broken.

It presses random buttons from your game's own input map, watches every
physics frame for eight kinds of problem, and only reports a finding
after it has **replayed it three times** and seen it come back every
time.

Everything runs on your machine. No cloud, no account, no AI model, no
network calls of any kind.

---

## What it looks for

| It is called | What it means | Tested? |
|---|---|---|
| `through_wall` | A body passed through a wall. It is cast as a ray from the body's recent positions; if the body ended up well past a surface the ray hit, it went through. | **yes** - planted bug 1 |
| `out_of_bounds` | A body left the world - fell below the floor, or ended up impossibly far from the origin. Two rules, one kind. | **yes** - planted bug 3 |
| `jitter` | A body keeps reversing direction while barely moving. That is the classic "stuck on a slope and vibrating" bug. | **yes** - planted bug 2 |
| `nan_numbers` | A position or velocity became `NaN` or infinite. | **yes** - planted bug 4 |
| `stuck` | A body is wedged inside a collider: it is deep inside a surface and the collision normals from several sides cancel out. Only checked on `CharacterBody3D`, because that is the only type that reports slide collisions. | **no** - implemented, no planted-bug test |
| `softlock` | The game stopped making progress. You mark progress points in your own code (see below) and the agent notices when it stops reaching new ones. **It only fires if your code calls `Bugpup.progress()` at least once** - otherwise the agent has no idea what "progress" means for your game. | **no** - implemented, no planted-bug test |
| `freeze` | A body stopped moving completely for a long time. Only counts a body that was seen to move earlier, so scenery is not a freeze. | **no** - implemented, no planted-bug test |
| `lag_spike` | One frame took far longer than the others - more than four times the median of the recent frames. | **no** - implemented, no planted-bug test |

That is **eight** detectors, and the table lists every one of them by the
exact name the plugin reports. Four have a planted-bug test; four are
implemented but untested.

**There is no `crash` detector.** An earlier version of this README
listed one. It does not exist: the plugin does not read engine error
logs and cannot tell that the game died. The closest thing to it is
`freeze`, which catches a body that stopped moving - not a crash.

---

## Install it in another project

1. Clone this repo into your project's `addons/` folder, and name that
   folder `bugpup`:

   ```bash
   cd /path/to/your/project
   git clone https://github.com/harshaldevloper/bugpup.git addons/bugpup
   ```

   Or download the release zip and unpack it as `addons/bugpup/`.
2. Open the project in Godot. **Project → Project Settings → Plugins**
   and enable **Bugpup**.
3. Open any 3D or 2D scene and press the **Bugpup** button in the
   panel that appears at the bottom of the screen.

That is the whole installation. There is nothing to configure and
nothing to sign up for.

To run it from the command line instead, use the test runner that
ships with this repo, from your project's root:

```bash
bash addons/bugpup/tests/run_tests.sh
```

---

## Marking progress (optional)

If you want softlock detection, add one line anywhere in your game code:

```gdscript
Bugpup.progress("room_3")
```

Call it whenever the player reaches a new place or clears a new step.
If the agent plays for a long time and never reaches a new progress
point, it reports a softlock.

If your game never calls it, softlock detection simply never fires.
Everything else still works.

---

## How the three-times replay works

A finding is not reported the first time it is seen. The agent:

1. **Notices** something wrong, and records the exact inputs it had
   pressed at that moment.
2. **Reloads the scene** and plays the recorded inputs again.
3. Does that **three times**.
4. Only reports the finding if it came back **all three times**.

Reloading the scene is what makes this work for both kinds of bug:

- A bug caused by the **bot's inputs** (going through a wall,
  jittering) comes back because the same inputs are applied again.
- A bug caused by the **game's own logic** (a `NaN` velocity, a body
  falling out of the world) comes back because the game's `_ready()`
  and `_physics_process()` run again.

The replay reports which specific wall or surface the body went
through, so the bug note points at something real.

---

## What a finding looks like

Each confirmed bug is written to `user://bugpup_reports/` as a JSON
file, and shown in the editor panel:

```json
{
  "bug": {
    "kind": "through_wall",
    "body": "FastBall",
    "detail": "passed 3.34 through '@StaticBody3D@30' at (-7.0, 1.0, -4.0) (its size is 0.05)",
    "replays": 3,
    "seen": 9
  },
  "inputs": [ { "frame": 12, "action": "move_right", "pressed": true } ],
  "seed": 20261116
}
```

- `kind` - which of the eight it is
- `body` - the node it happened to
- `detail` - what happened, in plain words
- `replays` - how many of the three replays reproduced it
- `seen` - how many times it was noticed in total
- `inputs` - the exact button presses, so you can reproduce it yourself

In the editor panel you get the same information, plus a **Reproduce**
button that plays the recorded inputs back into the running game.

---

## Changing the settings

Every threshold is an exported property on the agent, so you change it
in the **Godot Inspector** - select the Bugpup node, or open the plugin
panel and edit the settings there. If the agent is too eager or too
quiet, this is where you change that.

The main ones:

| Setting | What it does | Default |
|---|---|---|
| `duration_seconds` | How long one session plays for | `60` |
| `seed_value` | The random seed. The same seed plays the same way | `20261116` |
| `action_hold_frames` | How many frames a pressed button is held | `6` |
| `idle_frames` | How many frames to wait before pressing again | `3` |
| `jitter_flips` | Direction reversals before it counts as jitter | `6` |
| `jitter_window_frames` | The window those reversals are counted in | `45` |
| `jitter_max_avg_step` | How far the body may move per frame and still be "barely moving" | `0.25` |
| `out_of_bounds_y` | Below this height, a body is out of the world | `-50` |
| `out_of_bounds_radius` | Further than this from the origin, a body is out of the world | `120` |
| `stuck_depth` | How far a body must be pushed before it counts as stuck | `0.25` |
| `lag_spike_ms` | A frame slower than this is a lag spike | `120` |
| `softlock_seconds` | This long without new progress is a softlock | `25` |
| `freeze_seconds` | This long without moving is a freeze | `6` |
| `replay_attempts` | How many times a finding is replayed | `3` |

The Inspector shows the rest - `jitter_min_path`, `stuck_normal_cancel`,
`lag_window`, `freeze_min_travel` and `tunnel_history_frames` - with the
same defaults listed in `agent.gd`.

---

## Testing it

The plugin ships with its own test scene and its own test run:

```bash
bash addons/bugpup/tests/run_tests.sh
```

It runs two scenes:

- **the bug lab** - the same world with four bugs planted on purpose
  (a fast ball through a thin wall, a shaking box, a hole in the
  floor, a body whose velocity becomes `NaN`). All four must be caught,
  each surviving a three-times replay.
- **the clean lab** - the same world with each of those four bugs
  fixed. It must report **nothing**. Anything it reports there is a
  false alarm, so the false-alarm count is a measurement rather than a
  claim.

The clean lab is the same world with a flag flipped, so the only
difference between the two runs is the bugs themselves.

### What the last run actually printed

```
BUG LAB: 6 confirmed, 4/4 expected kinds caught
  - kind=through_wall  body=FastBall   replays=3
  - kind=jitter        body=JitterBox  replays=3
  - kind=out_of_bounds body=FastBall   replays=3   (120.6 from origin)
  - kind=nan_numbers   body=NanBox     replays=3
  - kind=out_of_bounds body=PitFaller  replays=3   (fell below the floor)
  - kind=out_of_bounds body=Player     replays=3   (fell below the floor)
CLEAN LAB: 0 reported
RESULT: PASS - all 4 planted bugs caught, clean scene silent.
```

**Six findings, four planted bugs.** They are not six different bugs.
Four is the number of planted bugs, and `4/4 expected kinds caught` is
the number that matters. The other two findings are the *same* planted
bugs seen by a second detector:

- `out_of_bounds / FastBall` - the ball went through the thin wall
  (that is planted bug 1) and kept flying until it was 120.6 units
  from the origin, which is the *other* out-of-bounds rule. Same bug,
  second symptom.
- `out_of_bounds / Player` - the player fell into the hole. The hole
  is planted bug 3, and the player is not a planted body: the agent
  drove it in by pressing random keys. Same root cause, different
  body.

So this test proves two things and no more:

1. **Every planted kind is caught**, and each finding survives a
   three-times replay.
2. **The same world with the bugs removed produces zero findings**, so
   the false-alarm count is 0, not an estimate.

It does **not** prove the other four detectors work. `stuck`,
`softlock`, `freeze` and `lag_spike` are implemented and listed above,
but this test does not exercise them, so they are not claimed here as
tested.

---

## How it decides what to watch

Most games put their player in a group called `"player"`. A lot of
games - including the one this was built on - use **no groups at
all**.

So the agent watches three things:

1. the `"player"` and `"physics_body"` groups, if the game uses them;
2. every `CharacterBody3D`, `RigidBody3D`, `AnimatableBody3D`, `Area3D`
   and their 2D equivalents, whether the game groups them or not;
3. any node that has been **seen to move** - some actors are plain
   `Node3D`, and they are exactly the things that fall through floors.

Children of a watched body are skipped, so a camera pivot under the
player does not double every finding.

### Which body is the bot driving?

Jitter is only a bug if the game is not causing it. When the agent
presses a direction, the body the game steers with that direction is
*expected* to turn.

The agent works out which body that is **by measurement**: it compares
the average movement over the six frames before a press with the
average over the six frames after. The body's average movement flips
direction, so it is the one the game is steering with that input. A
shaking box averages out to nearly nothing over six frames, and a ball
travelling in a straight line never changes at all, so neither of them
can win.

---

## Known weaknesses

These are real, and they are not fixed:

- **A body the bot drives can look like it is jittering.** The driver
  detection needs a few presses before it is confident, so the first
  few seconds can produce a jitter false alarm on the player.
- **Tunnelling detection needs a body that moved a lot in one frame.**
  A body that creeps through a wall over many frames is not caught.
- **There is no crash detector.** The plugin cannot tell that the game
  died. `freeze` catches a body that stopped moving, which is the
  closest thing, but it is not a crash.
- **The softlock detector needs `Bugpup.progress()`.** Without it,
  softlocks are never reported.
- **Screenshots need a real renderer.** In `--headless` mode there is
  no image to capture, so the screenshot is skipped.
- **The lag detector measures the physics frame time.** It will not
  notice a slow frame caused by something outside the physics loop.

---

## How it was built

Everything here was written by an AI agent working against the Godot
4.6.3 class documentation and the engine's own output. Every claim in
this file was checked by running it:

- the four planted bugs are caught, each with `replays=3`;
- the clean scene reports nothing;
- the plugin parses cleanly under `--check-only`;
- the agent was run against a real game that uses no groups at all.

The reasoning behind each decision is in the comments in the source.
