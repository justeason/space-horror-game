extends Node3D
## Coordinates "using the Control Room workstation": a full sit-down
## transition (not just a camera zoom) that moves the player into a
## seated position at the console, then a matching get-up transition on
## Escape. Conceptually the same family of techniques already proven by
## scripts/player/sleep_state.gd (the bed's sit-down/get-up, and its
## camera-aim math), deliberately REIMPLEMENTED here as its own small,
## independent copy rather than a shared dependency, so this system can
## never risk regressing the already-tested bed/laptop behavior.
##
## IMPORTANT GEOMETRY TRADE-OFF (read before touching sit_position):
## the existing SittingPose (scripts/player/player_body.gd) was authored
## for the BED, where the legs extend in the same direction the camera
## faces (both toward sitting_world_yaw_degrees's convention). At the
## workstation, the screen sits only ~0.3-0.6m in front of the seat but
## the authored leg length is ~0.88m -- facing the body the same
## direction as the camera would drive the feet THROUGH the back wall
## (confirmed numerically: at any reasonable seat distance, foot_z lands
## past the wall). So this script deliberately lets the frozen body
## yaw (player_body.gd's existing default, unchanged, legs extend into
## the OPEN room behind the chair) diverge from the camera's own aim
## (which independently faces the screen, exactly like the existing
## aim-direction technique already used for the bed/laptop editor zoom).
## In first person this is not visible in practice (you don't see your
## own body's facing direction, and the legs never intrude into frame
## at the screen-level camera pitch used here -- same invariant already
## verified for ordinary standing/sitting composition). Documented
## here, not silently chosen, in case a future skeletal rig (Milestone
## 2) wants to resolve this more fully with a dedicated desk-chair pose.
##
## Navigation while seated is entirely key-driven (number keys 1-6 pick
## a section, 0 goes Home, R runs the current section's context action,
## Esc exits) -- see scripts/ui/workstation_screen.gd's class doc
## comment for why this deliberately avoids mouse-click-on-3D-screen
## mapping.

@export var player_path: NodePath
@export var free_body_path: NodePath
@export var global_free_move_path: NodePath
@export var interaction_controller_path: NodePath
@export var look_controller_path: NodePath
@export var player_body_path: NodePath
@export var workstation_console_path: NodePath
@export var workstation_screen_path: NodePath

## World-space seat position (eye point) -- reuses the EXACT same eye
## height as the bed's own sit_position (1.2) so the existing
## SittingPose geometry (authored once, for that height) is valid here
## without any recomputation. See the class doc comment for why x/z
## were chosen the way they were (hip/legs end up over open floor, not
## the desk).
##
## z moved from -0.65 to -0.45 (0.2m back from the screen, which sits
## at world z=-0.90): at the original 0.25m eye-to-screen distance the
## 0.576m-wide monitor already filled essentially the entire 72-degree
## vertical FOV (player feedback: "can only see the monitor"), leaving
## no margin for anything else -- basic FOV geometry (visible height at
## distance d = 2*d*tan(fov/2)) shows the monitor's own height (0.36m)
## only just fit the frame at 0.25m, with zero room for the switch row
## below it. At 0.45m there's real margin. See begin_use()'s pitch aim
## below for the matching small downward tilt that brings the switches
## into that margin.
@export var sit_position: Vector3 = Vector3(0.0, 1.2, -0.45)
@export var sit_duration: float = 0.8
@export var stand_rise_duration: float = 0.4
@export var stand_finish_duration: float = 0.35

var _player: Node3D
var _free_body: Node
var _global_free_move: Node
var _interaction_controller: Node
var _look_controller: Node3D
var _pitch_pivot: Node3D
var _player_body: Node
var _console: Node
var _screen: Node

var _in_use: bool = false
var _transitioning: bool = false
var _pre_sit_position: Vector3
var _tween: Tween

# scripts/ui/workstation_screen.gd's Section enum order, mirrored here
# as plain ints so this script never needs to reach into another
# script's enum (GDScript enums are plain ints under the hood).
const SECTION_HOME := 0
const SECTION_OVERVIEW := 1
const SECTION_WORK_ORDERS := 2
const SECTION_DIAGNOSTICS := 3
const SECTION_SURVEILLANCE := 4
const SECTION_SAVE_LOAD := 5
const SECTION_SETTINGS := 6


func _ready() -> void:
	_player = get_node(player_path)
	_free_body = get_node(free_body_path)
	_global_free_move = get_node(global_free_move_path)
	_interaction_controller = get_node(interaction_controller_path)
	_look_controller = get_node(look_controller_path)
	_pitch_pivot = _look_controller.get_node("PitchPivot")
	_player_body = get_node(player_body_path)
	_console = get_node(workstation_console_path)
	_screen = get_node(workstation_screen_path)


