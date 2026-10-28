# Satellite Maintenance Horror Game — Game Design Document

> **Status:** Planning baseline / locked design reference  
> **Purpose:** This document is the authoritative design reference for the game's gameplay philosophy, systems, task structure, station topology, interaction vocabulary, and horror pacing.
>
> **Implementation rule:** When implementing a feature, preserve the principles in this document unless the user explicitly changes the design. Do not invent new systems merely because a simpler implementation is inconvenient.
>
> **Companion document:** `MILESTONE1_DESIGN.md` holds the Milestone 1
> design-readiness audit, room interior specifications, task interaction
> specifications, and the Slice A/B implementation specs built on top of
> this document's locked material. That file is where locked decisions
> here get turned into something implementable — it never overrides
> anything locked in this file.

---

# 1. Game Identity

This is a **first-person spacecraft technician simulation/adventure with slow-burn psychological horror**.

The player is an isolated orbital maintenance technician responsible for keeping a spacecraft, station, or satellite functioning.

The important distinction is:

> **The game is not primarily a horror game in which the player happens to repair machines. It is a technician game in which horror slowly invades a believable routine.**

The ordinary maintenance gameplay must be enjoyable even if the supernatural/horror layer were removed.

The player should gradually learn:

- where things belong
- how systems normally sound
- how rooms normally feel
- what normal readings look like
- how maintenance procedures work
- which tools belong in which rooms
- how long familiar tasks normally take
- what the station looks like from observation windows
- what normal camera footage looks like
- what they personally did earlier in the day

Later, horror works by violating those established expectations.

The strongest horror is often not an obvious monster. It is:

> **"I know this station. That is not how it is supposed to be."**

---

# 2. Core Design Philosophy

## 2.1 Routine first, horror second

The opening should not scream "horror."

The player should initially think:

- I have a job.
- I know what I am supposed to do.
- I need to keep this place operational.
- I am learning the station.
- I have a schedule.
- I need to remember where equipment is.

Horror gradually becomes more important as the player's confidence in their understanding of the station increases.

## 2.2 Establish normal reality before breaking it

The game should deliberately teach the player what "normal" means.

Examples:

- A particular tool normally lives on a particular rack.
- A particular corridor normally has a certain sound.
- A particular camera normally shows an empty hallway.
- A particular door normally opens in a particular way.
- A particular sensor normally agrees with another sensor.
- A particular observation window normally shows a particular module.
- A particular maintenance procedure normally follows the same sequence.

Later:

- the tool is missing
- the corridor sound changes
- the camera shows something the player did not see
- a door moves when nobody is there
- sensors disagree
- an object appears somewhere impossible
- the outside view contradicts the inside station layout
- the maintenance log contains something the player does not remember writing

The player should have enough established knowledge to recognize the contradiction.

## 2.3 Do not over-explain the horror

The game should preserve ambiguity for a long time.

Possible grounded explanations can include:

- fatigue
- nutrient deficiency
- stress
- isolation
- sleep problems
- hallucination
- memory problems
- equipment malfunction
- sensor failure

But there should also be evidence for explanations such as:

- temporal displacement
- spacetime distortion
- alternate reality
- another version of the station
- another version of the player
- an unknown phenomenon

Neither explanation should immediately invalidate the other.

The player should be able to think:

> "Maybe I am hallucinating."

and then encounter evidence that makes that explanation uncomfortable:

> "But the camera recorded it."

---

# 3. Three Narrative / Horror Phases

## Phase 1 — "This is my job"

The player learns:

- movement
- station layout
- daily schedule
- workstation
- tools
- equipment
- maintenance procedures
- normal sounds
- normal readings
- object locations

Small anomalies may occur, but they are rare and understated.

The player should still primarily feel like a technician.

## Phase 2 — "Something is wrong"

The player understands the station well enough to recognize contradictions.

Examples:

- equipment behaving incorrectly
- missing or relocated objects
- unusual radio transmissions
- unexplained sounds
- strange window sightings
- camera contradictions
- maintenance records that do not make sense
- inconsistent sensor readings
- objects appearing where they should not be

The player begins actively questioning reality.

## Phase 3 — "I don't know what reality is"

Established rules begin breaking.

Possible events:

- time discrepancies
- impossible timestamps
- contradictory physical and instrument evidence
- impossible station geometry
- communications from impossible times
- another version of the player
- another version of the station
- exterior/interior spatial contradictions
- events that cannot be explained by ordinary equipment failure

The player should no longer know whether the problem is:

- their mind
- the station
- time
- space
- an external phenomenon
- or some combination.

---

# 4. Horror Pacing

Horror should be deliberately spaced.

Do **not** produce an anomaly every day.

A useful pacing pattern is:

> normal → normal → tiny anomaly → normal → normal → strange event → normal → normal → bigger event

Silence is important.

After an unusual event, the game should often return to ordinary work.

This gives the player time to wonder what happened.

### Important rule

Do not turn the pacing director into a visible schedule.

The player should never feel:

> "It has been five minutes, so a horror event must happen now."

The director should control pacing invisibly.

---

# 5. Player Perspective and Movement

The game uses a **first-person perspective**.

The player should feel physically present in the station.

The environment should be experienced through:

- walking
- looking around
- physically approaching equipment
- operating physical controls
- carrying equipment
- sitting at workstations
- looking through observation windows
- listening to the environment

## 5.1 Movement system

Movement is **node-based rather than free WASD navigation**.

The player:

1. looks toward a direction
2. clicks
3. smoothly walks toward the appropriate movement node

Movement must feel like physical walking rather than teleportation.

### Movement principles

- smooth camera translation
- natural mouse look
- footsteps during movement
- multiple nodes in long corridors
- direction-based candidate selection
- no obvious instant teleport
- movement markers are subtle and immersive
- no bright gamey floor arrows

Current movement architecture uses:

- `MovementNode`
- room regions
- tunnel node chains
- angle-based movement candidate selection

A room can contain multiple nodes in the same region, allowing more flexible movement.

A narrow tunnel should normally use sequential nodes to preserve spatial pacing.

A junction can use a node with multiple neighbors or a small node cluster.

Loops are allowed.

## 5.2 Implemented interaction controls (prototype)

The bunk/laptop/daily-log interaction (the only seated interaction
implemented so far) uses this keyboard scheme:

- **E** near the bunk: sit down on the bed. **E** again from any seated
  state (sitting, laptop open, or editing): get up and return to the
  standing position the player was at before sitting down.
- **F** while seated: open the laptop (picks it up onto the lap,
  physically, as a reparented world object). **F** again while the
  laptop is open (not editing): close it.
- **T** while the laptop is open (not yet editing): enter the
  daily-log editor. The camera eases closer to the laptop's physical
  screen (an "editor zoom," not a 2D overlay or a teleport) so the
  text is actually readable; the laptop and its screen remain real 3D
  objects the whole time. (A previous round also made bare **T** exit
  the editor again, as a toggle — removed: it silently ate every
  literal "t" typed into the entry, e.g. "Quiet shift." became
  "Quie shift." Esc is the only exit key.)
