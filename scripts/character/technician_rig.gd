extends Node3D
## Round 28: the rigged spacecraft-technician character -- a real Skeleton3D
## with smoothly skinned, locally generated meshes (no external assets, so no
## licensing questions). It replaces the procedural CSG body as the visible
## player character (player_body.gd drives it; the old CSG nodes remain only
## as the existing, tested pose anchors and as a fallback visual).
##
## Space: rig root at the floor under the body's plumb line; +Y up, -Z
## forward, +X the character's right. Anatomy for a ~1.70m adult with the
## EYE at EYE_POINT -- 12cm IN FRONT of the ear/shoulder/hip/ankle plumb
## line and level with the chest front, so a straight-down look passes in
## front of the chest onto belly, thighs, knees and boots (verified by
## render; at 9cm the chest bulged 3.5cm in front of the eye and filled the
## lower half of a straight-down view). (Round 28 root cause: the old CSG body had
## its torso in front of the eye and its legs raked ~20 deg forward, so a
## straight-down look landed on two thigh-top spheres directly beneath the
## camera.)
##
## Meshes:
## - BodyMesh  (layer 1): coverall torso, arms, gloved five-finger hands,
##   legs, boots, belt -- seen by the player's own camera AND every other.
## - HeadMesh  (layer 4): head/helmet, visor, headset, neck, collar -- hidden
##   from the player's own camera (the eye is inside it), seen by mirrors,
##   surveillance and future other players.
## Weights are blended across every joint (lofted rings near a joint are
## split between the two bones), so elbows/knees/hips/shoulders bend without
## gaps or detached parts.
##
## Posing is entirely through bone rotations (bone offsets never change, so
## limb lengths are constant). All rest rotations are identity; this script
## keeps its own per-bone local rotations and computes global transforms
## itself, so IK can account for the spine/shoulder chain exactly.

const EYE_POINT: Vector3 = Vector3(0.0, 1.60, -0.12)
const MIRROR_ONLY_LAYER: int = 4

## [name, parent, rest head position (skeleton space)]
const BONES: Array = [
	["Hips", "", Vector3(0, 0.95, 0.0)],
	["Spine", "Hips", Vector3(0, 1.06, 0.005)],
	["Chest", "Spine", Vector3(0, 1.19, 0.01)],
	["UpperChest", "Chest", Vector3(0, 1.31, 0.015)],
	["Neck", "UpperChest", Vector3(0, 1.44, 0.02)],
	["Head", "Neck", Vector3(0, 1.53, 0.01)],
	["RightShoulder", "UpperChest", Vector3(0.04, 1.40, 0.02)],
	["RightUpperArm", "RightShoulder", Vector3(0.175, 1.40, 0.02)],
	["RightLowerArm", "RightUpperArm", Vector3(0.19, 1.085, 0.035)],
	["RightHand", "RightLowerArm", Vector3(0.195, 0.835, 0.005)],
	["LeftShoulder", "UpperChest", Vector3(-0.04, 1.40, 0.02)],
	["LeftUpperArm", "LeftShoulder", Vector3(-0.175, 1.40, 0.02)],
	["LeftLowerArm", "LeftUpperArm", Vector3(-0.19, 1.085, 0.035)],
	["LeftHand", "LeftLowerArm", Vector3(-0.195, 0.835, 0.005)],
	["RightUpperLeg", "Hips", Vector3(0.09, 0.88, 0.0)],
	["RightLowerLeg", "RightUpperLeg", Vector3(0.09, 0.48, -0.01)],
	["RightFoot", "RightLowerLeg", Vector3(0.09, 0.08, 0.0)],
	["RightToes", "RightFoot", Vector3(0.09, 0.02, -0.12)],
	["LeftUpperLeg", "Hips", Vector3(-0.09, 0.88, 0.0)],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(-0.09, 0.48, -0.01)],
	["LeftFoot", "LeftLowerLeg", Vector3(-0.09, 0.08, 0.0)],
	["LeftToes", "LeftFoot", Vector3(-0.09, 0.02, -0.12)],
]

const COL_COVERALL := Color(0.34, 0.37, 0.40)
const COL_GLOVE := Color(0.12, 0.12, 0.13)
const COL_BOOT := Color(0.09, 0.09, 0.1)
const COL_BELT := Color(0.1, 0.1, 0.11)
const COL_ACCENT := Color(0.55, 0.38, 0.12)
const COL_HELMET := Color(0.24, 0.27, 0.3)
const COL_VISOR := Color(0.05, 0.07, 0.09)
const COL_METAL := Color(0.58, 0.59, 0.62)

var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var watch_mount: Node3D
var watch_label: Label3D

var _rest: Dictionary = {}        # bone name -> rest head (skeleton space)
var _parent: Dictionary = {}      # bone name -> parent name
var _local_rot: Dictionary = {}   # bone name -> Quaternion (parent space)
var _mats: Dictionary = {}


func _ready() -> void:
	if skeleton == null:
		build()


func build() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	for b in BONES:
		skeleton.add_bone(b[0])
		var idx: int = skeleton.get_bone_count() - 1
		_rest[b[0]] = b[2]
		_parent[b[0]] = b[1]
		_local_rot[b[0]] = Quaternion.IDENTITY
		var local: Vector3 = b[2]
		if b[1] != "":
			skeleton.set_bone_parent(idx, skeleton.find_bone(b[1]))
			local = b[2] - _rest[b[1]]
		skeleton.set_bone_rest(idx, Transform3D(Basis(), local))
	skeleton.reset_bone_poses()
	_make_materials()
	body_mesh = _build_body()
	head_mesh = _build_head()
	_build_watch()


