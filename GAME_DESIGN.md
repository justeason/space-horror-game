# Satellite Maintenance Horror

## Game Design & Development Specification

## 1. Project Overview

A first-person atmospheric sci-fi horror game set aboard a small orbital maintenance satellite.

The player is a maintenance technician responsible for keeping the satellite operational.

The game begins as a mundane maintenance simulator. The player performs routine inspections, repairs equipment, monitors systems, communicates with Mission Control, and manages limited resources.

Gradually, the player encounters unexplained events.

The central horror comes from contradictory information.

The player should never be completely certain whether the problem is:

* a mechanical malfunction
* a sensor failure
* a camera malfunction
* human error
* interference from an unknown source
* something physically present on the satellite
* or something else entirely

The game should favor slow-burn environmental and psychological horror over combat, monsters, and frequent jump scares.

---

# 2. Core Player Experience

The intended feeling is:

> "I am actually inside this satellite, and something is wrong, but I don't know what."

The player should feel like a technician rather than a traditional video-game character.

They should:

* walk through cramped satellite corridors
* physically inspect equipment
* operate switches and control panels
* read monitors
* monitor security cameras
* listen to radio transmissions
* investigate abnormal readings
* perform repairs
* make decisions about limited resources
* gradually realize that different sources of information cannot all be trusted

The game should create tension through uncertainty rather than constant danger.

---

# 3. Perspective and Movement

## First-Person 3D

The game uses a first-person 3D perspective.

The environment itself is genuinely 3D.

However, the player does NOT use conventional free WASD movement.

Instead, the player moves between predefined first-person camera nodes.

This is a "node-based first-person" movement system.

Example:

CONTROL ROOM
↓
DOORWAY
↓
CORRIDOR 01
↓
CORRIDOR 02
↓
JUNCTION
↙     ↘
POWER   AIRLOCK

Each node represents a physical position in the satellite.

The player clicks an available direction/location to move toward the next node.

## Important

Movement must NOT feel like teleportation.

When moving between nodes:

* the camera physically translates through 3D space
* the movement takes a short amount of time
* footsteps play
* the environment moves naturally around the player
* the camera can have subtle head movement
* appropriate environmental audio continues during movement

The player should feel like they are physically walking.

For example:

CLICK FORWARD
→ camera moves down corridor
→ footsteps
→ pipes/walls move past the player
→ lighting changes slightly
→ player arrives at next node

The number of nodes should be high enough that walking through the satellite feels physical.

This is particularly important for creating claustrophobia.

Do NOT collapse an entire corridor into one click.

A long corridor should require several movement steps.

---

# 4. Looking Around

At each movement node, the player can look around using the mouse.

The camera should support:

* horizontal looking
* vertical looking
* smooth mouse movement
* configurable sensitivity
* sensible limits on vertical rotation

The player should be able to inspect physical objects from their current position.

---

# 5. Physical Interaction Philosophy

Interactions should feel physical whenever practical.

Avoid generic interfaces such as:

> Press E → open abstract menu

Prefer:

> Look at physical panel → interact with physical switch/button → switch moves → equipment responds → monitor updates → sound plays.

Examples:

* physical switches
* buttons
* circuit breakers
* doors
* handles
* radio controls
* monitors
* maintenance panels
* camera controls
* emergency controls

The environment should communicate functionality visually.

The player should gradually learn what different equipment does.

---

# 6. Core Game Rule: Three Sources of Truth

The game has three major sources of information.

## A. Physical Reality

What the player personally:

* sees
* hears
* touches
* observes

## B. Instrument Reality

What the satellite's:

* cameras
* sensors
* computers
* monitors
* logs
* alarms
* diagnostics

report.

## C. External Information

What external sources tell the player:

* Mission Control
* radio transmissions
* the unknown contact
* maintenance records
* automated messages

These sources may contradict each other.

Example:

PHYSICAL REALITY:
The player hears knocking.

INSTRUMENT REALITY:
Motion sensor reports no movement.

CAMERA:
Corridor appears empty.

MISSION CONTROL:
"No abnormalities detected."

UNKNOWN CONTACT:
"Don't open the door."

The game should NOT immediately tell the player which source is correct.

This contradiction is a central gameplay mechanic.

---

# 7. Surveillance Camera System

Surveillance cameras are a major gameplay mechanic.

The satellite should have multiple cameras covering different areas.

Example:

* Camera 01 — Corridor
* Camera 02 — Airlock
* Camera 03 — Power Room
* Camera 04 — Communications
* Camera 05 — Exterior
* Camera 06 — Storage

The player can only monitor one camera at a time.

The player must manually switch between camera feeds.

This creates a fundamental limitation:

> The player cannot observe the entire satellite simultaneously.

While monitoring one camera, events may occur outside the player's current field of attention.

The player may never know whether they missed something.

---

# 8. Camera Contradiction Mechanic

Cameras do not necessarily represent reality accurately.

Possible situations:

