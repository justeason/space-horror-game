# Milestone 1 Design Readiness — Rooms, Tasks, and First Playable Slices

> **Status:** Design/audit companion to `GAME_DESIGN.md`.
> **Relationship to `GAME_DESIGN.md`:** `GAME_DESIGN.md` remains the single
> authoritative source for locked decisions (topology, task database,
> interaction vocabulary, horror pacing, architecture principles). Nothing
> in this document overrides it. This document is where that locked
> material gets turned into room-by-room and task-by-task specifications
> specific enough to implement, plus an honest audit of what already
> exists in code today.
>
> **Scope:** Milestone 1 only (finish/polish the first-person prototype,
> build the normal maintenance gameplay loop). No skeletal-character work.
> No implementation happened in this pass except this document itself —
> see the final report for exact confirmation.

**Label legend used throughout:**

- **[LOCKED]** — already decided in `GAME_DESIGN.md`; restated here only
  for context, never changed.
- **[AUDITED]** — a factual statement about the current state of the
  actual Godot project, confirmed by reading the code/scenes, not guessed.
- **[NEW SPEC]** — authored in this pass. Specific enough to implement,
  but **not locked** — treat as a strong draft until you approve it.
- **[OPEN QUESTION]** — a genuine design decision that needs your input;
  options and consequences are laid out, nothing is silently assumed.
- **[PROPOSAL]** — a new mechanic or system this audit concluded is
  necessary, explained with its justification. Requires your approval
  before being treated as locked.
- **[DEFERRED]** — explicitly out of scope for Milestone 1 or this task.

---

# PART 1 — IMPLEMENTATION AUDIT

Audited by reading the actual scenes/scripts, not by inferring from names.
Project inventory at audit time: 14 scenes, 19 scripts (listed in full at
the end of this Part for reference).

| # | Feature | Status | Evidence |
|---|---|---|---|
| 1 | Station room geometry | **B** (shells exist for every locked room; interiors mostly undressed) | See 1.1 |
| 2 | Room connections & navigation nodes | **A** (complete graph across the whole locked topology) | See 1.2 |
| 3 | Control Room workstation & physical controls | **B** (a physical panel/switch pair exists; it is a generic M3/M4 tech demo, not any locked C01-C08 task, and there is no computer-screen workstation interface) | See 1.3 |
| 4 | Surveillance cameras & feeds | **A** for the mechanism, **B** for coverage (3 feeds, console works; only covers Control/Corridor, not every room) | See 1.4 |
| 5 | Living Quarters & bed interactions | **B** (room geometry/furniture built; only the bed interaction exists — no morning/evening routine, no personal-item interactions) | See 1.5 |
| 6 | Laptop & physical daily-log screen | **A** (fully working, manually verified this and last round) | See 1.6 |
| 7 | Player movement & interaction system | **A** (node-graph movement, free-look, raycast interaction, all tested) | See 1.7 |
| 8 | Physical interactables | **B** (the `interact()` pattern is proven and reusable; only 6 instances exist, all in Living/Control) | See 1.8 |
| 9 | Tools and carried objects | **D** (no code at all; Section 19/20 fully designed in prose, zero implementation) | See 1.9 |
| 10 | Task assignment / task-state system | **D** (no code at all) | See 1.10 |
| 11 | Maintenance procedures (the 48 tasks) | **C** (named and partly described in `GAME_DESIGN.md`; zero are implemented) | See Part 3 |
| 12 | Task completion & verification | **D** (no state to complete or verify yet) | See 1.10 |
| 13 | Time/day progression | **D** (no clock, no day counter, no wristwatch object) | See 1.11 |
| 14 | Waking, daily routine, sleeping | **B** (sitting/laptop/get-up exist; "waking up" and the routine itself do not) | See 1.11 |
| 15 | Storage component identification & retrieval | **D** (room shell + 2 decorative racks only; no component props, no S01-S04 logic) | See 1.12 |
| 16 | Engineering repair equipment | **C/D** (room + some decorative props exist; no interactable equipment, no E01-E12 logic) | See 1.12 |
| 17 | Life Support equipment | **D** (empty room shell; no equipment props, no L01-L10 logic) | See 1.12 |
| 18 | Communications equipment | **D** (empty room shell + one observation movement node; no M01-M07 logic) | See 1.12 |
| 19 | Airlock / EVA systems | **D**, explicitly later-phase per `GAME_DESIGN.md` §32 | See 1.12 |

## 1.1 Station room geometry [AUDITED]

Every room in the locked topology (§7) has real 3D geometry in
`scenes/main.tscn` — not placeholder boxes, but floor/wall/ceiling CSG
shells with doorframes, elbows, and connector segments matching the
"irregular, modular spacecraft" philosophy in §6. Measured floor
footprints (from the actual `CSGBox3D` transforms):

| Room | Core floor size (X × Z, meters) | Connector/tunnel segments |
|---|---|---|
| Living Quarters | 4.0 × 4.0 | — (direct to Control) |
| Control Room | 2.8 × 3.4 | Corridor 1.6×1.1 |
| Main Junction | 2.0×2.0 (south) + 2.8×1.8 (north) | — |
| Storage | 2.2 × 2.2 core | 4 connector segments (A–D), snaking, ~1.0–1.2m wide |
| Engineering | 3.2 × 3.8 | Tunnel 1.2×1.2 |
| Life Support | 3.2 × 2.4 | Tunnel (1.0×2.0) + bend (3.4×1.6) |
| Communications | 2.8 × 2.4 | TunnelA 1.6×1.2, TunnelB 1.2×1.4, Alcove 1.4×1.0 (east extension) |
| Airlock | **no chamber yet** — only a 1.0×5.7 tunnel ending at a sealed hatch assembly | — |

Decorative (non-interactable) props already placed:
- **Living Quarters**: bunk, locker, wash basin/mirror, desk w/ task light,
  mug, notebook, wall shelf+book, personal container, stool.
- **Control Room**: console desk, operator stool, equipment housings,
  conduits, task light.
- **Engineering**: `EngineeringCabinet1`/`2`, `EngineeringMachineryHousing`,
  two conduit pipes, a cable bundle, a warning label — all plain
  `CSGBox3D` with no script, i.e. **set dressing, not interactables**.
- **Storage**: `StorageRack1`/`2` (two plain boxes flanking the room,
  east/west) — also set dressing, no component props on them yet.
- **Life Support, Communications, Airlock**: shell geometry only, no
  props at all yet.

Every room already has at least one `OmniLight3D` (`Lights` node, 19
lights total) — basic lighting pass already done station-wide.

## 1.2 Room connections & navigation nodes [AUDITED]

`scripts/navigation/movement_node.gd` implements a plain node-graph (no
separate graph manager — a junction is just a `MovementNode` with >2
neighbors, plus an optional `region` for small free-roam areas). 34
`MovementNode` instances in `main.tscn`'s `MovementNodes` tree span
**every** locked room and connector, confirmed by
`test_whole_station_capsule.gd`, which sweeps 38 distinct edges with the
real player collision capsule. 5 edges fail that sweep today (narrow
clearance at specific elbows) — these are the documented pre-existing
failures this task must not "fix" incidentally. Full navigability
already exists; this is not blocking any Milestone 1 room work.

## 1.3 Control Room workstation & physical controls [AUDITED]

`scenes/interactables/control_panel.tscn` + `toggle_switch.tscn[x2]` exist
and work (two independent switches, a panel that evaluates "switch A
on, switch B off" and lights a status lamp). Read literally, per its own
doc comment, **this is a one-off interaction-architecture demo from an
earlier milestone (M3/M4), not any task from the locked database** — it
does not correspond to C01–C08. There is **no computer screen /
workstation UI** of the kind §13 describes (Systems / Tasks /
Communications / Logs / Station Status / Diagnostics / Surveillance,
"2–3 clicks" navigation). The only existing "physical screen" pattern in
the project is the laptop's SubViewport-on-a-mesh technique
(`scripts/player/laptop_view.gd`, `scripts/ui/session_log_screen.gd`),
which is directly reusable for a workstation screen (see Part 7).

## 1.4 Surveillance cameras & feeds [AUDITED]

`scripts/surveillance/surveillance_camera.gd` (a `SubViewport` wrapping a
real `Camera3D`) + `scripts/interactables/surveillance_console.gd` (click
to cycle feeds, one camera ID at a time) fully match §35's design,
including the `set_feed_override()` horror seam (unused, confirmed by
grep). Only 3 camera instances exist (`cam_control_room`, `cam_corridor`,
`cam_corridor_end`), all clustered near Control/Corridor — none in
Engineering, Storage, Life Support, Communications, or Airlock yet. Not
blocking for Slice A/B (neither slice uses surveillance).

## 1.5 Living Quarters & bed interactions [AUDITED]

`scripts/interactables/bunk.gd` + `scripts/player/sleep_state.gd` fully
implement sit-down → laptop → daily-log editing → get-up, manually
playtested and automatically tested this round and last. There is
**no morning routine, no "wake up," no personal-item interactions**
(brushing teeth, dressing, eating/drinking — §11/§12) — none of the
decorative Living Quarters props (wash basin, desk mug/notebook, locker)
have an `interact()` method. The player currently always starts the
session already standing in the world; there is no sleep → next-day
transition of any kind.

## 1.6 Laptop & physical daily-log screen [AUDITED]

Fully implemented and manually verified (this is the system covered
extensively in the immediately preceding round of work — camera
alignment, screen orientation, Esc hint, typing, all confirmed working
with real rendered screenshots). Per your explicit instruction, this
system was **not touched or redesigned** in this pass.

## 1.7 Player movement & interaction system [AUDITED]

`free_move_controller.gd` (continuous WASD, 1.8 m/s, collision capsule),
`look_controller.gd` (mouse-look, sensitivity 0.0016, damping 9.0),
`interaction_controller.gd` (raycast + reticle + duck-typed `interact()`
dispatch, click priority over movement per §48) are all complete,
tuned, and covered by the existing regression suite. `MovementNode` /
click-to-walk (§49) coexists with free movement (`global_free_move.gd`);
both paths are exercised by tests. No changes needed for Milestone 1
room/task work.

## 1.8 Physical interactables [AUDITED]

The `interact()` duck-type (§48) is proven across 6 real instances
(`ToggleSwitch`, `ControlPanel`, `SurveillanceConsole`, `WallWatchWindow`,
`Bunk`, laptop via `LaptopView`/`SleepState`), each independent, each
owning its own state and emitting its own signals where relevant. This
is a solid, reusable foundation for task interactables — **no new base
class or framework is needed** to start building task equipment (see
Part 7).

## 1.9 Tools and carried objects [AUDITED — not implemented]

Grepped the entire `scripts/` tree for `inventory`, `carry`, `pickup`,
`pick_up`, `held_item` and inspected every hit by hand: every match is an
incidental word in a comment (e.g. "pickup tween" for the laptop's own
lid-raising animation) or unrelated (`component` in a transform-basis
comment). **There is no carried-item system of any kind.** Section 19's
"one item at a time; pick up / carry / place / drop / return" is fully
designed in prose and has zero code. This is a **foundational gap** for
Slice B (see Part 6) and for essentially all Engineering/Life
Support/Communications repair tasks. See the Part 7 proposal.

## 1.10 Task assignment / task-state / completion & verification [AUDITED — not implemented]

No task, objective, or quest code exists anywhere — no `TaskState`,
no signal bus, no save/progress data beyond the laptop's one in-memory
string (confirmed last round: no `FileAccess`/`ConfigFile`/`user://`
anywhere in the project). This is the **other foundational gap**: without
some minimal state tracking, there is no way to represent "C02 found a
fault in Engineering," gate E05 behind having the right wire in hand, or
know C05 should now report success. See the Part 7 proposal — scoped
deliberately small, per §47's explicit warning against premature
registries/frameworks.

## 1.11 Time/day progression & daily routine [AUDITED — not implemented]

No clock, no wristwatch object, no day counter, no concept of "morning"
vs "evening" exists in code. `sleep_state.gd`'s own doc comment is
explicit about this: *"This does NOT implement sleep or day-advancement.
No day/time... system exists anywhere in this project yet."* Getting up
from the bed currently returns the player to full AWAKE/standing state
immediately — there is no actual sleep transition, no next-day
reset/advance. This blocks the literal "Sleep → next day begins" beat
in Slice A, and needs a (small, explicit) design decision — see Open
Question 1.

## 1.12 Storage / Engineering / Life Support / Communications / Airlock task systems [AUDITED — not implemented]

None of the 44 non-Control tasks (E, L, M, S, A series) have any code.
Storage has 2 decorative racks with no component props on them.
Engineering has decorative cabinets/conduits with no `interact()`.
Life Support and Communications are bare shells. Airlock has no
interior at all. This is expected and consistent with `GAME_DESIGN.md`
treating the task database as a catalog, not an implementation record —
restated here only so "C01–A07 exist in the design doc" is never
mistaken for "implemented."

## Full file inventory (for reference)

```
scenes/dev/dev_label.tscn                scripts/audio/footstep_player.gd
scenes/dev/free_move_body.tscn           scripts/dev/global_free_move.gd
scenes/interactables/bunk.tscn           scripts/dev/nav_debug_overlay.gd
scenes/interactables/control_panel.tscn  scripts/interactables/bunk.gd
scenes/interactables/laptop.tscn         scripts/interactables/control_panel.gd
scenes/interactables/surveillance_console.tscn   scripts/interactables/laptop.gd
scenes/interactables/toggle_switch.tscn  scripts/interactables/surveillance_console.gd
scenes/interactables/wall_watch_window.tscn      scripts/interactables/toggle_switch.gd
scenes/main.tscn                         scripts/interactables/wall_watch_window.gd
scenes/movement_prompt.tscn              scripts/navigation/movement_node.gd
scenes/player.tscn                       scripts/player/free_move_controller.gd
scenes/player/player_body.tscn           scripts/player/interaction_controller.gd
scenes/surveillance/surveillance_camera.tscn     scripts/player/laptop_view.gd
scenes/ui/session_log_screen.tscn        scripts/player/look_controller.gd
                                          scripts/player/movement_controller.gd
                                          scripts/player/player_body.gd
                                          scripts/player/sleep_state.gd
                                          scripts/surveillance/surveillance_camera.gd
                                          scripts/ui/session_log_screen.gd
```

---

# PART 2 — ROOM INTERIOR SPECIFICATIONS [NEW SPEC]

Every spec below respects the locked topology exactly as audited in 1.1 —
no room connections, doorways, or shortcuts are changed. Equipment
placement is checked against the real room footprints and existing
`MovementNode` positions (so nothing blocks a path the player already
walks). Where a prop already exists in `main.tscn` (1.1), the spec reuses
it rather than inventing a duplicate.

Each room follows the requested 12-point structure. Point 11/12 (what's
needed now vs. deferred) is the load-bearing distinction for Part 7.

## 2.1 Living Quarters

1. **Purpose**: personal baseline; start/end of day; established as
   safe (§8) so later violations land.
2. **Equipment/furniture (existing)**: bunk, desk (+ task light, mug,
   notebook), wash basin/mirror/cabinet, locker, wall shelf + book,
   personal container, stool, reading light.
3. **Placement**: already built around `MovementNode`s `LivingBed`
   (5.0,1.6,1.0), `LivingHygiene` (2.15,1.6,1.55, at the wash basin),
   `LivingTable` (3.3,1.6,1.65, at the desk), `LivingA`/`LivingDoor` as
   the path to Control. No changes.
4. **Required interaction points (new)**: wash basin (hygiene routine),
   desk/mug (drink), locker (get dressed) — see 2.1.11.
5. **Tools stored here**: none (§20 — personal items only: wristwatch,
   hygiene items, food/water).
6. **Replacement components**: none — Living Quarters is not a
   maintenance space.
7. **Clearance/navigation**: already validated by the nav-capsule sweep;
   no changes needed.
8. **Lighting/materials/sound/identity**: already warm/soft (bunk-side
   lamp, desk lamp) matching "personal/comfortable" (§8); no change
   needed for M1.
9. **Tasks using this room**: none of C01–A07 — Living Quarters hosts
   the *routine*, not a numbered task.
10. **Objects that must stay accessible**: the bunk (already is); the
    wristwatch (new, worn/always-available, no physical prop needed —
    see 2.1.11).
11. **Needed for Slice A**: an automatic wristwatch check on waking (a
    HUD/UI beat, not a 3D prop — see Open Question 1), and a trivially
    skippable "leave for work" trigger (walking to the Control doorway
    already does this; no new mechanic required). Optional morning
    routine interactions (hygiene/dress/eat) are **not** required for
    Slice A to be playable — §34 lists them as optional, and §12
    explicitly discourages forcing mundane clicking.
12. **Deferred**: actual hygiene/dressing/eating `interact()` scripts
    on the wash basin/locker/desk (simple one-click or short-timed
    interactions per §12 — trivial to add once Slice A's loop is
    proven, not before); a physical wristwatch prop (vs. a UI
    indicator); evening-routine variety.

## 2.2 Control Room

1. **Purpose**: operational hub — "home base," not a checkpoint (§8,
   §9). Hosts C01–C08.
2. **Equipment (existing)**: console desk + operator stool, equipment
   housings, conduits, task light. **Missing**: the actual computer
   screen/workstation interface (§13), and a physical station clock
   (§10).
3. **Placement**: console already occupies the room's working wall;
   `MovementNode`s `ControlRoomFrontLeft/Right` sit at the console,
   `ControlRoomRearLeft/Right` give room to turn around. The existing
   `ToggleSwitch`/`ControlPanel` pair sits at (±0.65, 0.86, -0.95) —
   small, to one side, not blocking the console seat.
4. **Required interaction points (new)**: the workstation screen itself
   (sit → operate, §13) — reuses the laptop's proven SubViewport
   pattern on a monitor mesh instead of a laptop mesh. A **station
   clock** prop (observation-only, no `interact()` needed — §10).
5. **Tools stored here**: diagnostic equipment, small tester,
   headset/radio, flashlight, small multitool, station-access equipment
   (§20) — **props TBD**, not required until a specific task needs one
   physically present (e.g. a visible "tester" prop only matters once a
   task's procedure asks the player to pick it up — see Part 7's
   "don't build infrastructure before a task needs it").
6. **Replacement components**: none — Control is operational, not
   logistics.
7. **Clearance**: existing seat/console geometry already accommodates
   the player's sit-down transform (reused pattern from the bed).
8. **Lighting/identity**: console task-light + ambient `Light_
   ControlRoom`/`Light_ConsoleTask` already give it a "working" look,
   consistent with "operational home base."
9. **Tasks using this room**: C01–C08 (all of them — Control is where
   the computer lives).
10. **Must stay accessible**: the workstation seat/screen at all times;
    the existing switch/panel pair can remain as unrelated set
    dressing (it's a real, if generic, physical control cluster — no
    need to remove it) **or** be repurposed as C08's "Manually Test
    Subsystem" physical control, since that task explicitly wants a
    physical-control-plus-response procedure (§13) and this is the only
    physical control cluster that already exists. Flagged as Open
    Question 2 rather than silently decided.
11. **Needed for Slice A**: the workstation screen interactable (new,
    see Part 4 — C01), seated at the existing console position. Nothing
    else.
12. **Deferred**: station clock prop (purely cosmetic for M1 — no code
    reads it yet since there's no time system); the full Systems/Tasks/
    Comms/Logs/Status/Diagnostics/Surveillance menu hierarchy from §13 —
    Slice A only needs the single C01 screen; the fuller menu structure
    can grow exactly when C02–C08 are implemented (Part 7).

## 2.3 Engineering

1. **Purpose**: machinery/electrical (§8); hosts E01–E12, the project's
   main "hands-on repair" room.
2. **Equipment (existing, reusable as-is)**: `EngineeringCabinet1` (at
   -3.2,1.1,3.7), `EngineeringCabinet2` (-4.0,1.0,6.75),
   `EngineeringMachineryHousing` (-5.55,0.9,6.0 — reads as a cooling/
   pump unit by size and position), two conduit pipes along the
   ceiling/upper wall, a cable bundle, a warning label. These already
   form a coherent "electrical panels + machinery" arrangement.
3. **Placement / spatial relationships**: room spans X:[-5.8,-2.6],
   Z:[3.1,6.9]. `EngineeringA` (-3.6,1.6,5.2) sits in the open-floor
   middle, near Cabinet1 — natural position for **the** electrical
   panel. `EngineeringB` (-4.9,1.6,4.6) sits nearer the
   MachineryHousing/Cabinet2 cluster — natural position for the
   cooling-system/battery work. This matches the room's existing decor
   without moving anything.
4. **Required interaction points (new)**:
   - **Electrical panel** (E01/E02/E09/E12): make `EngineeringCabinet1`
     itself interactable (add a script; its box already reads as a
     panel door) rather than adding a redundant second prop.
   - **Fuse/connector/wire points**: small sub-targets on or beside the
     panel (new, simple static meshes with their own `interact()`,
     following the ToggleSwitch precedent of "small independent part").
   - **Battery bank** (E07/E11): `EngineeringMachineryHousing` is sized
     right (0.5×1.6×1.4) to read as a battery rack; repurpose rather
     than add a new prop.
   - **Cooling unit** (E08): `EngineeringCabinet2` repurposed similarly,
     or a small new fan/pump prop near it if the battery bank already
     claims `MachineryHousing` — see Open Question 3.
5. **Tools stored here**: electrical tester, screwdrivers, pliers, wire
   cutters/strippers, torque tools, connector tools (§20) — only the
   ones a specific Slice A/B task actually needs get a physical prop
   first (a tool rack is easy to add once real tools exist; don't
   pre-build an empty rack).
6. **Replacement components here**: none (§20 — replacements live in
   Storage, not Engineering).
7. **Clearance**: the existing nav sweep already validates
   `EngineeringTunnel1 ↔ EngineeringA ↔ EngineeringB` as clear; new
   interaction props must stay clear of those node-to-node sightlines
   (they're wall-mounted, not floor obstacles, so this is naturally
   satisfied).
8. **Lighting/sound/identity**: existing `Light_Engineering`/`Light_
   EngineeringTunnel` already give a harsher, more industrial cast than
   Living/Control; fine as-is for "machinery/electrical" per §8.
9. **Tasks using this room**: E01–E12 entirely; also the Engineering leg
   of the Storage round-trip (E05) and the Engineering↔Life Support
   maintenance loop (§7).
10. **Must stay accessible during tasks**: the panel (E01/E02 target)
    must remain reachable and clickable while the player is also
    carrying the retrieved wire (no modal state should block normal
    movement/interaction elsewhere — consistent with the carry-item
    proposal in Part 7, which never blocks movement).
11. **Needed for Slice A**: nothing beyond what E06 needs — a single
    "loose connection" sub-prop, which can be a small independent part
    near `EngineeringA` (does not require the full panel system below;
    see Part 5's explicit minimal scope).
12. **Needed for Slice B / deferred**: the panel script with its own
    small internal state (loose/damaged-wire/fine, matching E01's
    outcome list) is Slice B work, not Slice A. The full tool rack and
    all 12 Engineering tasks' remaining props are deferred past both
    slices (Part 7).

## 2.4 Life Support

1. **Purpose**: environmental/mechanical (§8); hosts L01–L10.
2. **Equipment (existing)**: none — bare shell (room + tunnel + bend).
3. **Placement (new)**: room spans X:[-4.5,-1.3], Z:[9.6,12.0].
   `LifeSupportA` (-2.8,11.0) and `LifeSupportB` (-4.0,10.8) are the two
   natural equipment anchors.
   - Place a **filter bank** (L01/L02) near `LifeSupportA` — a
     wall-mounted housing with a visible, removable filter cartridge.
   - Place a **pressure/valve manifold** (L04/L05) and **pump unit**
     (L08) near `LifeSupportB` — gauges + a bank of valves + an
     audible pump housing (sound is an explicit diagnostic clue for
     L08, so the pump prop should be a real, separately-positioned
     `AudioStreamPlayer3D` source, not just a mesh).
4. **Required interaction points (new)**: filter cartridge (inspect +
   swap), 2–3 valves (sequence-sensitive per §29/L04), a pressure gauge
   (readable value), the pump housing (listen, then inspect).
5. **Tools stored here**: pressure gauge, leak detector, valve tools,
   filter handling tools, environmental equipment (§20) — same
   "add when a task needs it" rule as Engineering.
6. **Replacement components here**: none (filters themselves are
   retrieved from Storage per §20/§31).
7. **Clearance**: room is otherwise open (3.2×2.4 minus the two
   equipment clusters) — plenty of room to walk between
   `LifeSupportA`/`B` without new geometry blocking the existing
   tunnel/bend path.
8. **Lighting/sound/identity**: currently only has `Light_
   LifeSupportTunnel`/`Light_LifeSupportBend`/`Light_LifeSupport` — fine
   for "environmental/mechanical," but the room will read as empty/flat
   until the equipment above exists. Ambient pump/fan sound should be
   added once the pump prop exists (ties L08's "listen first" into
   ambient station sound, not just a task-triggered cue).
9. **Tasks using this room**: L01–L10 entirely.
10. **Must stay accessible**: valves must remain clickable in whatever
    sequence the player attempts (§29/L04 — "wrong paths should simply
    fail to identify the target," not jam the room, echoing E02's
    stated design principle).
11. **Needed for Slice A/B**: **nothing** — neither slice touches Life
    Support. No Life Support work is required before either slice is
    playable.
12. **Deferred**: all of the above equipment and all of L01–L10 are
    deferred past Slice A/B, to be built in the "expand the catalog"
    phase (Part 7).

## 2.5 Communications

1. **Purpose**: isolated/informational (§8); hosts M01–M07.
2. **Equipment (existing)**: none — bare shell + the `CommsWindow`
   observation `MovementNode` (already wired to `cam_corridor_end`? —
   **no**, confirmed: `WallWatchWindow`'s one instance is in Control
   near the corridor, not at `CommsWindow`. `CommsWindow` is currently
   just a named standing position with no watch-window prop yet).
3. **Placement (new)**: room spans X:[0.6,3.4], Z:[5.9,8.3], with the
   alcove extending east to X:[3.4,4.8]. Place the **comms console**
   (M01/M02/M06 — signal tester, tuning dial, frequency readout) at
   `CommsA` (2.0,6.4). Place an **antenna alignment control** (M03) near
   `CommsAlcove` (4.1,7.1) — physically separate from the console,
   since §30/M03 is a "hold/steady and watch response" action distinct
   from the console's diagnostics, and the alcove is already a
   deliberate side-nook in the geometry. The watch-window prop at
   `CommsWindow` (1.1,7.5) can host future A03/A07-adjacent flavor
   observation, but is not required for any locked Comms task.
4. **Required interaction points (new)**: comms console (diagnostic +
   calibration dial), antenna alignment control (physical lever/wheel),
   optionally a watch-window instance reusing `wall_watch_window.gd`.
5. **Tools stored here**: signal tester, antenna calibration equipment,
   communications diagnostic equipment, electronics repair tools (§20).
6. **Replacement components here**: none (comms components come from
   Storage per M05/§20).
7. **Clearance**: alcove (1.4×1.0) is snug but workable for a single
   alignment-control prop; console sits in the larger main room.
8. **Lighting/sound/identity**: should read as "isolated/informational"
   — cooler, quieter lighting than Engineering's industrial cast, with
   the long quiet approach corridor (§7) already reinforcing distance
   from the operational center. No equipment exists yet to texture
   this further.
9. **Tasks using this room**: M01–M07 entirely.
10. **Must stay accessible**: console and alignment control both need
    to remain reachable independently (M02 and M03 are used together in
    the weak-signal chain, §33).
11. **Needed for Slice A/B**: **nothing** — neither slice touches
    Communications.
12. **Deferred**: all Comms equipment and all of M01–M07, including the
    horror-capable M07, deferred past Slice A/B.

## 2.6 Storage

1. **Purpose**: logistics (§8); hosts S01–S04; deliberately **not** a
   transit hub (§7).
2. **Equipment (existing)**: `StorageRack1`/`StorageRack2` already flank
   the room east/west, matching "navigate shelves/racks" (§31).
3. **Placement (new)**: room spans X:[-7.6,-5.4], Z:[6.9,9.1].
   `StorageA` (-7.0,7.4) and `StorageB` (-6.0,8.7) sit between the two
   racks — correct positions to browse either rack from. Add labeled
   **bins/shelves of components** as child props on the existing racks
   (not new standalone furniture) — small boxes with distinct colors
   and a readable label mesh/texture per component type (wire, fuse,
   connector, filter, battery — matching §20's Storage list).
4. **Required interaction points (new)**: each component bin needs its
   own small `interact()` (pick up — see the carry-item proposal, Part
   7) and a label (readable at normal interaction range, per S01/S02's
   "read requested part" and "compare label").
5. **Tools stored here**: none normally (Storage holds *components*,
   per §20 — tools live where used).
6. **Replacement components here**: spare wires, fuses, connectors,
   filters, batteries, specialized spare equipment (§20) — this **is**
   the room's entire content list.
7. **Clearance**: the 2.2×2.2 core plus the connector segments already
   pass the nav sweep; new bins are rack-mounted (wall-adjacent), not
   floor obstacles.
8. **Lighting/identity**: currently only `Light_Storage` — functional,
   utilitarian is appropriate for "logistics"; no change needed.
9. **Tasks using this room**: S01–S04, plus every chain that ends in
   "retrieve X from Storage" (E05, L02, M05, per §33).
10. **Must stay accessible**: the specific bin a chain currently needs
    must be identifiable without ambiguity — see Part 4's S01 spec and
    Open Question 4 (how "the correct part" is actually specified to
    the player).
11. **Needed for Slice B**: **one** labeled wire bin on one rack is
    sufficient (S01 for the one wire Slice B's chain needs). Nothing
    else in Storage is required for either slice.
12. **Deferred**: full component catalog across both racks, S02–S04,
    inventory-discrepancy/missing-component horror hooks.

## 2.7 Maintenance passages

1. **Purpose**: claustrophobic connective tissue (§8) — not a "room" in
   the task sense; no locked tasks live here.
2. **Equipment**: none designed or needed — by definition these are the
   tunnel/elbow/connector segments already built (Storage connectors
   A–D, Life Support tunnel/bend, Engineering tunnel, Comms tunnels
   A/B, Airlock tunnel).
3–10. Not applicable — these are circulation space, not task space.
11. **Needed for Slice A/B**: none.
12. **Deferred/ongoing**: the "claustrophobic" identity (§8) is a
    lighting/width/sound question for general station polish, not a
    per-task requirement — reasonable to address as general station
    atmosphere work outside this task-focused milestone.

## 2.8 Airlock / EVA

1. **Purpose**: exposed/dangerous (§8); hosts A01–A07, all explicitly
   **"later-phase"** per §32 itself.
2. **Equipment (existing)**: a sealed hatch assembly (door, rim, wheel,
   bolts, stripes) at the end of a long tunnel — reads correctly as
   "you have reached the airlock, it is shut," appropriately foreboding
   for a system that isn't playable yet.
3–10. **Deliberately not specified further in this pass** — per §32,
   A01–A07 require suit-check and EVA systems that do not exist and are
   not needed for Slice A/B. Speculatively furnishing an airlock
   interior now would be exactly the "building infrastructure before a
   task needs it" (§47) this audit was told to avoid.
11. **Needed for Slice A/B**: none.
12. **Deferred in full**: the entire Airlock/EVA interior and all of
    A01–A07, consistent with the design doc's own phasing.

---

# PART 3 — TASK DATABASE READINESS AUDIT

Every task below is checked against the 5 readiness criteria (name/
purpose, procedure, physical interaction, equipment/room layout,
dependencies/outcomes) plus a verdict. "Room layout" now reads **yes**
for any task whose room has a Part-2 spec above (all of them do, even
if marked deferred) — the question is whether that spec actually placed
the *specific* equipment the task needs, noted per-row.

Legend for the verdict column: **READY** (ready to implement when its
turn comes in Part 7's order) · **CHAIN** (ready, but only makes sense
built together with its chain, per §33) · **DEFER** (intentionally
deferred — later phase or horror-dependent) · **GAP** (a real
specification gap exists — see note).

## 3.1 Control Room

| ID | Task | Name/Purpose | Procedure | Interaction | Equipment | Deps/Outcomes | Verdict |
|---|---|---|---|---|---|---|---|
| C01 | Morning Station Inspection | yes | yes (§27 checklist) | computer diagnostics (needs the new workstation screen, 2.2) | gap until workstation screen built | yes (normal / abnormal→followup) | **READY** (Slice A — fully specced Part 4) |
| C02 | Run Subsystem Diagnostic | yes | yes | computer diagnostics | needs workstation screen | yes | **CHAIN** (Slice B — Part 4) |
| C03 | Investigate Abnormal Reading | yes | yes | diagnostic reasoning | needs workstation screen | yes | READY (post-slices) |
| C04 | Compare Conflicting Sensors | yes | partial — "player determines which evidence is trustworthy" has no concrete UI/criteria yet | diagnostic reasoning | needs workstation screen | partial | **GAP** — needs a concrete comparison procedure before implementation (not blocking Slice A/B) |
| C05 | Verify Repaired System | yes | yes | computer diagnostics | needs workstation screen | yes | **CHAIN** (Slice A & B — Part 4) |
| C06 | Review Camera Footage | yes | yes for "normally nothing happens"; horror branch undesigned (expected — horror is later) | computer diagnostics / search-observation | needs workstation screen; reuses existing surveillance feeds | yes (normal path) | READY (normal path only) |
| C07 | Review Maintenance Record | yes | **ambiguous — see Open Question 1** (is this the player's own daily log, or a separate station-generated history?) | computer diagnostics | needs workstation screen | partial | **GAP** |
| C08 | Manually Test Subsystem | yes | yes | physical control → computer confirmation | the existing `ToggleSwitch`/`ControlPanel` pair is a strong candidate prop (Open Question 2) | yes | READY (post-slices) |

## 3.2 Engineering

| ID | Task | Name/Purpose | Procedure | Interaction | Equipment | Deps/Outcomes | Verdict |
|---|---|---|---|---|---|---|---|
| E01 | Inspect Electrical Panel | yes | yes | physical inspection | panel prop needed (2.3 — reuse `EngineeringCabinet1`) | yes | **CHAIN** (Slice B) |
| E02 | Trace Electrical Circuit | yes | yes ("wrong paths simply fail, no punishment") | circuit tracing | same panel | yes | **CHAIN** (Slice B) |
| E03 | Replace Fuse | yes | yes | sequential disassembly/reassembly + component matching | needs a fuse sub-prop (deferred) | yes | READY (post-slices) |
| E04 | Replace Connector | yes | yes | same family as E03 | needs a connector sub-prop (deferred) | yes | READY (post-slices) |
| E05 | Replace Damaged Wire | yes | yes, and the most detailed procedure in the whole doc (15 steps, §23) | sequential disassembly/reassembly + component matching + travel | same panel + Storage wire bin | yes | **CHAIN** (Slice B — Part 4 & 6) |
| E06 | Tighten Loose Connection | yes | yes | repeated clicking (explicitly suggested) | one small sub-prop (2.3 — minimal, Slice-A-scoped) | yes | **READY** (Slice A — Part 4) |
| E07 | Battery Inspection | yes | yes | physical inspection | battery prop (2.3 — reuse `MachineryHousing`, pending Open Question 3) | yes | READY (post-slices) |
| E08 | Cooling-System Inspection | yes | yes (sound is the clue) | physical inspection + sound-based diagnosis | cooling prop (2.3 — pending Open Question 3) | yes | READY (post-slices) |
| E09 | Diagnose Intermittent Electrical Fault | yes | yes ("fault not reproduced" explicitly valid) | diagnostic reasoning + repeated tests | same panel | yes | READY (post-slices) |
| E10 | Power Rerouting | yes | yes | valve/sequence-style procedure (breaker order matters) | same panel (needs an alternate-bus concept — minor gap) | yes | READY (post-slices) |
| E11 | Battery Overheating | yes | yes | limited QTE (explicitly suggested) | battery prop | yes | DEFER (emergency tier — not needed until the pacing director exists) |
| E12 | Electrical Short | yes | yes | diagnostic reasoning + physical inspection | same panel | yes | DEFER (emergency tier) |

## 3.3 Life Support

| ID | Task | Name/Purpose | Procedure | Interaction | Equipment | Deps/Outcomes | Verdict |
|---|---|---|---|---|---|---|---|
| L01 | Filter Inspection | yes | yes | physical inspection | filter prop (2.4, not yet built) | yes | READY (post-slices) |
| L02 | Filter Replacement | yes | yes | valve sequencing + component matching + Storage trip | filter prop + Storage filter bin (not yet built) | yes | **CHAIN** (post-slices) |
| L03 | Airflow Inspection | yes | yes | physical inspection + sound | needs an airflow indicator (not yet built) | yes | READY (post-slices) |
| L04 | Valve Procedure | yes | yes (order matters, explicit) | valve/pressure sequencing | valve manifold (2.4) | yes | READY (post-slices) |
| L05 | Pressure Leak Investigation | yes | yes | leak detection + physical inspection | pressure gauge + manifold | yes | READY (post-slices) |
| L06 | Condensation Investigation | yes | yes | physical inspection | pipe/joint prop (not yet built) | yes | READY (post-slices) |
| L07 | Environmental Sensor Calibration | yes | yes | calibration/tuning | a dial (not yet built) | yes | READY (post-slices) |
| L08 | Pump Diagnosis | yes | yes ("listen first") | sound-based diagnosis + physical inspection | pump prop w/ 3D audio (2.4) | yes | READY (post-slices) |
| L09 | Rapid Pressure Loss | yes | yes | valve sequencing under time pressure | manifold | yes | DEFER (emergency tier) |
| L10 | CO2 Spike | yes | partial — "determine scrubber/sensor/airflow issue" needs a concrete decision procedure | diagnostic reasoning | needs a scrubber concept (not yet designed) | partial | **GAP** + DEFER (emergency tier) |

## 3.4 Communications

| ID | Task | Name/Purpose | Procedure | Interaction | Equipment | Deps/Outcomes | Verdict |
|---|---|---|---|---|---|---|---|
| M01 | Communications Diagnostic | yes | yes | computer-style diagnostics | console (2.5, not yet built) | yes | READY (post-slices) |
| M02 | Signal Calibration | yes | yes | calibration/tuning | console dial | yes | **CHAIN** (post-slices) |
| M03 | Antenna Alignment | yes | yes | hold/steady | alignment control (2.5) | yes | **CHAIN** (post-slices) |
| M04 | Weak Signal Investigation | yes | yes | diagnostic reasoning | console | yes | **CHAIN** (post-slices) |
| M05 | Communications Component Replacement | yes | yes | component matching + Storage trip | console + Storage comms bin (not yet built) | yes | **CHAIN** (post-slices) |
| M06 | Interference Investigation | yes | yes | sound + tuning + frequency comparison | console | yes | READY (post-slices) |
| M07 | Unusual Transmission Investigation | yes | **the normal-world (pre-horror) version is undescribed** — §30 only describes the horror-capable branch | diagnostic reasoning | console | partial | **GAP** — needs a mundane baseline behavior defined before this is implementable as an *ordinary* task |

## 3.5 Storage

| ID | Task | Name/Purpose | Procedure | Interaction | Equipment | Deps/Outcomes | Verdict |
|---|---|---|---|---|---|---|---|
| S01 | Retrieve Component | yes | yes | search/observation + inventory identification | one wire bin (Slice B scope, 2.6) | yes | **CHAIN** (Slice B — Part 4 & 6) |
| S02 | Component Matching | yes | yes | component matching | needs ≥2 visually-similar components to contrast (deferred) | yes | READY (post-slices) |
| S03 | Inventory Discrepancy | yes | yes | inventory identification | needs a tracked inventory count (depends on the task-state proposal, Part 7) | yes | READY (post-slices, after task-state exists) |
| S04 | Missing Component Investigation | yes | yes as a *mechanic*; explicitly a "major future horror hook" (§31) so its *payoff* is intentionally undesigned yet | search/observation | same | yes (search outcome only) | DEFER (horror-dependent) |

## 3.6 Airlock / EVA

| ID | Task | Name/Purpose | Procedure | Interaction | Equipment | Deps/Outcomes | Verdict |
|---|---|---|---|---|---|---|---|
| A01 | Suit Inspection | yes | yes | physical inspection | no suit prop exists | yes | DEFER (later-phase, §32) |
| A02 | Airlock Pressure Test | yes | yes | valve/pressure sequencing | no airlock interior yet (2.8) | yes | DEFER |
| A03 | External Inspection | yes | yes ("no UI minigame required") | search/observation | no EVA exterior space yet | yes | DEFER |
| A04 | Antenna External Inspection | yes | yes | search/observation | same | yes | DEFER |
| A05 | External Component Repair | yes | yes | combined thinking+doing, multi-stage | same | yes | DEFER |
| A06 | Hull Damage | yes | yes | emergency interaction | same | yes | DEFER (emergency tier) |
| A07 | Solar Array Observation | yes | yes for "normal"; horror branch intentionally later | search/observation | same | yes | DEFER |

## 3.7 Cross-cutting findings

- **No contradictions in the locked task IDs/names/descriptions
  themselves** — the database is internally consistent. The gaps found
  are all "procedure under-specified for implementation," not
  conflicts with other locked material.
- **Genuine specification gaps** (flagged **GAP** above, none blocking
  Slice A/B): C04, C07, L10, M07. Each needs a short, focused follow-up
  design pass before implementation — not proposed to solve here, since
  none affect Slice A/B and inventing their resolution now would be
  exactly the "silently convert an assumption into a locked decision"
  this task warned against.
- **Backlog/system tasks** (§26) — confirmed still appropriate as
  non-interactive: the Control "backlog examples" list in §27 (station
  integrity, historical readings, emergency supplies, restocking,
  routine reports/messages, transmitter/receiver status, battery
  status, temperature/humidity). These remain correctly un-promoted to
  dedicated tasks; no change proposed.
- **No new tasks are proposed.** The one genuine mechanic gap this audit
  surfaced (carrying one physical item) is infrastructure the existing
  database already assumes (§19/§20 and the E05/S01 chain depend on it)
  — it is not a new *task*, so it's handled as a system proposal in
  Part 7, not an addition to the task catalog.

---

# PART 4 — TASK INTERACTION SPECIFICATION FORMAT [NEW SPEC]

## 4.1 Reusable format

```
### <ID> — <Exact Locked Name>
Purpose: <why a technician would do this>
Starting condition: <what must be true for this task to become available>
Initial state: <what the player perceives at the very start>
Location: <room, and which MovementNode(s)>
Requires: <objects/tools/components the player must have or use>
Player-visible info: <what the game shows/tells the player>
Procedure:
  1. ...
Interaction primitive: <one or more from §22>
Expected duration: <from the locked frequency/weight table>
Success feedback: <what the player sees/hears on success>
Other outcomes: <per §25, where applicable>
State changes: <what persists after this task>
Dependencies/prerequisites: <what must come before>
Travel required: <yes/no, which room>
Must carry an item: <yes/no, which>
Verification: <how/when correctness is confirmed>
Ends when: <the exact end condition>
Logged as: <how it's represented in station systems/logs>
Implemented vs proposed: <explicit>
```

This format is applied in full below only to the 8 tasks Slice A and
Slice B actually need (C01, C02, C05, E01, E02, E05, E06, S01) —
applying it to all 48 now would itself be "implementing the task
database" in substance even without writing code, which the task
explicitly said not to do. The format is ready to reuse unchanged for
the rest, in the dependency-aware order Part 7 lays out.

## 4.2 C01 — Morning Station Inspection

- **Purpose**: establish "everything is normal" at the start of the day;
  the player's first real use of the workstation.
- **Starting condition**: player is seated at the Control Room
  workstation (new screen, §2.2); always available once per day, any
  time after arriving at Control.
- **Initial state**: screen shows a single "Station Inspection" summary
  view (not 8 separate screens, per §27) with 8 readout rows: power,
  battery, pressure, O2, CO2, temperature, communications, structural.
- **Location**: Control Room, console seat.
- **Requires**: nothing carried.
- **Player-visible info**: 8 labeled values, each with a normal-range
  indicator (color or simple "OK"/"!" marker) — no numeric tuning
  required of the player for Slice A; **[OPEN QUESTION 5]** whether C01
  should ever be able to roll an abnormal reading in Slice A specifically
  (see Part 5).
- **Procedure**: (1) sit at workstation (already works — reuses
  `sleep_state.gd`'s seating approach); (2) open the Inspection screen
  (one click, §13's "1 click ideal"); (3) read the 8 rows; (4)
  acknowledge/close.
- **Interaction primitive**: Simple click/action + Search/observation
  (reading the readout).
- **Expected duration**: ~1–2 minutes (locked).
- **Success feedback**: "Station nominal" confirmation + (Slice A) the
  normal maintenance assignment becomes visible (E06, per §34).
- **Other outcomes**: abnormal reading → follow-up (C03) — **out of
  scope for Slice A** (Slice A's spec in Part 5 keeps this path
  unreachable so a normal day is always completable, per your explicit
  instruction).
- **State changes**: marks C01 done-for-today; unlocks the day's
  assignment.
- **Dependencies/prerequisites**: none (first task of the day).
- **Travel required**: no (already at Control for this check).
- **Must carry an item**: no.
- **Verification**: none needed — it's an inspection, not a repair.
- **Ends when**: player closes the Inspection screen after having
  opened it at least once.
- **Logged as**: an entry in the day's maintenance record (ties into
  Open Question 1).
- **Implemented vs proposed**: 100% proposed. Needs the new workstation
  screen (§2.2) and the task-state proposal (Part 7) to mark it done
  and reveal the assignment.

## 4.3 C02 — Run Subsystem Diagnostic

- **Purpose**: the player-initiated check that surfaces Slice B's fault.
- **Starting condition**: seated at the workstation; available any time.
- **Initial state**: a subsystem picker (Power / Life Support /
  Communications / Structural, etc.).
- **Location**: Control Room, console seat.
- **Requires**: nothing carried.
- **Player-visible info**: a subsystem list; after selecting one and
  initiating, a short "running..." beat, then a result line.
- **Procedure**: (1) select subsystem (Power, for Slice B); (2) initiate;
  (3) observe the result line.
- **Interaction primitive**: Simple click/action + Computer diagnostics.
- **Expected duration**: ~30–60s (locked).
- **Success feedback**: result text — for Slice B, specifically
  "**Fault detected: Engineering power circuit**" rather than "normal."
- **Other outcomes**: normal / warning / fault / intermittent /
  inconclusive (locked, §27) — Slice B always rolls "fault" (Open
  Question 6 covers how task selection/rolling works in general).
- **State changes**: sets the active fault target (which panel, which
  wire) that E01/E02 will reveal — this is the first piece of real
  "task state" the proposal in Part 7 needs to hold.
- **Dependencies/prerequisites**: C01 already done (keeps the day in
  order, though not strictly required by the fiction).
- **Travel required**: no.
- **Must carry an item**: no.
- **Verification**: n/a (this task *creates* the thing to verify later).
- **Ends when**: result line is shown and acknowledged.
- **Logged as**: a diagnostic entry noting which subsystem and result.
- **Implemented vs proposed**: 100% proposed.

## 4.4 C05 — Verify Repaired System

- **Purpose**: close the loop — confirm a repair actually worked.
- **Starting condition**: the repair task this verifies (E06 for Slice
  A; E05 for Slice B) has been marked complete.
- **Initial state**: workstation shows the same subsystem check used to
  find the fault, now available to re-run.
- **Location**: Control Room, console seat.
- **Requires**: nothing carried.
- **Player-visible info**: before the repair, re-running this check
  would show the original fault/abnormal state; after, it shows normal.
- **Procedure**: (1) open the relevant check; (2) run it; (3) observe
  "normal."
- **Interaction primitive**: Computer diagnostics.
- **Expected duration**: ~30–60s (locked).
- **Success feedback**: "System nominal" + the day's workload item is
  cleared (§16).
- **Other outcomes**: if the player runs C05 **before** actually
  completing the repair, it must report the still-broken state, not
  silently pass — this is the dependency-gate requirement from Part 6.
- **State changes**: marks the chain complete; for Slice A, this ends
  the workday (per §34).
- **Dependencies/prerequisites**: E06 (Slice A) or E05 (Slice B) must
  already be marked complete.
- **Travel required**: yes — back to Control from Engineering.
- **Must carry an item**: no (the player should have already returned
  any tool/component before this — see Part 6).
- **Verification**: this task *is* the verification step.
- **Ends when**: "normal" result is shown and acknowledged.
- **Logged as**: repair confirmed, subsystem marked healthy.
- **Implemented vs proposed**: 100% proposed.

## 4.5 E01 — Inspect Electrical Panel

- **Purpose**: physically locate what C02's diagnostic only pointed at
  abstractly.
- **Starting condition**: C02 has flagged the Engineering power circuit
  (Slice B) — or, read generically, any time the player wants to check
  the panel.
- **Initial state**: closed panel housing (`EngineeringCabinet1`,
  repurposed per §2.3) with a simple "open panel" affordance.
- **Location**: Engineering, at `EngineeringA`.
- **Requires**: nothing carried.
- **Player-visible info**: once opened, a simple schematic/physical view
  showing breakers, a few wires, connectors, with the damaged wire
  visually distinct (color, scorch mark, or a hanging/loose end) —
  matching §28's outcome list (loose connector / heat damage / damaged
  wire / tripped breaker / nothing obvious).
- **Procedure**: (1) walk to the panel; (2) open it (click); (3)
  physically inspect (hover/click each sub-element, or a single
  "inspect" action that reveals all of them at once — **[OPEN QUESTION
  7]**, see below); (4) identify the damaged wire.
- **Interaction primitive**: Physical inspection.
- **Expected duration**: ~1–2 minutes (locked).
- **Success feedback**: the damaged wire is visually marked/highlighted
  once found.
- **Other outcomes**: for a *different* fault than Slice B's (loose
  connector, tripped breaker) this same inspection would reveal a
  different outcome — same prop, different internal state, per §25.
- **State changes**: sets "damaged wire located" — a prerequisite for
  E02.
- **Dependencies/prerequisites**: C02 should have run first narratively,
  though the panel itself doesn't strictly need to check this (the
  player can always inspect the panel; it just won't matter yet if no
  fault is active).
- **Travel required**: yes, to Engineering.
- **Must carry an item**: no.
- **Verification**: n/a — this task produces information, not a repair.
- **Ends when**: the player has visually located the damaged wire.
- **Logged as**: not separately logged — folds into the eventual C05
  verification.
- **Implemented vs proposed**: 100% proposed. Needs the panel prop
  script (§2.3).

## 4.6 E02 — Trace Electrical Circuit

- **Purpose**: confirm *which* wire/run is actually responsible,
  teaching the player to read the panel rather than just clicking the
  one obviously-damaged-looking thing.
- **Starting condition**: E01 has located the damaged wire.
- **Initial state**: the panel's internal wiring is visible (opened by
  E01).
- **Location**: Engineering, same panel.
- **Requires**: nothing carried.
- **Player-visible info**: a small number of distinct wire runs from
  breakers to components, at least one clearly leading toward the
  flagged outlet/device.
- **Procedure**: (1) with the panel open, click along/select the wire
  run that leads from the flagged breaker to the affected device; (2)
  wrong selections simply don't confirm anything (§28 — "fail to
  identify the target," not a penalty); (3) correct selection confirms
  the circuit.
- **Interaction primitive**: Circuit tracing.
- **Expected duration**: ~1–3 minutes (locked).
- **Success feedback**: the traced run highlights end-to-end; "circuit
  confirmed" message.
- **Other outcomes**: none beyond confirm/not-yet — this task doesn't
  have a failure state per §28's own explicit design rule.
- **State changes**: confirms the damaged wire's exact spec (what
  replacement it needs) — this is the value S01 reads.
- **Dependencies/prerequisites**: E01.
- **Travel required**: no (same location as E01).
- **Must carry an item**: no.
- **Verification**: n/a.
- **Ends when**: the correct run is traced.
- **Logged as**: folds into C05.
- **Implemented vs proposed**: 100% proposed.

## 4.7 E05 — Replace Damaged Wire

- **Purpose**: the actual physical repair — Slice B's central task.
- **Starting condition**: E02 has confirmed the circuit **and** the
  player is currently carrying the matching wire from Storage (S01).
- **Initial state**: panel open, damaged wire visible, player holding
  the new wire (visible in-hand, consistent with the laptop/held-object
  precedent).
- **Location**: Engineering, same panel.
- **Requires**: the carried wire (matching S01's output).
- **Player-visible info**: a clear "isolate power" affordance (e.g. the
  breaker from E02's trace) before the wire itself becomes removable —
  this is where §23's 15-step procedure gets compressed into player-
  facing beats, not 15 individual clicks.
- **Procedure** (compressing §23 into the actual player-facing steps —
  the remaining sub-steps, like "route/secure/reassemble," are
  presented as one continuous physical animation/action per click, not
  15 separate inputs, per §21's "abstract away boring repetition"):
  1. Isolate power (click the flagged breaker — pairs naturally with
     E02's trace).
  2. Disconnect and remove the damaged wire (click).
  3. Connect the carried replacement wire (only enabled if the player
     is actually carrying the correct one — see Open Question 4).
  4. Restore power (click the breaker again).
- **Interaction primitive**: Sequential disassembly/reassembly +
  Component matching.
- **Expected duration**: ~2–4 minutes (locked).
- **Success feedback**: panel indicator light changes from
  fault-red to nominal-green (reusing the exact visual language the
  existing `ControlPanel`/`ToggleSwitch` pair already established —
  not inventing a new feedback color language).
- **Other outcomes**: attempting step 3 while carrying the *wrong* item
  (or nothing) must clearly fail without penalty — a short "this isn't
  the right part" message, not a lockout (Part 6 covers this exactly).
- **State changes**: marks the repair physically complete; power is
  restored.
- **Dependencies/prerequisites**: E02 complete, correct wire in hand.
- **Travel required**: no (already at the panel, having returned from
  Storage).
- **Must carry an item**: **yes** — the retrieved wire, until step 3
  consumes it.
- **Verification**: the panel's own green light is local confirmation;
  C05 is the authoritative/remote verification.
- **Ends when**: power is restored (step 4) and the panel reads normal.
- **Logged as**: a repair entry, referenced by C05.
- **Implemented vs proposed**: 100% proposed. Depends on the carry-item
  proposal (Part 7) existing first.

## 4.8 E06 — Tighten Loose Connection

- **Purpose**: Slice A's single hands-on repair — intentionally the
  simplest Engineering task in the whole database (§28: "a good place
  for a simple repeated-click interaction").
- **Starting condition**: C01 has produced the normal daily assignment.
- **Initial state**: a single small prop near `EngineeringA` (**not**
  the full panel — see §2.3.11) showing a visibly loose fitting (a
  bolt/clamp slightly askew, or a connector visibly not seated).
- **Location**: Engineering, near `EngineeringA`.
- **Requires**: nothing carried **unless** Open Question 8 (below)
  decides a tool should be required even for this simplest task.
- **Player-visible info**: the loose fitting itself is the only
  information needed — this is an intentionally low-information task.
- **Procedure**: (1) find the connection (walk up, it's visually
  obvious); (2) use the tool (if required, see Open Question 8); (3)
  tighten (repeated clicks, per §23/§28); (4) verify (the fitting
  visibly seats correctly once enough clicks register).
- **Interaction primitive**: Repeated/rapid clicking.
- **Expected duration**: ~30s–1m (locked) — the shortest task in the
  entire database, deliberately.
- **Success feedback**: fitting visibly seats flush; a short
  "tightened" confirmation.
- **Other outcomes**: none — per §28's own note, this task has no
  interesting failure mode; it's a calibration task for teaching the
  interaction, not a diagnostic one.
- **State changes**: marks the day's assigned repair complete —
  satisfies C05's dependency check.
- **Dependencies/prerequisites**: C01 done (assignment exists).
- **Travel required**: yes, Control → Engineering.
- **Must carry an item**: no (pending Open Question 8).
- **Verification**: visual (the fitting seats) — C05 is the remote/
  authoritative confirmation.
- **Ends when**: the repeated-click meter completes.
- **Logged as**: a repair entry, referenced by C05.
- **Implemented vs proposed**: 100% proposed. This is the **smallest
  implementable unit in the whole catalog** — deliberately the first
  thing to build (Part 7).

## 4.9 S01 — Retrieve Component

- **Purpose**: Slice B's logistics beat — "the travel and logistics are
  part of the task" (§23).
- **Starting condition**: E02 has specified exactly which wire is
  needed.
- **Initial state**: a labeled wire bin on one of the two existing
  racks, showing a readable spec matching what E02 determined.
- **Location**: Storage, at `StorageA` or `StorageB` (whichever rack
  hosts the wire bin, per §2.6).
- **Requires**: nothing carried yet — this task is *how* the player
  starts carrying something.
- **Player-visible info**: the requested spec (shown by the workstation/
  panel earlier) and the bin's own label, so the player can visually
  match them (§31/S02's "compare part number, shape, connector, color,
  label" — S01 only needs label-matching; full S02 multi-attribute
  matching is deferred).
- **Procedure**: (1) travel to Storage; (2) read the requested spec
  (already known from E02 — no re-lookup UI needed for Slice B's single-
  item case); (3) navigate to the correct bin; (4) identify it by label;
  (5) pick it up.
- **Interaction primitive**: Search/observation + Inventory
  identification.
- **Expected duration**: ~30s–1m (locked, low end of its 0.5–1.0 weight
  range, appropriate for a single unambiguous bin).
- **Success feedback**: the wire becomes the player's one carried item
  (visible in-hand or on a simple carry indicator — see Part 7).
- **Other outcomes**: picking up a *wrong* bin (once more than one
  exists, post-Slice-B) should simply let the player carry the wrong
  item, which then fails at E05's step 3 rather than being blocked here
  — consistent with §28's "fail to identify the target" philosophy
  applied to retrieval instead of tracing.
- **State changes**: player now carries "wire (matching spec X)."
- **Dependencies/prerequisites**: E02 complete (so the spec is known).
- **Travel required**: yes, Engineering → Storage.
- **Must carry an item**: this task **produces** the carried item.
- **Verification**: n/a.
- **Ends when**: the wire is picked up.
- **Logged as**: not separately logged.
- **Implemented vs proposed**: 100% proposed. Depends on the carry-item
  proposal (Part 7).

---

# PART 5 — SLICE A FULL SPECIFICATION: "MY FIRST WORKDAY" [NEW SPEC]

## 5.1 Audit of what already exists for Slice A

| Slice A beat | Status |
|---|---|
| Wake up | **not implemented** — no sleep/wake transition exists (1.11) |
| Automatic wristwatch check | **not implemented** — no time system (1.11) |
| Optional personal routine | **not implemented**, and per §12/§34 intentionally skippable — no blocker |
| Leave Living Quarters | **implemented** — walking to Control already works |
| Sit at workstation, C01 | **not implemented** — needs the new workstation screen |
| Receive assignment | **not implemented** — needs minimal task-state |
| Travel to Engineering | **implemented** (nav graph, 1.2) |
| E06 Tighten Loose Connection | **not implemented** — needs the one small prop (2.3.11) |
| Travel back to Control | **implemented** |
| C05 Verify | **not implemented** — needs workstation screen + task-state |
| End workday | **not implemented** — no day-end concept exists |
| Return to Living, evening routine (optional), sleep | **get-up/sit exist; the rest does not** |

**Conclusion**: every *mechanical* beat (movement, sitting, physical
interaction) already exists; every *structural* beat (time, task state,
workstation UI, day-end/sleep transition) does not. This matches the
audit in Part 1 precisely — Slice A is blocked on exactly two small
systems (workstation screen, minimal task-state) plus one small prop
(E06's loose connection), not on anything environmental or topological.

## 5.2 Minimum mechanics needed to make Slice A playable

1. **A Control Room workstation screen** (reuses the laptop's SubViewport-
   on-mesh pattern, §2.2) showing C01's inspection view and later C05's
   verify view. This is the single biggest new system Slice A needs,
   and it is a close structural cousin of something already built and
   proven (the laptop) — low risk.
2. **A minimal day/task-state object** (see Part 7's proposal) tracking
   exactly three booleans for Slice A: `c01_done`, `e06_done`,
   `c05_done` — nothing more elaborate is needed yet.
3. **E06's one small prop** in Engineering (§2.3.11).
4. **A day-end → sleep → "next day" transition.** This is Slice A's one
   genuinely open design question (§5.4, Open Question 1) — everything
   else is a small, concrete addition to existing patterns.

No new movement, interaction-controller, or camera system work is
needed — this is a deliberate consequence of Part 1's audit (those
systems are already Status A).

## 5.3 Task states, transitions, feedback, failure cases

```
AWAKE (new day starts here)
  → (wristwatch auto-check — a HUD line, see Open Q1 — no player input)
  → (optional personal routine — entirely skippable, no state tracked)
  → WORKDAY (player leaves Living Quarters)
       → at Control: open workstation → run C01
            C01 outcome: "normal" (ALWAYS, for Slice A — see 5.4)
            → assignment revealed: "E06 — Engineering, tighten the
              loose connection near [panel]."
       → player travels to Engineering (free navigation, no gating)
       → at the E06 prop: perform the repeated-click interaction
            on success → prop visibly seats; e06_done = true
            (no failure state for E06, per §28/4.8)
       → player travels back to Control (free navigation)
       → at Control: open workstation → run C05
            IF e06_done == false: report "connection still loose" and
              do NOT clear the day (gentle, non-punishing feedback —
              the player simply hasn't finished yet; this is not a
              failure state, just an accurate status check)
            IF e06_done == true: report "verified — all nominal";
              c05_done = true; workday ends
       → player returns to Living Quarters (free navigation)
       → optional evening routine (skippable)
       → sleep (bunk interact — already works mechanically)
       → NEXT DAY (see Open Question 1 for what this actually resets)
```

No hard failure state exists anywhere in Slice A, by design — this
matches your explicit instruction that a normal workday must be
completable without any horror event, and matches §25/§28's general
preference for "didn't finish yet" over punitive failure.

## 5.4 Keeping Slice A a guaranteed-normal day

C01 and C05 are **hard-restricted to their "normal" outcome** for Slice
A specifically — the general task design (Part 3/4) supports abnormal
branches, but Slice A's own task-state should simply never roll one.
This is a deliberate, explicit scope decision for this first slice, not
a claim that C01/C05 can *never* branch once the catalog expands.

## 5.5 Keeping optional content optional and non-tedious

- Morning/evening personal routines: **zero required interactions**.
  The player can walk straight through Living Quarters both ways.
  (2.1.11/2.1.12 defers the actual hygiene/dressing scripts — they
  aren't needed for Slice A to be playable, and per §12, even once
  added they should be quick single interactions, never repeated
  mandatory clicking.)
- Travel: already smooth and fast per the existing movement tuning (1.8
  m/s, tested) — no artificial waiting is introduced anywhere in this
  spec.
- E06 itself is the shortest task in the entire database (~30s–1m) —
  appropriate for a *first* repair that's mostly teaching the player
  "this is how tasks work," not testing them.

## 5.6 Open questions specific to Slice A

**[OPEN QUESTION 1] — What does "sleep → next day" actually do?**
Three options, increasing in scope:
  - **(a) Minimal**: sleep just resets `c01_done`/`e06_done`/`c05_done`
    to false and the game continues in the same scene — no actual
    time/calendar system, no visual transition beyond what already
    exists (screen fade or similar). Lowest implementation cost;
    sufficient to make Slice A *loop* and prove the daily rhythm.
  - **(b) Day counter**: adds a simple integer "Day N" plus the
    wristwatch/clock display problem from §10, without yet wiring up
    any time-of-day lighting or scheduling. Medium cost; needed before
    §10's later horror hooks (clock disagreement etc.) can ever work.
  - **(c) Full time system**: a real in-game clock driving lighting,
    pacing-director timing (§17), etc. High cost, not needed for
    Slice A or B.
  My recommendation (not assumed as decided): **(a)** for this
  milestone, with (b) scheduled explicitly in Part 7 once more than one
  day's content exists to tell apart. **This needs your decision before
  implementation begins**, since it changes how much of §10 gets built
  now vs. later.

**[OPEN QUESTION 5]** (referenced from 4.2): should C01 ever be capable
of a non-normal result during Slice A's own scope, or is "always normal"
a permanent property of *this specific slice's* instance of C01 (with
the general C01 task gaining real branching only once C03 is built)? I
recommend the latter — it costs nothing extra and keeps Slice A's
guarantee airtight.

---

# PART 6 — SLICE B FULL SPECIFICATION: FIRST DEPENDENCY CHAIN [NEW SPEC]

Control → Engineering → Storage → Engineering → Control, using the
locked electrical-fault example (§33, §34).

## 6.1 How the initial fault is selected/presented

C02 (Part 4.3) is the entry point. For Slice B specifically, C02's
subsystem-diagnostic roll is **pinned to "Power / Engineering fault"**
— the same "pin it for this slice, let it roll generally later"
treatment Slice A gives C01/C05 (§5.4). This keeps Slice B's chain
reliably reproducible for testing without yet building the general
fault-selection logic (**[OPEN QUESTION 6]**, below) that later content
will need.

## 6.2 How the diagnostic reveals a meaningful result

C02's result line explicitly names the room and subsystem ("Fault
detected: Engineering power circuit") — enough to send the player to
Engineering without naming the exact wire yet (that's E01/E02's job,
preserving the "diagnostic → investigation" structure in §33 instead of
collapsing it into one step).

## 6.3 How the player physically inspects the panel (E01)

Specified in full in Part 4.5. Key point for Slice B specifically: the
panel's internal state is pre-set to "damaged wire" (not loose
connector or tripped breaker — those are other chains, Part 3.2) the
moment C02 pins the Power fault.

## 6.4 How circuit tracing works (E02)

Specified in full in Part 4.6. For Slice B, exactly one wire run is the
correct target; all other visible runs simply don't confirm anything
when selected (no penalty, per §28).

## 6.5 How the damaged wire is identified

The outcome of E02 **is** the identification — once traced, the game
knows (and can now tell the player) the wire's replacement spec (e.g.
"16-gauge control wire, blue"). This spec is both: (a) shown to the
player as the thing to go find, and (b) stored as task-state so S01/E05
can check against it without the player needing to re-read/remember an
exact string.

## 6.6 How the required component is specified to the player

**[OPEN QUESTION 4]** — two reasonable options:
  - **(a) Visual/label only**: the player sees a label or color on the
    panel ("blue, 16ga") and must match it to a bin's own label in
    Storage, entirely by eye — matches S02's "color/label
    identification" vocabulary and needs no extra UI.
  - **(b) Workstation-tracked**: the required spec is also written to a
    simple "current objective" line visible at the workstation/HUD, so
    the player doesn't have to remember it across the Engineering→
    Storage walk.
  For Slice B (a single unambiguous bin, §2.6.11) either works
  identically in practice. I recommend **(b)** as the standing general
  rule once S02's multi-bin matching exists (so the player isn't forced
  to memorize a spec across a multi-minute walk), but **either is fine
  for Slice B specifically** — flagging so the decision is explicit
  rather than silently baked in.

## 6.7 How the player finds and retrieves the component (S01)

Specified in full in Part 4.9.

## 6.8 How the player carries and installs it

**[PROPOSAL — see Part 7 for the full system]**: one carried item at a
time (§19, locked philosophy); picking up the wire in Storage makes it
the player's held item; it stays held through ordinary movement (no
penalty, no drop-on-interact-with-something-else); "installing" is
E05's step 3 (Part 4.7), which consumes it back to empty-handed.

## 6.9 How power isolation/restoration are represented

E05 steps 1 and 4 (Part 4.7) — clicking the flagged breaker twice
(isolate, then restore), reusing the panel's own breaker sub-prop from
E01/E02 rather than inventing a separate isolation mechanic.

## 6.10 How repair verification works

E05's own panel light is local/immediate feedback; C05 (Part 4.4) back
at Control is the authoritative verification that ends the chain —
exactly mirroring Slice A's structure, which is intentional (teaches
the player the general "repair, then go verify" rhythm identically in
both slices).

## 6.11 What happens on an incorrect action

- Tracing the wrong wire run (E02): no effect, try again (§28).
- Picking up the wrong Storage bin (post-Slice-B, once >1 bin exists):
  allowed — the mistake surfaces later at E05 step 3, not blocked at
  pickup (6.8/Part 4.9).
- Attempting E05 step 3 while carrying the wrong item or nothing: a
  clear, non-punishing "that's not the right part" message; the
  breaker/panel state is untouched, so the player can simply go back to
  Storage and try again. **No progress is lost, no timer penalty.**
- Running C05 before E05 is actually complete: reports the accurate
  "still faulty" status (Part 4.4) rather than silently passing or
  erroring.

## 6.12 What state persists between rooms

Exactly three pieces of task-state, all simple booleans/strings:
`c02_fault_target` (set by C02, read by E01/E02/S01/E05), `e02_wire_spec`
(set by E02, read by S01/E05), `wire_carried` (set by S01, cleared by
E05). This is deliberately the entire Slice B state footprint — no
generic inventory array, no task-graph engine.

## 6.13 How dependencies prevent premature completion

Each gate is a **local check on the task that needs it**, not a central
rules engine (consistent with §47/§48's existing architecture
philosophy): E02 checks "has E01 run" before doing anything meaningful;
E05 step 3 checks "is the carried item's spec == `e02_wire_spec`"; C05
checks "is the Engineering fault's repaired flag true." Every check
lives on the object that needs it, exactly like `ControlPanel` already
checks its own two switches today (1.8) — this is a proven pattern, not
a new one.

## 6.14 Avoiding forced returns to Control between every room

Nothing in this spec routes the player back through Control between
Engineering and Storage — the chain is explicitly Control → Engineering
→ Storage → Engineering → Control (§34), matching the locked topology's
own guidance that Storage connects primarily to Engineering/Life
Support (§7) and that "the player must not be forced to return to
Control between every room" (§7's "Operational centrality" section).

---

# PART 7 — IMPLEMENTATION ORDER [NEW SPEC]

## 7.1 Foundational systems needed first (build once, reuse everywhere)

1. **[PROPOSAL] Minimal task-state object.** One new scene node (call it
   `DayPlan`, instanced in `main.tscn` alongside `SleepState` — **not**
   an autoload/singleton, consistent with §47's explicit warning and
   with how `SleepState` itself is already just a plain scene node).
   Holds a small, fixed set of typed fields for whatever the *current*
   slice needs (Slice A: 3 booleans; Slice B: adds the 3 fields from
   6.12) — **not** a generic key/value registry. Other nodes read it via
   an `@export var day_plan_path: NodePath`, exactly like `SleepState`
   already does for everything it depends on. Grows field-by-field as
   new slices are built; never becomes a generic "objective system."
2. **[PROPOSAL] Minimal carry-item system.** Lives on the `Player`
   node (or a small sibling node) as `var carried_item: Node = null`
   plus `pick_up(item)`/`place()`/`drop()` matching §19's five verbs
   exactly. An item is any node with a small duck-typed contract
   (`item_id: StringName`, maybe a `held_offset`) — same philosophy as
   `interact()`. Held item follows the camera at a fixed offset
   (reusing the exact technique already proven by the laptop's
   held-pose tweening, `laptop_view.gd`). No slots, no weight, no stacking
   — one item, full stop, matching the locked design exactly.
3. **Control Room workstation screen scene.** A direct structural reuse
   of `scenes/ui/session_log_screen.tscn`'s SubViewport-as-physical-
   screen pattern, with its own small `workstation_screen.gd` instead of
   `session_log_screen.gd`'s log-specific logic. This is the only new
   *rendering* technique Milestone 1 needs, and it's already de-risked
   by the laptop work.

## 7.2 Minimum room work required for Slice A

- Engineering: one small loose-connection prop near `EngineeringA`
  (§2.3.11) — not the full panel.
- Control Room: the workstation screen (7.1.3) at the existing console
  position.
- No other room needs any new geometry or props for Slice A.

## 7.3 First reusable physical interaction primitives to build

In this order, each unlocked by the previous:
1. Repeated-click interaction (needed by E06 first; reused later by
   E03/E04/battery-type tasks and the personal-routine brushing-teeth
   interaction).
2. Computer-diagnostic screen interaction (needed by C01 first; reused
   by every other Control task).
3. Physical inspection (opening a panel / revealing sub-state) (needed
   by E01 first; reused by E07/E08/L01/L03/L06/A01).
4. Circuit tracing (needed by E02 first; genuinely unique to
   Engineering's wiring tasks — no earlier reuse target, build it when
   E02 is built).
5. Search/observation + inventory identification (needed by S01 first;
   reused by S02/S04/A03/A04/A07).

## 7.4 Task-state and dependency requirements

Covered in 7.1.1 and Part 6.12/6.13 — no additional system beyond the
one `DayPlan` node and each task's own local checks.

## 7.5 Object pickup/carry requirements

Covered in 7.1.2 — required before E05/S01 can be built at all; not
required for Slice A (E06 carries nothing, per 4.8).

## 7.6 Component inventory and identification requirements

For Slice B: one labeled wire bin (§2.6.11) — no general inventory
system needed yet (S03's inventory-discrepancy task is explicitly
post-slice, Part 3.5, and depends on `DayPlan` already existing to
track counts against).

## 7.7 Verification and result feedback requirements

Reuses the existing `ControlPanel`/`ToggleSwitch` red/green status-light
visual language (already built, 1.8) for every task's local feedback;
the workstation screen (7.1.3) is the shared mechanism for remote/
authoritative feedback (C05 and friends).

## 7.8 Additional work required for Slice B specifically

Beyond Slice A's foundation: the carry-item system (7.1.2), the
Engineering panel's richer internal state (loose connector vs. damaged
wire vs. tripped breaker — Slice B only needs the "damaged wire" branch
populated, §6.3), and the one Storage wire bin (§2.6.11).

## 7.9 Tests required at each stage

Following this project's existing testing conventions (headless
`SceneTree` scripts under the scratchpad, real input-path simulation,
no "assume success because a function was called" shortcuts — exactly
as enforced throughout the laptop/camera work):

- `DayPlan`: a test that sets/reads each field and confirms no cross-
  talk between unrelated fields.
- Carry system: pick up / place / drop, confirm only one item is ever
  held, confirm movement/camera are unaffected while carrying.
- Workstation screen: open/close, confirm C01's 8 rows render, confirm
  it behaves like the laptop screen under the same camera-lock/Esc
  rules already proven (reuse, don't reinvent, that whole verified
  system).
- E06 prop: repeated-click completes, confirms `day_plan.e06_done`.
- Full Slice A: one end-to-end headless test walking the entire loop
  (wake → C01 → travel → E06 → travel → C05 → sleep), asserting state
  at each beat — mirroring the style of the existing
  `test_get_up_staged_sequence.gd`/`test_daily_log_behavior.gd` tests.
- Full Slice B: same end-to-end style, covering the 5-room chain and
  the "wrong item at E05" non-failure case explicitly (Part 6.11).
- Regression: full existing suite (22 files) must stay green, plus the
  whole-station capsule/locked-graph sweeps, exactly as enforced this
  round and last.

## 7.10 Which tasks/rooms can be deferred

Everything marked **DEFER** or **(post-slices)** in Part 3 — i.e., 40 of
the 48 locked tasks, and all of Life Support/Communications/Airlock's
props. Recommended expansion order once Slice A+B are solid and tested:
(1) the remaining Engineering tasks (richest existing prop base), (2)
Storage's remaining S02–S04 (small, high reuse of 7.1.2/7.3.5), (3)
Life Support (new room, moderate prop work), (4) Communications (new
room, moderate prop work), (5) emergency-tier tasks across all rooms
(need the pacing director, §17, which doesn't exist yet and is its own
future audit), (6) Airlock/EVA (explicitly later-phase, §32).

---

# RESOLVED DECISIONS AND PART 7.2 IMPLEMENTATION LOG

Every open question and proposal from the original audit was resolved
by the user and then implemented. This section is the permanent record
of those decisions, replacing the original "unresolved questions" list
(preserved in spirit below, each marked **[RESOLVED]**). Implementation
details are in the files listed; this section states the decision and
where to find it in code, not the code itself.

1. **[RESOLVED]** Sleep/day transition: minimal reset (Option A) --
   `scripts/station/day_plan.gd`'s `reset_for_new_day()`, invoked from
   `scripts/player/sleep_state.gd`'s `begin_sleep()` at the darkest
   point of a short eyes-closing -> held-dark -> eyes-opening sequence
   (a dedicated black `ColorRect` overlay, framed and timed as eyelids,
   not a generic scene fade). No day counter, no calendar, no
   simulation-time system. The automatic wristwatch glance is a short
   flavor-text HUD label with no real clock behind it. Daily-log
   behavior (session-only, no persistence) is unchanged.
2. **[RESOLVED]** C08/switches: the existing `ToggleSwitch`/
   `ControlPanel` pair is earmarked for a future C08 implementation
   (not built this round -- C08 is not in Slice A/B); its current
   appearance remains explicitly temporary.
3. **[RESOLVED]** `EngineeringMachineryHousing` is the cooling unit for
   E08, not the battery bank. E07/E11's battery-bank prop is separate,
   future work (not built this round -- neither task is in Slice A/B).
4. **[RESOLVED]** Difficulty/component memory: no difficulty framework
   was built. `DayPlan.show_component_hint()` is the single seam a
   future Easy/Hard system gates -- it currently always returns true
   (today's "Easy-equivalent" default), and both the Work Orders screen
   and the electrical panel's own trace message already route the
   required-component text through it, so hiding it later needs no
   task-logic changes.
5. **[RESOLVED]** C01/C05's "always normal" result is a Slice-A-only
   guarantee, not a permanent rule -- enforced simply by Slice A's own
   workstation logic never offering any other outcome, not by any
   restriction on C01/C05 themselves.
6. **[RESOLVED]** The general weighted task-selector remains a planned
   future system, preserved in the roadmap (Part 7.10), explicitly not
   built this round. `DayPlan.assign_daily_task()` and `trigger_fault()`
   are the two seams it will eventually replace (see each method's doc
   comment) -- both currently pin one hardcoded result for Slice A/B.
7. **[RESOLVED]** E01 uses one combined inspection action --
   `electrical_panel.gd`'s `interact()` advances a single internal
   stage machine (CLOSED -> INSPECTED -> TRACED -> REPAIRED); there are
   no individually-clickable sub-elements.
8. **[RESOLVED]** E06 requires no tool -- `loose_connection.gd`'s
   repeated-click interaction has no carry-item precondition at all.
9. **[IMPLEMENTED]** `scripts/station/day_plan.gd` -- a plain scene
   node (instanced in `main.tscn` as `DayPlan`, sibling to `SleepState`
   and `WorkstationState`), explicitly typed fields only, no registry.
10. **[IMPLEMENTED]** `scripts/player/carry_system.gd` -- one held item,
    `pick_up()`/`drop()`/`consume_if_matches()`, no slots/weight/stacks.
    First real carryable: `scripts/interactables/wire_component.gd`.
11. **[IMPLEMENTED]** `scripts/ui/workstation_screen.gd` +
    `scripts/interactables/workstation_console.gd` +
    `scripts/station/workstation_state.gd` -- the Control Room
    workstation, reusing the laptop's SubViewport-screen technique with
    its OWN independent camera-lock/zoom implementation (so neither
    system can regress the other). Navigation is key-driven (number
    keys + R + Esc), not raycast-to-UV mouse clicks, for the same
    reason the laptop avoided that -- see that script's class doc
    comment. Every implemented section is exactly one keypress from
    Home. Surveillance is read directly from the one real
    `SurveillanceConsole` instance (new `get_current_feed_texture()`/
    `get_current_camera_id()` getters) -- no second camera-selection
    state exists anywhere. Save/Load and Settings are present in the
    navigation but explicitly marked "not available in this build."

No design gap found in Part 3 (C04, C07, L10, M07) blocks Slice A/B --
still flagged for a future, separate focused pass, not resolved here.

## New files this round

- `scripts/station/day_plan.gd`, `scripts/station/workstation_state.gd`
- `scripts/player/carry_system.gd`
- `scripts/interactables/electrical_panel.gd` (attached to the existing
  `EngineeringCabinet1` node, not a new prop)
- `scripts/interactables/loose_connection.gd` +
  `scenes/interactables/loose_connection.tscn`
- `scripts/interactables/wire_component.gd` +
  `scenes/interactables/wire_component.tscn`
- `scripts/interactables/workstation_console.gd` +
  `scenes/interactables/workstation_console.tscn`
- `scripts/ui/workstation_screen.gd` +
  `scenes/ui/workstation_screen.tscn`

## Modified files this round

- `scripts/player/sleep_state.gd` (sleep/wake sequence)
- `scripts/interactables/surveillance_console.gd` (additive getters only)
- `scenes/main.tscn`, `scenes/player.tscn`, `scenes/player/player_body.tscn`
  (wiring the above into the world)

---

# ROUND 3: CONTROL ROOM WORKSTATION REVAMP

Driven by a real in-game screenshot and playtest feedback on Round 2's
workstation. All issues below were root-caused with runtime
measurements/renders, not assumed.

1. **Stacked monitor** — the new `WorkstationConsole` had been placed at
   almost the exact same (x,z) as the pre-existing `SurveillanceConsole`
   prop, 0.35m apart in Y, with overlapping bezel/backplate geometry.
   Fixed by hiding `SurveillanceConsole` (`visible = false`, its
   `CollisionShape3D` disabled) — it remains in the scene purely as the
   one surviving owner of camera-selection state (Approved Decision
   A.11 is unaffected: still exactly one owner, the workstation screen
   already only ever read from it, never duplicated it).
2. **Text too large / Home screen clipped** — root cause was NOT the UI
   layout (confirmed by rendering the raw SubViewport texture directly:
   every section's content was already complete and correctly laid
   out). The physical screen's `BoxMesh` does not map the full 0..1 UV
   range onto its front face by default — measured empirically with a
   calibration gradient texture (decile tick marks + a left-right color
   ramp) rendered onto the live mesh and read back pixel-by-pixel: only
   the left ~33% (horizontally) and top ~49% (vertically) of the
   texture was ever visible. Fixed with
   `StandardMaterial3D.uv1_scale = Vector3(3.03, 2.04, 1.0)` in
   `workstation_console.gd`, which rescales the mesh's native UV back
   out to the full 0..1 range. Also reduced font sizes station-wide in
   `workstation_screen.tscn` and fixed a real (separate, now moot but
   left fixed) Label sizing issue where content labels inside
   VBoxContainers were collapsing to ~1px wide without an explicit
   `custom_minimum_size`.
3. **Workstation looked sparse** — added 4 `ToggleSwitch` instances
   (master/comms/life-support/lighting, reusing the existing scene
   unchanged), 1 new `rotary_control.gd`/`.tscn` (a small, independent,
   duck-typed `interact()` prop, same philosophy as `toggle_switch.gd`),
   and 2 purely decorative status-light meshes, mounted below the main
   screen on the same backing wall using the exact same mounting
   rotation convention as the pre-existing switches. None of these are
   wired to any task logic — flavor/decoration only, not presented as
   controlling anything implemented.
4. **Sit-down transition** — `workstation_state.gd` was rewritten from a
   pure camera-zoom into a full sit-down: the player's actual position
   tweens into a seated spot (reusing the existing `SittingPose` and the
   existing bed sit-down's "swap pose only once settled" precedent),
   with a `sleep_state.gd`-style staged get-up (partial rise -> pose
   swap -> finish rising -> walk back) on Escape. Geometric constraint
   discovered and documented in-code: the authored `SittingPose`'s leg
   length (~0.88m) exceeds the available under-desk depth (~0.3-0.6m)
   at this console, so facing the frozen body the same direction as the
   camera would drive the feet through the back wall at any viable seat
   distance (verified numerically, not assumed) — the frozen body yaw
   and the camera's own aim are deliberately decoupled here (legs settle
   into open floor behind the chair; the camera independently faces the
   screen), not visible in practice at the screen-level camera pitch
   used. A proper desk-chair pose is deferred to the Milestone 2
   skeletal rig.
5. **Wire not found during playtest** — the Storage wire bin's collider
   was found to be embedded inside `StorageRack1`'s own solid CSG volume
   (invisible). Relocated to rest visibly on a small new shelf prop
   beside the rack. The first relocation attempt (directly in front of
   the rack face, near `StorageA`) introduced a real navigation
   regression — confirmed via `test_whole_station_capsule.gd` — because
   the rack's own face already sits only ~0.05m outside the player
   capsule's reach from `StorageA`, leaving no room for anything to
   protrude further. Re-placed further down the rack's length (near
   `StorageB`'s end, where the diagonal `StorageA|StorageB` path has
   already moved well away from the rack) — re-verified with zero new
   navigation failures.

## New files this round

- `scripts/interactables/rotary_control.gd` +
  `scenes/interactables/rotary_control.tscn`

## Modified files this round

- `scripts/station/workstation_state.gd` (full sit-down/get-up rewrite)
- `scripts/interactables/workstation_console.gd` (UV fix, texture wiring)
- `scripts/interactables/wire_component.gd` (pickup confirmation message)
- `scripts/interactables/surveillance_console.gd` (unshaded fix, unrelated to hiding it)
- `scenes/ui/workstation_screen.tscn` (typography, label sizing)
- `scenes/interactables/workstation_console.tscn` (larger screen/bezel)
- `scenes/main.tscn` (hid SurveillanceConsole, repositioned console,
  added switches/rotary/status lights, relocated wire + shelf)

---

# ROUND 4: MILESTONE 1 — HANDS-ON ELECTRICAL REPAIR

## Root cause of the "wire disappears" complaint

`electrical_panel.gd`'s `interact()` was a single combined click handler
on the cabinet's own big collider, advancing CLOSED → INSPECTED →
TRACED → REPAIRED on every click. At the REPAIRED transition it called
`carry_system.consume_if_matches()`, which `queue_free()`s the carried
node outright. There was no door state, no separate terminal target,
and no visual replacement for the consumed wire — any click anywhere on
the cabinet, once in the TRACED stage, deleted whatever was in the
player's hands.

## What was implemented (vs. Part 6's full original spec)

Part 6.8/4.7 originally specified a 4-sub-step repair (isolate the
flagged breaker → disconnect the damaged wire → connect the carried
wire, gated on carrying the correct part → restore power via the
breaker). **This round implements the terminal-targeting and visible-
installation core this milestone actually asked for, not that full
4-click breaker sequence** — the existing single-combined-click E01/E02
model (Approved Decision A.7) is preserved unchanged; only E05 gained
real targeting:

- **Door state** (new, independent of repair progress): the cabinet's
  own collider (`EngineeringCabinet1.interact()`) now does ONLY one
  thing — toggle `_door_open` and swap a small `AccessHatchCover`
  plate for the interior (`Terminal`/`IntactTerminal`/
  `DamagedWireVisual`). It never touches task state or the carried item.
  This is the actual fix: the wire-consuming action no longer lives on
  the same collider a generic "open the panel" click would hit.
- **Terminal targeting** (new): `Terminal` (correct) and
  `IntactTerminal` (a deliberately non-functional decoy, satisfying
  "wrong terminal preserves the carried wire") are separate
  `StaticBody3D` + `CollisionShape3D` nodes — NOT CSGShape3D children of
  the cabinet's own CSG tree. A CSG-nested child's `use_collision` was
  tried first and empirically found to merge into the parent's single
  combined collision shape rather than giving an independent raycast
  target (confirmed by a raycast aimed at the nested child being
  reported as hitting the parent cabinet instead) — the fix was to use
  the same plain `StaticBody3D` pattern every other small interactable
  in this project already uses (`toggle_switch.gd`, `rotary_control.gd`,
  `wire_component.gd`), not a new framework.
- **Physical installation** (new): `carry_system.gd` gained
  `take_carried_item_if_matches()`, a non-destructive sibling of the
  existing `consume_if_matches()` that returns the node instead of
  freeing it. `wire_component.gd` gained `mark_installed()`, which
  reparents the actual wire under `Terminal` at a fixed pose and
  disables its own pickup (`interact()`/`get_interact_prompt()` both go
  inert once `_installed`). The wire is never deleted — it becomes a
  permanent, visible, non-pickupable fixture, surviving door
  close/reopen (verified by test).
- **E01/E02 unchanged**: still a single combined click per step, now
  reached via `Terminal.interact()` → `panel.terminal_interact()`
  instead of the cabinet's own `interact()`.

## What was NOT implemented (explicit scope limits)

- No breaker-click power-isolate/restore sub-steps from Part 6.8/4.7 —
  out of this milestone's stated scope ("keep scope focused").
- No real hinge-swing door animation — a simple visibility swap
  (`AccessHatchCover` hidden/shown), one of the alternatives the task
  itself explicitly allowed ("door-state swap... is acceptable"),
  chosen over a hand-authored rotation pivot given this round's own
  discovery (see `scenes/main.tscn`'s camera-pitch work in the prior
  round) that hand-derived `Transform3D` rotation matrices are an easy,
  hard-to-visually-catch source of bugs without rendering available.
- Only one decoy terminal exists (`IntactTerminal`), not a full
  multi-connector wiring diagram — Slice B's own design doc already
  scopes the component-matching problem to "a single unambiguous bin"
  for this slice; a second decoy was the minimum needed to make "wrong
  terminal preserves the wire" a real, testable path rather than an
  assumption.
- No rendering/visual verification was possible in this environment
  (confirmed again this round) — the hatch-cover swap, terminal
  placement, and installed-wire pose are verified only by static
  inspection and headless behavioral tests, not by sight.

## New files this round

- `scripts/interactables/terminal_connector.gd`

## Modified files this round

- `scripts/interactables/electrical_panel.gd` (door/repair-stage split,
  terminal forwarding, non-destructive install)
- `scripts/interactables/wire_component.gd` (`mark_installed()`,
  `is_installed()`, pickup gating)
- `scripts/player/carry_system.gd` (`take_carried_item_if_matches()`)
- `scenes/main.tscn` (new `AccessHatchCover`/`Terminal`/
  `IntactTerminal`/`DamagedWireVisual` children under
  `EngineeringCabinet1`; new materials/meshes/shapes for them)
- `tests/test_electrical_panel_chain.gd`, `tests/test_slice_b_e2e.gd`,
  `tests/test_interaction_prompts.gd` (updated to drive the new door-
  then-terminal entry points; same original assertions/intent, new
  entry points)

## New test file this round

- `tests/test_electrical_panel_terminal.gd` — door open/close
  persistence, terminal-vs-cabinet collider separation, wrong-terminal
  preserves the wire, drop-then-reinstall, installed-wire pickup
  lockout, close/reopen persistence, repeated-interaction idempotence.

---

# ROUND 5: WRISTWATCH + STATION MAP MILESTONE

## Scope actually implemented

Phases 1/2/5/6 of this round's brief (finish the repair loop, connect
task state, prove the 5 interaction patterns, connect Slice A/B
end-to-end) turned out to already be complete and passing from Round 4
— re-verified, not rebuilt. The two genuinely new deliverables this
round are the wristwatch and the station map.

- **Shared task-state helpers** (`day_plan.gd`): `get_work_order_lines()`
  and `get_outstanding_task_room()`, both pure functions over existing
  fields (no new state). `workstation_screen.gd`'s Work Orders section
  was refactored to call the former instead of formatting its own copy;
  the wristwatch and station map both call these same two functions —
  three views, one authoritative source, per this round's explicit
  requirement.
- **Wristwatch** (`scripts/player/wristwatch_view.gd`, new): press-and-
  hold **C** (confirmed unused — E/F/T/G are claimed by
  `sleep_state.gd`/`carry_system.gd`, 0-6/R/Esc by
  `workstation_state.gd`). Polls `Input.is_key_pressed()` every frame
  (matching `free_move_controller.gd`'s own WASD convention — this
  needs continuous held state, not an edge-triggered action) and gates
  on `interaction_controller.gd`'s existing `interactions_enabled` flag,
  so it is fully inert while sitting, at the laptop, editing, sleeping,
  or seated at the workstation — verified by test, not assumed. Shows a
  small HUD panel (`Player/HUD/WristwatchView`) with the live Work
  Orders summary.
- **Station map** (augments the Overview section, per the brief's own
  "replace or augment" wording — the existing subsystem-status text and
  assignment line are untouched): an 8-room, 8-edge diagram, Left/Right
  to select a room, selected + outstanding-task rooms get a restrained
  color difference (dark gray / amber for the task room / lighter gray
  for selection / bright amber for both). **The topology was derived
  directly from the real `MovementNode` graph in `scenes/main.tscn`,
  not assumed from the brief's prose** — which turned out to matter:
  the brief suggested Life Support connects directly to Engineering,
  but the actual graph only connects them via Main Junction or via
  Storage. The map does not draw that edge; Life Support's info text
  says so explicitly instead of drawing a shortcut that doesn't exist.

## A real timing bug found and fixed in the test harness

`Input.is_key_pressed()` does not reflect a `parse_input_event()` call
until one engine frame later (confirmed by direct measurement) — a
single `await process_frame` after simulating a key-down was not
enough for the wristwatch's polling-based test, even though the exact
same one-frame pattern works fine for `_unhandled_input`-based actions
(G-key drop, workstation number keys) elsewhere in this test suite,
because those react to the dispatched *event* directly rather than
polling the separate stateful table. `test_wristwatch.gd`'s `_press()`/
`_release()` helpers now await the extra frame.

## New files this round

- `scripts/player/wristwatch_view.gd`

## Modified files this round

- `scripts/station/day_plan.gd` (`get_work_order_lines()`,
  `get_outstanding_task_room()`)
- `scripts/ui/workstation_screen.gd` (station map logic; Work Orders
  refactored onto the shared helper)
- `scripts/station/workstation_state.gd` (Left/Right room-selection
  routing, Overview-section-only)
- `scenes/main.tscn` (Wristwatch node wiring; `IntactTerminal` given its
  own restrained green material instead of sharing the damaged
  terminal's exact material, per this round's physical-presentation
  pass)
- `scenes/player.tscn` (`WristwatchView` HUD panel, `Wristwatch` node)
- `scenes/ui/workstation_screen.tscn` (8 room boxes + 8 edges + room-
  info label under Overview)

## New test files this round

- `tests/test_wristwatch.gd`, `tests/test_station_map.gd`

## Known limitations / deferred

- No in-world 3D wristwatch model/geometry — a 2D HUD panel, per the
  brief's own "readable display rather than inventing a new UI
  framework" allowance. A future pass could add an arm-mounted prop if
  that's actually wanted.
- The station map's "outstanding task room" uses a fixed priority order
  over Slice A/B's existing fields, not a generic scheduler — correct
  for the two currently-implemented slices, will need extending (not
  rewriting) once more tasks exist.
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited this round, no new evidence found in the repo
  or git history) — not invented, not marked obsolete.
- No rendering/visual verification was possible in this environment
  (confirmed again) — the map's layout, colors, and wristwatch panel
  position are verified by static inspection and headless behavioral
  tests only.

---

# ROUND 6: PANEL VISUAL FIX + PHYSICAL WRISTWATCH + MAP LAYOUT

Brief retroactive record (this round's own full report has the details):
fixed the electrical panel hatch's "doesn't visibly open" bug (a
same-material backing panel, `DoorPanel`, sat directly behind
`AccessHatchCover` and masked the state change); replaced the
wristwatch's 2D HUD panel with a physical first-person arm-raise
(`player_body.gd`'s `set_watch_raised()`, `WatchCase`/`WatchFace` under
`StandingPose`); and rearranged the station map's visual layout (Life
Support/Engineering swapped, Airlock moved downstream of Engineering)
without altering the real `MovementNode` graph. New test:
`test_electrical_panel_hatch_visual.gd`; `test_wristwatch.gd` and
`test_station_map.gd` rewritten against the new implementations.

---

# ROUND 7: MAINTENANCE INTERACTION FOUNDATION + ELECTRICAL PROCEDURE + SENSOR CALIBRATION

## Scope

Three deliverables, as scoped by the brief ("implement the interaction
foundation, the electrical repair procedure, and one contrasting
sensor-calibration prototype" — not every brainstormed mechanic):

1. A reusable focused-interaction boundary.
2. A full multi-stage electrical repair procedure replacing E05's old
   single-click install, extending (not replacing) the existing E01/
   E02/E05/S01/C02/C05 task IDs.
3. A contrasting calibration prototype implementing L07 Environmental
   Sensor Calibration.

## 1. Focused-interaction boundary (`scripts/player/focused_interaction_state.gd`)

A small coordinator, not a minigame framework — generalizes the exact
five-line exclusive-state pattern `workstation_state.gd`/`sleep_state.gd`
already used (disable `FreeMoveBody`/`GlobalFreeMove` mirroring/raycast
interaction/look escape+input, remember the prior `Input.mouse_mode`,
restore all of it on exit). `begin(view)`/`end()` are idempotent and
safe to call redundantly; Escape is reserved globally while a session is
active (consistent with the existing workstation/laptop Escape
convention) and always calls `end()`, so a session can never be left
stuck regardless of how it closes. Any view need only implement
`on_focus_exit()` (and optionally `cancel_requested()`) — duck-typed,
same convention as `interact()` elsewhere in this project.

Each maintenance interaction is its OWN visually-distinct Control
occupying ~94% of the screen (anchors 0.03..0.97) under `Player/HUD` —
not a shared 3D SubViewport-on-a-mesh like the Control Room workstation
screen, since the player is standing at an arbitrary angle/distance from
the serviced equipment, and the brief explicitly didn't want every
minigame forced into one visual style. Keyboard-only input (digits for
wire/screw selection, B for the breaker, R to confirm install, A/D or
arrow keys for calibration adjustment, Enter/Escape to close) — same
"no raycast-to-UI click mapping" convention `workstation_screen.gd`
already established, for the same reason (solving precise 3D-to-UV
click mapping wasn't worth it for a dedicated-key interface).

## 2. Electrical repair procedure (`electrical_panel.gd` + `scripts/ui/electrical_repair_view.gd`)

E01 (inspect) and E02 (trace) are unchanged. E05 (replace) now opens a
five-stage focused procedure instead of installing on one click:

1. **Isolate** — toggle the breaker (`B`); always succeeds, no danger/
   fail state (an explicit instruction).
2. **Disconnect** — three color-coded wires (Red=supply, Blue=return,
   Yellow=service/being-replaced), digits `1`/`2`/`3`, required order
   supply→return→service (a real safety rationale: de-energize the live
   feed, then return, then the wire actually being serviced — not an
   arbitrary memorization sequence; see the class doc comment in
   `electrical_panel.gd`). A wrong attempt is rejected with a message
   and changes nothing — already-correct wires stay disconnected.
3. **Replace** — `R` installs the carried Control Wire. This is the
   actual commit point: carrying the wrong item, or nothing, is
   rejected non-punishingly at every step up to here, and the wire is
   never consumed until this exact call.
4. **Reconnect** — the same three wires, required order reversed
   (service→return→supply), recalled from memory. The hint sequence
   (shown during Disconnect) is hidden here on Normal/Hard — the
   player must recall their own prior order, which is recorded once and
   frozen (`_recorded_disconnect_order`) so the "reverse" target can
   never silently change mid-attempt.
5. **Restore** — `B` re-energizes. Validates all three reconnections
   actually hold before marking E05 done — the SAME moment
   `_repair_stage` becomes `REPAIRED`, so `is_repaired()` (already read
   by the watch/map/workstation) updates with no second flag anywhere.

**Four-screw difficulty (`difficulty: EASY/NORMAL/HARD`, exported on
the panel node — "a minimal, documented configuration," not a
difficulty-management framework, per the brief):** on HARD, opening the
cabinet for the first time requires removing four screws (digits
`1`-`4`, three "turns" each) before the door opens; reinstalling them
is required to close it again once the repair is complete. EASY/NORMAL
skip screws entirely. Hint visibility: EASY shows the wire-order hint
during both Disconnect and Reconnect; NORMAL shows it only during
Disconnect; HARD shows it at neither stage (still fair — the physical
wire labels are visible, the player just isn't told the order outright).

**Reversibility:** every stage before Replace can be exited (Escape)
and resumed later with its progress intact — this was verified to
require TWO fixes beyond the panel's own state machine: (a)
`_open_procedure()`'s carried-wire check must only apply before Replace
actually commits, else resuming at Reconnect/Restore (wire already
consumed) would wrongly re-demand it; (b) every test that drives the
procedure via direct panel-method calls must explicitly close the real
focused session afterward (`FocusedInteractionState.end()`), because
`terminal_interact()` now opens a REAL session — three existing tests
(`test_electrical_panel_chain.gd`, `test_electrical_panel_terminal.gd`,
`test_slice_b_e2e.gd`) and the new prompt-text assertions in
`test_interaction_prompts.gd` needed this fix; omitting it left
`interactions_enabled`/free movement stuck disabled for the rest of
those tests (a real bug this round's regression pass caught, not a
hypothetical).

## 3. Diagnostic reasoning (Phase 4, `workstation_screen.gd`'s C02)

C02's diagnostic now reports two independent, terminal-ID-matched
clues instead of one flat "fault detected" line: a voltage comparison
(Terminal T-1 24.1V nominal vs. Terminal T-2 11.4V undervolt) and a
continuity result (T-1 OK, T-2 FAIL) — both pointing at the same
physical terminal the player will actually find at the panel (the panel's
own prompts/messages now say "Terminal T-2" too, via
`terminal_display_id()`, so the two screens are describable in the same
vocabulary). Verbosity is gated by the SAME `difficulty` field the
repair procedure uses (read via `repair_difficulty()`, not a second
copy): EASY also states the likely fault outright; HARD omits the
continuity line, leaving only the voltage comparison (still solvable,
less explicit).

## 4. Sensor calibration prototype (Phase 5) — why L07

`GAME_DESIGN.md` Section 29's locked task database describes L07
Environmental Sensor Calibration as "Adjust dial/knob until readings
converge" — the one documented task whose own description already
matches this milestone's required calibration gameplay (continuous
adjustment + convergence) with no invented task identity. No other
candidate task in the catalog is worded this way, so L07 was chosen for
that textual match, not arbitrarily. A new physical prop,
`scenes/interactables/sensor_calibration_station.tscn`
(`sensor_calibration_station.gd`), was added to Life Support (previously
bare walls, no equipment) since L07 belongs to that room.

Gameplay (`scripts/ui/sensor_calibration_view.gd`): target 50.0 ±3.0 on
a 0–100 scale, held keys `A`/`D` (or arrow keys) drive a `_control_input`
value at a fixed rate, and the DISPLAYED reading eases toward that
input with exponential lag (`RESPONSE_RATE`) rather than snapping — so
slamming the input to an extreme genuinely overshoots and has to be
walked back, and sitting at the exact target still takes ~1.5s of real
lag before the reading settles inside tolerance. Success requires the
reading to stay inside tolerance for `STABILITY_DURATION` (1.5s)
continuously — a brief pass-through doesn't count, matching the
brief's "stabilize for a short period, not just select the right
answer." L07 is marked done at that single commit point
(`sensor_calibration_station.gd`'s `mark_complete()`); opening the
station, overshooting, or abandoning an attempt never touches it.

## Files changed, by feature

**Focused-interaction foundation:**
- `scripts/player/focused_interaction_state.gd` (new)
- `scripts/audio/mechanical_sfx.gd` (new — procedural click/clunk/
  success/fail/ratchet tones, same "no sampled assets, synthesize at
  startup" convention as `footstep_player.gd`)
- `scenes/main.tscn` (new `FocusedInteractionState` node, wired like
  `WorkstationState`)
- `scenes/player.tscn` (new `ElectricalRepairView`/
  `SensorCalibrationView`/`MechanicalSfx` nodes under `HUD`)

**Electrical repair procedure:**
- `scripts/interactables/electrical_panel.gd` (difficulty, screw
  sub-state, inner `ProcedureStage` machine, terminal display IDs)
- `scripts/ui/electrical_repair_view.gd` (new)
- `scenes/main.tscn` (`repair_view_path` added to `EngineeringCabinet1`)

**Diagnostic reasoning:**
- `scripts/ui/workstation_screen.gd` (`_refresh_diagnostics()` rewritten)

**Sensor calibration prototype:**
- `scripts/interactables/sensor_calibration_station.gd` (new)
- `scripts/ui/sensor_calibration_view.gd` (new)
- `scenes/interactables/sensor_calibration_station.tscn` (new)
- `scripts/station/day_plan.gd` (`l07_status` field)
- `scenes/main.tscn` (new `SensorCalibrationStation` instance in Life
  Support, under `Interactables`)

**Tests, new:**
- `tests/test_focused_interaction_state.gd`
- `tests/test_electrical_repair_procedure.gd`
- `tests/test_sensor_calibration.gd`

**Tests, updated** (to drive the new multi-stage procedure instead of
the old single-click install, and to close the real focused session
they now open):
- `tests/test_electrical_panel_chain.gd`
- `tests/test_electrical_panel_terminal.gd`
- `tests/test_slice_b_e2e.gd`
- `tests/test_interaction_prompts.gd`

## Known limitations / deferred

- The wire-disconnect/reconnect order is currently deterministic
  (there is only one fault type in the game); the ordering logic is
  derived from each wire's documented ROLE specifically so a future
  second fault type would get a different, still non-arbitrary order
  without rewriting this logic — but that second fault type doesn't
  exist yet, so this is unverified beyond the one case.
- The calibration gauge's tolerance-zone/needle positions depend on
  `Control.size`, which is only meaningful once the Control has been
  laid out — relies on the node already being visible/sized from a
  prior frame; not an issue in practice (the station is re-entered many
  times over a session) but noted as a theoretical first-frame risk.
- No rendering/visual verification was possible in this environment
  (confirmed again) — the ~94%-screen framing, wire/screw/gauge visual
  layout, and the panel's new terminal-ID labeling are verified by
  static inspection and headless behavioral tests only, not by sight.
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited this round, no new evidence found) — not
  invented, not marked obsolete.

---

# GENERAL VISUAL-INTERACTION STANDARDS

Established in Round 8 below; apply to every future focused interaction
in this project, not only electrical repair/calibration/workstation:

1. If a process can be clearly visualized, do not explain it with a
   paragraph.
2. Prefer direct manipulation of visible objects over selecting
   numbered answers.
3. Important state changes should produce visible responses.
4. Animations should communicate the action, not merely decorate it.
5. Audio should reinforce meaningful mechanical or electrical feedback.
6. Different mechanics should exercise different player skills.
7. Electrical repair emphasizes procedural memory and manipulation.
8. Calibration emphasizes fine control and stabilization.
9. Diagnostics emphasize observation and deduction.
10. Avoid making every task a minigame. Simple observation and
    appropriate one-step interactions remain valid.
11. Avoid generic minigame infrastructure until a second or third
    genuine use case proves it is necessary.
12. Keep visual language consistent across focused interactions without
    making every interaction look identical.
13. Avoid long instructions, unnecessary confirmation dialogs,
    redundant success messages, and button labels that merely repeat
    the next step.
14. Keep the horror layer slow-burn and secondary to the normal
    maintenance gameplay.
15. Do not introduce new anomalies or supernatural events as part of a
    gameplay-mechanics task.

---

# ROUND 8: VISUAL ELECTRICAL REPAIR + CALIBRATION PRESENTATION + WORKSTATION REDESIGN

## Scope

Three workstreams, per the brief's own priority order (A highest):
replace the electrical repair's numbered-key wire/screw/breaker
selection with direct 3D manipulation; upgrade the calibration
prototype's presentation (analog gauge, rotary knob) without touching
its underlying simulation; and reduce the Control Room workstation's
Overview/Diagnostics sections from paragraphs to status lights paired
with the existing (unchanged) text evidence. The backend state
machines this round touches (`electrical_panel.gd`'s procedure API,
the calibration simulation's target/tolerance/lag/stability math,
DayPlan) were NOT modified -- this round replaced presentation/input
layers on top of an already-correct backend from Round 7.

## Workstream A: visual electrical repair

**The core architecture decision**: the repair equipment is now a
small, isolated 3D scene (`scenes/ui/electrical_repair_diorama.tscn` +
`scripts/ui/electrical_repair_diorama.gd`) rendered through a
`SubViewport` (`own_world_3d = true`) displayed via a
`SubViewportContainer` inside the existing focused-interaction Control
(`scripts/ui/electrical_repair_view.gd`). A `SubViewportContainer`
automatically forwards mouse input -- translated into the child
viewport's own local coordinates -- which is the one thing
`workstation_screen.gd`'s own class doc comment had previously flagged
as "a much larger problem" not worth solving for a dedicated-key
interface. It was worth solving here because this milestone
specifically asked for direct manipulation: the player now raycasts
(via the diorama's own camera and `direct_space_state`, the same
technique `interaction_controller.gd` already uses, just cursor-aimed
instead of forward-fixed) and clicks directly on three color-coded
wires (red/supply, blue/return, yellow/service), a breaker lever, and
(HARD difficulty) four screws -- all CSG primitives in the project's
existing material/lighting style, procedurally built, no external
assets.

**Interaction flow** (unchanged backend sequence from Round 7, new
input/presentation): open the cabinet (HARD: click each screw three
times to back it out, with a spin+outward-translate animation, before
the door opens) → click the breaker to isolate (lever rotates down, a
status light switches from green to red) → click each wire in order
(red, blue, yellow) to disconnect it (it swings away from its terminal
on a hinge-like rotation, and that terminal's indicator light goes
dark) → click the now-dangling damaged (scorch-marked) yellow wire to
remove it, then click the replacement wire that appears in its place
to install it (this is the one true commit point -- the carried wire
is only consumed here, never when the procedure merely opens) → click
each wire in the reverse order (yellow, blue, red) to reconnect (same
swing animation, reversed; the next-required wire pulses gently on
EASY/NORMAL during disconnect and on EASY only during reconnect, no
pulse at all on HARD) → click the breaker again to restore (lever
rotates up, light turns green) → E05 marks done only at this exact
call, which is also the only moment `is_repaired()` flips (watch/map/
workstation already read that one flag, so nothing else needed
updating) → (HARD: reinstall all four screws to close the cover).

**Hover highlighting**: whatever the cursor is currently over (and
is allowed to click for the current stage) gets its emission boosted;
this is tracked per the *allowed action set* `electrical_repair_view.gd`
recomputes every stage transition, so hovering something no longer
valid (e.g. the breaker during Disconnect, if a future stage ever
removed it from the allowed set) can never show a stale highlight --
verified by `test_electrical_repair_diorama.gd`'s explicit "allowed set
changes out from under a hover" case.

**A real headless-testing limitation, confirmed empirically**:
`SubViewport.push_input()` with a manually-positioned
`InputEventMouseMotion`/`InputEventMouseButton` does NOT reproduce the
coordinate mapping a real `SubViewportContainer` delivers in this
environment -- the viewport's own tracked mouse position did not
update to match the position pushed. Rather than leave the raycast
mapping untested, `electrical_repair_diorama.gd` gained
`screen_position_for(world_pos)` (the camera's own `unproject_position`,
the mathematical inverse of the real mapping) and an optional override
parameter on `_raycast_action()`, so tests can compute "what would a
real click exactly on this collider's position resolve to" and verify
the actual ray-picking math deterministically. This proves the picking
logic is correct; whether a real OS mouse event over the real
`SubViewportContainer` in an actual running build reaches the same
result is a manual playtest item (see the final report).

## Workstream B: calibration presentation

The simulation (target 50.0±3.0, `START_VALUE`, `ADJUST_RATE`,
`RESPONSE_RATE` lag, `STABILITY_DURATION`) is byte-for-byte unchanged
from Round 7 -- confirmed by the existing `test_sensor_calibration.gd`
passing without modification, since it only ever touched these same
script-level properties, never the old flat-bar gauge nodes directly.

What changed: the flat `ColorRect`-bar gauge is now a procedurally
custom-drawn analog instrument (`scripts/ui/analog_gauge.gd`, a
`Control` with `_draw()` -- a circular face, tick marks, a colored
tolerance arc, and two distinct needles: a dim short one for the dial
*setting* and a bright long one for the actual lagging *reading*,
which is the concrete way the player now SEES the distinction between
"what I'm commanding" and "what the sensor reports" instead of reading
two numbers). A draggable rotary knob sits beside the gauge --
click-and-drag in a circular motion turns it like a real dial (the
ANGULAR delta since the last frame drives the adjustment, so it can be
spun past a full turn without snapping, same spirit as a rotary
encoder); the original A/D and Left/Right keys remain a fully
functional fallback, per the brief's explicit "preserve keyboard
accessibility" instruction. A small direction indicator
(▲ Approaching / ▼ Drifting away / ● Holding) compares THIS frame's
distance-to-target against last frame's -- deliberately not just the
sign of the dial's own motion, which would say nothing once lag makes
the reading diverge from where the dial is currently pointed.

## Workstream C: workstation redesign

`workstation_screen.tscn`'s Overview section's four-line "X: nominal"
paragraph (repeated for all eight subsystems) is now a `StatusLights`
row: eight small colored indicators with three-letter labels
(PWR/BAT/PRS/O2/CO2/TMP/COM/STR). None of them currently vary (no
subsystem besides Engineering power has simulated fault state yet, and
inventing per-subsystem fake readings to make them move was explicitly
out of scope) -- `workstation_screen.gd`'s `_refresh_overview()` now
documents exactly where a future real subsystem fault would plug in a
light-color setter, rather than leaving that an undocumented gap. The
station map (already visual from Round 5/6) and its destination-room
highlighting are unchanged.

The Diagnostics section's C02 evidence TEXT is completely unchanged
(every voltage/continuity/terminal-ID line from Round 7's Phase 4
remains, difficulty-gated exactly as before) -- a small `TerminalLights`
row (T-1 green, T-2 red) was added ABOVE it as a visual pairing the
brief asked for ("where practical, pair the text with simple visual
instrument readings"), not a replacement; the player still has to read
the voltage/continuity numbers to reason about which terminal is at
fault, the lights just let them confirm which one at a glance once
they've worked it out.

## Files changed, by workstream

**Workstream A:**
- `scenes/ui/electrical_repair_diorama.tscn` (new)
- `scripts/ui/electrical_repair_diorama.gd` (new)
- `scripts/ui/electrical_repair_view.gd` (rewritten: click dispatch
  instead of numbered-key dispatch; same panel-method call-through
  contract as Round 7)
- `scenes/player.tscn` (`ElectricalRepairView`'s old `Content` VBox of
  per-stage label sections replaced with a `SubViewportContainer` +
  `SubViewport` hosting the diorama instance)

**Workstream B:**
- `scripts/ui/analog_gauge.gd` (new)
- `scripts/ui/sensor_calibration_view.gd` (rewritten presentation layer
  around the unchanged simulation; added knob drag handling and the
  direction indicator)
- `scenes/player.tscn` (`SensorCalibrationView`'s old
  `Gauge/Track/ToleranceZone/Needle/DialMarker` ColorRect stack
  replaced with a `GaugeRow` containing the new `Gauge`
  (`analog_gauge.gd`) and a draggable `Knob`/`Pointer`; added
  `DirectionLabel`)

**Workstream C:**
- `scenes/ui/workstation_screen.tscn` (Overview's `Rows` label replaced
  with the `StatusLights` row; Diagnostics gained the `TerminalLights`
  row)
- `scripts/ui/workstation_screen.gd` (`_overview_rows` reference
  removed; `_refresh_diagnostics()` now also drives the two terminal
  lights)

**Tests, new:**
- `tests/test_electrical_repair_diorama.gd`
- `tests/test_sensor_calibration_knob.gd`
- `tests/test_workstation_visual_overview.gd`

**Tests, rewritten** (the numbered-key simulation they drove no longer
exists; rewritten to call the view's click-dispatch handlers directly,
which is exactly what a real click resolves to -- same end-to-end
coverage, same assertions, new input mechanism):
- `tests/test_electrical_repair_procedure.gd`

## Known limitations / deferred

- Real OS-level mouse-click-through-`SubViewportContainer` cannot be
  exercised in this headless environment (see Workstream A's note
  above) -- the ray-picking MATH is verified deterministically; the
  platform-level input-forwarding path is a manual playtest item.
- The Overview status lights are currently always green (no subsystem
  besides Engineering power has real fault state to show) -- this is
  honest, not a placeholder bug; wiring a second subsystem's fault
  state into a light is a documented, bounded follow-up, not a
  redesign.
- Work Orders' task lines remain plain bracketed-status text
  (`[PENDING]`/`[DONE]`) rather than gaining their own icon/light --
  `Label` does not support partial-text styling without switching to
  `RichTextLabel`/BBCode, and Workstream A was this milestone's
  explicit priority; this is the one visual-density reduction from
  Phase C's brief deferred to a future pass rather than attempted
  under time pressure and risking a half-finished result.
- No rendering/visual verification was possible in this environment
  (confirmed again) -- the diorama's actual on-screen framing/lighting/
  readability, the analog gauge's drawn appearance, the knob's visual
  rotation, and the status lights' layout are verified by static
  inspection and headless behavioral tests only, not by sight.

---

*This document was authored as a pure design/audit pass in its first
round, updated in Round 2 to record approved decisions and the Slice
A/B implementation, updated again in Round 3 for the Control Room
Workstation Revamp, updated again in Round 4 for the Hands-On
Electrical Repair milestone, updated again in Round 5 for the
Wristwatch + Station Map milestone, updated again in Round 6 for the
panel-visual-fix/physical-wristwatch/map-layout milestone, updated
again in Round 7 for the Maintenance Interaction Foundation + Electrical
Procedure + Sensor Calibration milestone, updated again in Round 8 for
the Visual Electrical Repair + Calibration Presentation + Workstation
Redesign milestone, and updated again in Round 9 for the playtest-
feedback fixes below. See each round's final report for exact test
results and verification scope.*

---

# ROUND 9: PLAYTEST-FEEDBACK FIXES (CABINET HEIGHT, WATCH, SPACE PICKUP/DROP, E06 GUIDANCE, DIFFICULTY SETTING, CYLINDRICAL GAUGE)

## Scope

Six fixes/additions driven directly by the user's manual playtest of
Round 8, not new feature exploration:

## A. Engineering cabinet mounting height

**Root cause**: `EngineeringCabinet1`'s root transform sat at world
Y=1.1 with its hatch/terminal interior at a further LOCAL -0.65 offset
-- world Y≈0.45m, just above the floor (Y=0.0), well below standing eye
height (1.6m). Every hatch/terminal/wire/screw-visual/dressing child is
a child of this ONE root using local coordinates, so this was a
one-line fix: moved the root to Y=2.0 (bottom at 1.0m off the floor --
a believable wall-mounted height, not floating; top at 3.0m, 0.2m clear
of the 3.2m ceiling; hatch/terminal area now at world Y=1.35m, ~0.25m
below eye height -- a natural, comfortable downward glance, not a
crouch or an awkward reach-up). No child transform needed touching
individually. Re-verified: the capsule clearance sweep (unaffected --
only a prop's Y moved, not any MovementNode or corridor geometry) and
the panel's own existing tests, all unchanged/passing.

## B. Wristwatch

**The "not fixed to screen" bug, root cause**: `player_body.gd`'s
`standing_pitch_follow` (0.3) deliberately makes the standing body
follow only 30% of the camera's PITCH (tuned for ordinary standing-body
composition, not watch inspection). Since the watch is a plain child of
this body (not reparented, still "attached to the wrist"), a fixed
local offset under a body that under-rotates relative to the camera
drifts in screen-space the instant the player looks up or down.
**Fix**: while the watch is raised, PlayerBody's own pitch-follow
fraction eases (not snaps, to avoid a jolt if C is pressed mid-look) to
a FULL 1.0. Since this node's origin is always the player's own eye
point, rotating the whole body in exact lockstep with the camera's
pitch is mathematically equivalent to camera-anchoring the watch,
without reparenting anything. Verified via `Camera3D.unproject_position()`
(the real screen-space projection, a geometric check -- not a rendered
pixel comparison, see the limitations below): screen position stayed
within 0.06px across a -25°..+30° pitch sweep in the headless check: in
contrast to the old behavior, which was never actually screen-stable.

**Geometry**: the watch was a bare box + a floating `Label3D`
(confirmed -- exactly what the user suspected). Added, all as children
of the existing `WatchCase` (so they animate together with it,
unchanged tween code): a metal `Bezel` and recessed dark `FacePlate`
(the text now sits ON a backing plate instead of floating), two metal
`Lug` connectors, and a `Strap` (a solid cylindrical band -- not a true
hollow ring; CSG boolean subtraction was deliberately avoided here
since `StandingPose` is one large pre-existing `CSGCombiner3D` and
introducing a subtraction op into that tree risked unpredictable
interaction with unrelated body geometry with no way to visually
verify the result in this environment). This is a real geometric
improvement over a flat label, not a claim of photorealism -- see
Limitations.

**Display**: unchanged -- still reads `DayPlan.get_work_order_lines()`
directly (Round 7's single source of truth), still compact. Not
rewritten this round; the reported problems were positioning and
geometry, not content.

## C. Space pickup/drop (replacing G)

`carry_system.gd`'s drop-only G handler is now a unified Space
handler: carrying something, Space drops it (identical placement logic
to before); empty-handed, Space picks up whatever
`interaction_controller.gd` currently has hovered, IF it passes the
existing carryable-item duck-type check (`has_method("return_to_rest")`)
-- added a small `get_hovered()` getter to `interaction_controller.gd`
rather than having `carry_system.gd` run a second independent raycast,
which is what makes "prioritize the item actually being targeted" and
"prevent pickup through walls" free (the SAME raycast every other
interactable already uses already stops at the first physical
collider). Hovering something that ISN'T carryable (a door, a switch)
and pressing Space is a silent no-op -- deliberately not a message for
every ordinary Space press while just walking around.
`G: Drop <item>` -> `Space: Drop <item>` updated everywhere it actually
renders (`interaction_controller.gd`'s prompt string) and in every
`G:`-referencing doc comment across `carry_system.gd`/`wire_component.gd`.
`sleep_state.gd`'s UNRELATED `G: Sleep` binding (while sitting on the
bed) was left untouched -- different script, different state gate,
never actually conflicted with the old G-drop and doesn't conflict
with the new Space pickup/drop either.

## D. E06 contextual guidance

Investigation found the ACTUAL cause of "no further instruction after
opening the cabinet": the player's real assigned task, E06 Tighten
Loose Connection, is a small, separate object
(`scripts/interactables/loose_connection.gd`, a wall fitting ~1.3m away
from the cabinet in the same room) that is easy to miss next to the
much more visually prominent cabinet -- and it previously had **no
`get_interact_prompt()` at all**, so even looking directly at it showed
no text whatsoever. Fixed: added a real prompt (shows live click
progress, e.g. "Click: Tighten Loose Connection (2/6)"), and a small
amber `AttentionLight` that glows (gently pulsing, not a static blaze)
exactly while `DayPlan.assignment_task_id == &"e06"` and E06 is not yet
done -- both read authoritative state directly, no second flag, never
spoils the cue before the task is actually assigned, and goes dark the
instant real progress completes it. Also fixed the station map's
Engineering room description, which previously always said "Electrical
panel, maintenance connection" even when the real outstanding work was
E06 and had nothing to do with the panel -- it now names whichever
equipment the actual outstanding work order points at.

## E. Difficulty configuration

Previously `electrical_panel.gd`'s `difficulty` export could only be
changed by hand-editing the scene file -- no in-game way to reach HARD
at all. Reused the Control Room workstation's existing Settings
section (Section 6, previously just an inert "not available in this
build" placeholder) rather than building a new settings menu: it now
shows the current difficulty and a one-line summary of what each level
actually changes, and `[R]` cycles EASY -> NORMAL -> HARD -> EASY. This
writes `electrical_panel.gd`'s OWN `difficulty` field directly (plain
integer arithmetic over the enum's int value, so this script never
needs the enum TYPE by name through a loosely-typed reference) -- the
exact same field C02 diagnostics already reads via `repair_difficulty()`,
so there is exactly one authoritative flag, never two that could
disagree. Changing difficulty mid-repair is safe BY CONSTRUCTION, not
just by convention: disconnect/reconnect order, isolation state, and
any committed wire replacement are all stored independently of
difficulty (only hint visibility and the screw requirement read it),
so switching difficulty mid-attempt cannot invalidate recorded progress
-- verified directly (disconnect two wires, change difficulty twice,
finish the repair successfully).

**To verify HARD manually**: sit at the Control Room workstation,
press `6` for Settings, press `R` until the label reads
"ELECTRICAL REPAIR DIFFICULTY: HARD", stand up, and go open the
Engineering cabinet -- it will now require turning four screws before
the door opens at all.

## F. Second calibration instrument style (cylindrical)

Added `scripts/ui/cylindrical_gauge.gd`, a standalone, reusable
drum-style instrument (a vertical graduated scale that SCROLLS so the
current reading stays centered in a fixed window, a soft left-right
shading gradient suggesting a curved cylindrical surface, a fixed
target tick, and a separate dim dial-setting tick) -- visually nothing
like analog_gauge.gd's circular needle dial, same public
`set_readout()`-shaped API so either can be dropped into a focused view.

Per this milestone's explicit constraint, **L07's existing circular
dial remains its one instrument** -- the simulation, DayPlan
integration, target/tolerance/lag/stability behavior are byte-for-byte
unchanged (confirmed: the Round 7/8 `test_sensor_calibration.gd` passes
unmodified). The cylindrical gauge was instead wired into
`sensor_calibration_view.gd` as a purely cosmetic, session-local,
`[Tab]`-toggled ALTERNATE display of the exact same live simulation
state -- so the player can actually see both instrument styles (the
literal request: "I would like both cylinder and clock like dials")
without a second task ID, a second simulation, or the task becoming
confusing about which instrument is authoritative (there is only ever
one: the underlying numbers). The circular dial is always what a fresh
`open_station()` shows; the Tab choice is not persisted between
sessions. No new task ID was created. A later task (e.g. a future
pressure/flow gauge, or L04 Valve Procedure if it gains a dedicated
interaction) can adopt `cylindrical_gauge.gd` directly as its primary
instrument without this toggle machinery.

## Files changed

- `scenes/main.tscn` — `EngineeringCabinet1` root Y: 1.1 -> 2.0.
- `scripts/player/player_body.gd` — eased full-pitch-follow while the
  watch is raised; no other pose/animation logic touched.
- `scenes/player/player_body.tscn` — `WatchCase` enlarged slightly;
  added `Strap`/`LugTop`/`LugBottom`/`Bezel`/`FacePlate` children.
- `scripts/player/carry_system.gd` — G-drop-only -> unified Space
  pickup/drop.
- `scripts/player/interaction_controller.gd` — added `get_hovered()`;
  drop-prompt string updated to Space.
- `scripts/interactables/wire_component.gd` — doc-comment-only G->Space
  wording fix.
- `scripts/interactables/loose_connection.gd` / `.tscn` — added
  `get_interact_prompt()` and a state-driven `AttentionLight`.
- `scripts/ui/workstation_screen.gd` / `.tscn` — Settings section now a
  real difficulty cycle/display; Engineering room-info text no longer
  always blames "the electrical panel."
- `scripts/ui/sensor_calibration_view.gd` / `scenes/player.tscn` —
  added the Tab-toggled `CylinderGauge` display.
- `scripts/ui/cylindrical_gauge.gd` (new).
- Tests: see the final report for the full new/updated list.

## Known limitations / deferred

- No rendering/visual verification was possible in this environment
  (confirmed again) -- the cabinet's actual on-screen framing from a
  standing position, the watch's geometry/readability, the gauge
  drawings, and the attention light's glow are verified by static
  inspection, geometric projection checks, and headless behavioral
  tests only, not by sight. See the final report's manual playtest
  checklist.
- The watch strap is a solid band, not a true hollow ring (no CSG
  boolean subtraction -- see Section B above for why that was
  deliberately avoided this round). This is a real, bounded
  prototype-tier limitation, not the eventual skeletal-character
  wristwatch; that later milestone is NOT complete and nothing here
  should be read as claiming it is.
- Changing difficulty to HARD mid-repair AFTER the door was already
  opened on EASY/NORMAL (i.e., without ever removing screws) will still
  demand reinstalling screws to close once the repair finishes -- a
  minor narrative oddity (screws that were never removed), not a
  data-loss or progress-invalidation bug; documented rather than
  specially handled, given how rare mid-repair difficulty changes are
  expected to be.

---

# ROUND 10: PHYSICAL INTERACTION, WRISTWATCH RECOVERY, AND GAMEPLAY USABILITY

## Scope

A direct playtest-feedback round: the cabinet raised in Round 9 reads
as "a single large drawer, mostly non-interactive"; holding C makes the
wrist/forearm/body disappear entirely (a genuine regression, not a
cosmetic gap); the electrical diorama's three wires look like straight
bars; the repair view has too much small text; difficulty is still
task-owned rather than a real global setting; and the cylindrical gauge
is hard to read. Seven workstreams (A-G below), all implemented this
round.

## A. Cabinet rebuild: floor-standing housing + three compartments

Root cause confirmed by re-reading the Round 9 geometry directly:
`EngineeringCabinet1` was (and structurally still is) ONE `CSGBox3D`
with every dressing/functional child -- `DoorPanel`, hazard stripes,
decorative breakers, the one functional `AccessHatchCover`/`Terminal`
pair, the label, the base plate -- attached as plain local-offset
children. Round 9's one-line height fix moved this entire rigid block
upward as a single unit, which satisfied "hatch at a comfortable
height" but left `BaseFrame` (a "mounting plate resting on the floor"
dressing piece) floating in mid-air with no actual floor contact, and
left one oversized `DoorPanel` (spanning ~75% of the body) as the only
visually "door-like" surface while the small functional hatch sat
dwarfed below it -- exactly "a single large drawer with most of its
body noninteractive."

Fix: the housing root now rests genuinely on the floor (`size.y` 2.0 ->
2.2, position.y 1.1 so the box spans world Y 0.0-2.2, verified against
`EngineeringFloor`'s own top surface at Y=0.0, with 1.0m of clearance
below `EngineeringCeiling` at Y=3.2) and its children are reorganized
into three vertically-separated, independently-covered compartments,
each with its own seam/hinge dressing so they read as three separate
access points rather than one giant panel:

- **Upper diagnostics/control** (world Y≈1.85): a small dedicated
  cover (`UpperCover`), three switch/toggle pairs reusing the existing
  breaker-dressing style, three small indicator lights, its own
  "DIAGNOSTICS" label plate. Decorative only -- no task ID.
- **Middle electrical service** (world Y≈1.25, the SAME comfortable
  standing-reach height Round 9 targeted): `AccessHatchCover`,
  `Terminal`, `IntactTerminal`, and `DamagedWireVisual` kept as DIRECT
  children of the same root with the SAME node names, just repositioned
  -- `electrical_panel.gd`'s `@onready get_node("AccessHatchCover")` /
  `get_node("Terminal")` / etc. calls needed ZERO changes. This is
  E05's real, functional compartment.
- **Lower power/utility** (world Y≈0.55): its own cover, vent-slat
  dressing, two small hazard-yellow accents, its own "POWER / UTILITY"
  label. Decorative/reserved only -- no task ID, matching the brief's
  explicit "do not invent fake completed tasks for decorative
  compartments."

Each compartment's cover is a separate, non-colliding `CSGBox3D` sibling
(verified: none of the three covers carry `use_collision`, and all
three are distinct mesh instances) with its own pair of hinge-dressing
boxes at its own height band -- geometry a later round could attach a
real hatch/interaction to without touching the other two compartments.

**E06 vs. E05 re-verified under the new layout**: `LooseConnection`
(E06's actual fitting) is a wholly separate `StaticBody3D`-backed prop
at world `(-2.75, 1.3, 5.0)`, 1.4m away from the cabinet (`(-3.2, 1.1,
3.7)`) in a different part of the Engineering room -- not a sub-part of
the cabinet, so the compartment redesign could not have misdirected its
guidance. Its own Y (1.3) now lands almost exactly at the cabinet's new
middle-compartment height (1.25), so both the real electrical fixes in
this room sit at a consistent, comfortable working height.

New test: `tests/test_cabinet_compartments.gd` (12 checks) --
floor-contact height, ceiling clearance, three distinct compartment
heights with the middle one in the 1.0-1.6m standing-reach band, three
non-colliding distinct cover meshes, and E05's terminal/damaged-wire
geometry still aligned with the relocated hatch.

**Not verified by any test**: whether the result actually LOOKS like a
believable standing cabinet from the player's eye height and approach
angle -- see the manual playtest checklist.

## B. Wristwatch: the actual invisibility regression

Player report: "Holding C now makes the wrist, forearm and body
disappear from view." This was investigated as a genuine regression,
not dismissed as "probably the same old screen-position issue."

First ruled out: an Euler-order interaction between `PlayerBody`'s yaw
and pitch at non-level look angles (plausible on paper, since unlike
the camera's two-pivot rig, `PlayerBody` composes both axes on one
node) -- disproved directly: a yaw x pitch sweep showed the watch's
camera-local position stayed EXACTLY constant regardless of
combination, confirming Round 9's pitch-follow screen-stability fix
(`_pitch_follow_current` eased to 1.0 while raised) was and remains
mathematically correct.

The real root cause, found by going a level deeper than screen position
into actual frustum containment: `Camera3D.unproject_position()` does
NOT clamp to the field of view or check the near plane -- a point can
project to a perfectly stable on-screen pixel coordinate while sitting
geometrically OUTSIDE the visible cone. Computing genuine containment
(camera-local distance beyond `near`, and `|local.x|`/`|local.y|` both
under `distance * tan(fov/2)`) showed the raised watch/hand targets --
authored back in Round 6, never checked against the camera's actual
72-degree FOV -- sat roughly double the allowed half-angle below
center at every look angle. Round 9's fix made the watch's
camera-relative position CONSTANT, which is exactly what made this
always-present placement bug now reproduce consistently instead of
intermittently.

Fix: recomputed the raised arm-target constants
(`player_body.gd`'s `_WATCH_ARM_TARGETS` / `_WATCH_CASE_RAISED_POS` /
`_WATCH_FACE_RAISED_POS`) using the same existing falloff-interpolation
technique, chosen to satisfy the frustum bound with real margin, and
verified across a 24-combination yaw x pitch sweep including steep
(-60 to 75 degree) pitch.

New/extended test: `tests/test_wristwatch_screen_stability.gd` now
includes a genuine `_in_frustum()` helper (near-plane + fov-half-angle
check, not a projection-stability number) swept across yaw in {0, 40,
-70, 120, -150} x pitch in {-60, -20, 0, 20, 60, 75}, plus a 4-cycle
repeated press/release test confirming the hand/watch return to the
exact rest pose every time with no accumulated drift.

**Explicitly not claimed**: that the watch looks correct on screen.
Headless rendering was attempted directly this round
(`get_root().get_texture().get_image()`) and errors immediately
(`Parameter "t" is null`) -- genuinely unavailable in this environment,
not merely unattempted. Every "visible" claim above is a geometric
frustum-containment fact, not a pixel observation. See the manual
playtest checklist's first item.

## C. Wire geometry: from three straight bars to bent, layered cable runs

Player report: "The three wires currently resemble three straight bars
on a board. They do not look like wires, do not visually overlap, and
do not convincingly respond to disconnection." Confirmed by reading
`electrical_repair_diorama.tscn` directly: each wire role was a single
straight vertical `CSGCylinder3D` from its terminal anchor to its lug,
evenly spaced with no lateral variation at all.

Chosen physical interpretation (the brief requires picking exactly one
and staying consistent): the equipment **hangs under ordinary station
gravity**, not a zero-g float -- consistent with the rest of the game's
physicality (the player walks normally, breakers/screws behave
mechanically). Each wire's rotation pivot was already at its still-
attached top end, so the existing disconnect swing (pitching the loose
end down and away) already read as "unclipped from the bottom lug, now
hanging from the still-attached top," and that mechanism was kept
unchanged.

What changed is the STATIC shape: each wire is now two angled
`CSGCylinder3D` segments (`Run`/`Run2`, replacing the single straight
one) bowing from its own terminal anchor toward a shared "cable bundle"
region at the visual mid-height, then back out to its own lug --
Supply (disconnected first) bows toward the front and to one side,
Service (disconnected/replaced last) bows toward the back and the
other side, Return stays near-center with a gentler bow -- giving the
three roles genuinely different lateral directions AND depths (verified:
supply/service bow with opposite sign and all three sit at
distinguishable Z) rather than three parallel copies. `Run`/`Run2` both
reference the SAME material resource per role, so the existing
hover/pulse-highlight code (which only ever looked up `get_node("Run")`)
needed no changes and still lights the whole bent wire, not just one
segment. The damaged section's scorch mark moved to sit on the new bent
path instead of floating over the old straight centerline. The
replacement wire got the identical bow treatment for visual continuity
once installed.

Click targeting: each wire's collision box widened from the original
tight straight-line box to `Shape_wire_bowed` (0.5 x 0.78 x 0.22) to
actually cover the new bowed path -- verified this still leaves a real
gap (0.05) between neighboring wires' hitboxes, so the wider boxes
cannot create ambiguous click targeting between adjacent wires.

Disconnect order (Red/Supply -> Blue/Return -> Yellow/Service) is
unchanged this round and is now the one that matches the new VISUAL
depth stacking (frontmost disconnected first) rather than being
arbitrary with respect to the geometry. No randomization was added, per
the explicit "not this round unless design/tests can unambiguously
support it."

New test: `tests/test_wire_geometry.gd` (10 checks) -- each wire's two
segments are genuinely non-collinear (bent, not straight), each has a
real nonzero lateral offset, supply/service bow toward each other from
opposite sides, all three sit at distinguishable depths, and the
widened hitboxes still don't overlap a neighbor's.

**Not verified**: whether the bend/crossing/depth actually reads as
convincing "real wires" on screen, or whether the disconnect swing
looks sufficiently different from a rigid rod swinging -- geometric
facts about segment angles and positions were confirmed; the rendered
result was not seen. See the manual playtest checklist.

## D. Text simplification

The repair view's `StageLabel` (the single current objective, e.g.
"STAGE 2/5 -- DISCONNECT WIRES") was previously SMALLER (17pt) than the
mostly-static `TitleLabel` header (22pt) -- the least important,
unchanging line was visually louder than the one thing the player
actually needs to read each stage. Swapped the emphasis: `TitleLabel`
down to 14pt dim gray (context only), `StageLabel` up to 28pt bright
white (the dominant line), matching the brief's "one clear action at a
time" principle without changing any of the actual (already short,
single-line) stage/status/controls text content, which did not need
simplifying -- it was already free of multi-line procedural paragraphs
or spoiler-revealing permanent next-step text. Applied the same
title-down/status-up rebalancing to `SensorCalibrationView` for
consistency across both focused views.

## E. One global "Game Difficulty" setting

Player request verbatim: "Difficulty must apply across the entire
game, rather than belonging to an individual electrical repair task."
Previously `electrical_panel.gd` owned its own `@export var difficulty`
field, written directly by the workstation's Settings section -- a
real, working control, but task-owned exactly as the player described,
with no path for a future task to consult the same value without
duplicating the export.

Added `scripts/station/game_settings.gd`: the ONE authoritative
`Difficulty` (EASY/NORMAL/HARD) value for the whole game. Deliberately
NOT a scene-tree autoload and NOT a `class_name` global -- both were
tried and both are unreachable from this project's own headless test
scripts (`godot --headless --script`, which does not process
`[autoload]` and does not reliably see a brand-new `class_name` without
a full editor project scan, confirmed directly by a failing lookup
before this was discovered). Every consumer instead reaches it via
`const GameSettings = preload("res://scripts/station/game_settings.gd")`,
which resolves at parse time regardless of global registration and
works identically in-game and in every test. The value lives in plain
`static var`s, so this still behaves as one process-wide singleton.

`electrical_panel.gd`'s own `difficulty` export and `Difficulty` enum
were removed entirely; it now reads `GameSettings.get_difficulty()`.
`workstation_screen.gd`'s C02 diagnostic readout now reads the same
global value directly rather than through the panel. The Settings
section is now explicitly labeled **"GAME DIFFICULTY"** (not "panel" or
"electrical repair" difficulty), with detail text stating plainly that
it applies station-wide.

**Mid-repair stability policy** (documented, not merely implemented):
changing the global setting takes effect immediately for any task not
yet started. The moment a repair's door is opened for the first time,
`electrical_panel.gd` snapshots the current global value into
`_active_difficulty` and uses that locked snapshot -- not live reads --
for every difficulty-sensitive check (hint visibility, HARD's screw
count) for the rest of that one, non-repeatable repair. A brand-new
task started afterward sees whatever the global setting is at ITS own
first door-open. Verified directly: lock to NORMAL, disconnect two
wires, change the global setting to HARD mid-procedure, confirm hints
stay visible and the screw requirement stays 0 for the REST of that
repair even though a fresh task would now see HARD.

**Persistence**: no save/load system exists anywhere in this project,
and this milestone explicitly says not to add one as a side effect.
`GameSettings` uses a single, isolated `ConfigFile` key
(`user://game_settings.cfg`), read once lazily on first use and written
immediately on every change -- scoped to this ONE value, nothing else.
This means the chosen difficulty persists ACROSS LAUNCHES, not just
within a session. A brand-new game with no existing settings file
defaults to NORMAL.

New/rewritten test: `tests/test_difficulty_configuration.gd` -- the
Settings label now reads "GAME DIFFICULTY", C02 and the panel read the
same global value, and the mid-repair lock policy specifically (not
just "progress survives a change," but "requirements stay fixed").
Six other existing tests that call `panel.interact()` expecting an
immediate door-open were made defensively difficulty-agnostic (reset
the global setting to NORMAL at their own start), since the setting now
genuinely persists across separate test processes via the same disk
file a real play session would use.

## F. Calibration gauge clarity

Player report: "I can see [the cylindrical gauge] via Tab but don't
clearly understand how to operate or interpret it." The knob-drag and
A/D keyboard fallback were already shared by both gauge styles and
already worked identically either way -- the actual, confirmable defect
was color: the cylindrical gauge's TARGET marker (`0.75, 0.6, 0.25`,
gold) and its DIAL-SETTING marker (`0.7, 0.55, 0.3`, also essentially
gold) were nearly the same color, so the two most important distinct
concepts on that instrument were visually almost indistinguishable --
while the circular gauge already used genuinely different hues (green
tolerance arc vs. gold dial needle).

Fix: recolored the cylindrical gauge's TARGET to the same green family
as the circular gauge's tolerance band (`0.35, 0.75, 0.45`), kept the
dial tick gold but redrew it as a bold triangular wedge instead of a
thin same-toned line, and added small `draw_string()` labels ("TARGET",
"SET", "READING") directly on both instruments at their respective
markers -- one consistent color vocabulary (green = target/success,
gold = your commanded setting, white-to-green = actual lagging reading)
now shared by both gauge styles, while the two visual METAPHORS (needle
dial vs. scrolling drum) remain clearly distinct per the brief's "not
making the instruments look identical." The underlying L07 simulation,
Tab-toggle-is-cosmetic-only behavior, and existing drag/keyboard
controls are untouched.

No new task was created to showcase the cylinder; the wristwatch was
not touched or replaced by either gauge.

## G. Small polish

- **E06 discoverability**: re-verified (not re-built) under the new
  cabinet geometry -- see Section A above. Still a separate, correctly
  state-driven cue (`AttentionLight` + `get_interact_prompt()`), not
  overshadowed by the cabinet since it is 1.4m away in a different part
  of the room.
- **Mechanical sound**: already fully wired for every action this
  workstream touches -- wire disconnect/reconnect/install
  (`click`/`success`/`fail` via `_apply_result`), the breaker
  (`clunk`), and screws (`ratchet`/`success`), all through the existing
  `mechanical_sfx.gd` convention. No new sound framework was needed or
  added.
- **Font sizes/contrast**: addressed as part of Workstream D above for
  both focused views; the already-successful status lights and
  diagnostic indicators from earlier rounds were left untouched.
- **Control ownership**: unchanged and re-confirmed by the full test
  suite -- Space (pickup/drop), E (world interaction), C (watch), Tab
  (calibration display only), R (difficulty cycle in Settings) all
  still route through the same exclusive-session boundaries as before.

## Files changed

- `scenes/main.tscn` — `EngineeringCabinet1` rebuilt into a
  floor-standing housing with three compartments (see Section A);
  dozens of child nodes added/repositioned/renamed, none of E05's
  functional node names changed.
- `scripts/player/player_body.gd` — corrected `_WATCH_ARM_TARGETS` /
  `_WATCH_CASE_RAISED_POS` / `_WATCH_FACE_RAISED_POS` to satisfy actual
  camera frustum containment.
- `tests/test_wristwatch_screen_stability.gd` — added genuine frustum
  containment checks and a repeated press/release cycle test.
- `tests/test_cabinet_compartments.gd` (new).
- `tests/test_electrical_panel_chain.gd` — updated a hardcoded
  `get_node("DoorPanel")` reference to the new `UpperCover`.
- `scenes/ui/electrical_repair_diorama.tscn` — each wire's single
  straight `Run` replaced by a bent two-segment `Run`/`Run2` pair;
  collision shapes widened to `Shape_wire_bowed`; `DamageScorch`
  repositioned onto the new path.
- `tests/test_wire_geometry.gd` (new).
- `scenes/player.tscn` — `ElectricalRepairView`/`SensorCalibrationView`
  title/stage/status font-size rebalancing (Section D).
- `scripts/station/game_settings.gd` (new) — the global `GameSettings`
  singleton.
- `scripts/interactables/electrical_panel.gd` — removed its own
  `difficulty` export/enum; added `_active_difficulty` snapshot and
  `_current_difficulty()`; every `Difficulty.*` check now reads
  `GameSettings`.
- `scripts/ui/workstation_screen.gd` / `scenes/ui/workstation_screen.tscn`
  — Settings section now shows/cycles the global "GAME DIFFICULTY";
  C02 diagnostics read `GameSettings` directly.
- `tests/test_difficulty_configuration.gd` — rewritten for the global
  setting and the mid-repair lock policy.
- `tests/test_electrical_repair_procedure.gd` — difficulty set via
  `GameSettings` instead of a per-panel field; added a reset before the
  sync scenario to avoid leaking a prior scenario's difficulty.
- `tests/test_electrical_panel_terminal.gd`,
  `tests/test_electrical_panel_hatch_visual.gd`,
  `tests/test_interaction_prompts.gd`,
  `tests/test_focused_interaction_state.gd`, `tests/test_slice_b_e2e.gd`
  — each now resets the global difficulty to NORMAL at its own start,
  defensively, since the setting persists across separate test
  processes via the same disk file real play uses.
- `scripts/ui/cylindrical_gauge.gd` — recolored TARGET, redrew the
  dial-setting tick, added on-face labels.
- `scripts/ui/analog_gauge.gd` — added matching on-face labels.

## Known limitations / deferred

- No rendering/visual verification was possible in this environment
  (confirmed again, by direct attempt, not by assumption) -- the
  cabinet's standing-cabinet appearance, the watch's actual on-screen
  look while raised, the wires' bend/crossing/depth, and the gauges'
  on-face labels are all verified by static inspection, geometric
  frustum/footprint checks, and headless behavioral tests only, never
  by sight. See the final report's manual playtest checklist.
- The wire bend/crossing uses hand-picked, round-numbered bow
  magnitudes and small-angle Euler approximations for the segment
  tilts, not exact endpoint-matched 3D rotations -- a deliberate,
  documented simplification for a cosmetic prototype cable, not a claim
  of physical/geometric precision.
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited again this round via a fresh repo-wide search
  and full git history search -- zero new evidence found). Not
  invented, not marked obsolete, consistent with every prior round's
  finding.

## Future maintenance roadmap (not implemented this round)

Explicitly deferred candidate systems -- listed as future design
candidates only; no mechanics or task IDs for any of these were
introduced this round:

1. Circuit tracing with probes and a schematic.
2. Valve sequencing / coolant routing with visible pressure/flow
   effects.
3. Pump diagnosis via audio/vibration/instrument readings.
4. Mechanical alignment / physical component replacement.
5. Power distribution / load balancing.
6. Integrated subsystem faults with cascading consequences.
7. EVA suit checks / airlock procedures.
8. Dynamic maintenance work orders with dependency chains.
9. Believable room-specific environmental sound / material wear.
10. A shared skeletal character model and proper first-person arm
    animation.
11. Slow-burn psychological anomalies affecting familiar
    equipment/logs/cameras.
12. Optional emergency tasks reusing previously-learned mechanics.

---

# ROUND 11: FIRST-PERSON WRISTWATCH, PHYSICAL WIRING, AND ADVANCED CALIBRATION

## Scope

A direct playtest round again: holding C to check the watch made the
player's whole body disappear (a genuine, serious regression); the
wire-reconnect puzzle had a dead-end bug where the required wire
became physically unclickable; the wires still read as rigid rods, not
cables; L07's calibration task was "too simple"; and the cabinet
blended into its surroundings. Six workstreams (A-F below), all
implemented this round.

## A. Wristwatch architecture: separating the world body from the first-person presentation

**Root cause (A1)**, confirmed by reading `player_body.gd`'s
`_process()` directly, not assumed: the Round 9/10 watch-visibility fix
eased `PlayerBody`'s OWN pitch follow toward a FULL 1.0 while the watch
was raised, to keep a watch node parented under `StandingPose` camera-
anchored. `StandingPose` parents the ENTIRE visible body -- torso,
hips, legs, both arms. Rotating the whole body in lockstep with the
camera's full pitch around the eye-point pivot is mathematically
correct for a single small fixed offset close to that pivot (the old
watch), but wrong for a body extending ~1.6m below it: at any real
pitch (most naturally, looking down to check a watch), most of the
body's mass swings outside the frustum or behind the camera. At
pitch=0 nothing ever looked wrong, which is consistent with the report
-- this is pitch-dependent, not a binary "watch raised = body hidden"
flag.

**The fix (A2)**: `player_body.gd` no longer has ANY watch-related
logic or full-pitch-follow mode at all -- it always uses its ordinary
PARTIAL `standing_pitch_follow` (0.3), watch raised or not, so the
world body never again inherits an artificial camera-relative offset.
A new node, `scripts/player/first_person_watch_rig.gd` +
`scenes/player/first_person_watch_rig.tscn`, is a plain child of
`Camera3D` (`scenes/player.tscn`) and owns the ENTIRE watch inspection
presentation: a tapered forearm, hand, and the watch, all rigidly
camera-relative by ordinary scene-graph parenting, needing no per-frame
tracking math at all and therefore unable to ever separate from the
camera's view. It has no collision authority, never touches
`Player`/`PlayerBody`'s transform, movement, or any game-state
authority -- raising/lowering is a position tween on one internal
"ArmGroup" node, from a far-off-screen "lowered" offset to the
already-frustum-verified "raised" offsets Round 10 established (reused
directly, since those were already confirmed safe across a wide yaw/
pitch sweep). `player_body.gd` keeps one small, optional, purely
defensive reference to this rig (`watch_rig_path`) used only to force
it down instantly when the player starts sitting -- the same race-
condition safeguard the old code had, just delegated instead of
self-contained.

**Double-arm duplication**: `StandingPose`'s own right arm simply never
moves for this feature anymore -- it stays in its ordinary resting-at-
the-side pose at all times, exactly like the left arm. Combined with
`standing_pitch_follow`'s own existing design (the whole body, resting
arm included, stays out of frame under ordinary look angles by the
same mechanism that keeps the torso out of frame), there is nothing to
duplicate in practice; every CSG root under the new rig is additionally
tagged `layers = 2` so a future third-person/mirror camera could
exclude it via `cull_mask` without this script needing to change.

**Future skeletal integration**: documented directly in the rig's own
class doc comment -- this is the same "first-person view-model
attached to the camera, separate from the world skeleton" pattern
nearly every FPS game with third-person/mirror support already uses;
`set_raised()`/`set_watch_text()` would not need to change when the
current CSG primitives are eventually replaced by a real skinned mesh.

**Wristwatch visual spec (A3)**: the forearm is now three tapered
cylinder segments (radius narrowing from near-elbow to wrist) with
sphere joints hiding the seams, a flattened box palm, a small curled
"finger mass" with a rounded tip, and an angled thumb cylinder --
clearly recognizable as a forearm/hand silhouette, not a uniform
cylinder+sphere, while staying an honest prototype (not a claim of
photorealistic anatomy). The watch case grew four corner fasteners, a
side crown and a side button, a dedicated metal bezel and a dark
recessed face plate, and a strap with a visible retaining loop,
wrapping the wrist via a cylinder band positioned to join it rather
than float beside it. The watch screen's `Label3D` was previously sized
for a MUCH larger face (pixel_size 0.0011, width 260px = 0.286m of text
block against a 0.062m-diameter face -- the actual, measurable "floating
text outside the case" bug) -- now sized to fit inside the real face
plate (pixel_size 0.00032, width 170px ≈ 0.054m, comfortably inside the
new ~0.066m face), with no change to the underlying DayPlan-driven
content it displays.

**Animation (A4)**: unchanged conceptually from Round 10's tween
approach, just now operating on the rig's own nodes instead of
`StandingPose`'s -- a sine-eased position tween between the lowered and
raised offsets, `visible` toggled synchronously with the flag so a
forced lower can never leave it stuck, and idempotent by state so rapid
press/release can never stack redundant tweens.

**Verification (A5)**: `tests/test_wristwatch_screen_stability.gd` was
rewritten to check the ACTUAL regression directly -- sampling the
world body's own hips/chest/foot `global_position` across a real pitch
sweep with the watch raised, then again with it lowered, and asserting
they are IDENTICAL (not merely that the watch itself stays visible).
It also re-verifies the rig's own frustum containment (near plane +
fov-derived half-angle, not `unproject_position()` alone) across 30
yaw×pitch combinations including steep angles, and a 4-cycle repeated
press/release test. All of this is geometric/transform verification,
not a rendered-pixel observation -- headless rendering remains
unavailable in this environment (re-confirmed). See the final report's
manual playtest checklist.

## B. Electrical repair: the reconnect dead-end bug, and genuinely curved crossing wires

**B1 root cause**, found by tracing the actual code path end to end,
not assumed: once `install_replacement_wire()` commits, the diorama
hides the ORIGINAL `Service` wire node and shows `ReplacementWire`
instead (confirmed in `sync_full_state()`/`begin_replace_sequence()`)
-- so during RECONNECT, the real, visible, clickable collider for the
service/yellow role is `_replacement_collider` (action
`&"replacement"`), never `_wire_colliders[&"service"]` (action
`&"wire:service"`, now pointing at an invisible node).
`electrical_repair_view.gd`'s `_update_allowed()` for the RECONNECT
stage listed `&"wire:service"` and never `&"replacement"` -- so a real
click on the visibly-yellow wire resolved to an action that was never
in the allowed set, and the raycast resolved to nothing at all.
Separately, even if it had been allowed, the diorama's own
`_dispatch_click()` would have routed that click to the
`replacement_clicked` signal -> `_on_replacement_clicked()`, which only
ever handled the REPLACE-stage install click and returned early for
every other stage. Both halves of the bug were fixed together:
`_update_allowed()` now lists `&"replacement"` for RECONNECT (and
routes the hint pulse there when service is next), and
`_on_replacement_clicked()` now also handles the RECONNECT stage by
calling `reconnect_wire(&"service")` exactly as `_on_wire_clicked`
would for any other role. `electrical_repair_diorama.gd` also gained
`_resolve_wire_node(role)`, so any animation/material lookup for
`&"service"` after replacement correctly targets the replacement node,
never the permanently-hidden original.

A new regression test, `tests/test_reconnect_hitbox_bug.gd`, drives the
ENTIRE procedure through the REAL raycast/hover resolution path
(`_raycast_action()` via `screen_position_for()`, the same technique
`test_electrical_repair_diorama.gd` already established for this
headless environment) rather than direct backend calls -- reproducing
the exact reported sequence (wrong click, then the required yellow
click) and confirming it now succeeds. This is also WHY the previous
test suite never caught it: every existing reconnect test called
`_on_wire_clicked()`/`_on_replacement_clicked()` directly, bypassing
the allowed-list/collider-mapping layer entirely.

**B2/B3 wire geometry**: `electrical_repair_diorama.gd`'s wires are no
longer hand-authored straight or two-segment-bent rods. `_build_wire_curve()`
samples a quadratic Bezier (anchor -> a per-wire control point -> the
fixed terminal lug) into six straight chord segments at runtime, giving
a genuinely smooth multi-point curve instead of a rigid angle. Chosen
control points make supply (disconnected FIRST) bow toward the front
and one side, service (disconnected LAST) bow toward the back and the
other side, and return stay near-center -- their lateral sweeps
GENUINELY OVERLAP in world X (verified: a real geometric intersection,
not merely "close together"), with an unambiguous front-to-back depth
order (supply in front, return in the middle, service behind) that
matches the required disconnect order, so "topmost removed first"
reads correctly at the crossing. The chosen physical interpretation
(consistent with Round 10) remains "hangs under ordinary station
gravity" -- the existing swing-the-whole-node-on-disconnect animation
needed no changes, since it already pivots at the still-attached top
end; it now swings a genuinely curved cable instead of a straight one.

Click targeting required a real redesign, not just a wider box: the
brief's own guidance ("prioritize connector/terminal hotspots... over
accidental clicks on any part of an overlapping cable") was followed
literally -- each wire's hitbox moved from the tangled crossing zone
near the middle down to a small box near its own terminal end, where
the curve has already narrowed back toward its own anchor column and
no longer overlaps a neighbor's. Verified: the three wires' hitboxes
still don't overlap each other despite the much wider visual sweep at
the crossing.

New test `tests/test_wire_geometry.gd` (rewritten for the new
structure): all six chords exist and are genuinely non-collinear
(a real curve), all six share one material resource (hover still
lights the whole wire), supply/service bow toward each other from
opposite sides with a real overlapping extent, the front-to-back depth
order matches disconnect order, and hitboxes stay non-overlapping.

**B4/B5/B6**: disconnect/reconnect visuals, difficulty locking, screw
mechanics, cancel/reentry, and wrong-action recoverability are
unchanged in behavior and re-confirmed by the full existing
`test_electrical_repair_procedure.gd` suite passing unmodified except
for the one `get_node("DoorPanel")` reference updated in Round 10 and
the B1 fix above.

## C. Sensor calibration: a genuine three-control tuning puzzle

**C1/C2**: L07 keeps its task identity, its 0-100 scale, its target
50.0, its stability-gated completion, and its circular/cylindrical
instrument choice -- what changed is the SIMULATION underneath. The
previous version was a first-order exponential lag
(`displayed = lerp(displayed, setpoint, 1-exp(-rate*delta))`), which
can only ever approach a target, never overshoot it, regardless of
tuning -- mathematically incapable of producing the brief's own
"poor tuning causes an observable oscillation or prolonged settling."
It is now a genuine damped spring-mass system:
`acceleration = RESPONSE_STRENGTH * (setpoint - reading) - damping * velocity`,
integrated every frame (delta clamped to 0.05s for numeric stability at
low frame rates). `RESPONSE_STRENGTH` (the sensor's own fixed
responsiveness) never changes; `damping` is the one new thing the
player directly commands, starting deliberately UNDERDAMPED (1.4,
against a critical value of 6.0 for this strength) so a player who
never touches it will visibly oscillate and never settle -- a real,
deterministic, learnable relationship, not a random difficulty tax.
Verified directly: a single coarse jump produces a reading that
crosses back and forth over the target at least twice before damping
is raised, and raising damping toward critical lets the identical
setpoint settle and succeed.

Three controls, each with a knob (click-drag, the existing rotary-
encoder convention) AND a keyboard fallback: Coarse (A/D, Left/Right,
or its knob) moves the setpoint quickly; Fine (Q/E, or its knob) moves
it by roughly 6x less per the same input, for precise correction;
Damping (Z/X, or its knob) is the new convergence control. All three
share one drag handler (`_on_knob_gui_input`, bound per-control via
`Callable.bind`), with only one knob "grabbed" at a time so overlapping
drag gestures can't fight each other.

**C3 difficulty**: reads `GameSettings.get_difficulty()` directly, like
every other difficulty-sensitive system -- L07 had NO difficulty
sensitivity at all before this round. EASY gets a wider tolerance
(±5.0) and a shorter required hold (1.0s); HARD gets a tighter
tolerance (±2.0) and a longer hold (2.2s); NORMAL keeps the previous
±3.0/1.5s. The underlying spring physics (`RESPONSE_STRENGTH`) never
changes by difficulty -- only the acceptance criteria and hint
visibility do, so the learned coarse/fine/damping relationship stays
identical regardless of difficulty. No explicit lock was needed for
mid-attempt difficulty changes: this view holds exclusive focused
input the entire time an attempt is open (the same
`focused_interaction_state.gd` boundary every other focused view
uses), so the player structurally cannot reach the workstation's
Settings section mid-calibration -- reading the global value once per
`open_station()` call is already the simplest correct policy.

**C4/C5/C6 presentation**: the two knobs and gauge used to sit in one
flat `HBoxContainer` with large empty dark space around them. They now
share a `Panel`-backed "console" housing with the three labeled knobs
in their own column beside the active gauge, so the controls read as
physically connected to the instrument they drive rather than floating
separately. Both gauges retained their existing circular-needle/
scrolling-drum identities and the Tab-toggle-is-cosmetic-only
behavior; this round's gauge work was Round 10's legend/color-
consistency pass (TARGET/SET/READING labels, shared green/gold/white
vocabulary) and did not need further changes here.

**C7 discoverability**: a one-time (per game session, `static var
_ever_opened`), auto-dismissing hint line appears on the FIRST ever
`open_station()` call, explaining the three controls' roles in one
sentence, and disappears the instant the player touches any control
(key or knob) or after 7 seconds, whichever comes first -- never shown
again that session, never solving the puzzle for the player.

**C8 testing**: `tests/test_sensor_calibration.gd` (rewritten) verifies
coarse movement, lag, overshoot pinning at the gauge limits, a real
two-crossing oscillation while underdamped, successful settling once
damping is raised, and the full completion/reopen contract.
`tests/test_sensor_calibration_knob.gd` (rewritten) verifies each of
the three knobs drives its OWN distinct value at its OWN distinct
sensitivity (fine genuinely ~6x finer than coarse for the same drag
angle), that the damping knob never touches the setpoint, that only
one knob can be grabbed at a time, and that all three go inert once
done. `tests/test_sensor_calibration_difficulty.gd` (new) verifies
EASY/NORMAL/HARD's actual tolerance/stability values, that
`RESPONSE_STRENGTH` never changes by difficulty, and that HARD still
permits a genuine correctly-tuned success.

## D. Cabinet material/contrast polish

Player report: the cabinet's color blends too closely into its
surroundings. No geometry, collision, dimensions, world position, or
compartment organization was touched -- only materials.
`StandardMaterial3D_elec_panel_body` (the outer housing) moved from
albedo `(0.1, 0.11, 0.14)` to `(0.17, 0.18, 0.22)` with higher
roughness (matte, less light-absorbing); `StandardMaterial3D_elec_panel_door`
(the three access covers) moved to `(0.26, 0.27, 0.31)` with LOWER
roughness/metallic than the housing, so covers read as smoother
"serviced panels" distinct from the rougher outer shell, per the
brief's own suggested "cool dark metal housing with slightly lighter
service panels." A new `StandardMaterial3D_elec_panel_accent`
(muted teal, `(0.2, 0.52, 0.5)`) replaces the plain gray breaker
material on all six compartment hinges, giving a restrained, non-
hazard-stripe accent that marks the three access points as a
deliberate design language rather than a byproduct of reusing generic
hardware dressing. Verified geometrically: the housing's luminance now
differs from the room's wall material by a real, measurable margin
(0.22 vs. 0.50), the covers are a genuinely different material from
the housing (not merely the same resource relabeled), and the hinge
accent is a genuinely different color from ordinary gray hardware.

## E. Shared interaction quality

Reviewed, not rebuilt -- every item in the brief's checklist was
already satisfied as a direct consequence of this round's
implementation choices, confirmed by the full suite:

- The world body's transform is identical whether the watch is raised
  or not (Workstream A's own regression test).
- The watch rig carries no `CollisionShape3D`/`StaticBody3D` anywhere
  in its tree -- visual only.
- No body duplication: the world body's right arm simply never moves
  for this feature, and stays out of frame under ordinary look angles
  by the same mechanism that already keeps the torso out of frame.
- No input leakage: `sensor_calibration_view.gd`'s `_unhandled_input`
  consumes the full new key set (A/D/Left/Right/W/S/Q/E/Z/X) exactly
  like the old set; both focused views still gate all input behind
  `visible`/`_station != null`/`_done` checks.
- Mouse targeting through overlapping wire meshes: covered directly by
  `test_reconnect_hitbox_bug.gd` and `test_wire_geometry.gd`'s hitbox-
  overlap checks.
- No permanently inaccessible next step: the B1 fix's entire point.
- Calibration controls/Tab/Escape: unchanged gating logic, re-verified
  by the existing focused-interaction and cylindrical-gauge tests.
- Space pickup/drop, global difficulty propagation: re-confirmed by
  `test_carry_drop.gd`/`test_difficulty_configuration.gd` passing
  unmodified.
- No new task registries: zero new task IDs introduced this round.
- No duplicate signal connections: the three knobs' `gui_input` signals
  are each connected exactly once, in `_ready()`, never re-connected on
  `open_station()`.
- No visual state drift: the gauge-mirrors-view and diorama-mirrors-
  panel-state tests all still pass.

No new sound feedback was added for the fine/damping controls --
consistent with the existing convention (the original coarse/knob
controls never had per-adjustment sound either, only the final success
cue), and adding one now would be a new convention, not a fix to a
reported gap.

## Files changed

- `scripts/player/player_body.gd` -- removed ALL watch-related
  state/logic; pitch follow is now unconditionally the ordinary
  partial value; added an optional `watch_rig_path` for the sitting-
  transition defensive lower.
- `scripts/player/first_person_watch_rig.gd` (new) -- the camera-child
  watch inspection rig.
- `scenes/player/first_person_watch_rig.tscn` (new) -- tapered
  forearm/hand/watch geometry.
- `scenes/player/player_body.tscn` -- removed the old
  StandingPose-parented WatchCase/Strap/WatchFace nodes.
- `scenes/player.tscn` -- instanced the new rig under `Camera3D`;
  rewired `Wristwatch`'s and `PlayerBody`'s paths to it; rebuilt
  `SensorCalibrationView`'s control layout into a console with three
  knobs.
- `scripts/player/wristwatch_view.gd` -- retargeted from
  `player_body_path`/`set_watch_raised()` to `watch_rig_path`/
  `set_raised()`.
- `tests/test_wristwatch.gd`, `tests/test_wristwatch_screen_stability.gd`
  -- rewritten for the new rig architecture and the actual body-
  disappearance regression.
- `scripts/ui/electrical_repair_view.gd` -- B1 fix
  (`_update_allowed()`/`_on_replacement_clicked()`).
- `scripts/ui/electrical_repair_diorama.gd` -- `_resolve_wire_node()`;
  procedural `_build_wire_curve()`/`_bezier_point()`/`_basis_with_y()`
  replacing the hand-authored bent-rod geometry.
- `scenes/ui/electrical_repair_diorama.tscn` -- wires simplified to one
  template segment each (the script builds the rest); collision boxes
  repositioned/resized near the terminal ends.
- `tests/test_reconnect_hitbox_bug.gd` (new), `tests/test_wire_geometry.gd`
  (rewritten).
- `scripts/ui/sensor_calibration_view.gd` -- rewritten: spring/damping
  physics, three knobs, difficulty-driven tolerance/stability,
  first-use hint.
- `tests/test_sensor_calibration.gd`, `tests/test_sensor_calibration_knob.gd`
  (rewritten); `tests/test_sensor_calibration_difficulty.gd` (new).
- `scenes/main.tscn` -- cabinet material contrast
  (`StandardMaterial3D_elec_panel_body`/`_door`, new
  `_elec_panel_accent` on the six hinges).
- `tests/test_cabinet_compartments.gd` -- added material-contrast
  checks.

## Known limitations / deferred

- No rendering/visual verification was possible in this environment
  (confirmed again, by direct attempt) -- the watch's actual on-screen
  look, the wires' bend/crossing/depth, the console layout, and the
  cabinet's contrast are all verified by static inspection, geometric
  frustum/footprint/luminance checks, and headless behavioral tests
  only, never by sight. See the manual playtest checklist.
- The wire curve's bow magnitudes and segment orientations use hand-
  picked, round-numbered control points and a small-angle-safe basis
  construction, not a claim of physically exact cable mechanics -- a
  deliberate, documented simplification for a cosmetic prototype cable.
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited again this round via a fresh repo-wide search
  and full git history search -- zero new evidence found, consistent
  with every prior round).

---

# ROUND 12: WRISTWATCH VISUAL QUALITY, ELECTRICAL REPAIR FIDELITY, AND GAMEPLAY PRESENTATION

## Scope

A visual-quality round, triggered by the user's actual screenshots
rather than a described complaint. This round made a genuine
capability discovery that changes how every future round should be
verified: this machine has a real GPU (Apple M1, Metal), and
`godot --path . --write-movie <file>.png --quit-after N` (or combined
with `--script <driver>.gd` to programmatically set up a scene state
first) produces REAL rendered PNG frames, not a dummy/headless
no-op -- confirmed directly, not assumed, by rendering the exact
scenes this round needed to fix and inspecting the output. Every
visual claim in this section was checked this way, not merely by
reading code or computing projections.

## Capability discovery: real rendered screenshots are possible here

Previous rounds' repeated finding that "headless rendering is
unavailable" was correct for `--headless` specifically (confirmed
again this round: `DisplayServer.get_name()` still returns
`"headless"` and texture read-back still errors under that flag) --
but this machine is not a headless server. It has a GPU, and running
WITHOUT `--headless`, using Godot's built-in Movie Maker mode
(`--write-movie`), renders real frames through the actual Forward+
renderer and writes them as numbered PNGs. Combining this with a
`--script <driver>.gd` that loads `main.tscn`, programmatically
positions the player / drives a task's backend+view calls, waits a
few frames, then quits, makes any in-game visual state inspectable on
demand. This was used to directly confirm the player's two reported
screenshots, to verify every fix in this round against the real
render (not just geometry math), and should be the default
verification method for future visual work in this environment,
replacing the geometric-proxy-only approach of Rounds 9-11.

## A. Wristwatch: framing and hand silhouette

Rendering the Round 11 watch directly (not re-describing the
screenshot the user provided, but independently reproducing it)
confirmed the report precisely: the assembly sat crammed into the
very bottom-right corner, partially cut off, the watch face's text
was tiny, and the "hand" read as a few disconnected tan boxes with an
odd triangular shape poking up -- not a recognizable hand.

**Framing (A2)**: moved the whole arm/watch/hand assembly closer to
the camera (watch center distance ~0.46m, down from ~0.53m) and
shifted it up and slightly left as a rigid block so the full case and
most of the wrist are inside frame with real margin below it, instead
of touching the bottom edge. Re-verified
`test_wristwatch_screen_stability.gd`'s full yaw/pitch frustum sweep
still passes at the new position (near-plane + fov-derived half-angle,
not `unproject_position()` alone).

**Hand silhouette (A3)**: replaced the single boxy "FingerMass" +
"Thumb" pair with four individually-modeled fingers (a tapered
cylinder + a rounded tip sphere each, lengths graduated -- middle
longest, index/ring slightly shorter, pinky shortest) curling forward
and down from the palm's far edge, plus a separate thumb originating
lower on the palm and angled outward/across -- all still CSG
primitives (no skeletal mesh, per the explicit "do not begin the full
skeletal-character milestone"), but composed for silhouette/continuity
rather than as disconnected blocks. The existing tapered forearm
chain (3 segments narrowing toward the wrist, sphere joints hiding the
seams) was kept, just repositioned with the rest of the assembly.

**Watch construction (A4)**: the case grew from 0.1x0.09x0.038 to
0.13x0.115x0.046 (visibly more substantial, matching "give the case
some visual weight"), with proportionally larger bezel, fasteners,
crown and side button; strap/keeper-loop kept from Round 11 (already
wraps the wrist via a cylinder band, not glued-looking).

**Watch UI (A5)**: TWO concrete, separate fixes. First, the Label3D's
own physical size was still authored for a much larger face
(inherited from Round 11's partial fix) -- enlarged again now that the
case itself is bigger (pixel_size 0.00042, width 190px ≈ 0.080m, font
20, against the new face's ~0.086m diameter) and verified by a new
automated check (`test_wristwatch.gd`) that computes the Label3D's
real physical footprint in meters and compares it against the face
plate's actual radius -- not merely "some text exists". Second, and
more substantively, the CONTENT itself was simplified:
`wristwatch_view.gd`'s `_refresh_text()` used to show a full paragraph
("No assignment yet — check in at the Control Room workstation.")
plus the complete multi-line work-order summary. It now shows exactly
one glanceable two-line status -- an action word (CHECK IN / TASK:
E06 / VERIFY REPAIR / ALL CLEAR) and the outstanding room, both
derived directly from `DayPlan.get_outstanding_task_room()` and
`assignment_task_id` (the SAME fields the station map already uses for
"which room to head to next" -- no second copy of that priority
logic, no invented in-game clock, since this project has no time/
calendar system at all and fabricating one was explicitly
out of scope). Full work-order detail remains exactly where it was:
the Control Room workstation.

**Animation (A6)**: unchanged mechanically from Round 11 (the same
tween-based raise/lower on the rig's ArmGroup); re-verified with the
existing 4-cycle repeated press/release test and the full pitch-sweep
world-body-identity test, both still passing at the new position.

## B. Electrical repair: the completed-state contradiction and cable geometry

Rendering the Round 11 "REPAIR COMPLETE" state directly reproduced the
reported inconsistency exactly: a large asymmetric red loop that
visually hooked back on itself, a nearly-straight blue line, and a
yellow wire that was almost entirely MISSING (only a tiny stub near
its terminal was visible) -- while the screen said the repair was
complete.

**Root cause (B1), found by direct investigation, not assumed**: two
separate, compounding geometry bugs, both only visible through an
actual render:
1. Round 11's "crossing" bow made each wire's curve bow OUT from its
   own anchor and back to the SAME anchor x at the bottom -- a
   symmetric "out and return" shape that reads as a confusing hook/
   loop rather than a cable, especially for the wire with the largest
   bow (supply).
2. The depth offset used to separate the three wires' crossing layers
   pushed the service wire's path BEHIND the opaque `InsetPanel`/
   `Backdrop` panels (which sit only ~0.015m behind the wire anchors
   -- almost no clearance), clipping nearly the entire wire except
   the small portion right at its own terminal.

**The fix**: wire paths are no longer an "out and return" bow. Each
wire now has its own ENTRY point offset toward the OPPOSITE side (supply
enters from the right, service from the left), so the two outer wires
travel in one consistent diagonal direction and genuinely swap sides
end to end -- confirmed monotonic in both X and Y (no loop) via direct
calculation before implementing. Depth layering is now expressed as a
FORWARD-only push (toward the camera): supply (disconnected first)
pushes forward the most, service (disconnected last) stays at its own
anchor's baseline depth -- still a strict, unambiguous front-to-back
order, but nothing ever recedes past where it already safely sits, so
the InsetPanel/Backdrop clipping bug cannot recur. Re-rendering
confirmed all three cables now read as smooth, continuous, plugged-in
wires crossing cleanly through the center, with REPAIR COMPLETE no
longer visually contradicted by the equipment.

**Panel components (B2/B6)**: each terminal gained a backing housing
plate, a recessed socket cylinder the wire's cap visibly seats into,
and two mounting screws; each indicator light gained a small bezel
frame instead of floating as a bare square. The breaker gained a
mounting bracket, a face frame, a bezel around its status light, a
visible pivot pin, and a distinct lever-cap paddle shape -- re-rendered
and confirmed it now reads as a real toggle switch, not a flat
rectangle.

**Cable geometry (B3)**: still six-chord quadratic-Bezier segments
(Round 11's technique), now built from [entry point, sag control
point] pairs per role instead of a single bow-control point -- see
`_WIRE_CURVE_POINTS`'s class doc comment for the exact reasoning.
Endpoints are verified (new test) to land exactly on each wire's own
terminal lug, and no segment is allowed to recede behind its own
anchor depth (the direct regression check for the B1 root cause).

**B4/B5/B7**: disconnect/replace/reconnect/complete visual states,
difficulty locking, Hard screws, wrong-order recovery, and the
Round 11 replacement-wire hitbox fix are all unchanged in behavior and
re-confirmed by the full `test_electrical_repair_procedure.gd` and
`test_reconnect_hitbox_bug.gd` suites passing unmodified. All visual
state still derives from `electrical_panel.gd`'s authoritative
procedure stage through `sync_full_state()`/the animate_* entry
points -- no new independent visual booleans were introduced.

## C. Debug label cleanup

The giant yellow room/tunnel-name labels (`DevLabels` in main.tscn,
each a `dev_label.tscn` instance -- a billboarded, `no_depth_test`
Label3D with no visibility gating of its own) were confirmed, via a
direct render, to be permanently visible during ordinary gameplay --
not an inference from code, an actual screenshot showing "CORRIDOR" /
"MAIN JUNCTION" / "AIRLOCK" overlapping across a third of the frame.

Fix: `DevLabels` now defaults to `visible = false`.
`scripts/dev/nav_debug_overlay.gd` -- this project's EXISTING,
already-off-by-default (`enabled = false`) station-topology debug
tool, toggled with F3 -- gained one new optional export
(`room_labels_path`) and now also owns this node's visibility,
syncing it with its own ring/edge overlay's visibility in both
`_ready()` and the F3 handler. One toggle, not two. A direct re-render
of the same default view confirmed the labels are gone in normal
gameplay; `test_debug_labels_visibility.gd` (new) confirms both the
default-hidden state and that enabling the existing overlay (and
pressing F3) reveals the labels together with the nav diagnostic mesh,
never independently.

## D. Quality-of-life review

Cabinet material/contrast (Round 11), the calibration console's
coarse/fine/damping model (Round 11), and existing mechanical SFX for
connector release/seating/breaker movement (pre-existing,
`_apply_result()`/`_play_feedback()`) were all reviewed and found to
need no changes this round -- confirmed by the full existing test
suite passing unmodified for every one of those systems. No new audio
framework or additional calibration mechanics were introduced, per the
brief's explicit "do not divert most of this milestone into unrelated
changes."

## Files changed

- `scripts/player/first_person_watch_rig.gd` (doc comment only --
  behavior unchanged) / `scenes/player/first_person_watch_rig.tscn` --
  repositioned assembly; rebuilt hand (4 individual fingers + thumb);
  enlarged watch case/bezel/fasteners/face text.
- `scripts/player/wristwatch_view.gd` -- `_refresh_text()` rewritten
  for a concise two-line status from `get_outstanding_task_room()`/
  `assignment_task_id`.
- `tests/test_wristwatch.gd` -- updated text assertions for the new
  concise format; added a physical face-bounds check.
- `scripts/ui/electrical_repair_diorama.gd` -- `_WIRE_CURVE_POINTS`
  (entry+control per role, replacing a single bow-control point);
  `_build_wire_curve()` updated for the new two-point signature.
- `scenes/ui/electrical_repair_diorama.tscn` -- `Backdrop` moved back
  for depth clearance; terminal backings/sockets/screws/indicator
  bezels added; breaker bracket/frame/pivot/lever-cap added.
- `tests/test_wire_geometry.gd` -- added checks for the Round 12
  occlusion regression (no segment recedes behind its own anchor
  depth) and endpoint-to-terminal alignment.
- `scripts/dev/nav_debug_overlay.gd` -- `room_labels_path`; syncs
  `DevLabels` visibility with the existing enabled/F3 state.
- `scenes/main.tscn` -- `DevLabels` defaults to `visible = false`;
  `NavDebugOverlay`'s `room_labels_path` wired to it.
- `tests/test_debug_labels_visibility.gd` (new).

## Known limitations / deferred

- Rendered screenshots were captured and inspected for the specific
  states this round needed (watch raised at two task-state variants,
  the initial/disconnected/complete electrical panel states, and
  normal-gameplay debug-label visibility) -- not an exhaustive sweep
  of every look angle, task state, or difficulty. Steep up/down pitch
  angles and the HARD-difficulty screw view were NOT re-rendered this
  round (only re-verified geometrically, via the existing frustum
  test); see the manual playtest checklist for what still needs human
  eyes.
- The hand remains CSG primitives, not a skinned mesh -- a
  deliberately bounded prototype improvement, not a claim of
  anatomical precision. Future skeletal-character work can replace
  this rig's internals without changing its `set_raised()`/
  `set_watch_text()` API (see the rig's own class doc comment).
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited again this round -- zero new evidence,
  consistent with every prior round).

---

# ROUND 13: ELECTRICAL RELIABILITY, SHARED PANEL VISUALS, AND COUPLED PRESSURE CALIBRATION

## Scope

A reliability-and-coherence round: a recurring wire-reconnection
defect, a mismatch between the in-world and focused electrical
equipment, a poorly lit cabinet, and a request for real depth in L07's
calibration minigame. Six workstreams, all implemented and verified
with actual rendered screenshots this round (see the new capability
note below).

## Capability note: real rendered screenshots, confirmed and used throughout

Round 12 discovered that `godot --path . --write-movie <file>.png
--quit-after N` (NOT `--headless`) produces genuine GPU-rendered PNG
frames on this machine (Apple M1, Metal backend) -- this round made
that the DEFAULT verification method for every visual claim, not an
occasional spot-check. Every fix below (the Yellow/Blue reconnect
race, the shared equipment architecture, cabinet lighting, the hand
silhouette) was captured BEFORE and AFTER via a small `--script
<driver>.gd` (loads `main.tscn`, drives the exact panel/view calls
needed to reach a state, positions the player using the established
`free_body.sync_to_eye_position(pos)` + `player.global_position = pos`
pattern -- confirmed this round that skipping the `sync_to_eye_position`
call lets an unrelated system silently snap the player back to the
scene's default spawn point every frame, which cost real time to
diagnose) and inspected directly, not inferred from geometry math.

## A. The Yellow→Blue reconnection bug: root cause, reproduction, and fix

**Reproduction**: a direct diagnostic reproduced the exact reported
sequence (reconnect Yellow, immediately click Blue) and found TWO
independent, real defects in the production code, not a flaky test:

**Root cause #1 -- stale hover-cache dispatch.**
`electrical_repair_diorama.gd`'s `_unhandled_input()` dispatched every
click through `_hovered_action`, a value refreshed only once per
`_process()` tick. Mouse MOTION events are delivered through the same
input queue but were never used to update the hover target directly --
only `_process()`'s own per-frame raycast did that. A fast, deliberate
mouse-move-then-click landing within a single rendered frame could
therefore fire using whatever was hovered a frame EARLIER (e.g. the
wire just reconnected) instead of what is actually under the cursor at
the moment of the click.

**Root cause #2 -- the collider rides along with the animating
visual.** Each wire's `Collision` StaticBody3D was a direct SIBLING of
its own visual mesh, both children of the SAME node whose
`rotation.x` the connect/disconnect tween animates. While a wire's
reconnect-settle animation (0.3s) is still in flight, its collider
physically sweeps through 3D space along with the visual -- and the
sweep's own lateral travel (radius ~0.64 at up to 58 degrees ≈ 0.54m)
very nearly equals the ~0.55m spacing between adjacent terminals, so a
ray aimed at a NEIGHBORING wire's terminal could resolve to the
animating wire's own still-moving collider instead.

**The fix, addressing the underlying lifecycle rather than patching
around either symptom**:
1. `_unhandled_input()` now resolves the click target via a FRESH
   raycast at the mouse-button event's own screen position
   (`_raycast_action(event.position)`), not the cached
   `_hovered_action` -- `_hovered_action`/`_update_hover()` remain
   exactly as before for the purely cosmetic hover-glow highlight,
   which can tolerate a frame of lag; click RESOLUTION can no longer
   be stale.
2. Every wire's visual mesh moved into a new "VisualGroup" child node;
   `Collision` stays a direct, PERMANENTLY FIXED sibling at its one
   authored position, never rotated. `_tween_wire_pitch()`,
   `begin_replace_sequence()`, `animate_install_replacement()`, and
   `sync_full_state()` were all updated to animate/set `VisualGroup`'s
   rotation instead of the wire root's -- the click target can no
   longer be swept through space by any in-flight animation, for any
   wire, under any circumstance.

**Verification**: the original diagnostic (reconnect Yellow, raycast
toward Blue with ZERO frames of delay) now resolves correctly and
reconnects Blue on the very next click. New integration test
`tests/test_reconnect_lifecycle.gd` drives the ENTIRE procedure
through real `InputEventMouseButton` events dispatched to
`_unhandled_input()` (the actual production input path, not a direct
backend call) for both NORMAL and HARD difficulty, covering: wrong
click before Yellow, the core Yellow-then-immediately-Blue sequence,
repeated clicks on already-connected wires, and full completion --
all 20 checks pass for both difficulties.

## B. Shared in-world/focused electrical equipment

**Root cause of the mismatch**: the in-world cabinet's ENTIRE wire
representation was a single flat, undamaged-looking
`CSGCylinder3D` placeholder (`DamagedWireVisual`) toggled visible/
invisible by door-open and wire-replaced state only -- no disconnect/
reconnect granularity, no resemblance to the focused view's three-wire
crossing assembly at all. This was the direct cause of "the focused
minigame doesn't match what I see in the cabinet."

**Architecture**: rather than hand-authoring a second geometry to keep
in sync, `electrical_repair_diorama.tscn` -- the SAME scene the
focused view already uses -- is now instantiated a SECOND time as a
plain child of the world's `EngineeringCabinet1`
(`WorldDiorama`), replacing the old placeholder. A new
`world_display_mode` export (default false, so the focused-view
instance is completely unaffected) frees this instance's own
Camera3D/KeyLight/FillLight (the real world already provides both),
hides its flat photo-backdrop/inset panels (the cabinet's own housing
serves that role), and zeroes every StaticBody3D's collision
layer/mask so none of its wire/screw/breaker hitboxes can ever be hit
by the player's own movement or interaction raycast -- it never calls
`set_active(true)` either, so its `_process()`/`_unhandled_input()`
stay permanently inert regardless. `electrical_panel.gd` gained
`_sync_world_diorama()`, called after every state-mutating method
(`toggle_isolation()`, `disconnect_wire()`, `install_replacement_wire()`,
`reconnect_wire()`, `turn_screw()`, and folded into the existing
`_refresh_interior_visuals()` so the door-toggle/screw-open call sites
get it for free) -- it pushes the SAME 6-argument state tuple
`electrical_repair_view.gd`'s own `_sync_diorama_full()` already
computes into the world twin's `sync_full_state()`. Both views are
driven from the one authoritative panel; neither reads the other.

**A real placement bug found and fixed via rendering, not math**: the
first attempt (instance scaled 0.35x, positioned at the same
z-depth Round 10's flat `Terminal`/`IntactTerminal` nodes used)
rendered as almost entirely BLACK/EMPTY except a sliver of one wire.
Direct inspection of the diorama's own internal coordinates explained
why: its terminals/breaker sit at local z=-0.26 (deep within its own
coordinate space, since that scene was authored to be viewed through
ITS OWN dedicated close-up camera, not embedded as a 3D object).
Placed at the chosen world depth, that content ended up BEHIND the
cabinet housing's own solid front face (nothing in this prototype's
CSG cabinet geometry carves out an actual hollow cavity) -- literally
embedded inside the opaque housing box. Fixed by moving the whole
instance's depth offset forward (and reducing scale to 0.3x) until
even the deepest content (terminals/breaker) clears the housing's
front face with margin -- re-rendering confirmed all three wires,
both terminal indicator lights, and the breaker are now fully visible
and correctly crossing, matching the focused view's own layout
exactly.

## C. Cabinet wall-object investigation and lighting

**C1 -- the "two rectangular wall objects"**: a systematic proximity
search over every `Geometry` node within 2.5m of
`EngineeringCabinet1`, cross-referenced against every script/test
reference to those names, found no orphaned or unexplained objects
immediately adjacent to the cabinet -- the closest actual prop is
`EngineeringCableBundle` (a thin cable run, 0.67m away), and the
nearest panel-like dressing cluster (`EngineeringCabinet2`,
`EngineeringMachineryHousing`, `EngineeringWarningLabel`) sits ~3m
away near a different part of the room; one of those three
(`EngineeringCabinet2`) is already explicitly referenced in
`test_electrical_panel_chain.gd`'s own comments as intentional
"decorative neighbor" dressing from an earlier round, not a bug. Per
the explicit "do not guess, do not delete without evidence"
instruction, nothing was removed or altered based on this
investigation -- see the final report for the full accounting.

**C2 -- lighting**: rendering the open cabinet directly (not inferring
from material values) confirmed the report precisely: the upper and
middle compartments were nearly black, with only a single room-level
`Light_Engineering` omni light (2.4m+ away, ceiling-mounted) providing
any illumination at all, heavily self-shadowed by the cabinet's own
cover geometry. Added three small, short-range `OmniLight3D` fixtures,
one per compartment (`UpperInspectionLight`/`MiddleInspectionLight`/
`LowerInspectionLight`, energy 0.5-0.75, range 0.7-0.75), each a child
of `EngineeringCabinet1` positioned just inside its own compartment's
opening -- restrained enough to only illuminate inside their own
compartment, not flood the room (re-rendered the wider room view to
confirm no change to overall Engineering ambiance). Re-rendering the
middle compartment after this fix shows all three wires, the terminal
lights, and the breaker clearly legible -- a dramatic, directly-
observed improvement over the pre-fix render.

**C3 -- compartment detail**: the three compartments were already
visibly distinct (Round 10-12's covers/hinges/labels/accent trim) and
remain unchanged in structure, dimensions, and floor contact this
round -- the lighting fix alone resolved the player's "appears tiny
and poorly lit" complaint; no further geometry changes were made or
needed.

## D. L07 redesigned: coupled three-chamber pressure calibration

**The new mechanic**: L07 evolved from Round 11's single-chamber
coarse/fine/damping spring puzzle into three COUPLED chambers (A/B/C),
each still a damped spring (`acceleration = RESPONSE_STRENGTH *
(effective_target - reading) - damping * velocity`, Round 11's own
innovation, kept), but each chamber's pull target is no longer its own
setpoint alone -- it is a WEIGHTED BLEND of all three chambers'
setpoints via a fixed 3x3 coupling matrix row. Concretely:
`effective_target[i] = sum_j M[i][j] * setpoint[j]`. Raising chamber
A's regulator therefore visibly, measurably nudges chambers B's and
C's own readings too -- confirmed as real simulated behavior (not a
label) by a dedicated test that raises A alone and asserts B/C's
readings move in the correct direction by a real, non-trivial amount.

**Guaranteed solvability, not merely hoped-for**: every coupling
matrix is ROW-NORMALIZED (each row sums to exactly 1.0) -- this is not
cosmetic. It guarantees the linear system `M * S = T` (S = setpoint
vector, T = the fixed target vector) has a solution whenever M is
invertible, which is verified directly (not assumed) for all three
difficulty matrices by `tests/test_sensor_calibration_coupling.gd`:
`_solve_equilibrium()` (Cramer's rule on the 3x3 system) computes the
actual solution for each matrix, and the test asserts it lands within
the real reachable gauge range [0,100] for every chamber AND satisfies
the original matrix equation exactly (residual check). The one fixed
target vector (A=40, B=58, C=65) is shared across all three
difficulties -- only the coupling matrix, tolerance, and stability
duration vary -- so the puzzle's actual "correct pressures" never
change, only how hard the coupling makes them to isolate by eye.
Solved setpoints for NORMAL: (29.8, 61.2, 68.9); HARD's stronger
coupling pushes the solution further from the targets themselves
((13.0, 71.5, 76.1)) while remaining comfortably in-bounds.

**Controls** (explicitly NOT ten knobs): three chamber regulator knobs
(one per chamber's own setpoint, keyboard fallback 1/2, 3/4, 5/6) plus
ONE SHARED damping knob (Z/X) affecting all three chambers'
convergence uniformly -- four knobs total. A held Shift key is the
"shared fine-adjustment mode" (not three separate fine knobs): it
multiplies whichever regulator is currently being adjusted (keyboard
or knob-drag) down to a slower, more precise rate, directly reusing
Round 11's coarse/fine distinction without tripling the control count.

**Difficulty**: EASY uses a near-diagonal-dominant matrix (weak
cross-chamber influence, diagonal sum 2.54), a wide ±6 tolerance, and
a short 1.0s hold, plus an explicit first-use hint naming the
coupling behavior. NORMAL uses meaningful coupling (diagonal sum
2.05), ±4 tolerance, 1.8s hold, no direct hint. HARD uses strong
coupling (diagonal sum 1.55), ±2.5 tolerance, 2.5s hold, no hints at
all -- verified directly that HARD's matrix is strictly less
diagonal-dominant than NORMAL's, and EASY's strictly more, not merely
asserted by difficulty label. `RESPONSE_STRENGTH` (each chamber's own
fixed physical responsiveness) and the target vector never change by
difficulty, consistent with Round 11's "physics stays constant, only
acceptance criteria change" policy.

**Completion rule**: stable only once ALL THREE chambers are
simultaneously within their own tolerance band, continuously, for the
full required duration -- the stability timer resets to zero the
instant ANY single chamber leaves its band, exactly extending Round
11's single-chamber rule to the coupled system; verified directly that
a plausible real adjustment sequence (set every regulator to its
solved value, raise damping toward critical) reaches completion.

**Presentation**: three chamber panels side by side, each with its own
gauge, a labeled regulator knob below it, a reading/target/direction-
arrow label above it, and a colored IN RANGE / LOW / HIGH status chip.
One shared damping knob sits below all three. Tab switches ALL THREE
chambers' gauges together between circular and cylindrical styles (one
consistent design, never a per-chamber mixed mode) -- both styles
reused directly from Round 11/12's existing `analog_gauge.gd`/
`cylindrical_gauge.gd` scripts, three instances of each, no new gauge
code needed.

**Numeric stability**: verified directly that integrating the same 2.0
simulated seconds via 400 small substeps (dt=0.005) vs. 40 larger ones
(dt=0.05, exactly `MAX_PHYSICS_STEP`) converges to readings within 1.0
unit of each other for every chamber -- the simulation is not
meaningfully frame-rate dependent.

## E. Wristwatch/hand refinement (limited scope, per the explicit lower-priority instruction)

Rendered the current rig directly rather than guessing at
improvements. The overall presentation (strap wrapping the wrist,
detailed case, tapered forearm, readable text) already reads clearly;
the one concrete visual defect found was a hard, angular silhouette
edge where the sleeve cuff's flat cylinder end-cap was visible near
the watch. Lengthened the cuff slightly, enabled `smooth_faces` on it,
and added a small torus ring at its leading edge to round that
transition instead of leaving a flat cut end exposed -- re-rendered
from two angles to confirm the cuff/wrist/strap relationship reads
cleanly. Per the explicit "do not spend most of this round on
anatomical detail," no broader hand rebuild was attempted; the
existing camera-relative rig architecture, world-body isolation,
hold-C animation, and task-display content are all unchanged.

## Files changed

- `scripts/ui/electrical_repair_diorama.gd` -- `_unhandled_input()`
  resolves clicks at the event's own position; wires restructured into
  `VisualGroup` (animated) + fixed `Collision` siblings;
  `world_display_mode` + `_configure_world_display_mode()`.
- `scenes/ui/electrical_repair_diorama.tscn` -- each wire's visual
  mesh moved under a new `VisualGroup` child; `Backdrop` depth
  unchanged from Round 12.
- `tests/test_electrical_repair_diorama.gd`, `tests/test_wire_geometry.gd`
  -- updated for the `VisualGroup`-relative node paths.
- `tests/test_reconnect_lifecycle.gd` (new) -- real-input-event
  integration coverage for the Yellow→Blue bug, NORMAL+HARD.
- `scripts/interactables/electrical_panel.gd` -- `_world_diorama`
  reference; `_sync_world_diorama()`; removed the old
  `_damaged_wire_visual` field/usages.
- `scenes/main.tscn` -- `WorldDiorama` instance replacing
  `DamagedWireVisual`; three new compartment `OmniLight3D` fixtures.
- `tests/test_cabinet_compartments.gd` -- updated for `WorldDiorama`.
- `scripts/ui/sensor_calibration_view.gd` -- full rewrite: three
  coupled chambers, row-normalized difficulty-specific coupling
  matrices, `_solve_equilibrium()`, four-knob control scheme, per-
  chamber status/gauge refresh.
- `scenes/player.tscn` -- `SensorCalibrationView` rebuilt into a
  three-chamber panel layout with a shared damping control.
- `tests/test_sensor_calibration.gd`, `tests/test_sensor_calibration_knob.gd`,
  `tests/test_sensor_calibration_difficulty.gd`, `tests/test_cylindrical_gauge.gd`
  -- rewritten for the three-chamber structure.
- `tests/test_sensor_calibration_coupling.gd` (new) -- solvability,
  influence-direction, and numeric-stability coverage.
- `scenes/player/first_person_watch_rig.tscn` -- sleeve cuff
  lengthened/smoothed, added a rounding torus at its leading edge.

## Known limitations / deferred

- Rendered screenshots were captured for the specific states this
  round needed (the reconnect bug before/after, the cabinet before/
  after lighting, the watch from two angles) -- not an exhaustive
  sweep of every task state/difficulty/look angle. HARD-difficulty
  L07 and the cylindrical gauge style were verified only through
  automated tests this round, not rendered.
- The C1 wall-object investigation could not conclusively match the
  player's exact screenshot framing without the literal image; the
  geometric/test-reference evidence gathered is reported as-is rather
  than guessed further.
- The hand/forearm remains CSG primitives; the Round 13 refinement was
  deliberately small in scope per the brief's own instruction.
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited again this round -- zero new evidence,
  consistent with every prior round).

# ROUND 14: THE REAL RECONNECT BUG, A RECESSED CABINET, SCALABLE CALIBRATION, A FLASHLIGHT, AND VALVE ROUTING

## Scope

Six priorities from a single manual-playtest-driven brief: (0) the
Yellow→Blue electrical reconnect bug was reported as STILL reproducing
in real play despite Round 13's fix and regression tests; (1) the
cabinet's service compartment read as exposed-on-the-face rather than
recessed, and its three inspection lights were too bright/the wrong
color; (2) the focused repair view's cable presentation and the
replacement wire's "stray extra wire" feel; (3) a scalable difficulty
framework for the three-chamber calibration puzzle; (4) a first-pass
flashlight; (5) one new hands-on minigame prototype distinct from the
existing two. Every priority was implemented and verified (headlessly
and, where visual state mattered, via real rendered `--write-movie`
frames) this round; none were deferred.

## A. The Yellow→Blue bug: a second root cause Round 13 did not find

Round 13 fixed one real bug (the collider sweeping through space during
an in-flight animation) by making each wire's `Collision` body a
permanently-fixed sibling of a new `VisualGroup` node that carries the
actual tween. That fix, in isolation, created a SECOND bug: freezing
`Collision` forever meant it only ever matched the CONNECTED pose --
the instant a wire actually disconnected, its visual swung away while
its collider stayed exactly where it started. Measured directly via a
diagnostic: a disconnected wire's visible endpoint sat ~0.6m (world) /
~100px (screen) from its own frozen collider, and a raycast at the
wire's ACTUAL rendered position resolved to nothing. This reproduces
the exact reported sequence (reconnect Yellow, then Blue is rejected)
because by the time Blue is clicked, its collider has been sitting at
the wrong (connected-looking) pose since the moment it was disconnected.

Why Round 13's own regression tests (`test_reconnect_lifecycle.gd`,
`test_reconnect_hitbox_bug.gd`) never caught this: both compute their
click position from `_wire_colliders[role].global_position` -- the
collider's OWN authoritative position. Clicking exactly where the
collider sits will always "work" by construction, regardless of
whether the collider tracks the wire a real player can see. That is a
structural blind spot, not a flaky assertion.

A first attempted fix (snap `Collision.rotation.x` to the same target
angle `VisualGroup` tweens toward, at every transition) did NOT
resolve it: a diagnostic showed the rotation value became numerically
correct, yet a click at the wire's real visual position still missed.
Root cause: `Collision`'s own local position is authored at a fixed
offset `(0, -0.61, 0)` from the wire's anchor (unlike `VisualGroup`,
which sits at the anchor itself) -- rotating `Collision` in place
reorients it around ITS OWN already-displaced origin, it does not
sweep its position through the same arc `VisualGroup`'s rotation
sweeps the visual Cap through (which pivots around the anchor, where
`VisualGroup` actually sits). The real fix (`_snap_collision_to_pose()`
in `electrical_repair_diorama.gd`) explicitly rotates `Collision`'s
rest offset AROUND THE WIRE ROOT'S ORIGIN -- the same pivot
`VisualGroup` uses -- and assigns the result as `Collision.position`,
still snapping instantly (never tweening) so Round 13's actual fix (no
collider ever sweeps through space mid-animation) is preserved.

A second, more subtle issue surfaced once the collider actually tracked
the visual: Godot's physics server does not make a `StaticBody3D`'s
new transform visible to `intersect_ray()` until its NEXT physics step
-- confirmed directly via diagnostic (an immediate re-raycast at a
just-moved collider's own position missed; the same raycast one
`physics_frame` later hit). This is a real engine constraint, not
specific to this fix, and it never mattered before because Collision
never moved. It only affects two pre-existing tests that deliberately
fire several complete mouse clicks with literally zero frames between
them (an artificial stress pattern no human input can produce for
genuinely separate clicks); both were updated to `await physics_frame`
between separate clicks (not within one click's own down/up pair,
which is where the ORIGINAL Round 13 hover-cache bug actually lived) --
this does not weaken their coverage of the reported bug, it removes an
assumption (zero-frame gap between two separate completed clicks) nothing
in reality can satisfy.

New regression test: `tests/test_reconnect_visual_position.gd` computes
every click position from each wire's real `VisualGroup/Cap` global
position (never a collider), reproducing the exact reported sequence
(disconnect all three, replace, reconnect Yellow, IMMEDIATELY reconnect
Blue at Blue's own real visual position) through the genuine
`_unhandled_input()` path, for both NORMAL and HARD, plus indicator-
light sync checks after each reconnect. Verified both headlessly (all
PASS) and visually: a rendered `--write-movie` sequence driving the
exact reported click sequence through real `InputEventMouseButton`
events shows Blue correctly lit/reconnected immediately after Yellow.

## B. A genuinely recessed cabinet, dimmer fault-colored lighting, and real pipes

Rendered screenshots of the CLOSED cabinet showed the full wire/
terminal assembly already fully visible and overlapping the cabinet's
own surface details, with no visible difference between the open and
closed states -- confirmed by two root causes, both now fixed:

1. `WorldDiorama`'s own `visible` property was never toggled by
   `_door_open` at all (only the thin `AccessHatchCover` plate was).
   `electrical_panel.gd`'s `_refresh_interior_visuals()` now sets
   `_world_diorama.visible = _door_open`.
2. `WorldDiorama` was positioned at local z=0.29 inside the cabinet --
   PAST both the cover's own z=0.151 and the cabinet's front face at
   z=0.15 -- so the wire assembly rendered floating in front of the
   cabinet's own surface, in front of where a cover could ever occlude
   it. A new `ServiceBayCavity` CSG-subtraction box now carves a real
   recessed opening into the cabinet's own solid body (punching through
   the front face, stopping short of the back face so real material
   remains behind it), and `WorldDiorama` was repositioned to z=0.11
   (measured via diagnostic so the wire assembly's own content, which
   sits at a further -0.078 internal offset, lands at roughly z=0.03 --
   comfortably inside the new cavity, not clipped into its back wall).

Mid-fix pitfall worth recording: `.tscn` (Godot's resource-text format)
does NOT support `##`/`#`-prefixed comment lines the way `.gd` files
do -- adding doc-comment blocks directly above new `[node]` declarations
in `main.tscn` silently broke those specific nodes' registration
(`get_node("WorldDiorama")` returned "not found" at runtime, with no
parse error printed). Confirmed by stripping the comments and re-
testing; `main.tscn` carries no inline comments anywhere else in this
project for exactly this reason, and none were reintroduced.

The three `OmniLight3D` compartment lights were dimmed and recolored
from a bright warm-white (`energy` 0.5-0.75, near-white) to a
restrained red-amber (`Color(0.88, 0.4, 0.16)`, `energy` 0.35-0.48) --
an initial, more aggressive dim (`energy` 0.16-0.22) was tried first
and rendered the wires nearly unreadable against the recessed cavity's
own dark walls, which would have worked against Priority 1's own
"wires/terminals inside it must be clearly visible" requirement; the
final values keep the fault-lamp feel while keeping the repair content
legible (verified via rendered screenshot, both closed and open).
`WorldDiorama`'s own `KeyLight`/`FillLight` (part of the shared diorama
scene, unaffected by the cabinet's room lights) remain the dominant,
neutral-to-cool light source for actual wire-color readability in both
the world and focused views.

Wall-geometry investigation: `EngineeringConduitPipe1`/`2` were plain
`CSGBox3D` slabs (size e.g. `3.0 x 0.1 x 0.1`) standing in for pipes --
a thin flat rectangular prism does not read as a pipe, it reads as an
unexplained flat bar near the ceiling (plausibly the player's
"ambiguous rectangular wall geometries"). Converted to real
`CSGCylinder3D` pipes at the same routes/positions.

Replacement-wire "stray extra wire" feel: the staged replacement wire
previously hung at the exact same -58° angle a torn-loose DAMAGED wire
uses, with no visual distinction between "debris" and "a spare ready to
install." A new, shallower `REPLACEMENT_STAGED_PITCH_DEGREES` (-20°,
vs. -58° for genuinely disconnected wires) gives it a distinct resting
presentation.

## C. Focused repair view: largely already satisfied

Re-reading `electrical_repair_view.gd`/`electrical_repair_diorama.gd`
found that most of Priority 2's explicit asks were already implemented
in prior rounds and did not need rework this round: wires visibly
cross/overlap (confirmed by `test_wire_geometry.gd`'s own "genuinely
overlap in world X" assertions); disconnected wires already visibly
swing/hang loose (Round 11-13); and a hinted next-step wire already
PULSES (`set_pulsing_hint()`/`_apply_pulse()`), with the controls label
explicitly reading "Glowing wire shows the next step" -- i.e., the
"visually prominent current step, reduce text dependency" requirement
was already met by a prior round's own work, not newly added here. The
one genuinely outstanding item (the replacement wire's resting pose)
is covered in Section B above. No drag-and-drop rewrite was attempted,
per the brief's own caution.

## D. Scalable calibration difficulty framework

`sensor_calibration_view.gd`'s three-chamber coupled simulation,
coupling matrices, equilibrium solver, and win condition are UNCHANGED.
The progression model is implemented as HOW MANY chambers start
genuinely faulty (away from their own target): EASY=1, NORMAL=2,
HARD=3 (identical to every prior round's behavior, so the most-tested
path is untouched) -- a chamber not in this difficulty's active set
simply starts already AT its own target. Because each chamber's status
chip already shows its OWN current reading vs. target ("LOW"/"HIGH"/
"IN RANGE"), this makes "which chambers need attention" visually
obvious from frame one with no new UI state, satisfying "clearly show
which chambers are active" for free. Verified visually via rendered
screenshot (EASY shows Chamber A "HIGH", B/C already "IN RANGE") and
via new/extended assertions in `tests/test_sensor_calibration.gd` and
`tests/test_sensor_calibration_difficulty.gd`.

Documented, not implemented (per the brief's own "even if not fully
shipped" allowance): `_step_springs()` and the win-check loop already
iterate generically over `CHAMBERS.size()`, so 4-6 chamber expansion
needs no changes there; `_solve_equilibrium()`'s hand-expanded 3x3
Cramer's-rule determinant is the one piece NOT yet N-agnostic, and
would need generalizing to NxN before a verification test could
confirm a larger matrix's equilibrium the same way. Flagged in the
script's own doc comment so a future round does not rediscover this by
trial and error.

## E. First-pass flashlight

A `SpotLight3D` fixed to the player's own camera (`Flashlight` node,
`scripts/player/flashlight_controller.gd`), toggled with a plain KEY_L
poll -- this project has no `InputMap` actions anywhere (every other
control, e.g. calibration's KEY_1-6, polls raw keycodes the same way),
so this follows the same established convention rather than
introducing a new input system. A believable, fairly narrow
technician's worklight (26° cone, range 7.0, warm-white, shadows
enabled) rather than a wide horror-shooter floodlight -- verified via a
rendered frame in a dim corridor showing a well-defined hotspot with
natural falloff, not a wash. The beam hides (state preserved, not
reset) while a focused session (`FocusedInteractionState.is_active()`)
is active, mirroring that system's own "exclusive control" contract;
pressing the toggle key while focused is also ignored outright, so a
stray press cannot leave the beam in a surprising state once the
session ends. No battery/charge/power-drain system, per the brief's own
scope limit.

## F. New prototype: Coolant Loop Valve Routing (L08)

Chosen candidate, and why (documented per the brief's explicit "choose
the safest most architecture-consistent option and document why"): a
small discrete ROUTING/LOGIC puzzle -- three toggle valves on a fixed
schematic (INLET→V1→JUNCTION, JUNCTION→V2→OUTLET,
JUNCTION→V3→DRAIN) where the player must find the one configuration
that reaches OUTLET while keeping DRAIN sealed. This is genuinely
different in KIND from both existing minigames (electrical repair is a
sequenced click-order puzzle; calibration is continuous spring
convergence; this is discrete branching logic), while reusing only
already-proven architecture: `FocusedInteractionState`'s begin()/
on_focus_exit()/cancel_requested() contract (identical to both existing
focused views), a plain duck-typed interactable
(interact()/get_interact_prompt()/is_complete()/mark_complete(),
identical to `sensor_calibration_station.gd`), and clickable-Panel
`gui_input` toggles (the same pattern calibration's knobs already use)
-- with NO new 3D diorama/SubViewport/raycast layer, which is exactly
where this round's Priority 0 bug lived. Candidates like breaker/
isolation or filter/canister seating would have mostly re-skinned the
electrical repair's own click-sequence mechanic instead.

Fixed puzzle instance (same policy as both existing minigames): V3
(the drain) starts OPEN and V1/V2 start SHUT -- a deliberate trap,
real work required, not randomized. New task `l08_status` in
`day_plan.gd`, free-standing/independent of the Slice A/B chain,
identical in that respect to L07. New prop `ValveRoutingStation`
(`scenes/interactables/valve_routing_station.tscn`) placed in the Life
Support room. Its first placement (east-of-centre, near the
`LifeSupportB` movement node) introduced two NEW navigation-sweep
regressions (`life_support_a <-> life_support_b`,
`storage_life_support_link <-> life_support_b`) beyond the 5 known
baseline failures -- caught by `tests/test_station_capsule_sweep.gd`
and fixed by relocating the prop to the room's east wall, clear of both
nodes' sweep paths; re-verified clean (0 new regressions, same 5 known
ones). A rotation-direction mistake (the prop initially faced INTO the
wall, confirmed via a rendered screenshot showing its mirrored/backside
label text) was caught the same way and fixed by verifying the node's
actual `global_transform.basis.z` directly via diagnostic rather than
continuing to hand-derive the rotation matrix.

## Files changed

- `scripts/ui/electrical_repair_diorama.gd` -- `_snap_collision_to_pose()`
  (new); `_tween_wire_pitch()`, `begin_replace_sequence()`,
  `animate_install_replacement()`, `sync_full_state()` updated to call
  it; `REPLACEMENT_STAGED_PITCH_DEGREES` (new).
- `tests/test_reconnect_visual_position.gd` (new) -- clicks at each
  wire's real VISUAL position, not its collider's.
- `tests/test_reconnect_lifecycle.gd`, `tests/test_reconnect_hitbox_bug.gd`
  -- `await physics_frame` between separate completed clicks (physics-
  server transform-visibility latency, not a logic change).
- `scenes/main.tscn` -- `ServiceBayCavity` (new, CSG subtraction);
  `WorldDiorama` repositioned; three `OmniLight3D` fixtures dimmed/
  recolored; `EngineeringConduitPipe1`/`2` converted to
  `CSGCylinder3D`; `ValveRoutingStation` instance (new); `Flashlight`
  override (new); `ValveRoutingView` override (new).
- `scripts/interactables/electrical_panel.gd` -- `_world_diorama.visible
  = _door_open` in `_refresh_interior_visuals()`.
- `scripts/ui/sensor_calibration_view.gd` -- `_ACTIVE_FAULT_COUNT_BY_DIFFICULTY`
  (new); `open_station()` starts non-active chambers already at target;
  `_active_fault_count`; status text reflects how many chambers need
  attention.
- `tests/test_sensor_calibration.gd`, `tests/test_sensor_calibration_difficulty.gd`
  -- updated/extended for the active-fault-count progression.
- `scripts/player/flashlight_controller.gd` (new); `scenes/player.tscn`
  -- `Flashlight`/`SpotLight3D` nodes (new).
- `tests/test_flashlight.gd` (new).
- `scripts/ui/valve_routing_view.gd`, `scripts/interactables/valve_routing_station.gd`
  (new); `scenes/interactables/valve_routing_station.tscn` (new);
  `scenes/player.tscn` -- `ValveRoutingView` (new).
- `scripts/station/day_plan.gd` -- `l08_status` (new), wired into
  `is_task_done()`/`mark_done()`/`reset_for_new_day()`.
- `tests/test_valve_routing.gd` (new).
- `tests/run_tests.sh` -- registers the three new test files.

## Known limitations / deferred

- `_solve_equilibrium()`'s 3x3-specific Cramer's-rule solver was not
  generalized to NxN this round (see Section D) -- a real, documented
  seam for a future 4-6 chamber expansion, not a bug.
- The flashlight has no battery/charge/power-drain system and no
  dedicated HUD indicator beyond the beam itself, per the brief's own
  scope limit.
- Visual verification this round covered the specific states each
  priority needed (the reconnect sequence, the cabinet open/closed, the
  EASY-difficulty calibration start, the flashlight beam, the valve
  station's facing/schematic) via rendered `--write-movie` frames --
  not an exhaustive sweep of every difficulty/state/angle combination
  (e.g. the cabinet's HARD-difficulty screw-removal flow, or the valve
  station under actual room lighting with the new flashlight on, were
  not separately rendered).
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited again this round -- zero new evidence,
  consistent with every prior round).

# ROUND 15: MAINTENANCE GAMEPLAY EXPANSION AND INTERACTION RELIABILITY

## Scope

Seven priorities plus a screenshot-driven addendum: (0) permanently
resolve the recurring Yellow→Blue electrical-reconnect report; (1)
integrate the replacement wire into the physical repair so exactly 3
wires are ever visible; (2) redesign Coolant Loop Valve Routing (L08)
as a real 3D mechanical manifold, not a flat schematic (the Round 14
version); (2-addendum) a second pass on that same manifold against the
player's own screenshot evidence of a still-dark, still-tiny-feeling
interface; (3) a mechanically distinct hand-pumped flashlight on HARD
only; (4) a new physical filter-cartridge task (L02); (5) a new
evidence-based circuit-tracing diagnostic (E09); (6) confirm the five
maintenance activities are genuinely distinct and document the
difficulty-vs-progression relationship honestly; (7) full regression
and rendered verification; (8) this entry. No commits or pushes were
made; `.claude/settings.local.json` was not touched; all pre-existing
uncommitted work was preserved throughout.

## A. The Yellow→Blue reconnect report: root cause and why it is now fixed

Tracing the full production path (raycast → collider identity →
animation phase → visual wire state → indicator lights) against the
Round 14 fix found that the Round 14 collider-tracking fix itself was
already correct -- confirmed by pacing a genuine top-level
`get_root().push_input()` click sequence (the real
`SubViewportContainer`-forwarding path, only exercisable under
`--write-movie` real rendering, not plain `--headless`) through
disconnect → replace → reconnect Yellow → Blue → Red with proper
`await physics_frame` spacing between separate clicks. Two of my own
scratch diagnostics initially appeared to reproduce the bug; both were
traced to missing physics-frame pacing in the diagnostic itself (the
same physics-server transform-sync latency documented in Round 14),
not a real app defect.

What WAS found and fixed: the Return, Service, and Breaker terminal
indicator lights all shared one `Mat_light_on` `SubResource`, with only
Supply ever getting a visually-independent material from the original
build. Toggling any one indicator silently changed the ON-color of the
other three, which is indistinguishable from "my connection didn't
register" if the player is watching the wrong light flicker. This is
the most plausible explanation for continued player reports after a
logic fix that real-input-driven testing now confirms is correct: the
underlying state transitions were right, but the UI could visibly lie
about which terminal just changed. Fixed by giving Return, Service, and
Breaker their own separate `SubResource` materials (`Mat_light_on_return`
/`_service`/`_breaker`).

Transaction model (now made explicit, matching the brief's "choose one,
document it" requirement): this project uses **commit-then-animate**
-- `electrical_panel.gd`'s terminal click handler commits the logical
state change synchronously on a valid click, then kicks off the visual
tween; a second click during that tween targets whatever the NOW-
current logical state is (never replays the prior action), and
`_snap_collision_to_pose()` (Round 14) keeps the physics collider
aligned with the committed pose, not the mid-tween visual pose, so a
rapid second click's raycast can never land on a stale position.

New coverage added to `tests/test_reconnect_visual_position.gd`: a
wrong-click-during-Yellow's-tween-animation check (must not be
accepted, must not advance state), and a full Escape/reentry round
trip (`FocusedInteractionState.end()` then re-`interact()`) that checks
`reconnected_roles()`, `procedure_stage()`, AND
`_indicator_is_on(diorama, &"return")` together -- this last check is
the one that actually caught the shared-material bug (it failed before
the fix, passes after), which a check of logical state alone would
have missed entirely. `tests/manual_verify_real_input_reconnect.gd`
is a new PERMANENT (not run by `run_tests.sh`) artifact using genuine
top-level `push_input()` clicks; it is explicitly documented as
requiring `--write-movie` real rendering, since plain `--headless`
silently no-ops that input path -- a genuine, explicitly-stated
limitation of this project's headless test environment, not a gap this
round tried to paper over.

**Do not call this fixed on unit tests alone**: the claim above rests
on (1) logic tests, (2) the real top-level-input-forwarded manual
artifact run under actual GPU rendering, and (3) the indicator-light
fix being independently necessary regardless of whether the underlying
bug reproduces, because a correct-but-illegibly-lit UI produces the
exact symptom the player reported either way.

## B. Replacement wire integration (16-gauge, yellow)

The player's screenshot showed what read as a 4th, oddly-colored spare
wire coiled to one side. Root cause: `wire_component.tscn`'s insulation
material was still blue (`Color(0.13, 0.32, 0.72, 1)`) from before the
electrical-repair diorama's wires were themed yellow, and 7 occurrences
of "16-gauge, blue" remained in UI/task text across
`workstation_screen.gd`, `wire_component.gd`, `electrical_panel.gd`,
and `day_plan.gd`. Fixed by matching the spare's insulation color
exactly to `Mat_wire_service_healthy`'s yellow and correcting every
text reference. The diorama's own storage-holder → installed-position
handoff, empty-vs-occupied terminal visibility, and exactly-3-wires-
during-reconnection behavior were already correct from Round 14's
`begin_replace_sequence()`/`animate_install_replacement()` work; this
round's fix was specifically the color/label mismatch that made the
correctly-behaving spare LOOK like a foreign 4th wire.
`tests/test_electrical_panel_chain.gd` now asserts the carried wire's
material color equals the diorama's installed-replacement color
directly (not just by eye).

## C. Valve routing redesigned as a physical 3D manifold (L08)

**Why the Round 14 version rendered as "a tiny schematic over an
almost-black box"**: there was no 3D content for valve routing at all.
The focused view was a flat 2D `Control` panel of `ColorRect`s over a
0.72-alpha translucent background, so what the player saw behind the
small diagram was the dim, unlit 3D WORLD rendering straight through
that translucent layer -- not equipment, just the corridor behind the
UI. This was a layout/content problem, not a lighting problem, and
needed a real 3D scene, not a brighter light or more emissive paint.

Built `scenes/ui/valve_routing_diorama.tscn` /
`scripts/ui/valve_routing_diorama.gd`: a real cylindrical-pipe manifold
(inlet, branch junction, outlet, drain, elbow fittings, mounting
brackets) with three ball valves (V1 inlet shutoff, V2 outlet, V3
drain), each with a distinct handle that physically rotates about its
own axis between a pipe-aligned (open) and perpendicular (closed) pose,
a small pressure gauge whose needle respond to live outlet flow, and
short INLET/OUTLET/DRAIN labels. `valve_routing_station.gd` owns the
authoritative `{1,2,3}→bool` open-state and flow computation
(`v1_live`, `outlet_live = v1_live and v2_open`, `drain_live = v1_live
and v3_open`); the diorama only animates and recolors pipe segments
(teal pulse = live coolant, amber/red pulse = flow reaching the drain,
flat gunmetal = dead) in response. The puzzle requires a real decision,
not "open everything": V3 (drain) starts OPEN and V2 (outlet) starts
CLOSED, so a naive "turn on the inlet" first routes coolant to the
drain with a visible amber warning pulse rather than silently failing
or instantly failing the task; the correct solution (V1 open, V2 open,
V3 closed) is reachable by observation and is fully reversible at every
step. The 2D schematic from Round 14 was demoted to a Tab-toggleable
overlay that reads the exact same station state as the manifold --
never a second source of truth.

**Addendum fixes, driven by the player's own screenshot**: the real
3D manifold initially still rendered dim and small within its own
panel. Three concrete fixes, each addressing a specific found cause
rather than blanket-brightening: (1) the focused view's panel anchors
were widened to match `ElectricalRepairView`'s established ~94%-of-
screen convention instead of a smaller fixed box; (2) a genuine camera-
hijacking bug was found and fixed (below) that was intermittently
letting the WORLD-embedded copy's own camera steal the main viewport
entirely, which can present as "the view looks wrong/dark" depending
on exactly when the station entered the tree; (3) `Mat_pipe_v2_outlet`
was discovered shared between two visually-independent pipe segments
(`SegJunctionV2` and `SegV2Outlet`), recoloring both whenever either
should have changed -- split into its own `Mat_pipe_v2_outlet_seg`
resource, and all six pipe materials plus three handle materials were
additionally marked `resource_local_to_scene = true` as defense in
depth against the same bug class recurring.

**Camera-hijacking bug (found here, fixed project-wide)**: a plain
`Camera3D` placed directly in the main 3D world, with no other camera
having ever explicitly claimed `current = true`, can silently auto-
promote itself to the main window's active camera. The project's own
player camera (`interaction_controller.gd`) had never claimed
`current = true`, relying entirely on fragile auto-promotion order --
invisible until a new world-embedded diorama camera was added and
sometimes won that race. Fixed two ways, confirmed each necessary
independently: `interaction_controller.gd._ready()` now explicitly sets
`current = true` first thing (robust against any future world-embedded
camera), AND the world-display diorama instance's own
camera/`KeyLight`/`FillLight`/`RimLight` are `queue_free()`'d entirely
in `world_display_mode` (merely setting `current = false` on the
leftover camera was tested and found insufficient by itself).

A second, unrelated bug was found and fixed in the same pass: the
valve collision shapes (`Shape_valve`/`Shape_bracket`) were sized to
roughly the handle's own resting footprint, not its full rotation
sweep, and `valve_screen_position()` computed click targets from the
rotating `HandleRoot` rather than the stable valve body -- together
these made a valve intermittently un-clickable depending on its current
open/closed pose. Fixed by enlarging the collision shapes to
`(0.32, 0.32, 0.22)` and switching both the raycast target and
`valve_screen_position()`/`click_position()` to the valve body's own
stable origin.

`tests/test_valve_routing.gd` was rewritten to dispatch through real
diorama clicks (`await physics_frame` after each), check flow state
after each toggle, confirm world/focused handle-rotation sync (waiting
~0.4s for the focused tween to settle before comparing against the
world twin's instant snap), and confirm re-click-after-completion and
reopen-after-completion are both no-ops.

## D. Mechanical hand-pumped flashlight (HARD only)

EASY/NORMAL behavior is completely unchanged (L toggles on/off). On
HARD, `flashlight_controller.gd` was rewritten so each fresh,
non-repeat `L` key-DOWN event (`not event.echo`, Godot's own OS-auto-
repeat flag -- the actual mechanism, not a debounce timer, that stops a
held key from generating unlimited energy) adds a bounded amount of
stored charge (`PUMP_GAIN = 0.22`, capped at `MAX_CHARGE = 1.0`);
charge decays continuously (`DECAY_PER_SEC = 0.045`) and brightness is
a smooth, frame-rate-independent function of stored charge (never a
binary on/off); a held key additionally trickle-charges at a much
slower rate (`HOLD_GAIN_PER_SEC = 0.09`) as an accessible alternative
to rapid tapping, gated the same `not event.echo` way so OS auto-repeat
cannot spoof it. The flashlight is explicitly gated out while any
focused minigame is active and restores coherently on return: EASY/
NORMAL restore on/off state as before; HARD restores the stored-charge
value subject to the same ongoing decay, never resetting to full or
zero on reentry. `_handle_difficulty_transition()` converts state
cleanly in both directions on a live difficulty change (NORMAL↔HARD),
confirmed to never leave the light stuck on, grant free charge, or
produce an unexpected dark screen.

`tests/test_flashlight_hard_mode.gd` (new) covers: NORMAL toggle
unchanged; HARD pump gain, OS-echo rejection, hold-trickle, decay,
charge bounds; focused-session input gating; both directions of live
difficulty switching; repeated sessions. Verified visually via
`--write-movie` in a dark corridor (beam brightness visibly tracks a
sequence of real key-down pumps, with smooth decay between them, no
binary pop).

## E. Filter cartridge replacement (L02)

Cross-checked against `GAME_DESIGN.md`'s own Task Database before
building anything: L02 Filter Replacement is a real, previously-
unimplemented catalog entry whose documented procedure (isolate airflow
→ release latches → remove old → match/align → install → re-latch →
restore → verify) matches this priority's ask exactly, so no new or
repurposed task ID was needed.

`filter_housing_station.gd` is a 7-stage state machine (ISOLATE →
OPEN_LATCHES → REMOVE_OLD → ALIGN_INSERT → CLOSE_LATCHES → RESTORE →
COMPLETE) built around the one mechanic genuinely distinct from every
other task here: ALIGNMENT AND INSERTION. The new cartridge must be
rotated (click-to-rotate in 45° steps) until its tab lines up with the
housing's own fixed keyway mark within a difficulty-scaled tolerance
(EASY 40°, NORMAL 20°, HARD 8°, with EASY additionally showing a text
guide to the mark's location) before `[Enter]` can seat it. An insert
attempted at the wrong rotation visibly bumps and rejects
(`animate_insert_fail()`) rather than silently doing nothing or
destroying progress -- the stage does not advance and the attempt can
simply be retried after rotating further.

Two bugs were found and fixed during this build, both the same shared-
material/stale-formula class as Section C: (1) `sync_full_state()`'s
valve-color formula didn't match the station's own `is_isolated()`
(it excluded `COMPLETE` incorrectly), showing the wrong color at
startup; (2) the two latches shared one `Mat_latch_closed` resource,
which combined with bug (1) being re-applied on every
`_sync_world_diorama()` call made the FOCUSED view's valve handle
visibly flip color after any unrelated latch or cartridge click, even
though the focused view itself never touched the valve. Fixed by
correcting the formula to match `is_isolated()` exactly and giving each
latch its own `resource_local_to_scene = true` material.

Initial placement at `(-4.3, 1.6, 10.1)` collided with the
`storage_elbow_ls↔storage_life_support_link` and
`storage_life_support_link↔life_support_b` nav edges; relocated to
`(-1.7, 1.6, 10.0)` on the same east wall as the valve station
(different Z), re-confirmed via the capsule sweep at exactly the
pre-existing 5-failure baseline with 0 new regressions.

`tests/test_filter_housing.gd` drives the full 7-stage procedure via
real diorama clicks, asserts latch-material independence directly by
object identity, confirms a wrong-rotation insert fails harmlessly and
is recoverable, confirms world/focused sync, and confirms reopen-
after-completion shows COMPLETE immediately.

## F. Circuit-tracing diagnostic (E09)

Considered and explicitly rejected building this onto E02 Trace
Electrical Circuit, even though E02 is the catalog-correct thematic
match: E02's existing single-click completion is load-bearing across
Slice B's tested dependency chain (S01's component check, E05's
install gate, the workstation diagnostic screen, and several passing
tests that call `terminal_interact(&"damaged")` twice and immediately
assert `e02` done). Changing it would risk exactly the "invalidate
completed work / duplicate completion events" outcome the brief rules
out. **E09 Diagnose Intermittent Electrical Fault** is a second real,
previously-unimplemented catalog entry with no dependency chain of its
own, so it was built there instead -- the safer AND still catalog-
correct choice; `day_plan.gd` documents this reasoning inline.

The mechanic is evidence-based deduction, distinct from every other
task here: a fixed linear circuit `POWER → TP1 → TP2 → TP3 → TP4` with
exactly one, never-moving fault always at segment TP2–TP3 (TP1/TP2
read NOMINAL/12.0V; TP3/TP4 read DEAD/0.0V, internally consistent with
that one fault location in every difficulty). Clicking a TEST POINT
physically moves a probe prop to it and updates a readable display
(`circuit_tracer_diorama.gd`'s `animate_probe_to()`); clicking a WIRE
SEGMENT submits it as a diagnosis guess. Wrong guesses are harmless and
informative -- the view surfaces "`<segment>` reads consistent — fault
lies elsewhere" without resetting any progress or moving the fault --
and the correct guess (TP2–TP3) completes E09. Difficulty changes only
the reading's PRESENTATION, never the circuit: EASY/NORMAL show a
numeric voltage and EASY additionally keeps a running on-screen log of
every point tested; HARD shows only a qualitative "NO SIGNAL"/
"CONTINUITY OK", asking for a little more inference from less precise
evidence rather than a stricter tolerance (there is no tolerance here
to tighten).

One bug specific to this task was found and fixed before it ever
shipped: four test-point "Body" meshes initially shared one
`Mat_tp_body` `SubResource` (the same shared-material class as Sections
A/C/E, caught this time during authoring rather than after rendering)
-- recoloring TP3 as "tested" would have recolored TP1/TP2/TP4 too.
Given four separate `resource_local_to_scene = true` materials before
first test run. A second, subtler issue: the world-display twin never
receives the focused view's own `animate_probe_to()` calls, so
`sync_full_state()` was changed to take the station's full
`tested_points()` array explicitly (not just the current probe
location) -- without this the world twin would have shown only the
single most-recently-probed point as tested every time it resynced,
silently losing the rest of the player's test history from the world
view (confirmed by a dedicated check in the test file that all four
points show as tested on the world twin after all four are probed in
the focused view).

Placed at `(-2.75, 1.6, 4.3)` on Engineering's east wall (same solid
wall segment as the existing `LooseConnection` prop, 0.7m further from
it than their closest approach, well clear of all three of
Engineering's door gaps); the capsule sweep confirms 0 new regressions
at the same 5-failure baseline. `tests/test_circuit_tracer.gd` (new,
32 checks) covers: all four readings matching the fixed topology; three
separate wrong guesses being harmless and leaving progress untouched;
the correct guess completing the task; the world twin's FULL tested-
point history (not just current probe); reopen-after-completion;
post-completion clicks on both test points and segments being no-ops;
and difficulty-only-changes-presentation in both directions.

Real-rendered verification (`--write-movie`): the initial state (power
source, four test points and labels, "PROBE A TEST POINT" display, no
probe visible yet); after probing a dead point (TP3 highlighted teal,
probe prop visibly moved to it, display reading "0.0 V — NO SIGNAL");
and the correctly-identified-fault state (TP2 and TP3 both teal,
display reading "FAULT ISOLATED: TP2—TP3", status "FAULT ISOLATED —
BENCH NOMINAL"). One cosmetic issue was found and fixed from the first
render: the probe prop's resting offset slightly overlapped the TP3
text label; nudged from `Vector3(0, -0.22, 0.14)` to
`Vector3(0, -0.3, 0.2)` and re-rendered to confirm the overlap is gone.
A render of the world-embedded twin (from the player's position in
Engineering, prompt correctly reading "Click: Diagnose Intermittent
Fault", confirming no camera-hijack regression) shows it rendering
dim/low-contrast at its small world scale -- directly compared against
an equivalent render of the already-shipped `FilterHousingStation`
world twin from this same round, which is equally dim. This is the
established, already-accepted convention for small world-embedded
decorative props in this game (distant equipment reads dim under this
game's corridor lighting, same as the player's own screenshot
complaint was specifically about the FOCUSED interactive view, which
is confirmed bright and legible here) -- not a new defect, and not
"fixed" by this round since doing so would inconsistently diverge this
one station from its two just-shipped siblings.

## G. Progression and gameplay variety

The five maintenance activities now use genuinely different controls
and presentation, not reused-for-convenience sameness: electrical
repair (E01/E02/E05) is click-sequence memory across physical
terminals; sensor calibration (L07) is coupled real-time pressure
balancing across three chambers; valve routing (L08) is spatial flow
reasoning via rotating physical valve handles; filter replacement (L02)
is rotational alignment and insertion; circuit tracing (E09) is
evidence-based deduction via probe placement and segment diagnosis.
Each is reachable the same way every other task here is: the
workstation's own prompt/work-order text, the wristwatch, and an
in-room interaction prompt on the physical prop itself -- no floating
world-space labels or paragraph-length instructions were added.

**Honest documentation of a known conflation** (per the brief's own
"do not confuse the two, or at least honestly document it" allowance):
Round 14's sensor-calibration fault-count progression
(`_ACTIVE_FAULT_COUNT_BY_DIFFICULTY` in `sensor_calibration_view.gd`)
keys the number of simultaneously-faulted chambers directly off
`GameSettings.get_difficulty()`, not off an independent progression
variable. This means, as implemented, "how many chambers are wrong"
and "how forgiving the global difficulty is" are NOT actually separate
dimensions for L07 specifically, even though the brief asks for them to
be -- EASY/NORMAL/HARD each currently imply both a fixed guidance level
AND a fixed fault count together. None of this round's four
new/redesigned tasks (valve routing, flashlight, filter, circuit
tracing) introduce a second instance of this same conflation: each has
exactly one, non-difficulty-scaled puzzle instance, with only its
guidance/tolerance/presentation varying by difficulty. Correcting L07's
existing conflation into a genuinely separate progression axis was not
attempted this round -- it is pre-existing Round 14 behavior, not
something newly introduced, and reworking it carries its own regression
risk against `test_sensor_calibration_difficulty.gd`'s current
assumptions that this round's scope did not call for touching.

## Files changed

- `scenes/ui/electrical_repair_diorama.tscn` -- 3 new indicator-light
  `SubResource` materials (`Mat_light_on_return`/`_service`/`_breaker`),
  repointed from the one shared `Mat_light_on`.
- `tests/test_reconnect_visual_position.gd` -- wrong-click-during-
  animation and Escape/reentry-with-indicator-check coverage (new).
- `tests/manual_verify_real_input_reconnect.gd` (new, permanent,
  intentionally NOT in `run_tests.sh` -- requires `--write-movie`).
- `scenes/interactables/wire_component.tscn` -- insulation color
  blue→yellow.
- `scripts/ui/workstation_screen.gd`, `scripts/interactables/wire_component.gd`,
  `scripts/interactables/electrical_panel.gd`, `scripts/station/day_plan.gd`
  -- "16-gauge, blue" → "16-gauge, yellow" (7 occurrences).
- `tests/test_electrical_panel_chain.gd` -- wire/diorama color-match
  assertion (new).
- `scenes/ui/valve_routing_diorama.tscn`, `scripts/ui/valve_routing_diorama.gd`
  (both new) -- the 3D manifold replacing Round 14's flat schematic.
- `scripts/interactables/valve_routing_station.gd` (rewritten) --
  owns `_open{1,2,3}`, `toggle_valve()`, `flow_state()`.
- `scripts/ui/valve_routing_view.gd` (rewritten) -- diorama embedding,
  Tab-toggleable schematic reading the same station state.
- `scenes/interactables/valve_routing_station.tscn` (rewritten) --
  collision + `WorldDiorama` twin, old decorative geometry removed.
- `scenes/player.tscn` -- `ValveRoutingView` node tree replaced
  (SubViewportContainer diorama embed + schematic overlay);
  `FilterHousingView`, `CircuitTracerView` node trees added (new).
- `scripts/player/interaction_controller.gd` -- explicit
  `current = true` in `_ready()` (camera-hijack fix).
- `tests/test_valve_routing.gd` (rewritten) -- real diorama clicks,
  flow-state checks, world/focused rotation sync.
- `scripts/player/flashlight_controller.gd` (rewritten) -- HARD pump/
  hold/decay mechanics, echo rejection, difficulty-transition handling.
- `tests/test_flashlight_hard_mode.gd` (new).
- `scripts/station/day_plan.gd` -- `l02_status`, `e09_status` (new),
  wired into `is_task_done()`/`mark_done()`/`reset_for_new_day()`.
- `scripts/interactables/filter_housing_station.gd`,
  `scripts/ui/filter_housing_diorama.gd`, `scripts/ui/filter_housing_view.gd`,
  `scenes/ui/filter_housing_diorama.tscn`,
  `scenes/interactables/filter_housing_station.tscn` (all new).
- `scenes/main.tscn` -- `FilterHousingStation`, `CircuitTracerStation`
  instances (new, both relocated at least once for nav clearance);
  `CircuitTracerView` focused-state/sfx path overrides (new).
- `tests/test_filter_housing.gd` (new).
- `scripts/interactables/circuit_tracer_station.gd`,
  `scripts/ui/circuit_tracer_diorama.gd`, `scripts/ui/circuit_tracer_view.gd`,
  `scenes/ui/circuit_tracer_diorama.tscn`,
  `scenes/interactables/circuit_tracer_station.tscn` (all new).
- `tests/test_circuit_tracer.gd` (new, 32 checks).
- `tests/run_tests.sh` -- registers `test_flashlight_hard_mode`,
  rewritten `test_valve_routing`, `test_filter_housing`,
  `test_circuit_tracer` (61 registered scripts total; the 62nd `.gd`
  file in `tests/`, `manual_verify_real_input_reconnect.gd`, is
  intentionally excluded -- see Section A).

## Known limitations / deferred

- Priority 1's specific render list ("cabinet before/during/after wire
  installation in both world and focused views") was satisfied by
  Round 14's prior cavity/diorama renders plus this round's color-
  consistency fix; no NEW separate before/after screenshot pair was
  captured specifically for Round 15's own Priority 1, since the
  underlying visual behavior did not change this round (only the
  color/text label did).
- L07's fault-count-by-difficulty mechanic still conflates task
  progression with global difficulty rather than being a genuinely
  separate axis (see Section G) -- a pre-existing Round 14 behavior,
  documented rather than corrected this round.
- The small world-embedded twin of `CircuitTracerStation` (and, per
  direct comparison, `FilterHousingStation`/`ValveRoutingStation`
  before it) renders dim at its small in-world scale under this game's
  corridor lighting -- an established, already-accepted convention
  for distant small props, not something this round attempted to
  change.
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited again this round -- zero new evidence,
  consistent with every prior round).
- As in every prior round, real-rendered verification covered the
  specific states each priority's brief named, not an exhaustive sweep
  of every difficulty × state × camera-angle combination.

# ROUND 16: RANDOMIZATION, A NEW COMMUNICATIONS TASK, AND READABILITY

## Scope

Ten priorities: (1) permanently resolve the recurring "extra Yellow
click" electrical-reconnect report, with real proof, not a unit-test-
only claim; (2) fix the replacement wire's remaining duplicate-object
visual bug; (3) controlled, reproducible wire-fault randomization,
replacing the single hardcoded Red/Blue/Yellow procedure; (4) a
genuine (if CSG-bounded) visual improvement to the first-person hand/
watch; (5) a second, genuinely different valve-routing configuration;
(6) a readability pass across all five focused minigames; (7) one
substantial new maintenance task -- Communications Signal Calibration
(M02); (8) work-order/progression integration review, including
finally decoupling L07's fault count from global difficulty (flagged
but not fixed in Round 15); (9) full regression and rendered
verification; (10) this entry plus a git-checkpoint recommendation (no
commit/push performed). No commits or pushes were made;
`.claude/settings.local.json` was not touched; all pre-existing
uncommitted work was preserved throughout.

## A. The recurring "extra Yellow click": the real root cause

Traced the complete production path for the exact reported sequence
(disconnect Red/Blue/Yellow, replace, reconnect Yellow once, reconnect
Blue once) with a disposable diagnostic script before touching any
code. The backend state machine was confirmed to already be correct --
`reconnect_wire(&"service")` succeeds on its very first real call, no
replay needed. The actual bug: `animate_install_replacement()` (called
when the player clicks the replacement wire to *install* it) ALSO
lit the terminal indicator green and swung the wire to its fully-
seated pose -- before `electrical_panel.gd`'s `reconnect_wire(&"service")`
had ever actually been called (that only happens on the player's
*next*, separate click on that same now-installed wire). A player
trusting the now-green indicator naturally clicks Blue next, gets
correctly rejected ("reconnect Yellow first"), and only then goes back
and clicks Yellow -- which reads exactly like an unwanted extra click,
because relative to what the indicator promised, it is one. This is a
premature-visual-feedback bug, not a state-machine bug, and explains
why it survived multiple previous "fixes" that only ever re-verified
backend correctness.

**Fix**: removed the premature `_set_indicator(&"service", true)` call
from `animate_install_replacement()`. The wire still visually swings
into its seated slot on install (a reasonable "the new part now
occupies the terminal" cue), but the indicator stays off until the
player's actual next click calls `reconnect_wire()` for real.

**Proof, not just a unit-test claim**: (1) a new assertion in
`tests/test_reconnect_visual_position.gd` that the indicator reads OFF
immediately after install, before the first real reconnect call --
verified to actually FAIL against the pre-fix code (temporarily
reintroduced the bug, confirmed both NORMAL and HARD failed, restored
the fix, confirmed both pass again); (2) a full 10-click trace of the
exact intended procedure (isolate, disconnect ×3, replace ×2, reconnect
×3, restore) with zero wrong/duplicate clicks, asserted end to end; (3)
`tests/manual_verify_real_input_reconnect.gd` run under genuine
top-level `push_input()` forwarding (real GPU rendering, the one
environment that actually exercises the real `SubViewportContainer`
GUI-forwarding path) for the exact reported sequence -- `[AFTER
YELLOW]`/`[AFTER BLUE]` both read correctly reconnected with indicators
on, and the full repair completed (`is_repaired=true e05 done=true`).

## B. Replacement wire: eliminating the remaining duplicate object

The carried spare `WireComponent` prop, once consumed by
`install_replacement_wire()`, was reparented onto the cabinet's
`Terminal` node but left **visible** -- a second, independently-
modeled coiled-wire object (authored for a hand-held pickup, nothing
like the diorama's own smooth curved service wire) sitting right next
to the diorama's own `_replacement_wire` inside the same recessed
service bay. Round 15 only recolored this prop to match (blue →
yellow), fixing the color mismatch but leaving the actual duplicate
object in place -- still reading as an unrelated fourth wire, just now
a yellow one. Fixed by setting `visible = false` on install; the node
stays addressable (not freed) so `is_installed()`/`get_parent()`
checks already relied on elsewhere keep working. The diorama's own
`_replacement_wire` is now the one and only visible "installed wire"
representation, confirmed via a real render showing exactly three
wires crossing (Red/Blue/Yellow), no stray object.

## C. Controlled, reproducible wire-fault randomization

`electrical_panel.gd` now has `_REPAIR_CONFIGS`, two validated
configurations that vary WHICH role is at fault (and therefore the
disconnect/reconnect order, the carried part's color, and the trace/
install messages) rather than inventing new wire counts or meshes:
STANDARD (service/Yellow, the original behavior) and an alternate
return/Blue fault. Every other field (disconnect order, reconnect
order) is *derived* from the one `fault` choice via `_disconnect_order()`
(canonical role order minus the fault, fault appended last), so no
inconsistent configuration can be authored. Config selection is
locked exactly once per attempt, the first time `_trace()` runs, and
never regenerates on Escape/reentry or wrong clicks.

Making this real (not just a label swap) required generalizing the
diorama itself: `electrical_repair_diorama.gd` now tracks `_fault_role`,
swaps each wire's mesh between its healthy and a duller/rougher
damaged look depending on which role is actually at fault (previously
only "service" ever had a damaged-look material), and the replacement
wire is pre-built with one curve-shape variant per possible fault role
(`VisualGroup_service`/`VisualGroup_return`, each using THAT role's own
real Bezier curve points, not a single hardcoded shape reused
regardless of which wire is replaced -- reusing service's own long
diagonal sweep for a replaced return wire would have it visibly emerge
from entirely the wrong side of the assembly). The carried spare wire
(`wire_component.gd`) is recolored to match via a new `set_fault_color()`
call the moment a config is chosen, and every player-facing message
(`day_plan.gd`'s work-order line, `workstation_screen.gd`'s Storage
flavor text, the panel's own trace/error messages) now reads the
actual fault color instead of a hardcoded "yellow".

**A genuine real-time flakiness was found and fixed during this
build** (documented in detail because it is instructive): the new
alternate-config test was intermittently failing at exactly the second
real diorama click in a sequence, roughly 1 in 3-5 runs, but 100%
reliable when run in isolation. Root cause, found by elimination: the
test's own disconnect sequence had been driven through direct
`panel.disconnect_wire()` backend calls (to avoid an unrelated, also-
newly-discovered raycast-timing issue), which skipped the VIEW's own
`_refresh()`/`_update_allowed()` call -- leaving the diorama's
`_allowed` click-gate stuck at whatever the ISOLATE stage's initial
open left it as, silently rejecting the next real click. Fixed by
calling `view._sync_diorama_full()` + `view._refresh()` once after the
direct-call block, plus one `await physics_frame` for the just-
repositioned collider to become visible to the next raycast (the same
physics-server transform-sync latency documented repeatedly in prior
rounds). Both fixes verified with 20-run stress batches, zero failures.

Existing tests that hardcode the fixed supply/return/service order
(eight files) now call the new `debug_force_fault_role(&"service")`
test hook before `_trace()` runs, per the brief's own "use
deterministic seeds for testing" -- this is the correct, intended
pattern (production code is NOT supposed to disable randomization for
tests), not a workaround.

`tests/test_electrical_wire_randomization.gd` (new, 28 checks) covers
both the default config unchanged and the alternate config driven
through real diorama clicks end to end: correct recoloring/messaging,
correct disconnect/reconnect order, correct damaged-look swap (return
damaged, service stays healthy), correct replacement-wire visual
variant, full completion, and config-locking surviving Escape/reentry
and a second forced-config attempt.

## D. First-person hand/watch: a real, CSG-bounded improvement

Rendered the existing rig before touching anything (confirmed the
established "render first, then judge" discipline) -- the watch itself
(case, bezel, fasteners, crown, button, recessed face, readable text)
already reads reasonably well; the hand/wrist was the weak point the
brief's complaint matches: a flat `CSGBox3D` for the palm, and visibly
separate, low-segment-count primitives at the forearm/wrist joints.

Targeted fixes within the existing CSG-primitive architecture (a full
skinned mesh is out of scope per the brief's own allowance): replaced
the flat palm box with a non-uniformly-scaled `CSGSphere3D` (plus a
second smaller sphere for the back-of-hand volume) for a genuinely
rounded silhouette; added five small knuckle-bump spheres so each
finger no longer looks glued directly onto a flat palm surface;
increased `sides`/`radial_segments`/`rings` on every major forearm/
wrist/finger primitive (8-12 → 10-18) with `smooth_faces = true` added
where missing, for a visibly smoother silhouette at the same geometry
budget. Re-rendered after the change and compared directly against the
"before" frame -- the wrist/palm transition reads noticeably smoother
and less blocky; fingers/thumb read as individually articulated rather
than a single mass. `tests/test_wristwatch.gd`/
`test_wristwatch_screen_stability.gd` both still pass unchanged
(these changes are geometry-only, no API/behavior change).

**Honest limitation**: this remains CSG-primitive construction, not a
skinned mesh -- a fully convincing hand is still not achievable within
this architecture. The future skeletal-character milestone is the
right place for a true skinned replacement; this round's improvement
is the best clean upgrade available without starting that milestone,
exactly as the brief's own fallback allows.

## E. Valve routing: a second, genuinely different configuration

Visual polish from Round 15 was already reasonably complete (real
pipes, ball valves, pressure gauge, restrained flow glow); this
priority's main work was the "at least two meaningfully different
playable configurations" requirement. Rather than new pipe geometry
(explicitly out of scope per the brief's own "a few validated
configurations beat new geometry" guidance, mirrored from Section C
above), `valve_routing_station.gd` now has two configs that give V3 a
genuinely different PHYSICAL MEANING and WIN CONDITION, reusing the
exact same three valves/pipes:

- **STANDARD** (existing): V3 is a drain. Win = outlet live, drain
  sealed.
- **DUAL_OUTLET** (new): V3 is a second, legitimate outlet -- both V2
  and V3 must end up live. "Both open" alone would just be the "open
  everything" anti-pattern the brief explicitly warns against, so
  completion additionally requires V2 (primary) to have been the most
  recently-opened-before-V3 valve -- "a pressure-loss problem requiring
  careful valve sequencing," one of the brief's own suggested variant
  types. Opening V3 first is harmless and fully recoverable (a
  surfaced, consumed-once warning; close V3, open V2, reopen V3) -- it
  is a REAL completion gate, not merely a warning message, confirmed by
  a dedicated test that opening both in the wrong order leaves the
  task genuinely incomplete even with both branches reading live.

The diorama's `set_flow_visual()` gained a `branch3_is_leak` parameter
so V3's branch renders as a genuine live/teal flow (never the amber/red
leak tint) in DUAL_OUTLET, and the DRAIN 3D label swaps to "OUTLET B"
to match -- same manifold, same geometry, a different (still short,
still physical) terminal label, never silently mismatched against the
station's actual config.

`tests/test_valve_routing_dual_outlet.gd` (new, 15 checks) drives the
full out-of-order → warning → correction → completion sequence through
real diorama clicks. Real-rendered verification confirms both branches
read live/teal (not leak-red) with the status "COOLANT LOOP NOMINAL —
flow routed to both outlets, correctly sequenced."

## F. Readability pass across all five focused minigames

Surveyed every `font_size` across `ElectricalRepairView`,
`SensorCalibrationView`, `ValveRoutingView`, `FilterHousingView`, and
`CircuitTracerView` in `player.tscn` (22 distinct label instances) --
every single one sat well under even the brief's smallest suggested
tier (equipment labels, 16-20px), several as low as 11-15px. Applied a
consistent three-tier hierarchy: main objective/stage labels → 28px
(electrical's `StageLabel` was already there; every other view's
equivalent main-status label raised to match); secondary control
hints/status feedback → 18-20px; compact per-equipment readouts
(chamber status chips, the demoted schematic overlay, the EASY-only
log) → 15-17px. No text was removed or paragraph-ized -- this is
purely a legibility fix, not a content change. Verified with a direct
before/after real render of Circuit Tracer (the smallest text in the
original survey): the main instruction and control hint are now
immediately readable at a glance, with no overflow/clipping in either
panel.

## G. New maintenance task: M02 Signal Calibration (Communications)

Cross-checked `GAME_DESIGN.md` Section 30's own Communications Tasks
catalog before building anything: M02 Signal Calibration ("Tune signal
using a physical dial/control and observe the result") is a real,
previously-unimplemented catalog entry that matches the brief's own
preferred candidate name almost exactly, so no new or repurposed task
ID was needed. Placed in the existing (previously prop-less)
Communications room, on its solid north wall (no rotation needed --
the diorama camera's own default -Z already faces into the room from
there), confirmed via the capsule sweep at the same 38-edge/5-known-
failure baseline with 0 new regressions.

**The mechanic** is genuinely different in kind from every other task
in this project: continuous TWO-PARAMETER tuning (frequency 0-100,
gain 0-1) toward one fixed, hidden target, via two rotary dials (each
a single click target, split into decrease/increase halves by WHERE on
the dial body the raycast lands -- "the simplest appropriate mechanic,"
no extra invisible colliders needed), an analog signal-strength needle
meter, and a small oscilloscope-style waveform display (ten animated
CSG bars whose height tracks quality and whose jitter/color track
noise). Signal quality is the PRODUCT of a frequency-distance factor
and a gain-distance factor -- both dimensions must be near their own
target simultaneously, a real two-parameter problem, not "turn one
knob until a number reaches a target" (confirmed directly by a test:
tuning frequency alone to within 1 unit of its target, with gain left
untouched, still reads well under the completion threshold). Gain also
controls noise amplification when off-frequency, so a badly-tuned
attempt with gain turned up reads visibly worse (louder, redder
waveform), not just quieter.

Completion requires signal quality to stay above a difficulty-scaled
threshold for a SUSTAINED real-time period (2 seconds), not an instant
crossing -- "establish adequate signal quality for a sustained
verification period," per the brief. Dropping below threshold resets
the hold timer (recoverable, never a hard failure) rather than failing
the attempt. HARD difficulty hides the numeric frequency/gain/quality
readout entirely (tune by ear/eye only, via the needle and waveform);
EASY additionally shows a target marker.

**A real implementation lesson, documented because it will recur**:
the first attempt to verify the sustained-hold logic via a `for i in N:
await process_frame` loop showed it never completing even after what
looked like several real seconds. Root cause: Godot's headless mode
runs frames at whatever (often very small) delta the engine can
process, NOT a fixed 1/60s -- a frame-COUNT loop does not reliably
represent real elapsed TIME. Fixed by using `await create_timer(X).timeout`
(a genuine wall-clock timer) for the hold-duration portions of both the
manual diagnostic and the permanent test, matching the pattern this
project already uses elsewhere for animation settle waits.

`tests/test_signal_calibration.gd` (new, 23 checks) covers: the
deliberately-far starting state; frequency alone being insufficient
(the two-parameter requirement); both dials tuned via real diorama
clicks reaching high quality; a partial hold, a deliberate detune below
threshold resetting progress, and a full-duration real-time hold
completing the task; the world-view twin staying in sync; reopening
after completion; and HARD hiding the numeric readout. Real-rendered
verification shows the initial low-quality/quiet-waveform state and
the tuned high-quality state (taller green bars, "SIGNAL ACQUIRED —
holding... 13%", both dial pointers visibly rotated).

## H. Work-order integration and progression

**L07's fault-count/difficulty conflation, finally fixed** (flagged
but deliberately left alone in Round 15's own report): fault count
(how many of the three chambers start broken) is now
`sensor_calibration_station.gd`'s own exported `fault_count` property
(`active_fault_count()`), a work-order-scenario value completely
independent of `GameSettings.get_difficulty()` -- not a dict keyed by
difficulty. An EASY-difficulty player and a HARD-difficulty player
attempting the one existing L07 station now face the IDENTICAL fault
count (2, the exported default); only how forgiving the attempt is
(`_coupling`/`_tolerance`/`_stability_duration`, all still legitimately
difficulty-scoped) differs. This project has no actual day/assignment
progression system (`day_plan.gd`'s own documented policy: no
calendar, no day counter, not added this round either per the brief's
own "do not build a full procedural daily work-order generator"), so
today this is a single exported value on the one L07 station instance
-- but the seam is real: a future second station/scenario would simply
export a different `fault_count`, with zero logic changes needed
anywhere else. `tests/test_sensor_calibration_difficulty.gd` was
updated to explicitly confirm fault count now stays IDENTICAL across
EASY/NORMAL/HARD (previously it asserted 1/2/3 -- the exact conflation
the brief asks to undo).

**A real regression was found and fixed while making this change**:
`tests/test_sensor_calibration.gd` referenced the now-deleted
`_ACTIVE_FAULT_COUNT_BY_DIFFICULTY` constant directly, which threw an
uncaught property-access error inside its own `_init()` coroutine --
and because a script error inside `_init()` never reaches `quit()`,
the Godot process hangs indefinitely rather than failing visibly (the
same silent-hang class discovered and documented in Round 15,
recurring here for the same underlying reason). Caught by noticing an
unusually long-running headless process, not by a visible test
failure; fixed by updating the test to call the new
`station.active_fault_count()` instead. A systematic grep confirmed no
other file referenced the deleted constant.

**Discoverability review**: the Control Room workstation's own
room-info text for Communications and Life Support both still said
"Not used by any currently active task" even with real, playable
stations physically present in both rooms (Life Support's own L07/L08/
L02 predate this round entirely -- this was a pre-existing gap, not
something this round introduced). Engineering's own no-open-work-order
fallback line never mentioned the E09 diagnostic bench (added Round
15) at all. Fixed all three to describe the actual free-standing
equipment present, reading `DayPlan`'s existing done-flags for a
"available" vs "serviced" distinction -- flavor/discoverability text
only, read-only, never duplicating task state or injecting these
free-standing tasks into the Work Orders panel/Slice B chain (which
they are deliberately not part of). `tests/test_workstation_room_discoverability.gd`
(new, 8 checks) locks this in.

## Files changed

- `scripts/ui/electrical_repair_diorama.gd` -- removed the premature
  `_set_indicator()` call from `animate_install_replacement()`;
  `_fault_role`/`set_fault_role()`/`_apply_fault_role_visuals()`/
  `_active_replacement_visual_group()`/`_visual_group_for()` (new);
  `_build_wire_curve()` signature generalized; `sync_full_state()`
  gained a leading `fault_role` parameter.
- `scenes/ui/electrical_repair_diorama.tscn` -- `Mat_wire_return_damaged`/
  `Mat_wire_return_replacement` (new materials); `ReplacementWire`
  restructured from one `VisualGroup` into `VisualGroup_service`/
  `VisualGroup_return`; a `DamageScorch` added under `Wires/Return`.
- `tests/test_reconnect_visual_position.gd` -- new indicator-OFF-
  right-after-install assertions (verified to fail against the
  reintroduced bug, pass against the fix); `VisualGroup` path
  references updated to `VisualGroup_service`.
- `tests/manual_verify_real_input_reconnect.gd` -- forces the
  deterministic default config; `VisualGroup` path references updated.
- `scripts/interactables/wire_component.gd` -- `mark_installed()` now
  sets `visible = false`; `set_fault_color()` (new);
  `_color_name` (new).
- `tests/test_electrical_panel_chain.gd` -- new "no duplicate wire
  object" assertion; forces the deterministic default config.
- `scripts/interactables/electrical_panel.gd` -- `_REPAIR_CONFIGS`,
  `_config_index`, `_fault_role`, `_select_repair_config()`,
  `debug_force_fault_role()`, `fault_role()`, `fault_color_name()`,
  `_disconnect_order()`, `WIRE_COLORS` (all new); `wire_component_path`
  export (new); every hardcoded "yellow" message generalized.
- `scripts/ui/electrical_repair_view.gd` -- every hardcoded `&"service"`
  reference generalized to `_panel.fault_role()`; `ElectricalPanel`
  preload (new, for `WIRE_ROLES` access).
- `scenes/main.tscn` -- `EngineeringCabinet1` gained `wire_component_path`;
  `SignalCalibrationStation` instance (new); `SignalCalibrationView`
  focused-state/sfx overrides (new).
- 8 existing test files (`test_electrical_repair_procedure.gd`,
  `test_electrical_panel_terminal.gd`, `test_interaction_prompts.gd`,
  `test_reconnect_hitbox_bug.gd`, `test_reconnect_visual_position.gd`,
  `test_reconnect_lifecycle.gd`, `test_difficulty_configuration.gd`,
  `test_slice_b_e2e.gd`) -- each now forces the deterministic default
  config via `debug_force_fault_role(&"service")`.
- `tests/test_electrical_wire_randomization.gd` (new, 28 checks).
- `scenes/player/first_person_watch_rig.tscn` -- palm box replaced with
  two scaled spheres; 5 knuckle-bump spheres (new); increased
  sides/radial_segments/rings and `smooth_faces` across forearm/wrist/
  finger primitives.
- `scripts/interactables/valve_routing_station.gd` -- `ConfigKind`,
  `_CONFIGS`, `_config_index`, `_select_config()`,
  `debug_force_config()`, `config_kind()`, `is_dual_outlet()`,
  `drain_label_text()`, `branch3_is_leak()`, `_open_order`,
  `_v3_opened_with_v2_open`, `_pending_sequence_warning`,
  `consume_sequence_warning()` (all new); `_is_solved()` generalized.
- `scripts/ui/valve_routing_diorama.gd` -- `set_flow_visual()`/
  `sync_full_state()` gained a `branch3_is_leak`/`treat-as-leak`
  parameter; `set_drain_label_text()` (new).
- `scripts/ui/valve_routing_view.gd` -- config-aware status/flow/
  schematic text; sequence-warning surfacing.
- `tests/test_valve_routing.gd` -- forces the deterministic STANDARD
  config.
- `tests/test_valve_routing_dual_outlet.gd` (new, 15 checks).
- `scenes/player.tscn` -- 22 `font_size` values raised across all five
  minigame views; `SignalCalibrationView` node tree (new).
- `scripts/station/day_plan.gd` -- `m02_status` (new), wired into
  `is_task_done()`/`mark_done()`/`reset_for_new_day()`.
- `scripts/interactables/signal_calibration_station.gd`,
  `scripts/ui/signal_calibration_diorama.gd`,
  `scripts/ui/signal_calibration_view.gd`,
  `scenes/ui/signal_calibration_diorama.tscn`,
  `scenes/interactables/signal_calibration_station.tscn` (all new).
- `tests/test_signal_calibration.gd` (new, 23 checks).
- `scripts/interactables/sensor_calibration_station.gd` -- exported
  `fault_count`/`active_fault_count()` (new).
- `scripts/ui/sensor_calibration_view.gd` -- `_ACTIVE_FAULT_COUNT_BY_DIFFICULTY`
  removed; `open_station()` now reads `station.active_fault_count()`.
- `tests/test_sensor_calibration_difficulty.gd` -- updated to confirm
  fault count is now IDENTICAL across difficulties.
- `tests/test_sensor_calibration.gd` -- fixed a reference to the
  now-deleted `_ACTIVE_FAULT_COUNT_BY_DIFFICULTY` constant that was
  silently hanging the test process (uncaught error inside `_init()`
  never reaching `quit()`).
- `scripts/ui/workstation_screen.gd` -- Communications/Life Support/
  Engineering room-info text now describes actual free-standing
  equipment instead of stale "not used by any task" text;
  `_fault_color_name()` helper (new, from Round 15 carry-forward).
- `tests/test_workstation_room_discoverability.gd` (new, 8 checks).
- `tests/run_tests.sh` -- registers `test_electrical_wire_randomization`,
  `test_valve_routing_dual_outlet`, `test_signal_calibration`,
  `test_workstation_room_discoverability` (69 registered scripts
  total; the 70th `.gd` file in `tests/`, `manual_verify_real_input_reconnect.gd`,
  is intentionally excluded -- see Section A).

## Known limitations / deferred

- The first-person hand remains CSG-primitive construction, not a
  skinned mesh -- a fully convincing hand is not achievable within this
  architecture; the future skeletal-character milestone is the right
  place for a true replacement (see Section D).
- DUAL_OUTLET is valve routing's only second configuration this round
  (the brief's own "at least two" minimum, satisfied); a third variant
  (e.g. a blocked-branch bypass, which would need new pipe/valve
  geometry) was considered and deliberately deferred given this
  round's much larger remaining scope.
- M02 Signal Calibration has one fixed, non-randomized target
  frequency/gain (same "one authored puzzle instance" policy as every
  other minigame in this project) -- no difficulty/progression
  variation in the TARGET itself, only in tolerance/threshold and
  readout visibility.
- This project still has no actual day/assignment progression system
  (no calendar, no day counter, no work-order scenario selector) --
  Section H's fault_count/difficulty decoupling establishes a real
  architectural seam for one to eventually read, but nothing yet
  picks a scenario automatically; today's single exported value is set
  once, at scene-author time, on the one station instance that exists.
- `test_locked_graph` and `test_living_quarters_room` remain genuinely
  unresolved (re-audited again this round -- zero new evidence,
  consistent with every prior round).
- As in every prior round, real-rendered verification covered the
  specific states each priority's brief named, not an exhaustive sweep
  of every difficulty × state × camera-angle combination.

# ROUND 17: KEYBOARD-PRIMARY SIGNAL CALIBRATION, READABILITY, AND A LIVING QUARTERS MIRROR

## Scope

A readability/font-consistency pass across every focused minigame;
keyboard-primary controls plus randomized difficulty profiles for
Signal Calibration; a fix for a hardcoded DISCONNECT-stage bug in
`electrical_repair_view.gd`; rendering verification of a widened
5-wire electrical panel; a Living Quarters wash-station mirror
(SubViewport-based reflection feed); a player `HeadGroup` geometry
addition (head/neck/visor, on its own render layer) so third-person
viewpoints such as the new mirror show a head instead of a headless
torso; and a wristwatch/hand geometry tuning pass. No commits/pushes
performed as part of this round's own work.

The mirror was built as a live SubViewport feed (the same pattern
`surveillance_camera.gd` already established), painted onto the
physical glass CSG surface in `main.tscn`. Its first version used a
plain `look_at(player_eye)` camera placed a small fixed distance in
front of the glass -- later found in Round 19 to be the actual root
cause of "behaves like a fixed camera, not a real mirror," since
`look_at` always re-centers on the player regardless of where they
stand. Round 17 itself did not identify this; it is recorded here only
so this document's own history stays accurate about when the mirror's
real architecture changed (see Round 19 Section B).

## Known limitations carried forward

- `test_locked_graph`/`test_living_quarters_room` remained unresolved,
  same as every prior round.
- The mirror's left/right and up/down orientation had not yet been
  render-verified with asymmetric markers at the end of this round --
  that verification, and the upside-down/left-right bugs it found, are
  Round 18's own work (Section below).

# ROUND 18: SIX-CHAMBER CALIBRATION, A 10-WIRE PANEL, THE MIRROR'S FIRST ORIENTATION FIX, AND READABILITY

## Scope

Ten priorities, delivered selectively given the brief's own size: (1)
fix the Living Quarters mirror's upside-down/left-right orientation,
confirmed via asymmetric marker-cube renders -- two independent bugs
found and fixed (a 2D UV left/right flip on the glass material, and an
independent V-axis inversion in the glass CSGBox3D's own default UV
mapping); (2) redesign the electrical repair panel from 5 to 10 wires
(two physical rows, A hand-authored + B built procedurally from the
same per-role data tables, so the two rows can never drift out of
sync); (3) expand Chamber Calibration from 3 to 6 chambers (a general
NxN Gaussian-elimination equilibrium solver replacing the old
hardcoded 3x3 case), with required-fault-count tied to global
difficulty (EASY 1-2, NORMAL 3-4, HARD 5-6 of 6) -- a choice Round 19's
own audit later reversed (see Round 19 Section G); (4) Signal Tuning
completion-feedback states (SEARCHING -> ACQUIRED -> FINE TUNING ->
STABILIZING -> LOCKED); (7) a readability pass (36/26/20pt targets)
across every focused minigame; (9) resolution of several Round 17
quality issues, including a transient raycast-miss-after-adjacent-
collider-move flaky-test root cause (fixed via retry-on-miss in the
affected tests' own click-dispatch helpers). Priorities 5
(wristwatch/hand/arm redesign), 6 (full-body geometry), 8 (overall
difficulty audit), and 10 (additional polish) were explicitly deferred
given the scope already delivered, and documented as deferred rather
than silently dropped. Commit `9bc03b6` (preceded by checkpoint commit
`d2612eb` covering all prior uncommitted Round 5-17 work) was pushed,
with the user's own explicit authorization that round.

## Known limitations carried forward

- The mirror's ORIENTATION bugs were fixed and render-verified this
  round, but its underlying CAMERA MODEL was still a plain `look_at`
  camera placed in front of the glass -- genuinely improved from
  "upside down," but still not a true planar reflection (see Round 19
  Section B for the actual parallax fix).
- Priorities 5, 6, 8, and 10 were not attempted this round at all.
- `test_locked_graph`/`test_living_quarters_room` remained unresolved.

# ROUND 19: ACCURATE MIRROR PARALLAX, A REAL HAND/WATCH, PHYSICAL STORAGE, AND STATION POLISH

## Scope

A large brief covering: (1) a genuine view-angle-dependent mirror
reflection (not just correct orientation); (2) real hand and
wristwatch geometry on the world-body character, replacing bare
primitive blobs; (3) a physical storage cabinet so a maintenance spare
is retrieved from an openable container instead of sitting on an open
shelf; (4) a 3x2 (two rows of three) calibration-gauge layout, plus
separating required-fault-count from global difficulty; (5) closing a
real structural gap in the Control Room walkway; (6) a small visual
realism pass on the electrical panel's wire entry points; full
regression coverage throughout; and this documentation entry. Given
the brief's own enormous size, Priority 7 (work-order/task-progression
coherence review) and Priority 8 (one or two small complementary
additions) were NOT attempted this round, and the Priority 3 storage
work was deliberately scoped to the single existing retrievable item
(the electrical spare wire) rather than the full multi-category (A/B/C)
cabinet system the brief described, plus the filter-cartridge-from-
storage integration -- both explicitly deferred, not silently dropped
(see "Known limitations" below). No commit or push was performed this
round; the brief did not explicitly authorize one (unlike Round 18's
own brief, which did).

## A. Genuine mirror parallax: an off-axis portal projection

**Root cause of "behaves like a fixed camera, not a real mirror"**:
`_update_reflection()` called `_mirror_camera.look_at(eye, UP)` every
frame -- this ALWAYS re-centers the camera's gaze on the player
regardless of where they stand, which is a tracking-camera behavior,
not a mirror (a real mirror's reflected viewpoint translates with you
but does not re-center on you). A first attempt replaced `look_at`
with the player's own forward/up vectors reflected across the mirror
plane -- confirmed by render to make the content change with player
position (the original bug's defining symptom gone), but a 3-position
parallax sweep (rendered, not just asserted) showed the reflected
character's own screen position/scale barely moved between positions,
revealing a deeper limitation: a flat SubViewport texture painted onto
the glass with a plain (symmetric-frustum) camera can only depend on
where the camera is POINTED, never on the real viewer's angle to the
FIXED glass rectangle -- which is what a true mirror or window
requires.

**The actual fix**: a genuine off-axis ("asymmetric frustum" / portal-
style) projection. The virtual eye is the same true in-plane (left/
right, up/down) reflection of the player's own eye Round 17/18 already
used, but now placed a small fixed distance BEHIND the glass (toward
the wall) instead of in front of it, so it can look back THROUGH the
glass at the room -- viable because a solid, single-sided CSGBox3D
(the wall/cabinet) is backface-culled from the inside, so it does not
actually occlude the virtual eye's view (confirmed by render: nothing
beyond that geometry is modelled, so extreme frustum edges show void,
not the wall itself blocking things). The camera's ORIENTATION is now
fixed to the glass's own plane basis (a portal's viewing axis does not
rotate with the viewer) rather than reflecting player gaze; the
frustum's ASYMMETRY (Godot `Camera3D.PROJECTION_FRUSTUM`'s `size` +
`frustum_offset` + `near`) is computed each frame from the glass
rectangle's four corners as seen from the virtual eye -- standard
portal-rendering derivation, verified both symbolically and against
Godot's own documented `frustum_offset` semantics.

**Render verification** (all real `--write-movie`/direct-viewport
captures, not headless-only inspection): a left/center/right lateral
sweep showing genuinely different scene content at each position (the
right position's extreme angle shows mostly void at the frame edges --
an honest, documented limitation, not a bug, since the player's own
body fills most of the frame at normal viewing distance); close/far
captures showing correct zoom-with-distance; an oblique-angle capture
showing real asymmetric reframing (content shifts toward one side of
the glass, exactly as a real window would); a centered capture clearly
showing the reflected full-body silhouette. A new
`test_mirror_reflection.gd` assertion set covers: the virtual eye sits
BEHIND the glass (not in front, the opposite of Round 17/18's
approach); the camera uses `PROJECTION_FRUSTUM`; `frustum_offset`
genuinely shifts with player position; camera orientation stays FIXED
to the glass plane even as the player turns their head (the key
behavioral difference from the first, superseded gaze-reflecting
attempt).

**Honest limitation**: there is currently no distinct WORLD-BODY watch-
inspection pose -- render-verified directly (a "watch raised" capture
of the world body was pixel-identical to the unraised one) before any
fix was attempted. `wristwatch_view.gd` now also calls a new
`player_body.set_watch_raise_pose()` (Section C) so the mirror DOES
show a modest arm-raise while C is held, addressing this gap as part
of Section C's own work rather than leaving it purely documented.

## B. Real hand and wristwatch geometry on the world body

**Investigation finding**: the first-person watch-rig
(`first_person_watch_rig.tscn`) already had a genuinely detailed palm/
4-finger/separately-articulated-thumb/watch-case design (built in an
earlier round) -- it did NOT need rebuilding. The actual gap was
entirely on the WORLD body (`player_body.tscn`): `HandL`/`HandR` in
every pose (Standing, Sitting) were a single bare `CSGSphere3D` each --
no fingers, no thumb, no joints -- and the world body had no
wristwatch model anywhere, even though it is what the new mirror (and
any future third-person/multiplayer view) actually renders.

**Fix**: `HandL`/`HandR` in `player_body.tscn` were converted from
`CSGSphere3D` to empty `CSGCombiner3D` anchors; `player_body.gd` now
builds a real hand (a two-box tapered palm, four fingers each with a
knuckle sphere + two tapered cylinder segments + a matched-radius tip,
and a separately-angled thumb attached to the palm's own side, not the
knuckle row) procedurally at `_ready()` -- reusing this project's
established "procedural node generation for geometry too repetitive to
hand-author in `.tscn` text" pattern -- for both Standing and Sitting
poses, mirrored correctly per hand via a single builder function. A
compact case/bezel/face/strap/crown/lugs wristwatch, at the same
physical dimensions as the first-person rig's own watch case, is now
built onto the StandingPose/SittingPose right wrist too, visible at
all times (not only while C is held, unlike the camera-relative
first-person rig) -- a real third-person view should always show a
watch on the arm, exactly like a real wristwatch never disappears.

**Render verification**: a hand close-up clearly shows the palm,
four fingers with visible knuckle segmentation, and the watch case/
bezel/crown attached directly to the wrist (not floating); a sitting-
pose capture shows both jointed hands clearly in the seated/resting
pose; a side-angle capture shows a connected head/shoulder/torso/arm
silhouette. Several camera-placement iterations were needed to get
clean external captures in this specific tight alcove (an early
attempt's camera landed embedded in nearby walls, invisible-from-
inside CSG producing solid-black renders) -- resolved by anchoring the
diagnostic camera to a real body part (Chest) at a modest offset
rather than a large offset from an assumed-clear stage position.

**Known limitation**: a full Skeleton3D migration was explicitly
considered (per the brief's own framing of it as "justified now") but
NOT attempted -- `player_body.gd`'s existing leg-swing/arm-gesture/lean
animation logic is built entirely around named CSG-node POSITION/
TRANSFORM tweens (a two-bone law-of-cosines leg solve, a falloff-
weighted arm-gesture reach), none of which is compatible with
skeleton-bone-pose animation without a full reimplementation, and
CSGShape3D nodes cannot be skeleton-skinned in Godot at all (a true
rigged mesh would require hand-authoring an `ArrayMesh` with per-
vertex bone weights, a fundamentally different and much larger
undertaking than this round's remaining scope allowed). Per the
brief's own explicit escape valve ("provide a strong mesh-based
improvement and document the exact blocking dependency" rather than
silently substituting more CSG blocks), this round took the documented
mesh-based path instead.

## C. World-body watch-raise pose

`player_body.gd` gained `set_watch_raise_pose(raised, duration)`: a
modest standing-only right-arm raise toward the chest/lower-face,
using the same falloff-from-rest-position tween technique
`animate_hand_laptop_gesture()` already established for the sitting
pose's laptop-reach gesture (not a new animation system).
`wristwatch_view.gd` now calls it alongside its existing first-person
`_watch_rig.set_raised()` call, so holding C shows a believable world-
body "looking at my wrist" pose in the mirror for exactly as long as
the first-person presentation is also shown -- addressing the gap
Section A's own render verification found.

## D. Physical storage for the electrical spare wire

**Investigation finding**: the Storage room already exists in
`main.tscn` (`StorageFloor`/`StorageRack1`/`StorageRack1Shelf`/etc.),
and `Interactables/WireComponent` was ALREADY physically positioned on
`StorageRack1Shelf` inside it -- the "parts appear magically on
countertops" complaint was not about the part's location, but that
nothing enclosed it: it sat on an open shelf beside a solid decorative
rack, directly raycast-hittable with a single click, no door or
opening ritual of any kind.

**Fix**: a new `scripts/interactables/storage_cabinet.gd` plus a small
five-panel shell (back/top/bottom/two sides) and a real hinged door
(tweened rotation, same pivot-Node3D technique the breaker/latch
hinges elsewhere in this project already use) built around the
existing shelf/wire position in `main.tscn`. The wire's own visibility
and collision are gated by the cabinet's open/closed state (hidden and
non-raycastable while shut, shown and clickable once open) -- the
wire's own `interact()`/pickup/carry logic in `wire_component.gd` is
completely unmodified; the cabinet only controls whether a raycast can
reach it at all, the same "gate the existing object, don't duplicate
its logic" pattern this project already uses for `HeadGroup`'s render-
layer gating.

**Render verification**: a closed-door capture shows an opaque door
panel with a visible handle, fully hiding the interior; an open-door
capture (door swung open, visible at an angle) shows the interior
shelf with the yellow coiled wire genuinely sitting on it, visible and
reachable only now.

**A real regression found and fixed during this work**: the cabinet's
own side walls, authored flush with the front opening plane, created a
tight grazing corner that blocked a realistic diagonal approach-angle
raycast (confirmed by debug coordinate printing, not guessed) --
`test_interaction_prompts.gd` and `test_carry_drop.gd`, which raycast
at the wire from a natural nearby stance, started failing. Fixed by
recessing the side walls 0.05m back from the opening (more raycast
clearance at the corners) and updating both tests to open the cabinet
first, reflecting the new correct flow, rather than reverting the
cabinet. A new `test_storage_cabinet.gd` covers the door gate itself
directly via a genuine `PhysicsRayQueryParameters3D` query (not just
calling `interact()` on the object directly, which every pre-existing
wire-related test does and which deliberately bypasses this new gate).

**Known limitations, explicitly deferred, not silently dropped**: the
filter-housing task's replacement cartridge is still not a physical
Storage pickup at all (no cartridge prop exists in the scene); the
broader multi-category (A: electrical components, B: environmental/
life-support, C: tools/spares) cabinet system the brief described was
not built -- only the one existing retrievable item (the electrical
spare wire) was enclosed. Both are real, scoped-out gaps given this
round's remaining time budget, not oversights.

## E. 3x2 calibration layout, and separating count from difficulty

`ChamberRow` (`scenes/player.tscn`) changed from a single 6-wide
`HBoxContainer` to a 3-column `GridContainer` -- A/B/C fill row one,
D/E/F wrap onto row two automatically, since
`sensor_calibration_view.gd`'s own `_build_row_b()` already just
appends children in order (no positioning math needed). Fitting two
rows in the existing panel required shrinking `StatusLabel`'s font
(36pt -> 26pt, with an explicit minimum-height reservation so a two-
line wrapped status message can never overlap the chamber row below
it -- a real overlap bug found and fixed via render, not assumed) and
each `GaugeStack`'s own minimum height (130px -> 108px). Render-
verified: all six gauges visible in two clean rows of three, with the
shared damping control and the full keybind legend both fully visible
below, no clipping or overlap at the default 1152x648 resolution.

**Difficulty/progression separation** (this round's own explicit audit
instruction, reversing part of Round 18's Section 3/Priority 3):
required-fault-count no longer depends on the global EASY/NORMAL/HARD
setting at all. `sensor_calibration_view.gd` now keys it on a new
`_completions_this_session` counter (incremented once per real
`_commit_success()`) against a 3-tier progression table (first attempt
ever: 1-2 of 6; a few completions in: 2-4; experienced: 3-6, the full
complex range) -- deliberately NOT added to `DayPlan` (that script's
own class doc comment documents "no calendar, no day counter, no
simulation-time system" as an explicit prior Approved Decision; adding
a persistent cross-day counter there would reverse it), so it lives
entirely on this one view instead, the same "plain per-session state"
convention every other focused-view script here already uses.
Difficulty's role is now exclusively tolerance/stability/coupling-
strength (unchanged from Round 18) -- never count. A new
`test_sensor_calibration_layout_progression.gd` proves BOTH halves
concretely: HARD with zero completions still only ever produces 1-2 of
6 (not its old 5-6), and EASY with 3+ completions can reach 5-6 --
the exact two symptoms the brief's own audit instruction named.

## F. Control Room walkway: a real structural gap, not a texture bug

**Investigation, via actual rendering, not transform-math alone**: an
oblique/upward-pitched render from inside the corridor approaching
Main Junction A showed large solid BLACK regions at the frame's upper
corners -- genuine void, not a UV/lighting artifact. Coordinate
analysis of every `CSGBox3D` in that z-range confirmed a real 0.3m gap
(z=3.20 to z=3.50) where NEITHER the corridor's own floor/ceiling/
walls (ending at z=3.20) NOR Main Junction A's own floor/ceiling/west
wall (starting at z=3.50) provided any coverage at all -- floor,
ceiling, and both side walls were all missing simultaneously in that
band.

**Fix**: `CorridorFloor`/`CorridorCeiling`/`CorridorWestWall`/
`CorridorEastWall` extended from z=3.20 to z=3.50 (keeping the same
near edge at z=2.10 and the same 1.6m passable width, so the doorway's
usable width is unchanged), closing the gap directly. The now-
redundant `CorridorEndWallWest`/`CorridorEndWallEast` end-caps (which
would otherwise sit embedded mid-wall once the real walls extended
past them) were removed.

**Render verification**: the same oblique/upward-pitched viewpoint
that originally showed the black void now shows a fully enclosed,
continuous ceiling/wall transition with no visible gaps.
`test_station_capsule_sweep` confirms the exact same 5 known pre-
existing navigation-clearance failures as the established baseline,
zero new regressions; a new `test_control_room_walkway_seal.gd` asserts
the z-continuity directly from scene geometry (floor/ceiling/wall far-
edge >= the next segment's near-edge, for every piece on both sides of
the seam) so a future edit shrinking either side back below the
overlap cannot silently reopen the gap.

## G. Electrical panel: cable entry brackets

A small clamp/gland bracket (a `CSGBox3D`, reusing the terminal
housing's own material) now caps each of the 10 installed wires' own
TOP entry point, addressing the specific "cables ending openly toward
the top" complaint -- purely decorative, added once per role in
`electrical_repair_diorama.gd`'s own `_ready()` (never on the staged
`ReplacementWire` variants, which are not anchored to anything yet).
Deliberately minimal given this round's remaining scope: the fixed-10-
wire-identity architecture itself was not touched, and a fuller cable-
bundle/sleeve treatment described in the brief was not attempted.
Render-verified via the real repair-procedure view (door open, wire
picked up, terminal clicked through to the procedure) -- small grey
bracket caps visible at each wire's own entry point.

## H. Not attempted this round

Priority 7 (work-order/task-progression coherence review) and Priority
8 (small complementary additions beyond what Sections D/E/G already
include) were not attempted, given this round's remaining time budget
after Sections A-G. Both are genuine, scoped-out gaps against the
brief, documented here rather than silently dropped.

## Known limitations

- The mirror's extreme-oblique-angle frame edges show void (nothing is
  modelled behind the wall/cabinet) -- an honest, render-confirmed
  limitation of the off-axis approach given this station's real hull
  geometry, not a bug (see Section A).
- No full Skeleton3D character rig -- a documented, deliberate
  mesh-based path per the brief's own escape valve (see Section B).
- The filter-housing task still has no physical Storage-retrieved
  replacement cartridge; the broader multi-category storage system was
  not built (see Section D).
- Work-order coherence (Priority 7) and additional small polish
  (Priority 8) were not attempted this round (see Section H).
- `test_locked_graph`/`test_living_quarters_room` remain genuinely
  unresolved, consistent with every prior round's own re-audit.
- As in every prior round, real-rendered verification covered the
  specific states each section's own work named, not an exhaustive
  sweep of every difficulty x state x camera-angle combination.

# ROUND 20: MIRROR FOV, HAND GEOMETRY, THE JUNCTION-ENGINEERING DOORWAY, PHYSICAL STORAGE, AND WORK-ORDER COHERENCE

## Scope

Ten priorities from a player-feedback-driven brief. Addressed this
round: (1) the Living Quarters mirror's fisheye distortion, a real
root-cause fix (virtual-eye depth), not a reversal of Round 19's
parallax work; (2) a shared, reusable finger/thumb mesh builder
(`hand_mesh_builder.gd`) replacing the old per-finger CSG-primitive
chain on both the world body and the first-person rig; (3) a second,
previously-unaddressed structural gap at the Junction-Engineering
doorway (downstream of Round 19's own Control-Room-to-Junction-A seal,
confirmed by direct raycast to be a real void, not a lighting/texture
issue); (4) a second physical storage cabinet and a new carryable
Filter Cartridge item, replacing the filter-housing task's "part
appears beside the housing" placeholder behavior with a real
Storage-retrieval requirement; (5) a wristwatch glance hint ("GET
PART / STORAGE") when the electrical task's required component is
known but not yet in hand; (6) an audit confirming the six-chamber
calibration layout and its global-difficulty-vs-technician-progression
split (already correctly separated as of Round 19 Priority 4) needed
no further change; (7) cable-entry collars, mid-run routing clips,
terminal strain-relief collars, and paired-wire bundle ties on the
electrical panel, extending Round 19's single entry bracket; (8) small
storage-door and item-pickup/drop sound feedback, routed through the
existing shared `mechanical_sfx.gd` bank. Priorities 9 (verification)
and 10 (this section) close out the round. No commits or pushes were
performed.

## A. Mirror FOV: a virtual-eye depth bug, not a projection-math bug

Round 19's off-axis portal projection (`Camera3D.PROJECTION_FRUSTUM` +
fixed `size` + per-frame `frustum_offset`) was algebraically correct;
the complaint ("distorted/stretched, especially at oblique angles") had
a different, narrower cause. The off-axis frustum's vertical `size` is
constant by construction (see Round 19 Section A's own derivation), so
the half-angle of view is set entirely by `half_angle = atan(half_height
/ depth)`, where `depth` is `_VIRTUAL_EYE_DEPTH_BEHIND_GLASS` --
Round 19 had left this at `0.05`, giving a ~77 degree half-angle (a
fisheye) rather than a normal mirror's view. Raised to `0.4`, this
yields ~28 degrees, a normal reflection field of view. A second, much
smaller residual stretch (~0.8%) came from the SubViewport's pixel size
(`480x400`, aspect 1.2) not exactly matching the physical glass
rectangle's own aspect (0.5/0.42 = ~1.19); corrected to `500x420` (exact
match). No frustum-offset/near-plane/handedness/culling logic was
touched -- confirmed via `tests/test_hand_mesh_and_mirror_fov.gd`, which
asserts the viewport aspect now matches the glass aspect exactly and
the frustum half-angle lands in a normal 10-45 degree range (measured:
~27.7 degrees, versus the old ~77 degrees). Render-verified across
near/far/left/right/oblique camera placements with asymmetric marker
objects in frame (continuing Round 18/19's own verification approach);
no stretching or fisheye artifact at any tested angle. The previously
noted "mirror edge-void" limitation (nothing modelled behind the
wall/cabinet, visible only at extreme oblique angles) was re-examined
and remains an honest, unchanged limitation of the off-axis approach
given this station's real hull geometry -- not something this round's
fix touches or could touch without modelling behind-wall geometry that
does not otherwise need to exist.

## B. A shared, reusable hand-mesh builder

The previous per-finger geometry (four CSG cylinder/sphere chains per
hand, hand-placed per joint) was replaced with `hand_mesh_builder.gd`,
a `RefCounted` utility providing `build_tube()` (the core technique: a
`SurfaceTool`-lofted tube along a sampled, smoothstep-radius spine,
with per-vertex radial normals set explicitly before each vertex so
lighting reads as a genuinely rounded, continuous limb rather than a
faceted cylinder stack) and two callers: `build_fingers_and_thumb()`
(a canonical hand frame, used by the world body) and
`build_finger_from_anchors()` (lofts a tube between two arbitrary,
already-existing anchor points -- used by the first-person rig, which
has its own, different arm geometry and anchor placement). Both
`player_body.gd` and `first_person_watch_rig.gd` now build their
fingers/thumb through this one shared path instead of two independently
hand-tuned CSG chains, so the two representations cannot visually drift
apart the way two separately-authored primitive chains eventually
would. `preload()` is used (not a bare `class_name` reference) because
a freshly-added script's global class is not reliably resolvable
project-wide without a prior editor scan -- the same constraint
documented elsewhere in this project for scripts that must work
identically under `godot --headless --script`.

The Skeleton3D migration question (re-asked this round, with an
explicit escape valve) was evaluated again: this project's characters
have no bone-weighted skin, no animation state machine, and no existing
rig to migrate onto -- building one from scratch, correctly, with real
weight painting and without breaking the mesh-level first-/third-person
split Round 19's watch-raise work depends on, is a multi-round
undertaking on its own, not a same-round addition on top of eight other
priorities. The blocker is architectural, not a lack of effort: this
project's meshes are procedurally generated CSG/SurfaceTool geometry
assembled fresh at `_ready()`, not imported, weight-painted assets --
Skeleton3D's value (bone-driven deformation of a fixed mesh) has no
fixed mesh to deform here yet. Per the brief's own escape valve, the
meaningful, reusable improvement actually delivered is Section B's
shared mesh-lofting architecture, not a few more primitives -- it is
the first hand/limb geometry in this project built from a real swept
surface rather than assembled CSG primitives, and it is now shared
rather than duplicated between representations. Render-verified across
both hands, both representations, multiple grip/pose states; no
regressions in `test_hand_mesh_and_mirror_fov.gd`,
`test_standing_body_composition.gd`, or `test_wristwatch_screen_stability.gd`.

## C. The Junction-Engineering doorway: a second, separate structural gap

Round 19 Section F closed one real gap (Control Room corridor to
Junction A, a z=3.2-vs-3.5 mismatch). Player feedback this round that
the walkway was "only partially fixed" led to re-investigating the rest
of that same route rather than re-touching the already-fixed segment --
a direct `PhysicsRayQueryParameters3D` sweep through the Junction's own
doorway into Engineering (the same decisive technique Round 19 used to
distinguish "real hole" from "under-lit room") found a second,
independent gap: the doorway opening itself had no header/jamb framing
at all, reading as an unbounded black void from oblique and
upward-pitched angles even though the floor/ceiling on both sides were
already continuous there. Closed by adding `JunctionEngineeringLintel`
(header) and `JunctionEngineeringJambSouth`/`JunctionEngineeringJambNorth`
(side framing) plus `Light_JunctionEngineeringDoorway`, framing the
opening the same way every other doorway in the station already is.
This is a framing/lighting fix, not a width change --
`tests/test_junction_engineering_doorway.gd` asserts floor/ceiling stay
continuous through the opening, a header-height ray now hits the new
lintel within 1m, and the clear passable width after the new jambs
remains above 0.9m (i.e. the fix did not narrow the opening). Render-
verified from 5+ angles (straight-through, both oblique approaches, a
from-below look-up at the header, and a far approach); no remaining
visible void at any tested angle. This doorway is unrelated to any of
the five historically-known capsule-clearance failures (it is a
visual-framing fix, not a width fix); none of those five entries
changed status this round (see Section I).

## D. Physical storage, part two: a second cabinet and a real filter cartridge

Extended Round 19 Section D's pattern (a real hinged cabinet gating a
physical item's own visibility/collision, never touching the item's
own pickup logic) to the filter-replacement task. Added
`FilterCartridge` (a new carryable item, `filter_cartridge.gd` --
near-identical to the existing wire component's contract:
`interact()`/`get_interact_prompt()`/`is_installed()`/`return_to_rest()`/
`place_in_world()`/`mark_installed()`) and `StorageCabinet2`, a second
instance of the same `storage_cabinet.gd` script introduced in Round 19
(door-gated visibility/collision, independent of the first cabinet).
`filter_housing_station.gd`'s `remove_old_cartridge()` now requires the
player to actually be carrying a cartridge with `item_id ==
&"filter_cartridge"` before advancing past REMOVE_OLD -- an attempt
without the part fails harmlessly and recoverably (same nonpunishing
contract as every other "missing required item" case in this project),
surfacing a distinct "No replacement cartridge on hand -- retrieve one
from Storage first" status rather than silently doing nothing. This
directly removes the "appears beside/beneath the housing" placeholder
behavior the brief named: the cartridge now has one real, physical
origin (`StorageCabinet2`, closed by default) and is consumed
(`take_carried_item_if_matches` + `mark_installed`) exactly once,
mirroring `electrical_panel.gd`'s own established consume-on-success
pattern for the wire.

`StorageCabinet2` was initially placed with its shelf/cabinet assembly
too close to the `StorageB` navigation waypoint, reopening two of the
pre-existing (not newly-broken) capsule-clearance edges
(`storage_a<->storage_b`, `storage_b<->storage_elbow_ls`); relocated
0.9m along Z to clear them, confirmed by `test_station_capsule_sweep`
returning to its known-failures-only baseline. Render-verified: cabinet
closed (cartridge hidden, no collider), cabinet open (cartridge visible
and reachable). `tests/test_storage_cabinet2_filter.gd` and
`tests/test_filter_housing.gd`'s extended REMOVE_OLD coverage both
pass; `tests/test_carry_drop.gd`'s pre-existing "no duplicate wire"
check was narrowed to the wire's own specific display name (it had been
matching ANY carryable with a `get_display_name()` method, a latent
test bug the new, second carryable item exposed rather than caused).

## E. Work-order integration: a wristwatch hint for the missing part

The wristwatch's glanced status (Round 12's deliberately terse one-line
room+action summary) previously named the task's room even when the
player could not actually do anything useful there yet -- diagnosed but
empty-handed. `wristwatch_view.gd` now checks, before formatting the
normal room+action text, whether `DayPlan.required_component_id` is set
AND the task that set it (`e05`) is still outstanding AND the player is
not currently carrying a matching item; if so it shows "GET PART /
STORAGE" instead, directing the player to retrieve the part before
heading to the work site. Deliberately gated on `e05` specifically
(not merely on `required_component_id != ""`) because that field is
never reset mid-day (`day_plan.gd`'s own `reset_for_new_day()` is the
only place it clears) -- an earlier version of this check, gated only
on the field being non-empty, would have kept showing "GET PART" even
after the repair was already complete, since the field simply lingers.
`tests/test_wristwatch_part_hint.gd` specifically exercises that
regression scenario (diagnose, confirm the hint, pick up the part,
confirm it disappears, complete the full repair, confirm the hint does
NOT reappear afterward) in addition to the straightforward cases.
Scoped to the electrical task only -- the filter task's own existing
"No replacement cartridge on hand" message (Section D) already serves
the equivalent purpose for that chain, so no second copy of this same
idea was added there. `carry_system_path` wired onto `player.tscn`'s
`Wristwatch` node; no other work-order plumbing (task IDs, DayPlan
fields, workstation screen text) was touched.

## F. Calibration/difficulty audit: no change needed

Re-audited the six-chamber 3x2 calibration layout and the global-
difficulty-vs-technician-progression split the brief asked about.
Confirmed, by reading `sensor_calibration_view.gd` directly and
re-running its full regression coverage, that Round 19 Priority 4
already implemented exactly the split this round's brief describes:
required active-fault COUNT is keyed to `_completions_this_session`
(three tiers -- `[1,2]`/`[2,4]`/`[3,6]` -- independent of difficulty),
while EASY/NORMAL/HARD exclusively governs tolerance band width,
required stability-hold duration, and coupling strength (how forgiving
a given attempt is). A HARD player with zero completions gets the same
manageable 1-2-chamber introduction an EASY player would; an EASY
player who keeps playing eventually reaches the full 3-6-chamber case,
same as HARD -- confirmed directly via
`test_sensor_calibration_layout_progression.gd`'s own forced-seed
assertions. The layout itself (a `GridContainer`, 3 columns, A/B/C row
1 and D/E/F row 2) is unchanged. No code changes were made for this
priority; this section exists to record that the audit was performed
and found the existing implementation already correct, per the brief's
own explicit instruction not to redesign a layout that is "working
well... without a clear reason."

## G. Electrical panel: cable hardware beyond the single entry bracket

Round 19 Section G added one small bracket per wire at its own entry
point. This round extends the same per-wire `VisualGroup`-parented
approach (same pivot behavior as the existing, already-verified
bracket -- no new disconnect/reconnect swing assumptions) with three
more pieces, all derived from the same `_WIRE_CURVE_POINTS` data
`_build_wire_curve()` already uses, so none of it can drift out of sync
with the actual cable path: an `EntryCollar` (a grommet ring around the
wire, oriented along its own real initial tangent via the same
`_basis_with_y()` helper the curve segments themselves use, so the
cable visibly threads through its mount instead of merely overlapping a
floating box); a `RoutingClip` partway down the run (t=0.32, well short
of the terminal end that actually swings on disconnect); and a
`TerminalCollar` at the lug end, giving the terminal connection its own
strain-relief treatment to match the entry end. A fourth addition,
`_add_bundle_tie()`, is NOT per-wire: it adds one small tie bar between
each row's one genuinely adjacent, near-parallel wire pair (backup+
ground in row A, auxiliary+relay in row B -- their entry points sit
~0.3m apart at identical height/depth, the only pair in each row close
enough that a shared tie reads as physically correct rather than
arbitrary). Deliberately parented to the diorama's own `Wires` node,
not to either wire's `VisualGroup`, so it never has to pick a side to
swing with if one of the pair disconnects while the other stays
connected -- it is panel-mounted hardware, not part of either
individual cable. All eleven electrical-system regression suites
(`test_electrical_panel_chain`, `test_electrical_repair_procedure`,
`test_electrical_repair_diorama`, the three reconnect-bug regression
tests, `test_wire_geometry`, `test_electrical_panel_terminal`,
`test_electrical_panel_hatch_visual`, `test_electrical_wire_randomization`,
`test_circuit_tracer`) pass unchanged -- this is purely decorative
geometry, never part of `ROLES`/`_collider_action`, never touched by
the disconnect/reconnect/replace logic. Render-verified via a direct
instantiation of `electrical_repair_diorama.tscn` with its own camera:
a wide shot of the full 10-wire panel, a closeup on the backup/ground
bundle-tie pair (the tie bar reads as a real mounting rail bridging two
cable glands), and a closeup on a single wire's full run from entry
collar through routing clip to terminal collar (no wire visibly begins
or ends in open space at either end).

## H. Small polish: storage and item-handling sound

Two small, physical additions, both routed through the existing shared
`mechanical_sfx.gd` procedural sound bank (the same one every focused
repair view already uses) rather than a new audio system: `carry_system.gd`
now plays a short "click" on pickup, on a plain drop, and on the
Space-drop-at-feet path -- added once, centrally, in `carry_system.gd`
itself (not in each item's own script), so every current carryable item
(wire, filter cartridge) and any future one gets it automatically;
`storage_cabinet.gd` now plays a "clunk" on door toggle, shared by both
cabinet instances since they already share one script. Both `sfx_path`
exports are optional (`get_node_or_null`, harmless no-op if left
unwired) and wired this round onto `player.tscn`'s `CarrySystem` and
both `StorageCabinet` instances in `main.tscn`. No new minigame, no new
scope beyond these two items, per the brief's own "one or two small
complementary items only" instruction.

## I. Testing and verification

The full suite was reconfirmed at 69/69 passing before this round's own
changes (matching the last reported baseline exactly), then run twice,
clean, after all nine addressed priorities (70/70 -- the one additional
test is `test_wristwatch_part_hint.gd`, Section E's own new coverage).
A headless startup smoke test (`godot --headless --path . --quit-after
3`) produced no errors both before and after. The capsule-clearance
sweep (`test_station_capsule_sweep.gd`) stayed at its known-failures-
only baseline throughout -- the five historically-known edges
(`junction_node_1<->comms_tunnel_elbow`, `comms_a<->comms_alcove`,
`comms_a<->comms_window`, `engineering_tunnel_1<->engineering_a`,
`engineering_b<->storage_elbow_e`) remain exactly as before, tracked
separately and not conflated with anything new; the one transient
regression this round's own work caused (Section D's cabinet placement
intruding on `storage_a<->storage_b`/`storage_b<->storage_elbow_ls`)
was found and fixed before being reported here, not left as a "known"
failure.

A full test-inventory audit compared every `tests/*.gd` file on disk
against `run_tests.sh`'s own registered list: the only file on disk and
not registered is `manual_verify_real_input_reconnect.gd`, which is
correct and intentional -- its own class doc comment documents that it
requires a real rendering context (SubViewportContainer GUI-input
forwarding does not function under plain `--headless`) and is kept as a
permanent, deliberately-manual artifact, not an oversight.
`test_locked_graph.gd` and `test_living_quarters_room.gd`, both named
in this round's own brief for re-checking, no longer exist on disk at
all (superseded by other, currently-registered coverage in an earlier
round); per the brief's own explicit instruction, no replacement was
invented for either, since their original intended behavior is no
longer known with confidence.

Three small, genuine regressions were found and fixed during this
round's own work (none left unresolved): the `StorageCabinet2`
placement described in Section D; a pre-existing wire-counting bug in
`test_carry_drop.gd` exposed (not caused) by the new second carryable
item, also Section D; and a watch-rig input-polling conflict between a
direct `set_raised()` call and `wristwatch_view.gd`'s own continuous
`Input.is_key_pressed(KEY_C)` poll, fixed by simulating a genuinely
held key via `Input.parse_input_event()` rather than bypassing the real
input system.

One non-blocking, cosmetic observation: calling `mechanical_sfx.gd`'s
`play_kind()` shortly before a test script's own `quit()`/scene
teardown occasionally leaves an `AudioStreamPlaybackWAV` instance
reported as "leaked at exit" in Godot's own engine-level cleanup
diagnostics (confirmed pre-existing and already present, intermittently,
in `test_electrical_panel_chain.gd` and other views that already called
`play_kind()` before this round -- Section H's new call sites in
`carry_system.gd`/`storage_cabinet.gd` simply exercise the same existing
path in two more tests). It does not affect any test's PASS/FAIL result,
and does not occur during normal gameplay (the audio server only fails
to finish its own async cleanup when the process exits immediately
after a sound starts, which only ever happens in a short-lived headless
test script that calls `quit()` right after). Not treated as a
regression to chase given its pre-existing, cosmetic, non-deterministic
nature; recorded here for completeness.

## Known limitations

- The mirror's extreme-oblique-angle frame edges still show void
  (nothing is modelled behind the wall/cabinet) -- unchanged from
  Round 19, re-examined this round and confirmed to be an honest
  limitation of the off-axis approach given this station's real hull
  geometry, not a bug (see Section A).
- No full Skeleton3D character rig -- re-evaluated this round against
  its own explicit escape valve; the architectural blocker (procedural
  CSG/SurfaceTool meshes with no fixed, weight-paintable mesh to bind a
  skeleton to) is unchanged from Round 19, and a real reusable mesh
  improvement was delivered in its place (see Section B).
- `manual_verify_real_input_reconnect.gd` remains intentionally outside
  the automated suite (requires real rendering -- see Section I).
  `test_locked_graph`/`test_living_quarters_room` no longer exist on
  disk and were not recreated (see Section I).
- The occasional "leaked at exit" audio diagnostic described in Section
  I is pre-existing, cosmetic, and does not affect gameplay or test
  results.
- As in every prior round, real-rendered verification covered the
  specific states each section's own work named, not an exhaustive
  sweep of every difficulty x state x camera-angle combination.

# ROUND 21: FIX CURRENT REGRESSIONS, A PHYSICAL FILTER-DISPOSAL LOOP, AND SIX CONFIRMED-ROOT-CAUSE FIXES

## Scope

A fix-and-polish round driven by fresh manual playtest feedback: the
mirror still felt stretchy, the reflected raised hand still looked like
cylinders, the storage cabinets added in Round 20 could not actually be
opened, the filter task had no physical used-part loop, the Control
Room passage still had a void on one side, and the in-world electrical
cabinet showed two unexplained cube blocks the minigame never did. Each
of these six items turned out to have a specific, confirmable root
cause -- none were cosmetic guesses, and in two cases (the mirror depth
tuning, the "both sides" gap) the real cause was the OPPOSITE of what
the brief's own guess suggested. Also added, time permitting: the same
lofted-tube limb treatment for the world body's LEGS (Priority 7), and
the Storage disposal container doubles as this round's Priority 8 item
(a readable, real physical disposal interaction, required anyway by
Priority 4's own loop). No commits or pushes were performed.

## A. The raised hand "still looks like cylinders": two real bugs, not one shape problem

Two genuinely separate root causes, both confirmed by reading code and
by render -- not by re-touching the geometry Round 20 already fixed:

1. **The world-body arm itself WAS still three raw CSG primitives**
   (UpperArm cylinder + Elbow sphere + LowerArm cylinder, unioned by
   the parent CSGCombiner3D) -- Round 20 only rebuilt the FINGERS this
   way. Replaced with one continuously-lofted tube per arm
   (`HandMeshBuilder.build_tube()`, the same technique/builder Round 20
   introduced), spine sampled from the SAME five anchor nodes
   (Shoulder/UpperArm/Elbow/LowerArm/Hand) the existing
   `set_watch_raise_pose()`/`animate_hand_laptop_gesture()` falloff-
   tween system already animates -- no gesture-code changes at all,
   only what gets rendered through those live, possibly mid-tween
   positions. Rebuilt only when the spine has actually changed (not
   unconditionally every frame) to avoid real per-frame mesh-resource
   churn -- confirmed directly: an early unconditional-rebuild version
   left stray RenderingServer RIDs at process exit under a
   `--quit-after` headless run; the change-detection guard (and fixing
   a separate leak where `HandMeshBuilder.build_tube()`'s returned
   wrapper `MeshInstance3D` was never freed after extracting its
   `.mesh`, since `MeshInstance3D` is a `Node`, not a `RefCounted`,
   and is not reference-counted) made both runs clean again. The watch
   was ALSO fixed to actually move with the raised hand -- see Section
   B below.

2. **The actual, dominant thing the mirror was showing was not the
   world body's arm at all.** The mirror camera's `cull_mask` had
   never been set, so it kept `Camera3D`'s own default (every render
   layer) -- including layer 2, the layer `first_person_watch_rig.tscn`'s
   `ArmGroup`/`WatchAssembly` live on. That rig is a plain child of the
   PLAYER'S OWN `Camera3D`, positioned at the eye point, meant to be
   seen only by the player's own first-person view while the watch is
   raised. With no exclusion, the mirror (and every other non-player
   camera) rendered it too -- and since it sits right at the player's
   own head position, in the mirror it appeared as a disembodied,
   literally skin-colored (its own `Mat_skin` material, never a glove)
   hand floating near the reflection's head/chest, which is what was
   actually being reported as "still looks like cylinders." Fixed by
   excluding layer 2 from the mirror camera's `cull_mask` -- the exact
   mirror image of how `player.tscn`'s own camera already excludes
   `HeadGroup`'s layer (4) so the player never sees their own head.
   A SECOND, deeper instance of the same class of bug was found while
   verifying this: the first-person rig's own finger/thumb
   `MeshInstance3D` nodes (added in Round 20) and its `WatchFaceText`
   `Label3D` were never given `layers = 2` themselves -- only the CSG
   primitives under `ArmGroup` inherit that layer for free (a
   `CSGCombiner3D` folds `CSGShape3D` children into its own one render
   instance; a plain `MeshInstance3D`/`Label3D` child does not, and
   defaults to layer 1). Those two leaks were still visible in the
   mirror (floating fingers + "NO SIGNAL" text) even after the
   cull_mask fix, until `layers = 2` was set explicitly on each.
   Render-verified: the mirror and an external diagnostic camera both
   now show a consistent, correctly dark-gloved world-body arm with no
   skin-toned or floating-text artifacts.

Regression coverage: `tests/test_hand_mesh_and_mirror_fov.gd` gained
checks for the new `ArmMeshR` architecture, the hidden old CSG arm
primitives, the mirror's layer-2 exclusion, and the first-person rig's
finger/thumb/label layer correctness; `tests/test_mirror_reflection.gd`
gained the mirror-camera-excludes-layer-2 check alongside its existing
HeadGroup-layer-4 checks.

## B. The watch "floating/clipped": a real attachment bug

Confirmed by reading `player_body.gd`: the world-body wristwatch was
built as a SIBLING of `HandR` under the pose root, at a position fixed
in the pose root's own local space -- `set_watch_raise_pose()` tweens
`HandR`'s own position (and the other arm anchors), but never touched
this sibling at all, so raising the arm moved the hand away while the
watch stayed behind at its original rest spot. Fixed by making the
watch a CHILD of `HandR` instead, at the equivalent local offset
(computed from the two poses' own previously-authored positions) --
it now inherits `HandR`'s live position for free, exactly like the
palm/fingers already did. Verified by a new regression check that
reads the watch's actual `global_position` before and after
`set_watch_raise_pose(true, ...)` and asserts it moved by a believable
amount (previously it would not have moved at all).

## C. Mirror stretch: the fix is the OPPOSITE of the brief's own suggestion

Playtest feedback suggested reducing the virtual-eye depth further to
fix the remaining "stretchy" feel. Round 20's own derivation already
on file (`mirror.gd`'s class doc comment) shows this is backwards:
`half_angle = atan(half_height / depth)` means a SMALLER depth gives a
WIDER half-angle -- exactly the same relationship that made the
original `depth=0.05` fisheye-stretched in the first place. There is
also a second, independent reason the same direction helps: the
virtual eye's total distance to the player's own reflected body is
(real distance in front of the glass) + depth, so a LARGER depth also
pushes the apparent subject distance further away, directly reducing
the near-field "selfie" perspective stretching a close-up subject gets
regardless of lens angle. Depth was raised from 0.4 to 0.8 (half-angle
~28deg -> ~14.7deg, full vertical FOV ~56deg -> ~29deg, a flattering
portrait-length framing rather than a wide-angle one) -- render-
verified at multiple distances/angles; the reflection reads noticeably
less stretched, and parallax (confirmed by the existing, unchanged
off-axis frustum math and its own regression suite) is unaffected --
only the lens angle changed, not the projection technique.
`test_mirror_reflection.gd`'s own hardcoded near-plane upper bound
(previously tuned to the old 0.4 depth) was updated to match.

## D. Storage cabinets: unreachable by any real player action

Two independent, confirmed root causes, matching the brief's two
separate complaints exactly:

1. **The door genuinely could not be opened.** `storage_cabinet.gd`'s
   `interact()`/`get_interact_prompt()` live on the cabinet's plain
   Node3D ROOT, but every collidable surface (Back/Top/Bottom/
   SideNear/SideFar/DoorPanel) is a SEPARATE child `CSGBox3D` --
   `interaction_controller.gd`'s raycast resolution required the HIT
   COLLIDER ITSELF to have `interact()`, which none of those children
   do, so `get_hovered()` always resolved to `null` and no prompt ever
   appeared; this was not a missing prompt string, it was a genuinely
   unreachable interaction. Fixed centrally, not per-cabinet: a new,
   strictly ADDITIVE ancestor-walk fallback in
   `interaction_controller.gd`'s own raycast resolution -- if the
   direct collider lacks `interact()`, walk up a bounded number of
   parents looking for one that has it. Every other interactable in
   this project already puts its script directly on the one collidable
   node, so for them the existing direct check still resolves
   immediately and this fallback never triggers -- it can only make a
   previously-dead raycast hit resolve to a real target, never take
   away one that already worked, so it carries no regression risk for
   anything that already worked. A new real-raycast regression test
   (in `test_interaction_prompts.gd`, not a direct `.interact()` call
   like the older coverage) proves the full path: aiming at the door,
   `get_hovered()` resolving to the cabinet, the real open/close
   prompt text, and the door actually opening via the resolved hover
   target's own `interact()`.
2. **The cabinets read as small boxes bolted onto the side of the big
   decorative rack, not part of it.** Both `StorageCabinet1`/`2` were
   rebuilt to share their own rack's exact footprint (0.3m wide,
   matching `StorageRack1`/`2`) as a true middle section of one
   continuous built-in unit -- each rack was split into Upper/Lower
   pieces flanking the cabinet door vertically (same combined height
   as before), so the door now sits flush within the larger unit's own
   silhouette instead of protruding past it. One real placement bug
   surfaced while doing this and was fixed before it ever shipped: the
   room's own west/east walls are THICKER than their center position
   alone suggests (their own stated half-width), so the cabinet's
   naive "match the rack's full depth" first draft put the carried
   item's resting spot PARTIALLY EMBEDDED INSIDE the real wall's own
   solid collision -- confirmed by a real raycast test hitting
   `StorageWestWall` instead of the wire, at a position matching the
   wall's own inner face exactly. Items were repositioned to the
   cabinet's genuinely clear interior band (`WireComponent` x=-7.43,
   `FilterCartridge` x=-5.57) and the whole round's test suite re-run
   clean. Render-verified: cabinet closed and open, the wire visible
   and reachable inside the now-integrated unit; `test_station_capsule_sweep`
   confirms no new navigation regression from the resize.

## E. The full physical filter disposal loop (Priority 4)

Implements the complete desired sequence as real, physical, state-
tracked steps -- not auto-completed shortcuts:

1. **`used_filter_cartridge.gd`/`.tscn`** (new): the old/dirty
   cartridge. Starts hidden and non-collidable (there is no used
   cartridge in the world until a real repair produces one) --
   `filter_housing_station.gd`'s `remove_old_cartridge()` calls its
   new `eject_at(world_transform)` the moment the old cartridge
   actually comes out (same stage-gated call that already required
   carrying the real replacement part, see Round 20 Section D),
   placing it, visible and collidable, on the Life Support floor near
   the housing. Same duck-typed carry contract as every other
   carryable in this project; a dirtier, grimier material variant of
   `filter_cartridge.gd`'s own geometry so it reads as the USED one at
   a glance.
2. **`trash_disposal.gd`/`.tscn`** (new): a labelled ("WASTE DISPOSAL"),
   hazard-striped bin in Storage, in the open walkway near the filter
   supply cabinets. Duck-typed `interact()`: carrying an accepted item
   (currently only `used_filter_cartridge`) and interacting consumes it
   via `carry_system.gd`'s existing `take_carried_item_if_matches()`
   and calls the item's own `dispose()` (a real `queue_free()` -- the
   ONE place this object is ever actually removed from the game, only
   reachable after the full carry loop); carrying nothing, or the wrong
   item, is rejected with a distinct, readable message, never a silent
   no-op. Plays the existing shared `mechanical_sfx.gd` "success" tone
   and tracks a session-only `disposed_count()`.
3. **L02's own completion gate is UNCHANGED** -- it still completes
   exactly when the new cartridge is installed and airflow restored,
   same as every prior round. The disposal loop is a parallel physical
   layer on top of that, not a new blocking requirement, preserving
   existing working gameplay per this round's own explicit instruction.

New dedicated regression coverage, `tests/test_used_filter_disposal.gd`
(21 assertions): the used cartridge stays hidden/non-collidable/prompt-
less until a real removal ejects it; ejection lands it on the floor,
visible and collidable; L02 still completes on the original gate; the
cartridge is pickable via its own real `interact()`; the disposal bin
correctly rejects an empty-handed attempt (count stays 0, no crash);
picking the cartridge back up and disposing it for real consumes it,
increments the count to 1, and the node is genuinely gone
(`is_queued_for_deletion()`), not merely hidden. Render-verified: the
ejected cartridge sitting on the Life Support floor near the housing,
and the labelled disposal bin in Storage.

## F. Control Room passage: a second, independent gap -- confirmed, not assumed

Round 19's own corridor-to-junction seal (Section F of that round) is
still intact and unchanged (reconfirmed by its own regression suite,
still passing). The player's fresh report of a remaining gap was
investigated from scratch with real `PhysicsRayQueryParameters3D`
probes (the same decisive technique established in Round 19/20) rather
than assumed to be the same spot -- and it was not: a genuinely
different, previously-unknown gap exists right at the Control Room's
own doorway (z~1.8-2.0), not at the corridor/junction boundary (z=3.5).
`ControlRoomEastWallNorth` stopped at z=1.8 while
`ControlRoomDoorwayWallEast` only started at z=2.0 -- a real,
confirmed-by-raycast 0.2m unwalled gap, floor to ceiling, on the EAST
side only. The WEST wall (`ControlRoomWestWall`) already reached
z=2.2, past the doorway, with no corresponding gap -- probed and
confirmed solid at the same z values for direct comparison. Fixed by
extending `ControlRoomEastWallNorth`'s own far Z edge to meet the
doorway wall's near edge exactly (same "extend the short side to meet
the other, don't narrow the passage" fix pattern as Round 19's own
corridor seal). `tests/test_control_room_walkway_seal.gd` gained real-
raycast checks at the gap's exact former location (now solid) plus the
same edge-continuity math check Round 19's own fix already uses.
Render-verified from the open doorway looking straight through (both
jambs now read as solid, continuous framing) and from an oblique angle
inside the former gap's own position (a solid wall column, no void).

## G. The in-world electrical cabinet's "2 unexplained cube blocks"

Root cause confirmed by a real raycast picked at the blocks' own exact
screen position (not guessed from reading code alone): `Terminal`/
`IntactTerminal` (the two independent `StaticBody3D` raycast targets
`terminal_connector.gd` provides for the damaged/intact connection
points) report `visible = true` at runtime despite being AUTHORED as
`visible = false` in `main.tscn`. The cause was `terminal_connector.gd`'s
own `set_reachable(reachable)`, called by `electrical_panel.gd`
whenever the cabinet door opens: it set `visible = reachable` ALONGSIDE
disabling/enabling the collision shape -- so the moment the door
opened, these two small, UNSCALED `BoxMesh` placeholders became
visible right next to (and noticeably cruder/larger than) the panel's
own correctly-scaled `WorldDiorama` twin, which is shown by that exact
same door-open condition and already provides the real, minigame-
matching visual. This fully explains both halves of the complaint:
"two cube-like blocks" in the normal cabinet view (exactly 2 terminal
hitboxes, exactly matching the door-open condition) and "they do not
appear in the minigame view" (the focused minigame is a wholly separate
scene instance that never touches these world-space nodes at all).
Fixed by removing the `visible` assignment from `set_reachable()`
entirely -- these nodes are, and now stay, permanently invisible
collision-only targets, matching their own class doc comment's already-
stated intent; reachability (the collision shape) is unaffected.
`tests/test_electrical_panel_terminal.gd` gained checks that both
terminals stay invisible while reachable/door-open, and that
`WorldDiorama` is the one actually-visible twin. Render-verified: the
cabinet interior now shows only the wire/terminal assembly, matching
the minigame's own presentation, with no stray geometry.

## H. Priority 7: the same lofted-leg treatment, time permitting

With the six fixes above complete and fully verified, StandingPose's
legs got the same treatment Section A gave the arms: one continuous
lofted tube per leg (hip cap -> upper leg -> knee -> lower leg ->
ankle), replacing the same class of CSG sphere/cylinder primitive chain
(confirmed in `player_body.tscn`). Unlike the arms, this is built ONCE,
not rebuilt per frame -- StandingPose's legs are never tweened by
anything in this script (only SittingPose's own get-up sequence
animates legs, a different pose, untouched here), so there is no live
anchor movement to track after the initial build from each anchor's
rest position. The Foot itself stays a plain `CSGBox3D` (a flat-
surfaced shoe silhouette was never part of the complaint, same
reasoning `_build_hand()` already applies to the palm). Render-
verified: a close, well-lit shot shows a single smooth, continuously-
tapered leg from hip through knee to ankle with no hard seam at the
knee, alongside the already-improved arm/hand/watch and torso/shoulder
silhouette in the same frame. Full regression suite re-run clean after
this addition (structural checks only this round; no dedicated new
test file -- this is a pure geometry swap using the exact same, already
-tested `HandMeshBuilder.build_tube()` path Section A's own tests
already cover).

## I. Priority 8: the disposal container doubles as this round's extra feature

Section E's `trash_disposal.gd`/`.tscn` -- a labelled, hazard-striped,
readable-prompt disposal container with real accept/reject feedback and
a session-tracked disposed count -- is both a REQUIRED part of
Priority 4's own loop and, per the brief's own Priority 8 candidate
list ("a proper space-trash/disposal container interaction with
readable prompt and feedback"), satisfies this round's "one extra
meaningful feature" on its own merits. No separate, additional feature
was added beyond this given the round's already-substantial scope
across six confirmed fixes plus the Priority 7 leg work.

## J. Testing and verification

Baseline reconfirmed clean (70/70, matching Round 20's own final
count) before this round's own changes began. Full suite run clean
TWICE after all work completed: 71/71 (the one addition is
`test_used_filter_disposal.gd`, Section E's own new coverage) --
no failures, no regressions, on both runs. Headless smoke test
(`godot --headless --path . --quit-after 3`) clean throughout, checked
repeatedly between major changes, not just at the end. The capsule-
clearance sweep stayed at its known-failures-only baseline throughout
every change this round (confirmed after the storage cabinet resize
specifically, the change with the most plausible nav-footprint impact):
the same five historically-known edges (`junction_node_1<->comms_tunnel_elbow`,
`comms_a<->comms_alcove`, `comms_a<->comms_window`,
`engineering_tunnel_1<->engineering_a`, `engineering_b<->storage_elbow_e`)
remain exactly as before, tracked separately, zero new regressions.

Six new/extended regression test files or sections this round, each
targeting the specific confirmed root cause rather than the symptom:
`test_hand_mesh_and_mirror_fov.gd` (arm-mesh architecture, mirror
layer-2 exclusion, first-person rig layer correctness, watch-moves-
with-hand), `test_mirror_reflection.gd` (mirror layer-2 exclusion,
updated near-plane bound), `test_interaction_prompts.gd` (real-raycast
storage-cabinet-door coverage), `test_control_room_walkway_seal.gd`
(the new east-doorway gap), `test_electrical_panel_terminal.gd`
(terminal invisibility), and the new `test_used_filter_disposal.gd`
(the full physical disposal loop, 21 assertions). All genuinely new
coverage proves the ACTUAL confirmed root cause, not a restatement of
the symptom.

Several diagnostic dead ends during investigation are worth recording
for future reference, since real findings came from ruling them out,
not from the first guess: the "tan arm" symptom was first suspected to
be a material/lighting bug (ruled out by an isolated-scene render with
a known-correct material, which rendered correctly) before the real
cause (the first-person rig leaking through the mirror's unfiltered
cull_mask) was found via a direct scene-tree light/layer audit; the
"both sides" Control Room gap was first probed at the ALREADY-FIXED
Round 19 corridor/junction seam (z=3.5, confirmed still solid, both
sides) before the real, different gap (z=1.8-2.0, east side only) was
found by directly probing the Control Room's own doorway instead.

## Known limitations

- The mirror's extreme-oblique-angle frame edges still show void
  (nothing modelled behind the wall/cabinet) -- unchanged, an honest
  limitation of the off-axis approach, not touched this round.
- No full Skeleton3D character rig -- unchanged from Round 20's own
  evaluation; this round's arm/leg work is the same lofted-mesh
  architecture, not a skeletal migration.
- The disposal bin currently accepts only `used_filter_cartridge` --
  deliberately narrow (reads as a specific parts-disposal point, not a
  catch-all trash can for the whole game), per this round's own
  explicit "do not add an unrelated major feature" scope discipline.
- Priority 7's leg improvement covers StandingPose only (matching
  where the mirror/reflection complaint actually lives); SittingPose's
  own legs, LyingPose, and the torso/shoulder silhouette beyond what
  Section A's arm work already touches were not further revisited this
  round.
- The pre-existing, cosmetic "leaked at exit" audio/mesh diagnostic
  under a hard `--quit-after` headless kill (documented in Round 20's
  own report) remains a known, non-blocking artifact of short-lived
  test processes; does not affect gameplay or any test's PASS/FAIL
  result.
- As in every prior round, real-rendered verification covered the
  specific states each section's own work named, not an exhaustive
  sweep of every difficulty x state x camera-angle combination; some
  camera framings attempted during investigation (e.g. a few leg/body
  angles in the tight Living Quarters bathroom) did not produce a
  usable image on the first few attempts and were re-positioned or
  replaced with a cleaner open-area shot rather than reported as
  verified from a failed attempt.

# ROUND 22: WATCH-CASE REDESIGN, THE CONTROL ROOM DOORWAY SEAM, AND SPACE-STATION STORAGE/DISPOSAL COHERENCE

## Scope

Fresh playtest feedback: the raised wristwatch still looked boxy/
oversized and non-human, the Control Room doorway still showed a
visible void near its east jamb, the Storage waste bin sat on the
floor blocking the walkway and read as an Earth trash can, and the
Storage cabinets read as flat/shallow with items pasted to the wall.
Each item's root cause was investigated before any geometry changed,
per standing instruction, and two produced real surprises: the
doorway "gap" turned out to be a grazing-angle rendering seam between
two solid, non-overlapping CSG boxes (not a hole -- a direct raycast
at the same spot always hit solid geometry), and a `.tscn` parser
fragility was discovered and fixed along the way (see below). No
commits or pushes were performed this round.

## A. Watch case: box to cylinder

The wristwatch case (both the first-person raised-hand rig and the
world-body wrist watch) was a `CSGBox3D`, which cannot read as a round
watch case no matter how its dimensions are tuned -- the "boxy/
oversized" complaint was a shape problem, not a sizing problem.
Rebuilt both as `CSGCylinder3D` (radius/height/sides/smooth_faces),
roughly 40% smaller in cross-section than the old box, with repositioned
lugs, bezel, face plate, crown, and four rim screws placed by simple
trigonometry around the case's circumference instead of the old four
square corner fasteners. Confirmed by render, both first-person and on
the world body.

## B. The Control Room doorway seam

The real geometry (`ControlRoomEastWallNorth` ending exactly where a
second piece `ControlRoomDoorwayWallEast` began) was solid -- raycasts
at the seam always hit something -- but two independent CSGBox3D
pieces meeting at an exactly coplanar edge produced a real, reproducible
dark hairline at grazing viewing angles, confirmed by render and
confirmed to vanish at a near-perpendicular angle. The fix was
architectural, not cosmetic: made the wider doorway-jamb piece
OVERLAP and fully enclose the narrower wall piece's end (rather than
merely abut it), so the narrower piece's own faces inside the overlap
are entirely interior to the wider piece's solid volume and can never
be exposed to an exterior camera angle. A first attempt (fully merging
the two pieces into one) removed the seam but caused new
`test_station_capsule_sweep.gd` regressions near a diagonal room
traversal; reverted to the overlap-enclosure design, which has zero
regressions and no seam.

A `.tscn` parser fragility was found and worked around during this
investigation: a long (~15-20 line) `##` comment block placed directly
before a `[node ...]` declaration caused that node and all its
children to silently fail to load (`Parent path '...' has vanished`,
resolving to null at runtime) with no parse error reported. Confirmed
by removing the comment, which immediately fixed it, in two unrelated
files. Going-forward project convention: avoid long multi-line `.tscn`
comments; keep any such comment short, and put detailed rationale here
in this document instead.

## C. Waste disposal: floor bin to wall-mounted hatch

The disposal container previously sat on the Storage floor almost
exactly on top of the `storage_b` movement node, reading as (and
functioning as) an Earth-style trash can blocking the walkway.
Rebuilt as a wall-mounted recessed hatch on `StorageSouthWallEast`:
dark housing, amber hazard trim top/bottom, a green status indicator,
a "WASTE PROCESSING" label plate, and a hinged flap that plays a real
open/hold/close tween on a successful disposal (adopted as this
round's one new small feature -- Priority 6 option C, "sealed
compartment treatment, latch").

## D. Storage cabinet depth (first pass)

Added a `Shelf` node inside each cabinet and increased interior depth
from 0.3m to 0.36m, with items (`WireComponent`, `FilterCartridge`)
repositioned to rest on the shelf instead of floating at the box's
vertical center. A first attempt also deepened the flanking
`StorageRack1/2Upper/Lower` pieces to the same depth, which caused
`test_station_capsule_sweep.gd` regressions on the `storage_a`/
`storage_b` movement nodes (their width-spanning front face closed
clearance from 0.35m to 0.29m, under the 0.3m capsule radius);
reverted the rack depth, kept the cabinet itself deeper, confirmed
zero regressions. This pass turned out to be insufficient -- see Round
23 Section A, which redesigns the cabinets again after further
playtest feedback that they still read as shallow.

## E. Testing and verification

Full suite (`tests/run_tests.sh`, no args) ALL PASS (71/71 at the time
this round concluded); `test_station_capsule_sweep` at the same
five-edge known baseline, zero new regressions, reconfirmed after both
the doorway overlap-enclosure fix and the cabinet depth change
specifically. Real renders (not headless/geometry reasoning alone)
inspected for: the watch case (first-person close-up and world-body),
the Control Room doorway before/after at the original grazing angle,
the disposal hatch closed/flap-open/wide-walkway shots, and both
storage cabinets open with items on the shelf.

## Known limitations carried forward

- The hand/fingers were not yet addressed this round (see Round 19/20
  for the lofted-tube finger work); the raised-watch pose's forearm-to-
  hand transition still showed a visible seam -- addressed in Round 23.
- Storage cabinet depth (Section D) was a partial fix, later found
  still insufficient by fresh playtest feedback -- see Round 23
  Section A for the real redesign.
- No full Skeleton3D character rig -- unchanged.

# ROUND 23: STORAGE CABINET REDESIGN, THE FLOATING-CARTRIDGE BUG, AND A REAL CHARACTER-POSE FIX

## Scope

Continuing directly from Round 22's working tree, with fresh playtest
feedback on three fronts: the storage cabinets still read as shallow
with the filter cartridge "half embedded in the wall," the filter
replacement loop left a second, floating, never-carryable cartridge
visible at the station after a real swap, and the raised-watch pose
still looked awkward with forearms reading too long. All three had a
specific, confirmable root cause, found by reading the actual code/
geometry rather than guessing from the symptom description alone (no
screenshots were received this round despite being referenced in the
brief; the round proceeded on the detailed written feedback, which was
specific enough to act on, and every visual claim below was confirmed
by this round's own fresh renders, not assumed from the text). This
round also added one bounded, same-technique silhouette improvement to
the torso (a lofted-sphere bridge, the same non-uniform-CSGSphere
bridging technique already proven for Round 22's TrapeziusBase). No
unrelated scope was added.

## A. Storage cabinets: real depth, correct door-swing direction, a frame and latch

Two real, separate root causes, both confirmed directly rather than
assumed:

1. **The disposal hatch had been mounted with its housing geometry
   embedded inside the solid wall slab** (an unrelated discovery made
   while investigating the storage complaint, worth recording here
   since it was the same class of mistake): the node origin sat at
   z=6.98 while the wall spans z=6.8-7.0, so most of the hatch's own
   CSG pieces were fully enclosed by the wall's own solid front face,
   invisible from the room. Fixed by moving the origin to z=7.05
   (flush/proud of the room-facing surface).
2. **The storage cabinets' real problem was never raw depth** -- the
   math shows Round 22's 0.36m interior was not dramatically shallow.
   The actual "pasted to the wall" read came from two compounding
   issues: (a) still not deep enough to feel like real recessed
   furniture, and (b) **the cabinet door opened in the wrong
   direction**. Computing the door's own swept rotation (not just
   reading the authored `door_open_degrees` value) showed both
   cabinets' open door swinging AWAY from the room and back INTO the
   solid wall/recess behind them -- the door was never visible as a
   real opening door from the player's side, which likely compounded
   the "feels like a wall niche, not a cabinet" impression. Root cause:
   wrong sign on `door_open_degrees` for each hinge's position
   (`StorageCabinet1`: -110 -> +110; `StorageCabinet2`: +110 -> -110,
   mirrored because the cabinets sit on opposite walls).

Fix: real interior depth increased to 0.55m, achieved entirely by
extending the BACK of each cabinet further into the (confirmed empty)
void beyond the station's outer hull on that side -- not by
protruding further into the room, which is what caused Round 22's
nav-clearance regression. The flanking rack sections were left at
their safe Round 22 depth (the actual source of that regression, not
the cabinet itself). Added a proud `FrameTop`/`FrameBottom` trim
bezel around each opening and a two-piece `LatchPlate`/`LatchLever`
replacing the old plain handle cube, for a real "frame, door, hinge,
shelf depth, latch" read per the brief's own explicit checklist.
Confirmed by render: both cabinets now show a visibly deep interior
behind a framed opening, with the wire coil and filter cartridge
resting on a real shelf with headroom above, and a top-down render
confirms both doors now swing outward into the room between the two
cabinets, not into the wall.

New regression test: `test_storage_cabinet_door_direction.gd` --
computes each door's actual open-position tip coordinate and asserts
it lands on the room side of its own hinge and never past the
cabinet's own back wall.

## B. The floating duplicate cartridge

Root cause: `filter_housing_diorama.gd`'s `sync_full_state()`
unconditionally set `_new_cartridge.visible = true` (and
`_old_cartridge` per-stage) on BOTH instances of the diorama scene --
the focused procedure view's own diorama, where those small decorative
props are the real interactive target the player rotates/clicks, AND
the separate, permanently-present, scaled-down `WorldDiorama` twin
that sits in the actual 3D world right next to the REAL, full-scale,
carryable `FilterCartridge`/`UsedFilterCartridge` objects. The world
twin's own cartridge meshes were never meant to double as a second
physical cartridge -- the real pickups already represent that
state in the world. Showing them there too produced exactly the
reported symptom: after a real swap, the real installed cartridge is
visible at the housing AND the diorama's own decorative "new
cartridge" prop is also sitting there, permanently, since it was never
hidden at any stage including before the player had even started.

Fix: both cartridge props are now force-hidden whenever
`world_display_mode` is true (the world twin's own flag, already used
elsewhere in the same script to disable its colliders), leaving the
focused view's own diorama instance fully unaffected. The valve and
latches are unaffected -- they have no real-world physical duplicate,
so the world twin's own small decorative copies of those remain
correctly visible as a from-a-distance status read.

Verified by driving the real procedure end-to-end through the
station's own API (isolate, open latches, retrieve+carry the real
cartridge, remove old, align+insert, close latches, restore) and
rendering the station at each stage: no second cartridge mesh visible
at any point, the real installed cartridge reads sensibly at the
housing, and the real ejected used cartridge can still be picked up
and carried to disposal independently.

New regression test: `test_filter_no_duplicate_cartridge.gd` -- 17
assertions covering the world diorama's cartridge props staying hidden
through every stage of a real procedure, while the real carryable
objects behave correctly.

## C. The raised-watch pose: a real rotation bug, not just numbers

`set_watch_raise_pose()` tweened only each arm joint's POSITION
(`UpperArmR`/`ElbowR`/`LowerArmR`/`HandR`), never any rotation. The
forearm's own TUBE mesh already re-derives its orientation live from
the joint positions each frame (`_rebuild_arm_mesh()`'s tangent just
follows wherever the joints end up), so the forearm itself always
looked directionally correct -- but `HandR` is also the parent of the
actual rigid CSG geometry (palm, fingers, the wristwatch itself, built
once in `_build_hand()`/`_build_wrist_watch()`). That whole assembly's
rotation never changed, so it kept facing exactly the way it faces at
rest (arm hanging straight down) even once dragged up near the chest --
landing with the palm/watch pointed in a direction that no longer
matched the raised forearm at all. This is very likely the actual
mechanism behind "the raised watch pose looks awkward" rather than a
pure geometry/proportion problem.

Fixed by rotating `HandR` to the shortest-arc quaternion from the rest
forearm direction (Elbow->Hand at rest) to the raised forearm
direction, tweened in parallel with the existing position tweens and
back to identity on lowering -- the same "derive orientation from the
two live joint endpoints" principle the tube mesh already uses,
applied once to the rigid hand assembly instead of continuously to a
lofted spine.

Separately, computed the actual joint-to-joint arm proportions rather
than guessing: upper arm ~0.38m, forearm ~0.30m, a ~1.27:1 ratio
already close to the real anatomical ~1.27:1 (shoulder-to-elbow
~0.186 x height, elbow-to-wrist ~0.146 x height) -- shortening the
forearm's LENGTH further would have made it read as stubby rather
than more human. The actual "too long" READ is better explained by (a)
the rotation bug above visually distorting the limb in the one pose
where it was reported, and (b) a thin, uniformly-tapered tube reading
as "stretched" regardless of its real length. Nudged `LowerArm`/`Hand`
radii up slightly (0.032/0.024 -> 0.036/0.028) for a less noodle-like
read without touching the anatomically-sound length ratio.

Also added `TorsoBridgeUpper`/`TorsoBridgeLower` -- two non-uniformly-
scaled `CSGSphere3D` nodes bridging the Chest-Waist and Waist-Hips
cylinder junctions, the same already-proven technique as Round 22's
`TrapeziusBase` (chest-to-neck). Purely additive: the existing Chest/
Waist/Hips cylinder nodes and their radii (which `test_standing_body_
composition.gd` directly asserts on) are completely untouched, so this
silhouette improvement carried zero risk to that test's existing
invariants. Confirmed by render: the torso now shows a visibly
rounder, less stepped taper from chest to waist to hips.

New regression assertions added to `test_hand_mesh_and_mirror_fov.gd`:
confirms `HandR`'s quaternion actually changes (not just stays
identity) when the arm raises, and returns to identity on lowering.

## D. Honest assessment: what's still primitive, and the real next step

The hand itself (palm + four fingers + thumb) is ALREADY a genuinely
lofted-tube mesh per finger (`hand_mesh_builder.gd`'s
`build_fingers_and_thumb()`, from Round 20) with smoothstep radius
tapering and rounded tip caps -- not raw CSG primitives. What still
reads as stiff/claw-like in a close raised-pose render is the fixed,
un-curled, parallel arrangement of four short (0.044-0.06m) finger
tubes with no per-pose variation -- a real hand curls differently at
rest vs. gripping vs. a relaxed watch-check gesture, and this
construction only ever builds one static curl. The torso is still
fundamentally three separate CSG cylinders (now bridged at the seams,
not lofted into one continuous taper the way the limbs are) -- a
genuinely smoother torso would mean replacing Chest/Waist/Hips with a
single lofted spine the same way the arms/legs/fingers already work,
which this round deliberately did NOT do: `test_standing_body_
composition.gd` asserts directly on those three nodes' own radii and
vertical-overlap relationships (chest wider than waist, hips flaring
back out, shoulder/waist/hip overlap amounts), and swapping them for a
continuous mesh would require rewriting that test's whole approach,
not just adding assertions -- a larger, riskier change than this
round's remaining time budget allowed to do safely alongside the three
primary fixes above.

**Concrete next step**: convert the torso (Chest/Waist/Hips) to the
same lofted-tube-with-interpolated-radius technique the limbs already
use (`HandMeshBuilder.build_tube()`), rewriting `test_standing_body_
composition.gd`'s torso assertions to check equivalent properties of
the new mesh (radius-at-height samples instead of discrete node
radii) rather than the current node-by-node reads. This is the
single highest-leverage remaining step toward the torso not reading as
"a stack of shapes," using an already-proven technique, not a new
risky system -- genuinely scoped for its own dedicated round rather
than squeezed in alongside this round's other fixes.

A full Skeleton3D migration remains evaluated and declined again this
round, for the same reason as every prior round: the existing sitting/
lying/laptop-gesture/leg-swing/watch-raise animation logic is built
entirely around named-node position/rotation tweens on independently-
authored pose subtrees, not bone poses -- migrating would mean
reimplementing all of that animation logic in the same round as
switching the underlying representation, which is a substantially
larger, riskier change than this round's time budget allows to ship
green and verified.

## E. Testing and verification

Full suite (`tests/run_tests.sh`, no args): 76/76 PASS (two new test
files this round: `test_storage_cabinet_door_direction.gd`,
`test_filter_no_duplicate_cartridge.gd`, plus new assertions added to
`test_hand_mesh_and_mirror_fov.gd`), reconfirmed after every major
change (cabinet redesign, diorama fix, hand rotation/torso bridge) and
once more as a final combined check before this document was updated.
`test_station_capsule_sweep`: same five known pre-existing edges,
zero new regressions -- specifically reconfirmed after the cabinet
depth increase, since that was the exact change that caused a
regression in Round 22 before the back-extension approach was chosen
instead of a room-ward extension.

Real renders (not headless/geometry reasoning alone) inspected for:
both storage cabinets open (depth, shelf, item placement, frame/latch
detail), a top-down shot confirming both doors swing outward into the
room, the disposal hatch re-confirmed undisturbed by the nearby
storage changes, the filter procedure at four stages (before, old-
cartridge-removed, new-cartridge-installed, final) confirming no
duplicate cartridge at any point, the raised-watch pose close-up and
wide shot, and a (dimly, single-sided lit) mirror-reflection shot of
the raised pose for a real reflected view, not just a direct camera.

## Known limitations

- The hand still reads as stiff/claw-like in a close raised-pose view
  (Section D) -- a lofted-tube mesh, not raw primitives, but with no
  per-pose curl variation.
- The torso remains three separate CSG cylinders, now bridged at the
  seams but not a single continuous lofted taper like the limbs --
  Section D names the concrete next step and the specific blocker
  (the existing composition test's node-by-node assertions would need
  rewriting, not just extending).
- No full Skeleton3D character rig -- unchanged, evaluated and
  declined again this round for the reason given in Section D.
- No screenshots were actually received this round despite being
  referenced in the brief; proceeded on the detailed written feedback
  instead, which was specific enough to act on, and confirmed every
  visual claim via this round's own fresh renders rather than assuming
  the text description matched what a screenshot would have shown.
- The mirror render captured for Section C's raised-pose check was
  dim/single-sided lit (a diagnostic-light placement limitation, not a
  gameplay lighting issue) -- the clearer, better-lit direct-camera
  renders were the primary basis for this round's visual assessment of
  body/watch quality, with the mirror shot as supplementary
  confirmation that the same geometry reads consistently reflected.

# ROUND 24: REAL STORAGE DEPTH, THE DUPLICATE-CARTRIDGE ROOT CAUSES, A LARGER MIRROR, AND CHARACTER SILHOUETTE

(Documented retroactively in Round 25, alongside the checkpoint commit that
first records this work.)

## Root causes and fixes

- **Storage cabinets too shallow / contents clipping the wall.** Both cabinet
  shells extended behind the Storage room's wall face, but
  `StorageWestWall`/`StorageEastWall` were single solid slabs, so the wall
  itself filled the back of each cabinet (visible "back" only ~0.2 m in;
  wire and filter embedded in it). Each wall is now split into four pieces
  around a real opening (`StorageWestWall`, `...North`, `...BelowCabinet`,
  `...AboveCabinet`, same for East), and each cabinet is a 0.62 m-deep
  recessed locker in the hull void. Items sit mid-shelf; the wire coil
  (which floated 3.5 cm above its shelf because its collision box is taller
  than the flat coil) now rests on it. Doors still swing outward.
- **Floating duplicate filter cartridge** (three causes, all proven by
  running the new test against the old code):
  1. `filter_housing_station.gd` seated the real cartridge at a hard-coded
     `Vector3(0, -0.6, 0)` -- 0.6 m below the station, in open air -- and
     `filter_cartridge.gd`'s `mark_installed()` left it visible. It now goes
     inside the housing tube and is hidden, mirroring the wire's contract.
  2. `storage_cabinet.gd` re-applied visibility/collision gating to every
     listed item on every door swing regardless of where the item was:
     closing the cabinet hid the cartridge in the player's hand, and
     re-opening it resurrected an installed cartridge as a visible copy
     (same for an installed wire). Gating now applies only to items still
     physically stowed (`is_item_stowed()`).
  3. The world housing was a 0.3-scale model whose tube (r 0.039 m) could
     not hold the real cartridge (r 0.074 m). Now 0.6 scale (r 0.078 m),
     mounted flush to the wall; filter station moved to z 10.33, valve
     station to z 11.45; a 0.3 m void gap in `LifeSupportEastWall` behind the
     station was closed.
- **Mirror enlarged** 0.50 x 0.42 -> 0.56 x 0.90 m, extended down toward the
  basin (bottom at 1.08 m, clear of the faucet). `mirror.gd` now reads the
  portal extents and feed resolution from the glass node itself.
- **Character silhouette** (standing pose + head): head raised to sit
  around the eye line (it had been entirely below it), ovoid skull + jaw +
  wraparound visor + headset pads, shorter/thicker neck + collar, flatter
  sloped shoulders, elliptical torso cross-sections, higher tessellation;
  head group no longer casts shadows (cannot occlude the flashlight).
- **Additions:** live stock placards on the cabinet doors (QTY 1 / QTY 0 --
  RESTOCK), retaining hardware (strap + posts for the wire, clamp ring for
  the filter, shelf lips), interior cabinet lamps (on while open) and
  stencils.

Tests: new `test_storage_cabinet_depth.gd`; rewritten
`test_filter_no_duplicate_cartridge.gd` (asserts the exact visible set of
cartridge representations at every step); mirror test checks the real
glass size. Full suite 77/77; capsule sweep 38 edges, 5 known, 0 new.

# ROUND 25: A REAL WATCH-INSPECTION POSE, FIRST-PERSON/WORLD SEPARATION, AND RIG MIGRATION PREP

## A. Root cause of the "unnaturally long" reflected arm

Measured with a diagnostic that reads the actual StandingPose joint
positions (body space: eye at origin, -Z forward, +X right) at rest and
while C is held -- not inferred from screenshots:

| measurement | rest | old raised |
|---|---|---|
| shoulder -> elbow | 0.377 m | **0.143 m** |
| elbow -> wrist | 0.300 m | **0.193 m** |
| elbow interior angle | 159.5 deg | 132.7 deg |
| forearm direction | down | **(-0.35, -0.08, -0.93): straight forward** |
| watch face vs eye | -- | 131 deg off |

The old `set_watch_raise_pose()` never rotated anything. It *translated*
each arm anchor toward one fixed hand target by a different fraction
(UpperArm 0.2, Elbow 0.5, LowerArm 0.75, Hand 1.0) with the shoulder fixed.
Answers to the diagnosis questions:

1. The shoulder did not rotate; 2. the upper arm did not follow any
rotation -- it was squashed (0.377 -> 0.143 m) as its two ends were
translated by different amounts; 3. the elbow barely bent; 4. the forearm
did not keep its length (0.300 -> 0.193 m, varying mid-tween); 5. the wrist
stayed attached (the hand is the tube's end anchor); 6. the watch followed
the hand; 7. **yes, a transform was inherited twice**, in the watch: its
`Bezel`/`FacePlate`/screws were children of a `WatchCase` already rotated
90 deg about X and each carried its own 90 deg X rotation, so the dial discs
lay along the forearm (face axis (0, -1, 0) at rest), slicing through a
case that itself sat *inside* a 0.062 m-radius cuff on a ~0.03 m-radius
forearm; 8. the apparent length was **transform/animation**, compounded by
geometry: with the upper arm collapsed into the shoulder and the forearm
pointing straight at the glass, the mirror showed one long limb thrusting
out of the shoulder. Camera projection was not the cause (the mirror's
off-axis frustum was unchanged and correct).

Separately documented, deliberately NOT changed this round (the brief
forbids fixing this by shortening limbs or scaling the body): the rest
proportions are off -- shoulders 0.335 m below the eye (anatomically
~0.20 m), upper arm 0.377 m / forearm 0.300 m (~18% long for this
stature), fingertips at roughly knee height. This belongs to the rig
migration (Section F), whose prototype already uses anatomical values.

## B. The new shoulder / elbow / wrist pose

`player_body.gd` `_setup_watch_raise_rig()` / `_apply_watch_raise(p)`:

- **Raised target** solved once by analytic two-bone IK: wrist at body
  (0.0, -0.42, -0.40), elbow pole (1, -0.4, -0.3) (out, slightly down and
  forward). Both are exported (`watch_wrist_target`, `watch_elbow_pole`).
  Result: forearm lies across the chest rising 14 deg, elbow out and
  forward at lower-chest height, 13 cm clearance from the chest.
- **Shoulder:** the upper-arm segment (ShoulderR -> UpperArmR -> ElbowR,
  plus the deltoid cap `ShoulderCapR`, which previously stayed behind as a
  floating sphere) rotates rigidly about the fixed shoulder point
  (quaternion slerp between rest and raised limb frames).
- **Elbow:** the forearm hinges about the elbow axis (upper-arm x forearm
  normal); flexion interpolates 20.5 -> 109 deg (interior 159.5 -> 70 deg).
- **Wrist:** the forearm then rolls (pronates) about its own axis by the
  angle that turns the watch face toward the eye; HandR (palm, fingers,
  watch) takes exactly the forearm's rotation.
- **No 180-degree twist:** the first version needed a -173.5 deg roll
  because the standing hand rested fully supinated (palm forward). A
  relaxed standing hand hangs neutral (palm toward the thigh), so both
  standing hands now rest pre-rotated 90 deg about their forearm axis; the
  visible pronation during the gesture is -89 deg and the watch face ends
  7 deg off the eye line.
- **Sequencing:** one progress value is tweened; the shoulder leads
  (smoothstep 0..0.8), the elbow flexes almost with it (0.05..0.85 -- a
  shoulder-only lead swung the wrist 0.54 m out into a forward reach), the
  wrist rolls last (0.4..1.0). Release runs the same path backwards from
  wherever the pose currently is. World duration = first-person duration
  x 1.5 (0.42 s at the 0.28 s default).
- **Watch rebuilt:** one frame per watch (local +Y = face normal on the
  dorsal forearm, +Z up the forearm), strap radius = arm-tube radius + 3 mm,
  every dial part an unrotated child. Applied to the sitting pose's watch
  too.

## C. Limb lengths

Forward kinematics from rotations only: shoulder->elbow 0.377 m and
elbow->wrist 0.300 m are constant to < 0.5 mm at every sampled frame of
the real C-key tween (74 samples, max error 0.00000 m), and the joints
return exactly to rest on release.

## D. First-person vs world body

- The camera-relative first-person rig (`first_person_watch_rig.tscn`,
  layer 2, excluded from every non-player camera) is unchanged: readable
  "CHECK IN / CONTROL ROOM" face, stable framing. (It has the same
  doubly-inherited Bezel/FacePlate rotation; its readable display is the
  separate `WatchFaceText` Label3D, so it was left untouched as instructed.)
- New: while the watch is raised, the WORLD body's right forearm tube and
  every hand/watch visual move to the head's mirror-only layer (4: hidden
  from the player's own camera, rendered by the mirror and surveillance).
  Renders showed that looking down with C held previously displayed both
  the first-person rig's hand and the world glove beside it. Standing
  `HandR` became a plain `Node3D` (not a CSG child merged into the torso
  combiner) so its palm/watch can carry their own layer. At rest the arm
  returns to the default layer.
- No torso rotation, no limb stretching, no FOV or camera-distance change;
  the player's position is unchanged while holding C.

## E. Rendered verification (Godot `--write-movie`, frames inspected)

Captured with `--write-movie ... --fixed-fps 30` driving the real KEY_C
input path; stills saved per step (player POV, raw mirror feed, external
front-three-quarter and side cameras placed in the body's own frame):
rest, half-raised, fully raised, mirror front, mirror three-quarter,
first-person, look up, look down, lowering, rest again -- before and after.

- Before: mirror showed the forearm thrusting forward out of a shoulder
  stub; first-person look-down showed the world glove behind the rig's hand.
- After: mirror and external views show the upper arm swinging out/forward
  from the shoulder, a clearly bent elbow, the forearm across the chest,
  the watch face up on a strap that wraps the wrist; first-person shows
  only the rig's readable watch looking level/up/down; release returns to
  a symmetric neutral rest.

## F. Character rig migration plan

Dependency inventory (this round):
- Outside `player_body.gd`, only two body node names are used: `LapAnchor`
  (`sleep_state.gd`) and `CarryAnchor` (carry system).
- Public API used by gameplay: `set_sitting`, `set_lying`, `is_sitting`,
  `is_lying`, `set_watch_raise_pose`, `animate_hand_laptop_gesture`,
  `swing_leg_to_floor`, `lean_forward`, `reset_get_up_pose`.
- Tests referencing body internals: 16 files; heaviest
  `test_hand_mesh_and_mirror_fov` (21 refs), `test_sitting_pose` (11),
  `test_standing_body_composition` (9), `test_mirror_reflection` (7),
  `test_lying_body_transform` (7).

Gameplay behaviour vs implementation-specific assertions:
- Keep (behaviour): first-person composition (nothing visible at pitch 0,
  no body part near frame centre), head hidden from own camera but seen by
  mirror, watch raise reversible with constant limb lengths, pose changes
  reversible, sitting hand reaches the laptop, mirror isolation of the
  first-person rig, lying/sitting transforms.
- Rewrite at migration (implementation): `StandingPose is CSGCombiner3D`,
  CSG node names/radii (`Chest`/`Waist`/`Hips` radius taper,
  `ShoulderL.radius` gap), "old CSG arm primitives hidden", `ArmMeshR`/
  `FingerIndex` lofted-tube checks.

Plan:
1. `CharacterVisual` scene: `Skeleton3D` with SkeletonProfileHumanoid bone
   names + skinned low-poly technician mesh + `BoneAttachment3D`s for the
   watch (RightLowerArm), carry (RightHand) and lap anchors; head/neck
   meshes on render layer 4.
2. `PlayerBody` keeps its public API and becomes an adapter driving bone
   rotations (watch raise = this round's joint-space solve, already
   rotation-based; sit/lie/get-up as AnimationPlayer clips or bone poses).
   Movement controller and collision capsule stay authoritative and are
   never driven by the visual.
3. Swap behind a flag; port the behaviour tests to bone queries; delete the
   CSG-specific assertions only once their behavioural replacements pass.
4. Walking: AnimationTree locomotion blend driven by movement speed.
5. Second player: the same `CharacterVisual` instanced without the
   first-person rig, driven by replicated pose state.

Prototype added (not wired into the game):
`scenes/dev/rigged_technician_prototype.tscn` /
`scripts/dev/rigged_technician_prototype.gd` -- a real `Skeleton3D` (22
humanoid-profile bones), a procedurally generated rigidly-skinned stand-in
mesh with anatomical proportions (eye 1.64 m, upper arm 0.31 m, forearm
0.25 m), and the same watch-inspection gesture posed purely through bone
rotations. Rendered at rest / mid / full: the skinned mesh deforms with the
bones. Covered by `tests/test_rigged_technician_prototype.gd`.

## G. Tests

New: `test_watch_raise_pose.gd` (real C input; lengths sampled through the
tween; shoulder rotation; elbow flexion; forearm not pointing at the
mirror; deltoid follows; watch attached; no 180 twist; face toward eye;
single watch; body visible and unmoved; layer isolation of the first-person
rig and of the raised world arm; reversible; mid-raise reversal
continuous and monotonic; sitting/lying reset and no-op) and
`test_rigged_technician_prototype.gd`. Updated
`test_hand_mesh_and_mirror_fov.gd` ("returns to identity" -> "returns to its
captured rest orientation", the actual intent, since the rest hand is now
neutral). Runner: 79 tests (80 scripts on disk; the one exclusion,
`manual_verify_real_input_reconnect.gd`, is manual-only by its own
documented design -- needs real rendering -- and was run this round under
`--write-movie`: PASS). Results of the two full runs are recorded in the
checkpoint commit message and the Round 25 report.

## H. Known limitations

- Rest proportions remain off (Section A); fixing them inside the CSG body
  would break first-person composition assumptions -- deferred to the rig.
- The hand is rigid: no finger curl or wrist extension during inspection.
- The first-person rig is a bare-skin forearm while the world body wears
  dark gloves; its own watch keeps the doubly-inherited dial rotation
  (masked by its Label3D face).
- The rig prototype's mesh is a rigidly skinned stand-in (visible seams);
  it is a staging step, not an asset.

## I. Git checkpoint

One local commit records Rounds 24-25 (storage depth, duplicate-cartridge
fixes, mirror, character silhouette, watch-inspection pose, rig prototype,
tests, this documentation). Excluded: `CLAUDE.md.save` (editor backup),
render outputs (scratchpad only), `tests/.last_run.log` (gitignored).
Not pushed.

# ROUND 26: SHARED LOOK/POSE STATE -- HEAD LOOK, PITCH-AWARE WATCH POSE, AND FIRST-PERSON TORSO CLEARANCE

## A. Root cause (verified, not assumed)

The mirror was not broken. The two character representations ran different
pose rules:

- **First-person watch rig** (`first_person_watch_rig.gd`): a plain child of
  Camera3D, so it followed 100% of camera pitch.
- **World body** (`player_body.gd`): rotated as ONE rigid piece by 30% of
  camera pitch about the eye (`standing_pitch_follow = 0.3`) -- pelvis and legs
  included (logged: 23.4 deg whole-body tilt at a 78 deg downward look). It had
  no head/neck look response of its own.
- **Raised watch arm**: one fixed body-space target, independent of pitch.

So the mirror showed the same frozen gesture whatever the player did, while
the first-person watch moved with the camera. Separately, the first-person
torso clipping: the camera-locked forearm enters the frame from BELOW the
camera, which is where the player's own chest is. Measured by testing every
rig sample point against the actual StandingPose primitives: 2 points inside
the body at level, 131 at 45 deg down, 222 at 60 deg down. Counter-rotating the
rig enough to clear the torso needed 40-70 deg, pushing the watch 17-41 deg
above view centre (unreadable) -- not a viable fix on its own.

## B. Shared look/pose architecture

`scripts/player/character_pose_state.gd`, node `Player/PoseState`
(process_priority -100, so it runs before every consumer):

- **Inputs, read each frame from the authoritative sources** (it is not a
  controller): look yaw/pitch from LookPivot/PitchPivot, posture
  (standing/sitting/lying) and watch weight (0..1) from PlayerBody.
- **Outputs, engine-agnostic angles**: `spine_pitch`, `neck_pitch`,
  `head_pitch`, and `watch_pitch_bias` (look pitch clamped to +/-60 deg). No
  CSG node or bone names.
- `distribute_look_pitch(pitch, posture)` is a pure static function.
  Standing: spine 20% (limits -15..+8 deg), neck 60% of the rest (-45..+40),
  head the remainder (+/-25). Head overflow is handed back to the neck, so the
  shares sum to the look pitch over -80..+73 deg. Sitting: no spine share.
  Lying: head nod only (-10..+20 deg).
- `to_dict()` / `from_dict()`: the compact replicable form
  {yaw, pitch, watch, posture}. A remote peer derives the same joint angles
  with no camera (`remote_driven`).

Consumers: the world body (`process_priority` 0), the first-person rig
(`process_priority` 10, so it reads the world arm after the body has posed
it), and the Skeleton3D prototype (`apply_pose_state(dict)`).

## C. World body: head/neck and watch pose

- `standing_pitch_follow` default 0.3 -> 0: the body stays upright; pelvis,
  legs and capsule are unaffected by look pitch.
- HeadGroup restructured: `Collar` stays on the torso; `NeckPivot` (neck base)
  and `NeckPivot/HeadPivot` (skull base) are plain Node3D pivots whose CSG
  children render on layer 4 with no shadows. Rotating them is a transform
  change, not a CSG rebuild. The neck pivot carries spine + neck pitch (the
  CSG torso is one boolean union and cannot bend cheaply); the head pivot
  carries head pitch.
- Watch pose: `watch_target_for_bias()` adds a bounded offset to the wrist
  target. Looking up adds at most +0.12 m up and 0.03 m forward; looking down
  lowers it at most 0.06 m; nothing beyond +/-60 deg. The same two-bone IK
  re-solves (only when the bias changes by > 0.002 rad), so limb lengths, the
  shoulder pivot and the elbow hinge are preserved by construction. The
  forearm roll is re-derived so the face keeps turning toward the eye.
  Press/release and mid-animation reversal are unchanged (the progress tween
  from Round 25).

## D. First-person vs world

- Level and upward looks: the first-person rig keeps its authored camera
  framing (readable, stable; transform identity).
- Looking down (blend from -10 to -40 deg, scaled by the world arm's raise
  progress): the rig converges on the world arm's real pose. The watch goes to
  the world watch position in front of the chest, the forearm aligns with the
  world forearm (coming in from the elbow out to the side, not up through the
  chest), and the face is turned to the camera. The face is also spun 70% of
  the way toward level text, bounded by the torso-clearance test.
- Per-camera visibility: with the body upright, the eye sits directly above
  the shoulder yoke (this body's torso is centred ~7 cm in front of the eye).
  A downward glance therefore filled the frame with a grey dome at ~0.3 m. The
  near-eye upper torso (TrapeziusBase, ChestYoke, ShoulderL/R, ShoulderCapL,
  Chest, ChestPocket, AccentStripe, plus the right deltoid mesh) now renders on
  the mirror-only layer 4, like the head and collar. The original CSG nodes
  stay as hidden anchors; their visual duplicates live in
  `StandingPose/SelfHiddenTorso/UpperTorso`. The player's own downward glance
  shows belt, hips, legs and arms; the mirror, surveillance and any other
  camera see the complete body.
- The right deltoid was a CSG sphere in the torso union, visible to the
  player's own camera while the arm was raised (the grey ball the first-person
  sleeve passed through). It is now a mesh (`DeltoidR`) following its hidden
  anchor.
- No arm scaling, FOV, camera-distance or movement-tuning change. The body is
  not moved or rotated.

## E. Rendered verification (Godot `--write-movie`, frames inspected)

Matrix: C released level; C held at level, 30/60 deg up, 30/60/78 deg down,
yaw left/right; mid-transition up->down; release while looking down (mid and
settled); sit/stand then inspect again. Each captured as player POV, raw
mirror feed, and an external body-relative side camera, before and after.

- Before: the world body leaned as a rigid unit; its head did not look
  anywhere independently; the raised arm was frozen relative to the torso. At
  60 deg down, the first-person watch sank into a large grey shoulder/yoke dome.
- After: the body is upright and planted. The head and neck bow when looking
  down (the side view shows a natural reading posture) and tilt up when
  looking up; the watch arm lifts modestly when looking up. First person: no
  dome and no torso intersection; the forearm comes in from the right toward
  the world elbow; the watch is readable at level/up and visible at 60 and
  78 deg down. Releasing C mid-look-down blends back without snapping. Yaw
  turns the whole upright body; inspection works again after sit/stand.

## F. Skeleton3D migration compatibility

`rigged_technician_prototype.gd` gained `apply_pose_state(dict)`, taking the
exact replicable dictionary. The spine share is split over the Chest and
UpperChest bones, then Neck and Head bones; the watch weight and bounded bias
re-solve and pose the arm bones locally under the shoulder chain, so a
bending spine carries the arm. `head_forward()` exposes the look direction.
Verified by test: driven purely from a `from_dict()` state with no camera,
the skeleton's head looks down/up and the arm raises. The live CSG body is
unchanged as the playable character until the rig is visually validated.

## G. Tests

- New `tests/test_look_pose_sync.gd`:
  - state transmission and process order;
  - anatomical limits and that the shares sum to the look pitch;
  - lying nod;
  - world head responds down/up/level;
  - no whole-body tilt; pelvis/feet planted; collar fixed;
  - raised watch at -60..75 deg: constant lengths, elbow/wrist in front of the
    chest, elbow bent, bounded up/down adjustment;
  - first person: identity at level, 0 torso hits at 30/45/60/78 deg down,
    watch converges on the world watch at 60 deg down within the view;
  - layer isolation (rig layer 2; raised arm, deltoid, upper torso and head
    on layer 4);
  - release while sweeping the look is monotonic; presentation returns to
    identity;
  - sitting/lying posture and bias;
  - replicated dictionary drives the Skeleton3D prototype.
- `tests/test_standing_body_composition.gd`: the pitch-sweep invariant was
  rewritten against what the player's camera actually renders, keeping its
  intent (no near geometry fills the view, nothing visible at level). It no
  longer asserts on hidden anchor positions, which was only satisfiable by
  tilting the whole body. New checks: the upper torso still exists for the
  mirror; the lower body stays self-visible; the body never tilts.

## H. Remaining limitations

- The CSG torso does not bend; its spine share is carried at the neck base
  (the Skeleton3D prototype bends Chest/UpperChest).
- In first person the near-eye upper torso is hidden. Looking straight down
  you see belt/hips/legs/arms, not your chest. This is a deliberate per-camera
  rule; the underlying cause is this body's torso sitting ~7 cm in front of
  the eye (Round 25 proportions note), to be corrected by the rigged
  character.
- At 70-80 deg down the first-person watch sits high in the frame (still
  visible); real people rarely read a watch that steeply.
- The first-person forearm is still a bare-skin rig; the world arm is gloved.
- No yaw-only head turn: the head follows pitch; body yaw follows the camera
  as before.
- No networking implemented; only the replicable state form exists.

## I. Git

Round 25's local commit `b927d7a` is preserved and still unpushed. Round 26
changes are uncommitted in the working tree (no commit authorized for this
round).

# ROUND 27: ONE SHARED WATCH POSE -- FIRST PERSON AND MIRROR SHOW THE SAME ACTION

## A. Root causes

1. **Two rules, by design (Round 26).** The world arm reacted only a little to
   look pitch: a bounded +/-60 deg bias, at most +12 cm up and -6 cm down, so
   the mirror looked nearly static. The first-person rig followed the camera
   fully at level/up and converged on that nearly static world arm only when
   looking down. Looking up, the first-person watch rode with the camera while
   the mirror arm barely moved; looking down, the first-person watch drifted
   across the screen toward a static arm. The playtest symptoms followed
   directly.
2. **Strict 1:1 above eye level read as a wave** (rendered): holding the watch
   at a fixed view-relative direction while looking up 60 deg puts the hand
   20+ cm above the eye -- overhead.
3. **The hand always continued the forearm's line, and the elbow pole always
   pointed down**, so high or level holds stood the forearm up with the
   fingers pointing up past the face ("covering the mouth", later "salute").
4. **A sign error in the first wrist-flexion attempt:** rotating about
   (forearm x up) by a positive angle turns the hand toward up, so the
   "levelling" bent the fingers further up. Caught by render; a regression
   check now covers it (verified to fail with the wrong sign).

## B. The shared rule (single source of truth)

`CharacterPoseState.watch_target_for_pitch(pitch)` gives the wrist target in
body space (eye at origin):

- **Elevation** = look pitch - 32 deg (1:1), clamped to [-52 deg, 0 deg]:
  - -52 deg: below that the chest is in the way, so the arm holds and the head
    bows (from about 20 deg down);
  - 0 deg: eye level; above that the arm holds in front of the face and the
    head looks up (from about 32 deg up). No overhead wave.
- **Distance**: 0.50 m, up to 0.56 m when low (chest clearance), 0.46 m at
  eye level.
- The world arm two-bone-IK-solves to it each time it moves more than 1 mm.
- The first-person rig is ALWAYS the world arm's pose (watch position, forearm
  direction, face to camera), plus a constant +9 deg framing lift about the
  eye. The lift keeps the bigger first-person watch off the frame's bottom
  edge and fades out below -30 deg, where the arm no longer follows. Its
  raise/lower motion is the world arm's own animation; it stays shown until
  that arm is fully down.

Additions in the world arm:

- **Clavicle**: the shoulder pivot lifts by at most 2.5 cm up and 1 cm forward
  when the watch is held high.
- **Elbow pole**: rises toward shoulder height for high holds, so the forearm
  lies across in front of the face.
- **Wrist flexion**: the hand bends 60% back toward horizontal (cap 35 deg).
  The watch is counter-rotated so it stays fixed on the forearm (distances to
  wrist and elbow unchanged).

## C. Measured (body space)

| look pitch | wrist y | first-person watch from view centre |
|---|---|---|
| -78 | -0.44 (holds) | 25 deg above |
| -60 | -0.44 (holds) | 7 deg above |
| -30 | -0.44 | 14 deg below |
| 0 | -0.28 | ~22 deg below |
| +30 | -0.02 (eye level) | ~21 deg below |
| +60 | -0.02 (holds) | below the view |

The wrist travels 42 cm between 30 deg down and 30 deg up, a large, readable
mirror motion. Upper arm 0.377 m and forearm 0.300 m are exact at every pitch;
0 first-person torso hits at every pitch.

## D. Character presentation

The first-person forearm is now the same uniform-grey coverall sleeve and the
hand the same dark work glove as the world body (it was bare skin), so the
player sees the same arm the mirror and other players see. Geometry
unchanged.

## E. Rendered verification (`--write-movie`, frames inspected)

Matrix: C released level; C held level, 30/60 deg up, 30/60/78 deg down, yaw
left/right, mid up->down transition, release while looking down (mid and
settled), sit/stand then inspect, oblique mirror view at 30 deg down and
35 deg up. Each captured as player POV, raw mirror feed and an external side
view, compared against Round 26's final frames and the intermediate passes
(wave, salute and finger-sign issues were found and fixed this way).

## F. Remaining limitations

- Looking up more than ~45 deg with C held, the watch is below the first-person
  view (by design: the mirror shows it held at eye level while the head looks
  up; it does not magically ride with the camera).
- At 70-80 deg down the watch sits high in the frame.
- The first-person watch is still a larger, separately modelled viewmodel
  (10 cm face) than the world watch (4 cm); same position and motion,
  different scale, for readability.
- The CSG torso still does not bend; the hand is rigid (no finger curl).

## G. Tests (Round 27)

- `test_look_pose_sync.gd` rewritten for the shared rule:
  - wrist rises monotonically with pitch;
  - it moves clearly between 30 deg down and level, and between level and
    30 deg up, reaching eye level;
  - it holds above eye level (no overhead wave) and holds below the chest
    limit;
  - the wrist sits at the shared target elevation at every pitch;
  - the first-person watch equals the world watch plus the framing lift at
    every pitch;
  - first-person framing stays steady from level to 30 deg up, and at 60 deg
    up the player looks above the held watch;
  - fingers are never bent further up than the forearm (verified to FAIL with
    the old flexion sign);
  - elbow/wrist stay outside the torso and clear of the head;
  - the rig hides once the world arm is fully down.
- `test_watch_raise_pose.gd`: the shoulder may lift by the bounded clavicle
  amount (<= 3 cm); the watch must stay fixed on the forearm (distances to
  wrist and elbow); the level elbow bound is < 95 deg.
- `test_wristwatch.gd` / `test_wristwatch_screen_stability.gd`:
  - the rig now stays shown until the world arm finishes lowering (0.42 s),
    so the release waits allow for it;
  - frustum containment is asserted from -60 to +20 deg, where the watch is
    held in view;
  - at 60/75 deg up the rig must be in front of and below the view (the
    deliberate Round 27 contract; the old "watch glued in view at every
    pitch" assertion was the inconsistency the playtest reported).

# ROUND 27 FOLLOW-UP: EXTREME DOWNWARD LOOK WITH THE WATCH RAISED

## A. Diagnosis (measured from the player's own camera)

Bounding-box projection proved too crude, so the measurement used rendered
pixel differences (full frame vs body hidden vs first-person arm hidden),
C held. Before the fix, body pixels covered 33% / 37% / 31% of the
lower-centre region at 60 / 75 / 80 deg down.

1. **Which parts were visible:**
   - the top of the still-self-visible torso (belly bridge, waist, belt,
     pelvis cylinder) as a flat-topped grey disc, because the chest above it
     was already hidden from the player's camera;
   - the shoulder-end caps of the hanging arm tubes as floating stumps about
     0.35 m from the eye (their shoulders were hidden).
2. **Torso too far forward relative to the camera: yes.** This body had its
   torso centred 7-10 cm in front of the eye; a real person's eyes are about
   10 cm in front of the neck/torso axis. Looking straight down therefore
   looked onto the top of the belly and shoulders.
3. **Did the watch target keep diving: no.** The world wrist already holds
   still from about 20 deg down (the -52 deg elevation chest limit).
4. **Was the forearm path camera-driven: yes.** Round 26's text-levelling
   spun the WHOLE first-person arm about the face normal. At steep downward
   looks that swung the forearm off the real forearm line until it came up
   nearly vertically from the lower right, reading as a camera-attached prop.

## B. Fixes

- `StandingPose` and `HeadGroup` sit 0.10 m behind the eye (anatomical
  placement). Only the visuals moved: the camera, collision capsule and the
  CarryAnchor/LapAnchor are unchanged. IK targets and the eye are converted
  into pose space.
- No more arm spin. The first-person arm stays exactly on the world forearm;
  only the watch's text label auto-levels about its own face normal, like an
  auto-orienting display.
- Legs-only self view: the belly bridge, waist, belt and pelvis cylinder join
  the near-eye chest/shoulders on the mirror-only layer, and both standing
  arms/hands are mirror-only (standing `HandL`, like `HandR`, became a plain
  Node3D so its palm can carry a layer). The player's own camera sees thighs
  and feet, plus the first-person watch arm while C is held. The mirror and
  every other camera see the complete body.
- Watch hold distance re-tuned for the new body placement: 0.42 m from the
  eye (about 0.3 m in front of the chest), 0.52 m at the lowest hold, 0.40 m
  at eye level. The level elbow is 85 deg, versus 97 deg after the move alone.

## C. Result (pixel coverage of body in the lower-centre region, C held)

| look down | before | after |
|---|---|---|
| 60 deg | 33.2% | 13.5% (thigh tops) |
| 75 deg | 36.9% | 8.4% |
| 80 deg | 31.4% | 5.7% |

The first-person arm stays at about 5% of the frame and out of the lower
centre at steep angles. The watch is 10 deg from view centre at 45 deg down,
11 deg above it at 60 deg down, and 26 deg at 78 deg down. Elbow interior
71-108 deg at every pitch; 0 torso hits.

## D. Tests

- `test_standing_body_composition.gd`: new structural guarantee -- everything
  of the body the player's own camera can render is below hip height and at
  least 0.6 m from the eye; legs stay visible.
- `test_watch_raise_pose.gd`: arms are mirror-only at rest too; the watch
  attachment is measured in pose space.
- `test_look_pose_sync.gd`: real-time wait for the raise (headless frames can
  be milliseconds).

# ROUND 28: THE RIGGED TECHNICIAN, ANATOMICAL FIRST-PERSON VIEW, ONE SHARED HAND, MAINTENANCE WORKDAYS

## A. Root causes

**Straight-down self view ("two large rounded leg shapes, no torso").**
Measured from the scene coordinates and confirmed by render:

1. The old CSG body's legs were raked about 20 deg forward: hip caps 3 cm in
   front of the eye, knees 10 cm, feet 30 cm.
2. Round 27's legs-only rule hid its torso from the player's camera.
3. The camera rotated in place at the eye: at 80 deg down, the lower half of
   the 72 deg frame looks about 26 deg behind vertical.

So a straight-down look landed on two thigh-top spheres directly under the
camera, with no torso connecting them. Your hypothesis was right in part: a
real person's eyes sit forward of the torso. But a forward-shifted camera
alone was not enough (verified by render): with the eye 9-12 cm forward the
chest still filled the lower view, because real eyes also travel forward and
down with the neck when looking down.

**First-person fingers missing at 45 deg up.** Two different models: the
mirror showed the world body's hand, while the player saw a separate
camera-attached rig whose oversized strap/case sat between the camera and
its own short finger meshes at upward looks.

## B. Fixes

- **New `scripts/character/technician_rig.gd`
  (`scenes/character/technician_rig.tscn`):**
  - a Skeleton3D with 22 humanoid-profile bones and locally generated,
    smoothly skinned meshes (no external assets);
  - blend-weighted joints (543 blended vertices);
  - five-digit gloved hands, coverall, belt, boots;
  - helmet/visor/headset head;
  - a BoneAttachment wristwatch with a readable face;
  - ~1.70 m anthropometric proportions: upper arm 0.32 m, forearm 0.25 m,
    thigh 0.40 m;
  - the EYE 12 cm in front of a vertical ear-shoulder-hip-ankle plumb line.
- **Posing is entirely bone rotation**, so limb lengths are constant:
  - pose_look (spine/neck/head from CharacterPoseState);
  - two-bone arm/leg IK;
  - procedural walk from real movement speed;
  - sit (legs/hands follow the existing, tested sitting anchors);
  - lie (flat on the back).
- **`player_body.gd` drives the rig as the visible body**
  (`use_rigged_visual`, default true):
  - the old CSG nodes stay as the tested pose anchors but are not rendered;
  - setting `layers = 0` at runtime crashed the Godot 4.7 renderer, so
    visibility is used instead;
  - false = the legacy visual (fallback, tested);
  - the public PlayerBody API is unchanged.
- **Body visibility:** the rig body (torso, arms, hands, legs) is seen by the
  player AND every other camera; only the head/neck mesh is mirror-only.
- **Shared hand:** the old first-person rig is suppressed
  (`suppress_presentation`), so player and mirror see the SAME arm, hand,
  fingers and watch.
- **Anatomical eye anchor:** while standing, the camera node's local position
  follows the rig's POSED head -- `eye_anchor_offset()` uses the same
  spine/neck/head rotations the mirror shows. At 80 deg down the eye moves
  24 cm down and 8 cm forward; at a level look the offset is exactly zero.
  The LookPivot/PitchPivot controller, capsule, movement and interaction ray
  origin logic are untouched (the ray already lives on the camera).
- **Watch:**
  - shared target retuned for the rig: level hold 24 deg below the eye line at
    0.35 m;
  - the elbow drops for chest-height holds;
  - high holds swing the forearm across in front of the face;
  - the head bows toward the watch while reading;
  - the dial text is abbreviated to the real 48 mm face ("CHECK IN / CTRL RM").

## C. Rendered verification (inspected)

- **First-person downward, no C** (level, 30/45/60/75/80): at 80 deg the view
  shows belly, belt, thighs and boots in one continuous body; no grey dome,
  no disconnected spheres.
- **Watch** (level, 30 up, 45/60 down, extreme down, release mid-way;
  first-person and mirror side by side):
  - one gloved arm with five fingers;
  - a readable face;
  - the same gesture in the mirror.
- **Full character** (front/side/back/three-quarter standing, walking,
  sitting, lying, watch inspection), standalone and in-game. Defects fixed
  along the way:
  - pointed shoulder caps;
  - flared hip "pockets";
  - lying face-down / head through the mattress;
  - missing head when lying;
  - salute-like high hold;
  - fingers at the face at level;
  - oversized watch text.
- **Physical maintenance:** hand reaching into the filtration cabinet onto
  the cartridge; carrying; at the station; installed (no floating cartridge).

## D. Workdays (Priority 4)

- **Rotation:** day 1 is unchanged (Slice A/B). From day 2 (after sleeping),
  DayPlan runs one authored workday from `workday_rotation` (Filter Service ->
  Calibration -> Electrical Service).
- **Steps** are ordered references to EXISTING task fields (c01, c02, e02,
  e05, c05, l02, l07) plus named physical facts reported by the real objects:
  - storage cabinets: `retrieved:wire` / `retrieved:filter`;
  - filter housing: `inspected:filter`;
  - disposal bin: `disposed:used_filter`;
  - Diagnostics on calibration day: `reviewed:sensor_warning`;
  - the workstation: `verified` / `closed`.
- **Separate states:** restore -> verify -> cleanup -> close. The Work Orders
  [R] verifies; a later [R] closes only once cleanup is done ("Order stays
  open: used parts still awaiting disposal").
- **Guidance:** the map room and wristwatch follow the next step.
- **Calibration day:** Diagnostics reviews the pressure warning instead of
  raising the electrical fault.
- **No re-rolls:** puzzle configurations are never regenerated.
- **Serviced equipment is skipped:** stations keep their repaired state across
  days and there is no re-fault/restock system yet, so the rotation never
  schedules a workday for equipment that's already fixed.

## E. Physical interaction (Priority 5)

- `carry_system.gd` emits `item_picked_up(item, from_global)` before
  reparenting. Gameplay state is unchanged and immediate.
- The rig's right hand reaches to the part (which stays put), grasps, and
  carries it in the palm: CarryAnchor follows the palm.
- Drop at any time returns the part through the existing return/placement
  logic. The single-item rule is untouched; no duplicates, no losses
  (tested).

## F. Ambience (Priority 6)

`scripts/audio/station_ambience.gd`: three quiet procedural looping beds
(ventilation, Engineering machinery, Life Support airflow), driven only by
real state:

- an electrical crackle while the Engineering power fault is open;
- strained/quieter airflow while the filter housing is isolated.

## G. Tests

New:

- `test_rigged_character.gd`: bones, skinning, blended weights, anatomy, eye
  in front of the plumb line, per-camera visibility, no legacy visuals, eye
  anchor, fingers in the player's view looking up, constant limb lengths,
  sit/lie/stand, walk, fallback;
- `test_workdays.gd`;
- `test_carry_reach.gd`;
- `test_station_ambience.gd`.

Rewritten (geometry intentionally replaced; equivalent behaviour checks
kept):

- `test_look_pose_sync.gd` section 5/6;
- `test_standing_body_composition.gd`: the legs-only rule became an eye in
  front of the chest surface, plus no torso joint within 0.12 m of the eye
  at any pitch;
- `test_watch_raise_pose.gd`, `test_wristwatch.gd`,
  `test_wristwatch_screen_stability.gd`: "rig visible" -> the shared rig
  watch is raised and shown.

## H. Known limitations

- The character mesh is procedural low-poly (no textures, simple helmet
  head, rigid fingers); it is a solid base, not final art.
- Walking is a procedural cycle; there is no AnimationTree yet.
- Sitting reuses the legacy sitting anchors; seated shoulder/neck detail is
  simple.
- With C held at about 80 deg down, the raised upper arm sits close to the
  lowered eye on the right of the view.
- The eye anchor lowers the interaction ray origin up to 24 cm at extreme
  downward looks (looking at the floor), which is physically correct.
- Equipment does not re-fault and parts are not restocked across days;
  workdays therefore run once per unserviced system.
- The old first-person watch rig and the CSG body remain in the tree (unused
  visuals) until the legacy fallback is retired.

---

# Round 29 — Carrying bug, bed camera, head, watch range, gait, blending, recurring work

## A. Carrying moved the player backward (Priority 1)

- **Root cause (measured):** every carryable (filter, wire, used filter) is a
  `StaticBody3D` on collision layer 1, and its collider stayed ENABLED while
  parented to the carry anchor. Round 28's palm-carry pose holds the filter
  ~0.36 m from the capsule axis, so its 0.18 m box reached ~0.27 m -- inside
  FreeMoveBody's 0.30 m capsule. `move_and_slide()` depenetrated the capsule
  every tick (velocity stayed exactly 0), the player followed the capsule, the
  hand followed the player, and the item overlapped again: a self-sustaining
  drift (3.4 m in 3 s with no input) that stopped the moment the item was
  dropped. The wire did the same, less (0.85 m) -- proved by re-enabling the
  held collider in a scratch copy of the new test.
- **Fix (`carry_system.gd`):** a held item leaves the physics world:
  `_suspend_physics()` saves and zeroes its `collision_layer` at pickup;
  `_release_physics()` restores it on EVERY release path (drop, drop at feet,
  consume, take/install). The storage cabinet's own `disabled` gating is
  untouched (different property), so re-stowing behind a shut door still
  works.
- **Drop placement (Priority 6):** drop-at-feet put the item's ORIGIN 3 cm
  above the floor, sinking both filter cartridges (geometry 0.092 m below
  their origin) 6 cm into the floor. `item_bottom_offset()` now rests the
  item's lowest visual/collision point on the floor.

## B. Bed sitting / lying camera (Priority 2)

- **Root cause (measured):** the legacy SittingPose anchors describe a
  RECLINED sitter (hips 0.20 m in front of and 0.56 m below the eye), but the
  rig sat upright on those hips, so its eye was 0.38 m IN FRONT of the camera:
  the camera sat behind the character's head, its neck/shoulders/upper back
  0.22-0.29 m ahead of the lens.
- **Fix:** `_pose_rig_seated_recline()` reclines the rig from its pelvis
  (posterior pelvic tilt 40 %, lumbar 60 %) under two constraints -- pelvis at
  seat height on the mattress, eye on the seat camera -- solved at a NEUTRAL
  look so the pelvis stays planted; the look then bends neck/head and the
  camera follows the posed eye (rotated offset, never an absolute pin, so the
  laptop editor zoom still moves it). While the laptop is open, the posed eye
  itself is pinned instead (blend), so laptop/editor framing is unchanged.
  Seated feet/hands follow the pelvis's fore/aft shift.
- **Lying:** the camera sits on the lying rig's eye; looking toward the feet
  lifts the head (chin toward chest, up to 55 deg) so the view runs down the
  body instead of grazing the chest; the rig is anchored at the shoulders so
  the head rests at the pillow. (`set_lying()` is still not reachable from
  gameplay -- sleeping happens seated, timing unchanged.)
- **Get-up:** the seated body turns 90 deg toward the bunk's open west edge
  and slides 0.28 m to it while the legs swing down (parallel to the existing
  stages, same total duration), and the rise stage carries the eye out over
  the planted feet -- previously the legacy leg swing planted the feet 0.4 m
  ahead, through the mattress.

## C. Head / helmet / neck (Priority 3)

- **Root cause:** `_ellipsoid()` was wound opposite to `_loft()`, so every
  ellipsoid -- helmet, chin, visor and both shoulder deltoids -- rendered
  INSIDE-OUT (back faces only): a featureless glossy black ball for a head and
  dark holes on the shoulders. Winding fixed.
- Rebuilt head: matte grey-blue helmet shell (0.20 m wide, 0.24 m tall with
  chin guard), a separate glossy visor band, ear pads seated on the shell, a
  helmet neck seal, a 6 cm-radius neck and a raised collar (only ~3 cm of neck
  shows). The shared look split (spine/neck/head) is unchanged so the
  approved first-person downward behaviour is unchanged.

## D. Watch inspection above eye level (Priority 4)

- **Root cause:** the shared target's elevation was clamped at eye level, so
  above ~24 deg up the target was "eye height, 0.33 m ahead" -- ~0.53 m from
  the shoulder for a 0.565 m arm (39 deg elbow flexion at 35 deg up).
- **Fix:** above a level look only (`pitch > 0`): the watch keeps rising with
  the look up to a 32 deg elevation, the reading distance eases to 0.28 m
  (the shoulder joint is ~13 cm behind the eye; a bent elbow needs the wrist
  within ~0.44 m of the shrugged shoulder), the wrist comes to the midline,
  the clavicle shrugs (24 deg) and protracts (14 deg), the elbow pole goes
  from "out, forearm across the face" (to ~30 deg) to "low and in front"
  (by 60 deg), the target is measured from the posed eye, and the hand
  relaxes forward at the wrist. At or below a level look the code path and
  shared target are exactly Round 28's (tested against a verbatim replica).
- **Measured:** elbow flexion 81-89 deg from 20 to 70 deg up; dial faces the
  eye (0.99); watch 25-32 deg below view centre up to ~56 deg.
- **Anatomical limit:** to keep the watch in view at a 70 deg upward look it
  would have to sit ~42 deg above the eye line -- above the head (a raised
  arm). The pose therefore caps the rise; past ~56 deg the watch slips toward
  the bottom edge (43 deg below centre at 70 deg, partly out of the 72 deg
  view) while the arm stays a believable bent-elbow check.

## E. Gait and footsteps (Priority 5)

- **Root causes (real W input):**
  - **Drift against the sounds:** the rig's cycle advanced one step per 0.75 m
    while footsteps play every 0.85 m, so contacts drifted against the sounds
    (hip angle at successive sounds: +12/-1/-8 deg).
  - **Large swing:** ±24 deg pendulum legs with 38 deg knees.
  - **Sliding:** the "planted" foot slid at 1.38 m/s (77 % of walking speed).
  - **High frame rates:** at render rates above the 60 Hz physics rate, most
    frames saw zero displacement and the walk blend collapsed.
- **Fix:**
  - **Locked contacts:** `free_move_controller.gd` exposes `gait_position()`,
    meaning footsteps played plus progress. The legs are locked to it, so
    every footstep sound is a heel strike by construction.
  - **IK feet:** feet are placed by leg IK on a 0.55 m sweep (0.25 ahead /
    0.30 behind), with a swing arc and a 68 % ground-contact fraction. The
    pelvis drops 2 cm and the arms counter-swing.
  - **Smoothing:** speed is low-passed; the phase stays continuous across
    accumulator resets and source switches; side-steps never cross the legs.
- **Unchanged:** move speed 1.8 m/s and step distance 0.85 m. At that speed
  and cadence the footprint spacing itself is fixed by physics (speed /
  cadence); what shrank is how far the legs reach and how much the feet slide.
- **Measured:**
  - foot reach 0.24 m ahead of the hip, down from 0.33 m;
  - stance-phase slide 0.17 m/s, down from 1.38 m/s;
  - every sound within 0.04 steps of a heel strike, forward, backward,
    sideways and while turning.

## F. Pickup lifecycle (Priority 6)

Gameplay ownership stays immediate (single-item rule and every task contract
unchanged); visually the part stays on its shelf until the hand arrives
(reach 0.45 s, linear outer blend over the IK's own joint easing -- the old
double ease peaked at ~9 m/s), transfers to the palm at the grasp, returns to
the carry pose by 1.05 s. The held part is out of the physics world; drops
rest on the floor; interruptions and rapid pickup/drop resolve
deterministically (tested for both parts).

## G. Animation blending (Priority 7)

`player_body.gd` stays the single owner of every bone (one composition per
frame from the shared pose state). Added to it:

- **Pose crossfade:** `technician_rig.gd` gets `snapshot()` /
  `crossfade_from()`, a 0.4 s world-space crossfade on stand/sit/lie
  switches. It starts at the switch itself, from the pose actually shown, and
  an out-of-frame refresh never completes it.
- **Sit-down preview:** while the sit-down camera tween runs, the visible body
  eases into the final seated pose already placed at the seat. The logical
  pose and its timing are unchanged.
- **Camera blending:** the camera's local target blends across pose switches.

## H. Repeatable workday foundation (Priority 8)

- **Service log:** DayPlan's serviced set became a log, keeping the last day
  each system was serviced plus `service_history`.
- **Intervals:** `SERVICE_INTERVAL_DAYS` is filter 4, calibration 3,
  electrical 5. New API: `is_service_due()` and `days_since_service()`.
- **Opt-in re-arm:** `register_service_rearm(workday, handler)` and a
  deterministic `daily_variant_seed()`. A serviced system is scheduled again
  only when it is due AND its equipment can genuinely re-fault. No station
  registers yet, so the shipped behaviour equals Round 28's.
- **Staged plan:**
  1. Calibration re-arm: re-drift the coupled chambers from the day seed.
  2. Storage restock: a delivery restores a cabinet's part as a new physical
     instance, with ownership rules.
  3. Filter re-arm: fresh cartridge stock, the housing accepts a new service,
     and a new used cartridge is produced.
  4. Electrical: a different fixed component faults per day seed.

## I. Tests and rendered verification

- **New tests** (registered in `tests/run_tests.sh`):
  - `test_carry_no_drift`: proved to fail with the pre-fix collider (7.5 m of drift).
  - `test_bed_camera`, `test_watch_high_range`, `test_gait_footsteps`
  - `test_workday_recurrence`, `test_animation_transitions`
- **Updated for new intent:**
  - `test_rigged_character`: waits for the crossfade, and for settling after the teleport.
  - `test_look_pose_sync`: the high-hold intent changed; downward checks are unchanged.
  - `test_storage_cabinet_depth` and `test_carry_reach`: longer reach timing.
- **Results:** baseline 84/84; final full runs 90/90 and 90/90 (exit 0);
  headless startup clean; navigation 38 edges, 5 known, 0 new.
- **Renders inspected:**
  - bed: standing by the bunk, sit-down mid-move, seated at −45/−12/+20,
    woken, get-up leg swing / rise / swap / stood, lying looking at the
    ceiling and toward the feet;
  - head close-ups: front, side, three-quarter at neutral, ±40 and the watch
    holds;
  - mirror + first-person watch matrix: 0, +20/35/45/60/70, −30/−60/−80;
  - walking side view at each footstep contact and mid-stride;
  - filter and wire reach / grasp / carry.

## J. Limitations

- `set_lying()` is still not reached from gameplay; sleep stays seated, with
  timing unchanged.
- Above about 56° up the watch drifts to the bottom of the view, and at 70°
  it is out of view (the anatomical limit). In the mirror the raised forearm
  sits above the helmet line at 60–70°.
- At an 0.85 m cadence and 1.8 m/s, footprint spacing is fixed. The visible
  reach and the slide shrank, but stance slide is about 0.17 m/s, not zero.
- Gameplay ownership of a picked-up part is immediate; only the visual
  transfer waits for the grasp (0.45 s).
- The authored 0.35 s walk-back at the end of the get-up is still brisk
  (about 4 m/s).
- No station registers a re-arm handler yet, so recurring work is a
  foundation only; part restocking is not implemented.
- (Corrected in Round 30: the "Storage floor gap" reported here was wrong.
  That point is inside the Storage north wall, and a ray that starts inside a
  solid reports no hit. A 1,572-sample sweep found no floor holes.)


---

# Round 30 — Laptop on the bed, furniture contact, proportions, recurring calibration

## A. Bed laptop (Priority 2)

- **Root cause (rendered + measured):** the Round 29 reclined bed pose moved
  the rig's pelvis ~10 cm forward of the legacy hip anchor, while the legs
  still IK'd to the legacy ankle anchors, so the knees folded UP. The laptop
  stayed on the fixed legacy `LapAnchor`, now between/under the thighs, and
  the raised knees stood in front of the screen (in the editing view they
  covered most of it).
- **Seat style:** `player_body.gd` gains `seated_on_bed`, set by
  `sleep_state.gd` (`set_seat_style(true)`). The workstation chair keeps the
  legacy anchors.
- **Legs:** on the bunk the legs lie out along the mattress (hip joint to
  ankle 0.74 m, knees soft). The get-up leg swing, which moves the legacy
  ankle anchors, blends back to them.
- **Laptop placement:** `LapAnchor` rides on top of the actual thighs (62 %
  of the way hip→knee, 0.10 m above the thigh centre line). It pitches with
  the thighs plus the laptop's held 20° tilt, so the base lies along the lap.
  Its position comes from the NEUTRAL seated placement, so the open laptop
  never drifts as the player looks around.
- **Hands:** while the laptop is open, both hands rest on its keyboard.
- **Unchanged:** laptop/editor framing tests (aim, zoom distance,
  no-reversal) and sleep/wake timing.

## B. Furniture contact and drop physics (Priority 3)

- **Root causes:**
  1. 107 visible interior props had no collision at all: mattress, pillow,
     headboard, desk slab, console desk and kickplate, wash counter and basin,
     wall shelf, locker, stools, personal container, waste-hatch housing, and
     more. The drop ray went straight through them.
  2. The drop was a single ray that placed the item's ORIGIN at one point,
     with no footprint, clearance or path checks.
  3. The bunk's interaction collider is an invisible box from 0.40 to 0.75 m,
     21 cm above the mattress top. Once furniture collided, items rested on
     thin air.
- **`scripts/station/furniture_contact.gd`:** the listed props collide on a
  dedicated contact layer (value 4), never layer 1. The player capsule (mask
  1), navigation sweeps and interaction ray (now explicitly mask 1) are
  exactly as before.
- **Placement solver (`carry_system.gd`):**
  - **Sweep:** an upright box fitted to the item's VISIBLE meshes (the wire's
    collision box hangs 3.5 cm below its coil), yawed to the player's facing.
  - **Path:** cast out from the body to a candidate at carried height, then
    lifted to chest height to clear counters and desks.
  - **Fall:** cast straight down onto the first surface on layer 1 or the
    furniture layer.
  - **Accept only if:**
    - the surface is near-level (normal.y > 0.85);
    - the centre plus at least 3 of 4 inset footprint corners are supported
      within 2.5 cm, so nothing balances on edges, seams or steps;
    - the start pose is clear;
    - the drop is not "down a pit".
  - **Slide:** a partly supported rest slides toward its supported side, up to
    3 × 6 cm, before the next candidate (4 distances × 5 angles × 2 heights).
- **Landing:** the part falls from the hand under gravity (≤ 0.5 s), turning
  upright, with a small damped settle. It stays out of the physics world until
  landed, can be caught mid-fall, and its layer is tracked per item.
- **Hover proxies:** the bunk and the two wall-station hover volumes are in
  the `placement_proxy` group. The solver ignores them, and the interaction ray
  looks through a proxy to a carryable part resting inside it, so a part on
  the mattress can be picked up again.
- **Storage logic:** facing the OPEN cabinet a part belongs to, Space stows it
  back on its own shelf slot (prompt "Space: Stow …", stock restored). A part
  never stows into a cabinet it does not belong to.
- **Flat floors:** a 1,572-sample sweep found every walkable floor flat
  (y = 0) with no holes. The station's "uneven surfaces" are its furniture
  (stacked mattress/pillow/blanket, frame trims, recessed basin, shelf lips,
  desks, stools, hatch housing).

## C. Proportions (Priority 1)

From the rendered turnaround, the torso was a straight tube: the chest no
wider than the hips, almost no waist, a flat back and seat, and stick legs.
Only the mesh rings were changed:

- broader chest (rx 0.178);
- tapered waist (0.128);
- seat and shoulder-blade volume added behind;
- fuller upper thighs (fullness added front-to-back after a first try flared
  sideways) and a calf.

The chest FRONT surface is unchanged to the millimetre (first-person eye
clearance), and no bone, joint or pose changed, so the arm, watch, walk and
head are identical (watch matrix and walk re-rendered).

## D. Recurring maintenance (Priority C)

Calibration is now a genuinely recurring service. `sensor_calibration_station.gd`
registers its re-arm with DayPlan:

- **When:** once it is due (3 days after its last service) and every system
  has been serviced once, a new Calibration work order starts.
- **Drift:** the order comes with a recorded sensor drift. Its
  required-chamber count (1–3) comes from the day's variant seed, which the
  real calibration view uses: stable within the day, different across days.
- **Prompt:** "drift detected" until calibrated.

Filter and electrical do not recur yet: they need part restocking and a
second physical used part, which is the next staged step.

## E. Tests and rendered verification

- **New tests:**
  - `test_furniture_contact`: 12 scenarios × 2 parts, stow, hover through
    proxies, pick-up after settling. Proved to fail without the furniture
    collision.
  - `test_bed_laptop`: laptop on the thighs, no thigh penetration, nothing
    between the eye and the screen, hands on keys, no drift while looking
    around, get-up restores the anchor, chair unchanged.
- **Updated:** `test_workday_recurrence` (real calibration recurrence and the
  seeded requirement in the real view).
- **Renders inspected:**
  - seated, laptop open (side and front), editing, closed, woken, get-up;
  - drops on bed, blanket, desk, counter, console desk, Storage corner and
    waste-hatch area, plus a mid-fall frame;
  - character turnaround before/after and mirror;
  - watch matrix (0, 35, 60, −30, −60), walking side view.
- **Render-environment note:** with the Godot window occluded, macOS throttles
  it (0 % CPU, no `frame_post_draw`), so renders now use `--write-movie`.
  Giving the log editor keyboard focus also stalled a movie render, so the
  editing frame comes from an earlier non-movie run.

## F. Limitations

- Placement is a deterministic solver with a scripted fall and settle, not a
  rigid-body simulation: parts do not tumble, roll or stack on each other.
- Furniture surfaces collide only for parts and placement. The player capsule
  still passes through un-collided furniture, as before, to keep the locked
  movement/navigation baseline.
- Only calibration recurs; part restocking is not implemented.
- The bed legs-out pose applies only on the bunk; the workstation chair keeps
  the legacy seated anchors.
- A small bump remains at the hip joints in the front view.

## G. Late fixes found by the final suite runs

- **Reach speed:** the transition test now samples every render frame and
  divides by that frame's own engine delta (the old per-tick reading was
  flaky). Measured that way, the hand's peak reach speed was ~5.7 m/s. The
  reach is now 0.6 s out and back to the carry pose by 1.2 s, and the return
  blends the three arm joints in JOINT space between the solved grasp and
  carry arms; a straight-line IK target swung the elbow at ~7 m/s. Peak is
  now ~2.8 m/s.
- **Release snap:** dropping, stowing or installing mid-reach snapped the arm
  ~0.9 m in one frame. A release now eases from the arm rotations last shown.
- **Held part hidden by the door:** closing a cabinet during the reach hid and
  disabled the part already taken (it still sat at its shelf spot). A held
  part (`carry_system.is_holding()`) is never "stowed".
- **Final results:** two full runs 92/92 PASS, exit 0; headless startup
  clean; navigation 5 known, 0 new; 93 test scripts on disk, 92 in the runner
  (the manual-only one excluded).

---

# Round 31 — Physical storage, restocking, repeatable maintenance, physics, sleeping

## A. Multi-item storage (Priority 1)

- **Stock:** each Storage cabinet holds 4 real, individually retrievable
  parts: filter cartridges in cabinet 2, 16-gauge harnesses in cabinet 1.
  These are six new instances of the existing part scenes, three across the
  front of the shelf plus one in the back row.
- **Slots and holders:** every authored part defines one SLOT (capacity =
  real slots). The authored retaining holder (filter clamp ring/arm/strap,
  wire strap) is duplicated onto every slot.
- **Placards:** they read the real count: "4 AVAILABLE",
  "1 AVAILABLE — LOW", "0 AVAILABLE — RESTOCK". Low stock means 1 or fewer.
- **Retrieval fact:** recorded when stock DROPS. With several parts, "stock
  reached 0" was no longer the right trigger.
- **Stowing:** `stow()` returns a part to its own slot if free, otherwise
  the first free slot. Compatible unused parts (same `item_id`) are adopted
  as stock, with the cabinet's load-time home parent.
- **Ownership:**
  - installed parts are never "stowed", so they never reappear in Storage;
  - consumed (freed) parts are pruned;
  - held or reserved parts are never gated by a door;
  - a door that starts closing cancels any reach into it.
- **Wire colour:** all 16-gauge spares (group `wire_spare`) take the
  electrical fault's colour, so the pickup message names the right one.

## B. Restocking (Priority 2)

- **Reserve crate:** `scripts/interactables/supply_crate.gd`, placed in the
  Storage NW corner: a solid crate with a hinged lid and a real-count
  stencil. Its reserve of 2 filters and 3 harnesses is real part instances,
  created once at load, never on open.
- **Restocking:** open the crate, take a part, open the cabinet, Space to
  stow. The cabinet adopts it into a free slot, so shelf +1 exactly when
  reserve −1. A full cabinet refuses.
- **Supply warnings:** `DayPlan.supply_warnings()` turns low shelf stock into
  "SUPPLY: FILTER STOCK LOW (n) — RESTOCK FROM RESERVE (m)", shown in the
  workstation's Work Orders section.
- **Future deliveries:** a scheduled cargo delivery would instantiate real
  parts into the crate's reserve slots (a `deliver(scene, count)` call), and
  could become an ordinary logistics workday step ("receive delivery →
  restock shelf").

## C. Repeatable maintenance (Priority 3)

All of this is on DayPlan's Round 29–30 foundation:

- **Hooks:** `register_service_rearm(workday, handler, feasible)` with
  service intervals filter 4, calibration 3, electrical 5 days.
- **Feasibility:** `is_service_feasible()` means no impossible work order is
  ever scheduled. Filter and electrical require a clean part on a shelf or in
  the reserve.
- **Filter:** the housing tracks the cartridge actually installed. The
  re-arm returns it to ISOLATE with that cartridge still seated. On removal,
  the seated cartridge is retired and a NEW physical used cartridge
  (`used_filter_cartridge.tscn` instance) is ejected, so there is exactly one
  representation at a time. A clean cartridge is consumed from stock, and the
  used one must be disposed of before the order can close.
- **Electrical:** the same fixed 10-wire panel. The re-arm resets the repair
  state machine to UNDIAGNOSED and picks a DIFFERENT authored fault
  configuration from the day's seed. It stays fixed for the work order:
  `_select_repair_config()` keeps it, and debug forcing is ignored. The
  previously installed spare stays installed.
- **Calibration:** both how many chambers drift and WHICH ones come from the
  day's seed (the view shuffles its six chambers with it).

## D. Multi-day progression (Priority 4)

`test_multiday_maintenance.gd` drives:

- **Day 1:** tutorial, unchanged.
- **Day 2:** filter service (real cabinet, housing, used cartridge, waste
  bin, verify, close).
- **Day 3:** calibration. **Day 4:** electrical.
- **Day 6:** calibration recurs.
- **Day 7:** a second real filter service on the same housing.
- **Day 9+:** electrical recurs on a different circuit.
- **Plus:** restock from the reserve, and "parts exhausted → filter never
  scheduled".

Restored, verified, cleanup and closed remain separate (verify passes while
the used cartridge waits; closing needs disposal).

## E. Furniture and physics (Priority 5)

- **Player collision:** the player capsule now collides with the furniture
  contact layer (mask 1|4): desks, wash counter, console desk, locker, stools,
  bunk and so on block the body. The workstation operator stool is excluded:
  you sit on it, and with collision it pushed the player out of the
  workstation's use range (`test_workstation_sitdown` caught this).
- **Drops:** the Round 30 solver still finds a validated, reachable,
  supported spot. The part is set out over that column (0.18 s), then a
  temporary `RigidBody3D` (box fitted to the visible extent, mask 1|4,
  exceptions for the player capsule and hover proxies) drops it under real
  physics; the part follows it until it sleeps.
- **Validation:** the rest is validated (no interpenetration, level-ish
  support, within reach). The collision margin is corrected so the visible
  underside sits on the surface. If the outcome is invalid or slow (>2.5 s),
  the part settles at the solver rest instead. Measured across 24 test drops:
  23 physics rests, 1 fallback.

## F. Lying and sleeping (Priority 6)

- **Sleep:** G lies the technician down on the mattress first: a 1.1 s
  skeleton crossfade (pose switches now take a crossfade duration), with the
  camera easing to the lying eye and looking up. Then the unchanged
  eyes-close / hold / open sequence and day reset run.
- **Wake and get up:** you wake lying. E sits up (1.0 s crossfade back to the
  seat), then the existing staged get-up runs. The laptop is unavailable
  while lying.
- **Tests:** the sleep tests were updated for the added lie-down and sit-up
  time.

## G. Pickup lifecycle (Priority 7)

- **Grasp-time ownership:** clicking starts a REACH. The part stays where it
  is, still owned by its shelf, floor or crate, and the one-item rule covers
  reaches. Ownership transfers at the GRASP, on a single clock:
  `carry_system` completes it at `REACH_OUT_S` while the body animates the
  same timeline.
- **Cancellation:** a reach cancels if the part BECOMES unavailable (hidden,
  disabled, installed), the door starts closing, the player walks 1 m
  farther away, interactions become disabled (seat, focused view, sleep), or
  Space is pressed. The part never moves, so nothing is lost or duplicated.
- **Tests:** 36 waits were inserted into existing tests that relied on
  ownership at the click.

## H. Station life (Priority 8)

- **Equipment status lamps** (`equipment_status_lamps.gd`): an emissive bead
  and tag above the filter housing, the electrical panel and the calibration
  station. They are driven every frame by each station's real `condition()`:
  NOMINAL, SERVICE DUE (amber pulse), FAULT (red blink), IN SERVICE,
  RESTORED.
- **Maintenance log:** `DayPlan.log_event()` / `day_log()`, written by the
  real equipment (install, replace, dispose, restock, service) and shown in
  Work Orders alongside the supply warnings.
- **Audio:**
  - Life Support airflow spins down and up (1.5 s ramp) when the housing is
    isolated and restored;
  - the Engineering fault crackle fades with the real fault;
  - a quiet confirmation tone plays when a system turns RESTORED and when a
    work order closes.

## I. Tests and verification

- **New tests:** `test_multiday_maintenance`, `test_furniture_blocks_player`,
  `test_grasp_ownership`. Updated: storage and stock counts, sleep timing,
  furniture-mask intent, grasp waits, the ambience ramps, and the
  transition-test metric (physics-tick aware).
- **Rendered and inspected:** both populated cabinets, the open reserve
  crate, the Storage overview with the real-count placard.
- **Not rendered:** the harness stalled this round in movie mode (the main
  loop keeps writing frames but the script's timers stop advancing; no error
  logged) during the take/stow and lying-sleep shots. Those behaviours are
  verified by automated tests only; the lying view itself was rendered in
  Round 29.

# Round 32 — Item physics, cargo resupply, specialised spares, long-term maintenance

## A. Dropped items fall from the hand (Priority 1)

- **Root cause:** Rounds 30–31 released a dropped part by tweening it from
  the hand to a solver-chosen rest point about 0.6 m ahead (0.18 s, at
  constant height) and only then starting physics. A per-tick trace measured
  0.066 m of sideways travel on the first tick and 0.557 m over ten ticks
  before any fall.
- **Now:** Space releases the part from the hand pose itself. The release
  velocity is the player's horizontal velocity plus a gentle 0.15 m/s let-go.
  A temporary `RigidBody3D` proxy (mask 1|4, collision exceptions for the
  player capsule and placement proxies, continuous CD) drops it, and the part
  follows the proxy until it rests.
- **Place gesture:** when the look ray hits a reachable, upward-facing
  surface within 1.6 m, the ARM first carries the still-held part out over
  that point (0.35 s), with a waist lean of up to 35° for low targets. It
  then lets go a few centimetres above the surface. The disposal hatch is
  excluded (`no_place` group).
- **Releasing in tight spots:** the release pose is checked against
  furniture and walls (box query + line of sight from the eye). The smallest
  lift (≤8 cm) or pull-back (≤5 cm) that fits is used. Otherwise the release
  is REFUSED ("No room to release that here.") and the part stays in the
  hand.
- **Tunnelling guard:** CSG walls are thin. A per-tick ray between
  consecutive centres plus a penetration check reverts the proxy to its last
  good pose.
- **Landing next to the player:** a part that lands touching the player's
  capsule stays pickable-only (layer 16) until the player steps away, so it
  never shoves the body.
- **Used cartridges:** they now fall too, instead of floating at hand
  height.
- **Removed:** the Round 30 rest-point solver and its fallback.
- **Coverage:** clean filter, used filter, 16GA harness, reserve-crate
  filter; floor, bed, desk, wash counter, console desk, counter edge (refusal
  or plain release), locker wall, Storage corner.

## B. Render harness (Priority 2)

`tools/render_harness.gd` provides `start`, `step`, `wait`, `snap` and
`finish`, plus a watchdog (PROCESS_MODE_ALWAYS) that quits with exit code 2
and a "RENDER HARNESS STALL at step …" report after 45 s without progress.
It was verified with a never-firing signal (exit 2).

The Round 31 stall did not reproduce. The take/stow sequence (118 frames)
and the lying-sleep sequence (403 frames) both completed in movie mode.

## C. Cargo resupply (Priority 3)

- **Port:** `cargo_port.gd` is a secured transfer compartment cut into the
  airlock's west wall. It has a sliding hatch, latches, an orange restraint
  strap, a status lamp, a shipment ID panel and 7 typed cargo slots
  (3 filters, 2 × 16GA, 2 × 22GA).
- **Schedule:** DayPlan owns it. The first shipment arrives on day 3, then
  every 4 days. A port still busy delays the next shipment by a day.
- **Manifests:** each manifest is the real shortfall (shelf + reserve
  capacity minus parts on hand, including any still in the port), capped by
  the slots. It is finite and never regenerates.
- **Receiving procedure:**
  1. Check the ID.
  2. Unlock and open (pressure equalise + slide).
  3. Release the restraint.
  4. Carry each part to the reserve crate or a shelf. Stock changes only at
     each real transfer.
  5. Confirm receipt (exactly once, logged).
  6. Close and secure.
- **Before receipt:** the parts stay hidden and unclickable.
- **Round 32 fix:** confirming in the same frame as the last transfer now
  works. The port updates "empty" inside `interact()`, not only on its next
  `_process`.

## D. Specialised electrical spares (Priority 4)

- **Two types:**
  - power circuits (service, return, backup) need the 16GA power harness;
  - signal/control circuits (telemetry, relay) need the 22GA shielded signal
    cable. It is visually distinct: thinner, grey shield, blue connectors,
    "22GA SIG" tag.
- **Wrong part:** rejected without being consumed and without losing
  procedure progress. The message names the compatible part.
- **Messages:** the traced, wrong-part and "nothing to install" messages now
  use `required_part_name()` instead of hard-coded 16-gauge text.
- **First-time repairs** stay on power faults (tutorial unchanged).
- **Recurring repairs** pick a different configuration whose spare is in
  stock.
- **Storage:** typed slots in the electrical cabinet (4 power + 2 signal)
  and the reserve crate (4 filters, 3 power, 3 signal). Placards list each
  type.

## E. Scheduling and variety (Priority 5)

- **New workday:** a fourth workday, the Coolant Routing Inspection (L08,
  the existing valve routing station, 6-day interval, seeded configuration).
- **Blocked services:** a due service with no usable part is now BLOCKED
  ("awaiting supplies, next cargo day N") instead of silently skipped. It
  resumes once stock returns.
- **Schedule changes:** with four workdays, day 5 is the first coolant
  inspection, and on day 6 the filter re-service comes up before
  calibration. `test_workdays`, `test_workday_recurrence` and
  `test_multiday_maintenance` were updated accordingly.
- **Closed orders:** a closed order no longer reports an outstanding room
  (an optional unticked step had kept pointing the watch back at the Control
  Room).
- **Filter re-service fix:** a used cartridge disposed earlier in the same
  frame (still valid until the deferred free) was being re-ejected and then
  vanished. The housing now treats a queued-for-deletion cartridge as gone.

## F. Sustainability (Priority 6)

`test_sustainability_20days.gd` runs 20 consecutive days. Each day it:

- receives cargo through the real port procedure;
- restocks shelves from the reserve;
- performs the assigned service with real parts from real slots;
- verifies and closes at the workstation;
- audits the totals (initial + delivered − consumed) and single ownership.

Observed: filter 5, calibration 5, electrical 4 and coolant 3 services;
5 deliveries; 4 different electrical fault configurations; no blocked days.

## G. UI (Priority 7) and feedback (Priority 8)

- **Work Orders:** adds BLOCKED, CARGO status/next-day, per-type low-stock
  lines, a compact `STOCK (shelf+reserve)` line and an `UPCOMING:` line
  (next due day per system, from the service log).
- **Wristwatch:** when no order is open and a shipment waits, it shows
  "CARGO READY / AIRLOCK".
- **Feedback:**
  - the port's status lamp, mechanical sounds and hatch/strap animation;
  - the distinct tagged signal cable;
  - type-aware part guidance.

## H. Fixes found by this round's renders and full suite

- **No floor below:** a release with nothing solid within 3 m below (off
  the mapped station) is refused, and the part stays in the hand. The old
  solver refused here; the new physics drop briefly did not
  (`test_carry_drop` caught it).
- **22GA cables were not reachable:** the cables sat on the electrical
  cabinet floor, under the full-depth shelf with 9 cm of clearance. A
  standing look ray hit the shelf (Shelf, y 1.175) first. They are now in
  the upper shelf's back row, and `test_electrical_spare_types` ray-checks
  reachability.
- **Task messages were drawn off-screen (pre-existing, also in HEAD):**
  `TaskMessageLabel` used the top-centre preset with negative offsets, so it
  was drawn above the screen. It is now bottom-anchored, just above the
  interaction prompt.
- **Shared HUD message label:** an older writer's timer (for example the
  1.5 s pickup message) hid newer messages from other objects. Writers now
  stamp `msg_owner` and only hide their own message. The cargo port's
  messages auto-hide after 4 s.
- **Older tests updated** for the signal-cable spares and per-type stock:
  - `test_electrical_wire_randomization` carries the 22GA cable for the
    telemetry and relay faults;
  - `test_storage_cabinet_depth`, `test_grasp_ownership` and
    `test_furniture_contact` count stock per type.

## I. Rendered and inspected this round

Non-movie SubViewport and POV captures through `tools/render_harness.gd`,
with no stalls:

- **Drops:** a floor drop from the hand; the place gesture onto the wash
  counter; the counter edge (falls to the floor beside it); the 16GA wire
  placed on the desk.
- **Cabinet:** both cable types visible in the electrical cabinet from a
  standing view.
- **Messages:** the wrong-part message on screen.
- **Cargo port:** arrived (closed, "SHIPMENT ARRIVED"); open and restrained;
  the contents (3 filters, one tagged 22GA, one 16GA); empty and awaiting
  confirmation; received; secured again.
- **Other:** the reserve crate after the transfer; the Work Orders screen
  with the CARGO and STOCK lines; the POV while carrying a delivered part.

Not rendered: the wristwatch cargo hint (covered by an automated test only)
and the "before" state of the drop bug (proven by the numeric per-tick
trace, not by a frame).

# Round 33 — Checkpoint, persistent game state, technician workdays, maintenance expansion

## A. Phase 1 checkpoint

- **Commit:** `4ef6688` "Checkpoint: Rounds 26-32 rig, maintenance, cargo,
  inventory and physics", local only and NOT pushed. `main` is 2 ahead of
  `origin/main`.
- **Contents:** 121 files: 62 modified and 59 added (new scripts with their
  `.uid` files, the character rig, the render harness, 40 test files).
- **Excluded:** `CLAUDE.md.save` (left untracked), `.claude/` (ignored),
  `tests/.last_run.log` (ignored).
- **Validated first:** 99/99 tests and 2,431 checks; the 5 known nav
  failures, no new ones; clean headless start; `git diff --cached --check`
  clean.

## B. Day hint (user request)

`DayPlan.day_started(day)` fires at each new day, and `today_title()` /
`is_new_shift()` describe it.

- **Workstation:** the title bar always reads "DAY N · SECTION". Home shows
  "NEW SHIFT — TODAY IS DAY N", the scheduled work, and "Open [1] Overview",
  until the morning check-in (C01). After that it shows "TODAY: DAY N — …".
- **Laptop (bunk):** the title is "SESSION LOG — DAY N". The subtitle reads
  "New shift. Report to the Control Room workstation." / "Shift in progress.",
  and the status line shows today's work. This replaces the old prototype
  placeholder text.

## C. Save / load (`scripts/station/save_game.gd`, node `SaveGame` in main.tscn)

- **Schema v1:** a JSON document with a header (`schema`, `game`, `day`),
  `day_plan`, `difficulty`, `equipment` (by stable id), `items`,
  `station_used`, `player` and `laptop`.
  - Values are tagged (`$i`, `$sn`, `$v3`, `$xf`, `$d`) so ints, StringNames,
    vectors, transforms and int-keyed dictionaries round-trip exactly.
  - Typed arrays are restored with `assign()`.
- **Stable item IDs:** node names. Authored parts (`FilterCartridge2`,
  `WireSignal1`), crate parts (`ReserveFilter1`), delivered parts
  (`CargoCS0002_5`), ejected parts (`UsedFilterCartridge3`) and the
  `CargoCarrier`.
- **One owner per part:**
  - cabinet slot, reserve slot or port slot;
  - in the carrier (cradle) or docked (the carrier itself);
  - installed (filter housing or electrical panel);
  - seated (used cartridge still inside the housing);
  - loose (world transform) or held.
- **Equipment** (fields restored, visuals snapped without animation or
  sound): filter housing, electrical panel (config, repair stage, procedure,
  disconnect order), calibration station (drift), valve manifold, cargo port
  (state, manifest, receipts), supply crate. DayPlan gets its own fields;
  **no re-arm runs on load**, so faults are restored, not re-rolled.
- **Safe save boundary:** saving is refused, with the reason shown, while:
  - a reach, place or physics settle is in progress;
  - a focused equipment panel is open;
  - the player is on the bunk (sitting, lying, sleeping);
  - the cargo hatch is moving.

  A part held in the hand is saved and returns to the hand. Calibration
  minigame progress is not mid-saved; the day's recorded drift is.
- **Atomic write:** the save is serialised to `<save>.tmp`, read back and
  validated. The previous save becomes `<save>.bak`, then the tmp is renamed
  over the save.
- **Recovery:** a missing, empty, truncated, corrupt or unsupported (newer
  schema) main file falls back to the backup. A save that fails validation
  never replaces anything.
- **Validation:** duplicate part ids, two parts claiming one slot, unknown
  types, invalid owners, more than one held part and dangling references are
  all rejected, and a rejected load leaves the world untouched.
- **Loading:** reloads the scene, then restores before the player resumes:
  1. consumed parts are removed;
  2. delivered or ejected parts are recreated;
  3. every part is parked;
  4. each is placed into exactly its owner.
- **UI** (workstation [5] SAVE / LOAD): shows the current shift day and the
  saved game.
  - **[R]** saves.
  - **[L]** loads.
  - **[N]** pressed twice starts a new game. It never deletes or overwrites
    the save until the player saves again.

## D. Daily routine, briefing, shift report

- **Morning briefing** (Overview, from real state):
  - the day, and the carry-over note if any;
  - station health from each system's live `condition()`;
  - today's order and its priority step;
  - blocked, cargo, supply and upcoming lines.
- **End-of-shift report:** built from structured counters that the real
  equipment writes through `log_event(text, kind)`:
  - equipment serviced (service log) and orders closed;
  - inspections, parts consumed, discarded and restocked;
  - cargo parts received;
  - unfinished work and supply concerns.

  Work Orders [R] submits it once nothing is left to verify or close; this
  is the shift-completion action ("SHIFT COMPLETE — rest in the Living
  Quarters"). The report is kept in `shift_history`.
- **Carry-over:** an order whose equipment is NOT restored carries into the
  next day with its facts and task progress (`carried_over_from`). A
  restored-but-unverified order is reported, not carried. Routine
  inspections never carry.
- **Retrieval facts:** now recorded at the grasp (`on_item_taken`), not
  inferred from per-frame stock differences. The per-frame version was
  timing-dependent, and the 20-day save/load comparison exposed it.

## E. New maintenance tasks

On days with no service due, DayPlan schedules ROUTINE work, alternating:

- **Routine Inspection Round:** log the filter housing, coolant manifold and
  power panel status at their physical status tags, plus a **supply audit**
  (the electrical cabinet's count, readable only with the door open).
- **Routine Communications Check:** the M02 signal check on the existing
  console, plus sensor-array and power readings.

Filing at the workstation **cross-checks** every logged reading against the
equipment's live state. A stale reading fails the filing and must be re-read.
Inspection tags (`inspection_tag.gd`) are pickable-only (layer 16), so they
never block the player or physics.

## F. Cargo carrier

A removable parts carrier (`cargo_carrier.gd`) docks in the cargo port, and
shipments are packed into it.

- **Before release:** the restraint must be released before it can be
  lifted.
- **Carrying:** the whole delivery is carried as ONE item (the one-item rule
  holds), and the parts ride along unclickable.
- **Unloading:** Space at an open reserve crate or cabinet unloads every part
  with a free compatible slot through that container's own `stow()`; stock
  changes exactly then. The rest stay in the tray.
- **Return:** the empty carrier docks back (Space at the open port).
- **Single parts:** they can still be taken from the docked carrier one by
  one.
- **In transit:** parts in an undocked carrier count toward cargo needs and
  audits.
- **Targeting fixes:**
  - the crate's inner floor is now part of its body, so looking into the
    open crate targets it;
  - looking at a part stowed in an open container targets that container.

## G. Operational detail, reliability, HUD

- **Environment readout** (Control Room west wall, `environment_readout.gd`):
  live airflow %, filter dP, main bus T-2 voltage, coolant loop flow, sensor
  drift and cargo port status, all derived from equipment state.
- **Test runner:** each test is now bounded:
  - `TEST_TIMEOUT_S` (default 600 s);
  - a test that printed a SCRIPT ERROR and then went silent for
    `ERROR_IDLE_S` (default 20 s) is killed and reported as TIMEOUT instead
    of hanging the suite. Verified with a deliberately hanging probe (killed
    after 3 s; the suite continued).
- **HUD messages:** new writers use `scripts/ui/hud_message.gd`. Messages are
  owner-stamped, and the hide timer is a child of the label, so a scene
  reload no longer fires callbacks into a freed scene. This removed the
  "Lambda capture … was freed" errors seen after loading.

## H. Root causes found while rendering this round

- **Render-harness stall (Round 31 mystery): SOLVED.**
  `RenderingServer.frame_post_draw` is not emitted while macOS isn't drawing
  the window (minimized, occluded, display asleep). Process frames keep
  running: measured +435 process frames and 0 post-draw signals in 3 s
  minimized. Any `await frame_post_draw` then hung silently.
  `render_harness.gd` now waits for post-draw for at most 2 s, then calls
  `RenderingServer.force_draw()`, which is verified to produce a frame while
  minimized, and logs it. The stall report includes the window mode. The
  watchdog caught two such stalls this round before the fix.
- **Status lamps above the ceiling (since Round 31):**
  `EquipmentStatusLamps` computed lamp positions in `_ready()`, when the
  stations' visuals were not yet at their final transforms. The filter and
  coolant lamps landed at y≈6, above the Life Support ceiling, invisible.
  They are now built two frames after ready, and `_top_of()` ignores visuals
  more than 1 m from the station. The lamps, tags and inspection points now
  sit just above each station, and each is reachable by a look ray.
- **Briefing placement:** the full briefing pushed the Overview's station map
  off-screen in the rendered frame. The briefing is now on Home, the first
  screen when sitting down; Overview keeps the action and the priority line.
- **Carrier prompts:** "Space: Unload Parts Carrier" at a container, "Space:
  Dock Parts Carrier" at the port.

## I. Rendered and inspected (Round 33)

- **Screens:**
  - workstation Home on day 1 and day 2 (NEW SHIFT — TODAY IS DAY N);
  - laptop session log on day 1 and day 2;
  - Overview before and after check-in;
  - the inspection work order;
  - cross-check failed ("power logged NOMINAL, now FAULT");
  - verified, then the shift report;
  - the Save/Load screen after saving.
- **POV:**
  - an inspection point with its prompt, and the logged message;
  - the refused save ("Not saved: Finish handling the part first.");
  - the loaded world ("Progress loaded — Day 7.");
  - the carrier at the open port, at the crate, and after unloading
    ("Unloaded 3 parts").
- **External:**
  - storage stock, the loose dropped filter and the loaded carrier in the
    port, each before saving and after loading (identical);
  - the reserve crate after the transfer;
  - the environment readout on day 1 and day 2 (live values).
- **Regression:** bed sit, lie, eyes closed, wake and get up; wristwatch
  raised at five pitches with the mirror.

## J. Known limitations and roadmap

- **One save slot:**
  - no autosave;
  - no mid-minigame save;
  - save and load only from the workstation;
  - loading reloads the scene (about a second);
  - the user-facing save lives at `user://savegame.json` (+ `.bak`).
- **Routine workdays:** they only fill quiet days. The routine
  communications check reuses M02 as-is: its target is not re-randomised,
  so a previously solved dial can complete quickly.
- **Optional morning actions:** no new Living Quarters actions this round
  (the laptop log and the wristwatch remain optional).
- **Readout scope:** the environment readout is one panel. Other
  decorative status lights (Overview's 8-light row) are still static.
- **Roadmap:**
  - autosave at the sleep boundary, with a slot picker;
  - re-randomised comms targets;
  - multiple concurrent orders per day;
  - more live gauges at the equipment itself.

## K. Late fix: startup script errors hidden behind passing tests

The headless smoke start reported 4 SCRIPT ERRORs. The workstation's
`_ready()` built the Home briefing, which called `condition()` on stations
that were not yet ready, so they had no DayPlan reference. The same 4 errors
appeared in 106 of the 107 tests (520 lines), and every one still reported
PASS.

- **Fix:** the first Home render is deferred, and the briefing skips
  stations that are not ready.
- **Runner:** any test whose output contains a SCRIPT ERROR is now reported
  as ERRORS (failed), even if its checks passed. After the fix: 0 SCRIPT
  ERRORs across the suite.
- **Known intermittent:** `test_bed_camera` "get-up: no body snapping"
  measures bone travel per rendered frame. It failed once in five runs
  (0.164 m against the 0.12 limit; typical 0.014–0.057). A single long
  frame under load can trip it. It was left unchanged and is reported.

# Round 34 — Load crash, daily shift, automatic completion, clickable laptop, menus, settings

## A. Save/load crash (release blocker) — root cause and fix

- **Symptom:** your playtest log (`user://logs/godot2026-11-06T18.18.46.log`)
  shows `SCRIPT ERROR: Cannot call method 'set_input_as_handled' on a null
  value at workstation_state.gd:244`, 225 `Condition "!is_inside_tree()"`
  errors from the same `_unhandled_input`, then an abrupt end (hard
  crash).
- **Root cause:** `SaveGame.load_game()` called
  `get_tree().reload_current_scene()` synchronously INSIDE the
  workstation's `_unhandled_input` ([L] key). The old scene was torn down
  while its own input callback was still executing: `get_viewport()`
  became null, out-of-tree transforms were read, and the renderer crashed.
- **Fix:**
  - the save is read and validated first, and a bad save never touches the
    running game ("Load failed: …");
  - the scene change is deferred until after input dispatch and guarded
    against re-entry; New Game uses the same path;
  - the workstation's handler is null-safe.
- **Evidence:** `test_load_via_workstation_input` reproduced the exact error
  through real pushed key events before the fix. After the fix it passes
  (16 checks): three repeated loads, no save, a corrupt save (running
  game kept), and no SCRIPT ERRORs. Your real save (copied, read-only)
  loads cleanly.

## B. Days begin in the bunk

- **Start:** `SleepState.start_day_in_bed()` lies the technician in the
  bunk with eyes closed, then the eyes open into the existing wake (lying,
  wristwatch glance, E sits up and gets up).
- **Used by:**
  - New Game from the main menu, the workstation [N], or the pause menu;
  - loading an AUTOSAVE (the start of a day).
- **Sleep already woke the player in the bunk.**
- **Loading a manual mid-day save** restores the saved position; the
  player is never moved to bed.
- **The day only advances through sleep.**
- **`GameFlow.start_mode`** carries the intent across the scene change. A
  station opened directly (tests, F6) is left as authored.

## C. Ten-minute shift

- **Clock:** `DayPlan.shift_elapsed_s` counts in `_process`, so it stops
  when the tree is paused (the pause menu). Menus and loading are other
  scenes.
- **Duration:** `scripts/station/game_config.gd` `SHIFT_DURATION_S = 600`
  (a central dev setting, separate from difficulty).
- **Sleep before the end:** refused with "Shift in progress — mm:ss
  remaining." The seated prompt shows "Sleep after shift (mm:ss)".
- **At the end:**
  - the shift ends by itself, the report is generated automatically from
    real recorded work, and "Daily shift ended — you may return to your
    quarters." is shown;
  - nobody is teleported, and overtime is allowed;
  - unfinished unrestored work carries over (Round 33 rule).
- **Persistence:** the clock is saved and restored.
- **Shown on:** the workstation Work Orders (SHIFT mm:ss remaining /
  SHIFT ENDED + report), the wristwatch (third token) and the laptop
  Shift Report app.

## D. Automatic completion (event-driven)

- **Re-evaluation:** every recorded fact or task re-evaluates the open order
  (`DayPlan._auto_advance()`).
- **Equipment restored:** the self-test VERIFIES automatically (electrical
  c05 / "verified"). Step labels now say "(automatic)".
- **Verified and cleanup done:** the order CLOSES automatically
  ("<System> complete.").
- **Cleanup stays mandatory:** the used filter must be disposed of before
  closure.
- **Routine inspections:** the cross-check runs automatically on the last
  reading; a stale reading is cleared with "Cross-check failed — re-read:
  …".
- **Cargo duty:** opens with each shipment and completes itself once
  received, every part put away (none left in the carrier) and the hatch
  secured.
- **Removed:** the manual "Submit end-of-shift report" action. The
  workstation [R] still works, idempotently, and never reopens a closed
  job.

## E. Clickable laptop and Personal Log

- **Click bodies:** `laptop.gd` adds two pickable-only click bodies, the
  whole laptop and the screen.
- **Mapping:** `screen_uv()` maps a world hit to screen pixels from geometry
  (the screen's local X = height, toward the hinge = down; local Z = width,
  with "right" taken from the viewer's camera), not from the rotated/flipped
  CSG UV convention.
- **Seated on the bunk:** looking at the laptop shows "Click: Open Laptop"
  and a click opens it.
- **Screen:** an app bar — **Personal Log**, **Shift Report**, **Close
  Laptop**; while editing, **◀ Back** and **Save**.
  - Clicks use the reticle; while editing a visible cursor is used (the
    camera is locked on the screen).
  - Clicks are delivered into the SubViewport as real mouse events.
- **F/T** remain optional shortcuts.
- **Log content** is preserved and saved.

## F. Small loose parts no longer block walking

- **Root cause:** a landed part went back to collision layer 1, which the
  player capsule collides with (mask 1|4), and the capsule has no step-up.
  A 9 cm filter was a wall.
- **Fix:** small loose parts rest on the pickable-only layer 16:
  - the interaction ray (1|16) still hits them;
  - the drop proxy still lands on floors and furniture (mask 1|4);
  - the player walks over them;
  - held parts are still layer 0 (they never push).
- **Exception:** the parts-carrier tray stays solid.
- **Test:** proven by `test_loose_parts_walkable`, which fails with the old
  layer.

## G. Menus and settings

- **Main menu** (`scenes/ui/main_menu.tscn`, now the project's main scene):
  - Continue (newest valid slot);
  - New Game (asks first if a save exists; never deletes it);
  - Load Game (manual + autosave slots, with day and time);
  - Settings, Credits (only verifiable facts), Quit.
- **Pause menu** (`PauseMenu`, Esc): Resume, Save (disabled with the reason
  when unsafe), Load, Settings, Return to Main Menu, Quit.
- **Esc priority:** a seated workstation, an open laptop or editor, a
  focused equipment panel, or sleeping keeps Esc. Esc in the pause menu goes
  back or resumes.
- **Settings** (`GameSettings`, `user://game_settings.cfg`, independent of
  saves), all applied for real:
  - volumes for the Master/Ambient/SFX/UI/Voice buses
    (`default_bus_layout.tres`; ambience → Ambient, effects and footsteps →
    SFX);
  - fullscreen and window size;
  - mouse sensitivity and invert Y (read by `look_controller.gd`);
  - language.
- **Localization:** runtime `Translation` tables (en, zh_CN) for menu,
  pause, settings, credits and a few prompts, with a CJK system-font
  fallback behind the default font. The rest of the game is still
  English-only.

## H. Autosave and persistent ids

- **Autosave slot** `user://autosave.json` (+ `.bak`): written atomically
  only after a completed sleep → new-day wake. It is never the manual slot,
  and only in the real game flow, so tests and F6 never write the player's
  autosave.
- **Shared writer:** both slots use the same atomic writer (tmp → validate →
  .bak → rename).
- **Schema v2:** each item record carries a stable `pid` (an explicit
  `persist_id` meta, else its deterministic node name). `PID_ALIASES` maps
  renamed ids; v1 saves (no pid) still load.

## I. Task guidance

`DayPlan.guidance()` gives the ONE next physical step (the open work order
first, then the cargo duty) with a short form. It advances by itself as
facts arrive.

- **Shown on:** Work Orders (NEXT: …), the Home briefing (Priority) and the
  wristwatch ("REPLACE FILTER / LIFE SUP · 07:12").
- **Cargo steps:** CARGO ID → OPEN HATCH → RELEASE → CARRY TRAY → UNLOAD
  TRAY → CONFIRM → RETURN TRAY → SECURE HATCH.
- **Inspection steps:** LOG FILTER / LOG COOLANT / LOG POWER / AUDIT SPARES
  …

## J. Workload policy (Priority 14)

| Day type | Assignments |
| --- | --- |
| Quiet | one routine inspection or comms check (no service due) |
| Normal | one maintenance order; on delivery days plus the short cargo duty |
| Busy | the electrical repair (longest), plus at most the cargo duty |

Never more than one maintenance order plus the cargo duty per shift.
Guidance orders them deterministically (order first). Difficulty stays
separate from task volume and shift length.

## K. Future station AI (Priority 12) — design only

- **What it is:** a station operations AI (voice and console text, no body
  at first) that introduces the job on day 1:
  - the workstation briefing;
  - inspections at the status tags;
  - Storage and typed spares;
  - the cargo port and carrier.
- **Behaviour:**
  - event-driven: it subscribes to `DayPlan.task_completed`,
    `workday_step_completed`, `notify`, `shift_ended_signal` and the
    `guidance()` changes;
  - it speaks only on a NEW first-time event or after a long idle on the
    same step;
  - skippable and mutable (Voice bus + a setting), with no separate
    progression system.
- **Implementation:** a `StationAI` node with a line table keyed by event
  and a "first time" set saved in DayPlan.
- **Later:** it can become narratively important; no hidden identity
  early.

## L. Future personal laptop (Priority 13) — foundation in place

The app bar is the extension point: each app is a button plus a view in
`session_log_screen.gd`.

- **Planned apps:**
  - messages (fictional, authored);
  - photos (fictional placeholders until the author supplies real ones);
  - a daily schedule;
  - an ORIGINAL falling-block puzzle (own rules and art; no commercial
    assets or branding).
- **No anomalies yet.** Later horror can alter familiar files subtly.

## M. Found while rendering this round, and test status

- **Wrong prompt while lying awake (since Round 31):** the HUD read "E: Sit
  Down" while lying awake in the bunk. The interaction controller (re-enabled
  on wake) overwrote the sleep state's prompt. The sleep state now owns the
  prompt whenever the player is on the bunk ("E: Get Up · Sleep after shift
  (mm:ss)").
- **Pause menu during transitions:** the pause menu no longer opens during a
  workstation sit/stand transition. Pausing froze the stand-up tween;
  `test_workstation_sitdown` caught it.
- **Notification over the raised watch:** while the watch is raised, HUD
  notifications move to the top of the screen; they had covered the watch
  face.
- **Small UI fixes:** the settings checkboxes are now labelled "On"; the
  credits text wraps cleanly; the Work Orders [R] hint is hidden once the
  order is closed.
- **Tests:**
  - **New this round (8):** `test_load_via_workstation_input`,
    `test_loose_parts_walkable`, `test_laptop_clicks`,
    `test_shift_day_system`, `test_menus_settings`, plus the reworked Round
    33 routine/inspection tests.
  - **Updated to the new rules:** automatic completion, the shift clock,
    the laptop prompt, the loose-part layer.
- **Load-sensitive tests:** `test_gait_footsteps` (foot slide) and
  `test_animation_transitions` (watch→idle blend) measure motion per frame.
  Each failed once in a full suite run while the machine was swapping (0.68
  m/s, 0.375 m/tick), and passed 3/3 when rerun (0.16 m/s, 0.059 m/tick).
  They were left unchanged and are reported as timing-sensitive.

# Round 35 — Five physical maintenance tasks, station consequences, busier days, simpler workstation

## A. Interface

- **Workstation Settings ([6]):** the SAME `GameSettings` store as the main
  and pause menus (`user://game_settings.cfg`): difficulty, five bus
  volumes, fullscreen, window size, mouse sensitivity, invert Y, reduce
  visual effects, language.
  - Up/Dn selects a row and Left/Right (or [R]) changes it; changes apply
    immediately.
  - Verified: the main-menu panel shows the same values, they are
    persisted, and the language updates live.
- **Laptop:**
  - clicking the visible log TEXT opens the zoomed editor, the same as
    [Personal Log];
  - [< Save & Back] returns to the desktop;
  - the reticle is fed to the screen as mouse motion, so on-screen buttons
    show hover highlights.
- **One-line Work Orders:** each assignment is ONE row:
  `TAG — next physical action · Room  progress` (for example
  "BREAKER — Reset breaker B-02 · Engineering  c/o 3/4").
  - Rows advance by themselves from equipment state.
  - Up/Dn selects; Enter opens an optional detail panel (full step list,
    breaker table, seal sections, channel states …); the
    REPORT row appears when the shift ends.
  - Labels are kept short (≤ 56 chars); truncation is only a fallback.
- **Home** is a 7-line briefing (systems, duties + shift clock, priority,
  cargo, carry-over).
- **Watch:** one objective, destination and time.
- **Fonts:** the default font lacks ▶ ↑ ↓ ← → ✓ ↺ ◀ ▲ ▼, which rendered as
  blanks in the frames. ASCII replacements are used: `>`, Up/Dn,
  Left/Right, done, c/o, <, +/−.

## B. Task categories and concurrent orders (DayPlan)

- **Categories:** A quick (5–20 s), B interactive (20–90 s), C full job
  (2–5 min), D multi-room chain (2–6 min). Category is time/complexity;
  difficulty only changes assistance and tolerances.
- **Orders:** the main workday stays as it was. The new tasks are ORDERS in
  `DayPlan.orders` ({id WO-nnnn, type, category, priority, day, seed,
  status, carried_from}).
  - The EQUIPMENT is authoritative and answers `order_done()`,
    `order_next()`, `order_progress()`, `order_detail()`,
    `order_feasible()` and `order_rearm(seed)`.
  - DayPlan polls and closes each order automatically.
- **Schedule:**
  - One new type is introduced per early day: breaker d2, vent d3, loads
    d4, seal d5, data d6. The newcomer gets a +2 budget allowance, so its
    introduction never stalls.
  - Each day is then filled up to a time-weighted budget: quiet 7 / normal
    9 / busy 11 points (A1, B2, C/D3; main job 3; cargo 2). Day type is
    seeded; days 2–3 are always quiet.
  - The schedule is deterministic by day seed; there are no duplicate open
    types; no hatch-seal order is issued on a cargo day (interlock); an
    unfinished order carries over ("c/o").
  - Observed in tests: 2–6 concurrent duties.

## C. The five tasks

- **Breaker (Engineering west wall, `breaker_panel.gd`):** B-01 Quarters,
  B-02 Life Support (also the fans), B-03 Engineering, B-04 Comms
  lighting.
  - A trip puts out that zone's main light and turns on a dim red
    emergency light.
  - Resetting is refused while the cause is present: the unrepaired wiring
    fault (B-03), or an active overload. Switching a healthy breaker off is
    a real, recoverable mistake.
- **Vent grille (Life Support west wall, `vent_grille.gd`):** two clips →
  hinged cover → four duct sections with real dirt (drawn as a debris layer
  that fades as you scrub) → close → secure.
  - Efficiency = 1 − 0.4 × mean dirt, which feeds airflow.
- **Power distribution (Engineering south wall, `power_distribution.gd`):**
  three channels with +/− controls, load bars, lamps and a bus voltmeter.
  - Bus V = 28 − 0.6 × Σ|setting − demand| (−1 V while overloaded).
  - An overload (excess ≥ 2) trips B-03 after 45 s.
  - An under-powered LS-FANS channel cuts airflow.
  - The order completes after 4 s of stable balance.
  - EASY shows targets, NORMAL shows UNDER/OK/OVER, HARD shows bars and
    voltage only.
- **Hatch seal (airlock, `hatch_seal.gd`):** four sections with
  debris/misaligned-clip faults, an inspection-mode lever and a
  pressure-hold test.
  - Faults leak and lower cabin pressure; the test passes only with no
    faults and the hatch secured.
  - Cargo interlock both ways.
- **Data transfer (`data_port.gd`, `data_module.gd`):** module DM-7 is a real
  carried item.
  - Control upload port → Engineering capture port (records REAL readings
    plus a station-state signature) → back to Control.
  - Data captured before a change to loads, breakers, wiring or sensors is
    STALE and rejected.

## D. Environment

- **`environment_model.gd`:** airflow (filter × vent × fans), cabin pressure
  (seal leak) and O₂ partial pressure (follows airflow). They are separate
  variables with slow time constants, fully reversible, never fatal.
- **Effects:** MILD gives a faint vignette; SIGNIFICANT gives a stronger
  vignette plus a slight slow view drift (≤ 6 mm offset, no roll or blur),
  with a HUD warning. "Reduce visual effects" disables the visuals but keeps
  the warnings.
- **The readout** adds cabin pressure, O₂, bus A and tripped breakers.

## E. Audio

New synthesized SFX: breaker snap, relay, seal-test hiss, latch, module
insert, warning tone, power down/up and scrub. They play one at a time on the
SFX bus.

## F. Save/load

- **New sections:** `equipment2` (each new device's `state_dict()`),
  `environment`, the data module's payload and its `dataport` owner, and
  DayPlan `orders`/`day_type`/`_order_seq`.
- **No re-roll:** loading restores state; nothing is regenerated.
- **New safe-save blockers:** data transfer in progress, pressure test
  running.
- **Test:** `test_r35_save` covers a mid-task save into a fresh station.

## G. Intermittent animation tests — root causes

- **`test_animation_transitions`:** under load Godot runs catch-up physics
  ticks (two ticks inside one render frame shorter than 2/60 s). The probe
  assumed one tick and over-read motion by up to 1.7×. It now counts the
  ticks.
- **`test_gait_footsteps`:** foot-slide time was wall-clock milliseconds
  between bunched samples. It now uses counted physics ticks.
- Thresholds are unchanged. Reruns: 0.072–0.074 m/tick (limit 0.1) and
  0.16 m/s (limit 0.45).

## H. Tests and limitations

- **New tests:** `test_r35_equipment` (49 checks), `test_r35_scheduling_ui`,
  `test_r35_save`; `test_laptop_clicks` extended.
- **Limitations:**
  - workstation settings are keyboard-driven (no mouse on that screen);
  - only lighting zones are wired to breakers (no other equipment
    shutdown beyond the fans);
  - the seal's good state is subtle visually;
  - pre-existing minigame views still use ▲▼←→ glyphs.

# Round 36 — Station Operations Assistant (voice), interaction fixes, filter variants, thermal probe

## A. Vent grille retaining clips (Priority 1) — root cause and fix

- **Reproduced first** (`test_vent_clips`, real interaction ray, nine standing
  positions straight/left/right/near/far/looking down, aiming at the centre of
  the VISIBLE clip):
  - clips released, cover closed (the re-secure case): **0 / 18** hits —
    the ray hit nothing, the airflow gauge, or the grille cover;
  - clips secured: 9 / 18.
- **Root causes (two):**
  1. **The visual moved, the collider did not.** Releasing a clip slid its
     mesh 7 cm right (x 0.22 → 0.29) while its click box stayed at x 0.22:
     the box spanned x 0.18–0.26 and the released mesh x 0.26–0.32 — no
     overlap. Aiming at what you saw missed (or hit the gauge).
  2. **The cover's click box covered the lower clip from above.** The cover
     box (y ±0.20, z to 0.039) sat directly above the lower clip's box
     (y −0.20 to −0.25, z 0.005–0.055). From standing eye height (1.6 m, the
     grille centre is at 1.1 m) the ray to the lower clip passes through the
     cover box first — and clicking the cover of a closed grille with both
     clips released **reopened the grille** instead of latching it. That is
     the "lower clip often cannot be secured" report; the upper clip has
     nothing above it, so it worked "sometimes" (depending on where you aimed).
- **Fix (`vent_grille.gd`):**
  - each clip is a TURN LATCH on the frame (pivot `Clip0`/`Clip1`, lever
    `Lever`): secured = the orange lever stands across the cover's edge in
    front of the plate (it visibly holds it shut); released = grey lever
    turned 90° to lie along the frame, clear of the cover;
  - ONE fixed click volume per clip (11 × 10 × 6 cm) encloses BOTH lever poses
    — the target never drifts from the hardware;
  - the cover's click volume stops 3.5 cm short of the top/bottom edges, so it
    is never in front of a clip from any standing angle;
  - frame enlarged so the clips sit on it (no floating hardware);
  - prompts name the clip ("Click: Secure lower clip"); with the cover open a
    clip says "(close the grille first)" and refuses (the lever would block
    the cover); serviced = clean + cover closed + both clips secured.
- **After:** 18/18 from every stance in both states; 2–2.5 cm off-centre still
  hits; either order; open/close without cleaning; partial cleaning; reopen
  after completion; repeated cycles; save/load with the cover open and with
  exactly one clip secured (31 checks).

## B. Diagnostic module return / undo (Priority 2)

- **Root cause:** neither data port had anything hoverable while EMPTY. The
  carry system's Space "stow" needs a hovered receptacle with
  `accepts_item()`; with none, an unused module could only be dropped.
  (The existing tests called `port.stow()` directly, so they never saw it.)
- **Fix:**
  - `click_part.gd` can be a RECEPTACLE: `accepts_item/stow/stow_hint` are
    forwarded to the owning equipment (`part_accepts_item`, `part_stow`,
    `part_stow_hint`); `interaction_controller.gd` uses the hint for the
    "Space: …" line; `carry_system.gd` lets a receptacle report its own
    outcome (no generic "Stowed:" overwrite);
  - each data port has a real SOCKET part (`Click_slot`); Space or a click
    seats the module;
  - one payload state machine, `data_port.payload_state()`: `empty`, `ready`
    (valid for the open request), `stale` (station changed since capture OR
    captured before today's request), `uploaded`, `data` (no request);
  - contextual hints: "Return empty module to dock", "Insert module for
    capture", "Insert module: upload diagnostic data", "Insert module (data
    STALE - recapture required)"; the module's own prompt and screen show the
    state (EMPTY / DATA D5 / STALE D5 / SENT D5);
  - an EMPTY module in the Control dock is simply DOCKED (no fail sound, no
    progress); data from before today's request is now STALE (it used to be
    accepted if the station signature matched);
  - the "no removal during transfer" guard now works (the module sits in the
    port's slot node: the guard looked one level too high and never ran).
- Single-item carry, one owner, save/load of docked/carried/empty/captured/
  stale: unchanged architecture (`test_data_module_return`, 36 checks, real
  Space key events).

## C. Filter service variants (Priority 3)

- **What was fixed before:** target keyway 135°, replacement start rotation
  0°, both latches engaged, old cartridge seated — identical every service;
  nothing about the condition was per-service state.
- **Four legitimate conditions of the same fixed housing**
  (`filter_housing_station.gd`, `Variant`):

  | Variant | Found as | Correction | New cartridge starts at |
  | --- | --- | --- | --- |
  | STANDARD | both latches engaged, cartridge on its keyway | normal | 0° |
  | LOOSE_LATCH | latch L2 already released (hanging open) | release L1 only; L2 must still be re-engaged | 270° |
  | SEIZED_LATCH | latch L1 crusted with residue | three firm pulls work it free, then it releases | 90° |
  | COCKED | old cartridge turned 90° off its keyway | turn it back to the mark before it will pull out | 180° |

  The old cartridge's contamination differs per variant (dust / heavy dust /
  oily residue / soot). The focused view states what was found ("Found: …")
  and shows it (released latch, residue crust, the old cartridge's own keyed
  tab off the mark).
- **Selection:** `DayPlan.register_service_variant()` — called ONCE when a
  NEW filter service event is generated (first-time or due; never on
  carry-over, reload, or reopening), deterministic by the day seed, never the
  same as the previous service. In-progress procedures are never re-rolled.
- **Saved:** `_variant`, `_last_variant`, `_variant_day`, `_old_angle_deg`,
  `_seize_left` (plus the existing stage/latches/angle). Older saves load as
  STANDARD.
- Physical cartridge, inventory ownership, used-cartridge ejection, disposal
  and automatic closure are unchanged. Multi-day tests now use
  `tests/filter_service_solver.gd`, which completes any variant through the
  station's own public calls.

## D. Darker breaker outages (Priority 4)

- **Why it was still bright:** each breaker switched off ONE OmniLight, while
  the global `WorldEnvironment` ambient (0.25) kept lighting every surface
  everywhere, and the red emergency light was strong (0.6 over 5 m).
- **Now (`breaker_panel.gd`):**
  - each lighting circuit owns every normal light in its room (Quarters now
    includes the bunk light);
  - during an outage a `ReflectionProbe` over that room's volume overrides
    the ambient there (`ambient_mode = COLOR`, 18 % of the normal fill). It
    exists only while the breaker is off, so normal lighting is bit-for-bit
    unchanged and no other room darkens;
  - a restrained red emergency light (0.32, range 3.6 m) stays on high on the
    room wall;
  - a dim amber battery LOCATOR light on the breaker panel comes on whenever
    any breaker is off, so the panel stays findable even with Engineering
    dark;
  - the flashlight is untouched.
- **Rendered, same camera:** Life Support mean luminance 41.4 normal → 13.7
  tripped (−67 %) → 41.4 restored; Engineering 34.1 → 13–18 → 34.1; the
  Control Room next door stays 73.6 throughout. Save/load during an outage
  restores the dark state.

## E. Station Operations Assistant (Priority 5)

- **What it is:** a calm, impersonal station automation voice over the
  internal speakers, with a one-line caption and a small source light
  (`STATION OPS`). No body, no portrait, no supernatural hints, no identity.
- **Architecture:**
  - `scripts/station/station_ai.gd` (node `StationAI` in main.tscn);
  - `scripts/audio/speech_provider.gd` (speech backend).
- **Triggers — event-driven from REAL state only (no parallel quest system):**
  - `DayPlan.order_rows()`: each assignment's next physical step (`short`)
    → step lines; completion → acknowledgement;
  - the day-1 orientation fields (c01 / e06 / c05 / c02 / e05);
  - arriving within ~2 m of equipment whose task is OPEN (first time) →
    that procedure's lesson;
  - real alarms: a new breaker trip (outage / overload trip), Bus A overload,
    cabin pressure / O₂ severity;
  - equipment hooks via `event()`: cargo/seal interlocks
    (`equipment_base.ai_event()`, `cargo_port.gd`) and the missing filter
    cartridge.
- **Priority:**
  - safety > first-time instruction > information;
  - a safety line interrupts anything lower and has a 75 s cooldown;
  - non-safety lines keep their order, wait while a focused equipment view is
    open, during sleep/wake (eyes closed) or the workstation sit/stand tween,
    and while paused;
  - a non-safety line interrupted by a focused view replays afterwards.
- **No nagging:**
  - every lesson plays once (the `taught` set);
  - step and completion lines for a task only play after its equipment
    lesson (i.e. the player is actually doing that job);
  - later services of the same task are silent — DayPlan's HUD notices
    remain.
- **First day:** greeting → job → wristwatch (C) → "Press E to get up, then
  report to the Control Room" (or "Report to the Control Room" when not in
  the bunk) → at the workstation: Home / Work Orders, check in (Overview,
  R), orders close automatically → day-1 slices (loose connection,
  verification, diagnostic, fault, repair) → equipment lessons as they come
  up.
- **Later days (Priority 8):** one line on waking: "Day 5. Three assignments
  are scheduled. Power restoration is the current priority. Life Support
  filter service can follow." — from the real rows, never reading the whole
  list. Shift end: a full line the first time, then just "Shift complete."
- **Lessons covered:**
  - workstation, wristwatch, electrical service, Storage, breaker, power
    distribution, vent, hatch seal (+ interlocks), diagnostic transfer,
    thermal survey, filter service (+ missing part, disposal), calibration,
    coolant routing, comms check, inspection round, cargo (+ return tray),
    disposal, shift end / sleep;
  - plus alarms.
- **Controls:**
  - **H** repeats the last instruction (or states the current task from
    `DayPlan.guidance()`);
  - **J** skips the current line;
  - the player is never locked and never has to wait.
- **Settings** (`GameSettings`, in the menu settings panel AND the
  workstation [6]): Assistant guidance (on/off), Assistant voice (off =
  captions only), Assistant captions. Speech volume = Master × Voice
  settings; Voice 0 mutes.
- **Caption placement:**
  - top-centre (y 98–170), below the wristwatch label and the raised-watch
    message position;
  - low (above the task-message line) while seated at the workstation, so
    the screen stays clear;
  - top-right over a full-screen equipment view (safety lines only).
- **Localization:** EN and Simplified Chinese caption tables; speech follows
  the language.
- **Save/load:**
  - `station_ai` section: taught lessons, intro done, last day announced,
    last instruction;
  - loading never replays the intro;
  - a pre-Round-36 save (no section) is treated as already oriented;
  - a New Game starts fresh.

## F. Speech backend — what is real and what is not

- **Speech providers, in order:**
  - **Recorded voice files** `res://audio/voice/<lang>/<key>.ogg|wav` on the
    Godot Voice bus. **None exist** — none were invented; this is the seam
    for recorded voice later.
  - **Platform text-to-speech** through Godot's `DisplayServer.tts_*`
    (enabled by project setting `audio/general/text_to_speech=true`). On this
    Mac: AVSpeechSynthesizer, voices **Samantha (en-US)** and **Tingting
    (zh-CN)**.
  - **None (captions only)** with an honest reason (headless display, setting
    off, no installed voice).
- **Verified for real** (`tools/verify_station_ai_speech.gd`, real display):
  - an English and a Chinese line were spoken (the OS synthesizer reported
    speaking, then finished: 5.8 s and 4.8 s);
  - a safety line interrupted an instruction (one voice at a time);
  - Voice 0 muted;
  - freeing the station mid-sentence stopped the speech;
  - clean exit.
- **Limitations:**
  - OS TTS does not pass through Godot's audio buses (the Voice/Master
    settings scale its volume parameter instead);
  - Godot's movie writer cannot record it;
  - voice quality depends on installed OS voices;
  - on other platforms the voice list differs — not verified here.
- **No synthesizer callbacks:** an utterance callback left registered at exit
  crashed the process (`libc++abi … recursive_mutex lock failed`) in a probe.
  The provider polls `tts_is_speaking()` instead and always stops on exit.
- A short synthesized two-tone "PA chime" before each line plays on the
  Godot Voice bus.

## G. Airlock seal fault visibility (Priority 6)

- **Generation was valid:** every seal order had 1–2 faults (now checked
  over 60 seeds).
- **What was wrong:** the fault was a 4–5 cm coloured box that could not be
  told apart from a healthy rim at standing distance (confirmed in renders).
- **Now (`hatch_seal.gd`):** physical hardware per section, visible before
  inspection:
  - **debris**: a pale fibre wad and grit lodged on the gasket;
  - **misaligned clip**: one steel bracket twisted 40°, tipped and lifted off
    the gasket, with a bright strip of bare channel where the gasket has
    lifted;
  - **rolled lip** (new): a length of gasket bulging out of its groove,
    exposing the bare metal channel.
- Healthy sections show two aligned brackets for comparison. An inspection
  lamp over the hatch lights in INSPECT mode.
- Prompts and work-order lines name the correction (Remove debris / Realign
  clip / Reseat gasket). The hold test reflects the real leak; corrections
  persist; save/load restores the exact faults; the cargo interlock is
  unchanged both ways.

## H. Portable thermal probe survey (Priority 7)

- **New order type** `thermal` (category D, from day 7):
  "Thermal survey: power terminals".
- **Probe TP-3** (`thermal_probe.gd`): a real carried tool (body, orange grip,
  sensing tip, readout). It lives in its charging/data dock on the Control
  Room west wall (`thermal_survey.gd`, node `Equipment/ThermalSurvey`).
- **Terminal block TB-A** is new hardware under the Engineering power
  distribution panel: three cable-lug terminals (A1 LS-FANS, A2 ENG-AUX,
  A3 COMMS), each with a measuring point and a lug nut.
- **Temperature from REAL state:**
  - `T = 28 + 9 × setting`, plus `8 × excess load` (doubled while
    overloaded), plus 44 if that lug is loose;
  - abnormal when more than 12 °C above the expected value for the load;
  - so an overloaded channel reads abnormal too.
- **Procedure and reasons to travel:**
  - The order loosens one lug, and all lugs look alike — only the probe
    finds which one.
  - Take the probe → measure A1–A3 → re-torque the hot lug. This is only
    allowed once it has been measured hot: "don't disturb a live joint
    without a reason".
  - Re-measure: readings taken before a change are outdated.
  - Dock the probe in Control; docking uploads the survey. The order closes
    only with three current normal readings AND the probe docked.
- **Recovery:** the probe can be docked unused or mid-survey at any time
  (nothing is lost) and never gets stuck.
- **Save/load:** tool location (dock / hand / loose), readings, the armed
  fault, request / upload state.
- **Saving:** blocked during a 1.1 s measurement.

## I. Other fixes found this round

- **Player settings wiped by the difficulty writer (pre-existing,
  Round 10/34):**
  - `GameSettings._save()` wrote a NEW config file holding only the
    difficulty, discarding the `player` section (volumes, language,
    window…);
  - every save/load test calls `set_difficulty()`, so each full test run
    reset the player's settings file — on this machine it held only
    `difficulty=1` when inspected this round. Values lost earlier cannot be
    recovered.
  - **Fixes:** `_save()` now keeps the other sections, AND the test runner
    gives tests their own file (`SMH_SETTINGS_PATH=user://test_game_settings.cfg`,
    `GameSettings.settings_path()`), so the suite never touches the player's
    settings again.
- **Chinese text rendered blank (pre-existing, Round 34):**
  - a `SystemFont` resolves only the first of its `font_names`;
  - "PingFang SC" cannot be loaded by FreeType on macOS (every launch logged
    `FreeType: Error loading font: ''`), so the CJK fallback was dead;
  - `localization.gd` now probes each candidate and uses the first with CJK
    glyphs (Hiragino Sans GB here). Zh menus, settings and captions render
    (seen in renders); the FreeType errors are gone.

- **Regression caught by the full suite, fixed:**
  - the assistant's H/J keys were also taken while the laptop log editor
    was open, so typed "h" letters disappeared (5 laptop/editor tests
    failed);
  - H/J now only act in free roam (interactions enabled); the editor,
    the seated workstation and the focused views keep the keyboard.
- **Caption placement**, found in renders:
  - a non-safety line in progress when a focused view opens is paused and
    replayed afterwards, instead of covering the view's title;
  - captions move low while seated at the workstation.

## J. Tests and rendered verification

- **New tests (6):**
  - `test_vent_clips` (31 checks)
  - `test_data_module_return` (36)
  - `test_filter_variants`
  - `test_r36_lighting_seal`
  - `test_thermal_probe` (32)
  - `test_station_ai` (41)
- **Helper:** `tests/filter_service_solver.gd`.
- **Updated to the new rules:** the multi-day filter tests and
  `test_save_load` (solver); `test_menus_settings` (settings path).
- **Real-display tool:** `tools/verify_station_ai_speech.gd`.
- **Rendered and inspected** (scratchpad, not committed):
  - outage normal / tripped / restored (Life Support, Engineering, Control
    unchanged);
  - vent clips secured / released / opening / open / cleaned / closed with
    clips released / single clip states / after service / side close-ups;
  - module docked / carried with the return hint / returned / captured /
    ready for upload;
  - all four filter variants plus seized-pull and cocked-removal;
  - seal healthy / faulty / inspect lamp / close-ups / repaired PASS;
  - probe docked / carried / at TB-A / measuring / HOT reading / returned;
  - assistant greeting, breaker and vent lessons, caption with the watch
    raised, disabled, zh caption, safety caption over a focused view;
  - workstation Home / Work Orders / Settings with the assistant rows; bed;
    main menu; settings panel EN / ZH.

## K. Known limitations

- Speech is OS text-to-speech, not recorded voice acting; it bypasses the
  audio buses (volume is scaled instead) and is verified on macOS only.
- Dynamic "current task" repeats (H) speak the English action text in
  Chinese mode.
- The filter variants and seal faults are deliberately small, realistic
  details; the focused view's "Found:" line and the prompts carry the
  meaning.
- Only one portable instrument (the thermal probe) was added — chosen over
  three similar tools.
- The laptop was not re-rendered open this round; its automated tests
  still pass.

# Round 37 — Visual-first operations: emergencies, map-first workstation, spatial intercom, UI scaling, six-gauge sync

## A. Fullscreen UI scaling (Priority 1)

- **Root cause:** `project.godot` had no `[display]` stretch settings, so
  every screen-space Control kept its pixel size. In fullscreen
  (2880×1800 on this Retina Mac, or 1920×1080 / 4K) the 340 px pause panel
  and 16 px buttons shrank to a small patch.
- **Fix:**
  - `display/window/stretch/mode = "canvas_items"`, `aspect = "expand"`,
    1152×648 base: menus, HUD and captions scale with the window; the 3D
    view still renders at native resolution;
  - a new **Interface scale** setting (80–150 %) multiplies the factor
    (`root.content_scale_factor`);
  - the settings list scrolls inside a fixed area with Back always visible
    (it no longer fit the base height).
- **Mouse hit areas:** follow the stretch transform automatically.
- **Verified:**
  - **Test:** the pause panel keeps the same screen fraction (54 %) at
    1152×648 / 1920×1080 / 2560×1440 / 3840×2160; buttons stay on-screen;
    a click at the Resume button's real window position presses it.
  - **Rendered:** windowed 1280×720 and real fullscreen 2880×1800 look
    identical in proportion; switching back to windowed works without a
    restart.

## B. Six calibration gauges (Priority 2)

- **Root cause:** the focused view owned the six chambers' values and
  reset them on every open ("the next attempt starts clean"). The physical
  station had one static decorative dial.
- **Now:** `sensor_calibration_station.gd` owns the ONE state —
  setpoints, readings, velocities, damping, coupling, active count:
  - the view adopts those very dictionaries while open (shared
    references) and writes the damping back;
  - with the view closed, the station keeps integrating the same
    coupled springs;
  - six real dials (A–F: face, ticks over the same 280° sweep, a green
    target mark, a red needle, an in-range lamp) always show
    `cal.reading`.
- **Persistence:** a calibration TASK is one instance keyed by day + drift
  seed: never reset on reopen, saved/loaded exactly (`state_dict`), and a
  new recurring drift starts a new instance. Outside a task, opens are
  practice attempts, as before, still written into the station state so
  the dials stay truthful.
- **Proof:** `test_r37_calibration_gauges` (dial error ≤ 0.04 units, open
  / partial / closed / reopened / loaded / completed / new drift).
- **Rendered:** before, focused, partial, after close, calibrated, at
  0.75 m and 1.3 m.

## C. Station intercom speakers and spatial voice (Priority 3)

- **Speakers** (`station_speakers.gd`): eight ceiling-mounted units, no
  colliders —
  - Living Quarters, Control, Engineering, Life Support, Storage, Comms,
    Airlock, and the main junction (corridors);
  - each has a grille, trim ring, an LED and a faint glow while sounding.
- **Unit selection:** the player's room's unit, else the nearest; chosen
  at the start of a line and kept for the whole line.
- **Spatial voice (real):**
  - macOS's built-in `say` renders each line to a 16-bit WAV on a worker
    thread, cached in `user://voice_cache/`;
  - it is loaded at runtime (`AudioStreamWAV.load_from_file`) and played
    by the chosen unit's `AudioStreamPlayer3D` on a new **Intercom** bus
    (high-pass 220 Hz, low-pass 6.2 kHz, faint short reverb), which sends
    into **Voice**, so the Voice/Master settings and mute apply directly;
  - static lines are pre-rendered in the background; render tasks are
    awaited on exit;
  - local only: no network, no credentials.
- **Fallback:** where `say` is missing (other OSes), or a render fails,
  the Round 36 OS TTS speaks (non-positional). The source unit's light
  still shows; the backend string says which is in use.
- **Measured on the audio device** (`tools/verify_spatial_voice.gd`,
  Intercom bus peak meters, Engineering speaker):

  | Listener position | Left | Right |
  | --- | --- | --- |
  | Facing the speaker | −16.0 dB | −15.7 dB |
  | Speaker on the right | −22.4 dB | −16.3 dB |
  | Speaker on the left | −13.2 dB | −19.3 dB |
  | 8 m away | −29.4 dB | −29.9 dB |

  The assistant's own line played spatially from that unit (−4.6 dB
  peak). This is level-meter evidence, not human listening.
- **Voice character:** Samantha at 168 wpm (Tingting at 185 for Chinese),
  pitch 0.985, intercom band-limiting, subtle room.

## D. Emergency severity (Priority 4)

- **Severity scale:** 0 normal, 1 routine, 2 warning, 3 emergency, each
  from the equipment's own `order_severity()`:

  | Equipment | Routine | Warning | Emergency |
  | --- | --- | --- | --- |
  | Vent | dirty | airflow < 80 % | — |
  | Breaker | — | tripped (room dark) | — |
  | Seal | — | leaking | — |
  | Data | transfer | — | — |
  | Thermal | survey | hot terminal measured | — |
  | Power | imbalance | LS fans under-powered | Bus A overloaded |
  | Electrical workday | — | unrepaired | — |

- **Timed emergency:** the only one today is a Bus A overload, whose real
  consequence is the B-03 trip:
  - routine balancing orders can no longer START overloaded (that used to
    run the trip timer while the player slept);
  - overloads come from `DayPlan.plan_emergency()`: from day 5, about one
    day in four (14 of 80 days measured), at a fixed shift time between
    2:00 and 5:00 (day seed);
  - `power_distribution.surge()` drops one channel's demand so its output
    exceeds it by 2; an emergency balancing order opens.
- **Countdown length:** `OVERLOAD_TRIP_S` raised 45 → 90 s. Route lengths
  to the panel are 1–16 m (≤ 9 s walking at 1.8 m/s, estimated along
  doorway waypoints), plus getting up and ~10 s to correct the channels.
- **Recovery:** reduce the channel; if it tripped, balance then reset
  B-03.

## E. Countdown and warning feedback (Priorities 5–6)

- **One model** (`station_status.gd`): room severities, duties and the
  active emergency, all derived; nothing saved.
- **Countdown:** the equipment's own timer (`_overload_s`, saved). It
  pauses with the tree, never restarts on reopening or loading, and
  vanishes when cleared or once the trip happens.
- **Surfaces:**
  - a compact top banner, "POWER OVERLOAD · ENGINEERING · 01:24 Reduce
    COMMS output" (hidden while seated: the workstation shows its own
    strip);
  - the raised watch: "! PWR OVERLOAD / ENGINEER 01:24".
- **Lights:**
  - red wall beacons in Engineering plus the corridor at its doorway
    (others exist for Life Support / Airlock and only light for their own
    emergencies);
  - slow 0.5 Hz pulse, no strobe;
  - a **Steady warning lights** setting gives constant light;
  - distinct from breaker-outage emergency lighting and the panel
    locator.
- **Alert tone:** a two-tone alert on the room speaker at onset and once
  at 30 s.
- **Assistant lines:** "Warning. Engineering power overload. Breaker trip
  imminent." / "Thirty seconds to breaker trip." / "Breaker B-03 tripped.
  Emergency lighting active…" / "Overload cleared."
  - safety priority and cooldowns;
  - the voice waits for the alert tone (no clash).

## F. Map-first workstation (Priorities 7–9)

- **Shell:** `workstation_shell.gd` is the visible interface: three
  sections, every control clickable.
- **OPERATIONS (default):**
  - **Map:** the real topology (copied from the existing map layout). Each
    room shows its highest severity:
    - neutral = normal;
    - orange outline + circle = routine (gentle pulse);
    - amber fill + diamond = warning;
    - red pulsing fill + "!" triangle = emergency (steady when requested).
  - **Room panel:** clicking a room lists its duties, one line each;
    clicking a duty shows a few details.
  - **Actions:** CHECK IN, VERIFY REPAIR, DIAGNOSTIC (overlay), CAMERA (+
    NEXT CAM); the footer gives the most urgent duty; a red strip shows an
    emergency.
- **RECORDS:** today's log, shift reports, service history.
- **SYSTEM:**
  - every setting as a clickable row (and `<`);
  - SAVE GAME / LOAD GAME / NEW GAME, using the established safe deferred
    load;
  - saved / autosave status (disk is read only when the page opens or
    after an action).
- **Mouse:** seated, the cursor is visible; each mouse event is projected
  onto the monitor face (camera ray → `screen_uv_on_ray`) and pushed into
  the screen SubViewport; nothing reaches the world.
  - **Verified:** a rendered marker at the mapped RECORDS tab lands on it;
    a test click presses the right tab.
- **Keys kept:** 0/1 Operations, 2 tasks, 3 Diagnostic, 4 Camera, 5 Save/
  Load and 6 Settings (System), **7 Records** (new), arrows, R, Esc.
- **The old seven sections** remain as the hidden keyboard/text model
  (existing tests read them).
- **Glyphs:** all 17 non-ASCII UI symbols (arrows, triangles, °, …) are
  present in the font chain now that the CJK fallback really loads
  (`tools/audit_glyphs.gd`).

## G. Personal laptop (Priority 11)

- **Messages:** eight short, ordinary fictional messages arriving by day
  (sister, a friend, payroll, a dental reminder, mum); an unread count;
  read state saved; checked for horror vocabulary.
- **Schedule:** DayPlan's real day, shift clock, open duties, next cargo,
  plus a few personal notes.
- **Photos:** an honest empty album — "No photos have been synced to this
  device yet". No imagery was invented or borrowed; content pending.

## H. Save/load

- **New saved state:**
  - the emergency plan;
  - the overload timer (already in the power state);
  - the six-chamber calibration state;
  - read messages;
  - settings `ui_scale` and `steady_warnings` (settings file).
- **Not saved:** map / banner / beacons are derived. Loading during an
  emergency keeps the remaining time (tested).

## I. Tests

- **New (6):**
  - `test_r37_ui_scale`
  - `test_r37_calibration_gauges`
  - `test_r37_emergency`
  - `test_r37_workstation`
  - `test_r37_speakers` (renders real speech with `SMH_SPATIAL_SPEECH=1`)
  - `test_r37_laptop_personal`
- **Real-display tools:**
  - `tools/verify_spatial_voice.gd`
  - `tools/verify_station_ai_speech.gd` (now the OS-TTS fallback)
  - `tools/audit_glyphs.gd`

- **Found by the full suite (fixed):**
  - `test_laptop_clicks` failed after the stretch change. The test
    projected a point with `unproject_position()` (VIEWPORT coordinates)
    and pushed it as a WINDOW event; with canvas_items stretch (headless
    window 64×64) those differ. The game itself is consistent: handlers
    use `event.position` in viewport space.
  - The test now maps through the root's final transform.
  - Also hardened: every caption / emergency-banner Control now ignores
    the mouse (display-only overlays never swallow clicks).
- **Found in renders (fixed):**
  - the HUD emergency banner sat on the seated workstation's tab bar
    (now hidden while seated; the monitor has its own strip);
  - the Operations footer said "All assignments complete." on day 1 (it
    now shows the most urgent duty from the status model).

## J. Known limitations

- Spatial speech uses macOS `say`. On other platforms speech falls back
  to non-positional OS TTS (reported as such).
- Voice quality depends on installed voices; no recorded voice acting.
- No acoustic occlusion: a unit's voice is heard through walls with
  distance attenuation only (units are chosen by the player's room).
- Only one timed emergency type (Bus A overload). Life Support and seal
  problems are warnings (their modelled consequences are slow and
  non-fatal).
- Photos has no content yet.
- The old seven workstation sections still exist (hidden) as the
  keyboard/test model.
- Tests write the voice cache to `user://voice_cache/` (a cache, not
  saves or settings).

# Round 38 — Cameras, exterior & EVA, observation discrepancy foundation, interior upgrade, laptop desktop, portable tools

## A. Camera network (`scripts/surveillance/camera_network.gd`, node `CameraNetwork`)

Twelve live cameras. Each is a SubViewport camera (384×288) that renders
ONLY while its feed is on screen (`UPDATE_ALWAYS` while displayed,
otherwise `UPDATE_DISABLED`). The console's own feed is gated off while
the player stands in the Control Room. Camera housings are on visual
layer 16, which every camera excludes.

| ID | Label | Mount → target | Blind spot |
|---|---|---|---|
| INT-01 | CONTROL ROOM | existing `CameraControlRoom` | under the camera, the console's west side |
| INT-02 | MAIN CORRIDOR | existing `CameraCorridor` | the Control Room doorway behind the camera |
| INT-03 | JUNCTION | existing `CameraCorridorEnd` | the Comms tunnel mouth |
| INT-04 | ENGINEERING | (-2.78,2.95,6.72) → (-4.6,0.9,3.7) | the breaker-panel alcove right below the camera |
| INT-05 | LIFE SUPPORT | (-1.48,2.95,11.82) → (-4.1,0.9,10.0) | the doorway behind the camera |
| INT-06 | STORAGE | (-5.55,2.95,7.05) → (-7.2,0.7,8.9) | the near cabinet face |
| INT-07 | AIRLOCK | (-4.8,2.22,2.85) → (-4.8,1.0,-2.2) | the tunnel corner by Engineering |
| INT-08 | COMMS | (3.22,2.95,8.12) → (1.4,1.0,6.3) | the alcove behind the camera |
| EXT-01 | HULL OVERVIEW | (7.5,6.5,-9.5) → (-1.5,0.8,3.5) | the north face of every module |
| EXT-02 | AIRLOCK HATCH | (-3.45,3.05,-3.75) → (-4.8,0.9,-2.75) | directly beneath the camera mount |
| EXT-03 | OBSERVATION | (-1.62,3.25,2.92) → (-3.6,1.0,0.2) | the walkway behind the antenna mast |
| EXT-04 | ANTENNA A1 | (-4.12,2.55,2.45) → (-2.85,0.75,0.75) | the far side of the feed box |

API: `ids()`, `feed(id)`, `info(id)`, `camera(id)`, `request(requester, id)`,
`is_rendering(id)`, `sees(id, point, tolerance)`. `sees()` uses frustum plus
line of sight; sight rays ignore the EVA tether walls (collision layer value 4).

**Workstation.** There are four tabs: OPERATIONS / CAMERAS / RECORDS /
SYSTEM. CAMERAS lists the interior and exterior cameras and shows the
selected live feed with `LIVE mm:ss`, the blind-spot note and a mini plan
marking the camera. `< MAP` returns to Operations. The OPS "CAMERAS"
button and the old `[Surveillance]` section key both open the tab. The
network renders a feed only while the Cameras tab is shown and the
player is seated.

## B. Exterior spacecraft (`scripts/exterior/exterior_builder.gd`, node `Exterior`)

- **Space:** a star sphere and a planet with an atmosphere rim, both
  procedural. A Sun `DirectionalLight3D` lights only the EXTERIOR visual
  layer (1<<11), so it never leaks into the rooms.
- **Hull:** plating is generated on every outward wall face. A face counts
  as outward when a probe 0.3 m outside it is not inside any floor
  footprint. Roofs and undersides are plated too.
- **Equipment:** radiators, a solar wing truss, a comms dish, a cable
  tray and nav lights.
- **External airlock hatch:** frame, red door, wheel handle, hazard marks
  and a label.
- **EVA courtyard:** the deck floor, handrails and floodlights, plus
  tether walls on collision layer value 4. The player capsule collides
  with them; sight and interaction rays do not.

## C. EVA (`scripts/exterior/eva_system.gd`, node `EvaSystem`)

- **Sequence:** suit locker (Airlock, recessed) → inner panel "CYCLE OUT"
  (3.5 s depressurise, pressure readout) → outside at the hatch → walk the
  courtyard (mag-boots) → outer panel "CYCLE IN" → repressurise.
- **Cycle-out blockers** (`cycle_out_blocker()`): no suit; the cargo port
  is not SECURED; a hatch-seal inspection or test is in progress.
- **While outside:**
  - presentation: visor overlay, Ambient bus low-pass, Station AI on a
    non-positional `suit_radio` unit;
  - refused: saving ("Return inside through the airlock first."), the
    cargo port, and seal inspection;
  - failsafe: the tether returns you to the hatch if you ever leave the
    deck.
- **Saved:** only `suited`. A save is impossible outside, so a load
  always starts inside.

## D. Exterior maintenance with a consequence: antenna feed A1 (`antenna_mast.gd`, order type `antenna`)

- **Fault model:** feed A1 can be `ok`, `loose` or `corroded` (seeded).
  `link_quality()` = feed factor (1.0 / 0.35 / 0.55) × comms power
  (breaker B-04).
- **Effects of the link quality:**
  - shown on the Comms **LINK panel** (TEST);
  - degrades the Comms room's state;
  - surfaces as the work order ANTENNA, category D, from day 8.
- **Chain:** TEST LINK (Comms) → SUIT UP → CYCLE OUT → FIX FEED A1 (open
  the cover, reseat or clean the connector, close) → CYCLE IN → VERIFY
  LINK (Comms). The order closes only on a verified good link.
- **Multi-room chain:** Comms → Airlock → exterior → Airlock → Comms.

## E. Window / camera discrepancy foundation (`observation_discrepancy.gd`)

**Shared observation region:** the EVA courtyard around mast A1 and the
outer-hatch walkway. Three views cover it:

- the Control Room **observation port**, a DIRECT view;
- **EXT-03** and **EXT-04**, camera views;
- partly **EXT-02**, a camera view.

**Mechanism:**

- `camera_network` removes layer 19 (CAMERA_ONLY) from every direct view:
  the player, the observation port and the mirror.
- It removes layer 20 (DIRECT_ONLY) from every surveillance camera.

**Modes:**

| Mode | Effect |
|---|---|
| `camera_figure` | a suited figure by the hatch, visible on camera only |
| `window_object` | a tethered bag by the mast, visible through the port only |
| `displaced` | the same bag by the mast for the eyes and by the hatch on camera |

**Control:** `trigger(mode, seconds, source)` / `clear()`.

- `source` must be `"event"` (the future narrative system) or `"debug"`.
- `"debug"` is refused outside debug builds.
- It is never random and never saved; a load starts clean.
- `history` records every trigger.

## F. Observation port (`wall_watch_window.gd`, rewritten to the locked design)

- **Physical form:** a round port with a thick bolted rim standing proud
  of the wall and the glass recessed behind the bezel. It has no
  `interact()`.
- **The glass:** shows a portal render from the player's actual eye: an
  off-axis frustum through the glass with the near plane past the wall
  and hull. Parallax is therefore correct as you move.
- **Rendering cost:** the portal renders only while the player is in the
  Control Room.
- **Kept from the old design:** `set_feed_override()` and `camera_path`
  remain as seams.

## G. Interior aesthetic (`scripts/station/station_decor.gd`, node `StationDecor`)

Industrial spacecraft with restrained cyberpunk accents. Nothing has
collision, so navigation is unchanged (verified by the capsule sweep).

- **Rooms:**
  - chamfered ceiling cladding;
  - perimeter light strips in the zone colour;
  - kick plates and module signage (e.g. "COMMS · M-5");
  - one identity per room: Engineering pipe runs and a cable tray,
    Life Support duct and pipes, the Control status strip, the Quarters
    warm cove light, Storage hazard posts, and the Comms transceiver rack
    with status LEDs plus a ceiling cable bundle.
- **Corridors:** ribs every 0.75 m (skipped near mounted equipment), a
  centre light strip and handrails.
- **Lighting obeys power:** each strip belongs to a breaker zone and goes
  dark while that zone is off (polled every 0.5 s; `strip_lit(zone)`).

## H. Atmosphere / sound (`station_ambience.gd`)

Three new quiet room beds were added to the existing ventilation,
engineering and life-support beds:

- a Comms electronic whine, silent while B-04 (communications) is off;
- an Airlock coolant-pump throb;
- a faint Storage hum.

While outside, the Ambient bus is low-passed (EVA).

## I. Laptop

- **Zoom bug root cause:** the laptop's EDITING (zoomed) state was
  hard-wired to the personal-log editor. Zooming therefore always opened
  the log, and any other app could not be used zoomed.
- **Fix:** zoom (focused use) is now separate from the log app.
  - Clicking an icon while unzoomed requests focus (`app_requested(&"focus")`)
    and opens that app after the zoom.
  - Zooming out returns to the desktop.
  - The text entry is editable only while zoomed and in the log.
- **Desktop:** taskbar (Desktop / Save / Save & Back / Close) and app icons:
  Personal Log, Messages, Schedule, Photos, Files, Shift Report, Cargo Drop.
- **Files** (`laptop_files.gd`): folders Personal, Photos, Messages,
  Journal, Documents and Entertainment, holding text, image, message, log
  and app entries. Photos are original procedural pictures (dinner, house,
  the dog Pip, the coast, a watch).
- **Cargo Drop** (`cargo_drop_game.gd`): an original falling-crate game
  on an 8×12 grid. Pieces are 1–3 crates; a full row ships for
  100 × rows² points. The best score is saved.

## J. Portable tools (`portable_meter.gd`, `tool_rack.gd`)

- **Tool rack:** in Engineering, with two docked slots.
- **AFM-2 airflow meter:**
  - measure ports at the LS air vent and the air-filter housing;
  - readings come from the real vent, fan and filter state;
  - measuring the vent sets `vent.airflow_checked`.
- **LD-5 leak detector:**
  - signal = clamp(leak / 1.2, 0.5, 1) / (1 + (d / 0.3)²) near the hatch
    seal;
  - a signal above 0.6 marks that seal segment inspected.
- **Carrying and saving:** both tools follow the one-item carry rule; the
  rack and the tools' payloads are saved.

## K. Dynamic failures, variety, proficiency, AI

- **Dynamic failures:** the antenna feed degrades (seeded); comms power
  depends on B-04; the existing overload emergency remains.
- **Proficiency:**
  - families: electrical, life_support, mechanical, communications, eva;
  - each completed work order, and each day's main workday, credits its
    families exactly once (keyed by order ID or day/workday);
  - ranks: Trainee (0), Technician (1–2), Qualified (3–5), Senior (6+);
  - shown on RECORDS.
- **Proficiency-gated variety:**
  - harder filter variants (SEIZED / COCKED) need life_support ≥ 1;
  - two-fault seals need mechanical ≥ 2;
  - the timed overload emergency needs electrical ≥ 1.
- **Quarters life** (`quarters_life.gd`): galley tea (3 s brew → mug)
  and a meal once per day, plus a photo frame.
- **AI tuning:**
  - new lines for the suit, being outside, the interlock, the antenna,
    the comms link, the tools and the measure ports;
  - step narration is skipped once the family is Qualified (≥ 3).

## L. Save / load

Saved:

- EVA `suited`;
- the antenna (feed, cover, request day, link checked, verified day);
- the tool rack and tool payloads;
- quarters (tea, drank and meal days);
- proficiency and `_credited`;
- the laptop `game_best`.

Not saved:

- the discrepancy (always starts clean);
- camera selection.

Saving is refused during EVA.

## M. Tests

New tests:

- `test_r38_cameras_exterior`: network, gating, sight, the discrepancy
  layers and trigger rules, hull, port portal.
- `test_r38_eva`: real W-key walking outside, interlocks, tether
  failsafe, save refusal, the antenna chain.
- `test_r38_tools`: the rack, both tools, measurements, the return.
- `test_r38_laptop_station`: the zoom fix, desktop apps, files, photos,
  the game, quarters, decor and lighting.

`test_station_ambience` gained the Comms B-04 checks. Updated tests:
`test_laptop_clicks`, `test_r37_laptop_personal`, `test_r37_workstation`
(four tabs), `test_r37_speakers`, `test_r37_emergency` and
`test_filter_variants` (proficiency gates).

The navigation sweep (`test_station_capsule_sweep`) still shows only the
5 known pre-existing failures.

## N. Known limitations

- The observation port is a camera-backed portal with correct parallax,
  not a real opening in the wall.
- EVA is mag-boot walking on a deck, not 6-DOF free flight.
- Photos are stylised procedural images.
- Spatial speech remains macOS-only, and there is no acoustic occlusion.
- The old seven workstation sections still exist (hidden) as the
  keyboard/test model.
- **Pre-existing geometry quirk:** `JunctionEastWallNorth` (x≈1.4)
  stands inside the Comms footprint, so the usable Comms room is about
  x 1.5–3.3. It is unchanged from HEAD and was left alone.

# Round 39 — Real airlock & tethered EVA, sealed hull, daily routine, work-based shift, laptop desktop

## A. Personal laptop: a proper close-up of the desktop (Priority 1)

- **Root cause.** Round 38 tied "zoomed in" to opening an app: clicking the laptop only opened it unzoomed, and the desktop itself had no close-up state.
- **Fix.**
  - A click on the laptop from the bunk now opens it AND zooms in on the desktop (`sleep_state.open_laptop(zoom_in=true)`).
  - A click on the open, unzoomed screen that presses nothing also zooms in.
  - Zooming in keeps the current view; T still asks for the Personal Log (`set_pending_app`).
  - `< Save & Back` / Esc zoom out; Close shuts the laptop.
- **Zoom framing.** The zoom distance is now computed (`_editor_distance()`) from the real camera FOV, keep-aspect mode and viewport aspect, so the 0.24 × 0.14 m screen fills ~88 % of the view on any window shape. The old fixed 0.2 m distance under- or over-filled non-16:9 windows.
- **Desktop ("driftwood").**
  - Wallpaper (the technician's own coast photo) and a top menu bar showing brand, current app, controls and a day/shift clock.
  - Pictogram desktop icons and a sticky "today" note (day, today's work, eat + drink, new messages, the basil).
  - Apps open in an opaque window; Files entries have type icons.
- **Foundation for future content.** `laptop_files.register(folder, rec)` / `folders()` add folders and files at runtime, without editing the constant table.

## B. Stray corridor bars / unpainted bars (Priority 2)

Root causes:
- **Bars in the corridor.** Round 38's `StationDecor` took a corridor's run direction from its floor proportions. The 1.6 × 1.4 m main corridor was therefore dressed *across* its width: a rib post stood in the walkway and a handrail spanned it. Both were walk-through.
- **Trip bars at doorways.** Room kick plates ran along the full floor edge, across doorways.
- **"Unpainted" bars.** Five blockout wall fragments (`CommsWestWall*`, `CommsSouthWallWest`) floated inside the north Junction: 1 m tall pieces at y 1.1–2.1, with brightly lit hull plating visible behind them.

Fixes:
- Decor now follows the REAL walls (`_collect_walls` / `_side_walls` / `_side_face`):
  - a corridor's axis and interior width come from its side walls;
  - trim sits on the walls' inner faces;
  - kick plates are placed per wall segment, never across an opening;
  - sides without walls get no trim.
- The five fragments were removed from `main.tscn`. The Comms strip got a proper west wall, plus raises up to the 3.2 m ceiling (see C).

## C. Sealed hull (Priority 3)

- **Leak sweep.** `tests/test_r39_hull_seal.gd` casts rays in 26 directions from ~1,460 sample points (three heights over every interior floor, each visible from a walkable navigation node) against solid geometry. A ray that escapes, or first hits exterior geometry, is a leak.
- **Before.** About 340 leaking rays at ~100 gap locations.
- **After.** 0.
- **`StationSeal`** (`scripts/station/station_seal.gd`) adds 25 collidable panels in the neighbouring wall/floor material:
  - **Control ↔ Quarters doorway.** The 0.2 m slot between the two walls is filled; the doorway gets a floor threshold and a header. A separate jamb narrowing the Control-side door was tried and dropped: it pinched the navigation path.
  - **Corridor → Junction.** Shoulder walls (the junction is wider than the corridor).
  - **Junction → Life Support.** A corner block closing the tunnel/bend corner (no floor, walls or ceiling existed there), plus a small slit filler.
  - **Life Support ↔ Storage connectors.** C/D west closure, D floor and ceiling strips, the pocket floor and ceiling, and lintels.
  - **Lintels** wherever a 2.8 m connector meets a 3.2 m room: Engineering (south, west, east), Storage (south, north), Life Support (south, west) and the Comms door.
  - **Comms.** West closure, plus raises above the Junction walls.

## D. Living Quarters layout (Priority 4)

- The Round 38 galley stood in front of the closet's doors. It is now on the south wall, between the doorway and the bunk (`GALLEY = (3.1, 0, -1.18)`, facing into the room).
- The closet access zone is clear (tested).
- Lived-in touches: a basil plant on the desk, a wall calendar with crossed-off days, and a rug by the bunk.

## E. Eating and drinking are part of the day (Priority 5)

- **Galley.**
  - WATER dispenser (a drink).
  - HOT WATER → tea mug (a drink).
  - MEAL PACKS (food).
- **Gesture.** Each plays a visible hand-to-mouth gesture (`player_body.begin_consume`): the right arm brings the actual pouch or mug to the mouth (two bites / a sip with a tilt). The target follows the head bone, so it works whatever the head pitch. The effect lands when the gesture ends; hands must be free.
- **DayPlan.**
  - A MEAL routine row ("Eat and drink at the galley", Quarters, progress n/2) is required work. It shows on the map, the watch and the laptop note.
  - A day ending without both leaves the technician UNDERFED the next day: movement × 0.85, a faint vignette and an AI reminder, until they eat.
  - The shift report lists meals.

## F. Airlock, EVA, cameras, exterior (Priority 6)

- **Real two-hatch airlock** (`scripts/exterior/airlock_chamber.gd`, node `AirlockChamber`).
  - **Chamber.** The tunnel's south end (z −0.5 … −2.5).
  - **Hatches.** A hinged INNER hatch with a porthole (z −0.4, swings into the chamber) and a hinged OUTER hatch (z −2.6, red, swings out onto the hull). Both are framed bulkheads with hazard-striped jambs and flush sills.
  - **EXIT** (chamber panel): close inner → depressurize 14.7 → 0 psi → open outer.
  - **ENTER:** close outer → repressurize → open inner.
  - **Outside panel:** opens the outer hatch, cycling down first if needed, so the technician is never locked out.
  - **Station-side panel:** brings the chamber to station pressure and opens the inner hatch.
  - **Feedback.** A chamber light (green / amber / red), a large psi readout, and panel screens showing state, pressure and both hatches.
  - **Interlocks, re-checked at each step:**
    - never both hatches open;
    - the inner hatch opens only at ≥ 14.5 psi, the outer only at ≤ 0.2 psi;
    - no venting with an unsuited person in the chamber (the sequence aborts);
    - a hatch never closes on someone in its doorway (the sequence waits: "Clear the hatch");
    - the cargo port must be secured and seal inspection/testing idle.
  - **Not saved.** A load always restores the default; saving is refused while not default.
  - The old solid bulkhead and the decorative hatch props were removed.
- **Suit.** `player_body.set_eva_suit` → `technician_rig.set_eva_suit`: white garment, light gloves and boots, orange accents, a life-support pack, a chest unit, and a bubble helmet with a gold visor. The helmet is mirror/camera-only, like the head.
  - In view: the visor frame and "SUIT 4.3 psi O2 · O2 % · TETHER · AMB".
  - The suit state is saved.
- **Tethered zero-g EVA.**
  - **Outside** = beyond the outer hatch plane or off the hull footprint.
  - **Movement** (`free_move_controller.zero_g`): no gravity; W/S push along the look direction, A/D strafe, Space/C rise/sink, gentle thrust and slow stabilising drag. No footsteps; the body floats with relaxed legs.
  - **Tether.** Auto-clipped to ring A1 at the hatch. Clicking ring A2 (walkway) or A3 (mast) within reach re-clips it.
  - **Cable.** A visible sagging cable to the suit; an inelastic 5.5 m limit plus a failsafe.
  - Round 38's invisible tether walls were removed; the handrails remain as translation aids.
- **Cameras curated to six:** INT-02 corridor, INT-04 Engineering, INT-05 Life Support, INT-07 AIRLOCK CHAMBER (now inside it, looking at the outer hatch), EXT-02 airlock hatch, EXT-03 observation. The other table entries are documented but not built.
- **Observation port from outside.** A real exterior port at the window's position (rim, sun hood, dark glass with a faint cabin glow, label "OBS PORT C-1"). It sits behind the inside portal camera's near plane. The discrepancy foundation is unchanged (EXT-02 / EXT-03 still cover the shared region).
- **Hull finish** (`exterior_builder._dress_hull`):
  - painted module bands and large module IDs on every roof;
  - panel seams, roof vents and junction boxes;
  - gold insulation blankets on exterior walls;
  - hazard chevrons over the outer hatch;
  - the registry marking "KESTREL-7 · RELAY & SURVEY STATION".
- **EVA tasks.** The antenna A1 chain now reads AIRLOCK EXIT / FIX FEED / AIRLOCK ENTER. NEW work order `lens` (day 9, EVA family; `camera_lens_task.gd`):
  - the EXT-02 lens gets a real grime film just inside the camera's near plane, so the feed is visibly smeared;
  - chain: CHECK FEED (Cameras tab) → SUIT UP → AIRLOCK EXIT → WIPE LENS (float up to the camera; two wipes) → AIRLOCK ENTER → VERIFY FEED.

## G. Shift by work, end of day (Priority 7)

- **Progress.** `shift_progress()` is the done share of today's required work: check-in, main workday steps (partial), open orders, cargo duty and the meal routine. It is shown as "DAY n · 45 %" (laptop clock, workstation header, watch), not as a countdown.
- **End of shift.** When the work is complete, a 45 s WRAP UP follows ("Work complete. Wrap up, then rest."). Then the shift ends: "Shift over. Return to your bunk", and the watch shows SHIFT OVER / BUNK · REST.
- **Staying up.** After a 60 s grace, `tiredness()` ramps over 90 s: walking slows to 0.7 ×, a dark vignette closes in (`fatigue_vignette.gd`), and the AI reminds the player every 90 s.
- **Hard limit.** The old 10-minute clock remains the end of the working day. Unfinished work carries over as before.
- **Days start in bed.** New games, new days and autosave loads start in the bunk (verified).

## H. Station AI onboarding (Priority 8)

- **Rewritten lines** for the new flow: `eva_suit` (4.3 psi, chamber, EXIT), `eva_outside` (tether, drift) and `eva_interlock`.
- **New first-time lines:**
  - `airlock_intro` (proximity topic at the chamber panel), `airlock_cycle_out` and `airlock_cycle_in`;
  - `lens_intro`;
  - `meal_intro` (proximity topic at the galley while the meal routine is open).
- **New reminders:** `underfed` (morning), `work_complete` and `bed_reminder`.
- **Existing first-time lines** (breaker, vent, power, seal, data module, thermal, filter and others) are unchanged.
- **Proficiency.** The lens task counts toward the EVA family.

## I. Save / load additions

- **DayPlan:** `underfed`, `work_done_at_s`, `awake_after_shift_s`.
- **Quarters:** tea, drank and meal days, plus the mug.
- **Lens task:** dirt, request day, checked, verified day.
- **EVA:** suited (the visuals follow on load).
- **Airlock:** deliberately not saved.

## J. Tests

- **New:**
  - `test_r39_hull_seal` (leak sweep);
  - `test_r39_airlock_eva` (real W-key walk through both hatches, zero-g, tether limit and re-clip, the antenna repair, interlocks, a per-frame safety invariant, save/load);
  - `test_r39_routine_layout` (closet clear, decor clear of walkways and doorways, seal panels, meal routine and gesture, work-based shift, tiredness, underfed, save/load, day starts in bed, file registry).
- **Updated:**
  - `test_laptop_clicks` (zoom on open; blank-click zoom);
  - `test_shift_day_system` (progress text);
  - `test_r38_laptop_station` (gesture timing; 6 cameras);
  - `test_r38_cameras_exterior` (curated set; INT-07 in the chamber).
- **Replaced:** `test_r38_eva` (the old teleport flow no longer exists), by `test_r39_airlock_eva`.

## K. Known limitations / trade-offs

- **EVA movement.** Gentle thrusters with auto-drag, not full 6-DOF momentum. There is no roll axis and no handrail-grab traversal yet (the rails are visual aids).
- **Hatch animation.** Hatches swing on a simple eased hinge, with no dogging-wheel animation.
- **Pressure** is a single chamber value; there is no gas model.
- **Helmet lighting.** The helmet is mirror/camera-only, so it is not lit by the exterior-only floodlights on cameras.
- **Seal panels** are plain wall-material boxes. They close the seams but do not add new architecture.
- **Meal model.** One meal + one drink per day; no hunger meter by design (low friction).
- **Hard limit.** The shift's hard limit is still the old clock (the 10-minute balance setting).
- **Pre-existing:** the Junction wall at x ≈ 1.4 inside the Comms footprint (Round 38 note) and the 5 known navigation-sweep edges.

# Round 40 — EVA clarity, unified airlock module, walkway audit, spacecraft polish

## A. EVA (Priority 1)

- **Interior-to-exterior snap bug (root cause).**
  - Round 39 derived "outside" from interior floor footprints *every frame*. A suited technician standing on a spot not covered by a floor slab counted as outside:
    - the Control ↔ Quarters doorway gap;
    - the outer-hatch sill with the hatch SHUT.
  - Once "outside", the tether saw a huge distance, and the failsafe teleported the technician to the hatch exterior. The rendered probe reproduced it (LivingDoor, JunctionNode2: moved 10.5 m; chamber sill).
  - **Fix** (`eva_system.gd`): an explicit ZONE state.
    - station → chamber: walking in.
    - chamber → outside: ONLY through the OPEN outer hatch, suited.
    - outside → chamber: floating back in.
    - chamber → station: through the inner hatch.
  - Zero-g, the tether limit and the failsafe act only in `outside`.
  - Regression test: `test_r40_eva_clarity` checks 38 spots (every navigation node plus chamber and doorway spots) and the logged zone sequence.
- **Visible tether.** Round 39's cable was a ribbon turned toward the *player* camera: edge-on (invisible) to the exterior cameras and below the first-person view. It is now a solid tube (18 segments) from a harness D-ring on the suit's hip (rig bone) to the ring, with a carabiner at each end. It sags with slack and sways slightly. It sits on the normal and exterior layers, so the first-person view, EXT-02 (tested) and the mirror all see it. The cable visibly runs out to ring A1 as you leave the hatch.
- **Staged re-clip** (click a ring within 1.8 m):
  1. a second cable reaches out to the new ring (0.5 s);
  2. it clicks on and the ring turns green; both tethers hold for a moment (the two-tether rule, 0.35 s; both constrain movement);
  3. the old cable unclips and reels in (0.5 s).

  The visor shows "A1>A2" during the switch.
- **Controls** (`free_move_controller.zero_g`): one clear idea instead of "WASD + Space/C".
  - **Space (or W):** suit jets push toward the crosshair.
  - **Release:** coast, with a slow drag.
  - **S:** brake.
  - **A/D:** gentle sideways drift.
  - **C** no longer sinks you (it was also the wristwatch key).
  - **Space no longer picks up / drops items during EVA** (the carry system yields).
- **Visor HUD:**
  - a zone chip: STATION / CHAMBER (· VAC) / OUTSIDE / RETURN near the hatch;
  - the tether ring plus a range bar (green → red);
  - an O₂ bar and suit pressure (4.3 psi);
  - a first-EVA key-cap hint (SPACE push, S brake, A/D drift, CLICK RING re-clip) for 9 s; H shows it again.

## B. One airlock module (Priority 2)

- **Console.** The chamber panel and the HATCH SEAL panel are mounted together on one "AIRLOCK A-1" console on the chamber wall. The seal panel moved up to the chamber panel's height; the chamber panel moved next to it.
- **Status strip** of four lamps:
  - INNER: green when open;
  - CHAMBER: green pressurized / amber cycling / red vacuum;
  - OUTER: red when open to space;
  - SEAL: the last hold test — green pass, red fail, amber inspecting or testing, grey untested.
- **Wording.** The buttons are now "OUT >>" / "<< IN" (was EXIT/ENTER). The screens show short step text ("1/3 SEAL INNER", "2/3 VENT 9.2 psi", "3/3 OPEN OUTER"; "SEAL OUTER / PRESSURIZE / OPEN INNER" on the way in).
- **Labels everywhere** follow suit: work orders (AIRLOCK OUT / AIRLOCK IN), the AI lines and the laptop EVA handbook.
- **Assistant** (short, first time or context-triggered):
  - `airlock_intro` (OUT seals, vents, opens; IN reverses);
  - `eva_outside` (push toward the crosshair; S brakes);
  - `tether_intro` (near ring A2 while outside);
  - `tether_switch`;
  - `eva_repair` (at the worksite: stop first, then work).

## C. Walkway audit (Priority 3)

- **Root causes.** Corridor decor placed rib posts, handrails and ceiling cladding along each side's full length, so at side openings they crossed the doorway. The Junction → Comms opening had a post in it, a handrail across it and cladding over it.
- **Now.** Posts, rails, cladding and the new details exist only along real WALL segments (`_wall_segments`); a cross-beam needs walls on both sides.
- **New test** `test_r40_walkway_clear`: sweeps a person-sized volume along every navigation edge against ~900 visual-only pieces (decor, seals, airlock, exterior, scene trim without collision). Only overlaps visible from the walkway count.
- **Hull plating found by the audit:**
  - **Wrong footprint lookup.** The hull generator found interior footprints by names ending in "Floor". `JunctionFloorNorth` was missed, so the north Junction counted as outside and got hull plating on its INNER walls.
  - **Overhang.** Plates overhung wall ends by 0.12 m (into doorways), and plate ends sat flush with neighbouring walls (z-fighting stripes in the Engineering tunnel).
  - **Fixes:** floor-slab detection by geometry; plates are the wall's length minus 2 cm at each end.
- **Comms rack** moved clear of the alcove doorway.
- **Excluded from the audit** (named in the test): the operator stool, which is deliberate furniture.

## D. Spacecraft feel (Priority 4)

- **Corridors** (visual only, along walls):
  - lower 45° chamfer panels, giving an octagonal tunnel section with the ceiling chamfers;
  - twin cable conduits;
  - vertical panel seams every ~0.75 m and floor plate seams;
  - cyan floor guide lights;
  - labelled ACCESS panels on long wall runs.
- **Exterior:**
  - the observation port has a yellow painted surround and a warmer cabin glow, so it reads from outside;
  - EVA WORKSITE A1 at the antenna: foot restraints, a worklight on a post aimed at the feed box, a tool caddy and a site plate.

## E. Routine (Priority 5)

When the shift ends, a warm glow comes on over the bunk: a wordless "go to bed" (`quarters_life.bunk_glow_energy()`, tested).

## F. Tests

- **New:**
  - `test_r40_eva_clarity` (zones and the regression, sequence, tether visibility, staged re-clip, controls, HUD, console);
  - `test_r40_walkway_clear`.
- **Updated, with reasons:**
  - `test_r39_airlock_eva`: the re-clip is staged now (it waits ≈1.6 s); the cable is a tube (`_cables`); step labels are AIRLOCK OUT / IN; it gained the B-04 coverage check.
  - `test_r39_routine_layout`: adds the bunk glow check.
- **Rib count** (`test_r38_laptop_station`): the metric now counts rib stations with at least one wall post. Posts no longer stand in openings; the threshold is unchanged.

## G. Limitations

- **Re-clip animation.** The cables animate; the suit's arm does not reach for the ring.
- **Hint keys.** The hint uses plain text key caps (no icon art).
- **Tether physics.** The tether is a kinematic curve, not rope physics.
- **Walkway audit.** It checks volumes along navigation edges, not every possible player path.
- **Existing items.** The operator stool remains walk-through furniture, and the 5 known navigation-sweep edges remain.

---

# Round 41 — Dual-tether EVA, solar arrays and power, solar maintenance, suit, surveillance horror, Cargo Drop

## A. EVA movement (Priority 1) — `free_move_controller.gd`
- Playtest: "too complicated". Zero-g controls are now AIM AND PUSH:
  **W** thrusts along the camera's aim (pitch included), release = coast,
  **S** brakes smoothly to zero. **A / D / Space / C do nothing** in
  zero-g (Space stays the carry key and is ignored outside).
- Feel knobs are exported (one place): `zg_accel` 0.9 m/s², `zg_max`
  1.1 m/s, `zg_drag` 0.12 m/s² (gentle suit stabilisation while coasting),
  `zg_brake` 1.4 m/s², `zg_turn_rate` 2.2/s (thrusting along a new aim
  bleeds off the old sideways drift over ~1 s — no abrupt reversal).
- No thrust while stabilised at a worksite (`work_locked`), while a
  focused equipment panel has control (`thrust_blocked`), or while paused
  (physics does not run). Interior WASD walking is untouched.
- Visor strip (compact): zone chip · tether A chip · tether B chip ·
  range bar (tightest tether) · jet chip (▲ JET / ■ BRAKE / ● HOLD) ·
  speed bar · a motion-direction dot relative to the view · O2 · psi.
  First-EVA key-cap hint (H re-shows): W thrust, S brake, CLICK RING clip
  the free tether, R release the older tether. AI: "W thrusts toward your
  aim. S brakes." then (first thrust) "Aim at your destination. Your
  tethers limit how far you travel."

## B. Dual tethers (Priority 2) — `eva_system.gd`
- Two independent tethers, A (left hip D-ring) and B (right hip D-ring),
  each `{ring, state, t, seq}` with its own tube cable, swivel and
  carabiner (D body + spring gate that visibly opens / snaps).
- Per-tether states `stowed → connecting → secured → releasing → stowed`;
  pair state names `SECURED_A / SECURED_B / SECURED_BOTH / CONNECTING_x /
  RELEASING_x` (`tether_state()`).
- Rules: stepping out secures A on hatch ring A1 (clipped in the chamber
  before the outer hatch opened). Clicking a ring in reach sends the FREE
  tether (connect 0.55 s reach — the hand carries the hook — + 0.3 s seat
  with latch click). A tether can be released (click its ring, or **R**
  = release the older one) only while the OTHER one is SECURED; releasing
  the last one is refused with a visor warning + sound. One transition at
  a time (double clicks / duplicate hooks impossible). A connect
  interrupted by drifting > reach + 0.7 m aborts: hook reels back, the
  other tether never changed; retry works. Re-entering the chamber stows
  both.
- Constraint: each SECURED tether is an inelastic 5.5 m cable from its
  own D-ring; outward velocity past the limit is removed and the suit eased
  back ≤ 2 cm per physics frame. The cable is drawn taut (no sag) at the
  limit. The old failsafe now needs > 8.5 m on the tightest tether
  (never reached in tests).
- Arms: the tether's own hand reaches to the ring (IK), stays while the
  gate seats / opens, and returns.

## C. Anchor graph (Priority 4) — `eva_anchor_graph.gd`
- One shared graph (ids, positions, kinds, links, BFS `route()`):
  A1 hatch, A2 / A3 antenna route, H1 upper hull above the hatch, T0 truss
  at the airlock, L1 (wing root) … L3 (mid) … L5 (outer edge), R0 (hull),
  R1 (root) … R3 (mid) … R5 (outer). Truss / wing rings sit on the
  truss's south maintenance HANDRAIL (z −4.88, y 1.62) — never on cells.
- Longest link 3.6 m against the 7.3 m transfer limit (5.5 tether + 1.8
  clip reach). Tested: A1→L5→A1, A1→R5→A1, A1→A3→A1 with real transfers,
  ≥ 1 tether secured every physics frame.

## D. Solar arrays (Priority 3) — `solar_arrays.gd`
- A truss at z −5.2 (north of the modules) carries two wings: LEFT x −8.7
  … −25.4, RIGHT x 3.3 … 20.0 — a 45 m span against 13 m of modules.
  Bolted to the hull by two strut pairs (Control Room and Living Quarters
  north faces). Four longerons; battens, posts, diagonals, rail
  standoffs, hinges and amber service lights as MultiMesh (7 draws, ~370
  instances; ~270 nodes total). Collision: ONE static body with five
  boxes (truss beam + four panel blankets) so a floating technician bumps
  into the structure instead of drifting through it.
- 16 framed 2.0 m sections per wing (both sides of the truss): dark blue
  cells with a bus-bar grid (one shared 128 px texture), frame bars, back
  stiffener, hinge brackets; tip spreader + blanket box; rotary joints
  (SARJ-L / SARJ-R) with gold bands; truss / wing markings; a power
  conduit on the truss top.
- Visible to EXT-01 (repositioned far overview — whole vehicle) and the
  new EXT-05 SOLAR TRUSS camera (on a short mast above the airlock
  tunnel nose).

## E. Solar power (Priority 5)
- No second simulation: wing output = 6 kW × the faults owned by the three
  solar tasks (`wing_factor`). Load = 5.2 kW + 0.5 kW per Bus A channel
  step (the existing distribution panel). RESERVE (saved, 0..1, a new station starts full) charges on
  a surplus (0.0004 /kW·s) and drains on a deficit (0.0006 /kW·s): a lost
  wing takes most of a shift to matter.
- Bus A voltage droops only when the reserve is < 25 % AND there is a
  deficit; StationStatus raises an Engineering WARNING ("Solar reserve
  low") unless a solar order already explains it. Nothing trips or
  blacks out from solar alone. The power panel shows `SOLAR kW · LOAD ·
  RES %` with a bar and a SOLAR button (the VERIFY OUTPUT step).

## F. Solar tasks (Priority 6) — `solar_*_task.gd` (+ `solar_task_base.gd`)
- **Coupler (wing root, ring L1/R1, order `solar_coupler`, day 11):**
  faults loose (35 %) / degraded (55 %). Inspect window → ISOLATE (wing
  output 0, string safe) → open LATCH → pull PLUG → (degraded: new insert)
  → seat → close latch → re-energise → TEST continuity → back inside →
  power panel SOLAR (verify). Latch / plug refuse while LIVE (AI:
  "That coupler is live. Isolate the string first."); re-energise refuses
  with the latch open or plug out.
- **Hinge latch (mid-wing, ring L3/R3, `solar_hinge`, day 13):** variants
  latch (open fully, then seat), fastener (3 ratchet turns), bracket
  (release, then align). While faulted the north section sits 7° off-plane
  (static, eased) and the wing gives 78 %. A final INSPECT of the lock
  indicator verifies the mechanical state (order closes).
- **Outer panel (wing tip, ring L5/R5 only, `solar_clean`, day 10):**
  three real film patches on the outer cells + a filmed sun-sensor lens;
  wing at (1 − 0.45 × soil), sensor under-reads 71 %. Wipe patches, wipe
  the lens, read the sensor (99 %), get back inside (order closes).
- Faults come from the order seed (never re-rolled; saved per task).
  `LONG_EVA` rule: never more than one long EVA order open (antenna and
  the three solar jobs).

## G. Worksites (Priority 7)
- `eva_system.register_worksite(id, stance, look, rings, parent, hold)`:
  a yellow handhold bar on the truss rail (antenna: the A1 worklight
  post). Click within 1.7 m → STABILISE: the body eases ≤ 0.6 s into the
  stance (never a long move), thrust locks, pose WORK (knees in the foot
  restraint, both hands forward). Click again or press W to push off.
  Solar worksites require a SECURED tether on their ring.

## H. Suit (Priority 8) — `technician_rig.gd`
- ROOT CAUSE of the rectangle when looking down: the Round 39 chest
  control unit was a BOX whose front face was 7.5 cm IN FRONT of the eye
  plumb line (EYE_POINT z −0.12) — a downward look hit its flat top.
- New suit on the same skeleton (skinned, no new bones): white fabric
  garment (recoloured coverall), grey bearings at shoulders / elbows /
  wrists / waist / knees / ankles, gauntlet cuffs, boot overshells, hard
  upper-torso band, dark harness webbing with two D-rings (tether A / B),
  rounded lofted life-support pack with service panel, O2 bottle bumps,
  hoses and status lights, a rounded abdomen display (12 cm lower, ≤ 1.3
  cm ahead of the eye line). Helmet (mirror / camera only): rounded shell,
  gold visor with rim, neck seal ring, lamps, antenna stub. Tested: at
  chest height nothing of the suit is in front of the eye line.

## I. EVA animations and sound (Priority 9)
- `player_body.set_eva_pose(pose, reach)`: idle float (arms out, soft
  knees, slow drift), thrust (legs extend, arms trail), coast, brake
  (knees up, arms forward), work (restraint stance, both hands to the work
  point), reach (one arm IK to a world point; never stretched past
  0.62 m). Weights ease at 3/s. Re-entry: the left hand grabs the outer
  hatch frame. Watch / walk / bed poses are untouched inside.
- Suit audio (SFX bus, so settings apply): muted breathing loop, fan hum,
  jet hiss while thrusting, carabiner latch / click. No air-borne exterior
  sound (the Ambient bus stays low-passed in vacuum).

## J. Cameras (Priorities 10-12) — `workstation_shell.gd`, `camera_network.gd`
- Cameras tab: left list (178 px) in INTERIOR / EXTERIOR groups with
  rules; each row "ID  LOCATION" at a font size fitted with real font
  metrics; active row highlighted (cyan, left bar). Right: a 436 × 280
  feed (4:3) with only a REC/ID tag and the clock on its corners. Under
  it: one location line and one blind-spot line, each fitted to width.
  The UI renders into the workstation's fixed 640 × 400 SubViewport, so
  window size / fullscreen / aspect ratio do not change its layout.
- Operations: the duplicate camera feed and CAMERAS button are removed
  (keyboard section → Cameras tab still works).
- INT-02 "CORRIDOR → CONTROL" now hangs under the Junction ceiling
  (0.3, 2.47, 5.25) looking through the corridor and the Control Room
  doorway at the seated operator (verified by ray + frustum). Blind spot:
  the Control Room corners beside the doorway. Curated set: INT-02, -04,
  -05, -07, EXT-01, -02, -03, -05 (only the displayed feed renders).

## K. Story events (Priorities 13-17) — `scripts/story/story_events.gd`
- Separate from DayPlan; observes, never creates work. Phases by day:
  1-5 "This is my job" (no events), 6-11 "Something is wrong", 12+ "I
  don't know what reality is" (GAME_DESIGN has no day numbers; this is the
  Round 41 mapping).
- Each event: stable id, min_day, chance (deterministic per-day hash —
  reloads never re-roll), cooldown_days, max_plays, live eligibility,
  start, safe stop, saved plays / seen / last_day / armed_day. At most one
  event armed per day; missing it costs nothing.
- **corridor_presence** (day ≥ 7, cooldown 3, max 3): seated at the
  workstation, Cameras tab on INT-02, watched ≥ 6 s, INT-02 also watched
  on an EARLIER day, shift > 90 s, no emergency → a dark, faceless,
  motionless person-shaped outline appears on INT-02 (CAMERA_ONLY layer:
  never in the player's eyes or mirrors; no collision). Spots by play
  (always small on the feed): just inside the doorway half hidden by the
  west jamb, mid-room, then right behind the stool. Dim matte material. Gone the
  instant the technician stands, turns toward the doorway, leaves the feed,
  or after 9 s. Recorded seen if on screen ≥ 1.2 s while watched.
- **window_mismatch** (day ≥ 9, cooldown 4, max 2): looking out of the
  observation port ≥ 2.5 s (EXT-03 familiar from an earlier day) →
  `observation_discrepancy` "displaced" for 40 s (tool bag by the mast in
  the window, by the hatch on camera), then both agree again.
- Registered, disabled foundations: hatch_handle, blind_spot_object,
  wrong_reading, radio_contact, laptop_inconsistency. No popups, no
  music, no AI line, no explanation, no identity.

## L. Cargo Drop (Priority 18) — `cargo_drop_game.gd`
- 10 × 15 bay, 18 original loads in four tiers (level 1: block, rods,
  corner, ell, jay; level 2: tee, zig, zag; level 4: long ell, big tee,
  pee, cup, rod5; level 6: eff, enn, stair, wye). Seeded manifest bag
  (every unlocked load once per bag). Wall kicks, ghost, NEXT preview,
  soft (+1/row) and hard (+2/row) drop, pause, restart; rows 100/300/
  500/800 × level; level = 1 + rows/6, faster fall. Sounds on SFX.
- Save: best score as before + an unfinished run (restored PAUSED; the
  snapshot is validated — dimensions, values, the falling load must fit —
  or discarded for a clean restart).

## M. Save / load
- New `r35_equipment` nodes persist automatically: SolarArrays (reserve),
  SolarCoupler / SolarHinge / SolarClean (faults, progress, request /
  verify days), StoryEvents (plays, seen, cooldowns, feed familiarity).
  Tether / worksite state is never saved (saving is still refused
  outside); a load starts inside with both tethers stowed. Old saves load
  (missing sections keep defaults).

## N. Tests
- New: `test_r41_eva_dual_tether`, `test_r41_solar`,
  `test_r41_story_events`, `test_r41_cargo_drop`, `test_r41_cameras_suit`.
- Updated (requirement changes): `test_r40_eva_clarity` (staged re-clip is
  now connect + manual release; W instead of Space; tether chips),
  `test_r38_laptop_station` (8 curated cameras; Cargo Drop row score now
  includes the hard-drop bonus).

## O. Limitations
- The sun is fixed (no orbital day/night on generation).
- Tether cables are shaped curves, not rope physics.
- The suit pack / helmet are lofted primitives, not sculpted meshes.
- Camera labels are English only (no zh-CN for the Cameras tab).
- The five historical MovementNode-graph clearance failures remain: each is
  a diagonal authoring edge that clips a doorway corner by a few cm
  (CommsTunnelANorthWall, CommsEastWallSouth / AlcoveSouthWall,
  JunctionEastWallNorth, EngineeringTunnelSouthWall,
  StorageConnectorANorthWall). Free movement passes these doorways; the
  graph was not re-authored this round (other tests depend on it).
- Outside, the sun also lights the mirror/camera-only helmet layer (the
  helmet rendered black on cameras before).

# Round 42 — Story-driven horror + developer test panel, live surveillance, airlock / EVA corrections, Junction & Comms work, laptop games, station clock

## A. Surveillance
- **INT-02 relocated** to the Life Support approach: hung from the Life
  Support bend ceiling at (-0.35, 2.42, 9.50), fov 40, looking down the
  Life Support tunnel, Junction A and the corridor to the Control Room
  seat (verified with physics rays: Junction A, corridor, doorway, seat;
  Engineering not visible). Drop arm reaches the ceiling. Blind spots: the
  Engineering and Comms side openings of the Junction.
- **Stale feed root cause**: the workstation's Cameras page only requested
  its feed while the technician was SEATED; standing up released it, the
  SubViewport went UPDATE_DISABLED and the monitor kept showing the last
  frame (technician seated). Now the monitor feed renders whenever the
  monitor can be seen (Control Room / corridor / Junction A), at HI
  1280x720 while seated, LO 640x360 otherwise; nobody near = not rendering;
  returning = fresh frames. The legacy cameras outside the network
  (INT-01, INT-03) no longer render every frame for nothing. Only one
  technician rig exists (+ the stowed suit garment); no proxies.
- **Resolution**: camera feeds 16:9 (1280x720 inspected); the workstation
  UI renders at 2x (1280x800 for its 640x400 layout via size_2d_override);
  INSPECT mode gives the feed the whole monitor and narrows the seated
  field of view (x0.7) so the player leans in; prev / next / back.
- **EXT-01 retired** (`RETIRED`), ids not renumbered; 7 curated feeds.
- Developer layer can take a feed offline ("NO SIGNAL").

## B. Story phases (narrative, not calendar)
- `story_events.gd`: phase 1 -> 2 needs intro_complete (day >= 2),
  station_familiar (>= 3 duty kinds closed + feeds used on 2 days) AND the
  deliberately read handover note (laptop Documents; the assistant points
  at it once familiar). Late phase 2: two DIFFERENT anomalies SEEN. Phase 3:
  three seen + two physical INVESTIGATIONS (turn round during the
  presence, go to the airlock after the handle, compare the wall panel
  with the workstation). Round 41 saves migrate (played flags kept;
  anything played -> phase 2, `migrated_r41`).
- Registry: corridor_presence, window_mismatch, wrong_reading (phase 2),
  hatch_handle (late 2); unavailable: blind_spot_object, radio_contact,
  laptop_inconsistency (listed, never triggerable). Abnormal variants
  only in phase 3.

## C. Developer panel (debug builds only)
- `scripts/dev/dev_panel.gd`, built by StoryEvents only when
  `OS.is_debug_build()`; F8; unlock code `justeason` once per session
  (convenience, not security). Tabs STORY / EVENTS / STATION / PLAYER /
  SESSION: trigger (preview, not counted), trigger+count, arm, cancel,
  reset, seen, enable, variants, phase override (never saved); station
  faults through each device's own API with snapshot / restore; safe
  teleports (refused while suited / seated); restore-all.
- Release builds: no panel instance, no F8 handler, every `dev_*` call
  refuses. (Exported release presets should also exclude scripts/dev/.)

## D. New anomalies
- hatch_handle: knock at the airlock; on EXT-02 / INT-07 a CAMERA_ONLY copy
  of the outer hatch's dogging handle turns (32 deg, abnormal 70 deg)
  while the real handles are DIRECT_ONLY for the duration; real hatch,
  pressure and latch state are never touched. Going to the airlock ends it.
- wrong_reading: the Control Room ENVIRONMENT wall panel shows a
  contradictory cabin pressure (abnormal: impossible zeros) through a
  tagged presentation override (`override_source = story:wrong_reading`);
  `text()` / EnvironmentModel / workstation keep the truth; expires; never
  saved.
- corridor_presence spots moved onto the new approach (Junction A,
  corridor, doorway; abnormal: behind the stool).

## E. EVA / airlock
- Stowed suit = a second technician_rig.gd with the suit on, head hidden,
  hanging pose, on a yoke with restraint straps, umbilical and status lamp;
  hidden while worn (empty yoke + open straps + IN USE lamp).
- Float model: mag boots released when the chamber vents (or the outer
  hatch is open / pressure below station); engaged only when sealed and
  pressurised, followed by a bounded settle (no snap). Pressure is not
  gravity: walking is the boots on the deck.
- Console: OUT<< (left, toward the outer hatch) / IN>> (right); screens
  show IN/OUT hatch states and the cycle.
- Hatch seal hold test: refused HATCH OPEN / CYCLING / LOW PRESSURE /
  SECURE HATCH; aborts if the hatch opens; PASS cleared when the outer
  hatch opens again.
- Solar hinge "L3 at R3" root cause: both wings carry identical hinge
  hardware; working the healthy wing's hinge gave a misleading "tether on
  L3". Rings are now derived from the worksite (same wing, <= 3.5 m: L3/L4,
  R3/R4), the healthy hinge explains where the fault is, and an orange
  SERVICE tag marks the faulted hinge. Coupler / clean tasks got the same
  wrong-wing message.

## F. Maintenance
- Electrical (and every focused 3D view) blur root cause: canvas_items
  stretch rendered the SubViewport in canvas units, then magnified it.
  `hidpi_viewport.gd` renders at the real screen scale and remaps mouse
  input; inert at scale 1.
- Comms: ONE authoritative tuning state; deterministic daily profile,
  saved; physical console shows F / G / LINK; LINK = tuning x antenna feed
  x patch bay x B-04 power; the "SIGNAL LOCKED" twin no longer sticks.
- New orders: patch_bay (day 12), emerg_lights (14), junction_panel (15),
  backup_rx (16) — physical, seeded, saved, auto-closing.
- Ceiling LED strips 1.6 -> 0.55 glow; room lights dimmed (task lights kept);
  ambient 0.25 -> 0.2.
- Navigation: the five historical diagonal links re-authored with corner
  waypoints; the known-failure baseline is now empty.

## G. Laptop / clock / orbit
- Personal Log cropping root cause: the editing menu bar's minimum width
  (560 px > 456 px) widened the page; title clips, clock compact, runtime
  fit guard.
- Cargo Drop: spawn-blocked or lock-out = GAME OVER panel (final / best,
  RESTART / DESKTOP).
- HOLDOUT survival game (WASD via the laptop's own input, auto-fire,
  walker / runner / brute, waves, credits, 7 upgrades, save of wallet /
  ranks / best only).
- Station clock 08:00-16:00 over shift_duration_s, continuous overtime;
  the watch shows DAY + time first; emergencies below it. No bunk push /
  tiredness while suited or in EVA.
- Orbital cycle (360 s orbit, 70 s eclipse, 12 s penumbra): the phase is
  DERIVED from the saved shift clock (each shift starts at sunrise) plus a
  saved constant offset, so a load reproduces the same sunlight exactly;
  one sun for window and cameras; generation x sun; an eclipse costs ~34 %
  of the reserve. Interior lights spill onto the near exterior hull (a
  pre-existing light-layer issue), so the close courtyard seen through the
  port changes less in eclipse than wide exterior feeds.
- INT-02 aims at floor level by the seat (8-10 deg down-tilt).

## H. Limitations
- English-only camera / developer UI. Suit donning has no animation (the
  state change is immediate). Holdout runs are not saved mid-run (by
  design). The orbit timing is compressed for play.
