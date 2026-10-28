extends Node3D
## Visible first-person body: a reusable, non-colliding cosmetic model.
## It tracks the player's look yaw every frame while standing (so
## turning around visibly turns the body, a standard first-person
## simplification), and freezes to an authored world yaw while sitting
## on the bed or lying flat, where mouse-look no longer represents
## turning your whole body. See scripts/player/sleep_state.gd, which
## calls set_sitting()/set_lying() only once each transition tween has
## fully settled -- never mid-tween, so the standing pose is what
## visibly eases down, and whichever pose it eased into is what visibly
## eases back up out of it. Swapping mid-tween would show the wrong
## silhouette moving through the wrong space.
##
## Three complete pose subtrees (StandingPose / SittingPose / LyingPose)
## are authored independently, each already correctly offset from this
## node's own origin -- which always sits exactly at the current eye
## point, since this node is a plain child of Player and Player's
## position IS the eye point in every state (see global_free_move.gd /
## sleep_state.gd). Only one subtree is ever visible at a time. No
## skeleton or bone animation: swapping which static pose is visible is
## enough for this prototype (see GAME_DESIGN.md).
##
## LyingPose is no longer reachable from the bed interaction (the daily
## log flow now uses SittingPose -- see the "next iteration" report for
## why: lying flat put the torso through the mattress and gave a bad
## angle on the laptop). It is kept, unchanged, as a distinct pose/state
## for any future "actually go to sleep" mechanic; set_lying() still
## works exactly as before.
##
## SittingPose freezes yaw instead of tracking it, same as LyingPose
## (see sitting_world_yaw_degrees below) -- NOT because a seated player
## can't turn their head (they very much can and should, see the horror
## -gameplay requirement that they can look around the room while
## editing), but because the LEGS and the laptop/lap anchor are authored
## in a fixed relationship to the bed itself. If the body tracked head
## yaw while seated, turning to check the room would visibly swing the
## legs and the laptop sideways through the nightstand/wall with them,
## since there is no separate pivot between the torso and the legs in
## this static-pose prototype. Freezing the whole body's yaw (while
## mouse-look stays completely free, same as it ever was) keeps the
## legs/laptop planted correctly relative to the bed no matter which way
## the player is currently looking. sleep_state.gd's begin_sitting()
## also eases the CAMERA's yaw to the matching value as part of the
## sit-down tween, so the player starts out facing the same direction
## their now-seated body is facing, rather than an arbitrary mismatch
## left over from whatever direction they approached the bed from.

enum Pose { STANDING, SITTING, LYING }

@export var look_pivot_path: NodePath

## Player's own rotation.y is a fixed, never-updated legacy value baked
## in at scene load (movement_controller.gd snaps it once to the
## starting MovementNode's orientation, then free-move never touches
## it again -- see scripts/dev/global_free_move.gd). That baked value
## is 180 degrees for this station's starting node. PlayerBody is a
## plain child of Player, so its LOCAL rotation.y adds on top of that
## fixed 180.
##
## LyingPose was authored with "+Z (local) = toward the foot of the
## bed" -- a local value of 0 would point that axis at world -Z (into
## the headboard) instead of world +Z, so 180 here cancels Player's
## baked 180, landing PlayerBody at net-zero global rotation, which is
## what the lying pose geometry was actually authored against (verified
## empirically, not assumed).
@export var lying_world_yaw_degrees: float = 180.0

## SittingPose was authored with "-Z (local) = forward, toward the foot
## of the bed" -- the same convention as StandingPose. With Player's
## baked 180 already in the chain, a LOCAL value of 0 here nets a WORLD
## rotation of 180 degrees, which is exactly what points that local -Z
## axis at world +Z (toward the foot of the bed) for this station's
## bed placement -- verified empirically against the actual bed/laptop
## transforms in main.tscn, the same way the lying-pose convention was.
@export var sitting_world_yaw_degrees: float = 0.0

