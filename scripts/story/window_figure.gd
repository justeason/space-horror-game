extends Node3D
## The FIGURE behind the airlock-tunnel port (Chapter One climax).
##
## Round 47 REDESIGN. Root causes of the weak Round 45/46 encounter (found
## by measuring from the real observation spot, see MILESTONE1_DESIGN.md):
##   - the tunnel port's sill was at y 1.25, so through it only the head and
##     shoulder girdle were ever visible -- the arm and torso animation
##     played BELOW the frame, unseen (port now 0.84 x 0.9, sill y 1.05);
##   - the body was one capsule for both legs, a short arm on a straight
##     girdle: a "head and shoulders shadow" with no limb separation;
##   - the reaction was 1.15 s of mostly small rotations about axes that do
##     not show in silhouette from the observation spot.
##
## Body (a real joint hierarchy, near-black, unshaded, against the lit
## tunnel wall): separate legs (thigh/shin), a narrow waist under a deep
## ribcage, UNEVEN sloped shoulders (one 22 deg, one 14 deg), a neck slightly
## too long, a head a little small and elongated, arms slightly too long
## (fingertips at the knee) with elbow, wrist and three long fingers.
## Local frame: +X faces the Control Room, Z is the body's lateral axis, so
## rolls about X and moves along Z read in silhouette from the port.
##
## Sequence (state "react" then "retreat"; deterministic, tests drive it):
##   idle         OBSERVATION   still, asymmetric; the head slowly tips over
##   react 0.00   RECOGNITION   a held, uncomfortable pause; the head slowly
##                              rights itself -- it has noticed you
##   react 0.90   FIRST MOVE    a 70 ms SNAP: the head drops to the far
##                              shoulder, the upper body jerks sideways --
##                              then dead still in that pose
##   react 1.35   SHUDDER       stepped (not smooth) asymmetric jerks of the
##                              chest and shoulders at ~14 Hz; ONE arm rises
##                              out to the side out of time with the body,
##                              elbow bending the wrong way, wrist hanging;
##                              the other arm hangs dead
##   retreat      IMPOSSIBLE    a held beat, then a feet-still GLIDE along
##                RETREAT       the tunnel, accelerating far past walking
##                              speed, leaning away from its travel, the
##                              head staying turned to the window
##   gone         DISAPPEARANCE behind the port frame / into Engineering --
##                              never a fade in the middle of the glass.
## Reduced effects: the shudder uses 4 slow snaps instead of the 14 Hz jitter.
## `time_scale` exists for the developer's slow-motion replay only.

signal finished
const DIRECT_ONLY := 1 << 19
const RECOG_END := 0.9
const SNAP_S := 0.07
const FIRST_END := 1.35
const REACT_S := 2.45
const RETREAT_S := 0.6
const RETREAT_HOLD := 0.08
const RETREAT_DIST := 1.25
const FIRST_MOVE_AT := 1.2         # idle: the slow head tilt begins
const HIP_Y := 0.9
const SHUDDER_HZ := 14.0
const SHOULDER_SLOPE := {-1: 22.0, 1: 14.0}
## The arm that rises (local -Z: toward the port's open side as seen from
## the observation spot) and the one that hangs dead.
const RAISED := -1
const DEAD := 1

