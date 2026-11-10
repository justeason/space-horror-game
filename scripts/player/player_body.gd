extends Node3D
const _HandMeshBuilder = preload("res://scripts/player/hand_mesh_builder.gd")
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
##
## Round 26: RETIRED (default 0). Tilting the WHOLE body -- pelvis and legs
## included -- by 30% of camera pitch about the eye is exactly what made the
## mirror show a rigid, leaning mannequin whose head never looked anywhere
## (measured: 23.4 deg whole-body tilt at a 78 deg downward look, legs
## swinging with it). The body now stays upright and planted; look pitch
## drives the head/neck through CharacterPoseState instead, and the
## first-person composition concern this solved is handled per camera (see
## _set_upper_torso_self_hidden()). Kept as an export only so the old
## behaviour can be compared side by side.
@export var standing_pitch_follow: float = 0.0

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
@onready var _neck_pivot: Node3D = get_node_or_null("HeadGroup/NeckPivot")
@onready var _head_pivot: Node3D = get_node_or_null("HeadGroup/NeckPivot/HeadPivot")
## Round 26: the shared visual pose state (Player/PoseState). Optional so
## the body still works standalone (head simply stays level).
@export var pose_state_path: NodePath
@onready var _pose_state: Node = get_node_or_null(pose_state_path)
@onready var _watch_rig: Node = get_node_or_null(watch_rig_path)

## Round 19 Priority 2: StandingPose arm nodes whose rest position is
## captured once in _ready(), the same pattern _arm_rest_pos already
## uses for SittingPose's laptop-reach gesture -- needed so
## set_watch_raise_pose() has a known rest pose to tween the standing
## right arm away from and back to.
const _STANDING_ARM_NODES: Array = ["UpperArmR", "ElbowR", "LowerArmR", "HandR"]
var _standing_arm_rest_pos: Dictionary = {}

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
	_build_hands_and_watch()
	for node_name in _STANDING_ARM_NODES:
		_standing_arm_rest_pos[node_name] = _standing_pose.get_node(node_name).position
	_setup_watch_raise_rig()
	_split_self_hidden_upper_torso()
	_apply_watch_raise(0.0)
	_apply_pose()
	_update_arm_meshes()
	if use_rigged_visual:
		_setup_rigged_visual()


func _process(_delta: float) -> void:
	if _pose == Pose.STANDING:
		rotation.y = _look_pivot.rotation.y
		_pitch_follow_current = standing_pitch_follow
		rotation.x = _pitch_pivot.rotation.x * _pitch_follow_current
	_apply_look_pose()
	if _watch_raise_progress > 0.0 and _pose == Pose.STANDING:
		_update_watch_target(_shared_watch_target())
		_apply_watch_raise(_watch_raise_progress)
	_update_arm_meshes()
	_update_rig(_delta)
	_update_eye_anchor()


## Round 26 Priority 3: the world head/neck now answer the player's look
## pitch through the shared CharacterPoseState (anatomically limited split
## across upper spine / neck / head -- see character_pose_state.gd). The
## CSG torso is one boolean union and cannot bend cheaply, so on THIS body
## the upper-spine share is carried at the neck base; the Skeleton3D
## prototype applies it to its Spine/Chest bones instead. Pelvis, legs and
## the collar ring stay put; only HeadGroup/NeckPivot and
## HeadGroup/NeckPivot/HeadPivot rotate (plain Node3D pivots, so this is a
## transform change, not a CSG rebuild).
func _apply_look_pose() -> void:
	if _neck_pivot == null or _head_pivot == null:
		return
	var neck: float = 0.0
	var head: float = 0.0
	if _pose_state != null and _pose == Pose.STANDING:
		neck = _pose_state.spine_pitch + _pose_state.neck_pitch
		head = _pose_state.head_pitch
	_neck_pivot.rotation.x = neck
	_head_pivot.rotation.x = head


func is_sitting() -> bool:
	return _pose == Pose.SITTING


func is_lying() -> bool:
	return _pose == Pose.LYING


## Called by sleep_state.gd exactly when the sit-down/stand-up tween has
## fully settled. Idempotent.
func set_sitting(value: bool, crossfade_s: float = POSE_XFADE_S) -> void:
	_xfade_dur = maxf(crossfade_s, 0.05)
	if value:
		# Defensive: force the watch rig down/hidden instantly before
		# leaving STANDING, regardless of whatever wristwatch_view.gd's
		# own interactions_enabled-driven lower() call has or hasn't done
		# yet -- a real (if narrow) race otherwise, same reasoning as
		# before this was delegated to the separate rig.
		if _watch_rig != null:
			_watch_rig.set_raised(false, 0.0)
		_stop_watch_raise(true)
	if not value:
		_kill_hand_gesture()
		reset_get_up_pose()
	_begin_pose_crossfade(Pose.SITTING if value else Pose.STANDING)
	_pose = Pose.SITTING if value else Pose.STANDING
	_sit_preview_t = -1.0
	_apply_pose()
	if value:
		rotation.y = deg_to_rad(sitting_world_yaw_degrees)
	# _apply_pose()/the line above re-yaw the body right now; recompose the
	# rig immediately so the crossfade's first frame is exactly what was
	# shown, never one stale frame.
	_update_rig(0.0)


## Preserved from before the sitting-pose redesign: a distinct pose for
## lying flat, not currently reachable from any interaction, kept for a
## future sleep mechanic. Idempotent.
func set_lying(value: bool, crossfade_s: float = POSE_XFADE_S) -> void:
	_xfade_dur = maxf(crossfade_s, 0.05)
	if value:
		_stop_watch_raise(true)
	_begin_pose_crossfade(Pose.LYING if value else Pose.STANDING)
	_pose = Pose.LYING if value else Pose.STANDING
	_sit_preview_t = -1.0
	_apply_pose()
	if value:
		rotation.y = deg_to_rad(lying_world_yaw_degrees)
	# _apply_pose()/the line above re-yaw the body right now; recompose the
	# rig immediately so the crossfade's first frame is exactly what was
	# shown, never one stale frame.
	_update_rig(0.0)


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


## ============================================================
## Round 19 Priority 2: real hand geometry + a world-worn wristwatch.
##
## ROOT PROBLEM (confirmed by reading player_body.tscn, not assumed):
## HandL/HandR in every pose were a single CSGSphere3D each -- a bare
## blob with no fingers, thumb, or joints at all -- and the world body
## had no wristwatch model anywhere, even though the first-person
## watch-rig (first_person_watch_rig.tscn) already has a genuinely
## detailed palm/4-finger/thumb/watch-case design. That first-person
## rig is NOT rebuilt here (it already meets this round's hand/watch
## requirements); this is the missing other half -- giving the WORLD
## body (what the mirror and any future third-person/multiplayer view
## actually show) comparable hand and watch detail, built procedurally
## (this project's established pattern for geometry too repetitive to
## hand-author in .tscn text -- see e.g. the Round 18 electrical panel
## wire/terminal generation) so the same two builder functions serve
## both HandL/HandR and both StandingPose/SittingPose without 4x
## duplicated .tscn node trees.
## ============================================================

var _mat_glove_main: StandardMaterial3D
var _mat_glove_dark: StandardMaterial3D
var _mat_watch_strap: StandardMaterial3D
var _mat_watch_case: StandardMaterial3D
var _mat_watch_metal: StandardMaterial3D
var _mat_watch_face: StandardMaterial3D


## Round 21 Priority 1: ROOT PROBLEM (confirmed by reading
## player_body.tscn, not assumed): StandingPose/SittingPose's
## UpperArm/Elbow/LowerArm were THREE SEPARATE CSG primitives (cylinder
## + sphere + cylinder) unioned together by the parent CSGCombiner3D --
## a boolean union of differently-curved primitives meeting at a shared
## plane does not blend their surfaces, so every joint reads as a hard
## seam. This is the literal "raised hand/arm still looks like a bunch
## of cylinders" feedback, and it is specifically visible in the mirror
## because that is the one place the WORLD body's raised arm (not the
## first-person rig, which Round 20 already rebuilt) is actually seen
## up close. Fixed the same way Round 20 fixed the equivalent finger
## seam: one continuously-lofted tube mesh (HandMeshBuilder.build_tube)
## per arm, spine sampled through the SAME anchor positions
## (Shoulder/UpperArm/Elbow/LowerArm/Hand) the existing falloff-tween
## gesture system (animate_hand_laptop_gesture(), set_watch_raise_pose())
## already animates -- so no tween/gesture code changes at all, only
## what gets RENDERED through those live anchor positions changes. The
## old CSG primitives are hidden (not deleted -- CSGShape3D with
## visible=false is also excluded from its parent combiner's boolean
## operation, confirmed Godot behavior, so hiding them cleanly removes
## the old seamed geometry) but kept as the tween targets they already
## were, so _STANDING_ARM_NODES/_ARM_GESTURE_NODES and every caller that
## reads/writes their `.position` is completely unchanged.
## Round 23 Priority 3: LowerArm/Hand nudged up slightly (0.032/0.024 ->
## 0.036/0.028) -- player feedback was "forearms are too long"; the
## actual joint-to-joint LENGTH here is already close to anatomical
## (upper arm ~0.38 vs forearm ~0.30, roughly the real ~1.27:1 ratio),
## so shortening it further would have made it read as stubby instead.
## A thin, long, uniformly-tapered tube reads as "stretched" regardless
## of its real length -- a touch more thickness is the more honest fix
## for that specific visual impression without distorting the actual
## proportions.
const _ARM_RADII_STANDING: Dictionary = {"Shoulder": 0.052, "UpperArm": 0.048, "Elbow": 0.04, "LowerArm": 0.036, "Hand": 0.028}
const _ARM_RADII_SITTING: Dictionary = {"Shoulder": 0.048, "UpperArm": 0.044, "Elbow": 0.038, "LowerArm": 0.03, "Hand": 0.022}
var _arm_mesh_instances: Dictionary = {}
## Last spine this key's mesh was actually rebuilt from -- rebuilding a
## full ArrayMesh (SurfaceTool.commit()) is not free, and the anchors
## only ever move during the handful of seconds an actual tween
## (set_watch_raise_pose()/animate_hand_laptop_gesture()) is in flight;
## skipping the rebuild once the spine has settled avoids allocating a
## brand-new mesh resource 60 times a second forever for a static pose,
## which is both wasted per-frame work and (confirmed directly: a
## headless run churning through several real seconds of unconditional
## every-frame rebuilds left stray rendering-server RIDs at process
## exit) the kind of constant resource churn worth actually avoiding
## rather than shrugging off.
var _arm_last_spine: Dictionary = {}


## Hides the old 3-primitive CSG arm chain for one pose/side and adds a
## persistent (reused, not recreated per-frame) MeshInstance3D in its
## place, reusing the SAME material the CSG primitives already had so
## this is a geometry change only, not a re-skin. The mesh itself is
## filled in every frame by _update_arm_meshes() from the anchors' live
## (possibly mid-tween) positions.
func _setup_arm_limb(pose_root: Node3D, suffix: String, key: String) -> void:
	for part in ["UpperArm", "Elbow", "LowerArm"]:
		var old: Node = pose_root.get_node_or_null(part + suffix)
		if old != null and "visible" in old:
			old.visible = false
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ArmMesh" + suffix
	pose_root.add_child(mesh_instance)
	_arm_mesh_instances[key] = mesh_instance


func _rebuild_arm_mesh(pose_root: Node3D, suffix: String, key: String, radii_by_part: Dictionary) -> void:
	var mesh_instance: MeshInstance3D = _arm_mesh_instances.get(key)
	if mesh_instance == null:
		return
	var shoulder: Node3D = pose_root.get_node_or_null("Shoulder" + suffix)
	var upper: Node3D = pose_root.get_node_or_null("UpperArm" + suffix)
	var elbow: Node3D = pose_root.get_node_or_null("Elbow" + suffix)
	var lower: Node3D = pose_root.get_node_or_null("LowerArm" + suffix)
	var hand: Node3D = pose_root.get_node_or_null("Hand" + suffix)
	if shoulder == null or upper == null or elbow == null or lower == null or hand == null:
		return
	var spine: Array = [shoulder.position, upper.position, elbow.position, lower.position, hand.position]
	var last_spine: Array = _arm_last_spine.get(key, [])
	if last_spine.size() == spine.size():
		var unchanged := true
		for i in spine.size():
			if not (spine[i] as Vector3).is_equal_approx(last_spine[i]):
				unchanged = false
				break
		if unchanged:
			return
	_arm_last_spine[key] = spine.duplicate()
	var radii: Array = [radii_by_part["Shoulder"], radii_by_part["UpperArm"], radii_by_part["Elbow"], radii_by_part["LowerArm"], radii_by_part["Hand"]]
	# build_tube() returns a ready-to-add MeshInstance3D (its normal
	# contract -- see every OTHER caller, which does add it to the
	# tree); this caller only wants the Mesh RESOURCE to assign onto the
	# already-in-tree `mesh_instance` above, so the wrapper node itself
	# is immediately freed rather than left as an orphaned, un-parented
	# Node -- MeshInstance3D is a Node, not a RefCounted, so simply
	# letting the local variable go out of scope does NOT free it
	# (confirmed directly: without this, a `--quit-after` run left
	# exactly one orphaned, path-less MeshInstance3D + its ArrayMesh
	# leaked per rebuild call).
	var built: MeshInstance3D = _HandMeshBuilder.build_tube("ArmMesh" + suffix, spine, radii, 6, _arm_material)
	mesh_instance.mesh = built.mesh
	built.free()