## Standing-only: how much the body's own pitch follows the camera's
## downward look, as a fraction (0..1). This is the actual fix for "the
## body is dead-center when looking straight down" -- see the "next
## iteration" report's composition analysis. At 0 (the old behavior),
## the body is pitch-static in world space, which means there is
## ALWAYS some reachable camera pitch where the camera points exactly
## at a given body part (simple geometry: a rotating camera sweeps
## through every fixed direction in its range). Applying a FRACTION of
## the camera's downward pitch to the body itself makes the body
## "recede" relative to the camera as you look down further, instead
## of the camera's view center sweeping onto it -- keeping it confined
## to the lower part of the frame across the whole reachable pitch
## range instead of crossing through the middle. Tuned so the torso
## only enters view at a deliberately steep downward glance and never
## reaches frame-center even at the maximum pitch (see
## test_standing_body_composition.gd, which sweeps the whole pitch
## range and checks this as an invariant, not a single-angle sample).
@export var standing_pitch_follow: float = 0.3

## Debug/testing toggle for the whole body, independent of pose.
@export var body_visible: bool = true

## Round 11 Workstream A: OPTIONAL reference to the separate first-
## person watch rig (scripts/player/first_person_watch_rig.gd), used
## ONLY for the one defensive call in set_sitting() below -- this
## script otherwise has no watch-related state or logic at all anymore
## (see the "ROOT CAUSE" doc comment on that script for why it used to,
## and why that was the actual cause of the world body disappearing
## while the watch was raised).
@export var watch_rig_path: NodePath

@onready var _look_pivot: Node3D = get_node(look_pivot_path)
@onready var _pitch_pivot: Node3D = _look_pivot.get_node("PitchPivot")
@onready var _standing_pose: Node3D = $StandingPose
@onready var _sitting_pose: Node3D = $SittingPose
@onready var _lying_pose: Node3D = $LyingPose
## Round 17 Priority 5/6: a head/neck/visor, standing-pose-only, on a
## dedicated render layer (bit 3, value 4 -- layer 2 was already
## claimed, inertly, by first_person_watch_rig.gd's ArmGroup/
## WatchAssembly) excluded from the player's OWN Camera3D's cull_mask
## (see player.tscn) -- so the first-person camera still never sees its
## own head (preserving every existing composition test unchanged),
## while every OTHER camera in the game (the Living Quarters mirror,
## surveillance cameras, any future third-person view) renders it
## normally, at the default cull_mask. Without this, those other
## viewpoints would show a headless torso.
@onready var _head_group: Node3D = $HeadGroup
@onready var _watch_rig: Node = get_node_or_null(watch_rig_path)

var _pose: Pose = Pose.STANDING
var _hand_rest_pos: Vector3

## ROUND 11 FIX: this body previously eased its OWN pitch toward a full
## 1.0 follow (instead of the ordinary PARTIAL `standing_pitch_follow`)
## while the watch was raised, to keep a watch node parented under
## StandingPose camera-anchored. That was the actual, confirmed cause
## of "the player's body disappears when the watch is raised": rotating
## the WHOLE body (torso, hips, legs, both arms -- everything under
## StandingPose) in lockstep with the camera's full pitch swings all of
## it through a large arc around the eye point at any real look angle,
## carrying most of the body outside the frustum or behind the camera.
## The watch inspection presentation now lives entirely in a separate,
## purely cosmetic rig (first_person_watch_rig.gd) that is a plain
## child of Camera3D and therefore needs NO per-frame pitch-follow math
## of its own at all. This body's own pitch follow is now ALWAYS the
## ordinary partial value, unconditionally, matching Workstream A2's
## explicit requirement that the world body "does not inherit
## artificial camera-relative watch inspection offsets."
var _pitch_follow_current: float = 0.0


func _ready() -> void:
	visible = body_visible
	_pitch_follow_current = standing_pitch_follow
	_hand_rest_pos = _sitting_pose.get_node("HandR").position
	for entry in _ARM_GESTURE_NODES:
		var node_name: String = entry[0]
		_arm_rest_pos[node_name] = _sitting_pose.get_node(node_name).position
	_apply_pose()


func _process(_delta: float) -> void:
	if _pose == Pose.STANDING:
		rotation.y = _look_pivot.rotation.y
		_pitch_follow_current = standing_pitch_follow
		rotation.x = _pitch_pivot.rotation.x * _pitch_follow_current


func is_sitting() -> bool:
	return _pose == Pose.SITTING