- **Esc** while editing: save the entry and ease the camera back out to
  ordinary seated laptop-viewing framing. Does **not** close the
  laptop and does **not** stand the player up — this is deliberate, so
  a suspicious sound or something glimpsed in peripheral vision can be
  checked immediately by looking around once back in ordinary viewing.
  A bright "ESC — Exit editing" hint is shown directly on the laptop's
  physical screen (not a camera-space overlay) for the whole time the
  editor is open, replacing a dim, easy-to-miss hint of the same text.
- **Ctrl+S** while editing: save the entry without exiting the editor.
- The editor-zoom camera aligns its facing direction with the screen's
  own front-facing normal (not just "look at the screen's center
  point"), so the screen reads as a flat rectangle instead of a
  keystoned trapezoid while editing.
- Mouse-look is enabled in ordinary SITTING/LAPTOP viewing (idle
  focus-assist gently guides attention toward the laptop, but any live
  mouse input always overrides it immediately). **While actually
  EDITING, mouse-look is locked** — the camera stays exactly on the
  screen until Esc is pressed. This is a deliberate reversal of an
  earlier round's "always free-look" design; the "quickly check a
  noise" need is still met because exiting is instant and free-look
  resumes the moment you're back in ordinary laptop viewing.

The player sits in a dedicated **SittingPose**, reclined back toward
the bunk's headboard rather than sitting bolt upright (not the flat
**LyingPose**, which is preserved for a possible future "actually go
to sleep" mechanic but is not reachable from any interaction right
now). Opening the laptop plays a brief reach-and-retreat gesture with
the sitting pose's hand, timed to the laptop's own pickup+hinge
animation, so the player visibly opens the lid themselves.

Getting up (**E**) plays a 7-stage staged sequence rather than a single
rise: lean forward, one leg swings down and plants on the floor, the
other leg follows, the stance settles, the body pushes up to standing
(swapping to StandingPose only once the eye has risen most of the way,
not at the very start of the rise), then the player walks back to
where they were before sitting down. Which leg leads alternates every
time. This is still fundamentally a transform-offset/pose-swap trick,
not true skeletal animation — see the Section 52.1 roadmap for why a
fully convincing version needs the Milestone 2 character model.

---

# 6. Station Layout Philosophy

The station should feel like a real modular spacecraft rather than a grid dungeon.

The logical floor plan is a planning tool, not literal rectangular geometry.

Actual geometry should use:

- offsets
- elbows
- changing corridor widths
- alcoves
- hatches
- equipment bays
- irregular room shapes
- observation points
- dead ends
- maintenance passages

The station should visually communicate:

> **modules connected by tunnels and structural spaces**

rather than:

> **rooms placed on a square grid.**

---

# 7. Locked Floor Plan — Logical Topology v1

Coordinate convention:

- `(1,1)` = top-left
- X increases to the right
- Y increases downward

| Y \ X | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | Living | | | | | | | |
| 2 | | | | | | Living | | | | | | | |
| 3 | | | | | | Control | | | | | | | |
| 4 | | | | | | Control | Corridor | Corridor | Comms Corridor | Comms | | | |
| 5 | | | | Storage | Storage | Junction | Junction | Junction | Life Support | Life Support | | | |
| 6 | | | | Storage | Storage | Junction | Junction | Corridor | Life Support | Life Support | | | |
| 7 | | | Engineering | Engineering | Corridor | | | Corridor | Life Support | Life Support | | | |
| 8 | | | Engineering | Engineering | Corridor | | | Corridor | | | | |
| 9 | | | Engineering | Engineering | Maintenance | Maintenance | Maintenance | Corridor | | | | Airlock | |
| 10 | | | | | | | | | | | | Airlock | |
| 11 | | | | | | | | | | | | | |

## Canonical logical topology (locked)

This diagram is the authoritative statement of logical relationships. It is
**not** a literal rectangular floor plan — see "Physical geometry" below.

```text
                     ┌── Living
                     │
                Control
                     │
                     │
             ┌───────┴───────┐
             │  MAIN         │──────── quiet branch ───── Communications
             │  JUNCTION     │
             ├───────┐       │
             │       │       │
          Storage    │   Life Support
             │        │      │
             │        │      │
         Engineering ──────────┘
             │
       maintenance
          branch
             │
          Airlock
```

## Intended topology

- Living → Control → Main Junction
- Junction left → Storage
- Storage → Engineering
- Junction right → Life Support
- Engineering ↔ Life Support through a maintenance connection/loop
- Main Junction → longer quieter branch → Communications
- Engineering / maintenance side → far Airlock / EVA
- Airlock should have a deliberate exterior relationship and future EVA access
- Communications and EVA are deliberately farther away and more isolated
- Storage is central-ish to maintenance operations but must not become a mandatory transit checkpoint

### Main Junction

The Main Junction must be a genuine multi-direction spatial decision point.

When the player reaches it, there should be meaningful routes/directions toward:

- Control
- Storage
- Life Support
- the long Communications branch

It must **not** become a simple linear hallway where the player enters the
junction and can only proceed toward one room.

The player should be able to develop a strong mental map of the junction and
its branches.

### Storage

Storage has a deliberately restricted role.

Storage should **not** be a general transit corridor or central checkpoint.

Storage should primarily connect/access:

- Engineering
- Life Support

Storage is intentionally located close to those two maintenance-oriented
areas while being relatively far from:

- Living
- Control
- Communications

This makes Storage a logistics/maintenance space rather than a room the
player naturally walks through every day.

### Engineering / Life Support

Engineering and Life Support should have a meaningful maintenance
connection/loop.

Engineering also provides the maintenance-side route toward the future
Airlock/EVA area.

### Communications

Communications should be reached through a longer, quieter, more isolated
branch from the Main Junction. It should feel meaningfully farther away from
the operational center.

### Airlock

The Airlock/EVA area should be at the far end of the Engineering/maintenance
side rather than near the Main Junction.

### Physical geometry

Do **not** translate the logical diagram literally into a straight-line or
symmetric station.

The actual 3D station should use:

- irregular/offset geometry
- elbows and turns
- varied corridor lengths
- varied corridor widths where appropriate
- partial sightlines
- alcoves
- recognizable spatial landmarks
- some destinations visible from junctions and others hidden around corners
- believable spacecraft/module construction

Avoid:

- grid-dungeon appearance
- perfect symmetry
- a simple hub-and-spoke room arrangement
- a linear sequence of rooms

The goal is that the station feels like a real spacecraft that the player
can gradually memorize. The player's learned spatial understanding is
important for the later horror design: future anomalies can contradict
established routes, distances, sightlines, or room relationships.

### Operational centrality

Control is **operationally central**, not necessarily geometrically central.

It contains:

- workstation
- diagnostics
- task queue
- logs
- communications
- surveillance
- station status

The player may visit Control multiple times during a day.

However:

> **The player must not be forced to return to Control between every room.**

Example natural route:

> Control → Engineering → Storage → Engineering → Communications → Living

