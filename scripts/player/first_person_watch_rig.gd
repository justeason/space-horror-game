extends Node3D
## Round 11 Workstream A: the dedicated, visual-only first-person watch
## inspection presentation -- deliberately SEPARATE from PlayerBody/
## StandingPose (the world character body).
##
## ROOT CAUSE of "the player's body disappears when the watch is
## raised, and returns when C is released" (confirmed by reading
## player_body.gd's _process(), not assumed): that script eased its own
## `_pitch_follow_current` toward a FULL 1.0 while the watch was raised,
## so the WHOLE PlayerBody node -- which parents StandingPose, i.e. the
## entire visible body (torso, hips, legs, both arms) -- rotated in
## lockstep with the camera's pitch around the eye-point pivot. That is
## mathematically correct for keeping one small FIXED offset (the old
## watch, parented under the hand) at a constant camera-relative
## position, but it is the wrong transform for an object that extends
## ~1.6m below the pivot: pitching the camera down even a moderate
## amount to "look at your wrist" swings the entire body (legs
## included) through a large arc around the eye point, carrying most
## or all of it outside the frustum or behind the near plane. Looking
## level (pitch=0) never a showed problem, which is consistent with the
## report -- the bug is pitch-dependent, not binary.
##
## THE FIX: PlayerBody no longer has ANY watch-related logic or
## full-pitch-follow mode at all (see that script's own updated class
## doc comment) -- it always uses its ordinary PARTIAL pitch follow, so
## the world body never again inherits an artificial camera-relative
## offset for this feature. This node is the complete replacement: a
## plain child of Camera3D (scenes/player.tscn), so it inherits the
## camera's full position/rotation by ordinary scene-graph parenting --
## no per-frame pitch-follow math is needed at all, and no amount of
## look movement can ever separate it from the camera's view. It has no
## collision, never touches Player/PlayerBody's transform, authority,
## or any world-state, and is purely decorative.
##
## Reuses Round 10's already frustum-verified distances for the hand/
## watch region (HandR ~ (0.14,-0.25,-0.49), watch case ~
## (0.14,-0.23,-0.53) relative to the camera) as the RAISED resting
## offsets for this rig's own children, since those numbers were
## already confirmed (test_wristwatch_screen_stability.gd, Round 10) to
## sit safely inside this project's camera frustum (fov=72) across a
## wide yaw/pitch sweep -- reusing them here means this rig starts from
## a position already known to be visible, not a fresh guess.
##
## Double-arm note (Workstream A2's "prevent visual duplication of the
## inspection arm and world arm"): PlayerBody's own right arm now simply
## never moves for this feature (it stays in its ordinary resting-at-
## the-side pose at all times, exactly like the left arm) -- combined
## with standing_pitch_follow's existing design (the whole body,
## resting arm included, stays out of frame under ordinary look angles,
## by the same design that keeps the torso out of frame), there is
## nothing to duplicate in practice. If a future skeletal character
## model needs ACTUAL mutual exclusion (e.g. a mirror camera that must
## never show this first-person-only rig), every CSGCombiner3D root
## under this node is tagged `layers = 2` (bit 2) for exactly that
## purpose -- a future third-person/mirror Camera3D should set its own
## `cull_mask` to exclude bit 2 to avoid ever rendering this rig; the
## main first-person camera's cull_mask is left at its default (sees
## every layer) so nothing needs to change there today.
##
## FUTURE SKELETAL INTEGRATION: when a real shared skeletal character
## model exists, this rig's role does not change conceptually -- it
## remains "the first-person view-model," a separate, camera-attached,
## non-authoritative visual, the same pattern used by nearly every
## first-person game that also supports third-person/mirrors (the
## world skeleton plays its own anims for third-person/mirror cameras;
## the first-person camera's own viewmodel is a separate rig attached
## to the camera, often reusing the SAME skinned mesh/skeleton resource
## but posed independently). This script's set_raised()/set_watch_text()
## API would not need to change; only the internal geometry (currently
## CSG primitives) would eventually be replaced by a skinned mesh.

