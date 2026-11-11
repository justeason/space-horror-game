extends Node3D
## Minimal, reversible first-person "sit on the bed" + "use laptop" +
## "edit log" state machine, triggered by the bunk interactable
## (scripts/interactables/bunk.gd) and the laptop coordinator
## (scripts/player/laptop_view.gd, scripts/ui/session_log_screen.gd).
##
## This does NOT implement sleep or day-advancement. No day/time or
## task-history/save-data system exists anywhere in this project yet --
## so there is nothing for an explicit "sleep" action to invoke, and the
## daily log is prototype/sample data only. Sitting down here is purely
## positional/visual. The one explicit hook point for a future day
## system is marked below with a TODO; nothing is invented here to fill
## it.
##
## State machine (deliberately linear, not a bag of unrelated
## booleans):
##   AWAKE <-> SITTING <-> LAPTOP <-> EDITING
## F only steps one link at a time (cannot close the laptop while
## EDITING -- end editing first) so no single key ever has to decide
## what to do about two nested sub-systems at once. The E key is the
## one exception: it gets up from ANY of SITTING, LAPTOP, or EDITING in
## one press (end_sitting() tears down whatever sub-state is active --
## folding the laptop shut and saving any in-progress entry -- before
## starting the stand-up tween), since requiring the player to manually
## close the laptop before leaving the bed was explicitly reported as
## unwanted friction. Interrupting mid-transition (calling begin/end
## again, or starting a new transition while a tween is still running)
## always kills any in-flight tween first, so the state can never get
## stuck with movement permanently disabled.
##
## Body representation: the bed interaction now uses a dedicated SITTING
## pose (scripts/player/player_body.gd's SittingPose), not the older
## LYING pose -- lying flat put the torso through the mattress and gave
## a bad angle on the laptop (see the "next iteration" report). LYING is
## preserved as a separate, distinct pose/state capability in
## player_body.gd for any future "actually go to sleep" mechanic; this
## state machine simply no longer drives it from the bed interaction.
##
## Keyboard routing while EDITING: this script owns ALL keyboard routing
## itself -- the log lives entirely on the laptop's physical 3D screen
## (a SubViewport, not a camera-space 2D overlay), so there is no
## automatic Godot GUI-focus interception happening in THIS viewport to
## protect typing. Esc and Ctrl+S are intercepted directly; every other
## key (including E/F/T) is forwarded into the laptop screen's own
## SubViewport instead of being treated as a gameplay shortcut.
##
## Editor zoom (horror-gameplay requirement): entering EDITING also eases
## the player's eye position partway toward the laptop screen (see
## _start_editor_zoom()) so the physical screen is big enough to read,
## WITHOUT teleporting and WITHOUT leaving the player "trapped" -- Esc
## always eases back out to ordinary sitting-with-laptop framing in the
## same way it exits editing, so a suspicious noise can be investigated
## immediately: Esc, then free-look, while remaining seated.

enum State { AWAKE, SITTING, LAPTOP, EDITING, SLEEPING }

@export var player_path: NodePath
@export var free_body_path: NodePath
@export var interaction_controller_path: NodePath
@export var global_free_move_path: NodePath = ^"../GlobalFreeMove"
@export var look_controller_path: NodePath
@export var player_body_path: NodePath
@export var laptop_view_path: NodePath
@export var prompt_label_path: NodePath
## Approved Decision A.1 (sleep/day transition): the DayPlan node whose
## reset_for_new_day() runs once the eyes are fully closed. Optional on
## purpose -- leave unset in any test/scene that doesn't need a day
## transition, and begin_sleep() simply skips the reset.
@export var day_plan_path: NodePath
## A full-screen black ColorRect in Player/HUD, alpha 0 by default.
## Deliberately framed and timed as eyelids closing (quick, with a held
## dark beat), not a slow generic scene-transition fade -- Approved
## Decision A.1: "do not use a generic fade as the primary effect."
@export var eyes_overlay_path: NodePath
## A small flavor-text label in Player/HUD for the automatic wake-up
## wristwatch glance (Section 10/11: "checked automatically, not a
## click interaction"). No real clock/calendar backs this text -- see
## MILESTONE1_DESIGN.md Open Question 1 (minimal reset, no time system
## yet).
@export var wristwatch_label_path: NodePath

@export var eyes_close_duration: float = 0.35
@export var eyes_closed_hold_duration: float = 0.9
@export var eyes_open_duration: float = 0.35
@export var wristwatch_glance_duration: float = 2.2

## World-space eye position while sitting on the bed, and the look pitch
## (in degrees; POSITIVE = looking up) the view eases to on the way
## down -- a shallow, natural "looking toward the lap/room" angle, not
## the old lying pose's "staring at the ceiling" pitch. Mouse look is
## NOT locked at any point after that, including while editing the log --
## the laptop is a world object resting on the lap anchor, never camera-
## attached, so turning your head never fights it. A soft auto-return
## eases the view back toward the laptop after a short idle period while
## just looking at it (look_controller.gd's focus_assist_enabled).
@export var sit_position: Vector3 = Vector3(5.0, 1.5, -1.0)
@export var sit_look_pitch_degrees: float = -12.0
## Local yaw (degrees) the CAMERA eases to as part of sitting down, so
## the player ends up facing the same direction their now-seated body
## is frozen facing (see player_body.gd's sitting_world_yaw_degrees,
## which this must match -- both exist because the camera's yaw lives
## on look_controller.gd/LookPivot while the body's frozen yaw lives on
## player_body.gd, two different nodes with no direct reference to each
## other's export). Without this, a player who approached the bed from
## an odd angle would sit down facing a direction that doesn't match
## where their legs/the laptop actually are.
@export var sit_look_yaw_degrees: float = 0.0
@export var transition_duration: float = 1.1