is valid.

---

# 8. Room Identities

Each room should have a distinct emotional and functional identity.

| Area | Identity |
|---|---|
| Living Quarters | personal / comfortable |
| Control Room | operational home base |
| Storage | logistics |
| Engineering | machinery / electrical |
| Life Support | environmental / mechanical |
| Communications | isolated / informational |
| Maintenance spaces | claustrophobic |
| Airlock / EVA | exposed / dangerous |

Overall emotional progression:

> **comfortable → functional → claustrophobic → exposed → terrifying**

Living Quarters begins as a safe baseline.

Later, that baseline may be subtly violated.

---

# 9. Daily Gameplay Loop

The intended high-level loop is:

> **Living Quarters**
>
> wake → morning routine → food/water → preparation
>
> ↓
>
> **Control Room**
>
> sit at workstation → operate spacecraft computer → inspect station → review tasks/priorities
>
> ↓
>
> **Workday**
>
> choose efficient task order → travel → inspect → diagnose → retrieve/carry equipment → repair → verify
>
> ↓
>
> **Control when useful**
>
> diagnostics / logs / communications / surveillance / new tasks
>
> ↓
>
> **Living Quarters**
>
> evening routine → prepare for bed → sleep
>
> ↓
>
> next day

Control is a useful operational hub, not a checkpoint.

---

# 10. Time and Day System

A workday should feel like approximately **15–30 minutes of actual gameplay**, with roughly **20 minutes** as the intended experience.

Time matters for:

- task scheduling
- work priorities
- meals
- sleep
- logs
- radio timestamps
- maintenance history
- later horror/time contradictions

## Physical time indicators

The game should eventually have:

- a physical Control Room clock
- a wristwatch

The wristwatch is checked automatically when the player wakes.

Later, time can become part of the horror.

Examples:

- clock and wristwatch disagree
- a log timestamp is impossible
- a message appears to have arrived before it was sent
- the player remembers an event at a different time
- sleep appears to have changed the station's timeline

---

# 11. Living Quarters Routine

Living Quarters provides the beginning/end of each day and establishes normality.

## Morning

1. Wake up
2. Eyes open
3. Automatically check wristwatch
4. Optional personal routine:
   - brush teeth
   - get dressed
   - eat
   - drink
   - other personal preparation
5. Leave for work

The wristwatch check is automatic, not a click interaction.

Optional activities can be skipped.

## Evening

1. Return to Living Quarters
2. Optional personal routine
3. Prepare for bed
4. Eyes close
5. Sleep
6. Next day begins

Later, sleep can become a horror transition.

Possible changes after sleeping:

- object moved
- door state changed
- clock incorrect
- log changed
- equipment status changed
- unfamiliar sound
- something appeared/disappeared

The player should question whether the change occurred while asleep or whether they remember incorrectly.

---

# 12. Personal Routine Interaction Philosophy

Not every routine action should be a minigame.

Examples:

### Brushing teeth
Short timed interaction or repeated/rapid clicks.

Faster clicking can represent effort and save time.

### Hair brushing
Simple one-click interaction.

### Getting dressed
One interaction.

### Drinking/eating
Short interaction.

### General rule

Repeated clicking is acceptable when it represents physical effort.

However:

> **Do not turn every mundane action into repetitive clicking.**

The player should spend most of their time on interesting technician work.

---

# 13. Control Room Workstation

The player should:

> **walk to workstation → sit → physically operate spacecraft computer**

The workstation is a primary gameplay interface.

It should feel like equipment in the world, not a detached game menu.

## Computer information hierarchy

Likely areas include:

- Systems
- Tasks
- Communications
- Logs
- Station Status
- Diagnostics
- Surveillance

Exact UI can evolve.

Navigation should follow:

- 1 click = ideal
- 2 clicks = normal
- approximately 2–3 clicks maximum to reach useful information
- no deep menu labyrinth

## Physical controls

The computer exists alongside physical controls:

- switches
- knobs
- breakers
- indicator lights
- panels
- maintenance controls

Some procedures should move between digital and physical actions.

Examples:

> computer diagnostic → physical inspection → repair → computer verification

or:

> physical control → physical equipment response → computer confirmation

---

# 14. Task Philosophy

The station should feel like a real technician's workplace.

The player should have **responsibilities**, not a list of arbitrary video-game quests.

Tasks should answer:

> **"What would a technician actually do?"**

and then provide an interaction that represents the meaningful part of that procedure.

---

# 15. Three Task Types

## 15.1 Routine / Checklist

Characteristics:

- no urgent deadline
- predictable
- establishes normality
- player chooses when to do it
- common

Examples:

- morning station inspection
- filter inspection
- battery inspection
- subsystem diagnostic
- camera review

These tasks teach the player what normal looks like.

## 15.2 Scheduled

Characteristics:

- recommended time window
- flexible
- may relate to operations or station schedule
- player should plan around other work

Examples:

- scheduled observation
- antenna calibration
- communications check
- environmental calibration

## 15.3 Priority / Emergency

Characteristics:

- genuinely time-sensitive
- may interrupt current work
- has consequences for delay
- relatively rare
- should feel different from normal work

Examples:

- battery overheating
- electrical short
- rapid pressure loss
- CO2 spike
- hull damage

Emergency events must remain special.

If everything is urgent, nothing feels urgent.

---

# 16. Workload and Pacing

A day is a **time budget**, not a task quota.

The director should not attempt to fill every minute with work.

Approximate experience:

- fast player: ~12–16 minutes work + ~4–8 minutes breathing room
- normal player: ~18–23 minutes
- slower player: ~23–28 minutes

The slow player should not be punished indefinitely.

## Pending workload

Normal pending workload should usually remain around:

> **2–3 meaningful unresolved work items**

An emergency can temporarily override this.

After an emergency, the game should usually allow recovery.

## Four event states

### Quiet
No pressing work.

This is intentional downtime.

### Available
Work is available but not urgent.

### Active
The player is currently working.

Avoid unnecessary interruption.

### Priority
Something genuinely demands attention.

---

# 17. Pacing Director

The invisible pacing director may track:

- elapsed time
- completed workload
- current task
- pending tasks
- player pace
- recent interruptions
- recent emergency
- progression
- time remaining

Example initial task weights:

| Task scale | Weight |
|---|---:|
| quick system check | 0.5 |
| simple inspection | 0.75 |
| normal repair | 1 |
| investigation | 1.5 |
| multi-room chain | 2–3 |
| emergency | 2–4 |

Lower weight generally means more frequent.

Higher weight generally means less frequent.

These are **initial heuristics**, not immutable probabilities.

Tune later using real gameplay data.

## Breathing-room protection

After a meaningful task, usually allow approximately **30–90 seconds** of quiet time.

This is not a rigid timer.

During quiet time the player can:

- walk
- inspect
- organize equipment
- return tools
- look outside
- check cameras
- explore
- simply listen to the station

Silence is gameplay.

### Important pacing rules