# ======================================================================
# Mesh construction
# ======================================================================

func _make_materials() -> void:
	for pair in [["coverall", COL_COVERALL, 0.82, 0.0], ["glove", COL_GLOVE, 0.7, 0.0], ["boot", COL_BOOT, 0.55, 0.1], ["belt", COL_BELT, 0.6, 0.1], ["accent", COL_ACCENT, 0.6, 0.0], ["helmet", COL_HELMET, 0.6, 0.15], ["visor", COL_VISOR, 0.12, 0.8], ["metal", COL_METAL, 0.3, 0.8]]:
		var m := StandardMaterial3D.new()
		m.albedo_color = pair[1]
		m.roughness = pair[2]
		m.metallic = pair[3]
		_mats[pair[0]] = m


func _bi(name: String) -> int:
	return skeleton.find_bone(name)


## A builder for one material surface: indexed, skinned, smooth-normal.
class Surf:
	var st := SurfaceTool.new()
	var count: int = 0
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	func vert(p: Vector3, w: Dictionary) -> int:
		var bones := PackedInt32Array([0, 0, 0, 0])
		var weights := PackedFloat32Array([0, 0, 0, 0])
		var keys: Array = w.keys()
		keys.sort_custom(func(a, b): return w[a] > w[b])
		var total := 0.0
		for k in range(mini(4, keys.size())):
			total += w[keys[k]]
		for k in range(mini(4, keys.size())):
			bones[k] = keys[k]
			weights[k] = w[keys[k]] / total
		st.set_bones(bones)
		st.set_weights(weights)
		st.add_vertex(p)
		count += 1
		return count - 1
	func tri(a: int, b: int, c: int) -> void:
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)


## Lofted tube through `rings`; each ring = {c: centre, x: lateral unit axis,
## z: depth unit axis, rx, rz, w: {bone_idx: weight}}. Caps both ends.
func _loft(s: Surf, rings: Array, sides: int, cap_start := true, cap_end := true) -> void:
	var first: int = s.count
	for r in rings:
		for i in sides:
			var a: float = TAU * float(i) / sides
			var p: Vector3 = r.c + r.x * (cos(a) * r.rx) + r.z * (sin(a) * r.rz)
			s.vert(p, r.w)
	for ri in range(rings.size() - 1):
		for i in sides:
			var j: int = (i + 1) % sides
			var a0: int = first + ri * sides + i
			var a1: int = first + ri * sides + j
			var b0: int = first + (ri + 1) * sides + i
			var b1: int = first + (ri + 1) * sides + j
			s.tri(a0, b0, a1)
			s.tri(a1, b0, b1)
	if cap_start:
		var c0: int = s.vert(rings[0].c, rings[0].w)
		for i in sides:
			s.tri(c0, first + i, first + (i + 1) % sides)
	if cap_end:
		var last: int = first + (rings.size() - 1) * sides
		var c1: int = s.vert(rings[-1].c, rings[-1].w)
		for i in sides:
			s.tri(c1, last + (i + 1) % sides, last + i)


func _ring(c: Vector3, axis: Vector3, lateral_hint: Vector3, rx: float, rz: float, w: Dictionary) -> Dictionary:
	var ax: Vector3 = axis.normalized()
	var x: Vector3 = (lateral_hint - ax * lateral_hint.dot(ax)).normalized()
	var z: Vector3 = ax.cross(x).normalized()
	return {"c": c, "x": x, "z": z, "rx": rx, "rz": rz, "w": w}


