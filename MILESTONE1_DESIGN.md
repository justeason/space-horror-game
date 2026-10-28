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