- Do not interrupt travel with ordinary tasks.
- Emergencies may break that rule.
- Do not immediately replace a completed task with another major task.
- Near the end of the workday, stop introducing major new chains.
- Let the player finish the current job.
- Then allow Control/log → Living → evening → sleep.

---

# 18. Technician Proficiency

The player should become faster through familiarity.

Do not make this primarily an explicit RPG skill tree.

Instead, proficiency should come from:

- player memory
- procedural familiarity
- understanding station layout
- knowing where tools are
- knowing the correct sequence
- recognizing symptoms faster

Example:

Early:

> electrical panel repair takes 2–4 minutes and requires careful procedural attention.

Later:

> the player knows the panel, tool, component, isolation sequence, and verification step, so the same repair is much faster.

The player themselves becomes skilled.

---

# 19. Physical Object Philosophy

The player can carry **one physical item at a time**.

Core actions:

- pick up
- carry
- place
- drop
- return

Tools and components have persistent physical locations.

This creates spatial memory.

The player should eventually think:

> "I know I left that there."

That memory becomes a horror mechanic.

---

# 20. Tool and Component Placement

General rule:

> **Tools live where they are normally used. Replacement components primarily live in Storage.**

## Living Quarters

- personal items
- hygiene items
- food/water
- wristwatch
- personal objects

## Control Room

- diagnostic equipment
- small tester
- headset/radio
- flashlight
- small multitool
- station-access equipment

## Engineering

- electrical tester
- screwdrivers
- pliers
- wire cutters/strippers
- torque tools
- connector tools
- electrical repair equipment

## Life Support

- pressure gauge
- leak detector
- valve tools
- filter handling tools
- environmental equipment

## Communications

- signal tester
- antenna calibration equipment
- communications diagnostic equipment
- electronics repair tools

## Storage

- spare wires
- fuses
- connectors
- filters
- batteries
- replacement components
- specialized spare equipment

---

# 21. Task Interaction Philosophy

The most important rule:

> **The interaction should answer "What am I physically doing?" rather than merely "How do I complete this task?"**

The interaction should represent the meaningful physical procedure while abstracting away boring repetition.

Not every task needs a UI minigame.

---

# 22. Approved Interaction Vocabulary

The following interaction types are valid building blocks:

- Simple click/action
- Timed interaction
- Repeated/rapid clicking
- Sequential disassembly/reassembly
- Color/label identification
- Connect-the-lines
- Circuit tracing
- Diagnostic reasoning
- Calibration/tuning
- Component matching
- Memorization/procedural knowledge
- Physical inspection
- Sound-based diagnosis
- Valve/pressure sequencing
- Leak detection
- Inventory identification
- Computer diagnostics
- Limited QTEs
- Emergency interactions
- Repetitive count interaction
- Hold/steady
- Search/observation
- Combined thinking + doing

Multiple tasks may use the same primitive.

The variety should come from:

- context
- physical object
- procedure
- reasoning
- environment
- consequences

Do not make every task feel like the exact same minigame.

---

# 23. Interaction Examples

## Tighten loose connection

1. Find the connection.
2. Use the appropriate tool.
3. Tighten it.
4. Verify.

Repeated clicking can represent tightening.

## Replace fuse

1. Identify correct fuse.
2. Isolate circuit.
3. Remove fuse.
4. Match replacement rating.
5. Install.
6. Restore circuit.
7. Verify.

## Replace damaged wire

1. Identify affected circuit.
2. Trace circuit.
3. Isolate power.
4. Disconnect damaged wire.
5. Remove wire.
6. Determine replacement specification.
7. Travel to Storage.
8. Retrieve correct wire.
9. Return.
10. Route wire.
11. Connect.
12. Secure.
13. Reassemble.
14. Restore power.
15. Verify.

The travel and logistics are part of the task.

## Observation

No minigame is necessary.

Example:

> "Inspect solar array."

The player physically travels to the observation point and looks.

Possible results:

- normal
- minor damage
- debris
- unexpected configuration
- impossible sighting

Observation tasks are a major tool for establishing normal reality and later breaking it.

---

# 24. Observation Tasks

Observation is intentionally a major task category.

The player should sometimes be asked to:

- visually inspect solar arrays
- inspect exterior hull
- inspect antennas
- check external equipment
- look for damage
- confirm module configuration
- inspect an observation area

The player should actually look.

Later, the same observation task can become horror.

Example:

> The player looks through a window and sees a human-shaped shadow inside a distant module.

The important thing is that the player has previously learned what that module normally looks like.

---

# 25. Tasks Can Have Multiple Outcomes

A task does not always have to end with:

> SUCCESS

Possible outcomes include:

- normal
- minor issue
- real fault
- sensor issue
- temporary fluctuation
- unable to reproduce
- inconclusive
- component genuinely damaged
- false alarm
- unexplained result

This prevents every task from becoming a simple quest-completion machine.

It also provides a natural foundation for horror.

---

# 26. Actionable Tasks vs Backlog/System Tasks

The task database must distinguish between:

## Actionable tasks

Concrete player-facing tasks with meaningful interactions.

These should be prioritized for implementation.

## Backlog/system tasks

Realistic responsibilities that do not currently justify a dedicated interaction.

They can appear as:

- status information
- logs
- diagnostics
- prerequisites
- background processes
- automatically handled responsibilities

Do not force every realistic technician responsibility into a dedicated minigame.

---

# 27. Task Database v1 — Locked

## Control Room

| ID | Task | Frequency | Weight | Time |
|---|---|---|---:|---|
| C01 | Morning Station Inspection | Routine/Common | 1.0 | ~1–2m |
| C02 | Run Subsystem Diagnostic | Common | 0.75 | ~30–60s |
| C03 | Investigate Abnormal Reading | Occasional | 1.0–1.5 | ~1–3m |
| C04 | Compare Conflicting Sensors | Occasional | 1.0 | ~1–2m |
| C05 | Verify Repaired System | Common | 0.5 | ~30–60s |
| C06 | Review Camera Footage | Occasional | 0.75–1.5 | ~30s–2m |
| C07 | Review Maintenance Record | Common/Occasional | 0.5 | ~30–60s |
| C08 | Manually Test Subsystem | Occasional | 1.0 | ~1–2m |

### C01 Morning Station Inspection

Check:

- power
- battery
- pressure
- O2
- CO2
- temperature
- communications
- structural status

It should be one cohesive workstation task, not eight separate minigames.

Possible outcome:

- normal
- abnormal reading → follow-up

### C02 Run Subsystem Diagnostic

Select subsystem → initiate → observe readings.

Possible outcomes:

- normal
- warning
- fault
- intermittent
- inconclusive

### C03 Investigate Abnormal Reading

Compare:

- current reading
- historical reading
- related sensor

Then choose the next investigation.

Possible outcomes:

- real fault
- sensor issue
- temporary fluctuation
- cannot reproduce

### C04 Compare Conflicting Sensors

Example:

> Sensor A and Sensor B disagree.

Player determines which evidence is trustworthy.

### C05 Verify Repaired System

Run diagnostic and confirm the repair.

### C06 Review Camera Footage

