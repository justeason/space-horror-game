extends Node3D
## Round 38 Priority 6-7: the INTERIOR AESTHETIC LAYER -- one design
## language for the whole vehicle (industrial orbital modules, restrained
## cyberpunk accents), derived from the real room geometry:
##   - chamfered ceiling cladding along every ceiling edge (the rectangular
##     rooms read as rounded pressure modules);
##   - integrated LED light strips (per-module accent colour), powered by
##     the module's lighting breaker (dark during an outage);
##   - structural ribs (posts + beam + chamfered corners) every ~1 m along
##     corridors and tunnels, skipped wherever equipment is mounted;
##   - dark kick plates at floor edges, handrails along corridors;
##   - module signage (illuminated, short);
##   - module identity: pipe runs / cable trays (Engineering), a main duct
##     (Life Support), hazard banding + pressure signage (Airlock), an
##     overhead status strip (Control), warm cove light (Quarters).
## Nothing here has collision: navigation, reach and item placement are
## untouched (tested by the capsule sweep and the reach tests).

const ROOMS := {
	"ControlRoomFloor": ["CONTROL · C-1", Color(0.25, 0.85, 0.95), &"", "control"],
	"LivingFloor": ["QUARTERS · H-1", Color(1.0, 0.72, 0.42), &"living_quarters", "quarters"],
	"EngineeringFloor": ["ENGINEERING · E-2", Color(1.0, 0.65, 0.25), &"engineering", "engineering"],
	"LifeSupportFloor": ["LIFE SUPPORT · L-3", Color(0.35, 0.95, 0.75), &"life_support", "lifesupport"],
	"StorageFloor": ["STORAGE · S-4", Color(0.9, 0.92, 0.95), &"", "storage"],
	"CommsFloor": ["COMMS · M-5", Color(0.35, 0.7, 1.0), &"communications", "comms"],
}
const CORRIDORS := ["CorridorFloor", "JunctionAFloor", "CommsTunnelAFloor", "CommsTunnelBFloor", "EngineeringTunnelFloor", "AirlockTunnelFloor", "StorageConnectorAFloor", "StorageConnectorBFloor", "StorageConnectorCFloor", "StorageConnectorDFloor", "LifeSupportTunnelFloor", "LifeSupportBendFloor"]

var strips: Array = []            # [{mat, zone, color}]
var rib_count: int = 0
var decor_count: int = 0
var _avoid: Array = []            # world points of mounted equipment
var _t: float = 0.0
var _clad: StandardMaterial3D
var _frame: StandardMaterial3D
var _kick: StandardMaterial3D
var _pipe: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"station_decor")
	_clad = _m(Color(0.32, 0.34, 0.37), 0.35)
	_frame = _m(Color(0.2, 0.21, 0.23), 0.6)
	_kick = _m(Color(0.1, 0.11, 0.12), 0.4)
	_pipe = _m(Color(0.55, 0.57, 0.6), 0.75)
	_build.call_deferred()


