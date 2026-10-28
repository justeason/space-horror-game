extends Node3D
## The electrical repair's physical equipment, rendered into its own
## isolated 3D world (this node is the content root of a SubViewport
## with own_world_3d = true, embedded via a SubViewportContainer in
## scripts/ui/electrical_repair_view.gd) so the player can click
## directly on wires, screws, and the breaker instead of pressing
## numbered keys. This node owns ONLY presentation + raw input
## detection (hover/click raycasting within its own physics world,
## animating what it's told to animate) -- it never calls into
## electrical_panel.gd directly and holds no procedure state of its
## own; electrical_repair_view.gd listens to this node's signals, calls
## the panel's authoritative methods, and tells this node what to
## animate/sync in response. Same "view/presentation never duplicates
## authoritative state" split as every other object/view pair in this
## project.
##
## Raycast picking here is a smaller-scale copy of
## scripts/player/interaction_controller.gd's own technique (a
## PhysicsRayQueryParameters3D against this viewport's own
## direct_space_state), scoped to a cursor position instead of a
## fixed-forward reticle, because a SubViewportContainer forwards mouse
## input (and local mouse coordinates) into its child SubViewport
## automatically -- this is the thing workstation_screen.gd's own class
## doc comment identified as "a much larger problem" not worth solving
## for a dedicated-key interface; it is solved here because this
## milestone specifically asked for direct manipulation.

signal wire_clicked(role: StringName)
signal replacement_clicked()
signal breaker_clicked()
signal screw_clicked(index: int)

## Round 13 Workstream B: this SAME scene is now instantiated TWICE --
## once inside the focused view's SubViewport (interactive, its own
## camera/lights/isolated physics world, exactly as every prior round),
## and once as a plain child of the WORLD's EngineeringCabinet1 (a
## non-interactive, read-only visual twin sitting inside the middle
## compartment's real opening), so the player sees the SAME wire
## routes/colors/terminal positions/breaker/damage-and-replacement
## appearance in both places, driven from the SAME
## electrical_panel.gd calls (see that script's `_sync_world_diorama()`)
## instead of two independently hand-authored geometries that could
## drift out of sync. `world_display_mode` is the one flag that
## distinguishes the two instantiations: when true, this instance frees
## its own Camera3D/lights (the real world already provides both) and
## strips every StaticBody3D's collision layer/mask to 0 so none of its
## wire/screw/breaker hitboxes can ever be hit by the player's own
## movement or interaction raycast -- this instance never calls
## set_active(true) either, so _process()/_unhandled_input() are
## permanently inert here regardless. The interactive (focused-view)
## instance is entirely unaffected -- this flag defaults false.
@export var world_display_mode: bool = false

const WIRE_DISCONNECT_PITCH_DEGREES: float = -58.0
## Round 14 Priority 2: the staged replacement wire, waiting to be
## installed, previously hung at the exact same angle as a torn-loose
## DAMAGED wire -- per playtest, this read as "an extra wire sitting
## off to the side" rather than an intentionally-stored spare part. A
## shallower resting angle (closer to vertical, like a part still
## clipped in its holder) visually distinguishes "fresh spare, ready to
## install" from "ripped out and dangling."
const REPLACEMENT_STAGED_PITCH_DEGREES: float = -20.0
## Round 17 Priority 1: the FIXED TOTAL set of wires/terminals this
## panel physically has -- 5, always present, always the same
## believable system (the ship did not change; only WHICH subset is
## relevant to a given repair varies -- see
## electrical_panel.gd's own _REPAIR_CONFIGS). Expanded from the
## original 3 (supply/return/service) by adding two auxiliary roles,
## backup and ground, so a repair config can involve a genuinely
## different SUBSET of this one fixed panel instead of only ever
## varying which of the same three wires is at fault.
## Round 18 Priority 2: expanded from 5 to 10 -- see
## electrical_panel.gd's own WIRE_ROLES doc comment for the full
## rationale. The first 5 are the original, hand-authored ROW A
## (terminal y=-0.22); the last 5 (_ROW_B_ROLES) are a NEW, physically
## lower second row (terminal y=-0.48) built PROCEDURALLY in _ready()
## (see _build_row_b()) rather than hand-authored in the .tscn --
## hand-writing ~10 nodes per wire/terminal x5 wires in a text scene
## file is impractical to do reliably; building them from the same
## data this script already uses for ROW A (_WIRE_CURVE_POINTS,
## _HEALTHY_WIRE_COLOR, ...) guarantees the two rows share one
## construction path and can't drift apart from authoring mistakes.
const ROLES: Array[StringName] = [
	&"supply", &"return", &"service", &"backup", &"ground",
	&"telemetry", &"coolant", &"sensor_feed", &"auxiliary", &"relay",
]
const _ROW_B_ROLES: Array[StringName] = [&"telemetry", &"coolant", &"sensor_feed", &"auxiliary", &"relay"]
## Row B terminal x positions mirror row A's exactly (same -1.0..1.0
## spread, same 0.5 spacing -- the exact spacing test_wire_geometry.gd
## already proves gives non-overlapping click hitboxes for row A, reused
## here rather than re-deriving a new spacing).
const _ROW_B_X: Dictionary = {
	&"telemetry": -1.0, &"coolant": -0.5, &"sensor_feed": 0.0, &"auxiliary": 0.5, &"relay": 1.0,
}
## Row B sits physically BELOW row A on the same panel (a believable
## two-row terminal strip, not a wider single row) -- wire roots start
## lower (0.16 vs row A's 0.42) and their curves land on a
## correspondingly lower terminal row (world y -0.48 vs row A's -0.22,
## both comfortably inside InsetPanel's existing y span -- no scene
## resizing needed, confirmed by render).
const _ROW_B_WIRE_ROOT_Y: float = 0.16
const _ROW_B_TERMINAL_Y: float = -0.48