## Only the currently-active pose's two arms are rebuilt each frame
## (LyingPose keeps its own simple CSGSphere3D hands/cylinder arms
## unchanged -- it is not the pose this feedback was about, and is
## rarely seen up close). Cheap: ~5 control points x 6 segments x 10
## sides per arm, two arms, rebuilt from already-known positions, no
## different from any other per-frame tween read in this script.
func _update_arm_meshes() -> void:
	match _pose:
		Pose.STANDING:
			_rebuild_arm_mesh(_standing_pose, "R", "standing_R", _ARM_RADII_STANDING)
			_rebuild_arm_mesh(_standing_pose, "L", "standing_L", _ARM_RADII_STANDING)
		Pose.SITTING:
			_rebuild_arm_mesh(_sitting_pose, "R", "sitting_R", _ARM_RADII_SITTING)
			_rebuild_arm_mesh(_sitting_pose, "L", "sitting_L", _ARM_RADII_SITTING)
		Pose.LYING:
			pass


## Round 21 Priority 7: builds one continuous lofted tube for a
## StandingPose leg (hip -> upper leg -> knee -> lower leg -> ankle),
## replacing the same kind of CSG sphere/cylinder primitive chain the
## arms had (HipCap sphere, UpperLeg cylinder, Knee sphere, LowerLeg
## cylinder, Ankle sphere -- confirmed in player_body.tscn). The Foot
## itself stays a plain CSGBox3D (a flat-surfaced shoe silhouette was
## never part of the "looks like cylinders" complaint, same reasoning
## _build_hand() already applies to the palm). Built once from each
## anchor's own rest position -- StandingPose's legs are never tweened
## by anything in this script, unlike the arms, so there is no live
## position to track after this initial build.
const _LEG_RADII: Dictionary = {"Hip": 0.095, "UpperLeg": 0.085, "Knee": 0.072, "LowerLeg": 0.058, "Ankle": 0.045}


func _build_leg_mesh(pose_root: Node3D, suffix: String) -> void:
	var hip: Node3D = pose_root.get_node_or_null("HipCap" + suffix)
	var upper: Node3D = pose_root.get_node_or_null("UpperLeg" + suffix)
	var knee: Node3D = pose_root.get_node_or_null("Knee" + suffix)
	var lower: Node3D = pose_root.get_node_or_null("LowerLeg" + suffix)
	var ankle: Node3D = pose_root.get_node_or_null("Ankle" + suffix)
	if hip == null or upper == null or knee == null or lower == null or ankle == null:
		return
	var material: Material = upper.material
	for part in ["UpperLeg", "Knee", "LowerLeg", "Ankle"]:
		var old: Node = pose_root.get_node_or_null(part + suffix)
		if old != null and "visible" in old:
			old.visible = false
	var spine: Array = [hip.position, upper.position, knee.position, lower.position, ankle.position]
	var radii: Array = [_LEG_RADII["Hip"], _LEG_RADII["UpperLeg"], _LEG_RADII["Knee"], _LEG_RADII["LowerLeg"], _LEG_RADII["Ankle"]]
	var built: MeshInstance3D = _HandMeshBuilder.build_tube("LegMesh" + suffix, spine, radii, 6, material)
	pose_root.add_child(built)


var _arm_material: Material


func _build_hands_and_watch() -> void:
	# Reuses this body's own existing "dark" material language (boots,
	# belt) for the glove rather than introducing a skin tone -- these
	# coveralls read as a work glove, consistent with the rest of the
	# uniform's material palette already authored here.
	_mat_glove_main = StandardMaterial3D.new()
	_mat_glove_main.albedo_color = Color(0.13, 0.13, 0.14, 1)
	_mat_glove_main.roughness = 0.75
	_mat_glove_dark = StandardMaterial3D.new()
	_mat_glove_dark.albedo_color = Color(0.09, 0.09, 0.1, 1)
	_mat_glove_dark.roughness = 0.75

	_mat_watch_strap = StandardMaterial3D.new()
	_mat_watch_strap.albedo_color = Color(0.11, 0.11, 0.12, 1)
	_mat_watch_strap.roughness = 0.8
	_mat_watch_case = StandardMaterial3D.new()
	_mat_watch_case.albedo_color = Color(0.14, 0.15, 0.16, 1)
	_mat_watch_case.roughness = 0.55
	_mat_watch_case.metallic = 0.3
	_mat_watch_metal = StandardMaterial3D.new()
	_mat_watch_metal.albedo_color = Color(0.58, 0.59, 0.62, 1)
	_mat_watch_metal.roughness = 0.25
	_mat_watch_metal.metallic = 0.82
	_mat_watch_face = StandardMaterial3D.new()
	_mat_watch_face.albedo_color = Color(0.03, 0.04, 0.04, 1)
	_mat_watch_face.roughness = 0.5

	_build_hand(_standing_pose.get_node("HandL"), false)
	_build_hand(_standing_pose.get_node("HandR"), true)
	_build_hand(_sitting_pose.get_node("HandL"), false)
	_build_hand(_sitting_pose.get_node("HandR"), true)

	# Round 21 Priority 1: all four arms (StandingPose/SittingPose x L/R)
	# get the lofted-tube limb treatment -- see _setup_arm_limb()'s own
	# doc comment. The CSG primitives being replaced all share this one
	# SubResource (confirmed in player_body.tscn: every Upper/Elbow/
	# Lower-Arm node uses the same "Mat_uniform"), captured here, once,
	# before any of them are hidden.
	_arm_material = _standing_pose.get_node("UpperArmR").material
	_setup_arm_limb(_standing_pose, "R", "standing_R")
	_setup_arm_limb(_standing_pose, "L", "standing_L")
	_setup_arm_limb(_sitting_pose, "R", "sitting_R")
	_setup_arm_limb(_sitting_pose, "L", "sitting_L")

	# Round 21 Priority 7: the same lofted-tube treatment for
	# StandingPose's legs (Hip cap -> UpperLeg -> Knee -> LowerLeg ->
	# Ankle), the other half of "assembled from cylinders" this round's
	# brief asked for if time allowed after the higher-priority arm/
	# mirror/storage/doorway/cabinet fixes. Built ONCE (not rebuilt per
	# frame like the arms): StandingPose's legs have no tween/gesture
	# system at all (only SittingPose's own get-up sequence animates
	# legs, and that pose is untouched here), so there is no live anchor
	# movement to track -- a single static mesh built from each anchor's
	# REST position is already correct for the whole pose's lifetime.
	_build_leg_mesh(_standing_pose, "R")
	_build_leg_mesh(_standing_pose, "L")

	# Round 21 Priority 1: ROOT PROBLEM for "the watch looks floating/
	# clipped" (confirmed by reading this code, not assumed) -- the
	# watch was built as a SIBLING of HandR under the pose root, at a
	# position FIXED in the pose root's own local space. set_watch_raise_pose()
	# tweens HandR's own `.position` (and the other arm anchors), but
	# never touched this sibling at all -- so raising the arm moved the
	# hand/fingers away while the watch stayed behind at its original
	# rest spot. Fixed by making the watch a CHILD of HandR instead (the
	# anchor that already correctly carries the palm/fingers through
	# every gesture), at the equivalent local offset -- it now inherits
	# HandR's own live, possibly mid-tween position for free, the same
	# way the hand/fingers already did.
	# Round 25: the watch now sits ON the forearm 5cm up from the wrist,
	# strap sized to the actual arm tube there -- see _build_wrist_watch().
	for entry in [[_standing_pose, _ARM_RADII_STANDING], [_sitting_pose, _ARM_RADII_SITTING]]:
		var placement: Dictionary = _wrist_watch_placement(entry[0], entry[1], 0.05)
		_build_wrist_watch(entry[0].get_node("HandR"), placement["dir"], 0.05, placement["radius"])


## Builds a palm + 4 fingers (each knuckle + two tapered segments + a
## matched-radius tip, not a floating sphere) + a separately-angled
## thumb on the palm's own side, as children of `root`. Canonical local
## frame: -Y points toward the fingertips, -Z is the palm's front face,
## X is hand width -- callers place/rotate `root` itself so that frame
## lines up with each pose's own arm (see the two StandingPose/
## SittingPose rotation choices in _build_hands_and_watch()). `is_right`
## mirrors the thumb side and finger X-fan so the same builder produces
## correct chirality for either hand.
func _build_hand(root: Node3D, is_right: bool) -> void:
	var side: float = 1.0 if is_right else -1.0

	var palm_wrist := CSGBox3D.new()
	palm_wrist.name = "PalmWrist"
	palm_wrist.size = Vector3(0.05, 0.03, 0.035)
	palm_wrist.position = Vector3(0, -0.018, 0)
	palm_wrist.material = _mat_glove_dark
	root.add_child(palm_wrist)

	var palm := CSGBox3D.new()
	palm.name = "Palm"
	palm.size = Vector3(0.066, 0.03, 0.06)
	palm.position = Vector3(0, -0.05, -0.005)
	palm.material = _mat_glove_main
	root.add_child(palm)

	# Round 20 Priority 2: the fingers/thumb are now ONE continuously
	# lofted tube mesh each (HandMeshBuilder), not a CSG chain of
	# knuckle-sphere + cylinder-segment + tip-sphere -- that CSG chain
	# produced a visible hard seam at every junction (CSG union does
	# not blend surfaces), which is the literal "looks like several
	# cylinders connected together" the player's own feedback named.
	# See hand_mesh_builder.gd's own class doc comment for the full
	# technique. The palm itself stays CSG boxes below (flat surfaces
	# were never the complaint).
	_HandMeshBuilder.build_fingers_and_thumb(root, is_right, _mat_glove_main)


## Round 25: rebuilt world-body wristwatch (the camera-relative first-person
## rig keeps its own, separately-framed watch -- see
## first_person_watch_rig.gd).
##
## ROOT CAUSE of the old "intersecting / floating watch geometry", found by
## measuring the built transforms, not assumed:
## 1. Bezel / FacePlate / rim screws were CHILDREN of a WatchCase that was
##    already rotated 90 deg about X, and each ALSO carried its own 90 deg X
##    rotation -- the rotation was inherited twice, so the dial discs lay
##    ALONG the forearm (face axis measured as (0,-1,0) at rest), slicing
##    crosswise through the case and the arm instead of facing outward.
## 2. The strap was a 0.062m-radius cuff on a ~0.03m-radius forearm tube,
##    and the case sat INSIDE that cuff.
## Now each watch gets ONE frame whose local +Y is the face normal (the
## dorsal side of the forearm, +Z in this project's canonical hand frame)
## and local +Z runs up the forearm toward the elbow. The strap hugs the
## arm tube; every dial part is an UNROTATED child of that frame (CSG
## cylinder axes are local Y = the face normal), so nothing is rotated
## twice. `forearm_dir_local` is the wrist->elbow direction in the hand's
## own local frame; `arm_radius` is the lofted arm tube's radius there.
func _build_wrist_watch(hand_root: Node3D, forearm_dir_local: Vector3, distance_from_wrist: float, arm_radius: float) -> void:
	var dir: Vector3 = forearm_dir_local.normalized()
	var dorsal: Vector3 = (Vector3(0, 0, 1) - dir * dir.z).normalized()
	var side: Vector3 = dorsal.cross(dir).normalized()
	var group := Node3D.new()
	group.name = "WristWatch"
	group.transform = Transform3D(Basis(side, dorsal, dir), dir * distance_from_wrist)
	hand_root.add_child(group)

	var strap_r: float = arm_radius + 0.003
	var strap := CSGCylinder3D.new()
	strap.name = "Strap"
	strap.radius = strap_r
	strap.height = 0.02
	strap.sides = 20
	strap.rotation_degrees = Vector3(90, 0, 0) # cylinder axis (local Y) -> along the forearm (local Z)
	strap.material = _mat_watch_strap
	group.add_child(strap)

	var case_h: float = 0.011
	var case_y: float = strap_r + case_h * 0.5 - 0.002
	var watch_case := CSGCylinder3D.new()
	watch_case.name = "WatchCase"
	watch_case.radius = 0.021
	watch_case.height = case_h
	watch_case.sides = 24
	watch_case.smooth_faces = true
	watch_case.position = Vector3(0, case_y, 0)
	watch_case.material = _mat_watch_case
	group.add_child(watch_case)

	var top_y: float = case_h * 0.5
	var bezel := CSGTorus3D.new()
	bezel.name = "Bezel"
	bezel.inner_radius = 0.0165
	bezel.outer_radius = 0.0215
	bezel.sides = 24
	bezel.ring_sides = 8
	bezel.position = Vector3(0, top_y, 0)
	bezel.material = _mat_watch_metal
	watch_case.add_child(bezel)

	var face := CSGCylinder3D.new()
	face.name = "FacePlate"
	face.radius = 0.0168
	face.height = 0.002
	face.sides = 24
	face.position = Vector3(0, top_y + 0.0005, 0)
	face.material = _mat_watch_face
	watch_case.add_child(face)

	for angle_deg in [45.0, 135.0, 225.0, 315.0]:
		var screw := CSGSphere3D.new()
		screw.name = "RimScrew"
		screw.radius = 0.0024
		var rad: float = deg_to_rad(angle_deg)
		screw.position = Vector3(0.019 * cos(rad), top_y + 0.0015, 0.019 * sin(rad))
		screw.material = _mat_watch_metal
		watch_case.add_child(screw)

	for lug_z in [0.022, -0.022]:
		var lug := CSGBox3D.new()
		lug.name = "LugTop" if lug_z > 0.0 else "LugBottom"
		lug.size = Vector3(0.016, 0.006, 0.01)
		lug.position = Vector3(0, -0.002, lug_z)
		lug.material = _mat_watch_metal
		watch_case.add_child(lug)

	var crown := CSGCylinder3D.new()
	crown.name = "Crown"
	crown.radius = 0.0035
	crown.height = 0.006
	crown.sides = 8
	crown.rotation_degrees = Vector3(0, 0, 90)
	crown.position = Vector3(0.0235, 0, 0)
	crown.material = _mat_watch_metal
	watch_case.add_child(crown)


