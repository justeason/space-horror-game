extends Node3D
## Round 15 Priority 4: physical presentation for the L02 Filter
## Replacement procedure -- a real 3D diorama (same architecture as
## electrical_repair_diorama.gd / valve_routing_diorama.gd: presentation
## only, raycast click dispatch, no procedure state of its own, shared
## between a focused SubViewport instance and a plain world-embedded
## twin). The distinctive mechanic here is ALIGNMENT AND INSERTION: the
## new cartridge's tab must be rotated to match the housing's own fixed
## keyway marker before an insert attempt can succeed -- neither a
## click-sequence (electrical) nor a discrete open/closed toggle
## (coolant loop).

signal valve_clicked
signal latch_clicked(index: int)
signal old_cartridge_clicked
signal new_cartridge_clicked
signal insert_attempted

@export var world_display_mode: bool = false

const FilterHousingStation = preload("res://scripts/interactables/filter_housing_station.gd")

@onready var _camera: Camera3D = $Camera3D
@onready var _valve_collider: StaticBody3D = $Valve/Collision
@onready var _latch_colliders := {
	1: $Housing/Latch1/Latch1Collision,
	2: $Housing/Latch2/Latch2Collision,
}
@onready var _old_cartridge_collider: StaticBody3D = $OldCartridge/Collision
@onready var _new_cartridge_collider: StaticBody3D = $NewCartridge/Collision
@onready var _old_cartridge: Node3D = $OldCartridge
@onready var _new_cartridge: Node3D = $NewCartridge
@onready var _new_cartridge_tab_root: Node3D = $NewCartridge/TabRoot
@onready var _housing_keyway: Node3D = $Housing/KeywayMark
@onready var _valve_handle_root: Node3D = $Valve/HandleRoot
@onready var _latch_bodies := {
	1: $Housing/Latch1/Latch1Body,
	2: $Housing/Latch2/Latch2Body,
}
@onready var _gauge_needle: CSGBox3D = $Gauge/Needle

const COLOR_LATCH_CLOSED := Color(0.15, 0.55, 0.22, 1)
const COLOR_LATCH_OPEN := Color(0.55, 0.1, 0.08, 1)
const COLOR_VALVE_OPEN := Color(0.15, 0.55, 0.22, 1)
const COLOR_VALVE_CLOSED := Color(0.55, 0.1, 0.08, 1)

var _collider_action := {}
var _active: bool = false
var _sealed: bool = false


func _ready() -> void:
	_collider_action[_valve_collider] = &"valve"
	_collider_action[_latch_colliders[1]] = &"latch:1"
	_collider_action[_latch_colliders[2]] = &"latch:2"
	_collider_action[_old_cartridge_collider] = &"old_cartridge"
	_collider_action[_new_cartridge_collider] = &"new_cartridge"
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


