extends Node3D
## The FIGURE behind the airlock-tunnel port (Chapter One climax).
##
## Round 48 REDESIGN (player screenshot + frame-by-frame capture from the
## real observation spot, see MILESTONE1_DESIGN.md). What read badly in
## Round 47: a flat UNSHADED black cut-out, a big oval head on a stick neck,
## square-on to the window, perfectly centred in the port, both arms in
## simple symmetric angles -- a mannequin, not a person; the shudder was
## random 14 Hz vibration and the raised arm a marionette shape.
##
## Body (built under a turnable root; near-black but SHADED, so it has
## volume, with a faint cold rim from a figure-only light down the tunnel):
## human proportions -- a skull with a back and a jaw (not an egg), a neck
## of real thickness that flows into trapezius slopes, deltoids, upper arms
## / forearms / hands of ordinary length, a ribcage over a narrower waist,
## separate legs. Subtle asymmetry: one shoulder sits lower, weight on one
## leg, one hand half-closed. Slight albedo differences between the
## coverall, skin and hands so it is not one cardboard colour.
## Staging: standing a little OFF-CENTRE in the port, body turned three-
## quarters away down the tunnel, head turned further -- for a moment it
## could be another technician waiting for the hatch.
##
## Sequence (deterministic; tests and the F8 panel drive it):
##   idle        A ORDINARY STILLNESS  almost still: breath, a small weight
##                                     shift; looking down the tunnel
##   react 0.00  (it has noticed you: one more beat of total stillness)
##   react TURN  B RECOGNITION         the HEAD turns to the window far too
##                                     fast; the torso does not follow
##   react POST  C IMPOSSIBLE POSTURE  the chest twists to face you while the
##                                     hips stay turned away; one shoulder
##                                     hitches up, the other drops; the upper
##                                     body bends sideways at the waist while
##                                     the head stays level (as if held)
##   react SHUD  D SHUDDER             four deliberate snapped key poses --
##                                     not random vibration -- then still
##   retreat     E IMPOSSIBLE RETREAT  a held beat; it slides away with its
##                                     feet still, then the speed changes
##                                     abruptly; the head stays on you
##   gone        F DISAPPEARANCE       behind the port frame (never a fade or
##                                     a vanish in open view)
## Variants (developer comparison only; the shipped default is "B"):
##   "A" subtle posture, extreme neck turn, sideways retreat
##   "B" bent upper body, asymmetric sideways retreat (chosen)
##   "C" normal posture, long stare, abrupt BACKWARD retreat
## Reduced effects: the same poses, but every snap is eased over 0.22 s and
## the shudder amplitude halves (no strobing jerks). `time_scale` exists
## for the developer's slow-motion replay only.

signal finished
const DIRECT_ONLY := 1 << 19
const VARIANTS := ["A", "B", "C"]
const DEFAULT_VARIANT := "B"
const HIP_Y := 0.92
const BODY_TURN_DEG := 42.0          # three-quarters away (toward -Z, down the tunnel)
const HEAD_AWAY_DEG := 30.0          # the head looks further down the tunnel
const SHOULDER_SLOPE := {-1: 19.0, 1: 12.0}
const RAISED := -1                   # the shoulder that hitches up / the arm that lifts
const DEAD := 1                      # the arm that hangs
# Timeline (s of react time).
const TURN_AT := 0.42
const POSTURE_AT := 1.05
const POSTURE_END := 1.6
const SHUDDER_AT := 1.85
const SHUDDER_KEYS := [0.0, 0.2, 0.34, 0.55]
const REACT_S := 2.65
# Retreat: hold, a slow slide, then a sudden change of speed.
const RETREAT_HOLD := 0.12
const RETREAT_SLOW_S := 0.38
const RETREAT_SLOW_DIST := 0.22
const RETREAT_FAST_S := 0.28
const RETREAT_DIST := 1.95
const RETREAT_S := RETREAT_HOLD + RETREAT_SLOW_S + RETREAT_FAST_S
# Round 47 names kept for older callers.
const RECOG_END := TURN_AT
const FIRST_END := POSTURE_AT

