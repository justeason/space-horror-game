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
var _watch_raise_tweens: Array = []

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
	_build_wrist_watch(_standing_pose.get_node("HandR"), Vector3(0, 0.08, 0.03), Vector3(0, 0, 0), true)
	_build_wrist_watch(_sitting_pose.get_node("HandR"), Vector3(0, -0.079, -0.003), Vector3(0, 0, 0), true)


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


## Builds a compact case/bezel/face/strap/crown/lugs wristwatch as
## children of `root` at `local_pos`/`local_rot_degrees` -- the same
## physical object the first-person rig shows up close, at matching
## real-world dimensions (same WatchCase/Bezel/FacePlate sizes as
## first_person_watch_rig.tscn), just seen from the outside on the
## actual wrist instead of raised to the camera.
func _build_wrist_watch(root: Node3D, local_pos: Vector3, local_rot_degrees: Vector3, is_right: bool) -> void:
	var group := Node3D.new()
	group.name = "WristWatch"
	group.position = local_pos
	group.rotation_degrees = local_rot_degrees
	root.add_child(group)

	var strap := CSGCylinder3D.new()
	strap.name = "Strap"
	strap.radius = 0.062
	strap.height = 0.05
	strap.sides = 14
	strap.material = _mat_watch_strap
	group.add_child(strap)

	# Round 22 Priority 1: ROOT CAUSE of "the watch is still too boxy/
	# oversized" (confirmed by render, not assumed) -- WatchCase was a
	# CSGBox3D with a half-diagonal (~0.067) well past the round
	# Bezel's own radius (0.042), so the box's square corners visibly
	# stuck out past the dial sitting on its face -- a round dial on a
	# visible square slab, not a wearable device. Rebuilt as a genuinely
	# round case (a CSGCylinder3D, matching the first-person rig's own
	# Round 22 fix -- see first_person_watch_rig.tscn's WatchCase class
	# doc comment for the full before/after), with four small rim
	# screws instead of the old box's exposed corners.
	var watch_case := CSGCylinder3D.new()
	watch_case.name = "WatchCase"
	watch_case.radius = 0.045
	watch_case.height = 0.026
	watch_case.sides = 24
	watch_case.smooth_faces = true
	watch_case.rotation_degrees = Vector3(90, 0, 0)
	watch_case.position = Vector3(0, 0, -0.02)
	watch_case.material = _mat_watch_case
	group.add_child(watch_case)

	var lug_top := CSGBox3D.new()
	lug_top.name = "LugTop"
	lug_top.size = Vector3(0.024, 0.018, 0.016)
	lug_top.position = Vector3(0, 0.043, -0.006)
	lug_top.material = _mat_watch_metal
	watch_case.add_child(lug_top)

	var lug_bottom := CSGBox3D.new()
	lug_bottom.name = "LugBottom"
	lug_bottom.size = Vector3(0.024, 0.018, 0.016)
	lug_bottom.position = Vector3(0, -0.043, -0.006)
	lug_bottom.material = _mat_watch_metal
	watch_case.add_child(lug_bottom)

	var bezel := CSGCylinder3D.new()
	bezel.name = "Bezel"
	bezel.radius = 0.045
	bezel.height = 0.011
	bezel.sides = 24
	bezel.rotation_degrees = Vector3(90, 0, 0)
	bezel.position = Vector3(0, 0, -0.018)
	bezel.material = _mat_watch_metal
	watch_case.add_child(bezel)

	var face := CSGCylinder3D.new()
	face.name = "FacePlate"
	face.radius = 0.036
	face.height = 0.006
	face.sides = 24
	face.rotation_degrees = Vector3(90, 0, 0)
	face.position = Vector3(0, 0, -0.013)
	face.material = _mat_watch_face
	watch_case.add_child(face)

	for angle_deg in [45.0, 135.0, 225.0, 315.0]:
		var screw := CSGSphere3D.new()
		screw.name = "RimScrew"
		screw.radius = 0.0055
		var rad: float = deg_to_rad(angle_deg)
		screw.position = Vector3(0.039 * cos(rad), 0.039 * sin(rad), -0.01)
		screw.material = _mat_watch_metal
		watch_case.add_child(screw)

	var crown := CSGCylinder3D.new()
	crown.name = "Crown"
	crown.radius = 0.008
	crown.height = 0.013
	crown.sides = 8
	crown.rotation_degrees = Vector3(0, 0, 90)
	crown.position = Vector3(0.047, 0, -0.008)
	crown.material = _mat_watch_metal
	watch_case.add_child(crown)