Normally nothing happens.

Later:

- impossible movement
- contradiction
- missing event
- camera shows something the player did not see

### C07 Review Maintenance Record

Later:

- changed record
- unknown entry
- handwriting/content player does not remember

### C08 Manually Test Subsystem

Command a physical/system test and observe the response.

### Control backlog examples

Not currently dedicated interactions:

- check station integrity
- check historical reading
- check emergency supplies
- restock component
- send routine report
- receive routine message
- check transmitter/receiver status
- check battery status
- check temperature/humidity

---

# 28. Engineering Tasks

| ID | Task | Frequency | Weight | Time |
|---|---|---|---:|---|
| E01 | Inspect Electrical Panel | Common | 0.75 | ~1–2m |
| E02 | Trace Electrical Circuit | Common/Occasional | 1.0–1.5 | ~1–3m |
| E03 | Replace Fuse | Common | 0.75 | ~1–2m |
| E04 | Replace Connector | Common | 1.0 | ~1–2m |
| E05 | Replace Damaged Wire | Common/Chain | 1.5–2.0 | ~2–4m |
| E06 | Tighten Loose Connection | Common | 0.5–0.75 | ~30s–1m |
| E07 | Battery Inspection | Common | 0.75–1.0 | ~1–2m |
| E08 | Cooling-System Inspection | Common/Occasional | 1.0 | ~1–2m |
| E09 | Diagnose Intermittent Electrical Fault | Occasional | 1.5–2.0 | ~2–4m |
| E10 | Power Rerouting | Occasional | 1.5 | ~2–3m |
| E11 | Battery Overheating | Emergency | 2–3 | ~2–4m |
| E12 | Electrical Short | Emergency | 2–3 | variable |

## E01 Inspect Electrical Panel

Physical inspection of:

- breakers
- wiring
- indicators
- connectors
- heat damage

Possible outcomes:

- normal
- loose connector
- heat damage
- damaged wire
- tripped breaker
- nothing obvious

## E02 Trace Electrical Circuit

Physically trace the relevant circuit.

Wrong paths should simply fail to identify the target rather than create arbitrary punishment.

## E03 Replace Fuse

Identify → isolate → remove → match rating → install → restore → test.

## E04 Replace Connector

Identify → isolate → release → remove → match → install → secure → test.

## E05 Replace Damaged Wire

This is an important multi-room chain task.

## E06 Tighten Loose Connection

A good place for a simple repeated-click interaction.

## E07 Battery Inspection

Check:

- appearance
- temperature
- voltage
- connections
- swelling/damage
- expected range

## E08 Cooling-System Inspection

Check:

- temperature
- pump/fan
- vibration
- sound
- indicators

Sound can be the diagnostic clue.

## E09 Diagnose Intermittent Electrical Fault

Use:

- history
- repeated tests
- test points
- reproduction attempts

May end with:

> fault not reproduced

That is a valid outcome.

## E10 Power Rerouting

Identify alternate path → isolate breakers → correct sequence → activate alternate bus → verify.

## E11 Battery Overheating

Emergency:

- check temperature
- isolate battery
- inspect cooling
- switch to alternate power if necessary
- stabilize
- verify

Limited QTEs can be appropriate under pressure.

## E12 Electrical Short

Identify affected circuit → isolate → follow safety procedure → inspect → restore safe configuration.

---

# 29. Life Support Tasks

| ID | Task | Frequency | Weight |
|---|---|---|---:|
| L01 | Filter Inspection | Common | 0.75 |
| L02 | Filter Replacement | Common | 1.0–1.5 |
| L03 | Airflow Inspection | Common | 0.75–1.0 |
| L04 | Valve Procedure | Common/Occasional | 1.0 |
| L05 | Pressure Leak Investigation | Occasional | 1.5–2.0 |
| L06 | Condensation Investigation | Occasional | 1.0 |
| L07 | Environmental Sensor Calibration | Occasional | 1.0 |
| L08 | Pump Diagnosis | Occasional | 1.5 |
| L09 | Rapid Pressure Loss | Emergency | 2–3 |
| L10 | CO2 Spike | Emergency | 2–3 |

### L01 Filter Inspection

Inspect:

- airflow
- pressure
- contamination
- filter condition

### L02 Filter Replacement

Isolate airflow → close valves → depressurize → remove → match → install → restore valves in correct order → verify.

### L03 Airflow Inspection

Use:

- airflow indicator
- pressure
- ventilation sound
- physical indicators

### L04 Valve Procedure

Correct sequence matters.

This can test procedural memory.

### L05 Pressure Leak Investigation

Check pressure → isolate sections → compare pressure changes → listen → inspect → locate leak.

Possible outcomes:

- real leak
- sensor problem
- environmental fluctuation
- unable to reproduce

### L06 Condensation Investigation

Inspect:

- temperature
- airflow
- pipe surface
- joints
- surrounding environment

### L07 Environmental Sensor Calibration

Adjust dial/knob until readings converge.

### L08 Pump Diagnosis

Listen first, then inspect physically.

### L09 Rapid Pressure Loss

Emergency:

- identify affected section
- close valves
- isolate
- locate leak
- stabilize

### L10 CO2 Spike

Determine:

- scrubber issue
- sensor issue
- airflow issue

---

# 30. Communications Tasks

| ID | Task | Frequency | Weight |
|---|---|---|---:|
| M01 | Communications Diagnostic | Common | 0.75 |
| M02 | Signal Calibration | Common/Occasional | 1.0 |
| M03 | Antenna Alignment | Occasional | 1.0–1.5 |
| M04 | Weak Signal Investigation | Occasional | 1.5 |
| M05 | Communications Component Replacement | Occasional | 1.5–2.0 |
| M06 | Interference Investigation | Occasional | 1.0–1.5 |
| M07 | Unusual Transmission Investigation | Occasional/Horror-capable | 1.0 |

### M01 Communications Diagnostic

Check:

- transmitter
- receiver
- signal
- antenna

### M02 Signal Calibration

Tune signal using a physical dial/control and observe the result.

### M03 Antenna Alignment

Hold/steady the alignment and watch signal response.

### M04 Weak Signal Investigation

Investigate:

- signal
- receiver
- transmitter
- antenna
- history

### M05 Communications Component Replacement

Isolate → remove → match → retrieve if necessary → install → test.

### M06 Interference Investigation

Use:

- sound
- signal behavior
- tuning
- frequency comparisons
- patterns

### M07 Unusual Transmission Investigation

Receive → record → timestamp → determine source → compare history → investigate contradiction.

Later outcomes may include:

- corrupted transmission
- unknown source
- impossible timestamp
- transmission from impossible location/time

---

# 31. Storage Tasks

| ID | Task | Frequency | Weight |
|---|---|---|---:|
| S01 | Retrieve Component | Common | 0.5–1.0 |
| S02 | Component Matching | Common | 0.75 |
| S03 | Inventory Discrepancy | Occasional | 1.0 |
| S04 | Missing Component Investigation | Occasional | 1.0–1.5 |