var state: String = "gone"
var t: float = 0.0
var time_scale: float = 1.0          # developer slow-motion replay only
var reduced: bool = false
var variant: String = DEFAULT_VARIANT
## World point the head keeps turning to (the encounter sets the camera).
var watch_point: Vector3 = Vector3(-0.45, 1.6, 1.13)
var _base: Vector3
var _root: Node3D
var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _clav: Dictionary = {}           # side -> clavicle pivot (shoulder hitch)
var _arms: Dictionary = {}           # side -> [shoulder, elbow, wrist]
var _legs: Dictionary = {}           # side -> [hip, knee]
var _rim: OmniLight3D
var _mats: Dictionary = {}


func _ready() -> void:
	_mats["suit"] = _make_mat(Color(0.014, 0.014, 0.016))
	_mats["skin"] = _make_mat(Color(0.02, 0.018, 0.018))
	_mats["dark"] = _make_mat(Color(0.009, 0.009, 0.01))
	_mats["face"] = _make_mat(Color(0.008, 0.008, 0.009))
	_mats["face"].rim_enabled = false          # no identity: the face never catches light
	_mats["face"].roughness = 1.0
	_root = _joint(self, Vector3.ZERO)
	_root.name = "Body"
	_hips = _joint(_root, Vector3(0, HIP_Y, 0))
	_part(_hips, CapsuleMesh, Vector3(0, 0.0, 0), 0.115, 0.36, Vector3(90, 0, 0), Vector3(0.85, 1, 1))   # pelvis, across
	for side in [-1, 1]:
		var hj: Node3D = _joint(_hips, Vector3(0, -0.04, side * 0.095))
		_part(hj, CapsuleMesh, Vector3(0, -0.22, 0), 0.075, 0.48)
		var kn: Node3D = _joint(hj, Vector3(0, -0.45, 0))
		_part(kn, CapsuleMesh, Vector3(0, -0.21, 0), 0.056, 0.44)
		_part(kn, BoxMesh, Vector3(0.04, -0.43, 0), 0, 0, Vector3.ZERO, Vector3(0.24, 0.07, 0.1), "dark")   # boot
		_legs[side] = [hj, kn]
	_spine = _joint(_hips, Vector3(0, 0.05, 0))
	_part(_spine, CapsuleMesh, Vector3(0, 0.12, 0), 0.105, 0.3, Vector3.ZERO, Vector3(0.78, 1.0, 1.0))   # waist
	_chest = _joint(_spine, Vector3(0, 0.25, 0))
	_part(_chest, CapsuleMesh, Vector3(0, 0.09, 0), 0.15, 0.42, Vector3.ZERO, Vector3(0.66, 1.0, 1.0))   # ribcage
	# Clavicle pivots at the neck base: trapezius slope + deltoid + arm hang
	# from them, so a shoulder can hitch without detaching anything.
	for side in [-1, 1]:
		var slope: float = deg_to_rad(SHOULDER_SLOPE[side])
		var cl: Node3D = _joint(_chest, Vector3(-0.01, 0.29, side * 0.03))
		_clav[side] = cl
		var reach: float = 0.18
		var tip := Vector3(0, -reach * tan(slope), side * reach)
		_part(cl, CapsuleMesh, tip * 0.5, 0.06, reach + 0.1, Vector3(90.0 + rad_to_deg(slope) if side == 1 else 90.0 - rad_to_deg(slope), 0, 0))   # trapezius
		_part(cl, SphereMesh, tip + Vector3(0, -0.03, side * 0.005), 0.056, 0.11)                 # deltoid
		var sh: Node3D = _joint(cl, tip + Vector3(0, -0.035, side * 0.015))
		_part(sh, CapsuleMesh, Vector3(0, -0.15, 0), 0.052, 0.33)
		var el: Node3D = _joint(sh, Vector3(0, -0.3, 0))
		_part(el, CapsuleMesh, Vector3(0, -0.14, 0), 0.043, 0.3)
		var wr: Node3D = _joint(el, Vector3(0, -0.28, 0))
		_part(wr, BoxMesh, Vector3(0, -0.045, 0), 0, 0, Vector3.ZERO, Vector3(0.035, 0.09, 0.08), "skin")    # palm
		_part(wr, BoxMesh, Vector3(0.008, -0.11, 0), 0, 0, Vector3(0, 0, -12.0 if side == DEAD else 0.0), Vector3(0.03, 0.065, 0.075), "skin")  # fingers (one hand half-closed)
		_part(wr, CapsuleMesh, Vector3(0.02, -0.06, side * -0.035), 0.011, 0.06, Vector3(0, 0, 25), Vector3.ONE, "skin")   # thumb
		_arms[side] = [sh, el, wr]
	_neck = _joint(_chest, Vector3(0.0, 0.31, 0))
	_part(_neck, CapsuleMesh, Vector3(0.0, 0.06, 0), 0.053, 0.22, Vector3.ZERO, Vector3(1.0, 1.0, 0.92), "skin")
	_head = _joint(_neck, Vector3(0.015, 0.12, 0))
	# A head DEEPER than it is wide (as a real one is), with a jaw and the
	# line of a nose (both unlit: no facial identity), so turning it changes the silhouette: profile -> face.
	_part(_head, SphereMesh, Vector3(-0.01, 0.105, 0), 0.08, 0.23, Vector3.ZERO, Vector3(1.28, 1.0, 0.98), "skin")   # skull
	_part(_head, BoxMesh, Vector3(0.093, 0.085, 0), 0, 0, Vector3(0, 0, 14), Vector3(0.03, 0.05, 0.022), "face")       # nose
	_part(_head, SphereMesh, Vector3(0.045, 0.03, 0), 0.05, 0.08, Vector3.ZERO, Vector3(1.0, 1.0, 1.25), "face")       # jaw
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = DIRECT_ONLY
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A faint cold rim light down the tunnel, behind and to one side. It
	# lights ONLY the figure (cull mask = the eye-only layer).
	_rim = OmniLight3D.new()
	_rim.name = "FigureRim"
	_rim.position = Vector3(-0.75, 1.9, -0.35)
	_rim.omni_range = 2.2
	_rim.light_energy = 1.1
	_rim.light_color = Color(0.75, 0.82, 0.95)
	_rim.light_cull_mask = DIRECT_ONLY
	_rim.shadow_enabled = false
	_rim.visible = false
	add_child(_rim)
	_base = position
	visible = false