func _m(c: Color, metal: float, em: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.5
	if em != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = em
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	decor_count += 1
	return mi


func _cyl(r: float, length: float, pos: Vector3, along_x: bool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 10
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(0, 0, 90) if along_x else Vector3(90, 0, 0)
	add_child(mi)
	decor_count += 1


## Round 42 Priority 21: the accent strips are a dim GUIDE glow, not a
## light source (playtest: "too bright"). Emission was col x 1.6.
const STRIP_GLOW := 0.55


func _strip(size: Vector3, pos: Vector3, col: Color, zone: StringName) -> void:
	var m := _m(col * 0.25, 0.0, col * STRIP_GLOW)
	m.emission_energy_multiplier = 1.0
	var mi := _box(size, pos, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strips.append({"mat": m, "zone": zone, "color": col})


func _near_equipment(p: Vector3, r: float = 0.55) -> bool:
	for a in _avoid:
		if Vector2(a.x - p.x, a.z - p.z).length() < r and absf(a.y - p.y) < 2.0:
			return true
	return false


func _build() -> void:
	var root: Node = get_parent()
	for grp in ["Interactables", "Equipment"]:
		var g: Node = root.get_node_or_null(grp)
		if g != null:
			for c in g.get_children():
				if c is Node3D:
					_avoid.append((c as Node3D).global_position)
	_avoid.append_array([Vector3(-5.3, 1.0, 1.05), Vector3(-4.41, 1.35, -1.2), Vector3(-4.42, 1.25, -1.88)])
	var geo: Node = root.get_node_or_null("Geometry")
	if geo == null:
		return
	_collect_walls(geo, root.get_node_or_null("StationSeal"))
	for fname in ROOMS:
		var f: CSGBox3D = geo.get_node_or_null(fname)
		var c: CSGBox3D = geo.get_node_or_null(fname.replace("Floor", "Ceiling"))
		if f != null and c != null:
			_dress_room(f, c, ROOMS[fname])
	for fname in CORRIDORS:
		var f: CSGBox3D = geo.get_node_or_null(fname)
		var c: CSGBox3D = geo.get_node_or_null(fname.replace("Floor", "Ceiling"))
		if f != null and c != null:
			_dress_corridor(f, c)


## Room: chamfered ceiling edges, perimeter light strip, kick plates,
## signage and module identity.
func _dress_room(f: CSGBox3D, c: CSGBox3D, spec: Array) -> void:
	var ctr: Vector3 = f.global_position
	var sx: float = f.size.x
	var sz: float = f.size.z
	var top: float = c.global_position.y - c.size.y * 0.5     # ceiling underside
	var col: Color = spec[1]
	var zone: StringName = spec[2]
	var ch := 0.32     # chamfer panel width
	for side in [[Vector3(1, 0, 0), sz], [Vector3(-1, 0, 0), sz], [Vector3(0, 0, 1), sx], [Vector3(0, 0, -1), sx]]:
		var n: Vector3 = side[0]
		var length: float = side[1] - 0.05
		# Round 39: trim follows the REAL wall on this side (its inner
		# face), and is skipped where there is no wall (an opening into a
		# neighbouring space) -- it used to sit on the floor rectangle's
		# edge: buried inside thick walls, or loose in the next room.
		var face: Variant = _side_face(ctr, sx, sz, n)
		if face == null:
			continue
		var half: float = absf(float(face) - (ctr.x if n.x != 0 else ctr.z))
		var pos: Vector3 = Vector3(ctr.x, top - ch * 0.35, ctr.z) + n * (half - ch * 0.35)
		var size: Vector3 = Vector3(0.02, ch, length) if n.x != 0 else Vector3(length, ch, 0.02)
		var rot: Vector3 = Vector3(0, 0, -45.0 * n.x) if n.x != 0 else Vector3(45.0 * n.z, 0, 0)
		_box(size, pos, _clad, rot)
		# Light strip at the chamfer's lower edge.
		var sp: Vector3 = Vector3(ctr.x, top - ch * 0.72, ctr.z) + n * (half - ch * 0.68)
		_strip(Vector3(0.02, 0.02, length * 0.9) if n.x != 0 else Vector3(length * 0.9, 0.02, 0.02), sp, col, zone)
		# Kick plates: one per WALL SEGMENT on this side (never across a
		# doorway, where a low plate read as a bar to trip over).
		for w in _side_walls(ctr, sx, sz, n):
			var a: AABB = w[0]
			var s_lo: float = maxf((a.position.z if n.x != 0 else a.position.x), (ctr.z - sz * 0.5) if n.x != 0 else (ctr.x - sx * 0.5))
			var s_hi: float = minf((a.end.z if n.x != 0 else a.end.x), (ctr.z + sz * 0.5) if n.x != 0 else (ctr.x + sx * 0.5))
			if s_hi - s_lo < 0.1:
				continue
			var mid: float = (s_lo + s_hi) * 0.5
			var kp: Vector3 = (Vector3(float(face) - n.x * 0.012, 0.06, mid) if n.x != 0 else Vector3(mid, 0.06, float(face) - n.z * 0.012))
			_box(Vector3(0.02, 0.12, s_hi - s_lo) if n.x != 0 else Vector3(s_hi - s_lo, 0.12, 0.02), kp, _kick)
	var south: Variant = _side_face(ctr, sx, sz, Vector3(0, 0, -1))
	var sign_pos: Vector3 = Vector3(ctr.x, top - ch - 0.12, (float(south) if south != null else ctr.z - sz * 0.5) + 0.03)
	var lbl := Label3D.new()
	lbl.text = spec[0]
	lbl.font_size = 26
	lbl.pixel_size = 0.0013
	lbl.modulate = col.lightened(0.3)
	lbl.outline_size = 6
	lbl.position = sign_pos
	add_child(lbl)
	match String(spec[3]):
		"engineering":
			for k in 3:
				_cyl(0.035 + k * 0.01, sz - 0.2, Vector3(ctr.x - sx * 0.5 + 0.35 + k * 0.1, top - 0.08, ctr.z), false, _pipe)
			_box(Vector3(0.3, 0.05, sz - 0.3), Vector3(ctr.x + sx * 0.5 - 0.45, top - 0.06, ctr.z), _frame)
		"lifesupport":
			_box(Vector3(sx - 0.5, 0.28, 0.4), Vector3(ctr.x, top - 0.16, ctr.z + sz * 0.5 - 0.5), _m(Color(0.6, 0.62, 0.6), 0.5))
			for k in 2:
				_cyl(0.04, sx - 0.4, Vector3(ctr.x, top - 0.1, ctr.z - sz * 0.5 + 0.35 + k * 0.12), true, _m(Color(0.25, 0.55, 0.45), 0.5))
		"control":
			_strip(Vector3(1.6, 0.05, 0.02), Vector3(ctr.x, top - 0.45, ctr.z - sz * 0.5 + 0.12), Color(0.25, 0.85, 0.95), zone)
		"quarters":
			_strip(Vector3(sx * 0.6, 0.02, 0.02), Vector3(ctr.x, 2.0, ctr.z - sz * 0.5 + 0.03), Color(1.0, 0.62, 0.3), zone)
		"comms":
			# Slim transceiver rack on the free east-wall segment (z 6.0-6.6;
			# the north wall carries the signal station and the link panel),
			# with status LEDs on the B-04 circuit, and a ceiling cable bundle.
			# Round 40: kept clear of the alcove doorway corner (walkway audit).
			var rx: float = ctr.x + sx * 0.5 - 0.16
			var rz: float = ctr.z - sz * 0.5 + 0.3
			_box(Vector3(0.12, 1.7, 0.36), Vector3(rx, 0.95, rz), _frame)
			for k in 5:
				_box(Vector3(0.01, 0.22, 0.3), Vector3(rx - 0.065, 0.4 + k * 0.3, rz), _m(Color(0.14, 0.15, 0.17), 0.5))
				_strip(Vector3(0.01, 0.015, 0.1), Vector3(rx - 0.072, 0.47 + k * 0.3, rz - 0.08), col, zone)
			for k in 3:
				_cyl(0.025, sz - 0.3, Vector3(ctr.x + sx * 0.5 - 0.3 - k * 0.06, top - 0.06, ctr.z), false, _m(Color(0.1, 0.1, 0.12), 0.3))
		"storage":
			for k in 3:
				_box(Vector3(0.02, 1.8, 0.05), Vector3(ctr.x - sx * 0.5 + 0.02, 1.1, ctr.z - 0.6 + k * 0.6), _m(Color(0.85, 0.6, 0.1), 0.2))


## Corridor / tunnel: ribs every ~0.75 m (not where equipment is mounted),
## ceiling chamfers, a centre light strip and a handrail.
func _dress_corridor(f: CSGBox3D, c: CSGBox3D) -> void:
	var ctr: Vector3 = f.global_position
	# Round 39 Priority 2: the run direction comes from the corridor's
	# SIDE WALLS, not the floor's proportions -- the 1.6 x 1.4 m main
	# corridor was dressed across its width (a rib post standing in the
	# walkway and a handrail spanning it).
	var cov_x: float = _coverage(ctr, f.size.x, f.size.z, Vector3(1, 0, 0)) + _coverage(ctr, f.size.x, f.size.z, Vector3(-1, 0, 0))
	var cov_z: float = _coverage(ctr, f.size.x, f.size.z, Vector3(0, 0, 1)) + _coverage(ctr, f.size.x, f.size.z, Vector3(0, 0, -1))
	# Clearly elongated floors run along their long axis (end walls and
	# closure panels would otherwise count as "side" coverage); only
	# near-square floors (the 1.6 x 1.4 m main corridor) need the walls.
	var ratio: float = maxf(f.size.x, f.size.z) / maxf(minf(f.size.x, f.size.z), 0.01)
	var along_x: bool = f.size.x > f.size.z
	if ratio < 1.4 and absf(cov_z - cov_x) > 0.2:
		along_x = cov_z > cov_x
	var length: float = f.size.x if along_x else f.size.z
	var width: float = f.size.z if along_x else f.size.x
	# Interior width between the side walls' inner faces (re-centred).
	var sn: Vector3 = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var f_hi: Variant = _side_face(ctr, f.size.x, f.size.z, sn)
	var f_lo: Variant = _side_face(ctr, f.size.x, f.size.z, -sn)
	if f_hi != null and f_lo != null:
		width = float(f_hi) - float(f_lo)
		if along_x:
			ctr.z = (float(f_hi) + float(f_lo)) * 0.5
		else:
			ctr.x = (float(f_hi) + float(f_lo)) * 0.5
	var top: float = c.global_position.y - c.size.y * 0.5
	var axis: Vector3 = Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var side: Vector3 = Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	# Round 40 Priority 3: posts, handrails and ceiling cladding exist only
	# where that side actually has WALL -- never across a side opening
	# (the Junction -> Comms doorway had a rib post standing in it, a
	# handrail across it and cladding over its top: the "bars").
	var fc: Vector3 = f.global_position
	var segs := {}
	for sgn in [-1.0, 1.0]:
		segs[sgn] = _wall_segments(fc, f.size.x, f.size.z, side * sgn, along_x)
	var n: int = maxi(int(length / 0.75), 1)
	for i in n + 1:
		var p: Vector3 = ctr + axis * (-length * 0.5 + length * float(i) / float(n))
		if i == 0 or i == n or _near_equipment(p):
			continue
		var a_pos: float = p.x if along_x else p.z
		var both: bool = true
		var any_post: bool = false
		for sgn in [-1.0, 1.0]:
			if not _in_segments(segs[sgn], a_pos, 0.12):
				both = false
				continue
			any_post = true
			var post: Vector3 = Vector3(p.x, top * 0.5, p.z) + side * sgn * (width * 0.5 - 0.04)
			_box(Vector3(0.06, top - 0.3, 0.12) if not along_x else Vector3(0.12, top - 0.3, 0.06), post, _frame)
			var corner: Vector3 = Vector3(p.x, top - 0.16, p.z) + side * sgn * (width * 0.5 - 0.16)
			_box(Vector3(0.06, 0.32, 0.12) if not along_x else Vector3(0.12, 0.32, 0.06), corner, _frame, (Vector3(0, 0, -45.0 * sgn) if not along_x else Vector3(45.0 * sgn, 0, 0)))
		if any_post:
			rib_count += 1       # a rib station (frame posts on the wall)
		if not both:
			continue             # the overhead beam needs walls on both sides
		_box(Vector3(0.12, 0.06, width - 0.5) if along_x else Vector3(width - 0.5, 0.06, 0.12), Vector3(p.x, top - 0.04, p.z), _frame)
	for sgn in [-1.0, 1.0]:
		for seg in segs[sgn]:
			var lo: float = seg[0]
			var hi: float = seg[1]
			if hi - lo < 0.3:
				continue
			var mid: float = (lo + hi) * 0.5
			var at := Vector3(mid, 0, ctr.z) if along_x else Vector3(ctr.x, 0, mid)
			var cp: Vector3 = Vector3(at.x, top - 0.12, at.z) + side * sgn * (width * 0.5 - 0.12)
			_box(Vector3(hi - lo - 0.05, 0.26, 0.02) if along_x else Vector3(0.02, 0.26, hi - lo - 0.05), cp, _clad, (Vector3(-45.0 * sgn, 0, 0) if along_x else Vector3(0, 0, 45.0 * sgn)))
			if sgn > 0.0 and hi - lo > 0.6:
				var hp: Vector3 = Vector3(at.x, 1.0, at.z) + side * (width * 0.5 - 0.05)
				if not _near_equipment(hp, 0.3):
					_cyl(0.018, hi - lo - 0.3, hp, along_x, _m(Color(0.7, 0.55, 0.15), 0.6))
	_strip(Vector3(length - 0.3, 0.015, 0.05) if along_x else Vector3(0.05, 0.015, length - 0.3), Vector3(ctr.x, top - 0.01, ctr.z), Color(0.35, 0.8, 0.95), &"")
	_corridor_details(ctr, along_x, length, width, top, segs, side)


# ======================================================================
# Round 40 Priority 4: SPACECRAFT corridors -- lower chamfer panels at the
# floor/wall corners (an octagonal "tunnel" section with the ceiling
# chamfers), cable conduits along the upper wall, vertical panel seams,
# floor plate seams, cyan floor guide lights, labelled access panels.
# All against walls / on the floor; visual only (no collision), so
# navigation is untouched, and only where a WALL runs.
# ======================================================================
var _access_n: int = 0


func _corridor_details(ctr: Vector3, along_x: bool, length: float, width: float, top: float, segs: Dictionary, side: Vector3) -> void:
	var seam := _m(Color(0.12, 0.13, 0.14), 0.3)
	var conduit := _m(Color(0.18, 0.19, 0.21), 0.5)
	var lower := _m(Color(0.26, 0.28, 0.31), 0.45)
	for sgn in [-1.0, 1.0]:
		for seg in segs[sgn]:
			var lo: float = seg[0]
			var hi: float = seg[1]
			var L: float = hi - lo
			if L < 0.3:
				continue
			var mid: float = (lo + hi) * 0.5
			var at := Vector3(mid, 0, ctr.z) if along_x else Vector3(ctr.x, 0, mid)
			var wall: Vector3 = at + side * sgn * (width * 0.5)
			# Lower chamfer panel (45 deg, 0.18 m) along the floor corner:
			# it stays below ankle height and within 0.13 m of the wall.
			var lp: Vector3 = Vector3(wall.x, 0.064, wall.z) - side * sgn * 0.064
			_box(Vector3(L - 0.05, 0.18, 0.02) if along_x else Vector3(0.02, 0.18, L - 0.05), lp, lower, (Vector3(45.0 * sgn, 0, 0) if along_x else Vector3(0, 0, -45.0 * sgn)))
			# Two cable conduits high on the wall.
			for k in 2:
				var cp: Vector3 = Vector3(wall.x, top - 0.42 - k * 0.07, wall.z) - side * sgn * 0.045
				_cyl(0.022, L - 0.08, cp, along_x, conduit)
			# Vertical panel seams every ~0.75 m.
			var ns: int = int(L / 0.75)
			for k in range(1, ns + 1):
				var sp: float = lo + L * float(k) / float(ns + 1)
				var sv := Vector3(sp, 1.15, ctr.z) if along_x else Vector3(ctr.x, 1.15, sp)
				sv += side * sgn * (width * 0.5 - 0.006)
				_box(Vector3(0.012, 1.7, 0.012), sv, seam)
			# A labelled access panel on longer runs.
			if L > 1.3:
				_access_n += 1
				var ap: Vector3 = Vector3(at.x, 1.25, at.z) + side * sgn * (width * 0.5 - 0.012)
				_box(Vector3(0.42, 0.5, 0.02) if along_x else Vector3(0.02, 0.5, 0.42), ap, _m(Color(0.3, 0.32, 0.35), 0.5))
				var lbl := Label3D.new()
				lbl.text = "ACCESS %d%s" % [_access_n, "AB"[_access_n % 2]]
				lbl.font_size = 18
				lbl.pixel_size = 0.0012
				lbl.modulate = Color(0.85, 0.85, 0.8)
				lbl.position = ap + Vector3(0, 0.17, 0) - side * sgn * 0.015
				lbl.rotation_degrees.y = (0.0 if sgn < 0.0 else 180.0) if along_x else (90.0 if sgn < 0.0 else -90.0)
				add_child(lbl)
			# Cyan floor guide lights along the base.
			var nl: int = int(L / 0.5)
			for k in nl:
				var gp: float = lo + 0.25 + k * 0.5
				var g := Vector3(gp, 0.012, ctr.z) if along_x else Vector3(ctr.x, 0.012, gp)
				g += side * sgn * (width * 0.5 - 0.2)
				_strip(Vector3(0.12, 0.008, 0.03) if along_x else Vector3(0.03, 0.008, 0.12), g, Color(0.3, 0.85, 1.0), &"")
	# Floor plate seams across the walkway.
	var nf: int = int(length / 0.75)
	for k in range(1, nf + 1):
		var fp: float = (ctr.x if along_x else ctr.z) - length * 0.5 + length * float(k) / float(nf + 1)
		var fv := Vector3(fp, 0.004, ctr.z) if along_x else Vector3(ctr.x, 0.004, fp)
		_box(Vector3(0.015, 0.006, width - 0.1) if along_x else Vector3(width - 0.1, 0.006, 0.015), fv, seam)


## Merged [lo, hi] intervals (along the corridor axis) covered by wall on
## side `n` of the floor rectangle.
func _wall_segments(ctr: Vector3, sx: float, sz: float, n: Vector3, along_x: bool) -> Array:
	var iv: Array = []
	var lo_lim: float = (ctr.x - sx * 0.5) if along_x else (ctr.z - sz * 0.5)
	var hi_lim: float = (ctr.x + sx * 0.5) if along_x else (ctr.z + sz * 0.5)
	for w in _side_walls(ctr, sx, sz, n):
		var a: AABB = w[0]
		var lo: float = maxf(a.position.x if along_x else a.position.z, lo_lim)
		var hi: float = minf(a.end.x if along_x else a.end.z, hi_lim)
		if hi - lo > 0.05:
			iv.append([lo, hi])
	iv.sort_custom(func(p, q): return p[0] < q[0])
	var merged: Array = []
	for v in iv:
		if not merged.is_empty() and v[0] <= merged[-1][1] + 0.02:
			merged[-1][1] = maxf(merged[-1][1], v[1])
		else:
			merged.append([v[0], v[1]])
	return merged


static func _in_segments(segs: Array, x: float, margin: float) -> bool:
	for sg in segs:
		if x >= sg[0] + margin and x <= sg[1] - margin:
			return true
	return false


## Strips follow their module's lighting breaker.
func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	var br: Node = get_parent().get_node_or_null("Equipment/BreakerPanel")
	for s in strips:
		var on: bool = s["zone"] == &"" or br == null or br.zone_powered(s["zone"])
		(s["mat"] as StandardMaterial3D).emission = (s["color"] as Color) * (STRIP_GLOW if on else 0.0)


func strip_lit(zone: StringName) -> bool:
	for s in strips:
		if s["zone"] == zone:
			return (s["mat"] as StandardMaterial3D).emission.r > 0.01 or (s["mat"] as StandardMaterial3D).emission.b > 0.01
	return false



# ======================================================================
# Round 39: the dressing follows the REAL walls (Geometry CSG boxes named
# *Wall* plus the StationSeal panels), so nothing floats in an opening or
# hides inside a thick wall.
# ======================================================================
var _walls: Array = []      # AABBs (axis-aligned; the station walls are)


func _collect_walls(geo: Node, seal: Node) -> void:
	_walls.clear()
	var srcs: Array = geo.get_children()
	if seal != null:
		srcs.append_array(seal.get_children())
	for n in srcs:
		if n is CSGBox3D and (String(n.name).find("Wall") != -1 or n.get_parent() == seal):
			var b := n as CSGBox3D
			if absf(b.global_transform.basis.get_euler().y) > 0.01:
				continue
			_walls.append(AABB(b.global_position - b.size * 0.5, b.size))


## Walls standing along the floor rectangle's side `n` (within 0.35 m of
## the edge, spanning eye height).
func _side_walls(ctr: Vector3, sx: float, sz: float, n: Vector3) -> Array:
	var out: Array = []
	var along_z: bool = n.x != 0
	var edge: float = (ctr.x + n.x * sx * 0.5) if along_z else (ctr.z + n.z * sz * 0.5)
	var lo: float = (ctr.z - sz * 0.5) if along_z else (ctr.x - sx * 0.5)
	var hi: float = (ctr.z + sz * 0.5) if along_z else (ctr.x + sx * 0.5)
	for w in _walls:
		var a: AABB = w
		if a.position.y > 1.2 or a.end.y < 1.2:
			continue
		var w_lo: float = a.position.x if along_z else a.position.z
		var w_hi: float = a.end.x if along_z else a.end.z
		var thick: float = w_hi - w_lo
		var span: float = (a.size.z if along_z else a.size.x)
		if thick > 0.45 or span < thick:
			continue
		if w_hi < edge - 0.35 or w_lo > edge + 0.3:
			continue
		var o_lo: float = maxf(lo, a.position.z if along_z else a.position.x)
		var o_hi: float = minf(hi, a.end.z if along_z else a.end.x)
		if o_hi - o_lo > 0.05:
			out.append([a, o_hi - o_lo])
	return out


## Share (0..1) of side `n` closed by walls.
func _coverage(ctr: Vector3, sx: float, sz: float, n: Vector3) -> float:
	var total: float = 0.0
	for w in _side_walls(ctr, sx, sz, n):
		total += float(w[1])
	return clampf(total / (sz if n.x != 0 else sx), 0.0, 1.0)


## The inner face (world x or z) of the main wall on side `n`, or null when
## that side is mostly open.
func _side_face(ctr: Vector3, sx: float, sz: float, n: Vector3) -> Variant:
	var ws: Array = _side_walls(ctr, sx, sz, n)
	if ws.is_empty() or _coverage(ctr, sx, sz, n) < 0.45:
		return null
	ws.sort_custom(func(p, q): return float(p[1]) > float(q[1]))
	var a: AABB = ws[0][0]
	if n.x > 0.0: return a.position.x
	if n.x < 0.0: return a.end.x
	if n.z > 0.0: return a.position.z
	return a.end.z
