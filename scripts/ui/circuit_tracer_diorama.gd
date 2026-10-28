extends Node3D
## Round 15 Priority 5: physical presentation for the E09 Diagnose
## Intermittent Electrical Fault procedure -- same proven architecture
## as every other diorama in this project (electrical_repair_diorama.gd
## / valve_routing_diorama.gd / filter_housing_diorama.gd): presentation
## only, raycast click dispatch, no procedure state of its own, shared
## between a focused SubViewport instance and a plain world-embedded
## twin via sync_full_state(). The distinctive mechanic here is
## EVIDENCE-BASED DIAGNOSIS: the player moves a probe to test points to
## gather readings, then submits a diagnosis of WHICH segment is at
## fault -- neither a click-sequence, a discrete toggle, nor an
## alignment/insertion task.

signal test_point_clicked(tp: StringName)
signal segment_clicked(segment: StringName)

@export var world_display_mode: bool = false

const _TEST_POINTS: Array[StringName] = [&"tp1", &"tp2", &"tp3", &"tp4"]
const _SEGMENTS: Array[StringName] = [&"power_tp1", &"tp1_tp2", &"tp2_tp3", &"tp3_tp4"]

const COLOR_TP_UNTESTED := Color(0.5, 0.52, 0.55, 1)
const COLOR_TP_TESTED := Color(0.25, 0.75, 0.85, 1)
const COLOR_TP_PROBE := Color(0.85, 0.75, 0.2, 1)

@onready var _camera: Camera3D = $Camera3D
@onready var _probe: Node3D = $Probe
@onready var _reading_label: Label3D = $Display/ReadingText

@onready var _tp_roots := {
	&"tp1": $TestPoints/Tp1,
	&"tp2": $TestPoints/Tp2,
	&"tp3": $TestPoints/Tp3,
	&"tp4": $TestPoints/Tp4,
}
@onready var _tp_colliders := {
	&"tp1": $TestPoints/Tp1/Collision,
	&"tp2": $TestPoints/Tp2/Collision,
	&"tp3": $TestPoints/Tp3/Collision,
	&"tp4": $TestPoints/Tp4/Collision,
}
@onready var _tp_bodies := {
	&"tp1": $TestPoints/Tp1/Body,
	&"tp2": $TestPoints/Tp2/Body,
	&"tp3": $TestPoints/Tp3/Body,
	&"tp4": $TestPoints/Tp4/Body,
}
@onready var _segment_colliders := {
	&"power_tp1": $SegmentColliders/PowerTp1Col,
	&"tp1_tp2": $SegmentColliders/Tp1Tp2Col,
	&"tp2_tp3": $SegmentColliders/Tp2Tp3Col,
	&"tp3_tp4": $SegmentColliders/Tp3Tp4Col,
}

var _collider_action := {}
var _active: bool = false


func _ready() -> void:
	for tp in _TEST_POINTS:
		_collider_action[_tp_colliders[tp]] = tp
	for seg in _SEGMENTS:
		_collider_action[_segment_colliders[seg]] = seg
	if world_display_mode:
		for collider in _collider_action.keys():
			collider.collision_layer = 0
			collider.collision_mask = 0
		_camera.queue_free()
		for light_name in ["KeyLight", "FillLight"]:
			var light: Node = get_node_or_null(light_name)
			if light != null:
				light.queue_free()


func set_active(value: bool) -> void:
	_active = value


func _unhandled_input(event: InputEvent) -> void:
	if not _active or world_display_mode:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var action: StringName = _raycast_action(event.position)
		if action == &"":
			return
		get_viewport().set_input_as_handled()
		if action in _TEST_POINTS:
			test_point_clicked.emit(action)
		elif action in _SEGMENTS:
			segment_clicked.emit(action)


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
	return _collider_action[collider]


func screen_position_for(world_pos: Vector3) -> Vector2:
	return _camera.unproject_position(world_pos)


func test_point_screen_position(tp: StringName) -> Vector2:
	return screen_position_for(_tp_roots[tp].global_position)


func segment_screen_position(segment: StringName) -> Vector2:
	return screen_position_for(_segment_colliders[segment].global_position)


## Moves the physical probe prop to the clicked test point and updates
## the reading display -- the actual interaction the brief asked for
## ("moving the probe to physical test points... a meter responding to
## the tested location"), not a text-menu answer selection.
func animate_probe_to(tp: StringName, reading_text: String) -> void:
	_probe.visible = true
	var target: Vector3 = _tp_roots[tp].position + Vector3(0, -0.3, 0.2)
	var tw := create_tween()
	tw.tween_property(_probe, "position", target, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var mat: StandardMaterial3D = _tp_bodies[tp].material
	mat.albedo_color = COLOR_TP_TESTED
	_reading_label.text = reading_text


## A wrong diagnosis guess bumps the display text briefly rather than
## silently doing nothing -- recoverable, informative feedback, same
## "never silently accept/ignore an incorrect action" policy used by
## filter_housing_diorama.gd's animate_insert_fail().
func flash_wrong_guess(segment_label: String) -> void:
	_reading_label.text = "NO FAULT FOUND AT " + segment_label
	_reading_label.modulate = Color(0.9, 0.35, 0.25, 1)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func(): _reading_label.modulate = Color(0.4, 0.95, 0.55, 1))


func show_fault_found(segment_label: String) -> void:
	_reading_label.text = "FAULT ISOLATED: " + segment_label
	_reading_label.modulate = Color(0.95, 0.8, 0.2, 1)


## Full authoritative resync -- called on (re)open and whenever the
## world twin needs to match, same contract as every other diorama in
## this project. `tested_points` is passed explicitly (not inferred)
## because the world-display twin never receives animate_probe_to()
## calls directly -- without this it would only ever show the CURRENT
## probe location as tested, losing the rest of the player's test
## history every time the station resyncs it.
func sync_full_state(probe_at: StringName, tested_points: Array, complete: bool) -> void:
	for tp in _TEST_POINTS:
		var mat: StandardMaterial3D = _tp_bodies[tp].material
		mat.albedo_color = COLOR_TP_TESTED if tp in tested_points else COLOR_TP_UNTESTED
	if probe_at == &"" or not _tp_roots.has(probe_at):
		_probe.visible = false
	else:
		_probe.visible = true
		_probe.position = _tp_roots[probe_at].position + Vector3(0, -0.3, 0.2)
	if complete:
		_reading_label.text = "FAULT ISOLATED — BENCH NOMINAL"
		_reading_label.modulate = Color(0.4, 0.95, 0.55, 1)
	elif probe_at == &"":
		_reading_label.text = "PROBE A TEST POINT"