func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.82
	m.metallic_specular = 0.25
	m.rim_enabled = true
	m.rim = 0.8
	m.rim_tint = 0.25
	return m


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func _part(parent: Node3D, mesh_type, pos: Vector3, r: float, h: float, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, mat: String = "suit") -> void:
	var mi := MeshInstance3D.new()
	var m: Mesh = mesh_type.new()
	if m is CapsuleMesh:
		(m as CapsuleMesh).radius = r
		(m as CapsuleMesh).height = maxf(h, r * 2.0)
	elif m is SphereMesh:
		(m as SphereMesh).radius = r
		(m as SphereMesh).height = h
	elif m is BoxMesh:
		(m as BoxMesh).size = scl
		scl = Vector3.ONE
	mi.mesh = m
	mi.material_override = _mats[mat]
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)


func appear() -> void:
	position = _base
	_pose_reset()
	state = "idle"
	t = 0.0
	visible = true
	if _rim != null:
		_rim.visible = true
	step_pose(0.0)


func react() -> void:
	if state == "idle":
		state = "react"
		t = 0.0


func reset() -> void:
	state = "gone"
	t = 0.0
	visible = false
	if _rim != null:
		_rim.visible = false
	position = _base
	time_scale = 1.0
	_pose_reset()


func head_point() -> Vector3:
	return _head.global_position + _head.global_basis.y * 0.1 if _head != null else global_position + Vector3(0, 1.7, 0)


