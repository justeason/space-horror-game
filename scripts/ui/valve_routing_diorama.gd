extends Node3D
## Round 15 Priority 2: the physical 3D presentation for the Coolant
## Loop Valve Routing manifold -- replaces the flat 2D button/ColorRect
## schematic from Round 14, which the player correctly reported as
## reading like a debug diagram, not physical equipment. Architecture
## directly mirrors scripts/ui/electrical_repair_diorama.gd (the
## project's own proven pattern for "one small 3D scene instanced
## twice -- once inside a focused-view SubViewport, once as a plain
## non-interactive child of the matching world prop -- driven entirely
## by an external authoritative owner's sync_full_state() calls, never
## holding its own procedure state"): presentation only, no gameplay
## logic lives here.
##
## WHY THE OLD VERSION LOOKED LIKE "A SMALL SCHEMATIC ABOVE AN ALMOST-
## BLACK BOX": there was no 3D content at all for valve routing --
## the focused view was a plain 2D Control panel over a translucent
## (0.72 alpha) background ColorRect, so what the player saw "behind"
## the small diagram was the dim, unlit 3D WORLD rendering straight
## through that translucent layer, misread as "equipment." This file
## (plus its own KeyLight/FillLight, same convention as the electrical
## diorama) is the actual equipment that now fills that space.

signal valve_clicked(id: int)

@export var world_display_mode: bool = false

const VALVE_IDS: Array[int] = [1, 2, 3]
## V1/V2 sit on horizontal pipe runs, so "aligned with the pipe" (open)
## is 0 degrees and "perpendicular" (closed) is 90. V3 sits on the
## vertical drain branch, so its own "aligned with the pipe" pose is
## already 90 degrees -- same rotation axis, swapped endpoints, so one
## shared tween helper still works for all three (see _target_angle()).
const _OPEN_ANGLE_DEG := {1: 0.0, 2: 0.0, 3: 90.0}
const _CLOSED_ANGLE_DEG := {1: 90.0, 2: 90.0, 3: 0.0}

const COLOR_PIPE_DEAD := Color(0.42, 0.45, 0.48, 1)
const COLOR_PIPE_LIVE := Color(0.2, 0.55, 0.62, 1)
const EMISSION_LIVE := Color(0.25, 0.75, 0.85, 1)
const EMISSION_LEAK := Color(0.85, 0.35, 0.15, 1)
const COLOR_HANDLE_OPEN := Color(0.15, 0.55, 0.22, 1)
const COLOR_HANDLE_CLOSED := Color(0.55, 0.1, 0.08, 1)

@onready var _camera: Camera3D = $Camera3D

@onready var _valve_handle_roots := {
	1: $Valves/V1/HandleRoot,
	2: $Valves/V2/HandleRoot,
	3: $Valves/V3/HandleRoot,
}
@onready var _valve_roots := {
	1: $Valves/V1,
	2: $Valves/V2,
	3: $Valves/V3,
}
@onready var _valve_colliders := {
	1: $Valves/V1/Collision,
	2: $Valves/V2/Collision,
	3: $Valves/V3/Collision,
}
@onready var _handle_materials := {
	1: $Valves/V1/HandleRoot/Handle.material,
	2: $Valves/V2/HandleRoot/Handle.material,
	3: $Valves/V3/HandleRoot/Handle.material,
}

@onready var _pipe_segments := {
	&"inlet_v1": $Pipes/SegInletV1,
	&"v1_junction": $Pipes/SegV1Junction,
	&"junction_v2": $Pipes/SegJunctionV2,
	&"v2_outlet": $Pipes/SegV2Outlet,
	&"junction_down": $Pipes/SegJunctionDown,
	&"v3_drain": $Pipes/SegV3Drain,
}
@onready var _gauge_needle: CSGBox3D = $Gauge/Needle

var _collider_action := {}
var _active: bool = false
var _pulse_time: float = 0.0
var _live_segments: Array[StringName] = []
var _leak_segments: Array[StringName] = []
var _handle_tweens := {}
var _outlet_live: bool = false


