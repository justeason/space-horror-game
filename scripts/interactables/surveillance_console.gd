extends StaticBody3D
## A physical surveillance console: click it to cycle through the
## station's cameras, one at a time. Only one feed is ever shown here —
## deliberate, explicit switching, not a multi-feed grid.
##
## `set_feed_override()` is an unused seam for future horror systems to
## make THIS specific display diverge from the camera's real feed,
## without touching SurveillanceCamera or any other display. Nothing
## calls it yet; normal operation always shows the live selected feed.

signal camera_changed(camera_id: StringName)

@export var camera_paths: Array[NodePath] = []

@onready var screen_mesh: MeshInstance3D = $Screen

var _cameras: Array = []
var _selected_index: int = 0
var _feed_override: Texture2D = null
var _screen_material: StandardMaterial3D


func _ready() -> void:
	for path in camera_paths:
		var cam := get_node_or_null(path)
		if cam != null:
			_cameras.append(cam)

	# Unshaded, driven only by albedo -- same overexposure bug class
	# found and fixed on the laptop/workstation screens: lit + emissive
	# stacks the screen's own brightness on top of scene lighting and
	# can clip to solid white near a strong nearby light. Fixed here too
	# even though this monitor is being hidden in main.tscn (M11 Control
	# Room Workstation Revamp), so the underlying prop stays correct if
	# it's ever shown again.
	_screen_material = StandardMaterial3D.new()
	_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mesh.material_override = _screen_material

	_update_screen()


func interact() -> void:
	if _cameras.is_empty():
		return
	_selected_index = (_selected_index + 1) % _cameras.size()
	_update_screen()
	camera_changed.emit(_cameras[_selected_index].camera_id)


## Unused in M5: lets a future system show something other than the
## true selected feed on this specific display.
func set_feed_override(tex: Texture2D) -> void:
	_feed_override = tex
	_update_screen()


## Read-only access for any OTHER physical display that wants to show
## the same live feed (e.g. the Control Room workstation screen,
## scripts/ui/workstation_screen.gd) without owning any camera-selection
## state of its own -- this console remains the single source of truth
## for "which camera is currently selected" station-wide (Approved
## Decision A.11: no duplicated surveillance state, no second camera
## owner).
func get_current_feed_texture() -> Texture2D:
	if _cameras.is_empty():
		return null
	return _feed_override if _feed_override != null else _cameras[_selected_index].get_feed_texture()


func get_current_camera_id() -> StringName:
	if _cameras.is_empty():
		return &""
	return _cameras[_selected_index].camera_id


func _update_screen() -> void:
	if _cameras.is_empty():
		return
	var tex: Texture2D = _feed_override if _feed_override != null else _cameras[_selected_index].get_feed_texture()
	_screen_material.albedo_texture = tex
