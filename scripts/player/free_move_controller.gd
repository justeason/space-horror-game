extends CharacterBody3D
## Free WASD movement with real physical collision — now the station's
## only active movement everywhere (see scripts/dev/global_free_move.gd,
## which activates this once at startup and never deactivates it). The
## node-based tween system in movement_controller.gd is left fully intact
## for recoverability; this is simply the only thing actually moving the
## player now.
##
## This body's origin is the player's FEET (standard CharacterBody3D
## convention: the collision shape is offset upward by half its height,
## so global_position.y sits at the floor when grounded). The owning
## Player node's eye-height origin is derived from this body each frame
## via `eye_height` — see global_free_move.gd.
##
## IMPORTANT: this capsule's height (see the CollisionShape3D in
## free_move_body.tscn) is a full standing-body height. Do not confuse it
## with movement_controller.gd's `player_clearance_height`, which is a
## short torso-band used only by the authoring-time navigation
## validation (test_locked_graph.gd) and is not a character height.

## Tuning: all movement-feel knobs live here, exported, rather than as
## inline literals. Walking pace deliberately slowed ~18% from the
## original free-move prototype (2.2 -> 1.8 m/s) for a heavier, more
## deliberate feel; see the movement-tuning report for the exact
## before/after values across speed, look sensitivity, and smoothing.
@export var move_speed: float = 1.8
@export var acceleration: float = 14.0
@export var gravity: float = 12.0
@export var eye_height: float = 1.6

## Footstep cadence: a step plays every `step_distance` meters of ACTUAL
## horizontal displacement (not requested velocity) while grounded, so
## cadence naturally tracks real pace — walking into a wall produces
## near-zero displacement and therefore no steps, exactly like stopping
## does. ~0.85m is a believable stride length at this walking speed; this
## is a cadence tuning knob, not the player's physical collision radius.
@export var step_distance: float = 0.85

## Horizontal yaw source for "forward" — the player's existing LookPivot,
## so free movement is relative to where you're looking, same convention
## as the node system (pitch is ignored for movement direction).
var look_pivot: Node3D = null

## Set once by global_free_move.gd to the Player's existing Footsteps
## AudioStreamPlayer3D (see movement_controller.gd) — reused as-is so
## there is exactly one footstep-audio path, never two competing ones.
## Deliberately duck-typed (not statically AudioStreamPlayer3D), same
## convention as interaction_controller.gd's "anything with interact()":
## anything with a play_step() method works, which also makes this
## straightforward to verify in tests without touching real audio.
var footsteps = null

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var active: bool = false
var _distance_since_step: float = 0.0


## This body exists in the world from scene load (parked wherever its
## scene transform puts it) even though it only ever MOVES while
## `active`. Without this, its collider would still be a live physics
## object the rest of the station — and navigation validation's capsule
## sweeps — could collide with at rest. Route all activation through
## this so collision participation always matches `active`.
func set_active(value: bool) -> void:
	active = value
	if _collision_shape:
		_collision_shape.disabled = not value


func _ready() -> void:
	set_active(active)


func _physics_process(delta: float) -> void:
	if not active:
		return

	var position_before: Vector3 = global_position

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	input_dir = input_dir.normalized()

	var yaw: float = look_pivot.global_rotation.y if look_pivot else 0.0
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish_dir: Vector3 = (forward * -input_dir.y + right * input_dir.x)
	if wish_dir.length_squared() > 0.0001:
		wish_dir = wish_dir.normalized()

	var target_velocity: Vector3 = wish_dir * move_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	_update_footsteps(position_before)


## Plays a footstep every `step_distance` of real horizontal travel.
## Uses ACTUAL displacement from move_and_slide (not the requested
## velocity), so pressing into a wall — where real displacement is near
## zero even with nonzero input — correctly produces no footsteps, and
## stopping halts them on the very next tick rather than letting a
## timer "finish out" a cadence that no longer matches reality.
func _update_footsteps(position_before: Vector3) -> void:
	if footsteps == null:
		return

	var delta_horizontal := global_position - position_before
	delta_horizontal.y = 0.0
	var moved: float = delta_horizontal.length()

	if not is_on_floor() or moved < 0.0005:
		_distance_since_step = 0.0
		return

	_distance_since_step += moved
	if _distance_since_step >= step_distance:
		_distance_since_step = fmod(_distance_since_step, step_distance)
		footsteps.play_step()


## Places this body's feet at `eye_world_pos` minus eye_height, preserving
## continuity: called once at startup with the player's CURRENT eye
## position (never a different/teleported spot).
func sync_to_eye_position(eye_world_pos: Vector3) -> void:
	global_position = eye_world_pos - Vector3(0, eye_height, 0)
	velocity = Vector3.ZERO


func current_eye_position() -> Vector3:
	return global_position + Vector3(0, eye_height, 0)