var state: String = "gone"
var t: float = 0.0
var time_scale: float = 1.0        # developer slow-motion replay only
var reduced: bool = false
var _base: Vector3
var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _arms: Dictionary = {}          # side -> [shoulder, elbow, wrist]
var _legs: Dictionary = {}          # side -> [hip, knee]
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.012, 0.012, 0.015)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hips = _joint(self, Vector3(0, HIP_Y, 0))
	_part(_hips, CapsuleMesh, Vector3(0, 0.0, 0), 0.12, 0.34, Vector3(90, 0, 0))     # pelvis, across
	for side in [-1, 1]:
		var hj: Node3D = _joint(_hips, Vector3(0, -0.03, side * 0.095))
		_part(hj, CapsuleMesh, Vector3(0, -0.22, 0), 0.068, 0.47)
		var kn: Node3D = _joint(hj, Vector3(0, -0.45, 0))
		_part(kn, CapsuleMesh, Vector3(0, -0.21, 0), 0.052, 0.44)
		_legs[side] = [hj, kn]
	_spine = _joint(_hips, Vector3(0, 0.04, 0))
	_part(_spine, CapsuleMesh, Vector3(0, 0.13, 0), 0.085, 0.3, Vector3.ZERO, Vector3(0.75, 1.0, 1.0))   # narrow waist
	_chest = _joint(_spine, Vector3(0, 0.26, 0))
	_part(_chest, CapsuleMesh, Vector3(0, 0.08, 0), 0.135, 0.42, Vector3.ZERO, Vector3(0.62, 1.0, 1.0))  # ribcage
	# Uneven, SLOPED shoulders (two capsules from the neck base): the -Z side
	# drops more steeply (22 deg) than the +Z side (14 deg).
	for side in [-1, 1]:
		var slope: float = SHOULDER_SLOPE[side]
		_part(_chest, CapsuleMesh, Vector3(0, 0.27 - 0.12 * tan(deg_to_rad(slope)), side * 0.12), 0.058, 0.27, Vector3(90.0 + slope if side == 1 else 90.0 - slope, 0, 0))
	for side in [-1, 1]:
		var sh: Node3D = _joint(_chest, Vector3(0, 0.27 - 0.235 * tan(deg_to_rad(SHOULDER_SLOPE[side])), side * 0.235))
		_part(sh, CapsuleMesh, Vector3(0, -0.17, 0), 0.046, 0.37)
		var el: Node3D = _joint(sh, Vector3(0, -0.34, 0))
		_part(el, CapsuleMesh, Vector3(0, -0.18, 0), 0.04, 0.38)
		var wr: Node3D = _joint(el, Vector3(0, -0.37, 0))
		_part(wr, BoxMesh, Vector3(0, -0.05, 0), 0.0, 0.0, Vector3.ZERO, Vector3(0.03, 0.1, 0.075))       # palm
		for f in 3:
			_part(wr, CapsuleMesh, Vector3(0, -0.15, (f - 1) * 0.024), 0.009, 0.12)                      # long fingers
		_arms[side] = [sh, el, wr]
	_neck = _joint(_chest, Vector3(0, 0.29, 0))
	_part(_neck, CapsuleMesh, Vector3(0, 0.08, 0), 0.036, 0.19)                 # a little too long
	_head = _joint(_neck, Vector3(0, 0.15, 0))
	_part(_head, SphereMesh, Vector3(0, 0.1, 0), 0.086, 0.25)                  # small, elongated
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = DIRECT_ONLY
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_base = position
	visible = false


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func _part(parent: Node3D, mesh_type, pos: Vector3, r: float, h: float, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
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
	mi.material_override = _mat
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
	step_pose(0.0)


func react() -> void:
	if state == "idle":
		state = "react"
		t = 0.0


func reset() -> void:
	state = "gone"
	t = 0.0
	visible = false
	position = _base
	time_scale = 1.0
	_pose_reset()


func head_point() -> Vector3:
	return _head.global_position + _head.global_basis.y * 0.1 if _head != null else global_position + Vector3(0, 1.7, 0)


## A hand / fingertip point (tests and renders measure the arm's travel).
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
			if t < RECOG_END:
				return "recognition"
			if t < FIRST_END:
				return "first_movement"
			return "shudder"
		"retreat":
			return "retreat"
	return "gone"


func _pose_reset() -> void:
	if _hips != null:
		_hips.position = Vector3(0, HIP_Y, 0)
	for n in [_hips, _spine, _chest, _neck, _head]:
		if n != null:
			n.rotation = Vector3.ZERO
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


## The asymmetric standing posture every stage starts from.
func _stance() -> void:
	_pose_reset()
	_hips.position.z = 0.03                       # weight on one leg
	_hips.rotation.x = deg_to_rad(-3.0)
	_legs[1][0].rotation.x = deg_to_rad(3.0)
	_legs[-1][0].rotation.x = deg_to_rad(-2.0)
	_legs[-1][1].rotation.z = deg_to_rad(-6.0)    # one knee slightly bent
	_spine.rotation.x = deg_to_rad(4.0)
	_arms[RAISED][0].rotation.x = deg_to_rad(4.0)     # arms held a little off the body
	_arms[DEAD][0].rotation.x = deg_to_rad(-5.0)
	_arms[DEAD][2].rotation.z = deg_to_rad(8.0)


## Idle head roll (deg) at time tt: a slow tip toward one shoulder.
func _idle_roll(tt: float) -> float:
	return 9.0 + 16.0 * smoothstep(FIRST_MOVE_AT, FIRST_MOVE_AT + 2.2, tt)


## Hard stepped noise in [-1, 1]: holds a value, then jumps (a shudder,
## not a wobble). Deterministic.
static func _jolt(x: float, seed_v: float) -> float:
	var k: float = floor(x)
	var h: float = fposmod(sin(k * 12.9898 + seed_v * 78.233) * 43758.5453, 1.0)
	var e: float = smoothstep(0.0, 0.18, x - k)       # ~5 ms ease into each new value
	var hp: float = fposmod(sin((k - 1.0) * 12.9898 + seed_v * 78.233) * 43758.5453, 1.0)
	return lerpf(hp, h, e) * 2.0 - 1.0


func step_pose(tt: float) -> void:
	match state:
		"idle":
			_stance()
			_head.rotation.x = deg_to_rad(_idle_roll(tt))
			_head.rotation.z = deg_to_rad(-7.0)
			_chest.rotation.x = deg_to_rad(-3.0) * smoothstep(FIRST_MOVE_AT, FIRST_MOVE_AT + 2.2, tt)
			_last_idle_roll = _idle_roll(tt)
		"react":
			_stance()
			if tt < RECOG_END:
				# RECOGNITION: utterly still; the head slowly rights itself.
				var u: float = smoothstep(0.0, RECOG_END, tt)
				_head.rotation.x = deg_to_rad(lerpf(_last_idle_roll, 0.0, u))
				_head.rotation.z = deg_to_rad(-7.0 * (1.0 - u))
			else:
				# FIRST MOVEMENT: a snap, then held. The head drops hard to one
				# shoulder while the torso jerks the other way.
				var s: float = clampf((tt - RECOG_END) / SNAP_S, 0.0, 1.0)
				s = 1.0 - pow(1.0 - s, 3.0)
				_head.rotation.x = deg_to_rad(70.0) * s
				_neck.rotation.x = deg_to_rad(16.0) * s
				_chest.rotation.x = deg_to_rad(10.0) * s
				_spine.rotation.x = deg_to_rad(4.0 - 2.0 * s)
				_hips.position.z = 0.03 - 0.06 * s
				_arms[DEAD][0].rotation.x = deg_to_rad(-5.0 + 12.0 * s)     # thrown by the jerk
				if tt >= FIRST_END:
					_shudder(tt - FIRST_END)
			if tt >= REACT_S:
				state = "retreat"
				t = 0.0
		"retreat":
			var v: float = clampf(tt / RETREAT_S, 0.0, 1.0)
			var w: float = clampf((v - RETREAT_HOLD / RETREAT_S) / (1.0 - RETREAT_HOLD / RETREAT_S), 0.0, 1.0)
			var travel: float = pow(w, 2.2)                      # accelerating, feet still
			_stance()
			position = _base + Vector3(-0.08 * travel, 0.0, RETREAT_DIST * travel)
			var lean: float = smoothstep(0.0, 0.35, v)
			_hips.position.z = -0.03
			_hips.rotation.x = deg_to_rad(-20.0) * lean          # dragged: leans AWAY from its travel (+Z)
			_spine.rotation.x = deg_to_rad(-8.0) * lean
			_chest.rotation.y = deg_to_rad(38.0) * lean          # body turns away...
			_neck.rotation.y = deg_to_rad(-22.0) * lean
			_head.rotation.y = deg_to_rad(-30.0) * lean          # ...the head stays on the window
			_head.rotation.x = deg_to_rad(58.0)                  # still dropped to the shoulder
			# The raised arm stays up as it is dragged away, then drops behind.
			_arms[RAISED][0].rotation.x = deg_to_rad(150.0 - 110.0 * lean)
			_arms[RAISED][1].rotation.x = deg_to_rad(140.0 * (1.0 - lean))
			_arms[DEAD][0].rotation.x = deg_to_rad(28.0) * lean
			_arms[DEAD][2].rotation.x = deg_to_rad(20.0) * lean
			for side in [-1, 1]:
				_legs[side][0].rotation.x = deg_to_rad(side * 4.0) * lean   # legs together, not walking
			if v >= 1.0:
				visible = false
				state = "gone"
				_pose_reset()
				position = _base
				time_scale = 1.0
				finished.emit()


var _last_idle_roll: float = 9.0


## SHUDDER (time since it began): stepped asymmetric jerks; one arm rises
## out of time with the body, the other hangs dead.
func _shudder(st: float) -> void:
	var hz: float = 3.0 if reduced else SHUDDER_HZ
	if reduced:
		st = floor(st * hz) / hz          # every part changes only on the same few slow beats
	var x: float = st * hz
	var amp: float = 1.0 - 0.3 * clampf(st / (REACT_S - FIRST_END), 0.0, 1.0)
	_chest.rotation.x = deg_to_rad(10.0 + 16.0 * _jolt(x, 1.0) * amp)
	_chest.rotation.y = deg_to_rad(12.0 * _jolt(x * 0.8, 2.0) * amp)
	_spine.rotation.x = deg_to_rad(2.0 + 8.0 * _jolt(x * 1.3, 3.0) * amp)
	_hips.position.z = -0.03 + 0.05 * _jolt(x * 0.6, 4.0) * amp
	_head.rotation.x = deg_to_rad(70.0 - 30.0 * absf(_jolt(x * 1.1, 5.0)) * amp)
	_head.rotation.y = deg_to_rad(24.0 * _jolt(x * 0.9, 6.0) * amp)
	_neck.rotation.x = deg_to_rad(16.0 + 10.0 * _jolt(x, 7.0))
	# The out-of-sync arm, in the FRONTAL plane so it reads in silhouette:
	# over 0.35 s the upper arm rises straight up beside the head, then the
	# forearm hooks over the top of the head and hangs there, the hand limp
	# -- a marionette's arm. It jerks on its OWN, slower beat.
	var rise: float = smoothstep(0.0, 0.35, st)
	var fold: float = smoothstep(0.2, 0.55, st)
	_arms[RAISED][0].rotation.x = deg_to_rad(150.0 + 12.0 * _jolt(st * 5.0, 8.0)) * rise
	_arms[RAISED][1].rotation.x = deg_to_rad(140.0) * fold
	_arms[RAISED][2].rotation.x = deg_to_rad(40.0 + 15.0 * _jolt(st * 7.0, 10.0)) * fold
	# The other arm hangs dead, barely moved by the jerks.
	_arms[DEAD][0].rotation.x = deg_to_rad(-4.0 + 4.0 * _jolt(x, 9.0))