## Get-up sequence stage durations (see end_sitting()'s "STAGED GET-UP"
## block). Named after the 7-stage breakdown this was designed against:
## prepare -> lead leg swings down -> (foot "planting" is simply that
## tween completing, not a separate one -- see player_body.gd's
## swing_leg_to_floor() doc comment) -> second leg swings down -> stance
## settles -> push up to standing -> finish/walk to the pre-sleep spot.
## Sums to roughly 2.3s, inside the requested ~1.7-2.4s feel.
@export var get_up_prepare_duration: float = 0.3
@export var get_up_leg_swing_duration: float = 0.5
@export var get_up_stance_settle_duration: float = 0.25
@export var get_up_rise_duration: float = 0.4
@export var get_up_finish_duration: float = 0.35
## Round 29: which way the seated body turns (degrees, added to its seated
## yaw) and how far the seat eye slides while the legs swing down during
## get-up -- authored for this bunk like sit_position: the bunk's open
## long edge is on its west (-X) side.
@export var get_up_turn_degrees: float = -90.0
## Round 31 Priority 6: lying down to sleep.
@export var lie_down_duration: float = 1.1
@export var sit_up_duration: float = 1.0
@export var lie_look_pitch_degrees: float = 55.0
@export var mattress_top_y: float = 0.535
@export var lie_position_xz: Vector2 = Vector2(5.0, -1.1)
var _lying: bool = false
@export var get_up_edge_offset: Vector3 = Vector3(-0.28, 0.0, 0.0)
## ...and how much further the eye travels out over the planted feet as
## it rises (stage 6), so the standing body never appears inside the bunk.
@export var get_up_rise_offset: Vector3 = Vector3(-0.35, 0.0, 0.0)
var _turn_tween: Tween

## Editor zoom: how far (0..1) from the ordinary sitting eye position
## toward the laptop screen's actual current position the view eases
## when editing begins. Deliberately a FRACTION of the real distance to
## the physical screen, recomputed from its live global_position each
## time editing starts, rather than a hand-placed second eye position --
## so it automatically stays correct if the sitting pose or laptop
## geometry is ever retuned, and automatically never overshoots past
## the screen regardless of exactly how far away it is.
## Fixed physical distance (meters) the camera settles at ALONG the
## screen's own outward normal once editing begins -- not a fraction of
## the straight-line distance from the sitting eye position (the old
## editor_zoom_fraction approach), which only pointed the camera AT the
## screen's center without ever aligning it to face the screen's actual
## plane, producing a keystoned/tilted-looking screen (confirmed via
## diag_screen_tilt.gd: ~21.6 degrees of misalignment, measured, not
## guessed). Anchoring the final eye position to screen_center +
## normal*editor_view_distance guarantees a true frontal view with zero
## keystone regardless of how the laptop itself is tilted. Chosen close
## to the previous effective distance (~0.20m) so the "zoomed in enough
## to read" feel is preserved.
@export var editor_view_distance: float = 0.2
@export var editor_zoom_duration: float = 0.45

var _player: Node
var _free_body: Node
var _interaction_controller: Node
var _global_free_move: Node
var _look_controller: Node
var _player_body: Node
var _laptop_view: Node
var _prompt_label: Label
var _day_plan: Node
var _eyes_overlay: ColorRect
var _wristwatch_label: Label
var _look_pivot: Node3D
var _pitch_pivot: Node3D

var _state: State = State.AWAKE
var _pre_sleep_eye_position: Vector3
var _tween: Tween
var _zoom_tween: Tween
var _laptop_aim_tween: Tween
var _eyes_tween: Tween
var _wristwatch_timer: SceneTreeTimer
## Set by scripts/interactables/bunk.gd each time the player crosses
## its interact_range boundary. Only consulted while AWAKE (to show
## the "E: Sit Down" prompt and allow the E key to work) -- see
## _update_prompt() and _unhandled_input() below.
var _near_bed: bool = false
## Alternates which leg leads the get-up sequence each time the player
## stands up (part B of the M9 get-up spec) -- flipped at the start of
## every end_sitting() call, independent of how that call resolves.
var _next_leg_leads_right: bool = true


func _ready() -> void:
	_player = get_node(player_path)
	_free_body = get_node(free_body_path)
	_interaction_controller = get_node(interaction_controller_path)
	_global_free_move = get_node(global_free_move_path)
	_look_controller = get_node(look_controller_path)
	_player_body = get_node(player_body_path)
	_laptop_view = get_node(laptop_view_path)
	_prompt_label = get_node(prompt_label_path)
	_look_pivot = _player.get_node("LookPivot")
	_pitch_pivot = _look_pivot.get_node("PitchPivot")
	_day_plan = get_node_or_null(day_plan_path)
	_eyes_overlay = get_node_or_null(eyes_overlay_path)
	_wristwatch_label = get_node_or_null(wristwatch_label_path)
	# Round 34: the laptop's on-screen app bar drives the same actions.
	var ls: Node = _laptop_view.get("_log_screen")
	if ls != null and ls.has_signal(&"app_requested"):
		ls.app_requested.connect(_on_laptop_app)

	_update_prompt()


# ======================================================================
# Round 34 Priorities 2/3/5/6.
# ======================================================================
var laptop_hovered: bool = false
var _prompt_tick: float = 0.0


func _process(delta: float) -> void:
	if _state == State.SITTING and not _lying:
		var h: bool = _ray_laptop(false) != Vector2(-2, -2)
		if h != laptop_hovered:
			laptop_hovered = h
			_update_prompt()
	elif laptop_hovered:
		laptop_hovered = false
	# Round 35: hover feedback on the open laptop's screen (reticle).
	if _state == State.LAPTOP:
		var uv: Vector2 = _ray_laptop(false)
		if uv.x >= 0.0:
			_laptop_view._log_screen.hover_at(uv)
	_prompt_tick += delta
	if _prompt_tick >= 1.0 and _state == State.SITTING:
		_prompt_tick = 0.0
		_update_prompt()


func _laptop_node() -> Node:
	return _laptop_view.get("_laptop")


## Casts the click ray (reticle = screen centre, or the visible mouse
## cursor while editing). Returns the normalized SCREEN coordinates if it
## hits the open screen, (-1,-1) if it hits the laptop elsewhere, and
## (-2,-2) if it misses the laptop.
func _ray_laptop(use_cursor: bool, cursor_pos: Vector2 = Vector2(-1, -1)) -> Vector2:
	var cam: Camera3D = _interaction_controller as Camera3D
	var lap: Node = _laptop_node()
	if cam == null or lap == null or lap.get("body_click") == null:
		return Vector2(-2, -2)
	var from: Vector3
	var dir: Vector3
	if use_cursor and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var mp: Vector2 = cursor_pos if cursor_pos.x >= 0.0 else get_viewport().get_mouse_position()
		from = cam.project_ray_origin(mp)
		dir = cam.project_ray_normal(mp)
	else:
		from = cam.global_position
		dir = -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.5, 16)
	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return Vector2(-2, -2)
	if hit["collider"] == lap.screen_click:
		var uv: Vector2 = lap.screen_uv(hit["position"], cam.global_transform.basis.x)
		return uv if uv.x >= 0.0 else Vector2(-1, -1)
	if hit["collider"] == lap.body_click:
		return Vector2(-1, -1)
	return Vector2(-2, -2)


