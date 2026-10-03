extends Node3D
## Free mouse-look. Rotates this node for yaw and a child pivot for pitch.
##
## Deliberately NOT reset when the player arrives at a new MovementNode —
## you keep looking wherever your head was turned, the way a real walk
## works. Only the player's body-facing (handled by MovementController)
## snaps to each node's authored orientation.

@export var mouse_sensitivity: float = 0.0025
@export var pitch_limit_degrees: float = 80.0

@onready var pitch_pivot: Node3D = $PitchPivot


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)

		var pitch: float = pitch_pivot.rotation.x - event.relative.y * mouse_sensitivity
		var limit := deg_to_rad(pitch_limit_degrees)
		pitch_pivot.rotation.x = clampf(pitch, -limit, limit)
