extends Node3D
## Round 45 Priorities 7-8: the FIGURE behind the airlock-tunnel port.
##
## A human-sized, indistinct silhouette built from a real jointed hierarchy
## (hips -> spine -> chest -> neck -> head; shoulders -> upper arm -> fore-
## arm per side), dark and matte, lit only by the tunnel light behind it --
## a recognisable head and shoulders, no face, no features. It exists only
## for DIRECT sight (DIRECT_ONLY layer: the eye and the Control Room port's
## portal camera; never surveillance feeds).
##
## A procedural, time-based animation (no tweens; deterministic for tests):
##   "idle"    almost still: a slow, slightly wrong sway, head a few degrees
##             off level, one shoulder lower;
##   "react"   0.55 s: the upper body CONVULSES -- spine and chest snap in
##             opposite directions, the head jerks sideways twice (too far,
##             too fast), one arm flicks up, the other hangs;
##   "retreat" 0.8 s: leans back past balance and slides out of the frame
##             along the tunnel (+z), accelerating (cubic), shoulders
##             leading, arms trailing asymmetrically -- not a walk;
##   "gone"    hidden, pose reset (ready for a developer replay).
## Limbs stay attached (rotations about real joints only); the figure stays
## inside the tunnel volume; it is hidden once fully past the frame.

signal finished
const DIRECT_ONLY := 1 << 19
## Round 46: a longer, multi-step, readable sequence (the 0.55 s version
## read as "one standing shadow" at the real viewing distance).
const REACT_S := 1.15
const RETREAT_S := 0.9
const RETREAT_DIST := 1.15
const FIRST_MOVE_AT := 1.2         # idle: the small first movement begins

var state: String = "gone"
var t: float = 0.0
var _base: Vector3
var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _arms: Dictionary = {}          # side -> [shoulder, elbow]
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	# Round 46: an UNSHADED near-black silhouette against the lit tunnel wall
	# -- its articulated outline is what reads at ~4 m, not its shading.
	_mat.albedo_color = Color(0.015, 0.015, 0.018)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hips = _joint(self, Vector3(0, 0.88, 0))
	_part(_hips, CapsuleMesh, Vector3(0, -0.45, 0), 0.13, 0.9)          # legs (one shape, indistinct)
	_spine = _joint(_hips, Vector3(0, 0.05, 0))
	_part(_spine, CapsuleMesh, Vector3(0, 0.22, 0), 0.12, 0.55)
	_chest = _joint(_spine, Vector3(0, 0.38, 0))
	_part(_chest, CapsuleMesh, Vector3(0, 0.02, 0), 0.085, 0.46, Vector3(90, 0, 0))   # shoulder girdle, across the body
	_neck = _joint(_chest, Vector3(0, 0.09, 0))
	_part(_neck, CapsuleMesh, Vector3(0, 0.03, 0), 0.045, 0.1)
	_head = _joint(_neck, Vector3(0, 0.07, 0))
	_part(_head, SphereMesh, Vector3(0, 0.09, 0), 0.092, 0.23)
	for side in [-1, 1]:
		var sh: Node3D = _joint(_chest, Vector3(0, 0.05, side * 0.2))
		_part(sh, CapsuleMesh, Vector3(0, -0.16, 0), 0.05, 0.34)
		var el: Node3D = _joint(sh, Vector3(0, -0.32, 0))
		_part(el, CapsuleMesh, Vector3(0, -0.16, 0), 0.045, 0.32)
		_arms[side] = [sh, el]
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


func _part(parent: Node3D, mesh_type, pos: Vector3, r: float, h: float, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m: Mesh = mesh_type.new()
	if m is CapsuleMesh:
		(m as CapsuleMesh).radius = r
		(m as CapsuleMesh).height = maxf(h, r * 2.0)
	elif m is SphereMesh:
		(m as SphereMesh).radius = r
		(m as SphereMesh).height = h
	mi.mesh = m
	mi.material_override = _mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)


func appear() -> void:
	position = _base
	_pose_reset()
	state = "idle"
	t = 0.0
	visible = true


func react() -> void:
	if state == "idle":
		state = "react"
		t = 0.0


func reset() -> void:
	state = "gone"
	t = 0.0
	visible = false
	position = _base
	_pose_reset()


func head_point() -> Vector3:
	return _head.global_position if _head != null else global_position + Vector3(0, 1.6, 0)


func is_in_frame() -> bool:
	return visible and absf(position.z - _base.z) < 0.3


func _pose_reset() -> void:
	if _hips != null:
		_hips.position = Vector3(0, 0.88, 0)
	for n in [_hips, _spine, _chest, _neck, _head]:
		if n != null:
			n.rotation = Vector3.ZERO
	for side in _arms:
		_arms[side][0].rotation = Vector3.ZERO
		_arms[side][1].rotation = Vector3.ZERO


