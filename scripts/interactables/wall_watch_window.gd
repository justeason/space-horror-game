extends StaticBody3D
## A fixed, physically mounted monitor permanently assigned to one
## camera. Unlike the surveillance console, this is NOT selectable — it
## has no interact() at all, so clicking it correctly falls through to
## the movement system exactly like any other inert wall geometry.
##
## `set_feed_override()` is an unused seam for future horror systems to
## make THIS specific display diverge from the camera's real feed,
## without touching SurveillanceCamera or the console. Nothing calls it
## yet; normal operation always shows the live assigned feed.

@export var camera_path: NodePath

@onready var screen_mesh: MeshInstance3D = $Screen

var _camera: Node = null
var _feed_override: Texture2D = null
var _screen_material: StandardMaterial3D


func _ready() -> void:
	_camera = get_node_or_null(camera_path)

	_screen_material = StandardMaterial3D.new()
	_screen_material.emission_enabled = true
	_screen_material.emission_energy_multiplier = 1.0
	screen_mesh.material_override = _screen_material

	_update_screen()


## Unused in M5: lets a future system show something other than the
## true assigned feed on this specific display.
func set_feed_override(tex: Texture2D) -> void:
	_feed_override = tex
	_update_screen()


func _update_screen() -> void:
	if _camera == null:
		return
	var tex: Texture2D = _feed_override if _feed_override != null else _camera.get_feed_texture()
	_screen_material.albedo_texture = tex
	_screen_material.emission_texture = tex