Storage is a real physical space.

The player should navigate shelves/racks and physically identify components.

## S01 Retrieve Component

Read requested part → navigate → identify → pick up.

## S02 Component Matching

Compare:

- part number
- shape
- connector
- color
- label

## S03 Inventory Discrepancy

Compare expected inventory with physical inventory.

Possible outcomes:

- counting error
- misplaced
- inventory error
- missing
- already used but not logged

## S04 Missing Component Investigation

Search for an item the player knows should exist.

This is a major future horror hook.

---

# 32. Airlock / EVA Tasks

These are later-phase tasks.

| ID | Task | Frequency | Weight |
|---|---|---|---:|
| A01 | Suit Inspection | Common Later | 1.0 |
| A02 | Airlock Pressure Test | Common Later | 1.0 |
| A03 | External Inspection | Occasional | 1.5 |
| A04 | Antenna External Inspection | Occasional | 1.5 |
| A05 | External Component Repair | Occasional | 2–3 |
| A06 | Hull Damage | Emergency | 2–4 |
| A07 | Solar Array Observation | Common/Occasional Later | 0.75–1.5 |

## A01 Suit Inspection

Inspect:

- seals
- connectors
- gloves
- helmet
- O2
- battery
- communications

## A02 Airlock Pressure Test

Operate:

- door
- pressure system
- gauges
- equalization

## A03 External Inspection

No UI minigame is required.

Player physically goes outside and observes:

- hull
- solar arrays
- antenna
- external equipment
- thermal surfaces

## A05 External Component Repair

Suit prep → airlock → exit → travel → inspect → repair → verify → return.

## A06 Hull Damage

Emergency EVA.

## A07 Solar Array Observation

A major observation/horror task.

Possible outcomes:

- normal
- damage
- debris
- unexpected configuration
- impossible sighting
- later, contradiction in panel count/configuration

---

# 33. Task Dependency Chains

The central pattern is:

> **diagnostic → investigation → retrieve → repair → verify**

Not every task uses every stage.

## Electrical fault

C02 Diagnostic  
→ E01 Inspect Electrical Panel  
→ E02 Trace Electrical Circuit  
→ identify damaged wire  
→ S01 Retrieve Component  
→ E05 Replace Damaged Wire  
→ C05 Verify

Typical route:

> Control → Engineering → Storage → Engineering → Control

## Loose connector

C03 Investigate Abnormal Reading  
→ E01 Inspect Electrical Panel  
→ identify loose connector  
→ S01 Retrieve Component  
→ E04 Replace Connector  
→ C05 Verify

## Fuse

C02 Diagnostic  
→ E01 Inspect Panel  
→ E03 Replace Fuse  
→ C05 Verify

This demonstrates that not every repair needs Storage.

## Battery/cooling

C03 Investigate Abnormal Reading  
→ E07 Battery Inspection  
→ E08 Cooling-System Inspection  
→ identify cooling problem  
→ repair/adjust  
→ C05 Verify

## Life support filter

C02 Diagnostic  
→ L03 Airflow Inspection  
→ L01 Filter Inspection  
→ identify clogged filter  
→ S01 Retrieve Filter  
→ L02 Filter Replacement  
→ C05 Verify

## Pressure leak

C03 Investigate Abnormal Reading  
→ L05 Pressure Leak Investigation  
→ isolate sections  
→ compare pressure  
→ listen/inspect  
→ locate leak  
→ retrieve seal/component  
→ repair  
→ pressure test

## Communications weak signal

M01 Diagnostic  
→ M04 Weak Signal Investigation  
→ M03 Antenna Alignment  
→ M02 Signal Calibration  
→ M01 Verify

## Communications component

M01 Diagnostic  
→ M04 Investigation  
→ M05 Component Replacement  
→ S01 Retrieve Component  
→ repair  
→ M01 Verify

## Missing component

S03 Inventory Discrepancy  
→ S04 Missing Component Investigation  
→ search

Later horror:

> The player knows where the item was, but it is not there.

Then perhaps:

> It appears somewhere impossible.

## Observation

Scheduled observation  
→ travel to observation point  
→ visually inspect  
→ record result

No artificial minigame required.

## Emergency

Example:

E11 Battery Overheating  
→ respond  
→ isolate  
→ inspect cooling  
→ stabilize  
→ verify

Emergency chains can break normal pacing, but should be followed by recovery.

## Unusual transmission

M07 Unusual Transmission Investigation  
→ receive  
→ record timestamp  
→ determine source  
→ compare history  
→ investigate contradiction

Can end unresolved.

---

# 34. First Playable Slices

These are intentionally small implementation targets.

## Slice A — "My First Workday"

### Living Quarters

Wake → automatic wristwatch check → optional drink/eat/get dressed → leave.

### Control

Sit at workstation → C01 Morning Station Inspection → receive normal maintenance task.

### Engineering

Travel to Engineering → E06 Tighten Loose Connection.

Interaction:

- find connection
- use tool
- tighten
- verify

### Control

C05 Verify Repaired System → normal result → end workday.

### Living

Return → evening routine → prepare for bed → sleep.

Slice A validates:

- movement
- scale
- room relationships
- workstation
- task assignment
- physical interaction
- tool use
- verification
- time
- walking
- daily rhythm
- sleep

## Slice B — First Genuine Dependency Chain

Control → Engineering → Storage → Engineering → Control

Example:

C02 Diagnostic  
→ E01 Inspect Panel  
→ discover damaged wire  
→ S01 Retrieve Wire  
→ E05 Replace Wire  
→ C05 Verify

Slice B validates:

- dependency-driven routing
- physical logistics
- one-item carrying
- storage
- repair sequence
- returning to verify

---

# 35. Surveillance System

Surveillance is a core horror mechanic.

The player should not be able to watch everything simultaneously.

Current architecture uses approximately three actual Camera3D feeds.

The console:

- switches feeds
- shows one feed at a time
- uses actual 3D camera views
- uses SubViewport + ViewportTexture
- has stable camera IDs

Current camera IDs:

- `cam_control_room`
- `cam_corridor`
- `cam_corridor_end`

The physical surveillance console is an in-world object.

## Surveillance philosophy

The player can monitor one camera while events happen outside the selected feed.

This creates:

> **information limitation**

rather than an artificial jumpscare system.

---

# 36. Camera Contradictions

A major horror principle:

> **Cameras can contradict reality.**

Examples:

- camera shows a door moving while player hears something elsewhere
- player sees an empty corridor in person but camera shows movement
- camera shows an object that is not physically present
- camera footage changes
- camera records something the player does not remember seeing
- camera and physical observation disagree

One especially important tension pattern:

> The player hears a noise from inside/near a door while the camera shows the external door handle slowly twisting.

The player receives two pieces of evidence that do not fit together.

---

# 37. Observation Windows / Watch Ports

Observation windows are **real spacecraft observation ports**, not monitors.

They should look like:

- rounded/oval opening
- substantial integrated frame
- thick mechanical bezel
- recessed glass
- structural rim
- bolts/fasteners
- industrial materials
- subtle reflections

