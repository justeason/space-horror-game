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
	_apply_watch_raise(0.0)
	_apply_pose()
	_update_arm_meshes()


func _process(_delta: float) -> void:
	if _pose == Pose.STANDING:
		rotation.y = _look_pivot.rotation.y
		_pitch_follow_current = standing_pitch_follow
		rotation.x = _pitch_pivot.rotation.x * _pitch_follow_current
	_update_arm_meshes()


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
		_stop_watch_raise(true)
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
	if value:
		_stop_watch_raise(true)
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
@export var watch_wrist_target: Vector3 = Vector3(0.0, -0.42, -0.40)
@export var watch_elbow_pole: Vector3 = Vector3(1.0, -0.4, -0.3)
## The world body moves a little slower than the snappy first-person rig
## (0.28s default) so the shoulder -> elbow -> wrist sequence reads as a
## natural gesture rather than a snap.
const _WORLD_RAISE_DURATION_SCALE: float = 1.5
var _watch_raise_progress: float = 0.0
var _watch_raise_tween: Tween
var _arm_rig: Dictionary = {}


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

	# Analytic two-bone IK for the raised wrist position.
	var d: Vector3 = watch_wrist_target - s
	var dist: float = clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dn: Vector3 = d.normalized()
	var along: float = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var out: float = sqrt(maxf(l1 * l1 - along * along, 0.0))
	var pole: Vector3 = (watch_elbow_pole - dn * watch_elbow_pole.dot(dn)).normalized()
	var e_d: Vector3 = s + dn * along + pole * out
	var w_d: Vector3 = s + dn * dist
	var u_d: Vector3 = (e_d - s) / l1
	var f_d: Vector3 = (w_d - e_d) / l2
	var h_d: Vector3 = u_d.cross(f_d).normalized()

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
	var q_upper: Quaternion = (_limb_frame(u_d, h_d) * _limb_frame(u_r, h_r).transposed()).get_rotation_quaternion()

	# Forearm roll that turns the watch face toward the eye (body origin).
	var roll: float = 0.0
	var hand: Node3D = _standing_pose.get_node("HandR")
	var watch: Node3D = hand.get_node_or_null("WristWatch")
	if watch != null:
		var r0: Basis = _limb_frame(f_d, h_d) * ff_r.transposed()
		var watch_rest: Transform3D = Transform3D(Basis(hand_rest_q), Vector3.ZERO) * watch.transform
		var face_n: Vector3 = r0 * watch_rest.basis.y
		var face_p: Vector3 = e_d + r0 * (w_rest - e_rest + watch_rest.origin)
		var to_eye: Vector3 = -face_p
		var n_p: Vector3 = (face_n - f_d * face_n.dot(f_d)).normalized()
		var e_p: Vector3 = (to_eye - f_d * to_eye.dot(f_d)).normalized()
		roll = atan2(f_d.dot(n_p.cross(e_p)), n_p.dot(e_p))

	_arm_rig = {
		"s": s, "u_rest": u_rest, "e_rest": e_rest, "l_rest": l_rest, "w_rest": w_rest,
		"u_r": u_r, "h_r": h_r, "ff_r": ff_r,
		"flex_r": u_r.angle_to(f_r), "flex_d": u_d.angle_to(f_d),
		"q_upper": q_upper, "roll": roll, "hand_rest_q": hand_rest_q,
		"upper_len": l1, "fore_len": l2,
		"cap_rest": _standing_pose.get_node("ShoulderCapR").position,
	}


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
	_set_right_arm_mirror_only(p > 0.0)
	if p <= 0.0:
		cap_node.position = rig["cap_rest"]
		upper_node.position = rig["u_rest"]
		elbow_node.position = rig["e_rest"]
		lower_node.position = rig["l_rest"]
		hand_node.position = rig["w_rest"]
		hand_node.quaternion = rig["hand_rest_q"]
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
	var e: Vector3 = s + b_upper * (rig["e_rest"] - s)
	upper_node.position = s + b_upper * (rig["u_rest"] - s)
	# The deltoid cap belongs to the upper-arm segment: it must swing with
	# it, or it is left floating where the arm used to hang.
	cap_node.position = s + b_upper * (rig["cap_rest"] - s)
	elbow_node.position = e
	lower_node.position = e + b_fore * (rig["l_rest"] - rig["e_rest"])
	hand_node.position = e + b_fore * (rig["w_rest"] - rig["e_rest"])
	hand_node.quaternion = b_fore.get_rotation_quaternion() * (rig["hand_rest_q"] as Quaternion)


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
	rotation.x = 0.0
	if _pose == Pose.STANDING:
		rotation.y = _look_pivot.rotation.y
