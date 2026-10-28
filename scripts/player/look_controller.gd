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

## Tuning: lowered from 0.0020 (~20%) alongside `look_damping` for a
## slower, more deliberate turn to build tension — see the movement-
## tuning report for before/after values and rationale.
@export var mouse_sensitivity: float = 0.0016
@export var pitch_limit_degrees: float = 80.0

## Higher = snappier/less floaty catch-up; lower = heavier, slower to
## settle. Was 14.0 (~95% in ~0.2s); lowered to 9.0 (~95% in ~0.33s) for
## a heavier, more deliberate feel without becoming laggy for aiming —
## interaction raycasts still read the camera's current (if lagging)
## transform every frame, so aim is always exactly where the view is,
## just arriving at a held mouse position slightly less snappily.
@export var look_damping: float = 9.0

@onready var pitch_pivot: Node3D = $PitchPivot

var _target_yaw: float = 0.0
var _target_pitch: float = 0.0

## Set false by scripts/player/sleep_state.gd only while actually
## typing in the log text field, so mouse motion stops turning the
## camera and clicks on the UI (which releases/needs the cursor) don't
## also get reinterpreted as "re-capture the mouse" by the block below.
## Free-look otherwise stays ON while the laptop is just being looked
## at (M7 Part B3: "I do NOT want the player frozen looking at the
## laptop"). Does not touch look_damping's per-frame easing in
## _process -- with no new input arriving, the view simply stays
## settled where it already was.
var input_enabled: bool = true

## Set false by scripts/player/sleep_state.gd only while EDITING the log
## entry. Escape is the dedicated "exit the editor" key there (see
## sleep_state.gd's _unhandled_input), and this node's own Escape
## handling below (toggle mouse visibility) must not compete for the
## same keypress. Node processing order already happens to let
## sleep_state.gd consume Escape first while editing (SleepState is
## added to main.tscn after Player, and Godot visits more-recently-added
## nodes first for _unhandled_input), so this guard is not fixing an
## observed double-handling bug -- it is removing the dependency on that
## tree-order coincidence, so a future scene reorder can never silently
## reintroduce one.
var escape_enabled: bool = true

## "Soft focus assist" for laptop use (M7 Part B3). While enabled, the
## view eases toward focus_target_point once the mouse has been still
## for focus_assist_idle_delay seconds, and ANY mouse motion instantly
## resets the idle timer and cancels the ease (ordinary free-look in
## _unhandled_input already updates _target_yaw/_target_pitch directly
## from live input every time, so there is nothing to "fight" -- the
## next frame's ease target simply becomes irrelevant until the mouse
## goes idle again). Only ever toggled by sleep_state.gd while the
## laptop is open and not being edited; never active otherwise, so
## ordinary free-look feel everywhere else in the game is completely
## unchanged.
@export var focus_assist_idle_delay: float = 1.2
@export var focus_assist_ease_speed: float = 2.5

var focus_assist_enabled: bool = false
var focus_target_point: Vector3 = Vector3.ZERO

var _focus_idle_time: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_target_yaw = rotation.y
	_target_pitch = pitch_pivot.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not escape_enabled:
			return
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_focus_idle_time = 0.0
		_target_yaw -= event.relative.x * mouse_sensitivity

		var limit := deg_to_rad(pitch_limit_degrees)
		_target_pitch = clampf(_target_pitch - event.relative.y * mouse_sensitivity, -limit, limit)


func _process(delta: float) -> void:
	if focus_assist_enabled:
		_focus_idle_time += delta
		if _focus_idle_time >= focus_assist_idle_delay:
			var dir: Vector3 = focus_target_point - global_position
			if dir.length_squared() > 0.0001:
				dir = dir.normalized()
				# Empirically-verified convention (see M7 investigation):
				# atan2(-x,-z)/asin(y) gives the WORLD yaw/pitch needed to
				# face dir. rotation.y on THIS node is LOCAL to its parent
				# (Player), and Player carries a fixed, non-zero baked
				# rotation (its starting MovementNode's orientation, 180
				# degrees for this station -- see player_body.gd's
				# lying_world_yaw_degrees comment for the same gotcha).
				# Forgetting to subtract that parent yaw here previously
				# sent the soft-return to face exactly the OPPOSITE
				# direction (confirmed by playtest: it turned toward the
				# headboard instead of the laptop).
				var parent_yaw: float = get_parent().rotation.y
				var desired_yaw := atan2(-dir.x, -dir.z) - parent_yaw
				var desired_pitch := asin(clampf(dir.y, -1.0, 1.0))
				var ease_t: float = 1.0 - exp(-focus_assist_ease_speed * delta)
				_target_yaw = lerp_angle(_target_yaw, desired_yaw, ease_t)
				_target_pitch = lerp_angle(_target_pitch, desired_pitch, ease_t)

	var t: float = 1.0 - exp(-look_damping * delta)
	rotation.y = lerp_angle(rotation.y, _target_yaw, t)
	pitch_pivot.rotation.x = lerp_angle(pitch_pivot.rotation.x, _target_pitch, t)
