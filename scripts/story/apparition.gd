extends Node3D
## Round 46: a reusable APPARITION actor -- an indistinct, dark, human-
## shaped figure with a real jointed hierarchy, a procedural walk and a
## path follower. Used by:
##   - the Junction crossing on INT-02 (CAMERA_ONLY layer: surveillance
##     feeds only, never the technician's own eyes);
##   - the peripheral figure (DIRECT_ONLY layer: the eyes only, never a
##     camera feed).
## It is never a screen-space image: it stands at a real world position, so
## its apparent size, perspective and occlusion come from the camera that
## sees it. No collision, no shadows, nothing left behind when hidden.
##
## Joints: hips -> (thigh -> shin) x2; hips -> spine -> chest -> neck ->
## head; chest -> (upper arm -> forearm) x2. All motion is rotation about
## those joints (limbs stay attached).
##
## Gait (walk): a believable step cycle that is slightly WRONG -- a short
## hitch on every second left step, one arm barely swinging, the head held
## a few degrees off level and too still. Not a monster: something a tired
## technician could talk themselves out of.

signal path_finished
const CAMERA_ONLY := 1 << 18
const DIRECT_ONLY := 1 << 19

var layer_mask: int = CAMERA_ONLY
var speed: float = 0.85                 # m/s along the path
var state: String = "hidden"            # hidden | still | walk
var path: PackedVector3Array = PackedVector3Array()
var _seg: int = 0
var _phase: float = 0.0                 # gait cycle 0..1
var _pause_at: float = -1.0             # path distance where it pauses (head turn)
var _pause_t: float = 0.0
var _dist: float = 0.0
var pause_s: float = 0.0
var travelled: float = 0.0

var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _legs: Dictionary = {}              # side -> [thigh, shin]
var _arms: Dictionary = {}              # side -> [upper, fore]
var _mat: StandardMaterial3D


