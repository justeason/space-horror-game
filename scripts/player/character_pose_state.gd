extends Node
## Round 26 Priority 2: the ONE shared, engine-agnostic visual pose state for
## the player's character. It is NOT a controller: the LookPivot/PitchPivot
## camera rig and the movement controller stay authoritative. Once per frame
## (before any consumer -- see process_priority in _ready()) it READS that
## authoritative state plus the body's posture and watch-inspection weight,
## and derives a small set of anatomical joint angles that every visual
## representation maps onto its own nodes/bones:
##
## - the world body (player_body.gd: CSG head/neck pivots + watch arm),
## - the camera-relative first-person watch rig (first_person_watch_rig.gd),
## - the experimental Skeleton3D technician
##   (scripts/dev/rigged_technician_prototype.gd: Spine/Neck/Head bones).
##
## Round 26 ROOT CAUSE this replaces: the two representations used
## unrelated pose rules. The first-person rig followed 100% of camera pitch
## (it is a child of Camera3D), while the world body rotated as ONE RIGID
## PIECE by 30% of pitch about the eye (standing_pitch_follow -- pelvis and
## legs tilting with the look) and its head had no look response of its own;
## the raised watch arm was a fixed body-space target. So the mirror showed
## the same frozen gesture whatever the player did with the camera.
##
## Nothing here names a CSG node or a bone: outputs are plain angles and a
## watch-target bias. to_dict()/from_dict() give the compact form a future
## multiplayer peer would replicate (a remote player's visuals can be driven
## from a received dictionary with no camera at all -- see `remote_driven`).

enum Posture { STANDING, SITTING, LYING }

@export var look_pivot_path: NodePath
@export var player_body_path: NodePath

## Anatomical limits (degrees, + = looking up / extension). Total head
## pitch reachable: down 15 + 45 + 25 = 85, up 8 + 40 + 25 = 73 (the
## camera's own 80 deg limit is covered; the last few degrees up are eyes).
const SPINE_FRACTION: float = 0.2
const SPINE_MIN_DEG: float = -15.0
const SPINE_MAX_DEG: float = 8.0
const NECK_FRACTION: float = 0.6
const NECK_MIN_DEG: float = -45.0
const NECK_MAX_DEG: float = 40.0
const HEAD_MIN_DEG: float = -25.0
const HEAD_MAX_DEG: float = 25.0
## Seated: the trunk is supported, so the neck/head do the looking.
## Lying: the head rests on the bunk; only a small nod.
const LYING_HEAD_MIN_DEG: float = -10.0
const LYING_HEAD_MAX_DEG: float = 20.0
## Round 27: the SHARED watch-inspection target -- the one source of truth
## both the world arm (mirror / other players) and the first-person rig are
## derived from. Round 26 made the world arm react only a little to look
## pitch (a bounded +/-60 deg bias: at most +12cm up / -6cm down) while the
## first-person rig followed the camera fully at level/up and converged on
## that nearly-static world arm only when looking down -- two different
## rules, so first person and the mirror still disagreed. Now the watch is
## held at a FIXED direction relative to the view and follows look pitch 1:1
## (elevation = pitch + WATCH_LEVEL_ELEVATION_DEG), limited only by the
## body: it cannot go lower than WATCH_ELEVATION_MIN_DEG (the chest is in the
## way -- below that the head bows the rest of the way) or higher than
## WATCH_ELEVATION_MAX_DEG = eye level (rendered: following 1:1 above eye
## level put the hand overhead and read as a WAVE, not a watch check --
## above that the arm holds in front of the face and the head looks up). Body space: eye at origin, -Z
## forward, +X right; the body itself never pitches.
const WATCH_LEVEL_ELEVATION_DEG: float = -24.0
const WATCH_ELEVATION_MIN_DEG: float = -52.0
const WATCH_ELEVATION_MAX_DEG: float = 0.0
const WATCH_LATERAL: float = 0.04
## Round 29 Priority 4: ABOVE a level look the watch no longer stops at eye
## level (that clamp made the target "eye height, 0.33m straight ahead" --
## ~0.53m from the shoulder for a 0.565m arm, i.e. a locked-straight arm
## reaching forward at 35 deg up). It keeps rising at WATCH_UP_GAIN of the
## look pitch up to WATCH_HIGH_ELEVATION_MAX_DEG (=> 24..30 deg below the
## view centre all the way to a 70 deg upward look), while the reading
## distance shrinks toward WATCH_HIGH_DISTANCE and the wrist comes in
## toward the midline -- the forearm rises IN FRONT OF the face with the
## elbow bent (player_body.gd adds the clavicle shrug). Everything at or
## below a level look is unchanged (Round 28's approved downward pose).
const WATCH_UP_GAIN: float = 1.0
const WATCH_HIGH_ELEVATION_MAX_DEG: float = 32.0
const WATCH_HIGH_DISTANCE: float = 0.28
## Look pitch over which the reading distance eases in to the high-hold
## distance (0 at a level look -> full by this pitch).
const WATCH_UP_EASE_DEG: float = 26.0