## Round 19 Priority 1/2: the standing world body's own "looking at my
## wrist" pose, distinct from the camera-relative first-person rig --
## called by wristwatch_view.gd ALONGSIDE (not instead of) its existing
## first-person _watch_rig.set_raised() call, so the mirror shows a
## believable world-body inspection pose for exactly as long as the
## first-person presentation is also shown, using the same
## falloff-from-rest-position tween approach animate_hand_laptop_gesture
## already established for SittingPose's arm. Only acts while STANDING
## (the only pose from which raising a wrist to look at it makes sense);
## a no-op otherwise, so no SittingPose/LyingPose arm is ever disturbed
## by holding C in those states.
func set_watch_raise_pose(raised: bool, duration: float) -> void:
	if _pose != Pose.STANDING:
		return
	for tw in _watch_raise_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_watch_raise_tweens.clear()

	# A modest raise toward the chest/lower-face, not full eye level --
	# this is a static-pose approximation (see the class doc comment's
	# own "no continuous IK solver" limitation), chosen so the forearm
	# swings plausibly up and inward without the hand needing to reach
	# convincingly all the way to eye height.
	var target: Vector3 = Vector3(0.08, -0.46, -0.32)
	var rest_hand: Vector3 = _standing_arm_rest_pos.get("HandR", Vector3.ZERO)
	var hand_delta: Vector3 = target - rest_hand
	var falloff: Dictionary = {"UpperArmR": 0.2, "ElbowR": 0.5, "LowerArmR": 0.75, "HandR": 1.0}
	for node_name in _STANDING_ARM_NODES:
		var node: Node3D = _standing_pose.get_node_or_null(node_name)
		if node == null:
			continue
		var rest: Vector3 = _standing_arm_rest_pos[node_name]
		var dest: Vector3 = rest + hand_delta * falloff[node_name] if raised else rest
		var tw: Tween = create_tween()
		tw.tween_property(node, "position", dest, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if raised else Tween.EASE_IN)
		_watch_raise_tweens.append(tw)

	# Round 23 Priority 3 fix: the loop above only ever tweened each
	# joint's POSITION -- the actual root cause of "the raised watch
	# pose looks awkward". _rebuild_arm_mesh() already re-derives the
	# forearm TUBE's own orientation live from the joint positions each
	# frame (its tangent just follows wherever Elbow/Hand end up), so
	# the forearm itself always looks right. But HandR is also the
	# parent of the actual rigid CSG geometry (Palm/fingers/WristWatch,
	# built once in _build_hand()/_build_wrist_watch()) -- that whole
	# assembly's ROTATION never changed, so it kept facing exactly the
	# way it faces at rest (arm hanging straight down) even once
	# dragged up near the chest, landing with the palm/watch pointed in
	# a direction that no longer matches the raised forearm at all.
	# Fixed by rotating HandR itself to match the forearm's new
	# direction: the shortest-arc rotation from the REST forearm
	# direction (Elbow->Hand at rest) to the RAISED one, applied as
	# HandR's own quaternion. This is the same "derive orientation from
	# the two live joint endpoints" principle _rebuild_arm_mesh()
	# already uses for the tube mesh, just applied once to the rigid
	# hand assembly instead of continuously to a lofted spine.
	var hand_node: Node3D = _standing_pose.get_node_or_null("HandR")
	var elbow_node: Node3D = _standing_pose.get_node_or_null("ElbowR")
	if hand_node != null and elbow_node != null:
		var rest_elbow: Vector3 = _standing_arm_rest_pos.get("ElbowR", Vector3.ZERO)
		var dest_elbow: Vector3 = rest_elbow + hand_delta * falloff["ElbowR"] if raised else rest_elbow
		var dest_hand: Vector3 = rest_hand + hand_delta * falloff["HandR"] if raised else rest_hand
		var rest_dir: Vector3 = (rest_hand - rest_elbow).normalized()
		var dest_dir: Vector3 = (dest_hand - dest_elbow).normalized()
		var target_quat: Quaternion = Quaternion(rest_dir, dest_dir) if raised else Quaternion.IDENTITY
		var rot_tw: Tween = create_tween()
		rot_tw.tween_property(hand_node, "quaternion", target_quat, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if raised else Tween.EASE_IN)
		_watch_raise_tweens.append(rot_tw)


func _apply_pose() -> void:
	_standing_pose.visible = _pose == Pose.STANDING
	_sitting_pose.visible = _pose == Pose.SITTING
	_lying_pose.visible = _pose == Pose.LYING
	_head_group.visible = _pose == Pose.STANDING
	rotation.x = 0.0
	if _pose == Pose.STANDING:
		rotation.y = _look_pivot.rotation.y