## Weight dictionary helper: {"BoneA": 0.7, "BoneB": 0.3} -> {idx: w}.
func _w(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[_bi(k)] = d[k]
	return out


## Rings along a two-bone limb (root -> joint -> end) with radii sampled
## along it and weights blended across the middle joint.
func _limb_rings(root_b: String, mid_b: String, end_b: String, end_pos: Vector3, radii: Array, lateral: Vector3, start_extra: Dictionary = {}) -> Array:
	var p0: Vector3 = _rest[root_b]
	var p1: Vector3 = _rest[mid_b]
	var p2: Vector3 = end_pos
	var l1: float = p0.distance_to(p1)
	var l2: float = p1.distance_to(p2)
	var total: float = l1 + l2
	var rings: Array = []
	var n: int = radii.size()
	for i in n:
		var t: float = float(i) / (n - 1)
		var d: float = t * total
		var c: Vector3
		var axis: Vector3
		if d <= l1:
			c = p0.lerp(p1, d / l1)
			axis = p1 - p0
		else:
			c = p1.lerp(p2, (d - l1) / l2)
			axis = p2 - p1
		# Blend weights within +/-0.05m of the middle joint.
		var blend: float = clampf((d - l1 + 0.05) / 0.10, 0.0, 1.0)
		var w := {root_b: 1.0 - blend, mid_b: blend}
		if i == 0 and not start_extra.is_empty():
			w = start_extra
		rings.append(_ring(c, axis, lateral, radii[i].x, radii[i].y, _w(w)))
	return rings


func _build_body() -> MeshInstance3D:
	var cov := Surf.new()
	var glove := Surf.new()
	var boot := Surf.new()
	var belt := Surf.new()
	var accent := Surf.new()

	# --- Torso: pelvis -> waist -> chest -> shoulder line, elliptical rings
	# weighted across Hips/Spine/Chest/UpperChest. ---
	# Round 30 Priority 1 (proportions, rendered turnaround): the torso was a
	# straight tube -- chest no wider than the hips, almost no waist, flat
	# back and seat. Rings reshaped only (no bones/joints/poses change):
	# broader chest, tapered waist, seat and shoulder-blade volume added
	# BEHIND; the chest FRONT surface is unchanged (first-person eye
	# clearance), as are the arm/watch/walk rigs.
	var torso := [
		[0.80, 0.135, 0.104, 0.02, {"Hips": 1.0}],
		[0.88, 0.156, 0.118, 0.018, {"Hips": 1.0}],
		[0.97, 0.146, 0.106, 0.008, {"Hips": 0.6, "Spine": 0.4}],
		[1.04, 0.128, 0.096, 0.002, {"Hips": 0.2, "Spine": 0.8}],
		[1.12, 0.142, 0.100, -0.003, {"Spine": 0.6, "Chest": 0.4}],
		[1.21, 0.172, 0.104, -0.006, {"Chest": 1.0}],
		[1.29, 0.178, 0.108, -0.002, {"Chest": 0.5, "UpperChest": 0.5}],
		[1.36, 0.172, 0.106, 0.004, {"UpperChest": 1.0}],
		[1.41, 0.140, 0.092, 0.01, {"UpperChest": 1.0}],
		[1.445, 0.085, 0.07, 0.015, {"UpperChest": 0.7, "Neck": 0.3}],
	]
	var rings: Array = []
	for t in torso:
		rings.append(_ring(Vector3(0, t[0], t[3]), Vector3.UP, Vector3.RIGHT, t[1], t[2], _w(t[4])))
	_loft(cov, rings, 20)

	# Belt band and a chest name patch (worn on the coverall).
	_loft(belt, [
		_ring(Vector3(0, 0.985, 0.004), Vector3.UP, Vector3.RIGHT, 0.156, 0.108, _w({"Hips": 0.5, "Spine": 0.5})),
		_ring(Vector3(0, 1.025, 0.0), Vector3.UP, Vector3.RIGHT, 0.146, 0.103, _w({"Hips": 0.3, "Spine": 0.7})),
	], 20, false, false)
	_box(accent, Vector3(0.075, 1.25, -0.108), Vector3(0.07, 0.035, 0.006), _w({"Chest": 1.0}))
	_box(accent, Vector3(-0.075, 1.25, -0.108), Vector3(0.05, 0.02, 0.006), _w({"Chest": 1.0}))

	# --- Arms (shoulder cap -> elbow -> wrist), coverall sleeves. ---
	for side in [1.0, -1.0]:
		var pre: String = "Right" if side > 0 else "Left"
		var radii: Array = [Vector2(0.058, 0.055), Vector2(0.052, 0.05), Vector2(0.047, 0.046), Vector2(0.042, 0.042), Vector2(0.038, 0.038), Vector2(0.04, 0.038), Vector2(0.037, 0.033), Vector2(0.032, 0.028), Vector2(0.03, 0.025)]
		var arm: Array = _limb_rings(pre + "UpperArm", pre + "LowerArm", pre + "Hand", _rest[pre + "Hand"], radii, Vector3(side, 0, 0))
		# Shoulder blends into the torso: the first ring is shared between
		# the upper arm and the chest, and a rounded deltoid covers the joint
		# (a pointed transition ring here read as a spike from the front).
		arm[0].w = _w({pre + "UpperArm": 0.6, "UpperChest": 0.4})
		_loft(cov, arm, 14)
		_ellipsoid(cov, _rest[pre + "UpperArm"] + Vector3(-side * 0.012, -0.01, 0.0), Vector3(0.06, 0.06, 0.058), _w({pre + "UpperArm": 0.6, "UpperChest": 0.4}), 10, 16)
		_build_hand(glove, pre, side)

	# --- Legs (hip -> knee -> ankle), coverall, and boots. ---
	for side in [1.0, -1.0]:
		var pre: String = "Right" if side > 0 else "Left"
		# Round 30: fuller upper thigh tapering to the knee, and a calf.
		var radii: Array = [Vector2(0.086, 0.102), Vector2(0.083, 0.094), Vector2(0.077, 0.083), Vector2(0.065, 0.07), Vector2(0.057, 0.063), Vector2(0.061, 0.07), Vector2(0.057, 0.064), Vector2(0.046, 0.05), Vector2(0.04, 0.043)]
		var leg: Array = _limb_rings(pre + "UpperLeg", pre + "LowerLeg", pre + "Foot", _rest[pre + "Foot"] + Vector3(0, 0.04, 0), radii, Vector3(side, 0, 0))
		leg[0].w = _w({pre + "UpperLeg": 0.6, "Hips": 0.4})
		# Start the thigh tube INSIDE the pelvis (its top ring hidden in the
		# torso), uncapped: a capped top ring at the hip joint showed as a
		# flat flared "pocket" outside the hips.
		leg.insert(0, _ring(_rest[pre + "UpperLeg"] + Vector3(-side * 0.02, 0.07, 0.0), Vector3.DOWN, Vector3(side, 0, 0), 0.07, 0.075, _w({"Hips": 1.0})))
		_loft(cov, leg, 16, false, true)
		_build_boot(boot, pre)

	var mi := MeshInstance3D.new()
	mi.name = "BodyMesh"
	mi.mesh = _commit([[cov, "coverall"], [glove, "glove"], [boot, "boot"], [belt, "belt"], [accent, "accent"]])
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skeleton.create_skin_from_rest_transforms()
	return mi


func _build_hand(s: Surf, pre: String, side: float) -> void:
	var wrist: Vector3 = _rest[pre + "Hand"]
	var w := _w({pre + "Hand": 1.0})
	var cuff := _w({pre + "Hand": 0.5, pre + "LowerArm": 0.5})
	# Palm: flattened loft from wrist down to the knuckles (palm faces the
	# thigh in the relaxed rest pose: width along Z, thickness along X).
	_loft(s, [
		_ring(wrist + Vector3(0, 0.005, 0), Vector3.DOWN, Vector3(0, 0, 1), 0.03, 0.022, cuff),
		_ring(wrist + Vector3(0, -0.04, -0.004), Vector3.DOWN, Vector3(0, 0, 1), 0.043, 0.018, w),
		_ring(wrist + Vector3(0, -0.085, -0.006), Vector3.DOWN, Vector3(0, 0, 1), 0.044, 0.016, w),
	], 12)
	# Four fingers (index at the front), slightly curled toward the palm.
	var finger_z: Array = [-0.03, -0.01, 0.01, 0.028]
	var finger_len: Array = [0.075, 0.082, 0.077, 0.062]
	for f in 4:
		var base: Vector3 = wrist + Vector3(0, -0.088, finger_z[f] - 0.006)
		var mid: Vector3 = base + Vector3(-side * 0.008, -finger_len[f] * 0.55, 0)
		var tip: Vector3 = mid + Vector3(-side * 0.02, -finger_len[f] * 0.42, 0)
		_loft(s, [
			_ring(base, mid - base, Vector3(0, 0, 1), 0.0095, 0.009, w),
			_ring(mid, tip - base, Vector3(0, 0, 1), 0.0088, 0.0082, w),
			_ring(tip, tip - mid, Vector3(0, 0, 1), 0.0072, 0.007, w),
		], 7)
	# Thumb from the front of the palm, angled forward and down.
	var tb: Vector3 = wrist + Vector3(-side * 0.005, -0.03, -0.035)
	var tm: Vector3 = tb + Vector3(-side * 0.012, -0.03, -0.022)
	var tt: Vector3 = tm + Vector3(-side * 0.014, -0.028, -0.008)
	_loft(s, [
		_ring(tb, tm - tb, Vector3(1, 0, 0), 0.012, 0.011, w),
		_ring(tm, tt - tb, Vector3(1, 0, 0), 0.0105, 0.0098, w),
		_ring(tt, tt - tm, Vector3(1, 0, 0), 0.0085, 0.008, w),
	], 7)


func _build_boot(s: Surf, pre: String) -> void:
	var a: Vector3 = _rest[pre + "Foot"]
	var fw := _w({pre + "Foot": 1.0})
	var tw := _w({pre + "Foot": 0.4, pre + "Toes": 0.6})
	# Boot shaft around the ankle, then the foot lofted heel -> toe.
	_loft(s, [
		_ring(a + Vector3(0, 0.1, 0), Vector3.UP, Vector3.RIGHT, 0.05, 0.055, _w({pre + "LowerLeg": 0.6, pre + "Foot": 0.4})),
		_ring(a + Vector3(0, 0.0, 0), Vector3.UP, Vector3.RIGHT, 0.052, 0.06, fw),
	], 12, false, false)
	_loft(s, [
		_ring(Vector3(a.x, 0.045, a.z + 0.075), Vector3.FORWARD, Vector3.RIGHT, 0.042, 0.045, fw),
		_ring(Vector3(a.x, 0.05, a.z + 0.02), Vector3.FORWARD, Vector3.RIGHT, 0.05, 0.055, fw),
		_ring(Vector3(a.x, 0.04, a.z - 0.07), Vector3.FORWARD, Vector3.RIGHT, 0.05, 0.04, tw),
		_ring(Vector3(a.x, 0.032, a.z - 0.15), Vector3.FORWARD, Vector3.RIGHT, 0.043, 0.032, tw),
		_ring(Vector3(a.x, 0.03, a.z - 0.185), Vector3.FORWARD, Vector3.RIGHT, 0.028, 0.026, tw),
	], 12)


func _build_head() -> MeshInstance3D:
	var helmet := Surf.new()
	var visor := Surf.new()
	var metal := Surf.new()
	var cov := Surf.new()
	var hw := _w({"Head": 1.0})
	# Neck and collar (head mesh: hidden from the player's own camera).
	# Round 29 Priority 3: a believable neck (6cm radius, not a 5cm pipe)
	# that meets a raised coverall collar, so only ~3cm of neck shows
	# between the collar and the helmet's lower rim.
	_loft(cov, [
		_ring(Vector3(0, 1.415, 0.02), Vector3.UP, Vector3.RIGHT, 0.064, 0.062, _w({"UpperChest": 1.0})),
		_ring(Vector3(0, 1.475, 0.02), Vector3.UP, Vector3.RIGHT, 0.059, 0.058, _w({"Neck": 1.0})),
		_ring(Vector3(0, 1.535, 0.012), Vector3.UP, Vector3.RIGHT, 0.056, 0.055, _w({"Neck": 0.4, "Head": 0.6})),
	], 16, false, false)
	_loft(cov, [
		_ring(Vector3(0, 1.405, 0.02), Vector3.UP, Vector3.RIGHT, 0.105, 0.088, _w({"UpperChest": 1.0})),
		_ring(Vector3(0, 1.45, 0.02), Vector3.UP, Vector3.RIGHT, 0.082, 0.074, _w({"UpperChest": 0.75, "Neck": 0.25})),
		_ring(Vector3(0, 1.475, 0.022), Vector3.UP, Vector3.RIGHT, 0.072, 0.069, _w({"UpperChest": 0.4, "Neck": 0.6})),
	], 20, false, false)
	# Helmet shell: a matte work helmet over the skull, centred slightly
	# behind the eyes; ~0.20m wide / 0.24m tall incl. chin guard -- in
	# proportion to the ~0.46m shoulder span.
	_ellipsoid(helmet, Vector3(0, 1.615, -0.02), Vector3(0.098, 0.112, 0.118), hw, 16, 22)
	# Chin guard, blended into the shell's lower front.
	_ellipsoid(helmet, Vector3(0, 1.54, -0.04), Vector3(0.07, 0.048, 0.07), hw, 10, 16)
	# Neck seal: the helmet's soft lower rim hugging the neck, so the
	# helmet->collar transition reads as gear, not a bare stalk.
	_loft(helmet, [
		_ring(Vector3(0, 1.478, 0.018), Vector3.UP, Vector3.RIGHT, 0.068, 0.066, _w({"Neck": 0.7, "Head": 0.3})),
		_ring(Vector3(0, 1.515, 0.012), Vector3.UP, Vector3.RIGHT, 0.074, 0.072, _w({"Neck": 0.2, "Head": 0.8})),
		_ring(Vector3(0, 1.55, 0.0), Vector3.UP, Vector3.RIGHT, 0.08, 0.085, hw),
	], 18, false, false)
	# Visor: a glossy band wrapping the front at eye level, standing just
	# proud of the shell so it reads as a separate part.
	_ellipsoid(visor, Vector3(0, 1.597, -0.056), Vector3(0.086, 0.043, 0.092), hw, 10, 22)
	# Headset ear pads seated on the shell sides.
	for side in [1.0, -1.0]:
		_loft(metal, [
			_ring(Vector3(side * 0.09, 1.598, -0.005), Vector3(side, 0, 0), Vector3(0, 0, 1), 0.03, 0.03, hw),
			_ring(Vector3(side * 0.108, 1.598, -0.005), Vector3(side, 0, 0), Vector3(0, 0, 1), 0.027, 0.027, hw),
		], 14)
	var mi := MeshInstance3D.new()
	mi.name = "HeadMesh"
	mi.mesh = _commit([[helmet, "helmet"], [visor, "visor"], [metal, "metal"], [cov, "coverall"]])
	mi.layers = MIRROR_ONLY_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skeleton.create_skin_from_rest_transforms()
	return mi


func _ellipsoid(s: Surf, c: Vector3, r: Vector3, w: Dictionary, rings: int, segs: int) -> void:
	var first: int = s.count
	for i in range(rings + 1):
		var th: float = PI * float(i) / rings
		for j in segs:
			var ph: float = TAU * float(j) / segs
			s.vert(c + Vector3(r.x * sin(th) * cos(ph), r.y * cos(th), r.z * sin(th) * sin(ph)), w)
	for i in rings:
		for j in segs:
			var a: int = first + i * segs + j
			var b: int = first + i * segs + (j + 1) % segs
			var c2: int = first + (i + 1) * segs + j
			var d: int = first + (i + 1) * segs + (j + 1) % segs
			# Round 29: wound like _loft() (outward-facing). The old order
			# was reversed, so every ellipsoid -- helmet, chin, visor and the
			# shoulder deltoids -- rendered INSIDE-OUT (back faces only): the
			# helmet read as a featureless glossy black ball and the deltoids
			# as dark holes on the shoulders.
			s.tri(a, c2, b)
			s.tri(b, c2, d)


func _box(s: Surf, c: Vector3, size: Vector3, w: Dictionary) -> void:
	var h: Vector3 = size * 0.5
	var corners: Array = []
	for k in 8:
		corners.append(s.vert(c + Vector3(h.x * (1 if k & 1 else -1), h.y * (1 if k & 2 else -1), h.z * (1 if k & 4 else -1)), w))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		s.tri(corners[f[0]], corners[f[1]], corners[f[2]])
		s.tri(corners[f[0]], corners[f[2]], corners[f[3]])


func _commit(parts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for p in parts:
		var s: Surf = p[0]
		if s.count == 0:
			continue
		s.st.generate_normals()
		s.st.set_material(_mats[p[1]])
		s.st.commit(mesh)
	return mesh


## The wristwatch: on the right forearm just above the wrist, following the
## forearm bone; dorsal (back-of-wrist) face; readable text face.
func _build_watch() -> void:
	watch_mount = BoneAttachment3D.new()
	watch_mount.name = "WatchMount"
	watch_mount.bone_name = "RightLowerArm"
	skeleton.add_child(watch_mount)
	var wrist: Vector3 = _rest["RightHand"]
	var elbow: Vector3 = _rest["RightLowerArm"]
	var dir: Vector3 = (elbow - wrist).normalized()
	# Dorsal side of the relaxed hand = lateral (+X for the right arm).
	var dorsal: Vector3 = (Vector3.RIGHT - dir * dir.x).normalized()
	var frame := Node3D.new()
	frame.name = "Watch"
	# Bone-local placement: 5cm up the forearm from the wrist.
	var pos_sk: Vector3 = wrist + dir * 0.05
	frame.transform = Transform3D(Basis(dorsal.cross(dir).normalized(), dorsal, dir), pos_sk - elbow)
	watch_mount.add_child(frame)
	var strap := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.035
	sm.bottom_radius = 0.035
	sm.height = 0.022
	sm.radial_segments = 20
	strap.mesh = sm
	strap.rotation_degrees = Vector3(90, 0, 0)
	strap.material_override = _mats["belt"]
	frame.add_child(strap)
	var case_mi := MeshInstance3D.new()
	case_mi.name = "WatchCase"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.027
	cm.bottom_radius = 0.028
	cm.height = 0.012
	cm.radial_segments = 24
	case_mi.mesh = cm
	case_mi.position = Vector3(0, 0.038, 0)
	case_mi.material_override = _mats["metal"]
	frame.add_child(case_mi)
	var face := MeshInstance3D.new()
	face.name = "Face"
	var fm := CylinderMesh.new()
	fm.top_radius = 0.024
	fm.bottom_radius = 0.024
	fm.height = 0.002
	fm.radial_segments = 24
	face.mesh = fm
	face.position = Vector3(0, 0.0445, 0)
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.03, 0.05, 0.05)
	face_mat.emission_enabled = true
	face_mat.emission = Color(0.02, 0.08, 0.06)
	face.material_override = face_mat
	frame.add_child(face)
	watch_label = Label3D.new()
	watch_label.name = "WatchFaceText"
	watch_label.text = "--"
	# Text sized to the 42mm dial: ~4mm cap height, 2 short lines fit.
	watch_label.font_size = 32
	watch_label.pixel_size = 0.00016
	watch_label.line_spacing = -6.0
	watch_label.outline_size = 0
	watch_label.modulate = Color(0.45, 1.0, 0.75)
	watch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	watch_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	watch_label.double_sided = false
	watch_label.no_depth_test = false
	# Lie on the face, readable from outside (+Y of the frame).
	watch_label.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.0465, 0))
	frame.add_child(watch_label)