func is_lying() -> bool:
	return _pose == Pose.LYING


## Called by sleep_state.gd exactly when the sit-down/stand-up tween has
## fully settled. Idempotent.
func set_sitting(value: bool) -> void:
	if value:
		# Defensive: force the watch rig down/hidden instantly before
		# leaving STANDING, regardless of whatever wristwatch_view.gd's
		# own interactions_enabled-driven lower() call has or hasn't done
		# yet -- a real (if narrow) race otherwise, same reasoning as
		# before this was delegated to the separate rig.
		if _watch_rig != null:
			_watch_rig.set_raised(false, 0.0)
	if not value:
		_kill_hand_gesture()
		reset_get_up_pose()
	_pose = Pose.SITTING if value else Pose.STANDING
	_apply_pose()
	if value:
		rotation.y = deg_to_rad(sitting_world_yaw_degrees)


## Preserved from before the sitting-pose redesign: a distinct pose for
## lying flat, not currently reachable from any interaction, kept for a
## future sleep mechanic. Idempotent.
func set_lying(value: bool) -> void:
	_pose = Pose.LYING if value else Pose.STANDING
	_apply_pose()
	if value:
		rotation.y = deg_to_rad(lying_world_yaw_degrees)


## Right-arm nodes that move together for the laptop-opening gesture,
## paired with how much each one travels relative to the hand's own
## reach distance -- approximating the arm swinging from the shoulder
## (which stays put) rather than only the hand sliding through empty
## space while the rest of the arm stays behind.
const _ARM_GESTURE_NODES: Array = [
	["UpperArmR", 0.25],
	["ElbowR", 0.55],
	["LowerArmR", 0.8],
	["HandR", 1.0],
]

var _arm_rest_pos: Dictionary = {}
var _hand_gesture_tweens: Array = []