## Round 11 Workstream B3 introduced a curved, multi-segment cable
## path (a quadratic Bezier sampled into _WIRE_SEGMENT_COUNT straight
## CSGCylinder3D chords -- "segmented geometry... multiple control
## points to produce believable bends", the explicitly-permitted low-
## overhead alternative to a true spline mesh). ROUND 12 FIX: that
## first attempt bowed each wire OUT from its own anchor and back to
## the SAME anchor x at the bottom (a symmetric "out and return"
## curve) -- which, confirmed by an actual rendered screenshot (not
## merely inferred from code), reads as a confusing hook/loop rather
## than a cable, especially for supply's large bow. A loop is the
## wrong shape for "three wires cross through a central space": real
## wire-harness crossing looks like a FAN, each wire traveling
## monotonically from one position to a DIFFERENT one, not bowing out
## and snapping back.
##
## Each wire's local path is now P0 (a top ENTRY point, offset from
## this node's own anchor) -> a sag control point -> P2 (the fixed
## local (0,-0.64,0) terminal endpoint, unchanged -- still exactly
## aligned with Terminals/<role>/Lug). Supply's entry point is offset
## toward service's side (and service's is offset toward supply's),
## so the two outer wires genuinely swap sides end to end -- confirmed
## monotonic in both X and Y (no loop) and confirmed to genuinely
## overlap in world X with return staying centered at a middle depth.
## Supply stays the FRONTMOST layer at the crossing (disconnected
## FIRST) and service the BACKMOST (disconnected LAST), preserving the
## same "topmost removed first" depth logic as before.
const _WIRE_SEGMENT_COUNT: int = 6
## Local (relative to each wire's own anchor) entry point, sag control
## point, in that dictionary's [entry, control] order; P2 is always
## the fixed Vector3(0, -0.64, 0) terminal endpoint.
##
## ROUND 12 FIX: depth layering is expressed entirely as a FORWARD
## (toward the camera, +Z) push, never backward -- confirmed via an
## actual rendered screenshot that pushing service's path BEHIND its
## own anchor depth clipped most of it against InsetPanel/Backdrop
## (both solid, opaque panels mounted only ~0.015m behind the wire
## anchors -- there is almost no room to recede before clipping).
## Supply (frontmost, disconnected first) pushes forward the most;
## service (disconnected last) stays at its own anchor's baseline
## depth (the smallest forward push of the three, i.e. relatively
## "backmost" without ever actually going negative) -- still a strict,
## unambiguous front-to-back order, with zero clipping risk since
## nothing ever moves behind where it already safely sits.
const _WIRE_CURVE_POINTS: Dictionary = {
	&"supply": [Vector3(1.0, 0.05, 0.22), Vector3(0.55, -0.45, 0.26)],
	&"return": [Vector3(0.12, 0.05, 0.08), Vector3(0.1, -0.42, 0.08)],
	&"service": [Vector3(-1.0, 0.05, 0.0), Vector3(-0.55, -0.45, 0.0)],
	# Round 17 Priority 1: backup/ground are the two NEW auxiliary wires
	# -- deliberately simple, small, non-crossing leans (matching
	# return's own low-drama style) rather than attempting a second
	# dramatic fan-cross: they sit outside the original 3's crossing
	# span entirely (backup/ground anchors are at local x 0.5/1.0 in
	# the now-widened panel, the original cross only spans roughly
	# -1.0..0.0), so there is no risk of the two systems visually
	# interfering.
	&"backup": [Vector3(0.08, 0.05, 0.06), Vector3(0.06, -0.42, 0.06)],
	&"ground": [Vector3(-0.08, 0.05, 0.06), Vector3(-0.06, -0.42, 0.06)],
	# Round 18 Priority 2: row B reuses row A's exact relative curve
	# shapes at the matching x slot (telemetry<->supply, coolant<->
	# return, sensor_feed<->service, auxiliary<->backup, relay<->ground)
	# -- since these are LOCAL offsets from each wire's own root, and
	# row B's roots sit at their own lower y (_ROW_B_WIRE_ROOT_Y), this
	# reproduces the exact same proven crossing geometry (telemetry
	# crosses sensor_feed the same way supply crosses service -- see
	# test_wire_geometry.gd) one row down, not a new, unverified shape.
	&"telemetry": [Vector3(1.0, 0.05, 0.22), Vector3(0.55, -0.45, 0.26)],
	&"coolant": [Vector3(0.12, 0.05, 0.08), Vector3(0.1, -0.42, 0.08)],
	&"sensor_feed": [Vector3(-1.0, 0.05, 0.0), Vector3(-0.55, -0.45, 0.0)],
	&"auxiliary": [Vector3(0.08, 0.05, 0.06), Vector3(0.06, -0.42, 0.06)],
	&"relay": [Vector3(-0.08, 0.05, 0.06), Vector3(-0.06, -0.42, 0.06)],
}

## Round 16/17: which pre-built ReplacementWire visual-group variant
## corresponds to each role this diorama can be told is at fault -- see
## _ready()'s own doc comment. Only roles electrical_panel.gd's own
## _REPAIR_CONFIGS can actually select ("service", "return", "backup")
## have a variant; "supply"/"ground" intentionally have none yet (no
## authored config currently puts the fault there -- see that script's
## own class doc comment on why only a few validated configurations are
## offered rather than every combinatorial possibility).
const _FAULT_VISUAL_GROUPS: Dictionary = {
	&"service": "VisualGroup_service",
	&"return": "VisualGroup_return",
	&"backup": "VisualGroup_backup",
	&"telemetry": "VisualGroup_telemetry",
	&"relay": "VisualGroup_relay",
}
## A role's own wire mesh swaps between its normal HEALTHY color and a
## duller, rougher DAMAGED look depending on whether THIS attempt's
## config says it is the one at fault -- the same healthy/damaged pair
## "service" already always had (Mat_wire_service_healthy/_damaged), now
## generalized so any configurable fault role gets the same visual
## treatment instead of only ever being available for service.
const _HEALTHY_WIRE_COLOR: Dictionary = {
	&"supply": Color(0.62, 0.12, 0.1, 1),
	&"return": Color(0.14, 0.26, 0.6, 1),
	&"service": Color(0.68, 0.56, 0.08, 1),
	&"backup": Color(0.75, 0.4, 0.08, 1),
	&"ground": Color(0.15, 0.55, 0.22, 1),
	&"telemetry": Color(0.5, 0.15, 0.65, 1),
	&"coolant": Color(0.1, 0.55, 0.6, 1),
	&"sensor_feed": Color(0.75, 0.75, 0.78, 1),
	&"auxiliary": Color(0.7, 0.15, 0.45, 1),
	&"relay": Color(0.45, 0.3, 0.15, 1),
}
const _DAMAGED_WIRE_COLOR: Dictionary = {
	&"return": Color(0.09, 0.16, 0.36, 1),
	&"service": Color(0.42, 0.36, 0.08, 1),
	&"backup": Color(0.46, 0.26, 0.07, 1),
	&"ground": Color(0.1, 0.34, 0.15, 1),
	&"telemetry": Color(0.3, 0.09, 0.4, 1),
	&"coolant": Color(0.06, 0.34, 0.37, 1),
	&"sensor_feed": Color(0.45, 0.45, 0.47, 1),
	&"auxiliary": Color(0.42, 0.09, 0.27, 1),
	&"relay": Color(0.27, 0.18, 0.09, 1),
}
const _HEALTHY_ROUGHNESS: float = 0.5
const _DAMAGED_ROUGHNESS: float = 0.75

