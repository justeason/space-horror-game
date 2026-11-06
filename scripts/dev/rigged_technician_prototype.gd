extends Node3D
## Round 25 Priority 5: EXPERIMENTAL rigged-character prototype -- a staging
## step toward replacing PlayerBody's procedural CSG/lofted-tube visual
## with a proper skinned, Skeleton3D-driven low-poly technician. NOT used
## by the player, main.tscn, or any gameplay system; it exists so the
## migration path (bone naming, proportions, skinning, and posing the
## watch-inspection gesture purely through bone rotations) can be built
## and tested in isolation first. See MILESTONE1_DESIGN.md, Round 25,
## "Character rig migration plan".
##
## - Bone names follow Godot's SkeletonProfileHumanoid (Hips, Spine, Chest,
##   UpperChest, Neck, Head, LeftShoulder/LeftUpperArm/LeftLowerArm/
##   LeftHand, LeftUpperLeg/LeftLowerLeg/LeftFoot/LeftToes, Right...), so a
##   future imported .glb technician retargeted to that profile can drop in
##   with the same pose code.
## - Proportions are anthropometric for a ~1.75m adult (eye 1.64m, acromion
##   1.43m, upper arm 0.31m, forearm 0.25m), unlike the current PlayerBody
##   whose shoulders sit 0.335m below the eye and whose arms are ~18% long
##   (documented in Round 25; not changed there to keep this round's fix
##   honest -- the proportion correction belongs to this replacement).
## - The mesh is generated here (rigid per-bone skinning: every vertex 100%
##   weighted to one bone) purely as a stand-in; a real authored mesh with
##   blended weights replaces it later without touching the pose API.
## - Skeleton space: feet at y=0, front = -Z, right = +X (same convention
##   as PlayerBody's own body space, so pose targets transfer directly).

const EYE_HEIGHT: float = 1.64

## Bone name -> [parent name, rest head position in skeleton space].
const BONES: Array = [
	["Hips", "", Vector3(0, 0.95, 0)],
	["Spine", "Hips", Vector3(0, 1.06, 0)],
	["Chest", "Spine", Vector3(0, 1.22, 0)],
	["UpperChest", "Chest", Vector3(0, 1.34, 0)],
	["Neck", "UpperChest", Vector3(0, 1.47, 0.0)],
	["Head", "Neck", Vector3(0, 1.56, 0.0)],
	["RightShoulder", "UpperChest", Vector3(0.04, 1.42, 0)],
	["RightUpperArm", "RightShoulder", Vector3(0.19, 1.43, 0)],
	["RightLowerArm", "RightUpperArm", Vector3(0.21, 1.12, 0.0)],
	["RightHand", "RightLowerArm", Vector3(0.22, 0.87, -0.01)],
	["LeftShoulder", "UpperChest", Vector3(-0.04, 1.42, 0)],
	["LeftUpperArm", "LeftShoulder", Vector3(-0.19, 1.43, 0)],
	["LeftLowerArm", "LeftUpperArm", Vector3(-0.21, 1.12, 0.0)],
	["LeftHand", "LeftLowerArm", Vector3(-0.22, 0.87, -0.01)],
	["RightUpperLeg", "Hips", Vector3(0.1, 0.92, 0)],
	["RightLowerLeg", "RightUpperLeg", Vector3(0.1, 0.5, 0.0)],
	["RightFoot", "RightLowerLeg", Vector3(0.1, 0.08, 0.02)],
	["RightToes", "RightFoot", Vector3(0.1, 0.02, -0.12)],
	["LeftUpperLeg", "Hips", Vector3(-0.1, 0.92, 0)],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(-0.1, 0.5, 0.0)],
	["LeftFoot", "LeftLowerLeg", Vector3(-0.1, 0.08, 0.02)],
	["LeftToes", "LeftFoot", Vector3(-0.1, 0.02, -0.12)],
]