@export var raise_duration_default: float = 0.28
## Round 26: shared CharacterPoseState (Player/PoseState). Optional.
@export var pose_state_path: NodePath
## Round 28: true while the rigged character is the visible body -- the
## player then sees the rig's own arm/hand/watch, so this separate
## camera-attached presentation is never shown (its raise state is still
## tracked for wristwatch_view.gd).
var suppress_presentation: bool = false

## Previously-verified-safe (Round 10) authored "raised" position for
## the whole arm group, relative to this node (which is itself a plain,
## non-moving child of Camera3D) -- see class doc comment.
const _RAISED_OFFSET: Vector3 = Vector3.ZERO
## Pushed down and slightly back so it is unambiguously outside the
## frustum and behind/below the visible area while lowered -- does not
## need to be precise, only "clearly out of view"; `visible` is also
## toggled so there is no reliance on position alone.
const _LOWERED_OFFSET: Vector3 = Vector3(0.0, -0.95, 0.25)

@onready var _arm_group: Node3D = $ArmGroup
@onready var _watch_face_text: Label3D = $ArmGroup/WatchAssembly/WatchFaceText

const _HandMeshBuilder = preload("res://scripts/player/hand_mesh_builder.gd")

var _raised: bool = false
var _tween: Tween


func _ready() -> void:
	visible = false
	_arm_group.position = _LOWERED_OFFSET
	_build_fingers()


## Round 20 Priority 2: this rig's fingers/thumb used to be a CSG chain
## (a knuckle sphere + one cylinder segment + a tip sphere, per digit) --
## the literal "looks like several cylinders connected together" the
## player's own feedback named (this is the RAISED hand their screenshot
## showed). Replaced with one smoothly-lofted tube per digit
## (hand_mesh_builder.gd), reusing this rig's OWN already-tuned knuckle/
## tip anchor positions (so the hand's size/spacing/angle against the
## palm is unchanged -- only the discrete-primitive-vs-smooth-mesh
## technique changes) rather than re-deriving a new layout. The SAME
## builder is used for the world-body hand (player_body.gd), satisfying
## "shared appearance between first-person and world-body models."
func _build_fingers() -> void:
	var mat: Material = _arm_group.get_node("Palm").material
	var arm: Node3D = _arm_group
	var defs: Array = [
		{"n": "Index", "base": Vector3(0.118, -0.1, -0.462), "tip": Vector3(0.118, -0.13, -0.5)},
		{"n": "Middle", "base": Vector3(0.098, -0.104, -0.468), "tip": Vector3(0.098, -0.14, -0.511)},
		{"n": "Ring", "base": Vector3(0.078, -0.102, -0.465), "tip": Vector3(0.078, -0.133, -0.503)},
		{"n": "Pinky", "base": Vector3(0.06, -0.098, -0.456), "tip": Vector3(0.06, -0.118, -0.486)},
	]
	for def in defs:
		var finger: MeshInstance3D = _HandMeshBuilder.build_finger_from_anchors(
			"Finger" + def["n"], def["base"], def["tip"], 0.0095, 0.0045, Vector3(0, -1, 0.3), 0.006, mat
		)
		# Round 21 Priority 1: ROOT CAUSE of "the mirror still shows a
		# tan/skin-colored floating hand+fingers even after excluding
		# this rig's layer 2 from the mirror camera" -- ArmGroup itself
		# (a CSGCombiner3D) correctly carries `layers = 2`, and every
		# CSG primitive child (palm/forearm/sleeve/watch) is folded into
		# that ONE combined render instance for free. These finger/thumb
		# MeshInstance3D nodes are NOT CSG shapes though -- Godot only
		# merges CSGShape3D children into a parent CSGCombiner3D's own
		# render instance; a plain MeshInstance3D child renders as its
		# OWN independent VisualInstance3D, with its OWN `layers`
		# property defaulting to 1 (the default/shared layer) unless set
		# explicitly. Round 20 added these without ever setting that,
		# so the fingers/thumb -- the exact geometry this project spent
		# two rounds improving -- silently leaked onto the shared layer
		# and rendered in every camera regardless of any cull_mask
		# exclusion of layer 2, confirmed directly by render (see the
		# Round 21 report). Explicitly matching ArmGroup's own layer
		# fixes it.
		finger.layers = 2
		arm.add_child(finger)

	var thumb: MeshInstance3D = _HandMeshBuilder.build_finger_from_anchors(
		"Thumb", Vector3(0.118, -0.082, -0.408), Vector3(0.155, -0.068, -0.408), 0.0115, 0.0055, Vector3(0, 1, 0.2), 0.005, mat
	)
	thumb.layers = 2
	arm.add_child(thumb)