@onready var _camera: Camera3D = $Camera3D
## Round 18 Priority 2: no longer a literal @onready dict of $-paths --
## row A's 5 roles still resolve from scene-authored nodes exactly as
## before, but row B's 5 don't exist in the .tscn at all (see
## _build_row_b()), so this is populated once, for every role uniformly,
## at the very start of _ready() instead.
var _wire_nodes := {}
var _wire_colliders := {}
var _terminal_indicators := {}
@onready var _replacement_wire: Node3D = $ReplacementWire
@onready var _replacement_collider: Node3D = $ReplacementWire/Collision
@onready var _breaker_hinge: Node3D = $Breaker/Hinge
@onready var _breaker_lever: Node3D = $Breaker/Hinge/LeverArm
@onready var _breaker_collider: Node3D = $Breaker/Hinge/Collision
@onready var _breaker_status_light: CSGBox3D = $Breaker/StatusLight
@onready var _screw_nodes: Array = [$Screws/Screw1, $Screws/Screw2, $Screws/Screw3, $Screws/Screw4]
@onready var _screw_colliders: Array = [
	$Screws/Screw1/Collision, $Screws/Screw2/Collision,
	$Screws/Screw3/Collision, $Screws/Screw4/Collision,
]

const LIGHT_ON_COLOR := Color(0.2, 0.9, 0.3, 1)
const LIGHT_OFF_COLOR := Color(0.5, 0.1, 0.05, 1)

var _active: bool = false
var _allowed: Dictionary = {} # action key (StringName) -> true
var _collider_action: Dictionary = {} # Node -> action key
var _hovered_action: StringName = &""
var _hover_base_energy: Dictionary = {} # action key -> original emission_energy_multiplier
var _pulse_time: float = 0.0
var _pulsing_action: StringName = &""

var _wire_tweens: Dictionary = {}
var _breaker_tween: Tween
var _screw_tweens: Array = [null, null, null, null]
var _replacement_tween: Tween
## Round 16 Priority 3: which role THIS repair instance's config says is
## at fault -- defaults to &"service" (this diorama's only fault role
## before this round, so a fresh instance that never receives an
## explicit set_fault_role() call -- e.g. a bare test scene -- behaves
## exactly as it always did).
var _fault_role: StringName = &"service"
var _screw_base_z: Array = []


func _ready() -> void:
	# Round 18 Priority 2: populate _wire_nodes/_wire_colliders/
	# _terminal_indicators for EVERY role before anything below reads
	# them -- row A from the scene-authored nodes (unchanged), row B
	# built procedurally right here (see _build_row_b()/
	# _build_replacement_variant()), so every loop that follows (which
	# already iterates ROLES/_FAULT_VISUAL_GROUPS generically) picks up
	# all 10 roles uniformly without needing to know which ones are
	# scene-authored vs procedural.
	for role in [&"supply", &"return", &"service", &"backup", &"ground"]:
		var root: Node3D = get_node("Wires/%s" % role.capitalize())
		_wire_nodes[role] = root
		_wire_colliders[role] = root.get_node("Collision")
		_terminal_indicators[role] = get_node("Terminals/%s/Indicator" % role.capitalize())
	_build_row_b()
	_build_replacement_variant(&"telemetry")
	_build_replacement_variant(&"relay")

	for role in ROLES:
		_collider_action[_wire_colliders[role]] = StringName("wire:%s" % role)
	_collider_action[_replacement_collider] = &"replacement"
	_collider_action[_breaker_collider] = &"breaker"
	for i in _screw_colliders.size():
		_collider_action[_screw_colliders[i]] = StringName("screw:%d" % i)
	for screw_node in _screw_nodes:
		_screw_base_z.append(screw_node.position.z)
	for role in ROLES:
		_build_wire_curve(_wire_nodes[role].get_node("VisualGroup"), _WIRE_CURVE_POINTS[role])
	# Round 16 Priority 3: the replacement wire is pre-built with ONE
	# curve variant per role this diorama can ever be told is at fault
	# (see _FAULT_VISUAL_GROUPS/set_fault_role() below) -- built once,
	# here, for every variant, rather than rebuilt at runtime once the
	# fault is actually chosen. Each variant uses THAT role's own real
	# curve shape (_WIRE_CURVE_POINTS[role]), not a single hardcoded
	# "service" shape reused regardless of which wire is actually being
	# replaced -- reusing "service"'s long diagonal sweep for, say, a
	# replaced RETURN wire would have the new wire visibly emerge from
	# entirely the wrong side of the assembly.
	for role in _FAULT_VISUAL_GROUPS:
		_build_wire_curve(_replacement_wire.get_node(_FAULT_VISUAL_GROUPS[role]), _WIRE_CURVE_POINTS[role])
	# The damage scorch mark sits ON its wire's own curved path (around
	# 70% of the way down) instead of floating over where the old
	# straight centerline used to be -- one scorch mark pre-positioned
	# per role this diorama can be told is at fault (see
	# set_fault_role() below for which one is actually shown).
	for role in _FAULT_VISUAL_GROUPS:
		var scorch: Node3D = _wire_nodes[role].get_node_or_null("VisualGroup/DamageScorch")
		if scorch == null:
			continue
		var pts: Array = _WIRE_CURVE_POINTS[role]
		scorch.position = _bezier_point(pts[0], pts[1], Vector3(0, -0.64, 0), 0.75)
	_apply_fault_role_visuals()
	if world_display_mode:
		_configure_world_display_mode()