## [bone, from, to, radius_from, radius_to, depth_scale]: tapered prisms
## (rest skeleton space) rigidly skinned to `bone`.
const SEGMENTS: Array = [
	["Hips", Vector3(0, 0.86, 0), Vector3(0, 1.06, 0), 0.16, 0.14, 0.7],
	["Spine", Vector3(0, 1.06, 0), Vector3(0, 1.22, 0), 0.14, 0.16, 0.65],
	["Chest", Vector3(0, 1.22, 0), Vector3(0, 1.34, 0), 0.16, 0.175, 0.62],
	["UpperChest", Vector3(0, 1.34, 0), Vector3(0, 1.45, 0), 0.175, 0.12, 0.6],
	["Neck", Vector3(0, 1.44, 0.01), Vector3(0, 1.57, 0.01), 0.055, 0.05, 1.0],
	["RightShoulder", Vector3(0.04, 1.43, 0), Vector3(0.19, 1.43, 0), 0.06, 0.055, 1.0],
	["RightUpperArm", Vector3(0.19, 1.43, 0), Vector3(0.21, 1.12, 0.0), 0.05, 0.04, 1.0],
	["RightLowerArm", Vector3(0.21, 1.12, 0.0), Vector3(0.22, 0.87, -0.01), 0.038, 0.028, 1.0],
	["RightHand", Vector3(0.22, 0.87, -0.01), Vector3(0.22, 0.69, -0.01), 0.03, 0.022, 0.55],
	["LeftShoulder", Vector3(-0.04, 1.43, 0), Vector3(-0.19, 1.43, 0), 0.06, 0.055, 1.0],
	["LeftUpperArm", Vector3(-0.19, 1.43, 0), Vector3(-0.21, 1.12, 0.0), 0.05, 0.04, 1.0],
	["LeftLowerArm", Vector3(-0.21, 1.12, 0.0), Vector3(-0.22, 0.87, -0.01), 0.038, 0.028, 1.0],
	["LeftHand", Vector3(-0.22, 0.87, -0.01), Vector3(-0.22, 0.69, -0.01), 0.03, 0.022, 0.55],
	["RightUpperLeg", Vector3(0.1, 0.94, 0), Vector3(0.1, 0.5, 0.0), 0.085, 0.06, 1.0],
	["RightLowerLeg", Vector3(0.1, 0.5, 0.0), Vector3(0.1, 0.08, 0.02), 0.058, 0.042, 1.0],
	["RightFoot", Vector3(0.1, 0.05, 0.05), Vector3(0.1, 0.04, -0.14), 0.045, 0.04, 0.6],
	["LeftUpperLeg", Vector3(-0.1, 0.94, 0), Vector3(-0.1, 0.5, 0.0), 0.085, 0.06, 1.0],
	["LeftLowerLeg", Vector3(-0.1, 0.5, 0.0), Vector3(-0.1, 0.08, 0.02), 0.058, 0.042, 1.0],
	["LeftFoot", Vector3(-0.1, 0.05, 0.05), Vector3(-0.1, 0.04, -0.14), 0.045, 0.04, 0.6],
]

## Watch-inspection wrist target relative to the eye, and elbow pole. With
## anatomical shoulders (0.21m below the eye, vs PlayerBody's 0.335m) the
## live body's (0, -0.42, -0.40) would leave the arm nearly straight, so the
## prototype uses its own anatomically-scaled target.
@export var watch_wrist_offset_from_eye: Vector3 = Vector3(0.0, -0.30, -0.30)
@export var watch_elbow_pole: Vector3 = Vector3(1.0, -0.4, -0.3)

var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var _bone_rest_global: Dictionary = {}
var _watch: Dictionary = {}


func _ready() -> void:
	_build_skeleton()
	_build_skinned_mesh()
	_setup_watch_inspection()
	var cam: Camera3D = get_node_or_null("Camera3D")
	if cam != null:
		cam.look_at(Vector3(0, 1.15, 0), Vector3.UP)


func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for entry in BONES:
		skeleton.add_bone(entry[0])
		var idx: int = skeleton.get_bone_count() - 1
		var head: Vector3 = entry[2]
		_bone_rest_global[entry[0]] = head
		var parent_name: String = entry[1]
		var local: Vector3 = head
		if parent_name != "":
			var p: int = skeleton.find_bone(parent_name)
			skeleton.set_bone_parent(idx, p)
			local = head - _bone_rest_global[parent_name]
		skeleton.set_bone_rest(idx, Transform3D(Basis(), local))
	skeleton.reset_bone_poses()


func _build_skinned_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in SEGMENTS:
		_add_prism(st, skeleton.find_bone(seg[0]), seg[1], seg[2], seg[3], seg[4], seg[5])
	_add_head(st, skeleton.find_bone("Head"))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.25, 0.27)
	mat.roughness = 0.8
	st.set_material(mat)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TechnicianMesh"
	mesh_instance.mesh = st.commit()
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()