## A real left click while on the bunk.
func handle_click(use_cursor: bool = false, cursor_pos: Vector2 = Vector2(-1, -1)) -> bool:
	match _state:
		State.SITTING:
			if not _lying and _ray_laptop(false) != Vector2(-2, -2):
				# Round 39: clicking the laptop picks it up, opens it AND
				# zooms in on its desktop (a proper close-up of the screen).
				open_laptop(true)
				return true
		State.LAPTOP, State.EDITING:
			var uv: Vector2 = _ray_laptop(_state == State.EDITING or use_cursor, cursor_pos)
			if uv.x >= 0.0:
				var was_viewing: bool = _state == State.LAPTOP
				_laptop_view._log_screen.click_at(uv)
				# Round 39: a click on the open screen that didn't press
				# anything (an app focuses / Close closes) zooms in on it.
				if was_viewing and _state == State.LAPTOP:
					begin_editing()
				return true
	return false


func _on_laptop_app(app: StringName) -> void:
	match app:
		&"log", &"focus":
			# Round 38: zoom in on the chosen app (the whole computer).
			begin_editing()
		&"back":
			end_editing()
		&"save":
			_laptop_view.save_entry()
		&"close":
			close_laptop()


func _task_message(text: String) -> void:
	var ml: Label = _prompt_label.get_parent().get_node_or_null("TaskMessageLabel") if _prompt_label != null else null
	if ml != null:
		preload("res://scripts/ui/hud_message.gd").show(ml, get_instance_id(), text, 3.0)


## Round 34 Priority 2: a NEW DAY / NEW GAME starts here -- lying in the
## bunk, eyes closed, then the eyes open (the existing wake: lying, the
## wristwatch glance, E sits up and gets up). Never used for loading a
## mid-day save (that restores the saved position).
func start_day_in_bed() -> void:
	_kill_tween()
	_kill_zoom_tween()
	_kill_eyes_tween()
	_state = State.SLEEPING
	_lying = true
	_pre_sleep_eye_position = Vector3(sit_position.x - 1.0, 1.6, sit_position.z + 0.7)
	_free_body.set_active(false)
	_free_body.sync_to_eye_position(_pre_sleep_eye_position)
	_interaction_controller.interactions_enabled = false
	_global_free_move.mirror_enabled = false
	_look_controller.input_enabled = false
	if _player_body.has_method("set_seat_style"):
		_player_body.set_seat_style(true)
	_player_body.set_lying(true, 0.05)
	_player.global_position = _lying_eye_position()
	_look_pivot.rotation.y = deg_to_rad(sit_look_yaw_degrees)
	_look_pivot._target_yaw = _look_pivot.rotation.y
	_pitch_pivot.rotation.x = deg_to_rad(lie_look_pitch_degrees)
	_look_pivot._target_pitch = deg_to_rad(lie_look_pitch_degrees)
	_update_prompt()
	_eyes_tween = create_tween()
	if _eyes_overlay != null:
		_eyes_overlay.color.a = 1.0
		_eyes_tween.tween_interval(eyes_closed_hold_duration)
		_eyes_tween.tween_property(_eyes_overlay, "color:a", 0.0, eyes_open_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_eyes_tween.tween_interval(eyes_closed_hold_duration + eyes_open_duration)
	_eyes_tween.tween_callback(_on_wake)


func is_sitting() -> bool:
	return _state != State.AWAKE


func is_laptop_open() -> bool:
	return _state == State.LAPTOP or _state == State.EDITING


func is_editing() -> bool:
	return _state == State.EDITING


func is_near_bed() -> bool:
	return _near_bed


## Called by scripts/interactables/bunk.gd whenever the player crosses
## its proximity boundary.
func set_bed_proximity(near: bool) -> void:
	_near_bed = near
	_update_prompt()


## Called by the bunk interactable's interact(). No-op unless currently
## AWAKE (re-clicking the bunk while already sitting -- or with the
## laptop open -- does nothing; see end_sitting() for the separate,
## dedicated way to get up).
func begin_sitting() -> void:
	if _state != State.AWAKE:
		return
	_state = State.SITTING
	_pre_sleep_eye_position = _player.global_position

	# Movement and other interactions are suppressed for the whole
	# sequence, not just once it settles -- otherwise the player could
	# walk or interact with something else mid-transition. Also stop
	# GlobalFreeMove's own per-frame position mirror, or it would snap
	# the player back to the stationary free body every tick and fight
	# this tween.
	_free_body.set_active(false)
	_interaction_controller.interactions_enabled = false
	_global_free_move.mirror_enabled = false

	_kill_tween()
	_kill_zoom_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_player, "global_position", sit_position, transition_duration)
	_tween.tween_property(_pitch_pivot, "rotation:x", deg_to_rad(sit_look_pitch_degrees), transition_duration)
	# Plain float tweening on rotation.y would take the raw numeric path,
	# not the shortest angular one -- harmless near 0 but the player's
	# accumulated look yaw is an unbounded, never-wrapped value (see
	# look_controller.gd's _target_yaw), so a player who has turned
	# around several times could otherwise see the camera spin through
	# multiple full revolutions here instead of easing smoothly. Always
	# tween to the nearest raw value that represents the same final
	# angle.
	var current_yaw: float = _look_pivot.rotation.y
	var yaw_delta: float = wrapf(deg_to_rad(sit_look_yaw_degrees) - current_yaw, -PI, PI)
	_tween.tween_property(_look_pivot, "rotation:y", current_yaw + yaw_delta, transition_duration)
	_tween.chain().tween_callback(_on_sit_settled)
	# Round 29 Priority 7: visual only -- the body eases into the seated
	# pose while the camera travels (set_sitting() timing unchanged).
	if _player_body.has_method("set_seat_style"):
		_player_body.set_seat_style(true)
	if _player_body.has_method("begin_sit_down"):
		_player_body.begin_sit_down(sit_position, transition_duration)
	_update_prompt()

	# TODO(day system): once a day/time system exists, this is where an
	# explicit, separate "go to sleep" confirmation (not just sitting
	# down, and not just writing in the log) would invoke it.
	# Deliberately not implemented here.