## A hand point (tests and renders measure the arm's travel).
func hand_point(side: int) -> Vector3:
	return (_arms[side][2] as Node3D).global_position


func is_in_frame() -> bool:
	return visible and absf(position.z - _base.z) < 0.3


## The named stage of the sequence at the current time (tests, dev panel).
func stage_name() -> String:
	match state:
		"idle":
			return "observation"
		"react":
			if t < TURN_AT:
				return "noticed"
			if t < POSTURE_AT:
				return "recognition"
			if t < SHUDDER_AT:
				return "posture"
			return "shudder"
		"retreat":
			return "retreat"
	return "gone"


func _pose_reset() -> void:
	if _hips == null:
		return
	_hips.position = Vector3(0, HIP_Y, 0)
	_root.rotation = Vector3.ZERO
	_root.position = Vector3.ZERO
	for n in [_hips, _spine, _chest, _neck, _head]:
		n.rotation = Vector3.ZERO
	_chest.scale = Vector3.ONE
	for side in _clav:
		(_clav[side] as Node3D).rotation = Vector3.ZERO
	for side in _arms:
		for j in _arms[side]:
			(j as Node3D).rotation = Vector3.ZERO
	for side in _legs:
		for j in _legs[side]:
			(j as Node3D).rotation = Vector3.ZERO


func _process(delta: float) -> void:
	if state == "gone":
		return
	t += delta * time_scale
	step_pose(t)


## Ease used for snaps: very fast, or 0.22 s with reduced effects.
func _snap(tt: float, at: float, dur: float) -> float:
	var d: float = maxf(dur, 0.22) if reduced else dur
	var s: float = clampf((tt - at) / d, 0.0, 1.0)
	return 1.0 - pow(1.0 - s, 3.0)


## The ordinary standing posture: three-quarters away, weight on one leg.
func _stance(tt: float) -> void:
	_pose_reset()
	_root.rotation.y = deg_to_rad(BODY_TURN_DEG)
	var breath: float = sin(tt * TAU / 4.2)
	_chest.scale = Vector3(1.0 + 0.012 * breath, 1.0 + 0.006 * breath, 1.0)
	var shift: float = 0.5 + 0.5 * sin(tt * TAU / 9.0)
	_hips.position.z = 0.025 + 0.008 * shift                # weight on one leg
	_hips.rotation.x = deg_to_rad(-3.0 - 0.6 * shift)
	_legs[1][0].rotation.x = deg_to_rad(3.0)
	_legs[-1][0].rotation.x = deg_to_rad(-2.5)
	_legs[-1][1].rotation.z = deg_to_rad(-7.0)              # one knee eased
	_legs[-1][0].rotation.z = deg_to_rad(4.0)
	_spine.rotation.x = deg_to_rad(2.5)
	_spine.rotation.z = deg_to_rad(-3.0)                    # a slight stoop
	_neck.rotation.z = deg_to_rad(-6.0)
	_clav[RAISED].rotation.x = deg_to_rad(-2.0)
	_arms[RAISED][0].rotation.x = deg_to_rad(5.0)
	_arms[RAISED][1].rotation.z = deg_to_rad(12.0)          # elbows not locked
	_arms[DEAD][0].rotation.x = deg_to_rad(-6.0)
	_arms[DEAD][1].rotation.z = deg_to_rad(8.0)
	_arms[DEAD][2].rotation.z = deg_to_rad(10.0)
	_head.rotation.y = deg_to_rad(HEAD_AWAY_DEG)            # looking down the tunnel
	_head.rotation.z = deg_to_rad(-4.0)