func _add_prism(st: SurfaceTool, bone: int, a: Vector3, b: Vector3, ra: float, rb: float, depth: float) -> void:
	var sides := 8
	var axis: Vector3 = (b - a).normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = axis.cross(ref).normalized()
	var z: Vector3 = axis.cross(x).normalized()
	var ring_a: Array = []
	var ring_b: Array = []
	for i in sides:
		var ang: float = TAU * float(i) / sides
		var dir: Vector3 = x * cos(ang) + z * sin(ang)
		# Elliptical torso cross-sections: squash world-Z depth.
		dir = Vector3(dir.x, dir.y, dir.z * depth)
		ring_a.append(a + dir * ra)
		ring_b.append(b + dir * rb)
	for i in sides:
		var j: int = (i + 1) % sides
		_tri(st, bone, ring_a[i], ring_b[i], ring_b[j])
		_tri(st, bone, ring_a[i], ring_b[j], ring_a[j])
		_tri(st, bone, a, ring_a[j], ring_a[i])
		_tri(st, bone, b, ring_b[i], ring_b[j])


func _add_head(st: SurfaceTool, bone: int) -> void:
	var c := Vector3(0, 1.645, 0.0)
	var r := Vector3(0.085, 0.11, 0.1)
	var rings := 8
	var segs := 12
	for i in rings:
		for j in segs:
			var p00: Vector3 = _ell(c, r, i, j, rings, segs)
			var p10: Vector3 = _ell(c, r, i + 1, j, rings, segs)
			var p11: Vector3 = _ell(c, r, i + 1, j + 1, rings, segs)
			var p01: Vector3 = _ell(c, r, i, j + 1, rings, segs)
			_tri(st, bone, p00, p11, p10)
			_tri(st, bone, p00, p01, p11)


func _ell(c: Vector3, r: Vector3, i: int, j: int, rings: int, segs: int) -> Vector3:
	var th: float = PI * float(i) / rings
	var ph: float = TAU * float(j) / segs
	return c + Vector3(r.x * sin(th) * cos(ph), r.y * cos(th), r.z * sin(th) * sin(ph))


