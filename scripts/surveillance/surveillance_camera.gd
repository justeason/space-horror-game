extends SubViewport
## A single physical surveillance camera. Its feed is this SubViewport's
## own render output — a real, continuously-updating Texture2D that any
## number of displays (the console, a wall watch window, ...) can show
## at once. The camera renders once per frame regardless of how many
## consumers are reading its texture.
##
## `camera_id` is a stable, human-readable identity for this camera,
## independent of wherever it lives in the scene tree.

@export var camera_id: StringName = &""


func _ready() -> void:
	# Not placed in a SubViewportContainer, so nothing would otherwise
	# mark this viewport "visible" — it must render continuously on its
	# own for its texture to stay live.
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func get_feed_texture() -> Texture2D:
	return get_texture()