## Head yaw (local to the chest) that points the face at watch_point.
func _yaw_to_watch() -> float:
	var to: Vector3 = watch_point - head_point()
	var local: Vector3 = _chest.global_basis.inverse() * to
	return atan2(-local.z, local.x)


func step_pose(tt: float) -> void:
	match state:
		"idle":
			_stance(tt)
			# a few degrees of attention drift, still facing away
			_head.rotation.y = deg_to_rad(HEAD_AWAY_DEG + 4.0 * sin(tt * 0.7))
		"react":
			_react_pose(tt)
			if tt >= REACT_S:
				state = "retreat"
				t = 0.0
		"retreat":
			_retreat_pose(tt)


func _react_pose(tt: float) -> void:
	_stance(0.0)                                             # breathing stops
	var turn_s: float = {"A": 0.07, "B": 0.1, "C": 0.16}[variant]
	var over: float = {"A": 34.0, "B": 16.0, "C": 5.0}[variant]   # overshoot past the window
	# B RECOGNITION: the head comes round to the window far too fast and
	# overshoots, then settles back onto you slowly; the torso stays turned
	# away (the neck takes all of it).
	var turn: float = _snap(tt, TURN_AT, turn_s)
	var settle: float = smoothstep(TURN_AT + turn_s, TURN_AT + turn_s + 0.35, tt)
	var face_sum: float = lerpf(BODY_TURN_DEG + HEAD_AWAY_DEG, 0.0, turn) - over * turn * (1.0 - settle)
	_neck.rotation.y = -deg_to_rad(16.0) * turn
	_head.rotation.z = deg_to_rad(-4.0 + 7.0 * turn)
	var bend: float = {"A": 10.0, "B": 32.0, "C": 0.0}[variant]
	var twist: float = {"A": 20.0, "B": 58.0, "C": 0.0}[variant]
	var p: float = 0.0
	if variant != "C":
		# C IMPOSSIBLE POSTURE: the chest twists round to face the window
		# while the hips stay away; one shoulder hitches up, the other drops;
		# the upper body bends sideways at the waist while the head is held
		# LEVEL above it (as if something held it in place).
		p = smoothstep(POSTURE_AT, POSTURE_END, tt)
		if reduced:
			p = smoothstep(POSTURE_AT - 0.1, POSTURE_END + 0.1, tt)
		_chest.rotation.y = -deg_to_rad(twist * 0.65) * p
		_spine.rotation.y = -deg_to_rad(twist * 0.35) * p
		_spine.rotation.x = deg_to_rad(2.5 + bend * 0.45 * p)
		_chest.rotation.x = deg_to_rad(bend * 0.55) * p
		# (about X: + lifts the -Z clavicle, + drops the +Z one)
		_clav[RAISED].rotation.x = deg_to_rad(-2.0 + 36.0 * p)     # hitched up toward the ear
		_clav[DEAD].rotation.x = deg_to_rad(14.0) * p              # the other drops
		_neck.rotation.x = -deg_to_rad(bend * 0.55) * p            # counter-roll: the head stays level
		_head.rotation.x = -deg_to_rad(bend * 0.45) * p
		# the hitched arm: the elbow lifts out, the forearm hangs, the hand limp
		_arms[RAISED][0].rotation.x = deg_to_rad(5.0 - 38.0 * p)
		_arms[RAISED][1].rotation.x = deg_to_rad(52.0) * p
		_arms[RAISED][2].rotation.x = deg_to_rad(35.0) * p
		_arms[DEAD][0].rotation.x = deg_to_rad(-6.0 + 3.0 * p)
		if tt >= SHUDDER_AT:
			_shudder(tt - SHUDDER_AT)
	# Keep the face where it was meant to be whatever the torso does.
	var torso_yaw: float = rad_to_deg(_spine.rotation.y + _chest.rotation.y + _neck.rotation.y)
	_head.rotation.y = deg_to_rad(face_sum - BODY_TURN_DEG - torso_yaw)