func is_in_use() -> bool:
	return _in_use


## Called by workstation_console.gd's interact(). No-op while already
## seated or mid-transition, so a repeated click (or a click that
## arrives while the stand-up tween is still finishing) can never start
## a second, overlapping transition.
func begin_use() -> void:
	if _in_use or _transitioning:
		return
	_transitioning = true
	_pre_sit_position = _player.global_position

	_free_body.set_active(false)
	_global_free_move.mirror_enabled = false
	_interaction_controller.interactions_enabled = false
	_look_controller.escape_enabled = false
	_look_controller.input_enabled = false

	_kill_tween()
	# Aimed slightly below the screen's own center (not dead-center) so
	# the seated view's lower frame margin includes some of the desk's
	## physical switch row instead of framing the monitor alone -- see
	# sit_position's doc comment above for the matching distance change
	# this pairs with. The monitor is still the dominant, in-focus
	# element (this is a few degrees of tilt, not a reframe toward the
	# desk).
	var aim_point: Vector3 = _console.get_screen_global_position() + Vector3(0.0, -0.1, 0.0)
	var dir: Vector3 = (aim_point - sit_position)
	var parent_yaw: float = _player.rotation.y
	var desired_yaw: float = atan2(-dir.x, -dir.z) - parent_yaw
	var desired_pitch: float = asin(clampf(dir.y / dir.length(), -1.0, 1.0))
	var current_yaw: float = _look_controller.rotation.y
	var yaw_delta: float = wrapf(desired_yaw - current_yaw, -PI, PI)

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_player, "global_position", sit_position, sit_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_look_controller, "rotation:y", current_yaw + yaw_delta, sit_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_pitch_pivot, "rotation:x", desired_pitch, sit_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.chain().tween_callback(_on_sit_settled)


## The pose swap happens only once fully settled -- same established
## timing as scripts/player/sleep_state.gd's bed sit-down (not a new
## technique), so this is consistent with the one visual precedent
## already shipped and confirmed working.
func _on_sit_settled() -> void:
	_look_controller._target_yaw = _look_controller.rotation.y
	_look_controller._target_pitch = _pitch_pivot.rotation.x
	_player_body.set_sitting(true)
	_in_use = true
	_transitioning = false
	_screen.show_section(SECTION_HOME)


## The dedicated "get up" action (Esc while seated). Mirrors
## sleep_state.gd's end_sitting() rise-then-swap-then-settle staging
## (rise partway, swap pose, finish rising, THEN walk back to wherever
## the player approached from) -- proportionate for standing up from a
## desk chair, not the bed's full leg-swing sequence (that would be
## disproportionate here and risks the "competing animation framework"
## this task was told to avoid).
func end_use() -> void:
	if not _in_use or _transitioning:
		return
	_transitioning = true
	_in_use = false
	_interaction_controller.interactions_enabled = true
	_look_controller.escape_enabled = true
	_look_controller.input_enabled = true

	_kill_tween()
	var standing_y: float = _pre_sit_position.y
	var mid_rise_y: float = lerp(sit_position.y, standing_y, 0.6)

	_tween = create_tween() # strictly sequential: rise, swap, finish rising, walk back
	_tween.tween_property(_player, "global_position:y", mid_rise_y, stand_rise_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func(): _player_body.set_sitting(false))
	_tween.tween_property(_player, "global_position:y", standing_y, stand_rise_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_player, "global_position", _pre_sit_position, stand_finish_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_on_stand_settled)


func _on_stand_settled() -> void:
	_free_body.sync_to_eye_position(_pre_sit_position)
	_global_free_move.mirror_enabled = true
	_free_body.set_active(true)
	_transitioning = false


func _unhandled_input(event: InputEvent) -> void:
	if not _in_use:
		return
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		end_use()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_0:
			_screen.show_section(SECTION_HOME)
		KEY_1:
			_screen.show_section(SECTION_OVERVIEW)
		KEY_2:
			_screen.show_section(SECTION_WORK_ORDERS)
		KEY_3:
			_screen.show_section(SECTION_DIAGNOSTICS)
		KEY_4:
			_screen.show_section(SECTION_SURVEILLANCE)
		KEY_5:
			_screen.show_section(SECTION_SAVE_LOAD)
		KEY_6:
			_screen.show_section(SECTION_SETTINGS)
		KEY_R:
			_screen.run_action()
		KEY_LEFT:
			if _screen.current_section() == SECTION_OVERVIEW:
				_screen.select_prev_room()
		KEY_RIGHT:
			if _screen.current_section() == SECTION_OVERVIEW:
				_screen.select_next_room()
		_:
			return
	get_viewport().set_input_as_handled()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