func set_watch_text(text: String) -> void:
	if watch_label != null:
		watch_label.text = text


func watch_face_node() -> Node3D:
	return watch_mount.get_node("Watch/Face")


## Rotate only the text about the face normal so it reads level to `cam`.
func level_watch_text(cam: Node3D) -> void:
	var frame: Node3D = watch_mount.get_node("Watch")
	watch_label.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0.0465, 0))
	var g: Transform3D = watch_label.global_transform
	var n: Vector3 = g.basis.z.normalized()
	var up_p: Vector3 = (g.basis.y - n * g.basis.y.dot(n)).normalized()
	var cu: Vector3 = cam.global_transform.basis.y
	var cu_p: Vector3 = (cu - n * cu.dot(n)).normalized()
	if up_p.length() < 0.5 or cu_p.length() < 0.5:
		return
	watch_label.rotate_object_local(Vector3(0, 0, 1), atan2(n.dot(up_p.cross(cu_p)), up_p.dot(cu_p)))


# ======================================================================
# Posing (bone rotations only)
# ======================================================================

func reset_pose() -> void:
	for b in _local_rot:
		_local_rot[b] = Quaternion.IDENTITY


func set_local(bone: String, q: Quaternion) -> void:
	_local_rot[bone] = q


func get_local(bone: String) -> Quaternion:
	return _local_rot[bone]