func _process(delta: float) -> void:
	if state == "gone":
		return
	t += delta
	step_pose(t)


## Deterministic pose for the current state at time `tt` (tests drive it).
##   idle     still; after FIRST_MOVE_AT the head tilts slowly over (16 deg)
##            and the near shoulder drops -- the "small initial movement";
##   react    0.00-0.12 a twitch (head jerks), 0.12-0.36 FROZEN in that
##            twitch, 0.36-1.15 the SHUDDER: the head snaps side to side
##            (up to ~60 deg, too fast), the chest twists and lurches
##            sideways, one shoulder hikes and its arm jerks up, the other
##            hangs dead -- asymmetric;
##   retreat  an abrupt SIDEWAYS slide out of the port's frame (along the
##            tunnel), accelerating, leaning away with the head LAGGING
##            behind -- still turned toward the window -- arms trailing.
func step_pose(tt: float) -> void:
	match state:
		"idle":
			_pose_reset()
			var m: float = smoothstep(FIRST_MOVE_AT, FIRST_MOVE_AT + 1.4, tt)
			_spine.rotation.x = sin(tt * 0.7) * 0.012
			_head.rotation.x = deg_to_rad(7.0 + 16.0 * m)
			_head.rotation.y = deg_to_rad(4.0)
			_arms[1][0].rotation.x = deg_to_rad(4.0)
			_arms[-1][0].rotation.x = deg_to_rad(-2.0)
			_chest.rotation.x = deg_to_rad(-5.0) * m
		"react":
			var u: float = clampf(tt / REACT_S, 0.0, 1.0)
			var rt: float = tt
			_pose_reset()
			_head.rotation.x = deg_to_rad(23.0)
			if rt < 0.12:
				var k: float = rt / 0.12
				_head.rotation.x = deg_to_rad(23.0 + 22.0 * k)
				_neck.rotation.z = deg_to_rad(-10.0) * k
			elif rt < 0.36:
				_head.rotation.x = deg_to_rad(45.0)            # frozen mid-twitch
				_neck.rotation.z = deg_to_rad(-10.0)
			else:
				var v: float = (rt - 0.36) / (REACT_S - 0.36)
				var amp: float = 1.0 - v * 0.35
				var snap: float = sign(sin(v * TAU * 3.5)) * pow(absf(sin(v * TAU * 3.5)), 0.35) * amp   # hard snaps
				_head.rotation.x = deg_to_rad(60.0) * snap
				_head.rotation.z = deg_to_rad(-28.0) * absf(snap)
				_neck.rotation.x = deg_to_rad(-18.0) * snap
				_chest.rotation.x = deg_to_rad(-26.0) * sin(v * TAU * 2.5)
				_chest.rotation.y = deg_to_rad(18.0) * sin(v * TAU * 2.0 + 0.6)
				_spine.rotation.x = deg_to_rad(14.0) * sin(v * TAU * 2.5 + 1.1)
				_spine.rotation.z = deg_to_rad(10.0) * v
				_hips.position.z = 0.07 * sin(v * TAU * 3.0)               # lurches sideways
				_arms[1][0].rotation.x = deg_to_rad(-110.0) * smoothstep(0.0, 0.25, v)
				_arms[1][1].rotation.x = deg_to_rad(-55.0) * smoothstep(0.1, 0.3, v)
				_arms[-1][0].rotation.x = deg_to_rad(6.0) * snap
			if u >= 1.0:
				state = "retreat"
				t = 0.0
		"retreat":
			var v: float = clampf(tt / RETREAT_S, 0.0, 1.0)
			var travel: float = v * v * v                        # accelerating
			_pose_reset()
			position = _base + Vector3(-0.1 * travel, 0.0, RETREAT_DIST * travel)
			_hips.rotation.z = deg_to_rad(-14.0) * v
			_spine.rotation.z = deg_to_rad(-28.0) * smoothstep(0.0, 0.4, v)
			_chest.rotation.y = deg_to_rad(32.0) * v
			# The head lags: it stays turned back toward the window.
			_neck.rotation.y = deg_to_rad(-40.0) * v
			_head.rotation.y = deg_to_rad(-35.0) * v
			_head.rotation.x = deg_to_rad(30.0) - deg_to_rad(20.0) * v
			_arms[1][0].rotation.z = deg_to_rad(65.0) * v
			_arms[-1][0].rotation.z = deg_to_rad(-20.0) * v
			_arms[-1][1].rotation.x = deg_to_rad(-75.0) * v
			if v >= 1.0:
				visible = false
				state = "gone"
				_pose_reset()
				position = _base
				finished.emit()