## Plays a reach-toward/retreat gesture with the sitting pose's whole
## right arm (shoulder joint excepted), timed to cover the laptop's own
## pickup+hinge animation. Used for BOTH directions -- called from
## scripts/player/sleep_state.gd's open_laptop() (right after
## scripts/player/laptop_view.gd's open()) AND close_laptop() (right
## alongside laptop_view.gd's close()) -- so the player visibly
## reaches to the lid to open OR close it, instead of either the
## laptop unfolding/folding on its own, or (the actual reported bug)
## only the OPEN direction ever animating anything at all: close_laptop()
## previously never called this function, so nothing moved the arm back
## -- there was no "closing gesture" to fail to reverse; there was no
## closing gesture at all.
##
## Every call recomputes its reach target from the SAME fixed
## _hand_rest_pos/_arm_rest_pos captured once in _ready(), and
## _kill_hand_gesture() always snaps every node back to that exact rest
## pose before a new gesture starts -- so open and close are already
## symmetric by construction (same rest reference both ways), calling
## this repeatedly can never accumulate drift, and interrupting one
## direction mid-flight to start the other is always safe: the
## in-flight tweens are killed and every node is restored to its known
## rest transform before the new gesture begins. target_global_pos is
## converted to this node's own local space each call, so it stays
## correct regardless of the player's current yaw.
func animate_hand_laptop_gesture(target_global_pos: Vector3, total_duration: float) -> void:
	if _pose != Pose.SITTING:
		return
	_kill_hand_gesture()
	var hand_reach: Vector3 = to_local(target_global_pos)
	var hand_delta: Vector3 = hand_reach - _hand_rest_pos
	var out_time: float = total_duration * 0.45
	var hold_time: float = total_duration * 0.15
	var back_time: float = total_duration - out_time - hold_time
	# Each arm node gets its OWN tween (not one shared Tween juggling
	# parallel() / chain() across nodes, which would make their "out ->
	# hold -> back" sequences fight over what "parallel" means) -- all
	# created together so every node's own 3-step sequence runs in sync
	# with every other node's, while remaining trivially killable as a
	# group via _hand_gesture_tweens.
	_hand_gesture_tweens.clear()
	for entry in _ARM_GESTURE_NODES:
		var node_name: String = entry[0]
		var falloff: float = entry[1]
		var node: Node3D = _sitting_pose.get_node_or_null(node_name)
		if node == null:
			continue
		var rest: Vector3 = _arm_rest_pos[node_name]
		var reach: Vector3 = rest + hand_delta * falloff
		var tw: Tween = create_tween()
		tw.tween_property(node, "position", reach, out_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_interval(hold_time)
		tw.tween_property(node, "position", rest, back_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_hand_gesture_tweens.append(tw)


func _kill_hand_gesture() -> void:
	for tw in _hand_gesture_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_hand_gesture_tweens.clear()
	for entry in _ARM_GESTURE_NODES:
		var node_name: String = entry[0]
		var node: Node3D = _sitting_pose.get_node_or_null(node_name)
		if node != null:
			node.position = _arm_rest_pos[node_name]


## ============================================================
## Get-up sequence: swings one SittingPose leg from its authored
## "lying flat on the mattress" rest pose down to the floor, via a
## 2-bone (hip + knee) rotation solved with the law of cosines against a
## fixed floor-contact target -- computed once (see the M9 investigation
## notes/compute_legs2.py), not guessed. Both legs share the exact same
## rotation (a pure pitch about the shared local X axis, independent of
## which side), so only the LEFT leg's targets are stored here; the
## right leg's targets are the same rotation with every position's X
## component negated (see _leg_targets_for()).
##
## HONEST LIMITATION (see the M9 final report): this is a single eased
## arc from "flat on the bed" to "foot flat on the floor," not a
## multi-waypoint knee-lift swing -- the current static-CSG-pose
## architecture has no continuous IK solver to drive a more organic
## path, only discrete authored/computed keyframes tweened between. The
## foot "planting" is this tween simply completing and nothing further
## moving that leg until the pose swap to StandingPose -- not a
## physically simulated contact.
## ============================================================

## Computed by compute_legs2.py: the floor-planted basis shared by both
## legs' UpperLeg/LowerLeg (a pure rotation about local X away from the
## authored "lying flat" rest basis -- see the class doc comment above).
const _LEG_SWING_UPPER_BASIS: Basis = Basis(Vector3(1, 0, 0), Vector3(0, 0.8245, -0.5659), Vector3(0, 0.5659, 0.8245))
const _LEG_SWING_LOWER_BASIS: Basis = Basis(Vector3(1, 0, 0), Vector3(0, 0.9865, -0.164), Vector3(0, 0.164, 0.9865))

## Left-leg target positions (right mirrors by negating .x -- see
## _leg_targets_for()).
const _LEG_SWING_TARGETS_L: Dictionary = {
	"UpperLegL": Vector3(-0.1, -0.6827, -0.2707),
	"KneeL": Vector3(-0.1, -0.8353, -0.3664),
	"LowerLegL": Vector3(-0.1, -0.9977, -0.3807),
	"AnkleL": Vector3(-0.1, -1.16, -0.395),
	"FootL": Vector3(-0.1, -1.17, -0.415),
}

var _leg_rest_transform: Dictionary = {}
var _leg_swing_tweens: Array = []
var _lean_rest_pos: Dictionary = {}
var _lean_tween: Tween

## Upper-body nodes that lean forward together in stages 1/5 of the
## get-up sequence (and during ordinary sitting, never -- this group is
## only ever displaced during end_sitting()). Position-only (no
## rotation re-derivation) -- a small, deliberately modest translation,
## not a full recline-angle recompute like the original sitting-pose
## authoring; proportionate to what a few centimeters of "leaning
## forward" should look like rather than a second full-body pose.
const _LEAN_NODES: Array = [
	"Hips", "HipCapL", "HipCapR", "Waist", "Chest", "ChestPocket", "AccentStripe",
	"ShoulderL", "ShoulderR", "ShoulderCapL", "ShoulderCapR",
	"UpperArmL", "UpperArmR", "ElbowL", "ElbowR", "LowerArmL", "LowerArmR", "HandL", "HandR",
]
const _LEAN_OFFSET: Vector3 = Vector3(0, -0.025, -0.07)


func _leg_targets_for(is_right: bool) -> Dictionary:
	if not is_right:
		return _LEG_SWING_TARGETS_L
	var mirrored: Dictionary = {}
	for key in _LEG_SWING_TARGETS_L:
		var mirrored_key: String = key.replace("L", "R") if key.ends_with("L") else key
		var v: Vector3 = _LEG_SWING_TARGETS_L[key]
		mirrored[mirrored_key] = Vector3(-v.x, v.y, v.z)
	return mirrored


## Eases ONE leg (is_right ? "...R" : "...L" nodes) from its rest pose to
## the computed floor-planted pose. Safe to call for both legs with a
## stagger (see sleep_state.gd's end_sitting()) -- each leg's nodes are
## only ever touched by that leg's own call, so the two never fight.
func swing_leg_to_floor(is_right: bool, duration: float) -> void:
	if _pose != Pose.SITTING:
		return
	var targets: Dictionary = _leg_targets_for(is_right)
	var upper_name: String = "UpperLegR" if is_right else "UpperLegL"
	var lower_name: String = "LowerLegR" if is_right else "LowerLegL"
	for node_name in targets:
		var node: Node3D = _sitting_pose.get_node_or_null(node_name)
		if node == null:
			continue
		if not _leg_rest_transform.has(node_name):
			_leg_rest_transform[node_name] = node.transform
		var target_pos: Vector3 = targets[node_name]
		var target_transform: Transform3D
		if node_name == upper_name:
			target_transform = Transform3D(_LEG_SWING_UPPER_BASIS, target_pos)
		elif node_name == lower_name:
			target_transform = Transform3D(_LEG_SWING_LOWER_BASIS, target_pos)
		else:
			# Knee/Ankle markers (spheres) and the foot box all keep
			# their rest rotation (identity) -- only the foot's position
			# matters for "flat on the floor," and sphere markers have
			# no visible rotation at all.
			target_transform = Transform3D(node.transform.basis, target_pos)
		var tw: Tween = create_tween()
		tw.tween_property(node, "transform", target_transform, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_leg_swing_tweens.append(tw)


## Snaps both legs back to their authored rest pose and kills any
## in-flight swing tweens -- called whenever the get-up sequence is
## interrupted or restarted, and once a cycle completes (via
## set_sitting(), so sitting back down always starts from the real rest
## pose, never a stale mid-swing one).
func reset_get_up_pose() -> void:
	for tw in _leg_swing_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_leg_swing_tweens.clear()
	for node_name in _leg_rest_transform:
		var node: Node3D = _sitting_pose.get_node_or_null(node_name)
		if node != null:
			node.transform = _leg_rest_transform[node_name]
	if _lean_tween != null and _lean_tween.is_valid():
		_lean_tween.kill()
	_lean_tween = null
	for node_name in _LEAN_NODES:
		if _lean_rest_pos.has(node_name):
			var node: Node3D = _sitting_pose.get_node_or_null(node_name)
			if node != null:
				node.position = _lean_rest_pos[node_name]


## Eases the whole upper body (torso + arms, see _LEAN_NODES) forward by
## `amount` (0..1 fraction of _LEAN_OFFSET) -- used for get-up stages 1
## ("prepare to rise") and 5 ("torso begins moving forward over the
## feet"), each just dialing in a bit more of the same offset rather
## than two unrelated poses.
func lean_forward(amount: float, duration: float) -> void:
	if _pose != Pose.SITTING:
		return
	if _lean_tween != null and _lean_tween.is_valid():
		_lean_tween.kill()
	_lean_tween = create_tween()
	_lean_tween.set_parallel(true)
	var offset: Vector3 = _LEAN_OFFSET * amount
	for node_name in _LEAN_NODES:
		var node: Node3D = _sitting_pose.get_node_or_null(node_name)
		if node == null:
			continue
		if not _lean_rest_pos.has(node_name):
			_lean_rest_pos[node_name] = node.position
		_lean_tween.tween_property(node, "position", _lean_rest_pos[node_name] + offset, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _apply_pose() -> void:
	_standing_pose.visible = _pose == Pose.STANDING
	_sitting_pose.visible = _pose == Pose.SITTING
	_lying_pose.visible = _pose == Pose.LYING
	_head_group.visible = _pose == Pose.STANDING
	rotation.x = 0.0
	if _pose == Pose.STANDING:
		rotation.y = _look_pivot.rotation.y