## The dedicated "get up" action (distinct from the bunk's own
## interact(), which only sits down). Valid from SITTING, LAPTOP, or
## EDITING -- getting up no longer requires manually closing the laptop
## first. If the laptop is open (or being edited), it is folded shut
## first (laptop_view.close() saves the in-progress entry via its
## existing end_editing() path before hiding the editor, so nothing
## typed is silently discarded), then returned to its resting spot on
## the bed so it is never left floating at the lap position.
func end_sitting() -> void:
	if _state == State.AWAKE or _state == State.SLEEPING:
		return
	if _lying:
		_sit_up_then_get_up()
		return
	_begin_get_up()


## Round 31: from lying, sit back up (crossfade over the whole move), then
## run the ordinary staged get-up.
func _sit_up_then_get_up() -> void:
	_lying = false
	_interaction_controller.interactions_enabled = false
	_player_body.set_sitting(true, sit_up_duration)
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_player, "global_position", sit_position, sit_up_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_pitch_pivot, "rotation:x", deg_to_rad(sit_look_pitch_degrees), sit_up_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_pivot._target_pitch = deg_to_rad(sit_look_pitch_degrees)
	_tween.chain().tween_callback(func():
		_interaction_controller.interactions_enabled = true
		_begin_get_up())


func is_lying_in_bed() -> bool:
	return _lying


## Player (eye) position that rests the lying body's pelvis on the mattress.
func _lying_eye_position() -> Vector3:
	var hips: Node3D = _player_body.get_node_or_null("LyingPose/Hips")
	var hy: float = hips.position.y if hips != null else -0.65
	return Vector3(lie_position_xz.x, mattress_top_y + 0.02 - hy, lie_position_xz.y)