## D SHUDDER: four deliberate key poses, each snapped into (40 ms) and HELD.
##   1 the head snaps over toward the hitched shoulder; that shoulder drops
##   2 the chest jerks back, the head snaps the other way
##   3 the upper body drops a few centimetres, the limp hand flips
##   4 the head snaps level onto you; the chest squares up; everything stops
func _shudder(st: float) -> void:
	var amp: float = 0.5 if reduced else 1.0
	var k := [0.0, 0.0, 0.0, 0.0]
	for i in SHUDDER_KEYS.size():
		k[i] = _snap(st, SHUDDER_KEYS[i], 0.04)
	var roll: float = 34.0 * k[0] - 52.0 * k[1] + 18.0 * k[3]
	_head.rotation.x += deg_to_rad(roll * amp)
	_clav[RAISED].rotation.x += deg_to_rad(-22.0 * k[0] + 14.0 * k[2]) * amp
	_chest.rotation.z = deg_to_rad(-14.0 * k[1] + 9.0 * k[3]) * amp
	_hips.position.y = HIP_Y - 0.055 * amp * (k[2] - 0.5 * k[3])
	_arms[RAISED][2].rotation.x = deg_to_rad(35.0 + 70.0 * amp * (k[2] - 0.4 * k[3]))
	_arms[RAISED][1].rotation.x = deg_to_rad(52.0 + 25.0 * amp * k[1])
	_chest.rotation.y -= deg_to_rad(12.0 * amp) * k[3]


## E IMPOSSIBLE RETREAT / F DISAPPEARANCE.
func _retreat_pose(tt: float) -> void:
	# Hold the final shudder pose as the starting point.
	if variant == "C":
		_react_pose(REACT_S)
	else:
		_react_pose(SHUDDER_AT + 0.9)
	var travel: float = retreat_travel(tt)
	var dir := Vector3(-0.05, 0.0, 1.0)                     # along the tunnel, out of the frame
	if variant == "C":
		dir = Vector3(-0.4, 0.0, 0.92)                      # yanked backward from the port, then away
	position = _base + dir.normalized() * travel
	# Feet still; the body is DRAGGED: it leans against its own travel.
	var lean: float = smoothstep(0.0, RETREAT_DIST * 0.5, travel)
	_hips.rotation.x += deg_to_rad(-16.0) * lean
	_spine.rotation.x += deg_to_rad(-6.0) * lean
	if variant == "B":
		# asymmetric: the hitched shoulder leads, the dead arm trails behind
		_arms[DEAD][0].rotation.x = deg_to_rad(-6.0 + 18.0 * lean)
		_arms[DEAD][0].rotation.z = deg_to_rad(-8.0) * lean
	# The head keeps turning to stay on the window as the body is carried off.
	var want: float = _yaw_to_watch()
	_head.rotation.y = lerpf(_head.rotation.y, want - _neck.rotation.y, 0.85)
	if tt >= RETREAT_S:
		visible = false
		if _rim != null:
			_rim.visible = false
		state = "gone"
		_pose_reset()
		position = _base
		time_scale = 1.0
		finished.emit()


## Distance travelled at retreat time tt: held, a slow slide, then a sudden
## change of speed (velocity jumps ~6x at one instant).
static func retreat_travel(tt: float) -> float:
	if tt <= RETREAT_HOLD:
		return 0.0
	var a: float = tt - RETREAT_HOLD
	if a <= RETREAT_SLOW_S:
		return RETREAT_SLOW_DIST * a / RETREAT_SLOW_S
	var b: float = clampf((a - RETREAT_SLOW_S) / RETREAT_FAST_S, 0.0, 1.0)
	return RETREAT_SLOW_DIST + (RETREAT_DIST - RETREAT_SLOW_DIST) * b