func _process(delta: float) -> void:
	var needle_target: float = deg_to_rad(-70.0) if _sealed else deg_to_rad(70.0)
	_gauge_needle.rotation.z = lerp_angle(_gauge_needle.rotation.z, needle_target, minf(delta * 6.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not _active or world_display_mode:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var action: StringName = _raycast_action(event.position)
		if action == &"":
			return
		get_viewport().set_input_as_handled()
		if action == &"valve":
			valve_clicked.emit()
		elif action.begins_with("latch:"):
			latch_clicked.emit(int(action.substr(6)))
		elif action == &"old_cartridge":
			old_cartridge_clicked.emit()
		elif action == &"new_cartridge":
			new_cartridge_clicked.emit()


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


func click_position(action: StringName) -> Vector2:
	match action:
		&"valve": return screen_position_for(_valve_collider.global_position)
		&"latch:1": return screen_position_for(_latch_colliders[1].global_position)
		&"latch:2": return screen_position_for(_latch_colliders[2].global_position)
		&"old_cartridge": return screen_position_for(_old_cartridge_collider.global_position)
		&"new_cartridge": return screen_position_for(_new_cartridge_collider.global_position)
	return Vector2.ZERO


func animate_valve(open: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_valve_handle_root, "rotation:z", deg_to_rad(90.0 if open else 0.0), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var mat: StandardMaterial3D = _valve_handle_root.get_node("Handle").material
	mat.albedo_color = COLOR_VALVE_OPEN if open else COLOR_VALVE_CLOSED
	mat.emission = (COLOR_VALVE_OPEN if open else COLOR_VALVE_CLOSED).darkened(0.5)


func animate_latch(index: int, open: bool) -> void:
	var root: Node3D = _latch_bodies[index].get_parent()
	var tw := create_tween()
	tw.tween_property(root, "rotation:x", deg_to_rad(50.0 if open else 0.0), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var mat: StandardMaterial3D = _latch_bodies[index].material
	mat.albedo_color = COLOR_LATCH_OPEN if open else COLOR_LATCH_CLOSED


func animate_remove_old_cartridge() -> void:
	var tw := create_tween()
	tw.tween_property(_old_cartridge, "position:x", _old_cartridge.position.x - 0.35, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_old_cartridge, "scale", Vector3(0.6, 0.6, 0.6), 0.3)
	tw.tween_callback(func(): _old_cartridge.visible = false)


func set_cartridge_angle(angle_deg: float) -> void:
	_new_cartridge_tab_root.rotation.x = deg_to_rad(angle_deg)


## A failed insert attempt visibly bumps/rejects rather than silently
## doing nothing -- per the brief's explicit "do not silently accept an
## incorrectly aligned component" / "recoverable feedback" requirement.
func animate_insert_fail() -> void:
	var start_pos: Vector3 = _new_cartridge.position
	var bump: Vector3 = start_pos + Vector3(-0.08, 0, 0)
	var tw := create_tween()
	tw.tween_property(_new_cartridge, "position", bump, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_new_cartridge, "position", start_pos, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func animate_insert_success() -> void:
	var tw := create_tween()
	tw.tween_property(_new_cartridge, "position", Vector3(-0.1, 0.1, 0.0), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_new_cartridge, "scale", Vector3.ONE, 0.35)


func set_sealed(sealed: bool) -> void:
	_sealed = sealed


## Full authoritative resync, same contract as every other diorama in
## this project -- called on (re)open and whenever the world twin needs
## to match.
func sync_full_state(stage: int, latch_open: Dictionary, cartridge_angle_deg: float) -> void:
	var Stage = FilterHousingStation.Stage
	# Must match filter_housing_station.gd's own is_isolated() exactly
	# (stage != ISOLATE alone is wrong: it also needs to exclude
	# COMPLETE, where airflow has been explicitly restored) -- confirmed
	# directly via diagnostic that the mismatched formula here, combined
	# with world/focused instances previously sharing one mutable
	# material (see this file's materials now marked
	# resource_local_to_scene in the .tscn), made the FOCUSED view's own
	# valve handle flip to the wrong color every time ANY action
	# triggered the station's _sync_world_diorama(), even though the
	# focused view itself never called animate_valve() for that action.
	animate_valve(not (stage != Stage.ISOLATE and stage != Stage.COMPLETE))
	for index in [1, 2]:
		var open: bool = latch_open.get(index, false)
		_latch_bodies[index].get_parent().rotation.x = deg_to_rad(50.0 if open else 0.0)
		var mat: StandardMaterial3D = _latch_bodies[index].material
		mat.albedo_color = COLOR_LATCH_OPEN if open else COLOR_LATCH_CLOSED

	var old_removed: bool = stage >= Stage.ALIGN_INSERT
	_old_cartridge.visible = not old_removed
	if not old_removed:
		_old_cartridge.position.x = -0.1
		_old_cartridge.scale = Vector3.ONE

	var new_seated: bool = stage >= Stage.CLOSE_LATCHES
	_new_cartridge.visible = true
	_new_cartridge.position = Vector3(-0.1, 0.1, 0.0) if new_seated else Vector3(0.1, -0.42, 0.15)
	_new_cartridge.scale = Vector3.ONE
	set_cartridge_angle(cartridge_angle_deg)

	set_sealed(stage == Stage.COMPLETE)