func _begin_get_up() -> void:

	_kill_zoom_tween()
	_kill_laptop_aim_tween()
	if _laptop_view.is_open():
		_laptop_view.close()
	_laptop_view.return_to_rest()
	if _player_body.has_method("set_seated_head_follow"):
		_player_body.set_seated_head_follow(true)
	_look_controller.focus_assist_enabled = false
	_look_controller.escape_enabled = true
	# In case the player got up directly from EDITING (bypassing
	# end_editing() entirely), make sure mouse-look is never left
	# locked once standing.
	_look_controller.input_enabled = true

	_state = State.SITTING
	_kill_tween()
	# Interrupting mid-sequence (e.g. E pressed again while already
	# getting up) must never leave a stale half-swung leg or half-leaned
	# torso behind when the new sequence starts -- player_body.gd's own
	# tweens aren't owned by _tween above, so killing that alone would
	# not stop them.
	_player_body.reset_get_up_pose()

	# ============================================================
	# STAGED GET-UP (M9): a sequential 7-stage transition replacing the
	# old "rise straight up, swap pose, walk" transform-offset trick.
	# The legs now visibly swing off the bed and plant on the floor
	# (player_body.gd's swing_leg_to_floor(), a 2-bone IK solve against
	# a real floor-contact target -- see that script's doc comment) BEFORE
	# any upward motion begins, and the two legs move one at a time, not
	# simultaneously/identically, alternating which one leads each time
	# (_next_leg_leads_right). The pose swap to StandingPose still has to
	# happen at some point (there is no shared rig to animate through
	# the swap itself -- the current static-CSG-pose architecture's
	# fundamental limit, documented in the M9 report's architecture
	# section) -- it happens during stage 6 once the eye has already
	# risen most of the way to standing height, same as the previous
	# round's rise-then-swap-then-continue technique, to avoid re-sinking
	# StandingPose's feet below the floor (StandingPose is authored
	# assuming a standing-height origin -- swapping while the eye is
	# still near seated height was the earlier "body sinks into the
	# mattress" bug).
	# ============================================================
	var lead_right: bool = _next_leg_leads_right
	_next_leg_leads_right = not _next_leg_leads_right

	var base_pos: Vector3 = _player.global_position
	var standing_y: float = _pre_sleep_eye_position.y
	var mid_rise_y: float = lerp(base_pos.y, standing_y, 0.7)

	_tween = create_tween() # strictly sequential: every stage waits for the last.
	# Stage 1 (prepare to rise): torso leans forward.
	_tween.tween_callback(_player_body.lean_forward.bind(0.6, get_up_prepare_duration))
	_tween.tween_interval(get_up_prepare_duration)
	# Stage 2+3 (lead leg swings down and plants): "planting" is simply
	# this tween completing -- see player_body.gd's doc comment on why
	# there is no separately simulated contact event in this
	# architecture.
	_tween.tween_callback(_player_body.swing_leg_to_floor.bind(lead_right, get_up_leg_swing_duration))
	_tween.tween_interval(get_up_leg_swing_duration)
	# Stage 4 (second leg follows, not simultaneously).
	_tween.tween_callback(_player_body.swing_leg_to_floor.bind(not lead_right, get_up_leg_swing_duration))
	_tween.tween_interval(get_up_leg_swing_duration)
	# Stage 5 (stable seated stance): both feet planted, torso leans a
	# bit further forward over them, preparing for the push-up.
	_tween.tween_callback(_player_body.lean_forward.bind(1.0, get_up_stance_settle_duration))
	_tween.tween_interval(get_up_stance_settle_duration)
	# Stage 6 (push up to standing): rises most of the way in place
	# first (weight shifting from the bed to the now-planted feet), THEN
	# swaps to StandingPose, THEN finishes rising -- see the block
	# comment above for why the swap can't happen at the very start of
	# this stage.
	# Round 29: rise FORWARD over the planted feet (beside the bunk), not
	# straight up out of the mattress -- same stage durations.
	var over_feet: Vector3 = base_pos + get_up_edge_offset + get_up_rise_offset
	_tween.tween_property(_player, "global_position", Vector3(lerp(base_pos.x + get_up_edge_offset.x, over_feet.x, 0.6), mid_rise_y, lerp(base_pos.z + get_up_edge_offset.z, over_feet.z, 0.6)), get_up_rise_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func(): _player_body.set_sitting(false))
	_tween.tween_property(_player, "global_position", Vector3(over_feet.x, standing_y, over_feet.z), get_up_rise_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Stage 7 (finish standing): walk, at the now-correct standing eye
	# height, from beside the bed to wherever the player was before
	# sitting down, restoring normal movement once settled.
	_tween.tween_property(_player, "global_position", _pre_sleep_eye_position, get_up_finish_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_on_stand_settled)

	# A SEPARATE Tween (not interleaved into the sequential one above)
	# for the camera-only reset, so it can run in parallel across the
	# WHOLE transition without fighting the ambiguity of mixing
	# parallel() / chain() with multiple sequential position segments
	# on the same tween. In case the player got up directly from
	# EDITING, the camera may still carry a nonzero local offset from
	# the editor zoom (see _start_editor_zoom()) -- _kill_zoom_tween()
	# above only stops that tween where it was, it does not reset the
	# offset. Ease it back to zero in step with the stand-up motion
	# rather than leaving the final standing view subtly mispositioned.
	var total_duration: float = get_up_prepare_duration + get_up_leg_swing_duration * 2.0 + get_up_stance_settle_duration + get_up_rise_duration + get_up_finish_duration
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(_look_pivot, "position", Vector3.ZERO, total_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Round 29 Priority 2/7: swing round to the bunk's OPEN edge while the
	# legs come down (parallel to stages 1-4, same total duration), so the
	# feet plant on the floor beside the bunk instead of through the
	# mattress. Seated body yaw + a short slide of the seat eye to the edge;
	# the camera's look direction stays the player's own.
	var swing_time: float = get_up_prepare_duration + get_up_leg_swing_duration * 2.0
	_turn_tween = create_tween()
	_turn_tween.set_parallel(true)
	_turn_tween.tween_property(_player_body, "rotation:y", deg_to_rad(sitting_world_yaw_for_get_up() + get_up_turn_degrees), swing_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_turn_tween.tween_property(_player, "global_position", base_pos + get_up_edge_offset, swing_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_update_prompt()


## The dedicated "go to sleep" action (Approved Decision A.1). Only
## valid from plain SITTING -- not LAPTOP/EDITING, matching the
## existing "F only steps one link at a time" philosophy (close the
## laptop first; G is not wired in those states, see _unhandled_input()).
##
## Deliberately reuses the existing SittingPose and the existing,
## already-tested end_sitting()/get-up sequence rather than inventing a
## parallel "lie down to sleep" animation: the player closes their eyes
## while already reclined on the bed, and waking simply leaves them
## SITTING exactly as before -- getting up afterward is ordinary E,
## unchanged. This keeps the new sleep transition small and avoids any
## broader character-pose work.
##
## The eyes-closing effect is deliberately short and framed as eyelids
## (quick ease-in -> held dark -> quick ease-out), not a slow generic
## scene fade (Approved Decision A.1). DayPlan's reset happens at the
## darkest point, invisibly -- the minimal reset from Option A: no
## calendar, no day counter, no simulation-time system.
func begin_sleep() -> void:
	if _state != State.SITTING:
		return
	# Round 34 Priority 3: sleep only once the day's shift has ended.
	if _day_plan != null and _day_plan.has_method("can_sleep") and not _day_plan.can_sleep():
		_task_message(_day_plan.sleep_refusal())
		return
	_state = State.SLEEPING
	_interaction_controller.interactions_enabled = false
	_free_body.set_active(false)
	_look_controller.input_enabled = false
	_update_prompt()

	_kill_eyes_tween()
	_eyes_tween = create_tween()
	# Round 31 Priority 6: lie down on the mattress FIRST (skeleton
	# crossfade over the whole move, camera easing to the lying eye and
	# looking up), then the unchanged eyes-closing sequence. Waking leaves
	# the player lying; E sits up and gets up.
	if not _lying:
		_lying = true
		var lie_eye: Vector3 = _lying_eye_position()
		_player_body.set_lying(true, lie_down_duration)
		var lt: Tween = create_tween()
		lt.set_parallel(true)
		lt.tween_property(_player, "global_position", lie_eye, lie_down_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lt.tween_property(_pitch_pivot, "rotation:x", deg_to_rad(lie_look_pitch_degrees), lie_down_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_look_pivot._target_pitch = deg_to_rad(lie_look_pitch_degrees)
		_eyes_tween.tween_interval(lie_down_duration)
	if _eyes_overlay != null:
		_eyes_tween.tween_property(_eyes_overlay, "color:a", 1.0, eyes_close_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		_eyes_tween.tween_interval(eyes_close_duration)
	_eyes_tween.tween_interval(eyes_closed_hold_duration)
	_eyes_tween.tween_callback(_on_eyes_fully_closed)
	if _eyes_overlay != null:
		_eyes_tween.tween_property(_eyes_overlay, "color:a", 0.0, eyes_open_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_eyes_tween.tween_interval(eyes_open_duration)
	_eyes_tween.tween_callback(_on_wake)


func is_sleeping() -> bool:
	return _state == State.SLEEPING


## Round 34: emitted when the player is awake in the bunk after a sleep
## that advanced the day (SaveGame autosaves here).
signal woke_into_new_day
var _day_advanced: bool = false


func _on_eyes_fully_closed() -> void:
	if _day_plan != null:
		_day_plan.reset_for_new_day()
		_day_advanced = true


## Eyes open, still sitting on the bed -- unchanged from before sleep
## except for DayPlan's reset already having happened in the dark.
## Mirrors the automatic wristwatch glance (Section 10/11: "checked
## automatically when the player wakes, not a click interaction").
func _on_wake() -> void:
	_state = State.SITTING
	_interaction_controller.interactions_enabled = true
	_look_controller.input_enabled = true
	_show_wristwatch_glance()
	_update_prompt()
	if _day_advanced:
		_day_advanced = false
		woke_into_new_day.emit()


func _show_wristwatch_glance() -> void:
	if _wristwatch_label == null:
		return
	_wristwatch_label.text = "You glance at your wristwatch. Another day."
	_wristwatch_label.visible = true
	_wristwatch_timer = get_tree().create_timer(wristwatch_glance_duration)
	_wristwatch_timer.timeout.connect(_hide_wristwatch_glance)


func _hide_wristwatch_glance() -> void:
	if _wristwatch_label != null:
		_wristwatch_label.visible = false


func _kill_eyes_tween() -> void:
	if _eyes_tween != null and _eyes_tween.is_valid():
		_eyes_tween.kill()
	_eyes_tween = null


## The dedicated "use laptop" action. Only valid from SITTING.
func open_laptop(zoom_in: bool = false) -> void:
	if _state != State.SITTING or _lying:
		return
	get_tree().call_group(&"station_ai", &"event", &"laptop_intro")
	_state = State.LAPTOP
	if _player_body.has_method("set_seated_head_follow"):
		_player_body.set_seated_head_follow(false)
	_laptop_view.open()
	# Target the SCREEN, not the lap anchor (the laptop's base/resting
	# point) -- the anchor sits low enough (near the hip) that aiming
	# the idle focus-assist at it required an extreme ~62 degree pitch
	# in practice, which in turn put the torso dead in the lower-center
	# of frame. The screen sits higher (the open hinge tilts it up
	# toward the face) and is also the thing actually worth looking at.
	_look_controller.focus_target_point = _laptop_view.get_screen_global_position()
	_look_controller.focus_assist_enabled = true
	_look_controller._focus_idle_time = 0.0
	_update_prompt()
	# The grip position is only meaningful once the laptop has finished
	# easing into its held pose on the lap -- reading it any earlier
	# (right after open() reparents it with keep_global_transform)
	# would aim the hand at wherever the laptop used to rest, not where
	# it ends up. Guarded by the state check in case the player closes
	# the laptop or gets up again during this short wait.
	await get_tree().create_timer(_laptop_view.pickup_duration).timeout
	if not (_state == State.LAPTOP or _state == State.EDITING):
		return
	_player_body.animate_hand_laptop_gesture(_laptop_view.get_lid_grip_global_position(), _laptop_view.get_hinge_duration())
	# The SCREEN's position specifically is not yet final here, though
	# -- the pickup tween above only settles the laptop's base pose;
	# the lid's own hinge-open tween starts right as that finishes and
	# takes its own get_hinge_duration() to reach the open angle the
	# screen actually ends up at. Reading the screen position now would
	# aim the camera/idle-focus-assist at the CLOSED-lid screen
	# position. Wait for the hinge too before locking that in.
	await get_tree().create_timer(_laptop_view.get_hinge_duration()).timeout
	if _state == State.LAPTOP or _state == State.EDITING:
		_aim_at_laptop_screen(0.3)
		_look_controller.focus_target_point = _laptop_view.get_screen_global_position()
		if zoom_in and _state == State.LAPTOP:
			begin_editing()


## The dedicated "close laptop" action. Only valid from LAPTOP (not
## EDITING -- end editing first, via Esc).
func close_laptop() -> void:
	# Round 45 Priority 13: ONE way to close the laptop -- from the focused
	# view too. end_editing() saves the private notes (laptop_view keeps
	# _saved_entry); letters / journal / games already save themselves.
	if _state == State.EDITING:
		end_editing()
	if _state != State.LAPTOP:
		return
	_state = State.SITTING
	if _player_body.has_method("set_seated_head_follow"):
		_player_body.set_seated_head_follow(true)
	_kill_laptop_aim_tween()
	_look_controller.focus_assist_enabled = false
	# Mirrors open_laptop()'s gesture (same grip point, same hinge
	# duration) -- previously nothing animated the arm on close at all,
	# which read as "the arm doesn't move correctly when the laptop
	# closes" (there was no closing gesture to be incorrect; there was
	# none). Started before laptop_view.close() so the reach and the
	# lid's own closing hinge motion run in the same window, not one
	# after the other.
	_player_body.animate_hand_laptop_gesture(_laptop_view.get_lid_grip_global_position(), _laptop_view.get_hinge_duration())
	_laptop_view.close()
	_update_prompt()


## The dedicated "edit log entry" action. Only valid from LAPTOP.
## Mouse-look is explicitly LOCKED while actually editing (below) -- the
## camera must stay exactly on the screen until the player deliberately
## exits via Esc/T, per the current design. This reverses an earlier
## round's "leave free-look on, the laptop isn't camera-attached"
## choice; the horror-gameplay need it was protecting ("quickly check a
## noise") is still satisfied because exiting is instant (Esc/T) and
## free-look resumes immediately in ordinary LAPTOP viewing -- it never
## required looking around DURING the close-up edit itself. The editor
## zoom (see _start_editor_zoom()) eases the eye position partway
## toward the screen so it is actually readable.
func begin_editing() -> void:
	if _state != State.LAPTOP:
		return
	# Round 44 Priority 1: focused laptop use pauses station time, so it is
	# refused while a genuine emergency runs (exiting is always allowed).
	if _day_plan != null and _day_plan.has_method("laptop_focus_allowed"):
		var ok: Dictionary = _day_plan.laptop_focus_allowed()
		if not ok["ok"]:
			_task_message(String(ok["reason"]))
			return
	_state = State.EDITING
	_laptop_view.begin_editing()
	_look_controller.escape_enabled = false
	# Prevent _aim_at_laptop_screen()'s tween (started when the laptop
	# opened) from ever being mid-flight at the same time as the editor
	# zoom's own rotation tracks -- both would write to the exact same
	# properties (LookPivot.rotation:y, PitchPivot.rotation:x) and fight.
	_kill_laptop_aim_tween()
	# ROOT CAUSE of the reported "camera reverses toward the player's
	# body shortly after zooming in": focus_assist_enabled was left
	# true (only open_laptop()/close_laptop()/end_sitting() ever
	# touched it; begin_editing()/end_editing() never did), still
	# targeting the LAP ANCHOR from ordinary LAPTOP viewing -- not the
	# screen. look_controller.gd's _process() runs that idle-triggered
	# ease every frame regardless of EDITING state, and _focus_idle_time
	# keeps accumulating from however long the player had already been
	# idle in LAPTOP mode. Once it crossed focus_assist_idle_delay
	# (1.2s) -- often almost immediately, since pressing T itself
	# involves no mouse movement -- it started overriding the editor's
	# own _target_yaw/_target_pitch every frame, dragging the view from
	# the screen back toward the lap anchor: exactly the "turns ~180
	# toward the body" symptom. The editor's own explicit aim (below)
	# is the ONLY camera authority while EDITING; the idle system must
	# be fully suspended, not merely out-raced.
	_look_controller.focus_assist_enabled = false
	# This round's explicit requirement reverses an earlier one: while
	# actually EDITING (not just viewing), mouse-look is now fully
	# LOCKED -- the camera must stay exactly on the screen until Esc/T.
	# (The earlier "must be able to check a noise while editing"
	# requirement is still satisfied: exiting is instant via Esc/T, and
	# free-look resumes immediately in ordinary LAPTOP viewing -- it
	# never required looking around DURING the close-up edit itself.)
	_look_controller.input_enabled = false
	# Round 34: a visible cursor while editing -- the [Back]/[Save] buttons
	# and the text are clicked with it.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_start_editor_zoom(true)
	_update_prompt()


## Ends editing (Esc) and returns to LAPTOP, saving the entry exactly
## like Ctrl+S does, and eases the editor zoom back out to ordinary
## sitting-with-laptop framing. The player remains seated throughout --
## this never triggers end_sitting().
func end_editing() -> void:
	if _state != State.EDITING:
		return
	_laptop_view.end_editing()
	_look_controller.escape_enabled = true
	_look_controller.input_enabled = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_state = State.LAPTOP
	_start_editor_zoom(false)
	# Re-arm ordinary LAPTOP-viewing idle focus-assist (see
	# begin_editing() for why it was disabled), with a FRESH idle
	# countdown -- without resetting _focus_idle_time, whatever idle
	# time had already elapsed before/during editing would still count,
	# so the ease could kick in instantly instead of after a genuine
	# fresh idle period.
	_look_controller.focus_target_point = _laptop_view.get_screen_global_position()
	_look_controller.focus_assist_enabled = true
	_look_controller._focus_idle_time = 0.0
	_update_prompt()


## Round 39: the zoom distance that makes the laptop SCREEN fill about
## `editor_screen_fill` of the view on its tighter axis -- from the real
## camera FOV / keep-aspect and the viewport's aspect -- so the zoomed
## desktop is a proper close-up on any window shape (a fixed distance
## over- or under-filled non-16:9 windows). editor_view_distance remains
## the upper bound.
@export var editor_screen_fill: float = 0.88
const LAPTOP_SCREEN_W := 0.24
const LAPTOP_SCREEN_H := 0.14


func _editor_distance() -> float:
	var cam: Camera3D = _interaction_controller as Camera3D
	if cam == null:
		return editor_view_distance
	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	var t: float = tan(deg_to_rad(cam.fov) * 0.5)
	var tv: float = t if cam.keep_aspect == Camera3D.KEEP_HEIGHT else t / aspect
	var th: float = tv * aspect
	var d: float = maxf(LAPTOP_SCREEN_H * 0.5 / tv, LAPTOP_SCREEN_W * 0.5 / th) / editor_screen_fill
	return clampf(d, 0.08, maxf(editor_view_distance, 0.3))


func _lap_anchor_global_position() -> Vector3:
	return _player_body.get_node("LapAnchor").global_position


## Eases the CAMERA (not the player/body) partway toward the laptop
## screen's actual current global position, by tweening LookPivot's
## local POSITION (not _player.global_position).
##
## This distinction matters: PlayerBody is a sibling of LookPivot under
## Player, authored entirely relative to Player's origin (the eye, per
## player_body.gd's documented invariant). Moving _player.global_position
## for the zoom (the original M8 implementation) dragged the ENTIRE
## seated body down and forward with it -- since the sitting pose's
## legs/feet are fixed offsets from that same origin, lowering the eye
## toward the laptop visibly sank the whole body into the mattress.
## Moving LookPivot's own local position instead relocates only the
## camera's origin; PlayerBody never moves, so the seated silhouette
## stays planted normally throughout.
##
## Also immediately (eased, not snapped) aims the camera AT the screen
## -- previously the zoom only moved the eye closer without changing
## where it was looking, so if the player hadn't been idle long enough
## for the separate soft focus-assist to kick in yet, pressing T could
## leave them zoomed in but still looking at the wall, never seeing the
## editor at all.
func _start_editor_zoom(zooming_in: bool) -> void:
	_kill_zoom_tween()
	var local_target: Vector3 = Vector3.ZERO
	var aim_dir: Vector3 = Vector3.ZERO
	if zooming_in:
		var eye_world: Vector3 = _camera_global_position()
		var screen_pos: Vector3 = _laptop_view.get_screen_global_position()
		# Position ALONG the screen's own normal (not a straight lerp
		# from the current eye toward the screen's center) so the final
		# camera pose looks squarely at the screen -- see
		# laptop_view.gd's get_screen_outward_normal() doc comment for
		# why "aim at the center point" alone left it looking tilted.
		var normal: Vector3 = _laptop_view.get_screen_outward_normal(eye_world)
		var desired_world: Vector3 = screen_pos + normal * _editor_distance()
		local_target = _player.global_transform.basis.inverse() * (desired_world - _player.global_position)
		aim_dir = -normal

	_zoom_tween = create_tween()
	_zoom_tween.set_parallel(true)
	_zoom_tween.tween_property(_look_pivot, "position", local_target, editor_zoom_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if zooming_in:
		_add_aim_direction_tracks(_zoom_tween, aim_dir, editor_zoom_duration)


## Adds yaw/pitch tracks to an existing (already-parallel) tween so the
## camera eases to directly face target_pos, then locks look_controller's
## _target_yaw/_target_pitch to match once settled (so its own per-frame
## easing doesn't drift back toward whatever they were before -- see
## _on_sit_settled()'s identical fix for the same reason). Shared by the
## editor zoom's aim and _aim_at_laptop_screen()'s ordinary-viewing aim
## so both compute the "face this point" math identically.
func _add_aim_tracks(tween: Tween, target_pos: Vector3, duration: float) -> void:
	var dir: Vector3 = (target_pos - _camera_global_position())
	if dir.length_squared() <= 0.0001:
		return
	_add_aim_direction_tracks(tween, dir.normalized(), duration)


## Same yaw/pitch-easing machinery as above, but driven by an explicit
## WORLD-space facing direction rather than "look at this point from
## wherever the camera currently is" -- used by _start_editor_zoom() to
## align the camera with the screen's own normal (a fixed direction,
## not dependent on the camera's position) rather than merely centering
## on a target point.
func _add_aim_direction_tracks(tween: Tween, dir: Vector3, duration: float) -> void:
	if dir.length_squared() <= 0.0001:
		return
	dir = dir.normalized()
	var parent_yaw: float = _player.rotation.y
	var desired_yaw := atan2(-dir.x, -dir.z) - parent_yaw
	var desired_pitch := asin(clampf(dir.y, -1.0, 1.0))
	var current_yaw: float = _look_pivot.rotation.y
	var yaw_delta: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	tween.tween_property(_look_pivot, "rotation:y", current_yaw + yaw_delta, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_pitch_pivot, "rotation:x", desired_pitch, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.chain().tween_callback(func():
		_look_pivot._target_yaw = _look_pivot.rotation.y
		_look_pivot._target_pitch = _pitch_pivot.rotation.x
	)


## Eases the camera's AIM ONLY (no position change) to directly face the
## laptop screen once it has settled into its held pose on the lap --
## called once from open_laptop(). Without this, the ordinary resting
## sit-down pitch (sit_look_pitch_degrees, a shallow -12 degrees chosen
## for "sitting and looking at the room," not at anything on the lap)
## leaves the laptop entirely outside the camera's FOV until the slow
## idle focus-assist eventually drags the view down -- confirmed by
## measuring the real angle from the camera's forward vector to the
## laptop at rest: ~50 degrees, well past the ~36-degree half-FOV, i.e.
## completely off-screen. The player would see nothing of the laptop
## at all right after opening it.
func _aim_at_laptop_screen(duration: float) -> void:
	_kill_laptop_aim_tween()
	_laptop_aim_tween = create_tween()
	_laptop_aim_tween.set_parallel(true)
	_add_aim_tracks(_laptop_aim_tween, _laptop_view.get_screen_global_position(), duration)


func _kill_laptop_aim_tween() -> void:
	if _laptop_aim_tween != null and _laptop_aim_tween.is_valid():
		_laptop_aim_tween.kill()
	_laptop_aim_tween = null


func _camera_global_position() -> Vector3:
	return _pitch_pivot.get_node("Camera3D").global_position


func _on_sit_settled() -> void:
	_look_pivot._target_pitch = deg_to_rad(sit_look_pitch_degrees)
	# Mirrors the pitch fix above: look_controller.gd's own _process()
	# eases rotation.y toward _target_yaw every frame, independent of
	# this tween. Without updating _target_yaw to match where the tween
	# just left rotation.y, the very next frame would start easing the
	# camera back toward whatever direction the player was facing
	# before they sat down, undoing the snap this tween just performed.
	_look_pivot._target_yaw = _look_pivot.rotation.y
	_player_body.set_sitting(true)


func _on_stand_settled() -> void:
	_free_body.sync_to_eye_position(_pre_sleep_eye_position)
	_global_free_move.mirror_enabled = true
	_free_body.set_active(true)
	_interaction_controller.interactions_enabled = true
	_player_body.set_sitting(false)
	_state = State.AWAKE
	_update_prompt()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_tween = null


func sitting_world_yaw_for_get_up() -> float:
	return _player_body.sitting_world_yaw_degrees if "sitting_world_yaw_degrees" in _player_body else 0.0


func _kill_zoom_tween() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	match _state:
		State.AWAKE:
			# Ownership of the AWAKE-state prompt (bed proximity, plus
			# every other free-roam contextual prompt) now belongs to
			# scripts/player/interaction_controller.gd, which recomputes
			# it every frame from both hover state and is_near_bed()
			# below -- this avoids two systems writing the same shared
			# label on independent, uncoordinated triggers. set_bed_proximity()
			# still updates _near_bed itself (read by is_near_bed()); it
			# just no longer also pokes the label directly here.
			pass
		State.SITTING:
			var sleep_hint := "G: Sleep"
			if _day_plan != null and _day_plan.has_method("can_sleep") and not _day_plan.can_sleep():
				sleep_hint = "Sleep after shift (%d%%)" % int(round(_day_plan.shift_progress() * 100.0))
			if _lying:
				_prompt_label.text = "E: Get Up    %s" % sleep_hint
			elif laptop_hovered:
				_prompt_label.text = "Click: Open Laptop    E: Get Up    %s" % sleep_hint
			else:
				_prompt_label.text = "E: Get Up    F: Laptop    %s" % sleep_hint
			_prompt_label.visible = true
		State.LAPTOP:
			_prompt_label.text = "Click the laptop's apps    E: Get Up"
			_prompt_label.visible = true
		State.EDITING:
			_prompt_label.text = "" # the laptop screen itself shows the Esc/Ctrl+S hint
			_prompt_label.visible = false
		State.SLEEPING:
			_prompt_label.text = ""
			_prompt_label.visible = false


## E/F/T are only ever acted on here while sitting/using the laptop, and
## are plain keycode checks rather than routed through
## interaction_controller.gd -- while sitting the camera's primary
## target is the lap, not necessarily something interaction_controller.gd
## would raycast-hit.
##
## While EDITING specifically, this takes over entirely: Esc and Ctrl+S
## are handled directly, and every other key (E/F/T included) is
## forwarded into the laptop screen's own SubViewport as ordinary typing
## instead of being interpreted as a shortcut.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _state in [State.SITTING, State.LAPTOP, State.EDITING] and handle_click(false, event.position):
			get_viewport().set_input_as_handled()
		return
	# Round 42: key RELEASES reach the laptop too while it is in focused use,
	# so a held-key laptop game (Holdout: W A S D) stops moving on release.
	# They never reach the technician's own movement.
	if event is InputEventKey and not event.pressed and _state == State.EDITING:
		_laptop_view.forward_key_to_screen(event)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed):
		return

	if _state == State.EDITING:
		if event.keycode == KEY_ESCAPE:
			end_editing()
			get_viewport().set_input_as_handled()
			return
		# A previous round added "bare T also exits editing" as a
		# convenience toggle. REMOVED: confirmed via a real typing test
		# that it silently truncated any entry containing the letter
		# "t" ("Quiet shift." -> "Quie", eating the "t" every time it
		# appeared) because every literal "t" keystroke was being
		# interpreted as the exit shortcut instead of being forwarded
		# to the text field. A toggle key that breaks typing the most
		# common consonant in English is not a usable feature. Esc is
		# the only exit key now, matching this round's explicit spec
		# (Section 3: "Pressing Esc exits the editor").
		if event.keycode == KEY_S and event.ctrl_pressed:
			_laptop_view.save_entry()
			get_viewport().set_input_as_handled()
			return
		_laptop_view.forward_key_to_screen(event)
		get_viewport().set_input_as_handled()
		return

	if _state == State.SLEEPING:
		# Eyes closed: input fully owned by the sleep tween, same
		# "takes over entirely" treatment as EDITING above.
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_E and _state == State.AWAKE and _near_bed:
		begin_sitting()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E and _state != State.AWAKE:
		end_sitting()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F and _state == State.SITTING:
		open_laptop()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F and _state == State.LAPTOP:
		close_laptop()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_T and _state == State.LAPTOP:
		_laptop_view._log_screen.set_pending_app(&"log")
		begin_editing()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_G and _state == State.SITTING:
		begin_sleep()
		get_viewport().set_input_as_handled()