## Round 25: forearm direction (wrist -> lower-arm anchor) in the hand's own
## local frame, plus the lofted arm tube's radius `dist` up from the wrist,
## so _build_wrist_watch() can wrap the strap around the actual arm.
func _wrist_watch_placement(pose_root: Node3D, radii: Dictionary, dist: float) -> Dictionary:
	var hand: Node3D = pose_root.get_node("HandR")
	var lower: Node3D = pose_root.get_node("LowerArmR")
	var seg: Vector3 = lower.position - hand.position
	var t: float = clampf(dist / seg.length(), 0.0, 1.0)
	return {
		"dir": hand.basis.inverse() * seg.normalized(),
		"radius": lerpf(radii["Hand"], radii["LowerArm"], t),
	}
## Round 25 Priority 1/2: the standing world body's watch-inspection pose,
## rebuilt as REAL JOINT ROTATION. Called by wristwatch_view.gd alongside
## (not instead of) the camera-relative first-person rig's own
## set_raised(); only acts while STANDING.
##
## ROOT CAUSE of "the reflected arm looks unnaturally long", measured
## (scratchpad arm_measure.gd; see MILESTONE1_DESIGN.md Round 25), not
## assumed: the old implementation never rotated anything. It TRANSLATED
## each joint anchor toward one hand target by a different fraction
## (UpperArm 0.2, Elbow 0.5, LowerArm 0.75, Hand 1.0) with the shoulder
## fixed. Segment lengths were therefore not preserved: shoulder->elbow
## collapsed from 0.377m to 0.143m and elbow->wrist from 0.300m to 0.193m
## (and varied mid-tween), the elbow barely bent (interior angle 159.5 ->
## 132.7 deg) and the forearm ended up pointing almost straight FORWARD
## (-Z 0.93). The upper arm effectively vanished into the shoulder, so the
## mirror showed one long limb thrusting out of the shoulder toward the
## glass. The rigid hand/watch assembly was then rotated by a shortest-arc
## quaternion with no control over forearm roll, so the watch face never
## turned toward the eyes (131 deg off).
##
## NOW: the arm is driven in joint space with constant segment lengths.
## - SHOULDER: the upper arm (ShoulderR->UpperArmR->ElbowR) rotates as one
##   rigid segment about the fixed shoulder point (ShoulderR never moves,
##   so it stays attached to the torso -- no shrug).
## - ELBOW: the forearm hinges about the elbow axis (the upper-arm x
##   forearm normal), so the elbow genuinely flexes.
## - WRIST: the forearm then rolls about its own axis (pronation) by the
##   amount that turns the watch face toward the eye; HandR (palm, fingers,
##   WristWatch) takes exactly the forearm's rotation, so hand and watch
##   stay rigidly attached to the wrist.
## The raised configuration is solved ONCE (analytic two-bone IK to a
## readable wrist position in front of the chest, elbow pole down/out/
## forward); the animation interpolates joint angles in sequence -- the
## shoulder leads, the elbow follows, the wrist turns last -- and simply
## runs backwards on release. Positions are recomputed from those angles
## each step (forward kinematics), so no segment can stretch mid-motion.
## Raised wrist position (body space: eye at origin, -Z forward, +X right)
## and the elbow pole direction for the two-bone solve. Exported so the
## pose can be tuned in the editor; _setup_watch_raise_rig() re-solves.
@export var watch_elbow_pole: Vector3 = Vector3(1.0, -0.4, -0.3)
## The world body moves a little slower than the snappy first-person rig
## (0.28s default) so the shoulder -> elbow -> wrist sequence reads as a
## natural gesture rather than a snap.
const _WORLD_RAISE_DURATION_SCALE: float = 1.5
var _watch_raise_progress: float = 0.0
var _watch_raise_tween: Tween
var _arm_rig: Dictionary = {}
var _watch_target_applied: Vector3 = Vector3(INF, INF, INF)
const _PoseStateScript = preload("res://scripts/player/character_pose_state.gd")
var _deltoid_r: MeshInstance3D


static func _limb_frame(axis: Vector3, hinge: Vector3) -> Basis:
	return Basis(axis, hinge, axis.cross(hinge))


func _setup_watch_raise_rig() -> void:
	var s: Vector3 = _standing_pose.get_node("ShoulderR").position
	var u_rest: Vector3 = _standing_arm_rest_pos["UpperArmR"]
	var e_rest: Vector3 = _standing_arm_rest_pos["ElbowR"]
	var l_rest: Vector3 = _standing_arm_rest_pos["LowerArmR"]
	var w_rest: Vector3 = _standing_arm_rest_pos["HandR"]
	var l1: float = s.distance_to(e_rest)
	var l2: float = e_rest.distance_to(w_rest)
	var u_r: Vector3 = (e_rest - s) / l1
	var f_r: Vector3 = (w_rest - e_rest) / l2
	var h_r: Vector3 = u_r.cross(f_r).normalized()

	var ff_r: Basis = _limb_frame(f_r, h_r)
	# Round 25: a relaxed standing hand hangs in NEUTRAL (palm facing the
	# thigh), not the fully supinated palm-forward "anatomical position"
	# the hand builder's canonical frame produces. With a supinated rest,
	# turning the dorsal watch face toward the eyes needed a -173.5 deg
	# forearm roll -- the unnatural near-180 twist. Neutral rest = the hand
	# pre-rotated 90 deg about its own forearm axis (palm -Z -> medial),
	# which leaves only a ~85 deg visible pronation during the gesture.
	var hand_rest_q := Quaternion(f_r, -PI / 2.0)
	var hand_l: Node3D = _standing_pose.get_node("HandL")
	var lower_l: Node3D = _standing_pose.get_node("LowerArmL")
	var f_l: Vector3 = (hand_l.position - lower_l.position).normalized()
	hand_l.quaternion = Quaternion(f_l, PI / 2.0)

	_arm_rig = {
		"s": s, "u_rest": u_rest, "e_rest": e_rest, "l_rest": l_rest, "w_rest": w_rest,
		"u_r": u_r, "h_r": h_r, "ff_r": ff_r, "f_r": f_r,
		"flex_r": u_r.angle_to(f_r), "hand_rest_q": hand_rest_q,
		"upper_len": l1, "fore_len": l2,
		"cap_rest": _standing_pose.get_node("ShoulderCapR").position,
		"watch_rest_local": (_standing_pose.get_node("HandR/WristWatch") as Node3D).transform,
	}
	_watch_target_applied = Vector3(INF, INF, INF)
	_update_watch_target(_shared_watch_target())

	# Round 26: the right deltoid cap was a CSG sphere inside the torso's
	# union (default layer) -- so while the arm was raised it stayed visible
	# to the player's own camera, a large grey ball in the lower-right of a
	# downward glance that the first-person sleeve passed through. The CSG
	# node stays as the (hidden) anchor the pose code already moves; the
	# visible deltoid is now its own mesh that follows it and switches to the
	# mirror-only layer with the rest of the raised arm.
	var cap_csg: CSGSphere3D = _standing_pose.get_node("ShoulderCapR")
	var deltoid := MeshInstance3D.new()
	deltoid.name = "DeltoidR"
	var sphere := SphereMesh.new()
	sphere.radius = cap_csg.radius
	sphere.height = cap_csg.radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	deltoid.mesh = sphere
	deltoid.material_override = cap_csg.material
	deltoid.transform = cap_csg.transform
	_standing_pose.add_child(deltoid)
	cap_csg.visible = false
	_deltoid_r = deltoid


## Round 27: the raised configuration follows the SHARED watch target
## (CharacterPoseState.watch_target: held at a fixed direction relative to
## the view, following look pitch 1:1 within body limits). The two-bone IK
## re-solves whenever that target moves (> 1mm), so limb lengths, the
## shoulder pivot and the elbow hinge are preserved by construction, and the
## forearm roll is re-derived each time so the face keeps turning toward the
## eye. The first-person rig is derived from THIS pose (see
## first_person_watch_rig.gd), so the player's own view and the mirror can
## no longer disagree.
const _CLAVICLE_LIFT: Vector3 = Vector3(0.0, 0.025, -0.01)
const _WATCH_ELBOW_POLE_HIGH: Vector3 = Vector3(1.0, 0.25, -0.15)
## Wrist flexion: the hand bends this fraction of the way from the
## forearm's slope back toward horizontal (fingers across, not pointing up
## past the face), capped -- see _apply_watch_raise().
const _WRIST_LEVEL_FRACTION: float = 0.6
const _WRIST_FLEX_MAX_DEG: float = 35.0


func _update_watch_target(target: Vector3) -> void:
	if target.distance_to(_watch_target_applied) < 0.001:
		return
	_watch_target_applied = target
	var cfg: Dictionary = _solve_raised(target)
	for key in ["q_upper", "flex_d", "roll", "target", "s_raised"]:
		_arm_rig[key] = cfg[key]


func _shared_watch_target() -> Vector3:
	if _pose_state != null:
		return _pose_state.watch_target
	return _PoseStateScript.watch_target_for_pitch(0.0)


## Analytic two-bone IK to `target` (body space) plus the forearm roll that
## turns the watch face toward the eye (body origin). Pure with respect to
## the rest data captured in _arm_rig.
func _solve_raised(target: Vector3) -> Dictionary:
	var rig: Dictionary = _arm_rig
	# Clavicle: the shoulder point rises/protracts a little when the watch is
	# held high (watch above lower-chest height), as a real shoulder girdle
	# does; segment lengths are measured from this moved pivot, so they stay
	# constant.
	# Round 27 follow-up: StandingPose is offset back from the eye (see the
	# "standing body offset" note above SELF_HIDDEN_TORSO_PARTS); targets
	# and the eye arrive in BODY space.
	target = target - _standing_pose.position
	var eye_local: Vector3 = -_standing_pose.position
	var lift: float = smoothstep(-0.30, -0.05, target.y)
	var s: Vector3 = (rig["s"] as Vector3) + _CLAVICLE_LIFT * lift
	var l1: float = rig["upper_len"]
	var l2: float = rig["fore_len"]
	var d: Vector3 = target - s
	var dist: float = clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dn: Vector3 = d.normalized()
	var along: float = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var out: float = sqrt(maxf(l1 * l1 - along * along, 0.0))
	# Round 27: for a high target (looking up) the elbow swings out toward
	# shoulder height so the forearm lies ACROSS in front of the face; with a
	# fixed downward pole the forearm stood vertical and the pose read as a
	# wave rather than a watch check.
	var high: float = smoothstep(-0.25, 0.15, target.y)
	var pole_dir: Vector3 = watch_elbow_pole.lerp(_WATCH_ELBOW_POLE_HIGH, high)
	var pole: Vector3 = (pole_dir - dn * pole_dir.dot(dn)).normalized()
	var e_d: Vector3 = s + dn * along + pole * out
	var w_d: Vector3 = s + dn * dist
	var u_d: Vector3 = (e_d - s) / l1
	var f_d: Vector3 = (w_d - e_d) / l2
	var h_d: Vector3 = u_d.cross(f_d).normalized()
	var u_r: Vector3 = rig["u_r"]
	var h_r: Vector3 = rig["h_r"]
	var q_upper: Quaternion = (_limb_frame(u_d, h_d) * _limb_frame(u_r, h_r).transposed()).get_rotation_quaternion()
	var roll: float = 0.0
	var watch: Node3D = _standing_pose.get_node("HandR").get_node_or_null("WristWatch")
	if watch != null:
		var r0: Basis = _limb_frame(f_d, h_d) * (rig["ff_r"] as Basis).transposed()
		var watch_rest: Transform3D = Transform3D(Basis(rig["hand_rest_q"]), Vector3.ZERO) * watch.transform
		var face_n: Vector3 = r0 * watch_rest.basis.y
		var face_p: Vector3 = e_d + r0 * (rig["w_rest"] - rig["e_rest"] + watch_rest.origin)
		var to_eye: Vector3 = eye_local - face_p
		var n_p: Vector3 = (face_n - f_d * face_n.dot(f_d)).normalized()
		var e_p: Vector3 = (to_eye - f_d * to_eye.dot(f_d)).normalized()
		roll = atan2(f_d.dot(n_p.cross(e_p)), n_p.dot(e_p))
	return {"q_upper": q_upper, "flex_d": u_d.angle_to(f_d), "roll": roll, "target": w_d, "s_raised": s}


