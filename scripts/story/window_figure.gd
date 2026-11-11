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
const REACT_S := 0.55
const RETREAT_S := 0.8
const RETREAT_DIST := 0.75

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
	_mat.albedo_color = Color(0.03, 0.03, 0.035)
	_mat.roughness = 0.95
	_mat.metallic = 0.0
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
func step_pose(tt: float) -> void:
	match state:
		"idle":
			_pose_reset()
			# Almost still -- slightly wrong: head off level, one shoulder low.
			_spine.rotation.x = sin(tt * 0.7) * 0.015
			_head.rotation.x = deg_to_rad(7.0) + sin(tt * 0.45) * 0.02
			_head.rotation.y = deg_to_rad(4.0)
			_arms[1][0].rotation.x = deg_to_rad(4.0)
			_arms[-1][0].rotation.x = deg_to_rad(-2.0)
		"react":
			var u: float = clampf(tt / REACT_S, 0.0, 1.0)
			# Two violent, too-fast lateral snaps of the head; chest and spine
			# convulse in opposite directions; one arm flicks up.
			var snap: float = sin(u * TAU * 2.0) * (1.0 - u * 0.3)
			_head.rotation.x = deg_to_rad(38.0) * snap
			_head.rotation.z = deg_to_rad(-22.0) * absf(snap)
			_neck.rotation.x = deg_to_rad(-12.0) * snap
			_chest.rotation.x = deg_to_rad(-16.0) * sin(u * TAU * 3.0)
			_spine.rotation.x = deg_to_rad(10.0) * sin(u * TAU * 3.0 + 1.2)
			_spine.rotation.z = deg_to_rad(9.0) * u
			_arms[1][0].rotation.x = deg_to_rad(-75.0) * smoothstep(0.1, 0.35, u) * (1.0 - smoothstep(0.7, 1.0, u) * 0.4)
			_arms[1][1].rotation.x = deg_to_rad(-40.0) * smoothstep(0.2, 0.4, u)
			_arms[-1][0].rotation.x = deg_to_rad(8.0) * snap
			if u >= 1.0:
				state = "retreat"
				t = 0.0
		"retreat":
			var v: float = clampf(tt / RETREAT_S, 0.0, 1.0)
			var travel: float = v * v * v                        # accelerating
			position = _base + Vector3(-0.08 * travel, 0.0, RETREAT_DIST * travel)
			# Leans back past balance, shoulders lead, arms trail unevenly.
			_hips.rotation.z = deg_to_rad(-10.0) * v
			_spine.rotation.z = deg_to_rad(-24.0) * smoothstep(0.0, 0.5, v)
			_chest.rotation.y = deg_to_rad(28.0) * v
			_head.rotation.x = deg_to_rad(-30.0) * v + sin(v * 40.0) * 0.08 * (1.0 - v)
			_arms[1][0].rotation.z = deg_to_rad(55.0) * v
			_arms[-1][0].rotation.z = deg_to_rad(-15.0) * v
			_arms[-1][1].rotation.x = deg_to_rad(-70.0) * v
			if v >= 1.0:
				visible = false
				state = "gone"
				_pose_reset()
				position = _base
				finished.emit()