## Round 18 Priority 2: builds all 5 of row B's wire+terminal node
## trees from scratch, mirroring the exact node shape row A's
## scene-authored wires already have (VisualGroup/Run+Cap+DamageScorch,
## a sibling Collision/Shape StaticBody3D) so every OTHER function in
## this script (sync_full_state(), _build_wire_curve(),
## _apply_fault_role_visuals(), hover/pulse highlighting, ...) treats
## row B identically to row A without needing a single "is this a row B
## role" branch anywhere outside this one function. Reuses row A's own
## Cap/Backing/Lug/Socket/Screw materials by reference (those never vary
## per role) and builds new StandardMaterial3D instances only where a
## role genuinely needs its own (the wire Run's color, and the
## terminal's Indicator light -- see the Round 15 "shared indicator
## material" bug class this project already fixed once for row A).
func _build_row_b() -> void:
	var ref_wire: Node3D = _wire_nodes[&"return"]
	var cap_material: Material = ref_wire.get_node("VisualGroup/Cap").material
	var scorch_material: Material = ref_wire.get_node("VisualGroup/DamageScorch").material
	var shared_wire_shape: Shape3D = ref_wire.get_node("Collision/Shape").shape

	var ref_terminal: Node3D = get_node("Terminals/Return")
	var backing_material: Material = ref_terminal.get_node("Backing").material
	var lug_material: Material = ref_terminal.get_node("Lug").material
	var socket_material: Material = ref_terminal.get_node("Socket").material
	var screw_material: Material = ref_terminal.get_node("Screw1").material
	var bezel_material: Material = ref_terminal.get_node("IndicatorBezel").material

	for role in _ROW_B_ROLES:
		var x: float = _ROW_B_X[role]

		var wire_root := Node3D.new()
		wire_root.name = "Wire_%s" % role
		wire_root.position = Vector3(x, _ROW_B_WIRE_ROOT_Y, -0.26)
		get_node("Wires").add_child(wire_root)

		var visual_group := Node3D.new()
		visual_group.name = "VisualGroup"
		wire_root.add_child(visual_group)

		var run := CSGCylinder3D.new()
		run.name = "Run"
		run.radius = 0.028
		run.height = 0.1
		run.sides = 10
		var wire_mat := StandardMaterial3D.new()
		wire_mat.albedo_color = _HEALTHY_WIRE_COLOR[role]
		wire_mat.roughness = _HEALTHY_ROUGHNESS
		run.material = wire_mat
		visual_group.add_child(run)

		var cap := CSGBox3D.new()
		cap.name = "Cap"
		cap.position = Vector3(0, -0.64, 0)
		cap.size = Vector3(0.07, 0.06, 0.06)
		cap.material = cap_material
		visual_group.add_child(cap)

		var scorch := CSGBox3D.new()
		scorch.name = "DamageScorch"
		scorch.visible = false
		scorch.size = Vector3(0.06, 0.1, 0.06)
		scorch.material = scorch_material
		visual_group.add_child(scorch)

		var collision := StaticBody3D.new()
		collision.name = "Collision"
		collision.position = Vector3(0, -0.61, 0)
		wire_root.add_child(collision)
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = shared_wire_shape
		collision.add_child(shape)

		_wire_nodes[role] = wire_root
		_wire_colliders[role] = collision

		var terminal := Node3D.new()
		terminal.name = "Terminal_%s" % role
		terminal.position = Vector3(x, _ROW_B_TERMINAL_Y, -0.26)
		get_node("Terminals").add_child(terminal)

		var backing := CSGBox3D.new()
		backing.name = "Backing"
		backing.position = Vector3(0, 0, -0.03)
		backing.size = Vector3(0.22, 0.16, 0.05)
		backing.material = backing_material
		terminal.add_child(backing)

		var lug := CSGBox3D.new()
		lug.name = "Lug"
		lug.size = Vector3(0.14, 0.08, 0.1)
		lug.material = lug_material
		terminal.add_child(lug)

		var socket := CSGCylinder3D.new()
		socket.name = "Socket"
		socket.position = Vector3(0, 0, 0.048)
		socket.rotation_degrees = Vector3(90, 0, 0)
		socket.radius = 0.032
		socket.height = 0.02
		socket.sides = 12
		socket.material = socket_material
		terminal.add_child(socket)

		var screw1 := CSGCylinder3D.new()
		screw1.name = "Screw1"
		screw1.position = Vector3(-0.08, 0.05, 0.051)
		screw1.rotation_degrees = Vector3(90, 0, 0)
		screw1.radius = 0.012
		screw1.height = 0.01
		screw1.sides = 8
		screw1.material = screw_material
		terminal.add_child(screw1)

		var screw2 := CSGCylinder3D.new()
		screw2.name = "Screw2"
		screw2.position = Vector3(0.08, -0.05, 0.051)
		screw2.rotation_degrees = Vector3(90, 0, 0)
		screw2.radius = 0.012
		screw2.height = 0.01
		screw2.sides = 8
		screw2.material = screw_material
		terminal.add_child(screw2)

		var bezel := CSGBox3D.new()
		bezel.name = "IndicatorBezel"
		bezel.position = Vector3(0, 0.09, 0.025)
		bezel.size = Vector3(0.05, 0.05, 0.015)
		bezel.material = bezel_material
		terminal.add_child(bezel)

		var indicator := CSGBox3D.new()
		indicator.name = "Indicator"
		indicator.position = Vector3(0, 0.09, 0.034)
		indicator.size = Vector3(0.03, 0.03, 0.012)
		var indicator_mat := StandardMaterial3D.new()
		indicator_mat.emission_enabled = true
		indicator_mat.albedo_color = LIGHT_ON_COLOR
		indicator_mat.emission = LIGHT_ON_COLOR
		indicator.material = indicator_mat
		terminal.add_child(indicator)

		_terminal_indicators[role] = indicator


## Builds one more ReplacementWire visual-group variant for a row B
## fault role (see _FAULT_VISUAL_GROUPS), the same procedural
## equivalent of the 3 hand-authored variants (VisualGroup_service/
## _return/_backup) already in the .tscn -- same VisualGroup/Run+Cap
## shape _build_wire_curve() expects, built here instead of by hand for
## the same "don't hand-write dozens of near-identical nodes" reason
## _build_row_b() exists.
func _build_replacement_variant(role: StringName) -> void:
	var cap_material: Material = _replacement_wire.get_node("VisualGroup_service/Cap").material

	var group := Node3D.new()
	group.name = _FAULT_VISUAL_GROUPS[role]
	_replacement_wire.add_child(group)

	var run := CSGCylinder3D.new()
	run.name = "Run"
	run.radius = 0.028
	run.height = 0.1
	run.sides = 10
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _HEALTHY_WIRE_COLOR[role]
	mat.roughness = _HEALTHY_ROUGHNESS
	run.material = mat
	group.add_child(run)

	var cap := CSGBox3D.new()
	cap.name = "Cap"
	cap.position = Vector3(0, -0.64, 0)
	cap.size = Vector3(0.07, 0.06, 0.06)
	cap.material = cap_material
	group.add_child(cap)


## See `world_display_mode`'s own doc comment above. Frees this
## instance's own camera/lights (the real world already provides both
## for a child of EngineeringCabinet1) and strips every StaticBody3D's
## collision layer/mask to 0 (not merely `disabled = true` on the
## shapes -- belt-and-suspenders, since a StaticBody3D with a nonzero
## layer/mask could still in principle be swept by some other physics
## query even with its own shapes disabled) so none of this read-only
## visual twin's wire/screw/breaker hitboxes can ever be hit by the
## player's own movement or interaction raycast.
func _configure_world_display_mode() -> void:
	var cam: Camera3D = get_node_or_null("Camera3D")
	if cam != null:
		cam.queue_free()
	for light_name in ["KeyLight", "FillLight"]:
		var light: Node = get_node_or_null(light_name)
		if light != null:
			light.queue_free()
	# The flat photo-backdrop/inset panel exist to fill the focused
	# view's own frame behind the equipment -- inside the cabinet, the
	# cabinet's own housing already serves that purpose, and the
	# backdrop's full width is wider than the compartment opening.
	for backdrop_name in ["Backdrop", "InsetPanel"]:
		var node: Node = get_node_or_null(backdrop_name)
		if node != null:
			node.visible = false
	# Round 18 Priority 2 fix: this used to hardcode only the original 3
	# roles (supply/return/service) -- backup/ground (added Round 17) and
	# every Round 18 role were silently left on the default collision
	# layer/mask in the world-display (non-interactive) twin, a real bug
	# (those colliders could in principle be hit by something other than
	# this diorama's own raycast query while sitting inside the cabinet)
	# that simply never surfaced because nothing happened to probe it.
	# Looping over ROLES generically means no future role addition can
	# reintroduce this gap.
	var bodies: Array = [_replacement_collider, _breaker_collider] + _screw_colliders
	for role in ROLES:
		bodies.append(_wire_colliders[role])
	for body in bodies:
		body.collision_layer = 0
		body.collision_mask = 0


