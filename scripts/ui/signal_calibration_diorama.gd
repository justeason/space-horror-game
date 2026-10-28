extends Node3D
## Round 16 Priority 7: physical presentation for M02 Signal Calibration
## -- a communications tuning console with two rotary dials (frequency,
## gain), an analog signal-strength meter, and a small oscilloscope-
## style waveform display. Same proven architecture as every other
## diorama in this project (electrical_repair_diorama.gd /
## valve_routing_diorama.gd / filter_housing_diorama.gd /
## circuit_tracer_diorama.gd): presentation only, raycast click
## dispatch, no procedure state of its own, shared between a focused
## SubViewport instance and a plain world-embedded twin via
## sync_full_state().
##
## DIAL INTERACTION: each dial is ONE click target, split into two
## logical halves by WHERE on the dial body the raycast actually lands
## (left half nudges the value down, right half nudges it up) -- "the
## simplest appropriate mechanic... rotate wheel between detents,"
## without needing two separate invisible colliders per dial.

signal freq_nudge(direction: int)
signal gain_nudge(direction: int)

@export var world_display_mode: bool = false

const _FREQ_MIN: float = 0.0
const _FREQ_MAX: float = 100.0
const _GAIN_MIN: float = 0.0
const _GAIN_MAX: float = 1.0
const _SWEEP_DEG: float = 120.0

const COLOR_BAR_QUIET := Color(0.2, 0.55, 0.3, 1)
const COLOR_BAR_NOISY := Color(0.75, 0.25, 0.15, 1)

@onready var _camera: Camera3D = $Camera3D
@onready var _freq_dial: Node3D = $Dials/FreqDial
@onready var _gain_dial: Node3D = $Dials/GainDial
@onready var _freq_collider: StaticBody3D = $Dials/FreqDial/Collision
@onready var _gain_collider: StaticBody3D = $Dials/GainDial/Collision
@onready var _needle: Node3D = $Meter/Needle
@onready var _readout: Label3D = $Labels/ReadoutText
@onready var _bars: Array = $Waveform/Bars.get_children()

var _collider_action := {}
var _active: bool = false
var _noise_time: float = 0.0
var _current_noise: float = 0.0
var _current_quality: float = 0.0


func _ready() -> void:
	_collider_action[_freq_collider] = &"freq"
	_collider_action[_gain_collider] = &"gain"
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
	_noise_time += delta
	_update_bars()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or world_display_mode:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit: Dictionary = _raycast(event.position)
		if hit.is_empty():
			return
		get_viewport().set_input_as_handled()
		var action: StringName = hit["action"]
		var direction: int = hit["direction"]
		if action == &"freq":
			freq_nudge.emit(direction)
		elif action == &"gain":
			gain_nudge.emit(direction)


func _raycast(mouse_pos_override = null) -> Dictionary:
	var mouse_pos: Vector2
	if mouse_pos_override != null:
		mouse_pos = mouse_pos_override
	else:
		var viewport := get_viewport()
		if viewport == null:
			return {}
		mouse_pos = viewport.get_mouse_position()
	var space_state := get_world_3d().direct_space_state
	var origin: Vector3 = _camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = _camera.project_ray_normal(mouse_pos)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 6.0)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return {}
	var collider = result.get("collider")
	if collider == null or not _collider_action.has(collider):
		return {}
	var action: StringName = _collider_action[collider]
	var dial: Node3D = _freq_dial if action == &"freq" else _gain_dial
	var local_hit: Vector3 = dial.to_local(result["position"])
	var direction: int = 1 if local_hit.x >= 0.0 else -1
	return {"action": action, "direction": direction}


## Test-only helper: resolves which half of a dial a given screen
## position would hit, without needing a real OS mouse event -- same
## convention as every other diorama's screen_position_for()/
## valve_screen_position() helpers.
func dial_half_screen_position(action: StringName, direction: int) -> Vector2:
	var dial: Node3D = _freq_dial if action == &"freq" else _gain_dial
	var offset: Vector3 = Vector3(0.05 * direction, 0, 0)
	return _camera.unproject_position(dial.global_transform * offset)


func _update_bars() -> void:
	for i in _bars.size():
		var bar: CSGBox3D = _bars[i]
		var t: float = float(i) / float(_bars.size() - 1)
		var wobble: float = sin(_noise_time * (4.0 + t * 3.0) + t * 6.0)
		var noise_wobble: float = _current_noise * wobble * 0.5
		var quality_height: float = 0.3 + _current_quality * 1.6
		var height: float = clampf(quality_height + noise_wobble, 0.15, 2.2)
		bar.scale.y = height
		bar.position.y = (height - 1.0) * 0.01
		var mat: StandardMaterial3D = bar.material
		if mat == null:
			mat = StandardMaterial3D.new()
			mat.resource_local_to_scene = true
			bar.material = mat
		mat.albedo_color = COLOR_BAR_QUIET.lerp(COLOR_BAR_NOISY, _current_noise)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color.darkened(0.3)
		mat.emission_energy_multiplier = 0.3 + _current_quality * 0.6


func set_readout_text(text: String) -> void:
	_readout.text = text


## Full authoritative resync -- called on (re)open and whenever the
## world twin needs to match, same contract as every other diorama in
## this project.
func sync_full_state(frequency: float, gain: float, quality: float, noise: float, complete: bool) -> void:
	var freq_t: float = inverse_lerp(_FREQ_MIN, _FREQ_MAX, frequency)
	_freq_dial.rotation.z = deg_to_rad(lerp(-_SWEEP_DEG, _SWEEP_DEG, freq_t))
	var gain_t: float = inverse_lerp(_GAIN_MIN, _GAIN_MAX, gain)
	_gain_dial.rotation.z = deg_to_rad(lerp(-_SWEEP_DEG, _SWEEP_DEG, gain_t))
	_needle.rotation.z = deg_to_rad(lerp(-_SWEEP_DEG, _SWEEP_DEG, quality))
	_current_quality = quality
	_current_noise = noise
	if complete:
		_readout.text = "SIGNAL LOCKED"
		_readout.modulate = Color(0.4, 0.95, 0.55, 1)