## Forward kinematics for watch-raise progress `p` (0 = rest, 1 = fully
## inspecting). Shoulder leads, elbow follows, wrist roll comes last.
func _apply_watch_raise(p: float) -> void:
	_watch_raise_progress = p
	if _arm_rig.is_empty():
		return
	var rig: Dictionary = _arm_rig
	var upper_node: Node3D = _standing_pose.get_node("UpperArmR")
	var elbow_node: Node3D = _standing_pose.get_node("ElbowR")
	var lower_node: Node3D = _standing_pose.get_node("LowerArmR")
	var hand_node: Node3D = _standing_pose.get_node("HandR")
	var cap_node: Node3D = _standing_pose.get_node("ShoulderCapR")
	if p <= 0.0:
		_standing_pose.get_node("ShoulderR").position = rig["s"]
		cap_node.position = rig["cap_rest"]
		if _deltoid_r != null:
			_deltoid_r.position = cap_node.position
		upper_node.position = rig["u_rest"]
		elbow_node.position = rig["e_rest"]
		lower_node.position = rig["l_rest"]
		hand_node.position = rig["w_rest"]
		hand_node.quaternion = rig["hand_rest_q"]
		var rest_watch: Node3D = hand_node.get_node_or_null("WristWatch")
		if rest_watch != null:
			rest_watch.transform = rig["watch_rest_local"]
		return
	# Overlapping phases: the shoulder leads slightly, the elbow flexes
	# almost with it (a shoulder-only lead swings the arm out into a
	# forward reach first -- measured: wrist 0.54m in front of the body
	# mid-raise), and the wrist roll finishes last.
	var t_shoulder: float = smoothstep(0.0, 0.8, p)
	var t_elbow: float = smoothstep(0.05, 0.85, p)
	var t_wrist: float = smoothstep(0.4, 1.0, p)
	var b_upper := Basis(Quaternion.IDENTITY.slerp(rig["q_upper"], t_shoulder))
	var u: Vector3 = b_upper * rig["u_r"]
	var h: Vector3 = b_upper * rig["h_r"]
	var f: Vector3 = u.rotated(h, lerpf(rig["flex_r"], rig["flex_d"], t_elbow))
	var b_fore: Basis = Basis(f, rig["roll"] * t_wrist) * _limb_frame(f, h) * (rig["ff_r"] as Basis).transposed()
	var s: Vector3 = rig["s"]
	# Clavicle lift blends in with the shoulder phase; the whole upper-arm
	# segment rotates rigidly about the (possibly lifted) shoulder pivot.
	var s_now: Vector3 = s.lerp(rig.get("s_raised", s), t_shoulder)
	_standing_pose.get_node("ShoulderR").position = s_now
	var e: Vector3 = s_now + b_upper * (rig["e_rest"] - s)
	upper_node.position = s_now + b_upper * (rig["u_rest"] - s)
	# The deltoid cap belongs to the upper-arm segment: it must swing with
	# it, or it is left floating where the arm used to hang.
	cap_node.position = s_now + b_upper * (rig["cap_rest"] - s)
	if _deltoid_r != null:
		_deltoid_r.position = cap_node.position
	elbow_node.position = e
	lower_node.position = e + b_fore * (rig["l_rest"] - rig["e_rest"])
	hand_node.position = e + b_fore * (rig["w_rest"] - rig["e_rest"])
	# Wrist flexion (Round 27): bend the hand at the wrist toward horizontal
	# so the fingers point across rather than continuing a steep forearm
	# line. The watch sits on the FOREARM, not the hand, so it is
	# counter-rotated to stay put relative to the forearm.
	var forearm_q: Quaternion = b_fore.get_rotation_quaternion() * (rig["hand_rest_q"] as Quaternion)
	var flex_axis: Vector3 = f.cross(Vector3.UP)
	var flex_q := Quaternion.IDENTITY
	if flex_axis.length() > 0.01:
		var slope: float = asin(clampf(f.y, -1.0, 1.0))
		var cap: float = deg_to_rad(_WRIST_FLEX_MAX_DEG)
		# Rotating about (forearm x up) by a POSITIVE angle turns the hand
		# toward up, so levelling a rising forearm needs the negative slope.
		var flex: float = -clampf(slope * _WRIST_LEVEL_FRACTION, -cap, cap) * t_wrist
		flex_q = Quaternion(flex_axis.normalized(), flex)
	hand_node.quaternion = flex_q * forearm_q
	var watch: Node3D = hand_node.get_node_or_null("WristWatch")
	if watch != null:
		var undo: Quaternion = (flex_q * forearm_q).inverse() * forearm_q
		watch.transform = Transform3D(Basis(undo), Vector3.ZERO) * (rig["watch_rest_local"] as Transform3D)


## Round 25 Priority 3: the player's OWN camera must not see the world
## body's raised right arm -- that view belongs to the camera-relative
## first-person rig (layer 2). Measured by render: looking down with C
## held showed BOTH the first-person rig's hand/watch AND the world body's
## raised glove beside it (already faintly visible before this round, more
## so once the arm genuinely flexed up in front of the chest). While the
## arm is raised, its forearm tube and every hand/watch visual move to the
## head's mirror-only layer (value 4: excluded from the player camera's
## cull mask, rendered by the mirror and every other camera); at rest they
## return to the default layer so a downward glance still shows a hanging
## arm. Standing HandR is a plain Node3D (not a CSG child of the torso
## combiner) precisely so its palm/watch can carry their own layer.
const _MIRROR_ONLY_LAYER: int = 4
var _right_arm_mirror_only: bool = false