func is_raised() -> bool:
	return _raised


func set_watch_text(text: String) -> void:
	_watch_face_text.text = text


## Idempotent by state, same convention as the previous implementation
## (raising while already raised, or lowering while already lowered, is
## a deliberate no-op) -- repeated fast C press/release from
## wristwatch_view.gd's per-frame polling can never stack redundant
## tweens or desync from the actual flag.
func set_raised(raised: bool, duration: float = -1.0) -> void:
	if raised == _raised:
		return
	_raised = raised
	var d: float = duration if duration >= 0.0 else raise_duration_default
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if raised:
		visible = not suppress_presentation
		_tween = create_tween()
		_tween.tween_property(_arm_group, "position", _RAISED_OFFSET, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_tween = create_tween()
		_tween.tween_property(_arm_group, "position", _LOWERED_OFFSET, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_tween.tween_callback(func(): visible = visible and _pose_state != null)


## Round 26 Priority 5: pitch-aware presentation.
##
## ROOT CAUSE of "the first-person arm intersects the torso when looking
## down" (measured, not assumed: scratchpad fp_clear_search.gd tests every
## rig sample point against the world body's actual StandingPose primitives):
## this rig is a plain child of Camera3D, so it follows 100% of camera pitch,
## and its forearm enters the frame from BELOW the camera -- which is exactly
## where the player's own chest/shoulder are. Level: 2 sample points inside
## the body; 45 deg down: 131; 60 deg down: 222. Merely counter-rotating the
## rig to clear the torso needed 40-70 deg, pushing the watch 17-41 deg above
## view centre (unreadable).
##
## Round 26 FIX (superseded in part by Round 27 -- see _process()): at
## level/upward looks the authored camera framing was kept; looking down the
## rig blended toward the WORLD arm's real pose from the shared
## CharacterPoseState pipeline. Round 27 removed that split (it left first
## person and the mirror disagreeing): the rig is now ALWAYS the world arm's
## pose, plus a constant framing lift. Original Round 26 notes: the watch goes to where the world
## watch is (in front of the chest), the forearm aligns with the world
## forearm (coming in from the elbow out to the side, not from under the
## camera), and the face is turned to the camera. First-person and mirror
## then agree, and the torso clearance the world arm already guarantees
## carries over. No arm scaling, no FOV/camera change, body not moved.
const _FRAMING_LIFT_DEG: float = 9.0

@onready var _pose_state: Node = get_node_or_null(pose_state_path)
var _player_body: Node = null
var presentation_weight: float = 0.0
## Current constant-angle framing lift (radians) applied about the eye.
var framing_lift: float = 0.0
var _face_text_rest = null


func _enter_tree() -> void:
	# Read the world arm AFTER PlayerBody has posed it this frame.
	process_priority = 10


func _process(_delta: float) -> void:
	if suppress_presentation:
		visible = false
		return
	if _pose_state == null:
		_set_presentation(Transform3D(), 0.0)
		return
	if _player_body == null:
		_player_body = _pose_state.get_node_or_null(_pose_state.player_body_path)
	if _player_body == null or not _player_body.has_method("world_watch_pose"):
		return
	# Round 27: ALWAYS derived from the world arm (the shared pose), at every
	# pitch -- not only when looking down. The world arm itself now holds the
	# watch at a fixed direction relative to the view (1:1 with look pitch,
	# see CharacterPoseState.watch_target_for_pitch), so the first-person
	# framing stays steady while the mirror shows the arm genuinely moving.
	# The visible raise/lower motion is the world arm's own shoulder -> elbow
	# -> wrist animation; this rig stays shown until that arm is fully down.
	var progress: float = clampf(_pose_state.watch_weight, 0.0, 1.0)
	visible = _raised or progress > 0.0
	if not visible:
		_set_presentation(Transform3D(), 0.0)
		return
	var w: float = 1.0
	var cam: Node3D = get_parent()
	var pose: Dictionary = _player_body.world_watch_pose()
	var inv: Transform3D = cam.global_transform.affine_inverse()
	var p_d: Vector3 = inv * (pose["watch"] as Vector3)
	var f_d: Vector3 = (inv.basis * (pose["to_elbow"] as Vector3)).normalized()
	var n_d: Vector3 = (-p_d - f_d * (-p_d).dot(f_d)).normalized()
	var assembly: Node3D = _arm_group.get_node("WatchAssembly")
	var sleeve: Node3D = _arm_group.get_node("SleeveCuff")
	var p_fp: Vector3 = _arm_group.position + assembly.position
	var f_fp: Vector3 = (sleeve.position - assembly.position).normalized()
	var n_raw: Vector3 = assembly.transform.basis.z
	var n_fp: Vector3 = (n_raw - f_fp * n_raw.dot(f_fp)).normalized()
	var b_fp := Basis(f_fp, n_fp, f_fp.cross(n_fp))
	var b_d := Basis(f_d, n_d, f_d.cross(n_d))
	var r: Basis = (b_d * b_fp.transposed()).orthonormalized()
	# Round 27 follow-up: NO spin of the arm about the face normal any more.
	# Spinning the whole arm toward level text (Round 26) swung the forearm
	# away from the real elbow -- at steep downward looks it came up nearly
	# vertically from the lower-right, reading as a camera-attached prop.
	# The arm now stays exactly on the world forearm; only the watch's TEXT
	# display auto-levels on its own face (see _level_face_text()).
	var target := Transform3D(r, p_d - r * p_fp)
	# Constant framing lift (Round 27): rotate the presentation up about the
	# eye by a FIXED angle so the larger first-person watch sits clear of the
	# frame's bottom edge at level look. It still moves 1:1 with the world
	# arm -- only its screen position is offset by this constant -- and
	# rotating up moves it away from the chest, never into it.
	# Faded out below -30 deg, where the world arm stops following (chest
	# limit) and the head bows instead -- there the watch already rises in
	# the frame on its own.
	framing_lift = deg_to_rad(_FRAMING_LIFT_DEG) * clampf((_pose_state.look_pitch + deg_to_rad(60.0)) / deg_to_rad(30.0), 0.0, 1.0)
	target = Transform3D(Basis(Vector3.RIGHT, framing_lift), Vector3.ZERO) * target
	_set_presentation(Transform3D().interpolate_with(target, w), w)
	_level_face_text(cam)


## Rotate only the watch's text display about the face normal so it reads
## level to the camera, like an auto-orienting display. The arm and case are
## untouched.
func _level_face_text(cam: Node3D) -> void:
	if _face_text_rest == null:
		_face_text_rest = _watch_face_text.transform
	_watch_face_text.transform = _face_text_rest
	var g: Transform3D = _watch_face_text.global_transform
	var normal: Vector3 = g.basis.z.normalized()
	var up_now: Vector3 = g.basis.y
	var up_p: Vector3 = (up_now - normal * up_now.dot(normal)).normalized()
	var cam_up: Vector3 = cam.global_transform.basis.y
	var cam_up_p: Vector3 = (cam_up - normal * cam_up.dot(normal)).normalized()
	var angle: float = atan2(normal.dot(up_p.cross(cam_up_p)), up_p.dot(cam_up_p))
	_watch_face_text.rotate_object_local(Vector3(0, 0, 1), angle)


func _set_presentation(t: Transform3D, w: float) -> void:
	transform = t
	presentation_weight = w