* camera shows an empty corridor while the player hears footsteps
* camera says an airlock is sealed while the physical handle moves
* camera recording contains missing time
* camera shows an object that does not appear physically present
* camera fails exactly when something important may have happened
* camera shows a door open while the physical door is closed
* camera shows something moving through an area that should be empty
* camera appears normal while another sensor reports movement
* camera feed briefly shows a different state than reality

Do NOT overuse these events.

The player should initially assume that the camera is simply malfunctioning.

The uncertainty should gradually increase.

---

# 9. Camera Attention Mechanic

The player can only watch one camera at a time.

This limitation is intentional.

Example:

Player watches:

CAMERA 03 — POWER ROOM

They switch to:

CAMERA 04 — COMMUNICATIONS

While they are watching Camera 04, something may happen in the Power Room.

When they return to Camera 03:

Nothing appears unusual.

The player must wonder:

> "Did something happen while I wasn't looking?"

Some events should only be detectable if the player happens to be watching the correct camera at the correct time.

Other events should leave indirect evidence.

This creates tension without requiring constant enemy AI.

---

# 10. Unknown Radio Contact

An unknown radio transmission gradually becomes an important mystery.

Do NOT begin with:

> "I'm you."

Do NOT immediately reveal the nature of the contact.

The first transmission should be ambiguous and believable.

Example:

"...hello?"

The player may assume:

* radio interference
* another satellite
* a communication error
* a distress transmission
* someone accidentally transmitting

The contact gradually demonstrates knowledge it should not have.

Example progression:

### Early

"Is anyone receiving this?"

### Later

"Your communications antenna is damaged."

The player has not told the contact.

### Later

"Don't open the airlock."

The contact should have no obvious way to know what the player is doing.

### Much later

The contact may demonstrate knowledge that becomes genuinely impossible to explain.

The mystery should develop slowly.

---

# 11. Mission Control

Mission Control should initially feel trustworthy and mundane.

They provide:

* maintenance instructions
* system status
* mission information
* routine communications
* emergency guidance

Later, their information may conflict with evidence inside the satellite.

Example:

Mission Control:

"There is only one crew member aboard."

But the player discovers:

* life-support usage inconsistent with one person
* unexplained occupancy readings
* camera anomalies
* logs referencing another presence

Mission Control should not immediately become obviously evil.

The player should be uncertain whether:

* Mission Control is mistaken
* the satellite data is wrong
* someone is hiding something
* communications have been compromised

---

# 12. Satellite Environment

The satellite should be small and believable.

Initial target:

Approximately 8–10 major locations.

Potential areas:

* Control Room
* Communications Room
* Power Room
* Life Support
* Crew Quarters
* Storage
* Main Corridor
* Airlock
* Exterior maintenance area
* Secondary corridor/junction

The environment should feel compact.

The player should gradually become familiar with its layout.

That familiarity is important because later the game can introduce subtle changes.

Examples:

* a chair is somewhere it wasn't
* a panel is open
* an object has moved
* a cable is disconnected
* a door takes longer to open
* a light is missing
* a previously inaccessible area becomes accessible

The player should notice these changes because they know the environment.

---

# 13. Claustrophobia

Satellite corridors should be narrow.

Avoid unnecessarily large rooms.

The environment should contain:

* pipes
* cables
* vents
* structural supports
* equipment cabinets
* narrow passageways
* mechanical doors
* emergency lighting
* exposed infrastructure

The player should sometimes feel physically trapped inside the structure.

Movement nodes should be placed relatively close together in corridors to create a sense of actual walking.

---

# 14. Resource Systems

Resources should become important later in development.

Potential resources:

* electrical power
* oxygen
* battery
* life support
* temperature
* communications capability

Power should be particularly important.

Different systems consume power:

* lighting
* cameras
* communications
* heating
* life support
* exterior equipment
* sensors

The player may eventually have to choose which systems remain operational.

Example:

Keeping all cameras online may consume power needed for another system.

This should create decisions rather than simply acting as a countdown timer.

---

# 15. EVA

The player can eventually leave the satellite in an EVA suit.

EVA should feel extremely isolated.

Possible systems:

* oxygen
* suit battery
* temperature
* pressure
* distance from satellite
* communications

The outside environment should be visually beautiful but psychologically uncomfortable.

There is almost no physical sound in space.

However, the suit microphone may produce unexplained sounds.

Example:

Three knocks.

The player checks the exterior.

Nothing is visible.

Audio system:

> AUDIO SOURCE: UNKNOWN

Again, the game should not immediately explain what happened.

---

# 16. Combat

There should be no conventional combat system.

The player's primary advantage is knowledge.

The player understands:

* the satellite
* its systems
* its cameras
* its sensors
* its resources

Survival should depend primarily on observation, reasoning, preparation, and decision-making.

---

# 17. Horror Philosophy

Avoid:

* constant jump scares
* enemies constantly chasing the player
* excessive gore
* obvious monsters appearing early
* horror music constantly signaling danger

Prefer:

* silence
* mechanical sounds
* radio static
* distant noises
* subtle environmental changes
* contradictory information
* missing information
* camera anomalies
* unexplained events
* uncertainty
* isolation

The player should often be asking:

> "Did I actually see that?"

rather than:

> "Where is the monster?"

---

# 18. First Vertical Slice