## Global (skeleton-space) basis and head position of `bone` under the
## current local rotations (rests are identity-rotation offsets).
func bone_basis(bone: String) -> Basis:
	var p: String = _parent[bone]
	var b := Basis(_local_rot[bone])
	return b if p == "" else bone_basis(p) * b


func bone_pos(bone: String) -> Vector3:
	var p: String = _parent[bone]
	if p == "":
		return _rest[bone]
	return bone_pos(p) + bone_basis(p) * (_rest[bone] - _rest[p])


func rest_pos(bone: String) -> Vector3:
	return _rest[bone]


## Set `bone` so its GLOBAL rotation becomes `g` (given current ancestors).
func set_global(bone: String, g: Basis) -> void:
	var p: String = _parent[bone]
	var parent_g: Basis = Basis() if p == "" else bone_basis(p)
	_local_rot[bone] = (parent_g.inverse() * g).get_rotation_quaternion()


## Round 29 Priority 7: one crossfade layer for pose SWITCHES (stand <->
## sit <-> lie). The caller (player_body.gd, the single owner of every bone)
## still computes each frame's target pose from scratch; snapshot() captures
## what was last shown, and crossfade_from() eases from that snapshot to the
## new target -- per-bone slerp plus the rig's own placement -- so no joint
## has two competing writers and nothing snaps.
func snapshot() -> Dictionary:
	return {"rot": _local_rot.duplicate(), "xf": transform}