## Authoritative inputs (read each frame).
var look_yaw: float = 0.0
var look_pitch: float = 0.0
var watch_weight: float = 0.0
var posture: int = Posture.STANDING

## Derived outputs (radians).
var spine_pitch: float = 0.0
var neck_pitch: float = 0.0
var head_pitch: float = 0.0
## Shared watch target (body space) and its elevation from the eye.
var watch_target: Vector3 = Vector3.ZERO
var watch_elevation: float = 0.0

## True when this state is fed from replicated data instead of a local
## camera (future multiplayer); refresh() then leaves the inputs alone.
var remote_driven: bool = false

var _look_pivot: Node3D
var _pitch_pivot: Node3D
var _body: Node


func _ready() -> void:
	# Run before PlayerBody / the first-person rig read it this frame.
	process_priority = -100
	_look_pivot = get_node_or_null(look_pivot_path)
	_pitch_pivot = _look_pivot.get_node_or_null("PitchPivot") if _look_pivot != null else null
	_body = get_node_or_null(player_body_path)
	refresh()


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if not remote_driven:
		if _look_pivot != null:
			look_yaw = _look_pivot.rotation.y
		if _pitch_pivot != null:
			look_pitch = _pitch_pivot.rotation.x
		if _body != null:
			if _body.has_method("is_lying") and _body.is_lying():
				posture = Posture.LYING
			elif _body.has_method("is_sitting") and _body.is_sitting():
				posture = Posture.SITTING
			else:
				posture = Posture.STANDING
			if _body.has_method("watch_raise_progress"):
				watch_weight = _body.watch_raise_progress()
	_derive()


func _derive() -> void:
	var d: Dictionary = distribute_look_pitch(look_pitch, posture)
	spine_pitch = d["spine"]
	neck_pitch = d["neck"]
	head_pitch = d["head"]
	var pitch_for_watch: float = look_pitch if posture == Posture.STANDING else 0.0
	watch_elevation = watch_elevation_for_pitch(pitch_for_watch)
	watch_target = watch_target_for_pitch(pitch_for_watch)