func _set_right_arm_mirror_only(value: bool) -> void:
	if value == _right_arm_mirror_only:
		return
	_right_arm_mirror_only = value
	var layer: int = _MIRROR_ONLY_LAYER if value else 1
	var arm_mesh: VisualInstance3D = _arm_mesh_instances.get("standing_R")
	if arm_mesh != null:
		arm_mesh.layers = layer
	var stack: Array = [_standing_pose.get_node("HandR")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = layer
		for c in n.get_children():
			stack.append(c)


func is_right_arm_mirror_only() -> bool:
	return _right_arm_mirror_only


## Round 26 Priority 5: per-camera visibility for the near-eye upper torso.
##
## With the whole-body tilt retired (see standing_pitch_follow), the body is
## upright and the eye sits directly above the shoulder yoke -- this body's
## torso is centred ~7cm IN FRONT of the eye -- so a downward glance from the
## player's own camera filled the lower half of the frame with the tops of
## the shoulders/yoke/chest at ~0.3m (rendered and confirmed: a large grey
## dome; and the camera-locked watch sank into it). In a real body that
## region is behind your own chin and jaw, and the player's camera already
## cannot see its own head/collar (layer 4) for the same reason. These
## upper-torso pieces now render on that same mirror-only layer: the mirror,
## surveillance and any other camera see the complete body, while the
## player's own downward glance shows belt, hips, legs and arms. The original
## CSG nodes stay in StandingPose as hidden anchors (pose code and existing
## tests address them by name); their visual duplicates live in a separate
## combiner under a plain Node3D so they are not part of the torso union.
## Standing body offset (Round 27 follow-up): StandingPose and HeadGroup sit
## 0.10m BEHIND the eye/camera (player_body.tscn). Measured from the
## player's own camera at an 80 deg downward look with C held: the torso
## (belt/belly/hips) covered 20% of the frame in the lower centre and the
## hanging left arm 13% lower-left, because this body had been built with
## its torso centred 7-10cm IN FRONT of the eye -- the reverse of a real
## person, whose eyes are ~10cm in front of the neck/torso axis. Looking
## straight down therefore looked onto the top of the belly and shoulders.
## Only the visuals moved: the camera, collision capsule and the
## CarryAnchor/LapAnchor (PlayerBody children) are unchanged.
##
## Round 27 follow-up (measured by rendered pixel diff, C held): with only the
## chest hidden, looking 60-80 deg down still showed the remaining torso top
## (belly bridge/waist/belt/pelvis cylinder) as a flat-topped grey disc
## covering 31-37% of the lower-centre region, plus the top caps of the
## hanging arm tubes as floating "stumps" near the eye (their shoulders are
## hidden). The player's own camera now uses "legs-only" body awareness: the
## whole torso and both arms/hands render only for the mirror and every
## other camera; the player's own view shows thighs and feet (and the
## first-person watch arm while C is held).
const SELF_HIDDEN_TORSO_PARTS: Array = ["TrapeziusBase", "ChestYoke", "ShoulderL", "ShoulderR", "ShoulderCapL", "Chest", "ChestPocket", "AccentStripe", "TorsoBridgeUpper", "Waist", "TorsoBridgeLower", "Belt", "Hips"]


func _split_self_hidden_upper_torso() -> void:
	var holder := Node3D.new()
	holder.name = "SelfHiddenTorso"
	_standing_pose.add_child(holder)
	var combiner := CSGCombiner3D.new()
	combiner.name = "UpperTorso"
	combiner.layers = _MIRROR_ONLY_LAYER
	holder.add_child(combiner)
	for part_name in SELF_HIDDEN_TORSO_PARTS:
		var src: CSGShape3D = _standing_pose.get_node_or_null(part_name)
		if src == null:
			continue
		var dup: CSGShape3D = src.duplicate()
		dup.visible = true
		combiner.add_child(dup)
		dup.transform = src.transform
		src.visible = false
	if _deltoid_r != null:
		_deltoid_r.layers = _MIRROR_ONLY_LAYER
	# Both arms and hands: mirror-only for the standing pose (see the doc
	# above). The raised right arm's first-person view is the watch rig.
	var left_mesh: VisualInstance3D = _arm_mesh_instances.get("standing_L")
	if left_mesh != null:
		left_mesh.layers = _MIRROR_ONLY_LAYER
	for hand_name in ["HandL"]:
		for v in _standing_pose.get_node(hand_name).find_children("*", "VisualInstance3D", true, false):
			(v as VisualInstance3D).layers = _MIRROR_ONLY_LAYER
	_set_right_arm_mirror_only(true)


## Round 26: the world watch's live pose (global space) for the
## first-person rig's downward-look presentation: the watch position and the
## unit direction from the wrist toward the elbow (forearm axis).
func world_watch_pose() -> Dictionary:
	var hand: Node3D = _standing_pose.get_node("HandR")
	var elbow: Node3D = _standing_pose.get_node("ElbowR")
	var watch: Node3D = hand.get_node("WristWatch")
	return {
		"watch": watch.global_position,
		"to_elbow": (elbow.global_position - hand.global_position).normalized(),
	}


func watch_raise_progress() -> float:
	return _watch_raise_progress


func watch_raise_rig() -> Dictionary:
	return _arm_rig


func _stop_watch_raise(instant_rest: bool) -> void:
	if _watch_raise_tween != null and _watch_raise_tween.is_valid():
		_watch_raise_tween.kill()
	if instant_rest:
		_apply_watch_raise(0.0)


func set_watch_raise_pose(raised: bool, duration: float) -> void:
	if _pose != Pose.STANDING:
		return
	_stop_watch_raise(false)
	var target: float = 1.0 if raised else 0.0
	var span: float = absf(target - _watch_raise_progress)
	var dur: float = duration * _WORLD_RAISE_DURATION_SCALE * span
	if dur <= 0.0:
		_apply_watch_raise(target)
		return
	_watch_raise_tween = create_tween()
	_watch_raise_tween.tween_method(_apply_watch_raise, _watch_raise_progress, target, dur)
func _apply_pose() -> void:
	_standing_pose.visible = _pose == Pose.STANDING
	_sitting_pose.visible = _pose == Pose.SITTING
	_lying_pose.visible = _pose == Pose.LYING
	_head_group.visible = _pose == Pose.STANDING
	# Round 28: the rig's head mesh is mirror-only in EVERY pose (the eye is
	# inside it), so the lying/sitting character keeps its head.
	if _rig != null:
		_rig.head_mesh.visible = true
	rotation.x = 0.0
	if _pose == Pose.STANDING:
		rotation.y = _look_pivot.rotation.y


# ======================================================================
# Round 28: the rigged technician as the visible character
# ======================================================================
## Round 28 Priority 1/2/3. The visible character is now the skinned
## Skeleton3D technician (scripts/character/technician_rig.gd). Everything
## above this point -- the CSG poses, their anchors and tweens, the
## watch-raise progress, the sitting/get-up/laptop gestures -- keeps running
## exactly as before and stays the tested source of pose data; its geometry
## is simply no longer rendered (layers = 0) while the rig is active.
## `use_rigged_visual = false` restores the old visuals as a fallback.
##
## ROOT CAUSE of the straight-down self view (measured, Round 28): the old
## body's legs were raked ~20 deg forward (hip caps 0.03m in front of the eye,
## feet 0.32m in front) and its torso was hidden from the player's camera,
## so a straight-down look landed on two thigh-top spheres directly under
## the eye. The rig is built on a vertical ear-shoulder-hip-ankle plumb line
## with the eye 9cm in front of it (EYE_POINT), and its torso, arms and legs
## are ONE continuous skinned body visible to the player's own camera; only
## the head/neck mesh (the eye is inside it) is mirror-only.
##
## ROOT CAUSE of "fingers in the mirror but not in first person" (Round 28):
## they were two different models -- the world body's hand and the separate
## camera-attached first-person rig, whose oversized watch strap/case sits
## between the camera and its own short finger meshes at upward looks. Now
## both views render the SAME rig arm, hand and watch; the old first-person
## rig is suppressed.
const _TechnicianRigScene = preload("res://scenes/character/technician_rig.tscn")
@export var use_rigged_visual: bool = true
var _rig: Node3D = null
var _walk_phase: float = 0.0
var _walk_amount: float = 0.0
var _last_global_pos: Vector3 = Vector3(INF, INF, INF)
var _carry_blend: float = 0.0
var _rig_roll_target: Vector3 = Vector3(INF, INF, INF)
var _rig_roll: float = 0.0


func rigged_visual() -> Node3D:
	return _rig


func _setup_rigged_visual() -> void:
	_rig = _TechnicianRigScene.instantiate()
	_rig.name = "RiggedVisual"
	add_child(_rig)
	if _rig.skeleton == null:
		_rig.build()
	_hide_legacy_visuals()
	if _watch_rig != null and "suppress_presentation" in _watch_rig:
		_watch_rig.suppress_presentation = true
	_update_rig(0.0)


## The legacy CSG/mesh visuals stay in the tree (their nodes are the tested
## pose anchors and keep their transforms/tweens) but every visual BELOW the
## four pose roots is hidden, so each root renders an empty union. Only
## _apply_pose() toggles visibility afterwards, and it touches the roots
## only. (Setting `layers = 0` at runtime instead was tried first and
## crashed the Godot 4.7 renderer -- "indexing did not unpair geometries
## from light" followed by SIGSEGV -- so visibility is used.)
func _hide_legacy_visuals() -> void:
	for root in [_standing_pose, _sitting_pose, _lying_pose, _head_group]:
		for n in (root as Node).find_children("*", "VisualInstance3D", true, false):
			(n as VisualInstance3D).visible = false


func _carry_system() -> Node:
	return get_parent().get_node_or_null("CarrySystem") if get_parent() != null else null


func _update_rig(delta: float) -> void:
	if _rig == null:
		return
	if _rig_shown_pose != _pose:
		_begin_pose_crossfade(_pose)
	_rig.reset_pose()
	match _pose:
		Pose.STANDING:
			_compose_standing(delta)
			_eye_offset_cached = _rig_eye() - _rig.EYE_POINT
			if _sit_preview_t >= 0.0:
				_compose_sit_preview(delta)
		Pose.SITTING:
			_seated_follow_w = move_toward(_seated_follow_w, _seated_follow_target, delta * 2.5) if delta > 0.0 else _seated_follow_target
			_compose_seated()
		Pose.LYING:
			var hips: Vector3 = to_local(_lying_pose.get_node("Hips").global_position)
			var shoulders: Vector3 = to_local(_lying_pose.get_node("Shoulders").global_position)
			# Lie FLAT on the back: the body axis is the hips->shoulders
			# direction projected onto the horizontal (the legacy anchors tilt
			# ~14 deg head-down, which put the rig's head through the
			# mattress), front (-Z) facing up so the back (+Z) points down.
			var y_axis: Vector3 = Vector3(shoulders.x - hips.x, 0.0, shoulders.z - hips.z).normalized()
			var z_axis: Vector3 = Vector3.DOWN
			var basis := Basis(y_axis.cross(z_axis), y_axis, z_axis)
			# Raise so the back rests at the legacy hip height, and anchor
			# along the body axis at the SHOULDERS (Round 29: anchored at the
			# hips, the rig's longer legs put the boots past the bunk's foot).
			var neck_rest: Vector3 = _rig.rest_pos("Neck")
			var anchor := Vector3(shoulders.x, hips.y, shoulders.z)
			_rig.transform = Transform3D(basis, anchor + Vector3(0, 0.1, 0) - basis * neck_rest)
			_pose_lying_head()
			# Arms rest along the sides, slightly bent (hands on the mattress).
			for side in ["Right", "Left"]:
				_rig.set_local(side + "UpperArm", Quaternion(Vector3.FORWARD, deg_to_rad(8.0 if side == "Right" else -8.0)))
				_rig.set_local(side + "LowerArm", Quaternion(Vector3.RIGHT, deg_to_rad(15.0)))
	if _rig_xfade_t < 1.0:
		# Out-of-frame refreshes (delta 0, e.g. from set_sitting()) never
		# advance the blend -- they used to complete it instantly.
		_rig_xfade_t = minf(_rig_xfade_t + delta / _xfade_dur, 1.0)
		var snap: Dictionary = {"rot": _rig_snap["rot"], "xf": global_transform.affine_inverse() * _rig_snap_gxf}
		_rig.crossfade_from(snap, smoothstep(0.0, 1.0, _rig_xfade_t))
	if _pose != Pose.SITTING:
		_place_lap_anchor()   # restores the authored spot
	_rig.apply_to_skeleton()
	_rig_applied = _rig.snapshot()
	_rig_applied_gxf = _rig.global_transform
	_update_carry_anchor()
	if _watch_rig != null:
		var label: Node = _watch_rig.get_node_or_null("ArmGroup/WatchAssembly/WatchFaceText")
		if label != null:
			_rig.set_watch_text(_compact_watch_text(label.text))
	var cam: Node3D = _pitch_pivot.get_node_or_null("Camera3D")
	if cam != null and _watch_raise_progress > 0.0:
		_rig.level_watch_text(cam)


## Round 29 Priority 2: lying head. The lying face points UP (rig -Z), so
## the player's look is measured against the torso, not the horizon:
## looking toward the feet lifts the head (chin toward chest, neck 60% /
## head 40%, up to 55 deg) the way a person in bed does, so the eye -- and
## the camera on it -- rises off the mattress and sees down the body
## instead of grazing along the chest; looking back past the headboard
## tips it back a little.
const LYING_HEAD_LIFT_MAX_DEG: float = 55.0
const LYING_HEAD_EXTEND_MAX_DEG: float = 15.0


func _pose_lying_head() -> void:
	var cam: Node3D = _pitch_pivot.get_node_or_null("Camera3D")
	if cam == null:
		return
	var fwd: Vector3 = (_rig.global_basis.orthonormalized().inverse() * (-cam.global_basis.z)).normalized()
	var toward_feet: float = atan2(-fwd.y, -fwd.z)   # 0 = straight up out of the face
	var flex: float = clampf(toward_feet * 0.7, -deg_to_rad(LYING_HEAD_EXTEND_MAX_DEG), deg_to_rad(LYING_HEAD_LIFT_MAX_DEG))
	_rig.pose_look(0.0, -flex * 0.6, -flex * 0.4)


func _compose_standing(delta: float) -> void:
	_rig.transform = Transform3D(Basis(), -_rig.EYE_POINT)
	_update_rig_walk(delta)
	if floating:
		_pose_eva_legs(delta)
	if _pose_state != null:
		_rig.pose_look(_pose_state.spine_pitch, _pose_state.neck_pitch, _pose_state.head_pitch)
	# Round 32: bend at the waist to place a part on a LOW surface (bed);
	# eases back after the release.
	var lean_goal: float = _place_lean if _place_t >= 0.0 else 0.0
	_lean_w = move_toward(_lean_w, lean_goal, delta / 0.3) if delta > 0.0 else lean_goal
	if _lean_w > 0.0:
		_rig.set_local("Spine", _rig.get_local("Spine") * Quaternion(Vector3.RIGHT, -deg_to_rad(PLACE_LEAN_MAX_DEG) * 0.6 * _lean_w))
		_rig.set_local("Hips", Quaternion(Vector3.RIGHT, -deg_to_rad(PLACE_LEAN_MAX_DEG) * 0.4 * _lean_w))
	var carry: Node = _carry_system()
	# A pending reach (Round 31: ownership only at the grasp) animates the
	# arm exactly like carrying.
	var carrying: bool = carry != null and (carry.is_carrying() or (carry.has_method("is_reaching") and carry.is_reaching()))
	_carry_blend = move_toward(_carry_blend, 1.0 if carrying else 0.0, delta * 4.0) if delta > 0.0 else (1.0 if carrying else 0.0)
	if _watch_raise_progress > 0.0:
		_pose_watch_arm()
	elif floating or not _eva_reach.is_empty():
		_pose_eva_arms(delta)
	elif _consume_t >= 0.0:
		_pose_consume_arm(delta)
	elif _carry_blend > 0.0:
		_pose_carry_arm(delta)


## Watch inspection arm (Round 28 shared target; Round 29 Priority 4 high
## range). The target comes from CharacterPoseState (shared with every
## view). Round 29: above eye level the old pose clamped the watch to eye
## height ~0.33m straight ahead -- ~0.53m from the shoulder for a 0.565m
## arm, i.e. a locked-straight "reaching forward" arm at 35 deg up. Now the
## target keeps rising with the look but comes CLOSER, and the clavicle
## elevates/protracts (a real shoulder shrug) so the elbow stays bent; the
## elbow pole swings out to the side for high holds so the forearm rises
## in front of the face instead of pointing at it.
const WATCH_CLAVICLE_ELEVATION_DEG: float = 24.0
const WATCH_CLAVICLE_PROTRACTION_DEG: float = 14.0


func _pose_watch_arm() -> void:
	var tgt_body: Vector3 = _shared_watch_target()
	var look_pitch: float = _pose_state.look_pitch if _pose_state != null else 0.0
	# 0 at/below a level look: EXACTLY the Round 28 pose (the approved
	# level/downward watch check). Eases to the high-hold pose above it.
	var up: float = smoothstep(0.0, deg_to_rad(25.0), look_pitch)
	var e: float = atan2(tgt_body.y, -tgt_body.z)
	# Round 28 high-hold shaping (keyed to target height): wrist slightly out
	# and forward, elbow pole rising toward shoulder height.
	var old_high: float = smoothstep(-0.25, 0.0, tgt_body.y)
	var old_pole: Vector3 = Vector3(0.55, -1.0, 0.05).lerp(Vector3(1.0, 0.05, -0.3), old_high)
	# Round 29 high hold: clavicle shrug + protraction, elbow out to the side
	# and a little below the wrist, target measured from the ACTUAL posed eye
	# (looking up tips the head back, carrying the eye back/down).
	var lift: float = up * (0.5 + 0.5 * smoothstep(0.0, deg_to_rad(40.0), e)) * smoothstep(0.0, 1.0, _watch_raise_progress)
	_rig.set_local("RightShoulder", Quaternion(Vector3.UP, deg_to_rad(WATCH_CLAVICLE_PROTRACTION_DEG) * lift) * Quaternion(Vector3.BACK, deg_to_rad(WATCH_CLAVICLE_ELEVATION_DEG) * lift))
	var eye_ref: Vector3 = _rig.EYE_POINT.lerp(_rig_eye(), up)
	var tgt: Vector3 = tgt_body + eye_ref + Vector3(0.12, 0.0, -0.06) * old_high * (1.0 - up)
	var pole: Vector3 = old_pole.lerp(Vector3(0.85, -0.75, -0.25), up).lerp(Vector3(0.45, -1.0, -0.55), smoothstep(deg_to_rad(30.0), deg_to_rad(60.0), look_pitch))
	# Gaze: while reading the watch the head bows toward it (on top of the
	# shared look angles) -- the mirror shows someone LOOKING at their
	# watch, not staring past it.
	var to_watch: Vector3 = tgt_body.normalized()
	var gaze: float = asin(clampf(to_watch.y, -1.0, 1.0)) - look_pitch
	var gaze_head: float = clampf(gaze * 0.6, deg_to_rad(-30.0), 0.0) * smoothstep(0.3, 1.0, _watch_raise_progress)
	_rig.set_local("Head", _rig.get_local("Head") * Quaternion(Vector3.RIGHT, gaze_head))
	if tgt.distance_to(_rig_roll_target) > 0.001:
		_rig_roll_target = tgt
		_rig_roll = _rig.watch_roll_toward(eye_ref, tgt, pole)
	_rig.pose_arm_ik("Right", tgt, pole, _watch_raise_progress, _rig_roll, _WRIST_LEVEL_FRACTION)
	# High holds: the hand relaxes forward at the wrist (flexion AWAY from
	# the eye) instead of standing upright like a wave; the dial is on the
	# back of the wrist, so it stays clear and facing the eye.
	var relax: float = deg_to_rad(WATCH_HIGH_WRIST_RELAX_DEG) * up * smoothstep(0.3, 1.0, _watch_raise_progress)
	if relax > 0.0:
		var hp: Vector3 = _rig.bone_pos("RightHand")
		var f: Vector3 = (hp - _rig.bone_pos("RightLowerArm")).normalized()
		var axis: Vector3 = f.cross((eye_ref - hp).normalized())
		if axis.length() > 0.05:
			_rig.set_global("RightHand", Basis(axis.normalized(), -relax) * _rig.bone_basis("RightHand"))


const WATCH_HIGH_WRIST_RELAX_DEG: float = 55.0


## Priority 5 (Round 28): the right hand genuinely holds the carried part.
## Carry pose: forearm forward, hand in front of the right hip/belly,
## within reach. Reach sequence: hand OUT to the part (which stays put),
## grasp, then both travel back to the carry pose.
func _pose_carry_arm(delta: float) -> void:
	var hold_body: Vector3 = CARRY_HAND_TARGET
	var blend: float = _carry_blend
	var carry: Node = _carry_system()
	if carry == null or not (carry.is_carrying() or (carry.has_method("is_reaching") and carry.is_reaching())):
		# Released (dropped/stowed/installed), possibly mid-reach: the arm
		# eases home from where the hand ACTUALLY was, never from the
		# nominal carry pose (that jumped the hand ~0.9 m in one frame).
		for n in _CARRY_ARM_BONES.size():
			_rig.set_local(_CARRY_ARM_BONES[n], Quaternion.IDENTITY.slerp(_last_arm_rot[n], blend))
		return
	if _reach_t >= 0.0:
		_reach_t += delta
		var grasp: Vector3 = _reach_from_body + Vector3(0.0, 0.07, 0.0)
		if _reach_t >= REACH_OUT_S and not _grasp_sent:
			# The hand has arrived: ownership transfers NOW.
			_grasp_sent = true
			if carry != null and carry.has_method("complete_grasp") and carry.is_reaching():
				if not carry.complete_grasp():
					return
		if _reach_t < REACH_OUT_S:
			hold_body = grasp
			# Linear here: pose_arm_ik() already eases each joint (shoulder
			# leads, elbow, then wrist); a second ease doubled the peak hand
			# speed (~9 m/s measured) into a snap.
			blend = clampf(_reach_t / REACH_OUT_S, 0.0, 1.0)
		else:
			var k: float = smoothstep(REACH_OUT_S, REACH_TOTAL_S, _reach_t)
			hold_body = grasp.lerp(CARRY_HAND_TARGET, k)
			if _reach_t >= REACH_TOTAL_S:
				_reach_t = -1.0
			else:
				# Return to the carry pose in JOINT space (slerp between the
				# solved grasp and carry arms): sliding the IK target in a
				# straight line swung the elbow through its pole region at
				# ~7 m/s mid-return.
				var pole := Vector3(0.9, -1.0, 0.2)
				var roll: float = deg_to_rad(-70.0)
				var bones := ["RightUpperArm", "RightLowerArm", "RightHand"]
				_rig.pose_arm_ik("Right", grasp + _rig.EYE_POINT, pole, 1.0, roll, 0.0)
				var qa: Array = bones.map(func(b): return _rig.get_local(b))
				_rig.pose_arm_ik("Right", CARRY_HAND_TARGET + _rig.EYE_POINT, pole, 1.0, roll, 0.0)
				for n in bones.size():
					_rig.set_local(bones[n], (qa[n] as Quaternion).slerp(_rig.get_local(bones[n]), k))
				_last_hold_body = hold_body
				_remember_arm()
				return
			blend = 1.0
	if _place_t >= 0.0:
		# Round 32 place gesture: the hand carries the part out to the place
		# point (still held), then carry_system releases it there.
		_place_t += delta
		hold_body = hold_body.lerp(_place_target_body, smoothstep(0.0, _place_dur, _place_t))
		var carry_c: Node = _carry_system()
		if carry_c == null or not carry_c.is_carrying():
			_place_t = -1.0
	_last_hold_body = hold_body
	var hold: Vector3 = hold_body + _rig.EYE_POINT
	_rig.pose_arm_ik("Right", hold, Vector3(0.9, -1.0, 0.2), blend, deg_to_rad(-70.0) * blend, 0.0)
	_remember_arm()


## The carry arm as last SHOWN (local rotations) -- a release eases from
## exactly this to rest, whatever phase the reach/carry was in.
const _CARRY_ARM_BONES := ["RightUpperArm", "RightLowerArm", "RightHand"]
var _last_arm_rot: Array = [Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion.IDENTITY]


func _remember_arm() -> void:
	for n in _CARRY_ARM_BONES.size():
		_last_arm_rot[n] = _rig.get_local(_CARRY_ARM_BONES[n])


## Seated pose in BODY space, independent of where the body currently is
## (SittingPose's own transform is identity, so its anchors' local
## positions are body-space): reclined spine, look, eye pinned to the
## body origin (= the seated camera), legs/hands IK'd to the tested
## legacy sitting anchors (get-up leg swing, laptop reach).
func _compose_seated() -> void:
	_rig.pose_sit()
	# Recline + placement are solved at a NEUTRAL look so the pelvis stays
	# planted on the mattress whatever the player looks at; the look then
	# bends neck/head/upper spine and the camera follows that posed eye
	# (see _update_eye_anchor(), same anatomical anchor as standing).
	_pose_rig_seated_recline()
	var neutral_eye: Vector3 = _rig_eye()
	if _pose_state != null:
		_rig.pose_look(_pose_state.spine_pitch, _pose_state.neck_pitch, _pose_state.head_pitch)
	# _seated_follow_w = 1: pelvis planted, camera follows the posed head.
	# 0 (laptop open): the posed eye itself is pinned to the camera, so the
	# laptop/editor framing (which positions the CAMERA) is never shifted
	# by the head; the pelvis absorbs it instead. Blended, so no jump.
	var posed_eye: Vector3 = _rig_eye()
	_seated_pin_shift = (posed_eye - neutral_eye) * (1.0 - _seated_follow_w)
	_rig.transform = Transform3D(Basis(), -(neutral_eye + _seated_pin_shift))
	# The legacy anchors were authored around the legacy hip; the reclined
	# rig's pelvis sits a little fore/aft of it, so the feet and hands move
	# with the pelvis (horizontal shift only -- floor contact stays on the
	# floor) and the legs keep their authored hip->ankle geometry instead
	# of folding the knees up toward the chest.
	var hip_shift: Vector3 = _rig.transform * _rig.bone_pos("Hips") - _sitting_pose.get_node("Hips").position
	hip_shift.y = 0.0
	for side in ["Left", "Right"]:
		var suffix: String = side.substr(0, 1)
		var ankle_node: Node3D = _sitting_pose.get_node("Ankle" + suffix)
		var ankle_b: Vector3 = ankle_node.position + hip_shift
		if seated_on_bed:
			# Round 30 Priority 2: on the bunk the legs lie OUT along the
			# mattress (thighs flat, knees soft) -- the folded legacy anchors
			# raised the knees in front of the laptop screen. The get-up leg
			# swing (which moves the legacy ankle anchors) blends back to them.
			var hip_j: Vector3 = _rig.transform * _rig.bone_pos(side + "UpperLeg")
			var out := hip_j + Vector3(0.0, BED_LEG_DROP, -BED_LEG_REACH)
			var swing: float = 0.0
			var key: String = "Ankle" + suffix
			if _leg_rest_transform.has(key):
				swing = clampf(ankle_node.position.distance_to((_leg_rest_transform[key] as Transform3D).origin) / 0.35, 0.0, 1.0)
			ankle_b = out.lerp(ankle_b, smoothstep(0.0, 1.0, swing))
		_rig.pose_leg_ik(side, _rig.transform.affine_inverse() * ankle_b)
	_place_lap_anchor()
	for side in ["Left", "Right"]:
		var suffix: String = side.substr(0, 1)
		var hand_b: Vector3 = _sitting_pose.get_node("Hand" + suffix).position + hip_shift
		var sx: float = 1.0 if side == "Right" else -1.0
		var kb: Variant = _laptop_hand_target(side)
		if kb != null:
			hand_b = kb
		_rig.pose_arm_ik(side, _rig.transform.affine_inverse() * hand_b, Vector3(sx, -1.0, 0.3), 1.0, 0.0, 0.0)


## Round 30 Priority 2: seat style + lap placement. sleep_state.gd sets
## seated_on_bed (legs out along the mattress, laptop on the thighs); the
## workstation chair keeps the legacy anchors.
var seated_on_bed: bool = false
const BED_LEG_REACH: float = 0.74   # hip joint -> ankle, along the mattress
const BED_LEG_DROP: float = -0.06
## Laptop base rests this far above the thighs' centre line (thigh radius
## ~0.085 m + a little clearance).
const LAP_ABOVE_THIGH: float = 0.1
## laptop_view.gd's held_local_rotation_degrees.x (front edge down).
const LAPTOP_HOLD_PITCH_DEG: float = 20.0
var _lap_anchor_rest = null


func set_seat_style(on_bed: bool) -> void:
	seated_on_bed = on_bed


## LapAnchor rides on top of the rig's actual thighs (midway hip->knee,
## both legs) while seated on the bunk; elsewhere it keeps its authored
## spot. The laptop is parented to it while open/held.
func _place_lap_anchor() -> void:
	var lap: Node3D = get_node_or_null("LapAnchor")
	if lap == null:
		return
	if _lap_anchor_rest == null:
		_lap_anchor_rest = lap.position
	if not seated_on_bed or _pose != Pose.SITTING:
		lap.position = _lap_anchor_rest
		lap.basis = Basis()
		return
	var mid := Vector3.ZERO
	var slope := 0.0
	for side in ["Left", "Right"]:
		var a: Vector3 = _rig.transform * _rig.bone_pos(side + "UpperLeg")
		var b: Vector3 = _rig.transform * _rig.bone_pos(side + "LowerLeg")
		mid += a.lerp(b, 0.62)
		slope += atan2(b.y - a.y, Vector2(b.x - a.x, b.z - a.z).length())
	mid *= 0.5
	slope *= 0.5
	# From the NEUTRAL seated placement: while the laptop is open the rig
	# slides a little to keep the eye on the camera as the head moves; the
	# laptop must not drift with the player's look.
	lap.position = mid + _seated_pin_shift + Vector3(0.0, LAP_ABOVE_THIGH, 0.0)
	# The base lies ALONG the thighs: they rise toward the knees, and
	# laptop_view.gd holds the laptop pitched -20 deg (front edge down), so
	# the anchor pitches up by the thigh slope plus that hold angle.
	lap.basis = Basis(Vector3.RIGHT, slope + deg_to_rad(LAPTOP_HOLD_PITCH_DEG))


## While the laptop is open on the lap, the hands rest on its keyboard
## (palm heels at the front edge), in body space. null otherwise.
func _laptop_hand_target(side: String) -> Variant:
	var lap: Node3D = get_node_or_null("LapAnchor")
	if lap == null or not seated_on_bed:
		return null
	for c in lap.get_children():
		if c is Node3D and "is_open" in c and c.is_open:
			var sx: float = 0.075 if side == "Right" else -0.075
			return to_local((c as Node3D).to_global(Vector3(sx, 0.03, 0.06)))
	return null


## Round 29 Priority 2/7: sit-down preview. The logical pose (and every
## caller's timing) is unchanged -- set_sitting(true) still arrives only
## once the sit-down tween settles -- but while the camera travels to the
## seat, the VISIBLE body eases from the live standing pose into the
## final seated pose already placed at the seat (world space), instead of
## the standing body being dragged down through the bunk with the camera
## and then snapping. Started by begin_sit_down().
var _sit_preview_t: float = -1.0
var _sit_preview_dur: float = 1.0
var _sit_preview_eye: Vector3 = Vector3.ZERO
var _sit_preview_w: float = 0.0


func begin_sit_down(seat_eye_global: Vector3, duration: float) -> void:
	if _rig == null or _pose != Pose.STANDING:
		return
	_sit_preview_t = 0.0
	_sit_preview_dur = maxf(duration, 0.05)
	_sit_preview_eye = seat_eye_global
	_sit_preview_w = 0.0


func sit_down_preview_weight() -> float:
	return _sit_preview_w if _sit_preview_t >= 0.0 else 0.0


func _compose_sit_preview(delta: float) -> void:
	_sit_preview_t += delta
	if _sit_preview_t > _sit_preview_dur + 1.5:
		# The sit was abandoned without ever settling: ease back to
		# standing through the ordinary pose-switch crossfade.
		_sit_preview_t = -1.0
		_rig_snap = _rig_applied
		_rig_snap_gxf = _rig_applied_gxf
		_rig_xfade_t = 0.0
		return
	_sit_preview_w = smoothstep(0.0, _sit_preview_dur, _sit_preview_t)
	var stand: Dictionary = _rig.snapshot()
	_rig.reset_pose()
	_compose_seated()
	# Where the body WILL be once seated: the seat eye, seated yaw.
	var parent_g: Transform3D = get_parent().global_transform if get_parent() is Node3D else Transform3D()
	var seat_body := Transform3D(parent_g.basis.orthonormalized() * Basis(Vector3.UP, deg_to_rad(sitting_world_yaw_degrees)), _sit_preview_eye)
	_rig.transform = global_transform.affine_inverse() * seat_body * _rig.transform
	_rig.crossfade_from(stand, _sit_preview_w)
	_eye_offset_cached *= (1.0 - _sit_preview_w)


## Pose SWITCH (stand/sit/lie): crossfade from what was last SHOWN (in
## world space -- the body's own yaw changes at the switch). Called by
## set_sitting()/set_lying() at the moment of the switch, so the snapshot
## never depends on whether a tween callback ran before or after this
## node's _process() that frame.
func _begin_pose_crossfade(new_pose: int) -> void:
	if _rig == null or new_pose == _rig_shown_pose:
		return
	if _rig_shown_pose != -1 and not _rig_applied.is_empty():
		_rig_snap = _rig_applied
		_rig_snap_gxf = _rig_applied_gxf
		_rig_xfade_t = 0.0
		var cam0: Node3D = _pitch_pivot.get_node_or_null("Camera3D")
		_cam_from = cam0.position if cam0 != null else Vector3.ZERO
	_rig_shown_pose = new_pose


const POSE_XFADE_S: float = 0.4
## Duration of the current pose-switch crossfade (lying down / sitting up
## use their whole transition time).
var _xfade_dur: float = POSE_XFADE_S
var _rig_shown_pose: int = -1
var _rig_snap: Dictionary = {}
var _rig_snap_gxf: Transform3D = Transform3D()
var _rig_xfade_t: float = 1.0
var _rig_applied: Dictionary = {}
var _rig_applied_gxf: Transform3D = Transform3D()
var _cam_from: Vector3 = Vector3.ZERO
var _eye_offset_cached: Vector3 = Vector3.ZERO


## Round 29 Priority 2 ROOT CAUSE ("sitting on the bed, the body covers the
## screen"): the legacy SittingPose anchors describe a RECLINED sitter --
## hips 0.20m in FRONT of and 0.56m below the eye, shoulders behind it --
## but the rig sat bolt upright on those hips, so its head landed 0.38m in
## front of the camera. The camera was therefore BEHIND the character's
## head: neck, shoulders and upper back sat 0.22-0.29m ahead of the lens
## and filled the frame (measured; only the head itself is camera-hidden).
## Fix: lean the rig back from its pelvis toward the legacy hips->eye
## direction (a person leaning back against the bunk wall), then pin its
## posed eye exactly on the camera (body origin). The camera, LookPivot,
## laptop framing and capsule are untouched.
func _pose_rig_seated_recline() -> void:
	# Two constraints: the eye exactly on the camera (body origin) AND the
	# pelvis resting at seat height (the legacy hip anchor's height, so the
	# seat never sinks into or floats above the mattress). With the torso's
	# hips->eye length fixed by the current pose (look included), the
	# recline angle is what satisfies both; the pelvis slides a few cm
	# fore/aft as the head moves, which is what a reclined sitter does.
	var seat_y: float = _sitting_pose.get_node("Hips").position.y + SEATED_HIP_RAISE
	var recline: float = 0.0
	for _i in 3:
		_rig.set_local("Hips", Quaternion(Vector3.RIGHT, recline * 0.4))
		_rig.set_local("Spine", Quaternion(Vector3.RIGHT, deg_to_rad(-4.0) + recline * 0.6))
		var have: Vector3 = _rig_eye() - _rig.bone_pos("Hips")
		var h: float = -seat_y                     # wanted hips->eye height
		var len_yz: float = Vector2(have.y, have.z).length()
		var want_z: float = sqrt(maxf(len_yz * len_yz - h * h, 0.0))  # eye BEHIND hips (+Z)
		var ang_have: float = atan2(have.z, have.y)
		var ang_want: float = atan2(want_z, h)
		recline = clampf(recline + (ang_want - ang_have), deg_to_rad(-10.0), deg_to_rad(45.0))
	_rig.set_local("Hips", Quaternion(Vector3.RIGHT, recline * 0.4))
	_rig.set_local("Spine", Quaternion(Vector3.RIGHT, deg_to_rad(-4.0) + recline * 0.6))
	_seated_recline = recline


## The rig's Hips bone sits ~2cm above the legacy pelvis-centre anchor for
## the same seat contact (the rig's buttocks are ~0.13m below that bone).
const SEATED_HIP_RAISE: float = 0.02
var _seated_follow_w: float = 1.0
var _seated_pin_shift: Vector3 = Vector3.ZERO
var _seated_follow_target: float = 1.0


## sleep_state.gd turns seated head-follow OFF while the laptop is open
## (its zoom/aim tweens place the camera precisely) and back ON after.
func set_seated_head_follow(enabled: bool) -> void:
	_seated_follow_target = 1.0 if enabled else 0.0


func seated_head_follow_weight() -> float:
	return _seated_follow_w
var _seated_recline: float = 0.0


## The rig's eye point under its CURRENT pose, in rig space.
func _rig_eye() -> Vector3:
	return _rig.bone_pos("Head") + _rig.bone_basis("Head") * (_rig.EYE_POINT - _rig.rest_pos("Head"))


## Round 28 Priority 5: the carried item sits IN the rig's right palm.
## carry_system.gd parents the item to CarryAnchor at a fixed local offset
## (held_local_position); here CarryAnchor itself follows the palm so the
## item and the hand stay together through pickup, carry and drop. Before
## and after carrying, CarryAnchor returns to its authored position.
const CARRY_HAND_TARGET: Vector3 = Vector3(0.17, -0.62, -0.30)
var _carry_anchor_rest = null


## Reach sequence: [0, REACH_OUT_S) hand travels to the item (item stays
## put), then the hand grasps and both travel to the carry pose by
## REACH_TOTAL_S. -1 = no reach in progress.
const REACH_OUT_S: float = 0.6
var _last_hold_body: Vector3 = CARRY_HAND_TARGET
const REACH_TOTAL_S: float = 1.2
var _reach_t: float = -1.0
var _reach_from_body: Vector3 = Vector3.ZERO
var _carry_connected: bool = false


## Round 32: place gesture toward `target_global` (the part's centre).
var _place_t: float = -1.0
var _place_dur: float = 0.35
var _place_target_body: Vector3 = Vector3.ZERO


const PLACE_LEAN_MAX_DEG: float = 35.0
var _place_lean: float = 0.0
var _lean_w: float = 0.0


func begin_place(target_global: Vector3, duration: float) -> void:
	_place_t = 0.0
	_place_dur = maxf(duration, 0.05)
	# Lean in proportion to how far below hand height the spot is.
	var below: float = global_position.y - target_global.y
	_place_lean = clampf((below - 0.6) / 0.45, 0.0, 1.0)
	# The palm sits ~7 cm above the held part's centre.
	_place_target_body = to_local(target_global) + Vector3(0.0, 0.07, 0.0)


func is_placing() -> bool:
	return _place_t >= 0.0


## Round 31 Priority 7: a physical reach is possible (rig present, standing,
## not mid sit-down); otherwise carry_system.gd claims the part at once.
func can_reach() -> bool:
	return _rig != null and _pose == Pose.STANDING and _sit_preview_t < 0.0


## The reach was cancelled before the grasp: the arm eases home from where
## it was (the release branch of _pose_carry_arm()).
func cancel_reach() -> void:
	_reach_t = -1.0
	_grasp_sent = true


var _grasp_sent: bool = true


func _on_item_picked_up(_item: Node3D, from_global: Transform3D) -> void:
	_grasp_sent = false
	_reach_from_body = to_local(from_global.origin)
	_reach_t = 0.0 if _pose == Pose.STANDING and _rig != null else -1.0


func is_reaching() -> bool:
	return _reach_t >= 0.0


func _palm_body() -> Vector3:
	var palm_rig: Vector3 = _rig.bone_pos("RightHand") + _rig.bone_basis("RightHand") * Vector3(0.0, -0.07, -0.01)
	return to_local(_rig.to_global(palm_rig))


func _update_carry_anchor() -> void:
	var anchor: Node3D = get_node_or_null("CarryAnchor")
	if anchor == null:
		return
	if _carry_anchor_rest == null:
		_carry_anchor_rest = anchor.position
	var carry: Node = _carry_system()
	if carry != null and not _carry_connected and carry.has_signal("item_picked_up"):
		carry.item_picked_up.connect(_on_item_picked_up)
		_carry_connected = true
	if carry != null and carry.has_method("is_reaching") and carry.is_reaching():
		anchor.position = _carry_anchor_rest   # the part is not in the hand yet
		return
	if carry == null or not carry.is_carrying() or _pose != Pose.STANDING or _rig == null:
		anchor.position = _carry_anchor_rest
		_reach_t = -1.0
		return
	var held: Vector3 = carry.held_local_position
	if _reach_t >= 0.0 and _reach_t < REACH_OUT_S:
		# Hand still on its way: the part stays exactly where it was.
		anchor.position = _reach_from_body - held
		return
	# Grasped: the part rides in the palm.
	anchor.position = _palm_body() - held


## Round 29 Priority 5: gait. ROOT CAUSES of "the steps look too large"
## (measured with real W input): the old cycle advanced one step per
## 0.75m while footstep sounds play every 0.85m (so contacts drifted
## against the sounds), its legs swung +/-24 deg with 38 deg knees like
## pendulums, and the "planted" foot slid at 1.38 m/s in the world (77% of
## walking speed). Now: contacts are locked to the footstep accumulator
## itself (free_move_controller.gd gait_position(): a heel strike at every
## footstep sound), feet are PLACED by leg IK on a shorter 0.55m sweep
## (0.25 ahead / 0.30 behind; thighs within ~22 deg instead of 24 deg plus
## 38 deg pendulum knees) with a swing arc, each foot is on the ground for
## 68% of a step period (so its sweep matches the ground it covers), and
## the pelvis drops a few cm so the knees stay softly flexed. At 1.8 m/s
## and an 0.85m cadence the footprint spacing itself is fixed by physics
## (speed / cadence); see test_gait_footsteps.gd for measured slide.
var gait_source: Node = null
const GAIT_STEP_DISTANCE: float = 0.85
const GAIT_REACH_AHEAD: float = 0.25
const GAIT_REACH_BEHIND: float = 0.30
const GAIT_PELVIS_DROP: float = 0.02
const GAIT_TELEPORT_SPEED: float = 6.0
var _gait_own: float = 0.0
var _gait_offset: float = 0.0
var _gait_last: float = 0.0
var _gait_used_src: bool = false
var _gait_raw_prev: float = 0.0
var _speed_est: float = 0.0
var _gait_dir: Vector2 = Vector2(0.0, -1.0)


func gait_position() -> float:
	var use_src: bool = gait_source != null and gait_source.has_method("gait_position") and "active" in gait_source and gait_source.active
	var raw: float = gait_source.gait_position() if use_src else _gait_own
	if use_src != _gait_used_src or raw < _gait_raw_prev - 0.0005:
		# Source switch (free movement re-activated after a scripted move)
		# or an accumulator reset (stopping restarts the stride at a whole
		# step): keep the legs' phase continuous; the offset is dropped once
		# the legs are at rest, so contacts re-lock to the footstep sounds
		# for the next walk.
		_gait_offset = _gait_last - raw
		_gait_used_src = use_src
	_gait_raw_prev = raw
	if _walk_amount < 0.02:
		_gait_offset = 0.0
	_gait_last = raw + _gait_offset
	return _gait_last


func walk_amount() -> float:
	return _walk_amount


func _update_rig_walk(delta: float) -> void:
	var gp: Vector3 = global_position
	var moved := Vector3.ZERO
	if delta > 0.0 and is_finite(_last_global_pos.x):
		moved = Vector3(gp.x - _last_global_pos.x, 0.0, gp.z - _last_global_pos.z)
		# A teleport (scene setup, the post-sit sync) is not walking: an
		# implausible per-frame speed would kick the walk blend on.
		if moved.length() / delta > GAIT_TELEPORT_SPEED:
			moved = Vector3.ZERO
	_last_global_pos = gp
	var step_d: float = gait_source.step_distance if gait_source != null and "step_distance" in gait_source else GAIT_STEP_DISTANCE
	if moved.length() > 0.0005:
		_gait_own += moved.length() / step_d
	elif delta > 0.0:
		_gait_own = floorf(_gait_own)  # same "stopped -> restart the stride" rule
	# Speed: low-passed (render frames can outnumber physics ticks, so many
	# frames see zero displacement -- the old per-frame estimate collapsed
	# the walk blend to ~0 at high frame rates).
	if delta > 0.0:
		var inst: float = moved.length() / delta
		_speed_est = lerpf(_speed_est, inst, 1.0 - exp(-delta * 12.0))
		var v: Vector3 = moved / delta
		if gait_source != null and gait_source.has_method("horizontal_velocity") and gait_source.active:
			v = gait_source.horizontal_velocity()
		var vb: Vector3 = global_basis.orthonormalized().inverse() * v
		if Vector2(vb.x, vb.z).length() > 0.2:
			_gait_dir = _gait_dir.lerp(Vector2(vb.x, vb.z).normalized(), 1.0 - exp(-delta * 10.0)).normalized()
	var target: float = clampf(_speed_est / 1.6, 0.0, 1.0) if _speed_est > 0.08 else 0.0
	if floating:
		target = 0.0          # Round 39: drifting in zero-g is not walking
	_walk_amount = move_toward(_walk_amount, target, delta * 4.0) if delta > 0.0 else target
	# Any continuity offset bleeds away while walking (<= 0.8 step/s), so
	# heel strikes always re-lock onto the footstep sounds.
	if delta > 0.0:
		_gait_offset = move_toward(_gait_offset, 0.0, delta * 0.8)
	_walk_phase = gait_position()
	if _walk_amount > 0.01:
		_rig.transform.origin.y -= GAIT_PELVIS_DROP * _walk_amount
		_rig.pose_gait(_walk_phase, _gait_dir, _walk_amount, GAIT_REACH_AHEAD, GAIT_REACH_BEHIND, _watch_raise_progress <= 0.0 and _carry_blend <= 0.0)


func set_watch_text(text: String) -> void:
	if _rig != null:
		_rig.set_watch_text(_compact_watch_text(text))


## The rig's real-size 48mm dial shows short glanceable codes: the same
## message as wristwatch_view.gd composes, with room names abbreviated
## (e.g. "CHECK IN\nCONTROL ROOM" -> "CHECK IN\nCTRL RM").
const _WATCH_ABBREV := {"CONTROL ROOM": "CTRL RM", "ENGINEERING": "ENGR", "LIFE SUPPORT": "LIFE SUP", "COMMUNICATIONS": "COMMS", "LIVING QUARTERS": "QUARTERS", "STORAGE": "STORAGE"}


static func _compact_watch_text(text: String) -> String:
	var out: String = text
	for k in _WATCH_ABBREV:
		out = out.replace(k, _WATCH_ABBREV[k])
	return out


## Round 28 Priority 1: anatomical eye anchor. ROOT CAUSE of the remaining
## straight-down view problem, confirmed by render with the rig in place:
## the camera ROTATED IN PLACE at the eye, so at 80 deg down the lower half
## of the 72 deg frame looked ~26 deg BEHIND vertical, straight onto the
## top of the player's own chest/shoulders -- a view no real eye has,
## because looking down flexes the neck and carries the eyes forward and
## down around it. While standing, the camera node follows the rig's posed
## head (the pose the mirror shows), see eye_anchor_offset(). Only the Camera3D's LOCAL offset changes -- the
## LookPivot/PitchPivot controller, capsule and movement are untouched, and
## at a level look the offset is exactly zero. The interaction ray and the
## flashlight live on/under this camera, so they move with the eye.
var _eye_anchor_active: bool = false


## The eye's displacement (body space) from its rest point for the rig's
## CURRENT posed head: the eye is carried by the same spine/neck/head bone
## rotations the mirror shows (CharacterPoseState's anatomical split), so the
## camera sits exactly where the reflected character's eyes are.
func eye_anchor_offset() -> Vector3:
	if _rig == null or _pose != Pose.STANDING:
		return Vector3.ZERO
	# Computed from the TARGET pose before any pose-switch crossfade, so a
	# half-blended seated/standing skeleton never drags the camera.
	return _eye_offset_cached


## Round 29 Priority 2: per-pose camera target (Camera3D LOCAL position):
## - standing: the anatomical eye anchor above;
## - sitting: the seated rig's posed eye (zero at a neutral look -- the
##   rig is placed so its neutral eye IS the seat camera);
## - lying: the lying rig's eye (the camera lies where the head lies,
##   looking up out of the face, never from inside the torso).
## Pose switches blend from where the camera was, over the same
## crossfade as the body, so getting up never jumps the view.
func _update_eye_anchor() -> void:
	var cam: Node3D = _pitch_pivot.get_node_or_null("Camera3D")
	if cam == null:
		return
	if _rig == null:
		if _eye_anchor_active:
			cam.position = Vector3.ZERO
			_eye_anchor_active = false
		return
	var target: Vector3 = Vector3.ZERO
	match _pose:
		Pose.STANDING:
			target = _pitch_pivot.basis.inverse() * eye_anchor_offset()
		Pose.SITTING, Pose.LYING:
			# An OFFSET from the body origin, rotated into PitchPivot space --
			# never an absolute position, so LookPivot's own offsets (the
			# laptop editor zoom) still move the camera.
			var eye_body: Vector3 = _rig.transform * _rig_eye()
			target = (cam.get_parent() as Node3D).global_basis.orthonormalized().inverse() * (global_basis.orthonormalized() * eye_body)
	if _rig_xfade_t < 1.0:
		target = _cam_from.lerp(target, smoothstep(0.0, 1.0, _rig_xfade_t))
	cam.position = target
	_eye_anchor_active = target != Vector3.ZERO



# ======================================================================
# Round 39 Priority 5: a readable EAT / DRINK gesture. The right hand brings
# a prop (red mug, water pouch or meal pouch) from the waist up to the
# mouth, holds it there (a sip / two bites), and lowers it again; the prop
# follows the real hand bone, so the mirror and cameras show it too.
# ======================================================================
const CONSUME_MOUTH_HEAD := Vector3(0.03, -0.04, -0.27)   # head-bone space: wrist in front of the mouth
const CONSUME_REST := Vector3(0.2, -0.5, -0.32)
var _consume_t: float = -1.0
var _consume_dur: float = 2.4
var _consume_kind: String = ""
var _consume_prop: Node3D = null
signal consume_finished(kind: String)


func begin_consume(kind: String, duration: float = 2.4) -> bool:
	if _rig == null or _pose != Pose.STANDING or _consume_t >= 0.0:
		return false
	_consume_kind = kind
	_consume_dur = maxf(duration, 0.6)
	_consume_t = 0.0
	_consume_prop = _make_consume_prop(kind)
	_rig.add_child(_consume_prop)
	return true


func is_consuming() -> bool:
	return _consume_t >= 0.0


func consume_progress() -> float:
	return clampf(_consume_t / _consume_dur, 0.0, 1.0) if _consume_t >= 0.0 else 0.0


## World position of the held prop (tests / tools).
func consume_prop_position() -> Vector3:
	return _consume_prop.global_position if _consume_prop != null else Vector3.INF


func _pose_consume_arm(delta: float) -> void:
	_consume_t += delta
	var u: float = _consume_t / _consume_dur
	# 0-0.28 raise, 0.28-0.78 at the mouth (bites/sips), 0.78-1 lower.
	var k: float
	if u < 0.28:
		k = smoothstep(0.0, 0.28, u)
	elif u < 0.78:
		k = 1.0
	else:
		k = 1.0 - smoothstep(0.78, 1.0, u)
	# The mouth follows the HEAD bone (looking down at the counter pitches
	# the spine / neck / head forward -- a fixed body-space point ended up
	# beside the temple). The wrist stops just below and in front of it so
	# the held prop is at the lips.
	var ofs: Vector3 = CONSUME_MOUTH_HEAD
	if u >= 0.28 and u < 0.78:
		# Bites: the hand dips away and back; sips: a slow tilt (prop rotation).
		var eating: bool = _consume_kind in ["meal", "dinner"]
		var bob: float = sin((u - 0.28) / 0.5 * TAU * (2.0 if eating else 1.0))
		ofs += Vector3(0.0, -0.04, -0.04) * maxf(bob, 0.0) * (1.0 if eating else 0.3)
		if _consume_kind == "brush":
			# Round 43: brushing -- a quick side-to-side scrub at the mouth.
			ofs = CONSUME_MOUTH_HEAD + Vector3(sin(_consume_t * TAU * 3.2) * 0.03, -0.01, 0.02)
	var mouth_rig: Vector3 = _rig.bone_pos("Head") + _rig.bone_basis("Head") * ofs
	var hold_rig: Vector3 = (CONSUME_REST + _rig.EYE_POINT).lerp(mouth_rig, k)
	var blend: float = clampf(minf(u / 0.12, (1.0 - u) / 0.12), 0.0, 1.0)
	_rig.pose_arm_ik("Right", hold_rig, Vector3(0.9, -1.0, 0.2), blend, deg_to_rad(-80.0) * blend, 0.0)
	_remember_arm()
	if _consume_prop != null:
		var hp: Vector3 = _rig.bone_pos("RightHand")
		var hb: Basis = _rig.bone_basis("RightHand")
		_consume_prop.position = hp + hb * Vector3(0.0, -0.07, 0.0)
		var tilt: float = 0.0
		if not _consume_kind in ["meal", "dinner", "brush"] and u >= 0.28 and u < 0.78:
			tilt = smoothstep(0.28, 0.45, u) * (1.0 - smoothstep(0.65, 0.78, u)) * deg_to_rad(55.0)
		_consume_prop.basis = Basis(Vector3.RIGHT, tilt)
		_consume_prop.visible = u > 0.03 and u < 0.97
	if _consume_t >= _consume_dur:
		_consume_t = -1.0
		if _consume_prop != null:
			_consume_prop.queue_free()
			_consume_prop = null
		consume_finished.emit(_consume_kind)


func _make_consume_prop(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "ConsumeProp"
	var add := func(mesh: Mesh, col: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.5
		mi.material_override = m
		mi.position = pos
		mi.rotation_degrees = rot
		root.add_child(mi)
	match kind:
		"tea":
			var c := CylinderMesh.new()
			c.top_radius = 0.04
			c.bottom_radius = 0.036
			c.height = 0.09
			add.call(c, Color(0.85, 0.3, 0.25), Vector3.ZERO)
			var h := TorusMesh.new()
			h.inner_radius = 0.012
			h.outer_radius = 0.026
			add.call(h, Color(0.85, 0.3, 0.25), Vector3(0.045, 0.0, 0.0), Vector3(90, 0, 0))
			var t := CylinderMesh.new()
			t.top_radius = 0.034
			t.bottom_radius = 0.034
			t.height = 0.004
			add.call(t, Color(0.45, 0.25, 0.1), Vector3(0, 0.04, 0))
		"water":
			var b := BoxMesh.new()
			b.size = Vector3(0.07, 0.11, 0.025)
			add.call(b, Color(0.55, 0.75, 0.95), Vector3.ZERO)
			var st := CylinderMesh.new()
			st.top_radius = 0.004
			st.bottom_radius = 0.004
			st.height = 0.05
			add.call(st, Color(0.95, 0.95, 0.95), Vector3(0.0, 0.075, 0.0))
		"brush":
			# Round 43: the toothbrush (teal handle, white bristle head).
			var hdl := BoxMesh.new()
			hdl.size = Vector3(0.012, 0.16, 0.012)
			add.call(hdl, Color(0.2, 0.75, 0.75), Vector3(0, 0.04, 0), Vector3(70, 0, 0))
			var head := BoxMesh.new()
			head.size = Vector3(0.016, 0.028, 0.02)
			add.call(head, Color(0.97, 0.97, 0.97), Vector3(0, 0.07, -0.07), Vector3(70, 0, 0))
		"dinner":
			# Round 43: the evening meal is a heated foil TRAY with a spork --
			# a different object (and moment) from the breakfast pouch.
			var tray := BoxMesh.new()
			tray.size = Vector3(0.15, 0.03, 0.1)
			add.call(tray, Color(0.78, 0.78, 0.8), Vector3(0, -0.02, 0))
			var stew := BoxMesh.new()
			stew.size = Vector3(0.13, 0.006, 0.085)
			add.call(stew, Color(0.45, 0.28, 0.15), Vector3(0, -0.003, 0))
			var spork := BoxMesh.new()
			spork.size = Vector3(0.012, 0.12, 0.006)
			add.call(spork, Color(0.95, 0.6, 0.2), Vector3(0.03, 0.05, 0.0), Vector3(-30, 0, 0))
		_:
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.09, 0.13, 0.03)
			add.call(b2, Color(0.75, 0.55, 0.25), Vector3.ZERO)
			var sp := CylinderMesh.new()
			sp.top_radius = 0.008
			sp.bottom_radius = 0.008
			sp.height = 0.03
			add.call(sp, Color(0.3, 0.3, 0.32), Vector3(0.0, 0.08, 0.0))
	return root



# ======================================================================
# Round 39 Priority 6C/6D: EVA presentation of the body.
# ======================================================================
## Zero-g: no walk cycle; the legs hang slightly bent (set by eva_system.gd).
var floating: bool = false
var eva_suit: bool = false


func set_floating(on: bool) -> void:
	floating = on


## The technician visibly wears the EVA suit (white suit, life-support
## pack, helmet with a gold visor) -- seen in the mirror, on cameras and
## from outside; the helmet is mirror/camera-only like the head.
func set_eva_suit(on: bool) -> void:
	eva_suit = on
	if _rig != null and _rig.has_method("set_eva_suit"):
		_rig.set_eva_suit(on)


# ======================================================================
# Round 41 Priority 9: EVA ANIMATION SET on the existing rig (authored
# poses blended per frame -- no new skeleton, no physics limbs).
#   idle   -- arms float a little out from the sides, knees soft, a slow
#             breathing drift;
#   thrust -- body extends (legs straighten), arms trail back;
#   coast  -- relaxed between idle and thrust;
#   brake  -- knees come up, arms forward (hands in view: stabilising);
#   work   -- foot-restraint stance (knees bent), both hands forward to
#             the work point (eva_system worksite);
#   reach  -- one arm IK'd to a world point (the tether hand carries the
#             carabiner to a ring / back to it to release; the left hand
#             grabs the outer-hatch frame on the way back in).
# Weights ease at 3/s, so no pose snaps; arm IK keeps limb lengths fixed.
# ======================================================================
var _eva_pose: String = "none"
var _eva_reach: Dictionary = {}
var _eva_w: Dictionary = {"idle": 0.0, "thrust": 0.0, "coast": 0.0, "brake": 0.0, "work": 0.0}
var _eva_reach_w: Dictionary = {"Left": 0.0, "Right": 0.0}
var _eva_t: float = 0.0


func set_eva_pose(pose: String, reach: Dictionary) -> void:
	_eva_pose = pose
	_eva_reach = reach


func eva_pose_weights() -> Dictionary:
	return _eva_w.duplicate()


func _pose_eva_legs(delta: float) -> void:
	_eva_t += delta
	for k in _eva_w:
		var goal: float = 1.0 if _eva_pose == k else 0.0
		_eva_w[k] = move_toward(float(_eva_w[k]), goal, delta * 3.0) if delta > 0.0 else goal
	var w: Dictionary = _eva_w
	var drift: float = sin(_eva_t * 1.4) * 0.04
	var hip: float = 0.22 + 0.3 * w["brake"] + 0.45 * w["work"] - 0.16 * w["thrust"] - 0.06 * w["coast"]
	var knee: float = -0.4 - 0.5 * w["brake"] - 0.6 * w["work"] + 0.28 * w["thrust"] + 0.1 * w["coast"]
	for side in ["Right", "Left"]:
		var sgn: float = 1.0 if side == "Right" else -1.0
		_rig.set_local(side + "UpperLeg", Quaternion(Vector3.RIGHT, hip + drift * sgn) * Quaternion(Vector3.FORWARD, sgn * 0.05))
		_rig.set_local(side + "LowerLeg", Quaternion(Vector3.RIGHT, knee - absf(drift)))


func _pose_eva_arms(delta: float) -> void:
	var w: Dictionary = _eva_w
	var drift: float = sin(_eva_t * 1.4 + 0.6) * 0.025
	var reach_side: String = String(_eva_reach.get("side", ""))
	for side in ["Right", "Left"]:
		var goal: float = 1.0 if (reach_side == side or reach_side == "Both") else 0.0
		var rw: float = float(_eva_reach.get("blend", 0.0)) * goal
		_eva_reach_w[side] = move_toward(float(_eva_reach_w[side]), rw, delta * 6.0) if delta > 0.0 else rw
	for side in ["Right", "Left"]:
		var sgn: float = 1.0 if side == "Right" else -1.0
		# Authored float poses (rig space, eye at EYE_POINT).
		var idle := Vector3(sgn * 0.33, 0.98 + drift, -0.16)
		var thrust := Vector3(sgn * 0.27, 0.92, 0.1)
		var brake := Vector3(sgn * 0.2, 1.2, -0.4)
		var work := Vector3(sgn * 0.17, 1.15, -0.42)
		var base: Vector3 = idle
		base = base.lerp(thrust, float(w["thrust"]) + float(w["coast"]) * 0.4)
		base = base.lerp(brake, float(w["brake"]))
		base = base.lerp(work, float(w["work"]))
		var tgt: Vector3 = base
		var rw: float = float(_eva_reach_w[side])
		if rw > 0.001 and _eva_reach.has("target"):
			var world: Vector3 = _eva_reach["target"]
			if reach_side == "Both":
				world += global_basis.orthonormalized().x * sgn * 0.12
			var local: Vector3 = _rig.global_transform.affine_inverse() * world
			var sh: Vector3 = _rig.bone_pos(side + "UpperArm")
			var to: Vector3 = local - sh
			if to.length() > 0.62:
				local = sh + to.normalized() * 0.62    # a straight-arm reach, never stretched
			tgt = base.lerp(local, rw)
		var float_w: float = 1.0 if floating else 0.0
		var blend: float = maxf(float_w, float(_eva_reach_w[side]))
		if blend <= 0.0:
			continue
		_rig.pose_arm_ik(side, tgt, Vector3(sgn * 0.9, -1.0, 0.25), blend, 0.0, 0.0)
	_remember_arm()