They must not resemble:

- rectangular screens
- floating UI
- glowing monitors
- generic game HUD displays

The camera-feed implementation should be invisible.

A physical watch port is fixed and non-interactive.

Each port can be assigned one camera feed.

Future ports can be added without redesigning the underlying system.

---

# 38. Exterior Layer and Sightlines

Interior station distance and exterior distance do not have to match.

Two modules may be:

- one or two tunnel hops apart internally
- physically separated across open vacuum externally

That exterior gap is useful for observation.

When creating a module that will be visible from another:

- provide an exterior shell
- create a deliberate exterior gap
- position the viewing window toward it
- place an exterior camera if useful

Exterior equipment should be placed early as static geometry where appropriate:

- antenna masts
- radiator panels
- solar arrays
- EVA hatches

This gives later horror events believable objects to manipulate.

---

# 39. Camera Framing Principle

Every camera placement should have a deliberate purpose.

A camera should be framed around something such as:

- doorway
- equipment
- corridor vanishing point
- junction
- exterior module
- hatch

Do not simply place cameras in generic ceiling corners.

Camera framing is part of level design.

---

# 40. Exterior / EVA Design Principle

Reserve the Airlock as an obvious future EVA exit.

Do not implement a complete EVA movement system prematurely.

The early station should merely ensure:

- exterior hatch exists
- geometry supports future EVA
- exterior sightlines work
- observation windows can see relevant external areas

The full EVA system can be added later.

---

# 41. Daily Log

At the end of a workday, the player can create/review a maintenance report containing items such as:

- power
- life support
- communications
- environmental systems
- maintenance performed
- notes

Later horror can alter the meaning of the log.

Examples:

- a note the player does not remember writing
- a previous report changes
- the player finds a maintenance entry for work they do not remember performing
- the log says something happened at a time the player believes they were asleep

---

# 42. Food, Supplies, and Competing Explanations

Food and supplies are real gameplay elements.

Nutrient deficiency or inadequate food can plausibly contribute to:

- fatigue
- confusion
- memory problems
- sensory abnormalities
- hallucinations

However:

> **Nutrition must never explain everything.**

It should remain one plausible grounded explanation.

The competing explanation may be something genuinely external:

- cosmic phenomenon
- spacetime distortion
- temporal displacement
- alternate reality
- another station
- another version of the player

The player should be uncertain for a long time.

---

# 43. Safe-Zone Philosophy

Living Quarters initially exists as a comfortable baseline.

The player should eventually develop the feeling:

> "At least I am safe here."

Then the game can subtly violate it.

Examples:

- an object moved
- door state changed
- unfamiliar sound
- light behaving differently
- personal item missing
- item appearing somewhere impossible
- watch showing incorrect time
- something outside the window that should not be there

The goal is not constant horror.

The goal is to make the player eventually realize:

> **There is nowhere they can completely trust.**

---

# 44. Horror Through Memory

Memory is one of the strongest horror mechanics because the player themselves is responsible for remembering the station.

Examples:

- tool is missing from its known location
- component is in the wrong rack
- door is open when player remembers closing it
- object moved after sleep
- maintenance record says something different
- player returns to a room and something is subtly different

The game should make the player question:

> "Did the game change, or did I simply remember wrong?"

---

# 45. Audio Philosophy

Audio should support realism before horror.

Normal sounds establish baseline:

- ventilation
- pumps
- fans
- electrical hum
- mechanical clicks
- footsteps
- relays
- distant machinery
- doors
- radio static

Later, small deviations become meaningful.

Examples:

- pump sounds different
- ventilation stops briefly
- relay clicks at an unusual time
- distant metallic impact
- sound comes from a direction where nothing should be
- a familiar machine makes an unfamiliar rhythm

Do not rely primarily on loud stingers.

---

# 46. What the Game Should Avoid

Avoid:

- constant jumpscares
- horror every day
- combat-first design
- excessive monsters
- arbitrary minigames
- giant quest lists
- RPG skill trees for basic technician competence
- returning to Control after every room
- bright gamey movement markers
- UI that feels disconnected from the physical station
- deep menu labyrinths
- making every task urgent
- making every task a timed challenge
- turning every mundane action into a minigame
- rigid room/task quotas
- random events with no relationship to established reality
- unexplained supernatural events before the player has learned normality
- geometry that looks like a grid dungeon

---

# 47. Architecture Principles

The implementation should remain modular and understandable.

Current important primitives include:

- `MovementNode`
- room regions
- tunnel node chains
- `interaction_controller.gd`
- physical interactables with `interact()`
- independent control interactables
- physical control panels
- surveillance camera instances
- SubViewport surveillance feeds
- fixed watch-window camera feeds

Avoid introducing heavyweight architecture before it is justified.

In particular, do not create:

- generic task/objective registries
- global singletons
- unnecessary base classes
- sticky completion systems
- large event frameworks

unless the design actually requires them.

Prefer small systems that compose.

---

# 48. Interaction Architecture Principle

Physical interactables should be independent where possible.

Example:

- each switch has its own state
- switch emits a state-change signal
- control panel listens and evaluates its configuration

Do not make a giant generic controller responsible for every physical object.

The player's interaction raycast should take priority over movement input.

A valid physical interaction should consume the click so it does not accidentally trigger movement.

---

# 49. Current Movement Interaction Rules

The player:

- looks naturally with the mouse
- sees a small center reticle
- clicks to move toward the nearest valid directional movement node
- movement is selected using a direction cone
- current cone is approximately 65°
- movement is smooth
- movement markers are decorative
- markers do not need collision
- markers are not the actual interaction target

Physical interactions use Camera3D raycasting.

---

# 50. Visual Direction

The station should feel:

- industrial
- believable
- functional
- compact
- lived-in
- mechanically dense

It should not feel like:

- a sterile sci-fi corridor
- a generic horror mansion in space
- a maze
- a video-game level made of perfect cubes

Different spaces should communicate their function visually.

Living:

- softer
- personal
- comfortable

Control:

- operational
- information-dense
- central

Engineering:

- cables
- panels
- electrical equipment
- machinery

Life Support:

- pipes
- valves
- filters
- pumps
- environmental machinery

Communications:

- isolated
- equipment-focused
- signal/radio identity

Storage:

- racks
- labels
- bins
- inventory organization

Maintenance:

- narrow
- constrained
- mechanical

Airlock/EVA:

- exposed
- procedural
- dangerous

---

# 51. Development Philosophy

Implementation should be incremental.

Do not build the entire game before testing the core loop.

Recommended workflow:

1. inspect current architecture
2. compare current prototype against this document
3. identify exactly what the next slice requires
4. propose implementation
5. user approves
6. implement only approved scope
7. headless validate
8. user performs hands-on windowed playtest
9. fix issues found in playtest
10. only after user approval, commit/push

Claude should not assume permission to commit or push.

---

# 52. Implementation Priority

The game should be built in slices that test the most important design assumptions.

The immediate priority is not "build every room."

The immediate priority is:

> **prove that the daily technician loop feels good.**

The first physical implementation area should therefore focus on:

> Living → Control → Junction → Storage → Engineering

This is enough to test:

- distances
- room scale
- walking feel
- workday rhythm
- workstation interaction
- tools
- physical components
- storage logistics
- repair
- verification
- returning home

The rest of the station can follow once this slice feels right.

---

# 52.1 Project Roadmap: Prototype First, Then Shared Character Model

Two explicitly sequenced milestones govern the player-character work:

**Milestone 1 — finish and polish the current first-person prototype.**
Bed/laptop interaction, daily-log editing, workstation interaction, and
core maintenance gameplay all need to feel solid on top of the
existing static-CSG-pose body (see Section 47/48's architecture
principles) before any character-model migration begins.

**Milestone 2 — migrate to a shared skeletal character model.**
Once Milestone 1 is solid, replace the separate StandingPose /
SittingPose / LyingPose CSG subtrees (scenes/player/player_body.tscn)
with one rigged model (a simple `Skeleton3D` + a small bone set --
pelvis/spine/head/arms/legs) driving standing, sitting, reaching,
lying-down, and getting-up animations, with the first-person camera
at the head bone's eye socket and a visibility rule hiding the local
player's own head mesh. This is what makes a coherent third-person
body possible for future multiplayer and for mirrors reflecting the
player's own body -- the current architecture, built entirely around
camera-locked static poses with no head and no joint hierarchy, cannot
support either without becoming a second, parallel character system
(see the M9 investigation report for the full trade-off analysis).

Multiplayer networking and a working mirror system are NOT part of
either milestone as currently scoped -- Milestone 2 is the
prerequisite architecture, not the features themselves.

The current get-up animation (a staged sequence within the existing
static-CSG-pose architecture) is known to be imperfect -- this is
tracked as remaining Milestone 1 first-person polish, not a reason to
begin the Milestone 2 migration early.

See `MILESTONE1_DESIGN.md` for the detailed Milestone 1 design-
readiness audit, room interior specifications, task interaction
specifications, and first-playable-slice (Slice A/B) specs built on
top of this document's locked task database (Section 27 onward) and
topology (Section 7).

---

# 53. What Is Locked vs What Is Intentionally Flexible

## Locked

- first-person perspective
- technician-first game identity
- slow-burn horror
- three horror phases
- node-based physical movement
- smooth movement rather than teleportation
- daily routine
- Living → Control → Work → Living loop
- physical workstation
- task categories
- task types
- task interaction philosophy
- actionable vs backlog task distinction
- task database v1
- dependency-chain philosophy
- one-item physical carrying
- tool/component placement philosophy
- observation tasks
- workload pacing philosophy
- quiet time
- emergency rarity
- technician proficiency through familiarity
- daily logs
- competing explanations
- room identities
- logical floor plan topology v1
- Control as operational center, not mandatory checkpoint
- surveillance as a core horror mechanic
- one camera feed at a time
- camera contradictions
- physical observation ports
- modular station architecture
- future EVA relationship

## Intentionally flexible

These should be tuned through actual implementation/playtesting:

- exact room dimensions
- exact corridor lengths
- exact number of movement nodes
- exact task durations
- exact task probabilities
- exact daily workload
- exact horror frequency
- exact observation-port locations
- exact EVA geometry
- final workstation UI layout
- final art style/material detail
- final audio design
- exact number of cameras
- final camera framing
- exact progression timing

Do not treat these flexible values as permanently locked until playtesting supports them.

---

# 54. Design Test for New Features

Before adding a new feature, ask:

### Does it strengthen the technician fantasy?

If not, reconsider it.

### Does it teach or reinforce normal reality?

If yes, it may have strong value.

### Does it provide meaningful player agency?

If not, it may be unnecessary.

### Does the interaction represent a physical action?

If not, reconsider whether it belongs as an interaction.

### Does it make the station feel more believable?

If yes, prioritize it.

### Can the feature later become a horror contradiction?

If yes, that is a strong bonus.

### Does it create unnecessary repetition?

If yes, abstract it.

### Does it force the player into a particular route for no believable reason?

If yes, reconsider the design.

### Does it make everything urgent?

If yes, it is probably harmful to pacing.

---

# 55. Core Design Principles — Short Reference

When in doubt, use these rules:

1. **Routine first. Horror later.**
2. **Teach normal reality before breaking it.**
3. **The player should feel like a technician, not a quest courier.**
4. **Physical actions should matter.**
5. **The station should feel like a real place.**
6. **Tools and objects should have persistent locations.**
7. **The player should build spatial memory.**
8. **Observation is gameplay.**
9. **Silence is gameplay.**
10. **Not every task needs a minigame.**
11. **Not every task needs to end in success.**
12. **Most tasks should be routine; emergencies should be special.**
13. **A day is a time budget, not a task quota.**
14. **Do not interrupt the player constantly.**
15. **Control is operationally central, not a mandatory checkpoint.**
16. **Horror should violate established expectations.**
17. **Cameras can contradict reality.**
18. **Memory can contradict reality.**
19. **Grounded explanations and supernatural explanations should coexist.**
20. **Build small slices and playtest before expanding.**

---

# 56. Canonical Example Day

A normal early-game day might look like:

### Morning — Living Quarters

Wake.

Wristwatch is automatically checked.

Player drinks water and gets dressed.

Leaves room.

### Control Room

Walk to workstation.

Sit.

Run C01 Morning Station Inspection.

Everything looks normal.

New task appears:

> Engineering — loose electrical connection.

### Engineering

Walk through the junction.

Enter Engineering.

Find the indicated panel.

Inspect connection.

Use tool.

Tighten connection.

Verify locally.

Task completes.

### Quiet period

No new emergency appears.

Player can:

- walk
- inspect station
- look outside
- organize tools
- return equipment
- review something optional

This quiet period is intentional.

### Control

Return when useful.

Run C05 Verify Repaired System.

Normal result.

Workday winds down.

### Living Quarters

Return home.

Optional evening routine.

Prepare for bed.

Eyes close.

Sleep.

### Later in the game

The same structure might occur, but one element changes:

> The player tightens a connection in Engineering.

They return later.

The tool is missing.

They remember putting it on the Engineering rack.

The rack is empty.

They check Storage.

It is not there.

They check the camera.

The camera shows the tool being carried into Storage.

The player does not remember doing that.

They go to Storage.

The tool is exactly where the camera showed it.

Nothing overtly supernatural has happened.

But the player's understanding of their own actions is now uncertain.

That is the intended horror language of the game.

---

# 57. Final Intent

The game should make the player care about the station before it asks them to fear it.

The player should eventually know the station well enough that small changes become frightening.

The ideal reaction is not:

> "A monster appeared."

It is:

> **"That wasn't there yesterday."**

or:

> **"I know I left that there."**

or:

> **"The camera says something different."**

or:

> **"That timestamp is impossible."**

or:

> **"I was asleep. So who did this?"**

The ordinary technician routine is therefore not filler.

**The routine is the foundation of the horror.**
