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

var _raised: bool = false
var _tween: Tween


func _ready() -> void:
	visible = false
	_arm_group.position = _LOWERED_OFFSET


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
		visible = true
		_tween = create_tween()
		_tween.tween_property(_arm_group, "position", _RAISED_OFFSET, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_tween = create_tween()
		_tween.tween_property(_arm_group, "position", _LOWERED_OFFSET, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_tween.tween_callback(func(): visible = false)