func _init(p_layer: int = CAMERA_ONLY) -> void:
	layer_mask = p_layer


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.03, 0.03, 0.035)
	_mat.roughness = 1.0
	_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED      # a dark shape, not a glossy mannequin
	_hips = _joint(self, Vector3(0, 0.92, 0))
	_part(_hips, CapsuleMesh, Vector3(0, 0.02, 0), 0.15, 0.32, Vector3(0, 0, 90))      # pelvis
	for side in [-1, 1]:
		var th: Node3D = _joint(_hips, Vector3(side * 0.1, -0.02, 0))
		_part(th, CapsuleMesh, Vector3(0, -0.22, 0), 0.075, 0.46)
		var sh: Node3D = _joint(th, Vector3(0, -0.44, 0))
		_part(sh, CapsuleMesh, Vector3(0, -0.22, 0), 0.06, 0.46)
		_part(sh, BoxMesh, Vector3(0, -0.45, 0.05), 0.0, 0.0, Vector3.ZERO, Vector3(0.09, 0.05, 0.22))   # foot
		_legs[side] = [th, sh]
	_spine = _joint(_hips, Vector3(0, 0.06, 0))
	_part(_spine, CapsuleMesh, Vector3(0, 0.2, 0), 0.15, 0.5, Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
	_chest = _joint(_spine, Vector3(0, 0.36, 0))
	_part(_chest, CapsuleMesh, Vector3(0, 0.04, 0), 0.085, 0.44, Vector3(0, 0, 90))     # shoulder girdle
	_neck = _joint(_chest, Vector3(0, 0.1, 0))
	_part(_neck, CapsuleMesh, Vector3(0, 0.04, 0), 0.045, 0.12)
	_head = _joint(_neck, Vector3(0, 0.08, 0))
	_part(_head, SphereMesh, Vector3(0, 0.1, 0), 0.1, 0.25)
	for side in [-1, 1]:
		var ua: Node3D = _joint(_chest, Vector3(side * 0.21, 0.04, 0))
		_part(ua, CapsuleMesh, Vector3(0, -0.15, 0), 0.05, 0.32)
		var fa: Node3D = _joint(ua, Vector3(0, -0.3, 0))
		_part(fa, CapsuleMesh, Vector3(0, -0.15, 0), 0.045, 0.32)
		_arms[side] = [ua, fa]
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = layer_mask
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func _part(parent: Node3D, mesh_type, pos: Vector3, r: float, h: float, rot: Vector3 = Vector3.ZERO, box: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m: Mesh = mesh_type.new()
	if m is CapsuleMesh:
		(m as CapsuleMesh).radius = r
		(m as CapsuleMesh).height = maxf(h, r * 2.0)
	elif m is SphereMesh:
		(m as SphereMesh).radius = r
		(m as SphereMesh).height = h
	elif m is BoxMesh:
		(m as BoxMesh).size = box
	mi.mesh = m
	mi.material_override = _mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)


# ------------------------------------------------------------- control
## Stand still at `at`, facing `face` (world point).
func show_still(at: Vector3, face: Vector3) -> void:
	state = "still"
	path = PackedVector3Array()
	global_position = at
	_face(face)
	_pose_still(0.0)
	visible = true


## Walk the polyline; optional pause (head turn) at a path distance.
func walk(points: PackedVector3Array, pause_at: float = -1.0, pause_seconds: float = 0.0) -> void:
	path = points
	_seg = 0
	_dist = 0.0
	travelled = 0.0
	_phase = 0.0
	_pause_at = pause_at
	pause_s = pause_seconds
	_pause_t = 0.0
	global_position = points[0]
	if points.size() > 1:
		_face(points[1])
	state = "walk"
	visible = true


func hide_now() -> void:
	state = "hidden"
	visible = false
	path = PackedVector3Array()


func is_shown() -> bool:
	return visible and state != "hidden"


func head_point() -> Vector3:
	return _head.global_position + Vector3(0, 0.1, 0)


## Joint offsets (tests: limbs stay attached).
func joint_offsets() -> Array:
	var out: Array = []
	for side in [-1, 1]:
		out.append(_legs[side][1].position)
		out.append(_arms[side][1].position)
	out.append(_head.position)
	return out


func _face(p: Vector3) -> void:
	var d: Vector3 = p - global_position
	d.y = 0.0
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func _process(delta: float) -> void:
	if state == "walk":
		step(delta)
	elif state == "still":
		_pose_still(Time.get_ticks_msec() / 1000.0)


## One deterministic tick (tests drive it directly).
func step(dt: float) -> void:
	if state != "walk" or path.size() < 2:
		return
	if _pause_at >= 0.0 and travelled >= _pause_at and _pause_t < pause_s:
		_pause_t += dt
		_pose_pause(_pause_t / maxf(pause_s, 0.01))
		return
	var move: float = speed * dt
	# The hitch: every second left step is a beat late.
	var hitch: bool = fmod(_phase, 2.0) > 1.62 and fmod(_phase, 2.0) < 1.8
	if hitch:
		move *= 0.25
	while move > 0.0 and _seg < path.size() - 1:
		var a: Vector3 = global_position
		var b: Vector3 = path[_seg + 1]
		var left: float = a.distance_to(b)
		if left <= move:
			global_position = b
			move -= left
			travelled += left
			_seg += 1
			if _seg < path.size() - 1:
				_face(path[_seg + 1])
		else:
			global_position = a + (b - a) / left * move
			travelled += move
			move = 0.0
	_phase += dt * speed / 0.62 * (0.35 if hitch else 1.0)       # ~0.62 m per step
	_pose_walk(_phase)
	if _seg >= path.size() - 1:
		state = "hidden"
		visible = false
		path_finished.emit()


func _reset_pose() -> void:
	for n in [_hips, _spine, _chest, _neck, _head]:
		n.rotation = Vector3.ZERO
	for side in [-1, 1]:
		for j in _legs[side] + _arms[side]:
			j.rotation = Vector3.ZERO


func _pose_still(t: float) -> void:
	_reset_pose()
	_head.rotation.z = deg_to_rad(6.0)                 # off level, too still
	_head.rotation.x = deg_to_rad(4.0) + sin(t * 0.4) * 0.01
	_arms[1][0].rotation.x = deg_to_rad(3.0)
	_spine.rotation.x = deg_to_rad(2.0)


func _pose_walk(ph: float) -> void:
	_reset_pose()
	var s: float = sin(ph * PI)                     # one stride per unit
	var swing: float = deg_to_rad(24.0)
	_legs[-1][0].rotation.x = s * swing
	_legs[1][0].rotation.x = -s * swing
	_legs[-1][1].rotation.x = maxf(-s, 0.0) * deg_to_rad(-35.0) * -1.0
	_legs[1][1].rotation.x = maxf(s, 0.0) * deg_to_rad(35.0)
	# One arm swings, the other hangs almost still (slightly wrong).
	_arms[-1][0].rotation.x = -s * deg_to_rad(16.0)
	_arms[1][0].rotation.x = s * deg_to_rad(3.0)
	_arms[-1][1].rotation.x = deg_to_rad(-10.0)
	_hips.position.y = 0.92 + absf(cos(ph * PI)) * 0.02
	_spine.rotation.x = deg_to_rad(4.0)
	_head.rotation.z = deg_to_rad(6.0)              # held off level
	_head.rotation.y = 0.0                           # and never turning with the step


func _pose_pause(u: float) -> void:
	_pose_walk(floor(_phase))
	# Mid-crossing: the head turns -- too smoothly -- toward the camera side.
	_head.rotation.y = deg_to_rad(-55.0) * smoothstep(0.0, 0.5, u) * (1.0 - smoothstep(0.75, 1.0, u))
	_neck.rotation.y = _head.rotation.y * 0.3