func crossfade_from(snap: Dictionary, w: float) -> void:
	if snap.is_empty() or w >= 1.0:
		return
	var k: float = clampf(w, 0.0, 1.0)
	var rots: Dictionary = snap["rot"]
	for b in _local_rot:
		if rots.has(b):
			_local_rot[b] = (rots[b] as Quaternion).slerp(_local_rot[b], k)
	var from_xf: Transform3D = snap["xf"]
	transform = from_xf.interpolate_with(transform, k)


func apply_to_skeleton() -> void:
	for b in _local_rot:
		skeleton.set_bone_pose_rotation(skeleton.find_bone(b), _local_rot[b])


## Look: spine share over Chest/UpperChest, then Neck and Head (radians,
## + = up). Rotation about +X tilts the forward (-Z) direction upward.
func pose_look(spine: float, neck: float, head: float) -> void:
	set_local("Chest", Quaternion(Vector3.RIGHT, spine * 0.5))
	set_local("UpperChest", Quaternion(Vector3.RIGHT, spine * 0.5))
	set_local("Neck", Quaternion(Vector3.RIGHT, neck))
	set_local("Head", Quaternion(Vector3.RIGHT, head))


static func _frame(axis: Vector3, hinge: Vector3) -> Basis:
	return Basis(axis, hinge, axis.cross(hinge))