func _ready() -> void:
	for id in VALVE_IDS:
		var body: StaticBody3D = _valve_colliders[id]
		_collider_action[body] = id
	if world_display_mode:
		for id in VALVE_IDS:
			var body: StaticBody3D = _valve_colliders[id]
			body.collision_layer = 0
			body.collision_mask = 0
		# Same "free the world-embedded copy's own camera/lights" policy
		# as electrical_repair_diorama.gd's _configure_world_display_mode()
		# -- the real world already provides both for a child of
		# ValveRoutingStation. Confirmed directly this is not merely
		# cosmetic: leaving this camera alive and current=false (rather
		# than freeing it) was NOT enough by itself -- it still silently
		# hijacked the player's entire main-window view the instant the
		# valve station entered the tree, because nothing in this
		# project's player camera had ever explicitly claimed
		# current=true either (now fixed in interaction_controller.gd,
		# but freeing this redundant camera/lights is the same
		# belt-and-suspenders policy electrical's diorama already uses).
		_camera.queue_free()
		for light_name in ["KeyLight", "FillLight", "RimLight"]:
			var light: Node = get_node_or_null(light_name)
			if light != null:
				light.queue_free()


func set_active(value: bool) -> void:
	_active = value


func _process(delta: float) -> void:
	if _live_segments.is_empty() and _leak_segments.is_empty():
		return
	_pulse_time += delta
	var pulse: float = 0.65 + 0.35 * sin(_pulse_time * 2.4)
	for key in _live_segments:
		var seg: CSGCylinder3D = _pipe_segments[key]
		var mat: StandardMaterial3D = seg.material
		mat.emission_energy_multiplier = pulse * 0.6
	for key in _leak_segments:
		var seg: CSGCylinder3D = _pipe_segments[key]
		var mat: StandardMaterial3D = seg.material
		mat.emission_energy_multiplier = pulse * 0.9
	var needle_target: float = deg_to_rad(-70.0) if _outlet_live else deg_to_rad(70.0)
	_gauge_needle.rotation.z = lerp_angle(_gauge_needle.rotation.z, needle_target, minf(delta * 6.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not _active or world_display_mode:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id: int = _raycast_valve(event.position)
		if id != 0:
			valve_clicked.emit(id)
			get_viewport().set_input_as_handled()


func _raycast_valve(mouse_pos_override = null) -> int:
	var mouse_pos: Vector2
	if mouse_pos_override != null:
		mouse_pos = mouse_pos_override
	else:
		var viewport := get_viewport()
		if viewport == null:
			return 0
		mouse_pos = viewport.get_mouse_position()
	var space_state := get_world_3d().direct_space_state
	var origin: Vector3 = _camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = _camera.project_ray_normal(mouse_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 6.0)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return 0
	var collider = result.get("collider")
	if collider == null or not _collider_action.has(collider):
		return 0
	return _collider_action[collider]


## Exposed for tests -- the real inverse of the raycast's own mouse->ray
## mapping, same convention as electrical_repair_diorama.gd's
## screen_position_for().
func screen_position_for(world_pos: Vector3) -> Vector2:
	return _camera.unproject_position(world_pos)


## Uses the valve's own stable body origin, NOT the handle's rotating
## tip -- the collision target is generously sized to cover the whole
## handle sweep regardless of open/closed pose, so clicking the stable
## center is the more reliable target (both for tests and for a real
## player, who should be able to click anywhere on the valve, not just
## exactly on the handle tip).
func valve_screen_position(id: int) -> Vector2:
	return screen_position_for(_valve_roots[id].global_position)


## Animates one valve's handle to its open/closed pose -- snaps
## instantly to the correct rotation target internally (a tween handles
## the actual smooth motion) and recolors the handle so state is
## readable two ways (orientation + color), not just one.
func animate_valve(id: int, open: bool) -> void:
	var target_deg: float = _OPEN_ANGLE_DEG[id] if open else _CLOSED_ANGLE_DEG[id]
	var root: Node3D = _valve_handle_roots[id]
	if _handle_tweens.has(id) and _handle_tweens[id] != null and _handle_tweens[id].is_valid():
		_handle_tweens[id].kill()
	var tw := create_tween()
	tw.tween_property(root, "rotation:z", deg_to_rad(target_deg), 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_handle_tweens[id] = tw
	var mat: StandardMaterial3D = _handle_materials[id]
	mat.albedo_color = COLOR_HANDLE_OPEN if open else COLOR_HANDLE_CLOSED
	mat.emission = (COLOR_HANDLE_OPEN if open else COLOR_HANDLE_CLOSED).darkened(0.5)


## Updates which pipe segments read as "live" (coolant flowing, gentle
## teal pulse) vs "leaking" (reaching the drain, amber/red pulse) vs
## dead (flat gunmetal, no glow) -- purely a function of the booleans
## the caller already computed from valve state, not a pathfinder of
## its own. `branch3_is_leak` (Round 16 Priority 5): in the standard
## single-outlet configuration, the V3 branch terminates at a DRAIN and
## flowing coolant there is always a leak (amber/red); in the
## alternate dual-outlet configuration, V3 is a genuine SECOND OUTLET,
## so flow there is live/valid (teal) exactly like V2's branch, never
## treated as a leak -- same station state, different physical meaning,
## so the diorama must be told which interpretation applies rather than
## assuming the original single-topology one.
func set_flow_visual(v1_live: bool, outlet_live: bool, drain_live: bool, branch3_is_leak: bool = true) -> void:
	_outlet_live = outlet_live
	_live_segments.clear()
	_leak_segments.clear()
	var live_keys: Array[StringName] = []
	if v1_live:
		live_keys.append(&"inlet_v1")
		live_keys.append(&"v1_junction")
		live_keys.append(&"junction_v2")
		live_keys.append(&"junction_down")
	if outlet_live:
		live_keys.append(&"v2_outlet")
	for key in _pipe_segments:
		var seg: CSGCylinder3D = _pipe_segments[key]
		var mat: StandardMaterial3D = seg.material
		if key == &"v3_drain" and drain_live and branch3_is_leak:
			mat.albedo_color = COLOR_PIPE_LIVE
			mat.emission_enabled = true
			mat.emission = EMISSION_LEAK
			_leak_segments.append(key)
		elif key == &"v3_drain" and drain_live:
			mat.albedo_color = COLOR_PIPE_LIVE
			mat.emission_enabled = true
			mat.emission = EMISSION_LIVE
			_live_segments.append(key)
		elif key in live_keys:
			mat.albedo_color = COLOR_PIPE_LIVE
			mat.emission_enabled = true
			mat.emission = EMISSION_LIVE
			_live_segments.append(key)
		else:
			mat.albedo_color = COLOR_PIPE_DEAD
			mat.emission_enabled = false
			mat.emission_energy_multiplier = 1.0


## Full authoritative resync -- called whenever the procedure (re)opens
## or the world twin needs to match, same "re-entering renders from
## saved state" contract as electrical_repair_diorama.gd's own
## sync_full_state().
func sync_full_state(open_state: Dictionary, branch3_is_leak: bool = true) -> void:
	for id in VALVE_IDS:
		var open: bool = open_state.get(id, false)
		var target_deg: float = _OPEN_ANGLE_DEG[id] if open else _CLOSED_ANGLE_DEG[id]
		_valve_handle_roots[id].rotation.z = deg_to_rad(target_deg)
		var mat: StandardMaterial3D = _handle_materials[id]
		mat.albedo_color = COLOR_HANDLE_OPEN if open else COLOR_HANDLE_CLOSED
		mat.emission = (COLOR_HANDLE_OPEN if open else COLOR_HANDLE_CLOSED).darkened(0.5)
	var v1_live: bool = open_state.get(1, false)
	var outlet_live: bool = v1_live and open_state.get(2, false)
	var drain_live: bool = v1_live and open_state.get(3, false)
	set_flow_visual(v1_live, outlet_live, drain_live, branch3_is_leak)


## Round 16 Priority 5: swaps the physical DRAIN label to read OUTLET B
## for the alternate dual-outlet configuration -- same manifold, same
## geometry, a different (still short, still physical) terminal label,
## never silently mismatched against the station's own config choice.
func set_drain_label_text(text: String) -> void:
	var label: Label3D = get_node_or_null("Labels/DrainLabel")
	if label != null:
		label.text = text