The first playable prototype should NOT contain the entire game.

It should contain approximately 10–15 minutes of gameplay.

Initial environment:

* Control Room
* Short Corridor
* Communications Room
* Airlock

Initial systems:

* first-person camera
* node-based movement
* smooth walking transitions
* mouse look
* basic physical interaction
* one communications panel
* one surveillance console
* one surveillance camera
* one airlock
* basic environmental audio
* radio communication

---

# 19. First Gameplay Sequence

### Step 1 — Wake Up

Player begins inside the satellite.

Mission Control provides routine instructions.

Nothing is obviously wrong.

### Step 2 — Routine Maintenance

Player receives simple tasks.

Example:

* inspect communications
* check power
* verify antenna

### Step 3 — Communications Error

The communications system reports an error.

Player physically investigates the panel.

Diagnostic appears normal except for an unexplained signal.

### Step 4 — Unknown Transmission

Radio produces static.

Then:

"...hello?"

Player can respond.

No explanation is provided.

### Step 5 — Surveillance

Player hears a metallic sound.

They inspect the surveillance console.

They cycle through cameras.

Nothing unusual appears.

### Step 6 — Airlock Warning

Airlock system reports an abnormality.

Player checks the airlock camera.

Camera reports:

DOOR: SEALED
PRESSURE: NORMAL
OCCUPANCY: 0

### Step 7 — Physical Contradiction

While the player is near the airlock:

The physical handle moves.

The player hears a metallic mechanism.

The camera still reports:

DOOR: SEALED

This is the first major contradiction between physical reality and instrument reality.

### Step 8 — Camera Recheck

Player returns to the surveillance console.

Camera shows the airlock.

The door appears normal.

The player switches away.

When they return, the door's visual state has changed.

The logs do not record the change.

### Step 9 — Unknown Contact

The radio activates.

The unknown contact says:

"Don't open the airlock."

The player has not told the contact about the airlock.

The contact refuses to explain how it knows.

### Step 10 — End of Prototype

End the vertical slice here.

Do not immediately reveal the answer.

The player should be left with questions.

---

# 20. Development Order

Development should proceed incrementally.

M0 — Project setup

M1 — First-person camera and node movement

M2 — One 3D room

M3 — Physical interaction

M4 — Monitor/control panel

M5 — Surveillance camera system

M6 — Camera switching

M7 — Camera/reality contradiction

M8 — Radio system

M9 — First 10–15 minute horror sequence

M10 — Satellite expansion

M11 — Resource systems

M12 — EVA

M13 — Full mystery/story

M14 — Multiple endings

Do not skip ahead unnecessarily.

Each milestone should be playable and tested before moving to the next.

---

# 21. Technical Direction

Recommended engine:

Godot 4.x

Recommended language:

GDScript

The project should be designed for maintainability rather than rapid generation of a large amount of code.

Potential architecture:

Game
├── Player
│   ├── FirstPersonCamera
│   ├── MovementController
│   └── InteractionController
│
├── Navigation
│   ├── MovementNode
│   └── NavigationGraph
│
├── Interactions
│   ├── Switch
│   ├── Button
│   ├── Door
│   └── ControlPanel
│
├── Systems
│   ├── PowerSystem
│   ├── CommunicationsSystem
│   ├── LifeSupportSystem
│   └── AirlockSystem
│
├── Surveillance
│   ├── SecurityCamera
│   └── CameraMonitor
│
├── Audio
│   ├── AmbientAudio
│   ├── Footsteps
│   └── Radio
│
└── Events
└── HorrorEventManager

This is a conceptual architecture, not a requirement to implement every system immediately.

---

# 22. Important Development Constraint

Do not build the entire satellite before the first vertical slice works.

The first goal is NOT:

"Create a complete horror game."

The first goal is:

"Create a small playable section that proves the game's core interaction and horror mechanics."

The most important proof-of-concept is:

Routine maintenance
→ investigation
→ surveillance
→ contradictory information
→ unexplained event
→ unknown transmission

If this sequence is compelling, expand the game.

---

# 23. Claude Code Development Philosophy

Claude Code should:

1. Inspect the existing project before modifying it.
2. Explain major architectural decisions before implementing them.
3. Make small, testable changes.
4. Avoid unnecessary dependencies.
5. Keep systems modular.
6. Avoid implementing future systems prematurely.
7. Test each milestone before moving forward.
8. Keep the project runnable after every meaningful change.
9. Document important architectural decisions.
10. Prefer simple solutions over elaborate systems when both satisfy the design.

Do not generate placeholder systems that pretend to work.

If a system is not implemented yet, keep it explicitly out of scope rather than creating a fake implementation.

---

# 24. Current Development Target

The immediate target is:

M0 → M1 → M2

Build:

* a clean Godot project
* a small 3D satellite control room
* first-person camera
* mouse look
* predefined movement nodes
* smooth node-to-node walking
* multiple movement steps through a corridor
* basic interaction detection

Do NOT implement the horror sequence yet.

Do NOT build the full satellite yet.

Do NOT implement the complete camera system yet.

First establish the physical foundation of the game.