## Two-bone arm IK to `target` (skeleton space), elbow toward `pole`.
## `blend` 0..1 eases from the current (rest/swing) pose to the solved one
## in joint space: upper arm first, elbow, then forearm roll/wrist.
## `roll` is the forearm pronation (radians) applied about the forearm;
## `wrist_level` bends the hand back toward horizontal by that fraction.
func pose_arm_ik(side: String, target: Vector3, pole: Vector3, blend: float, roll: float = 0.0, wrist_level: float = 0.0) -> void:
	var up_b: String = side + "UpperArm"
	var lo_b: String = side + "LowerArm"
	var ha_b: String = side + "Hand"
	if blend <= 0.0:
		set_local(up_b, Quaternion.IDENTITY)
		set_local(lo_b, Quaternion.IDENTITY)
		set_local(ha_b, Quaternion.IDENTITY)
		return
	var s: Vector3 = bone_pos(up_b)
	var r_s: Vector3 = _rest[up_b]
	var r_e: Vector3 = _rest[lo_b]
	var r_w: Vector3 = _rest[ha_b]
	var l1: float = r_s.distance_to(r_e)
	var l2: float = r_e.distance_to(r_w)
	var d: Vector3 = target - s
	var dist: float = clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dn: Vector3 = d.normalized()
	var along: float = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var out: float = sqrt(maxf(l1 * l1 - along * along, 0.0))
	var pl: Vector3 = (pole - dn * pole.dot(dn)).normalized()
	var e: Vector3 = s + dn * along + pl * out
	var w: Vector3 = s + dn * dist
	# Rest frames (skeleton space, parent chain at rest orientation).
	var parent_g: Basis = bone_basis(_parent[up_b])
	var u_r: Vector3 = parent_g * (r_e - r_s).normalized()
	var f_r: Vector3 = parent_g * (r_w - r_e).normalized()
	var side_x: Vector3 = parent_g * Vector3(1.0 if side == "Right" else -1.0, 0, 0)
	var h_r: Vector3 = u_r.cross(f_r)
	if h_r.length() < 0.05:
		h_r = side_x.cross(u_r)
	h_r = h_r.normalized()
	var u_d: Vector3 = (e - s).normalized()
	var f_d: Vector3 = (w - e).normalized()
	var h_d: Vector3 = u_d.cross(f_d)
	if h_d.length() < 0.05:
		h_d = h_r
	h_d = h_d.normalized()
	# Joint-space blend (shoulder leads, elbow follows, wrist last).
	var t_s: float = smoothstep(0.0, 0.8, blend)
	var t_e: float = smoothstep(0.05, 0.85, blend)
	var t_w: float = smoothstep(0.4, 1.0, blend)
	var q_full: Quaternion = (_frame(u_d, h_d) * _frame(u_r, h_r).transposed()).get_rotation_quaternion()
	var b_upper := Basis(Quaternion.IDENTITY.slerp(q_full, t_s))
	var u: Vector3 = b_upper * u_r
	var h: Vector3 = b_upper * h_r
	var flex_r: float = u_r.angle_to(f_r)
	var flex_d: float = u_d.angle_to(f_d)
	var f: Vector3 = u.rotated(h, lerpf(flex_r, flex_d, t_e))
	var hh: Vector3 = (h - f * f.dot(h)).normalized()
	var h_rr: Vector3 = (h_r - f_r * f_r.dot(h_r)).normalized()
	var b_fore: Basis = Basis(f, roll * t_w) * _frame(f, hh) * _frame(f_r, h_rr).transposed()
	set_global(up_b, b_upper * parent_g)
	set_global(lo_b, b_fore * parent_g)
	var hand_g: Basis = b_fore * parent_g
	if wrist_level != 0.0:
		var ax: Vector3 = f.cross(Vector3.UP)
		if ax.length() > 0.01:
			var slope: float = asin(clampf(f.y, -1.0, 1.0))
			var flex: float = -clampf(slope * wrist_level, -deg_to_rad(35.0), deg_to_rad(35.0)) * t_w
			hand_g = Basis(ax.normalized(), flex) * hand_g
	set_global(ha_b, hand_g)


## Roll (radians) that turns the watch face toward `eye` (skeleton space)
## for the forearm pose that pose_arm_ik(target, pole) produces at blend 1.
func watch_roll_toward(eye: Vector3, target: Vector3, pole: Vector3) -> float:
	var saved: Dictionary = _local_rot.duplicate()
	pose_arm_ik("Right", target, pole, 1.0, 0.0, 0.0)
	var fore_g: Basis = bone_basis("RightLowerArm")
	var e: Vector3 = bone_pos("RightLowerArm")
	var w: Vector3 = bone_pos("RightHand")
	var f: Vector3 = (w - e).normalized()
	var frame: Node3D = watch_mount.get_node("Watch")
	var face_n: Vector3 = fore_g * frame.transform.basis.y
	var face_p: Vector3 = e + fore_g * frame.transform.origin
	var to_eye: Vector3 = eye - face_p
	var n_p: Vector3 = (face_n - f * face_n.dot(f)).normalized()
	var e_p: Vector3 = (to_eye - f * to_eye.dot(f)).normalized()
	_local_rot = saved
	return atan2(f.dot(n_p.cross(e_p)), n_p.dot(e_p))