## Quadratic Bezier through p0 (start), c (control point), p2 (end).
func _bezier_point(p0: Vector3, c: Vector3, p2: Vector3, t: float) -> Vector3:
	var mt: float = 1.0 - t
	return p0 * (mt * mt) + c * (2.0 * mt * t) + p2 * (t * t)


## A right-handed orthonormal basis whose Y axis is `dir` -- used to
## orient each straight cylinder segment along its own chord of the
## curve. Picks whichever of FORWARD/RIGHT is less parallel to `dir`
## as a stable reference axis, so this never degenerates for a
## near-vertical or near-horizontal segment.
func _basis_with_y(dir: Vector3) -> Basis:
	var y_axis: Vector3 = dir.normalized()
	var reference: Vector3 = Vector3.FORWARD if absf(y_axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x_axis: Vector3 = reference.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


## Builds the curved, multi-segment cable path for one wire node (or
## the replacement wire): samples a quadratic Bezier from `entry_and_control[0]`
## (the wire's top ENTRY point, offset from this node's own anchor --
## see _WIRE_CURVE_POINTS's own doc comment for why this is no longer
## just this node's origin) through `entry_and_control[1]` (a sag
## control point) to the fixed lug endpoint at local (0,-0.64,0), then
## lays out _WIRE_SEGMENT_COUNT straight CSGCylinder3D segments along
## the resulting chords, parented under `wire_node`'s own "VisualGroup"
## child (see that node's own doc comment in _tween_wire_pitch() for
## why visuals and the click collider are no longer siblings animated
## together). The existing "VisualGroup/Run" child (authored in the
## .tscn purely as a radius/sides/material TEMPLATE) becomes segment 0
## in place; segments 1..N are new siblings created here, sharing the
## exact same material resource so the existing hover/pulse-highlight
## code (which only ever looks up get_node("VisualGroup/Run")) still
## lights the WHOLE curved wire, not just its first chord.
func _build_wire_curve(visual_group: Node3D, entry_and_control: Array) -> void:
	var template: CSGCylinder3D = visual_group.get_node("Run")
	var radius: float = template.radius
	var sides: int = template.sides
	var material: Material = template.material
	var p0: Vector3 = entry_and_control[0]
	var control: Vector3 = entry_and_control[1]
	var p2 := Vector3(0, -0.64, 0)
	var points: Array = []
	for i in (_WIRE_SEGMENT_COUNT + 1):
		points.append(_bezier_point(p0, control, p2, float(i) / float(_WIRE_SEGMENT_COUNT)))
	for i in _WIRE_SEGMENT_COUNT:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg: CSGCylinder3D
		if i == 0:
			seg = template
		else:
			seg = CSGCylinder3D.new()
			seg.name = "Seg%d" % i
			seg.sides = sides
			seg.material = material
			visual_group.add_child(seg)
		seg.radius = radius
		seg.height = (b - a).length()
		seg.transform = Transform3D(_basis_with_y(b - a), (a + b) * 0.5)


func set_active(value: bool) -> void:
	_active = value
	if not value:
		_clear_hover()
		_pulsing_action = &""


## Round 16 Priority 3: tells this diorama which role THIS repair
## instance's config says is at fault -- called once (idempotently) by
## electrical_repair_view.gd/electrical_panel.gd's own sync calls,
## every time, but only ever actually CHANGES anything the first time a
## non-default role is reported (a locked-for-the-attempt value, same
## "preserve the chosen configuration for the whole attempt" contract
## electrical_panel.gd's own _select_repair_config() enforces on the
## backend side).
func set_fault_role(role: StringName) -> void:
	if role == _fault_role:
		return
	_fault_role = role
	_apply_fault_role_visuals()


## Switches every role's wire mesh between its healthy and damaged look
## (only the fault role shows damaged) and which pre-built
## ReplacementWire visual-group variant is visible -- the one-time
## setup this diorama needs to correctly represent WHICHEVER wire this
## attempt's config says is actually broken, not always "service".
func _apply_fault_role_visuals() -> void:
	for role in _wire_nodes:
		var run: CSGCylinder3D = _wire_nodes[role].get_node("VisualGroup/Run")
		var mat: StandardMaterial3D = run.material
		var damaged: bool = role == _fault_role
		mat.albedo_color = _DAMAGED_WIRE_COLOR.get(role, mat.albedo_color) if damaged else _HEALTHY_WIRE_COLOR.get(role, mat.albedo_color)
		mat.roughness = _DAMAGED_ROUGHNESS if damaged else _HEALTHY_ROUGHNESS
		var scorch: Node3D = _wire_nodes[role].get_node_or_null("VisualGroup/DamageScorch")
		if scorch != null:
			scorch.visible = damaged
	for role in _FAULT_VISUAL_GROUPS:
		_replacement_wire.get_node(_FAULT_VISUAL_GROUPS[role]).visible = (role == _fault_role)


## The currently-active ReplacementWire visual-group variant (matching
## _fault_role) -- the one true "VisualGroup" every other function here
## used to assume was the only one.
func _active_replacement_visual_group() -> Node3D:
	return _replacement_wire.get_node(_FAULT_VISUAL_GROUPS.get(_fault_role, "VisualGroup_service"))


## `actions` is an Array of action-key StringNames currently clickable
## (e.g. [&"wire:supply", &"breaker"]) -- the one place per-stage
## interactivity is decided, read fresh from electrical_repair_view.gd
## every refresh so this never drifts from the panel's real stage.
func set_allowed(actions: Array) -> void:
	_allowed.clear()
	for a in actions:
		_allowed[a] = true
	if _hovered_action != &"" and not _allowed.has(_hovered_action):
		_clear_hover()


## Pulses a gentle glow on the given wire action (e.g. &"wire:supply")
## to show the next valid target without a paragraph of hint text --
## pass &"" to stop pulsing (e.g. on HARD difficulty, or once hints
## should hide).
func set_pulsing_hint(action: StringName) -> void:
	_pulsing_action = action
	_pulse_time = 0.0


func _process(delta: float) -> void:
	if not _active:
		return
	_update_hover()
	if _pulsing_action != &"":
		_pulse_time += delta
		_apply_pulse(_pulsing_action, _pulse_time)


## Returns the viewport-local screen position that would land exactly
## on `world_pos` as currently framed by this diorama's camera -- the
## real inverse of _raycast_action()'s own mouse->ray mapping, exposed
## so tests can compute "click exactly on this collider's position"
## without needing to drive Godot's real OS-level mouse/viewport input
## pipeline (confirmed unreliable to simulate in this headless
## environment -- SubViewport.push_input() does not reproduce the
## coordinate mapping a real SubViewportContainer delivers here).
func screen_position_for(world_pos: Vector3) -> Vector2:
	return _camera.unproject_position(world_pos)


## Round 13 Workstream A fix: resolves the click target FRESH, at the
## event's own position, instead of dispatching through `_hovered_action`
## (previously a once-per-`_process()`-tick CACHE). This closes a real
## one-frame staleness window: `_hovered_action` is only recomputed in
## `_process()`, which runs once per rendered frame, while mouse MOTION
## events are delivered (and silently ignored by this function -- only
## InputEventMouseButton is handled) through the separate
## `_unhandled_input` event queue. A fast, deliberate mouse-move-then-
## click landing within the same frame could therefore dispatch using
## WHATEVER was hovered a frame earlier (e.g. the wire just reconnected)
## instead of what is actually under the cursor at the moment of the
## click -- confirmed directly via a diagnostic reproducing the
## reported "reconnect Yellow, then Blue is rejected" sequence.
## Resolving fresh here removes that entire window; `_hovered_action`/
## `_update_hover()` remain exactly as before for the (purely cosmetic,
## one-frame-lag-tolerant) hover-glow highlight only.
func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var action: StringName = _raycast_action(event.position)
		if action != &"":
			_dispatch_click(action)
			get_viewport().set_input_as_handled()


func _dispatch_click(action: StringName) -> void:
	if action.begins_with("wire:"):
		wire_clicked.emit(StringName(action.substr(5)))
	elif action == &"replacement":
		replacement_clicked.emit()
	elif action == &"breaker":
		breaker_clicked.emit()
	elif action.begins_with("screw:"):
		screw_clicked.emit(int(action.substr(6)))


func _update_hover() -> void:
	var action: StringName = _raycast_action()
	if action == _hovered_action:
		return
	if _hovered_action != &"":
		_set_highlight(_hovered_action, false)
	_hovered_action = action
	if _hovered_action != &"":
		_set_highlight(_hovered_action, true)


func _clear_hover() -> void:
	if _hovered_action != &"":
		_set_highlight(_hovered_action, false)
	_hovered_action = &""


## `mouse_pos_override`: when non-null, used instead of the live
## viewport mouse position -- lets tests resolve "what would clicking
## exactly at this screen position hit" deterministically (see
## screen_position_for()'s own doc comment for why this is necessary
## in this environment). Real gameplay never passes an override; it
## always reads the actual forwarded mouse position.
func _raycast_action(mouse_pos_override = null) -> StringName:
	var mouse_pos: Vector2
	if mouse_pos_override != null:
		mouse_pos = mouse_pos_override
	else:
		var viewport := get_viewport()
		if viewport == null:
			return &""
		mouse_pos = viewport.get_mouse_position()
	var space_state := get_world_3d().direct_space_state
	var origin: Vector3 = _camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = _camera.project_ray_normal(mouse_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 6.0)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return &""
	var collider = result.get("collider")
	if collider == null or not _collider_action.has(collider):
		return &""
	var action: StringName = _collider_action[collider]
	if not _allowed.has(action):
		return &""
	return action


## Boosts emission on the visual mesh belonging to `action` while
## hovered -- a plain visual-only state (never mutates the authoritative
## base material tint), reverted exactly to the stored value on
## unhover/stage-change so repeated hovering can never drift the
## object's resting appearance.
func _set_highlight(action: StringName, on: bool) -> void:
	var mat: StandardMaterial3D = _material_for_action(action)
	if mat == null:
		return
	if on:
		if not _hover_base_energy.has(action):
			_hover_base_energy[action] = mat.emission_energy_multiplier if mat.emission_enabled else 0.0
		mat.emission_enabled = true
		mat.emission = mat.albedo_color.lightened(0.6)
		mat.emission_energy_multiplier = maxf(_hover_base_energy.get(action, 0.0), 0.5)
	else:
		var base: float = _hover_base_energy.get(action, 0.0)
		if base <= 0.0:
			mat.emission_enabled = false
		else:
			mat.emission_energy_multiplier = base


func _apply_pulse(action: StringName, t: float) -> void:
	var mat: StandardMaterial3D = _material_for_action(action)
	if mat == null:
		return
	if action == _hovered_action:
		return # hover highlight already takes precedence visually
	mat.emission_enabled = true
	mat.emission = mat.albedo_color.lightened(0.5)
	mat.emission_energy_multiplier = 0.35 + 0.3 * (0.5 + 0.5 * sin(t * 3.4))


func _material_for_action(action: StringName) -> StandardMaterial3D:
	if action.begins_with("wire:"):
		var role := StringName(action.substr(5))
		var run: CSGCylinder3D = _resolve_wire_node(role).get_node("VisualGroup/Run")
		return run.material
	if action == &"replacement":
		var run2: CSGCylinder3D = _active_replacement_visual_group().get_node("Run")
		return run2.material
	if action == &"breaker":
		return _breaker_lever.material
	if action.begins_with("screw:"):
		var idx := int(action.substr(6))
		var head: CSGCylinder3D = _screw_nodes[idx].get_node("Head")
		return head.material
	return null


# ============================================================
# Animation / sync entry points, called by electrical_repair_view.gd.
# Every one of these is presentation only -- the caller has already
# committed (or rejected) the real action via electrical_panel.gd
# before calling in here.
# ============================================================

func animate_wire_disconnect(role: StringName) -> void:
	_tween_wire_pitch(role, deg_to_rad(WIRE_DISCONNECT_PITCH_DEGREES), 0.35)
	_set_indicator(role, false)


func animate_wire_reconnect(role: StringName) -> void:
	_tween_wire_pitch(role, 0.0, 0.3)
	_set_indicator(role, true)


## Round 11 B1 fix: once the service wire has been replaced, the
## REPLACEMENT node is the one actually visible/parented in the
## assembly -- the original "Service" node stays permanently hidden
## from that point on (see sync_full_state()/begin_replace_sequence()).
## Any animation targeting role &"service" after that point (e.g. a
## later reconnect_wire(&"service") call, a separate action from
## installation) must act on the replacement, or it would silently
## tween an invisible node while the real, visible wire never moves.
func _resolve_wire_node(role: StringName) -> Node3D:
	if role == _fault_role and _replacement_wire.visible:
		return _replacement_wire
	return _wire_nodes[role]


## Resolves a wire-like node (either a normal entry in `_wire_nodes`, or
## `_replacement_wire` once installed) to its actual active "VisualGroup"
## child -- `_replacement_wire` no longer has just one fixed "VisualGroup"
## (see _FAULT_VISUAL_GROUPS's own doc comment), so every caller that
## used to do `resolved.get_node("VisualGroup")` directly now goes
## through here instead.
func _visual_group_for(resolved: Node3D) -> Node3D:
	if resolved == _replacement_wire:
		return _active_replacement_visual_group()
	return resolved.get_node("VisualGroup")


## ROUND 13 FIX (collider/visual split): tweens the wire's
## "VisualGroup" child, NOT the wire's own root node -- the root node
## also parents the "Collision" StaticBody3D (the click target).
## Previously these were siblings animated TOGETHER (Collision was a
## direct child of the same root whose rotation this tween drove), so
## while one wire's reconnect-settle animation was still in flight,
## its collider swept through real 3D space along with the visual mesh
## -- confirmed directly via a diagnostic that this sweep (radius
## ~0.64, up to 58 degrees) can transiently travel far enough laterally
## to intercept a ray aimed at a NEIGHBORING wire's terminal (the
## terminals sit ~0.55 apart, almost exactly the sweep's own lateral
## travel).
##
## ROUND 14 FIX (the SAME bug, still reproducing in real play): the
## Round 13 fix above, in isolation, created a NEW regression --
## freezing Collision at a single fixed transform FOREVER meant it
## only ever matched the CONNECTED pose. The instant a wire actually
## disconnects, its VISUAL swings away (toward WIRE_DISCONNECT_PITCH_DEGREES)
## while its collider stayed put -- confirmed directly via a
## diagnostic measuring a ~0.6m world-space / ~100px screen-space gap
## between a disconnected wire's visible endpoint and its own
## (unmoving) collider, with a click at the wire's ACTUAL VISIBLE
## position resolving to nothing at all. Every Round 13 regression test
## had computed its click targets from the COLLIDER's own position
## (`_wire_colliders[role].global_position`), which is exactly why none
## of them caught this: that is the one position guaranteed to always
## "work" by construction, and is NOT where a real player, aiming at
## the wire they can actually see on screen, would click once it is
## hanging loose.
##
## A first attempt just snapped Collision's own `rotation.x` to match
## VisualGroup's target angle, and it did NOT work: VisualGroup sits AT
## the wire root's origin, so rotating it sweeps its far-away Cap child
## (offset ~0.64 along -Y) through a wide arc PIVOTING AROUND THE ROOT.
## Collision, by contrast, is authored as a StaticBody3D that is ITSELF
## already offset ~0.61 along -Y from the root (see the .tscn) -- so
## rotating Collision's own `rotation.x` only reorients it in place
## around ITS OWN (already-displaced) origin; its `global_position`
## never moves at all. Confirmed directly via diagnostic: after this
## first attempt, `Collision.rotation.x` read back as numerically
## correct, yet a click at the wire's real visible position still
## resolved to nothing, because Collision's POSITION -- not just its
## rotation -- never tracked the swing. The real fix (see
## `_snap_collision_to_pose()` below) explicitly rotates Collision's
## rest offset AROUND THE WIRE ROOT'S ORIGIN, the same pivot
## VisualGroup's rotation uses, so Collision's position sweeps through
## (approximately) the same arc the visual Cap does, while still SNAPPING
## instantly (no tween, so it never sweeps through intermediate positions
## during the visual's smooth transition -- the Round 13 fix's actual
## goal) to a pose matching where the wire will be at rest.
func _tween_wire_pitch(role: StringName, target_rot_x: float, duration: float) -> void:
	var resolved: Node3D = _resolve_wire_node(role)
	var node: Node3D = _visual_group_for(resolved)
	_snap_collision_to_pose(resolved.get_node("Collision"), target_rot_x)
	if _wire_tweens.has(role) and _wire_tweens[role] != null and _wire_tweens[role].is_valid():
		_wire_tweens[role].kill()
	var tw := create_tween()
	tw.tween_property(node, "rotation:x", target_rot_x, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wire_tweens[role] = tw


## Collision's rest position, authored in electrical_repair_diorama.tscn
## as a fixed local offset from the wire root (NOT at the root's own
## origin, unlike VisualGroup) -- see _tween_wire_pitch()'s doc comment
## for why this matters.
const _COLLISION_REST_OFFSET: Vector3 = Vector3(0.0, -0.61, 0.0)


## Moves + reorients a wire's "Collision" StaticBody3D to match the
## given pitch, pivoting its rest offset around the WIRE ROOT's origin
## (the same pivot VisualGroup's rotation uses for the visual Cap) so
## the collider's actual world position tracks the visual instead of
## just matching its rotation angle in place. See _tween_wire_pitch()'s
## doc comment for the full reasoning.
func _snap_collision_to_pose(collision: Node3D, target_rot_x: float) -> void:
	collision.position = Basis(Vector3.RIGHT, target_rot_x) * _COLLISION_REST_OFFSET
	collision.rotation.x = target_rot_x


func _set_indicator(role: StringName, connected: bool) -> void:
	var indicator: CSGBox3D = _terminal_indicators[role]
	var mat: StandardMaterial3D = indicator.material
	mat.emission = LIGHT_ON_COLOR if connected else LIGHT_OFF_COLOR
	mat.albedo_color = Color(0.1, 0.3, 0.12, 1) if connected else Color(0.2, 0.08, 0.06, 1)


## The first click of the Replace stage: shrinks the damaged wire out
## of view, then shows the replacement wire staged at the same
## disconnected pose, ready to be clicked and installed -- one
## sequenced tween chain so electrical_repair_view.gd never has to
## manage the timing itself.
func begin_replace_sequence() -> void:
	var node: Node3D = _wire_nodes[_fault_role]
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(0.05, 0.05, 0.05), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		node.visible = false
		# Root stays at identity rotation (the fixed reference frame
		# Collision's position depends on) -- the disconnected-looking
		# staged pose is set on VisualGroup AND snapped onto Collision
		# together (Round 14 fix -- see _tween_wire_pitch()'s own doc
		# comment for why Collision must always match the CURRENT
		# discrete pose, not just sit at whatever it was last left at).
		var disconnected_rot := Vector3(deg_to_rad(REPLACEMENT_STAGED_PITCH_DEGREES), 0, 0)
		_active_replacement_visual_group().rotation = disconnected_rot
		_snap_collision_to_pose(_replacement_wire.get_node("Collision"), disconnected_rot.x)
		_replacement_wire.scale = Vector3.ONE
		_replacement_wire.visible = true
		_replacement_wire.position = node.position
	)


## The second click of Replace: swings the replacement into the
## terminal slot (mirrors animate_wire_reconnect's motion) -- from this
## point on the replacement node IS the service wire for the rest of
## the procedure (handled by electrical_repair_view.gd re-pointing its
## own role lookups, this node does not need to know that happened).
##
## ROUND 16 FIX (the recurring "extra Yellow click" report): this used
## to ALSO call `_set_indicator(&"service", true)` here, lighting the
## terminal indicator green at INSTALL time -- before
## electrical_panel.gd's reconnect_wire(&"service") has ever actually
## been called (that only happens on the player's NEXT, separate click
## on this same now-installed wire; see electrical_repair_view.gd's
## _on_replacement_clicked(), which only takes the install branch once,
## then the reconnect branch on every click after). A real-input
## diagnostic (disconnect Red/Blue/Yellow, replace, then click Blue
## next -- the natural thing to do once Yellow visually LOOKS
## connected) proved the backend was already logically correct the
## whole time (reconnect_wire(&"service") succeeds immediately on its
## first real call, and nothing needs clicking twice) -- the green
## indicator was simply lying about the wire's real logical state,
## causing the player to try Blue first, get rejected ("reconnect
## Yellow first"), and only then click Yellow again -- which reads
## exactly like an unwanted extra click, because it IS one extra click
## relative to what the (wrong) visual promised. The wire now still
## visually swings into its seated position on install (a reasonable
## "the new part is now physically in the slot" cue), but the
## indicator stays off until the player's actual next click calls
## reconnect_wire(&"service") and animate_wire_reconnect(&"service")
## lights it for real -- see that function and sync_full_state()'s own
## `is_service_connected = &"service" in reconnected` for the matching
## ground truth this now agrees with on every path (live play AND
## reopen-after-Escape).
func animate_install_replacement() -> void:
	_snap_collision_to_pose(_replacement_wire.get_node("Collision"), 0.0) # Round 14: snap immediately, same as _tween_wire_pitch()
	if _replacement_tween != null and _replacement_tween.is_valid():
		_replacement_tween.kill()
	_replacement_tween = create_tween()
	_replacement_tween.tween_property(_active_replacement_visual_group(), "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func animate_breaker(isolated: bool) -> void:
	if _breaker_tween != null and _breaker_tween.is_valid():
		_breaker_tween.kill()
	var target_rot: float = deg_to_rad(-35.0) if isolated else 0.0
	_breaker_tween = create_tween()
	_breaker_tween.tween_property(_breaker_hinge, "rotation:x", target_rot, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var mat: StandardMaterial3D = _breaker_status_light.material
	mat.emission = LIGHT_OFF_COLOR if isolated else LIGHT_ON_COLOR
	mat.albedo_color = Color(0.2, 0.08, 0.06, 1) if isolated else Color(0.1, 0.3, 0.12, 1)


func animate_screw(index: int, progress: int, turns_needed: int) -> void:
	if index < 0 or index >= _screw_nodes.size():
		return
	if _screw_tweens[index] != null and _screw_tweens[index].is_valid():
		_screw_tweens[index].kill()
	var node: Node3D = _screw_nodes[index]
	var t: float = float(progress) / float(maxi(turns_needed, 1))
	var target_z: float = _screw_base_z[index] + 0.1 * t # backs out of the panel as it's unscrewed
	var target_spin: float = deg_to_rad(360.0 * 1.5 * t)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "position:z", target_z, 0.2)
	tw.tween_property(node, "rotation:z", target_spin, 0.2)
	_screw_tweens[index] = tw


## Full, authoritative re-sync of every visual from scratch -- called
## whenever the procedure (re)opens, so "re-entering must render the
## equipment from its authoritative saved state" holds regardless of
## how much progress happened in a prior session. `fault_role` (Round 16
## Priority 3) is applied FIRST, before anything else below reads
## `_fault_role`/_wire_nodes[_fault_role]/etc., so every role-dependent
## branch that follows already sees this attempt's real configuration.
func sync_full_state(fault_role: StringName, disconnected: Array, reconnected: Array, service_replaced: bool, isolated: bool, screw_progress: Array, screw_turns_needed: int) -> void:
	set_fault_role(fault_role)
	for role in ROLES:
		if role == _fault_role and service_replaced:
			continue # handled by the replacement wire below instead
		var node: Node3D = _wire_nodes[role]
		node.visible = true
		node.scale = Vector3.ONE
		var is_connected: bool = (not (role in disconnected)) or role in reconnected
		# Round 14 fix: Collision must be snapped to match the SAME
		# target rotation as VisualGroup, not left at identity forever
		# -- see _tween_wire_pitch()'s own doc comment for the full
		# reasoning (Round 13 fixed one bug by freezing Collision, which
		# created a second, more severe one: the collider no longer
		# matched a disconnected wire's actual resting pose at all).
		var rot_x: float = 0.0 if is_connected else deg_to_rad(WIRE_DISCONNECT_PITCH_DEGREES)
		node.get_node("VisualGroup").rotation.x = rot_x
		_snap_collision_to_pose(node.get_node("Collision"), rot_x)
		_set_indicator(role, is_connected)

	if service_replaced:
		_wire_nodes[_fault_role].visible = false
		var is_service_connected: bool = _fault_role in reconnected
		_replacement_wire.visible = true
		_replacement_wire.scale = Vector3.ONE
		var service_rot_x: float = 0.0 if is_service_connected else deg_to_rad(REPLACEMENT_STAGED_PITCH_DEGREES)
		_active_replacement_visual_group().rotation.x = service_rot_x
		_snap_collision_to_pose(_replacement_wire.get_node("Collision"), service_rot_x)
		_set_indicator(_fault_role, is_service_connected)
	else:
		_replacement_wire.visible = false

	_breaker_hinge.rotation.x = deg_to_rad(-35.0) if isolated else 0.0
	var bmat: StandardMaterial3D = _breaker_status_light.material
	bmat.emission = LIGHT_OFF_COLOR if isolated else LIGHT_ON_COLOR
	bmat.albedo_color = Color(0.2, 0.08, 0.06, 1) if isolated else Color(0.1, 0.3, 0.12, 1)

	for i in _screw_nodes.size():
		var node2: Node3D = _screw_nodes[i]
		var p: int = screw_progress[i] if i < screw_progress.size() else 0
		var t: float = float(p) / float(maxi(screw_turns_needed, 1))
		node2.position.z = _screw_base_z[i] + 0.1 * t
		node2.rotation.z = deg_to_rad(360.0 * 1.5 * t)