func _tri(st: SurfaceTool, bone: int, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	for p in [p0, p1, p2]:
		st.set_bones(PackedInt32Array([bone, 0, 0, 0]))
		st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		st.add_vertex(p)


static func _frame(axis: Vector3, hinge: Vector3) -> Basis:
	return Basis(axis, hinge, axis.cross(hinge))


## Same joint-space solve as PlayerBody._setup_watch_raise_rig(), expressed
## as BONE ROTATIONS: upper-arm global rotation, elbow hinge flex, forearm
## pronation roll.
func _setup_watch_inspection(target_offset: Vector3 = Vector3.ZERO) -> void:
	var s: Vector3 = _bone_rest_global["RightUpperArm"]
	var e: Vector3 = _bone_rest_global["RightLowerArm"]
	var w: Vector3 = _bone_rest_global["RightHand"]
	var l1: float = s.distance_to(e)
	var l2: float = e.distance_to(w)
	var u_r: Vector3 = (e - s) / l1
	var f_r: Vector3 = (w - e) / l2
	var h_r: Vector3 = (Vector3.RIGHT - u_r * u_r.dot(Vector3.RIGHT)).normalized()
	var target: Vector3 = Vector3(0, EYE_HEIGHT, 0) + watch_wrist_offset_from_eye + target_offset
	var d: Vector3 = target - s
	var dist: float = clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dn: Vector3 = d.normalized()
	var along: float = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var out: float = sqrt(maxf(l1 * l1 - along * along, 0.0))
	var pole: Vector3 = (watch_elbow_pole - dn * watch_elbow_pole.dot(dn)).normalized()
	var e_d: Vector3 = s + dn * along + pole * out
	var u_d: Vector3 = (e_d - s) / l1
	var f_d: Vector3 = (s + dn * dist - e_d) / l2
	var h_d: Vector3 = u_d.cross(f_d).normalized()
	_watch = {
		"q_upper": (_frame(u_d, h_d) * _frame(u_r, h_r).transposed()).get_rotation_quaternion(),
		"u_r": u_r, "h_r": h_r, "f_r": f_r,
		"flex_r": u_r.angle_to(f_r), "flex_d": u_d.angle_to(f_d),
		"roll": -PI / 2.0,
	}


## Poses the right arm for watch-inspection progress `p` (0 rest, 1 full)
## purely through Skeleton3D bone pose ROTATIONS -- bone offsets (and so
## limb lengths) are never touched.
func set_watch_inspection(p: float) -> void:
	var upper: int = skeleton.find_bone("RightUpperArm")
	var lower: int = skeleton.find_bone("RightLowerArm")
	if p <= 0.0:
		skeleton.set_bone_pose_rotation(upper, Quaternion.IDENTITY)
		skeleton.set_bone_pose_rotation(lower, Quaternion.IDENTITY)
		return
	var t_s: float = smoothstep(0.0, 0.8, p)
	var t_e: float = smoothstep(0.05, 0.85, p)
	var t_w: float = smoothstep(0.4, 1.0, p)
	var q_upper: Quaternion = Quaternion.IDENTITY.slerp(_watch["q_upper"], t_s)
	var b_upper := Basis(q_upper)
	var u: Vector3 = b_upper * _watch["u_r"]
	var h: Vector3 = b_upper * _watch["h_r"]
	var f: Vector3 = u.rotated(h, lerpf(_watch["flex_r"], _watch["flex_d"], t_e))
	# Global forearm rotation: carry the rest forearm frame onto the
	# current one, then pronate about the forearm axis.
	var f_r: Vector3 = _watch["f_r"]
	var h_r: Vector3 = _watch["h_r"]
	var h_r_f: Vector3 = (h_r - f_r * f_r.dot(h_r)).normalized()
	var h_f: Vector3 = (h - f * f.dot(h)).normalized()
	var b_fore: Basis = Basis(f, _watch["roll"] * t_w) * _frame(f, h_f) * _frame(f_r, h_r_f).transposed()
	# Bone pose rotations are parent-relative (rest rotations are identity).
	skeleton.set_bone_pose_rotation(upper, q_upper)
	skeleton.set_bone_pose_rotation(lower, (b_upper.inverse() * b_fore).get_rotation_quaternion())


func bone_global_position(bone_name: String) -> Vector3:
	return skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin


## Round 26 Priority 6: drive this skeleton from the SAME shared pose data
## the live player uses -- the compact dictionary produced by
## CharacterPoseState.to_dict() ({yaw, pitch, watch, posture}), i.e. exactly
## what a future multiplayer peer would receive. Joint angles come from the
## same anatomical distribution (CharacterPoseState.distribute_look_pitch)
## and map onto BONES, not CSG node names: spine share split over Chest and
## UpperChest, then Neck, then Head. Arm bones are posed locally under the
## shoulder chain, so a bending spine carries the raised arm with it.
const _PoseState = preload("res://scripts/player/character_pose_state.gd")
var _applied_bias: float = INF


func apply_pose_state(data: Dictionary) -> void:
	var pitch: float = data.get("pitch", 0.0)
	var posture: int = data.get("posture", _PoseState.Posture.STANDING)
	var d: Dictionary = _PoseState.distribute_look_pitch(pitch, posture)
	_set_pitch("Chest", d["spine"] * 0.5)
	_set_pitch("UpperChest", d["spine"] * 0.5)
	_set_pitch("Neck", d["neck"])
	_set_pitch("Head", d["head"])
	# Round 27: the same shared 1:1 watch target the live body uses
	# (relative to the eye), re-solved when the look pitch changes.
	var watch_pitch: float = pitch if posture == _PoseState.Posture.STANDING else 0.0
	if absf(watch_pitch - _applied_bias) > 0.002:
		_applied_bias = watch_pitch
		var target: Vector3 = _PoseState.watch_target_for_pitch(watch_pitch)
		_setup_watch_inspection(target - watch_wrist_offset_from_eye)
	set_watch_inspection(clampf(data.get("watch", 0.0), 0.0, 1.0))


func _set_pitch(bone_name: String, angle: float) -> void:
	skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), Quaternion(Vector3.RIGHT, angle))


## Global (skeleton-space) forward direction of the head bone -- what a
## viewer would read as "where this character is looking".
func head_forward() -> Vector3:
	return skeleton.get_bone_global_pose(skeleton.find_bone("Head")).basis * Vector3.FORWARD