## Splits a look pitch across upper spine, neck and head within anatomical
## limits. Pure function: usable by any representation or by tests.
static func distribute_look_pitch(pitch: float, posture_value: int) -> Dictionary:
	if posture_value == Posture.LYING:
		return {"spine": 0.0, "neck": 0.0, "head": clampf(pitch * 0.4, deg_to_rad(LYING_HEAD_MIN_DEG), deg_to_rad(LYING_HEAD_MAX_DEG))}
	var spine: float = 0.0
	if posture_value == Posture.STANDING:
		spine = clampf(pitch * SPINE_FRACTION, deg_to_rad(SPINE_MIN_DEG), deg_to_rad(SPINE_MAX_DEG))
	var neck_min: float = deg_to_rad(NECK_MIN_DEG)
	var neck_max: float = deg_to_rad(NECK_MAX_DEG)
	var neck: float = clampf((pitch - spine) * NECK_FRACTION, neck_min, neck_max)
	var head: float = clampf(pitch - spine - neck, deg_to_rad(HEAD_MIN_DEG), deg_to_rad(HEAD_MAX_DEG))
	# If the head saturated first, hand the overflow back to the neck (still
	# within its own limit) so the joints use their full combined range.
	neck = clampf(pitch - spine - head, neck_min, neck_max)
	head = clampf(pitch - spine - neck, deg_to_rad(HEAD_MIN_DEG), deg_to_rad(HEAD_MAX_DEG))
	return {"spine": spine, "neck": neck, "head": head}


static func watch_elevation_for_pitch(pitch: float) -> float:
	if pitch > 0.0:
		return minf(deg_to_rad(WATCH_LEVEL_ELEVATION_DEG) + pitch * WATCH_UP_GAIN, deg_to_rad(WATCH_HIGH_ELEVATION_MAX_DEG))
	return clampf(pitch + deg_to_rad(WATCH_LEVEL_ELEVATION_DEG), deg_to_rad(WATCH_ELEVATION_MIN_DEG), deg_to_rad(WATCH_ELEVATION_MAX_DEG))


## Wrist target (body space, eye at origin) for a look pitch: along the
## fixed view-relative direction, at a distance that keeps it in front of
## the chest when low (0.52m at the lowest) and comfortable when high
## (0.40m at eye level).
static func watch_target_for_pitch(pitch: float) -> Vector3:
	var e: float = watch_elevation_for_pitch(pitch)
	var e_deg: float = rad_to_deg(e)
	# Round 28: distances for the rigged technician's anatomy (shoulder
	# joint 14cm behind and 20cm below the eye): 0.35m at the level hold
	# (elbow dropped to the lower chest, forearm angled up across the chest),
	# out to 0.41m at the lowest hold for chest clearance, in to 0.33m at
	# eye level.
	var d: float = 0.35
	if e_deg < -30.0:
		d += 0.06 * clampf((-e_deg - 30.0) / 22.0, 0.0, 1.0)
	elif e_deg > -10.0:
		d -= 0.02 * clampf((e_deg + 10.0) / 10.0, 0.0, 1.0)
	var lateral: float = WATCH_LATERAL
	if pitch > 0.0:
		# Anatomical reach: the shoulder joint sits ~13cm BEHIND and 20cm
		# below the eye, so a bent elbow (wrist <= ~0.44m from the shrugged
		# shoulder) needs the watch at ~0.23-0.25m once it rises to eye
		# level (solved numerically for the rig; see MILESTONE1_DESIGN.md
		# Round 29). The wrist also comes in toward the midline.
		d = lerpf(d, WATCH_HIGH_DISTANCE, smoothstep(0.0, deg_to_rad(WATCH_UP_EASE_DEG), pitch))
		lateral = lerpf(WATCH_LATERAL, 0.0, clampf(e_deg / WATCH_HIGH_ELEVATION_MAX_DEG, 0.0, 1.0))
	return Vector3(lateral, d * sin(e), -d * cos(e))


## Compact replicable form (future multiplayer): only the inputs; every
## peer derives the joint angles itself with the same limits.
func to_dict() -> Dictionary:
	return {"yaw": look_yaw, "pitch": look_pitch, "watch": watch_weight, "posture": posture}


func from_dict(data: Dictionary) -> void:
	remote_driven = true
	look_yaw = data.get("yaw", 0.0)
	look_pitch = data.get("pitch", 0.0)
	watch_weight = data.get("watch", 0.0)
	posture = data.get("posture", Posture.STANDING)
	_derive()
