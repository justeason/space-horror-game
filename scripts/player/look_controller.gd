extends Node3D
## Free mouse-look. Rotates this node for yaw and a child pivot for pitch.
##
## Deliberately NOT reset when the player arrives at a new MovementNode —
## you keep looking wherever your head was turned, the way a real walk
## works. Only the player's body-facing (handled by MovementController)
## snaps to each node's authored orientation.
##
## Mouse input updates a target yaw/pitch instantly; the actual rotation
## eases toward that target each frame (frame-rate-independent exponential
## smoothing) so the head has a little weight instead of snapping 1:1
## with the cursor. `look_damping` is exported so a future horror beat
## can lower it temporarily for a heavier, draggier feel — nothing
## horror-specific is implemented here, just the tunable baseline.

@export var mouse_sensitivity: float = 0.0020
@export var pitch_limit_degrees: float = 80.0

## Higher = snappier/less floaty catch-up; lower = heavier, slower to
## settle. ~14 reaches ~95% of the target turn in about 0.2s.
@export var look_damping: float = 14.0

@onready var pitch_pivot: Node3D = $PitchPivot

var _target_yaw: float = 0.0
var _target_pitch: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_target_yaw = rotation.y
	_target_pitch = pitch_pivot.rotation.x


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
		_target_yaw -= event.relative.x * mouse_sensitivity

		var limit := deg_to_rad(pitch_limit_degrees)
		_target_pitch = clampf(_target_pitch - event.relative.y * mouse_sensitivity, -limit, limit)


func _process(delta: float) -> void:
	var t: float = 1.0 - exp(-look_damping * delta)
	rotation.y = lerp_angle(rotation.y, _target_yaw, t)
	pitch_pivot.rotation.x = lerp_angle(pitch_pivot.rotation.x, _target_pitch, t)