## Simple procedural walk at `phase` (radians) with amplitude 0..1.
func pose_walk(phase: float, amount: float, swing_right_arm: bool) -> void:
	var a: float = clampf(amount, 0.0, 1.0)
	for side in ["Right", "Left"]:
		var ph: float = phase + (0.0 if side == "Right" else PI)
		var hip: float = sin(ph) * deg_to_rad(24.0) * a
		var knee: float = maxf(0.0, -sin(ph + 0.6)) * deg_to_rad(38.0) * a
		set_local(side + "UpperLeg", Quaternion(Vector3.RIGHT, hip))
		set_local(side + "LowerLeg", Quaternion(Vector3.RIGHT, -knee))
		set_local(side + "Foot", Quaternion(Vector3.RIGHT, -hip * 0.4))
		if side == "Left" or swing_right_arm:
			# Arms swing opposite to the same-side leg.
			set_local(side + "UpperArm", Quaternion(Vector3.RIGHT, -sin(ph) * deg_to_rad(16.0) * a))
			set_local(side + "LowerArm", Quaternion(Vector3.RIGHT, deg_to_rad(10.0) * a))


## Round 29 Priority 5: IK-placed gait. `gait` is in STEPS (a heel strike
## at every integer: right leg on even, left on odd); `dir` is the travel
## direction in rig space (x, z); stance feet move back along -dir at
## ground speed from `ahead` to `behind`, swing feet arc forward. Arms
## counter-swing with the opposite leg.
func pose_gait(gait: float, dir: Vector2, amount: float, ahead: float, behind: float, swing_right_arm: bool, stance: float = 0.68) -> void:
	var a: float = clampf(amount, 0.0, 1.0)
	var d3 := Vector3(dir.x, 0.0, dir.y)
	# Side-steps: shorter sweep (legs must not cross).
	var k: float = lerpf(1.0, 0.55, absf(dir.x))
	var span: float = (ahead + behind) * k
	for leg in ["Right", "Left"]:
		var p: float = fposmod(gait - (0.0 if leg == "Right" else 1.0), 2.0)
		var off: float
		var lift: float = 0.0
		if p < stance:
			off = ahead * k - span * (p / stance)             # stance: planted
		else:
			var u: float = (p - stance) / (2.0 - stance)
			off = -behind * k + span * smoothstep(0.0, 1.0, u) # swing forward
			lift = 0.06 * sin(PI * u)
		var rest: Vector3 = _rest[leg + "Foot"]
		var o: Vector3 = d3 * off
		# Side-steps never cross the legs: each foot may move outward freely
		# but at most 5cm toward the midline.
		o.x = maxf(o.x, -0.05) if leg == "Right" else minf(o.x, 0.05)
		pose_leg_ik(leg, rest + (o + Vector3(0.0, lift, 0.0)) * a)
		if leg == "Left" or swing_right_arm:
			var arm: String = ("Left" if leg == "Right" else "Right") + "UpperArm"
			# Arm swings forward with the OPPOSITE leg (dir.y < 0 = forward).
			var fwd: float = -off * dir.y / maxf(ahead, 0.01)
			set_local(arm, Quaternion(Vector3.RIGHT, fwd * deg_to_rad(11.0) * a))
			set_local(arm.replace("Upper", "Lower"), Quaternion(Vector3.RIGHT, deg_to_rad(10.0) * a))


## Seated: thighs forward, shins down, a slight forward trunk.
func pose_sit() -> void:
	for side in ["Right", "Left"]:
		set_local(side + "UpperLeg", Quaternion(Vector3.RIGHT, deg_to_rad(88.0)))
		set_local(side + "LowerLeg", Quaternion(Vector3.RIGHT, deg_to_rad(-86.0)))
		set_local(side + "Foot", Quaternion.IDENTITY)
		set_local(side + "UpperArm", Quaternion(Vector3.RIGHT, deg_to_rad(28.0)))
		set_local(side + "LowerArm", Quaternion(Vector3.RIGHT, deg_to_rad(42.0)))
	set_local("Spine", Quaternion(Vector3.RIGHT, deg_to_rad(-4.0)))


## Two-bone leg IK toward an ankle target (knee pole forward).
func pose_leg_ik(side: String, ankle_target: Vector3) -> void:
	var up_b: String = side + "UpperLeg"
	var lo_b: String = side + "LowerLeg"
	var s: Vector3 = bone_pos(up_b)
	var l1: float = _rest[up_b].distance_to(_rest[lo_b])
	var l2: float = _rest[lo_b].distance_to(_rest[side + "Foot"])
	var d: Vector3 = ankle_target - s
	var dist: float = clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dn: Vector3 = d.normalized()
	var along: float = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var out: float = sqrt(maxf(l1 * l1 - along * along, 0.0))
	var pole: Vector3 = bone_basis("Hips") * Vector3(0, 0, -1)
	var pl: Vector3 = (pole - dn * pole.dot(dn)).normalized()
	var k: Vector3 = s + dn * along + pl * out
	var a: Vector3 = s + dn * dist
	var parent_g: Basis = bone_basis("Hips")
	var u_r: Vector3 = parent_g * (_rest[lo_b] - _rest[up_b]).normalized()
	var f_r: Vector3 = parent_g * (_rest[side + "Foot"] - _rest[lo_b]).normalized()
	var q_u: Quaternion = Quaternion(u_r, (k - s).normalized())
	set_global(up_b, Basis(q_u) * parent_g)
	var cur_f: Vector3 = Basis(q_u) * f_r
	set_global(lo_b, Basis(Quaternion(cur_f, (a - k).normalized())) * Basis(q_u) * parent_g)
	set_global(side + "Foot", parent_g)
