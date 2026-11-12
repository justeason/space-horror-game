extends Node3D
## Round 49: builds DECK B, the Lower Service Deck, from deck_b_layout.gd
## (one source of truth for the builder, navigation, map, hull and tests).
##
##   Shell     floors, ceilings, walls (0.2 m, centred on the module edges);
##             a wall shared by two modules is built ONCE (up to the higher
##             ceiling) with its doorway cut in it; corner posts close every
##             T-junction; framed pressure doorways, thresholds with hazard
##             markings, room signs on both sides, handrails, cable trays,
##             exposed piping in the service corridors, emergency strips.
##             Real collision (layer 1) everywhere.
##   Lights    ceiling SPOTS pointing DOWN (a downward cone can never reach
##             Deck A above), small accent lights on Deck B's own visual
##             layer; Deck A's lights are told to ignore Deck B's layer, so
##             nothing leaks through the floors in either direction.
##   Hull      every outward wall face, every roof and every underside gets
##             exterior plating (the sunlit EXTERIOR layer), plus structural
##             connectors to Deck A, coolant / power / data conduits, the
##             cargo berthing port, module labels and hull lights.
##   Graph     MovementNodes for every room and doorway, added to the
##             station's ONE movement graph (deck "B"); the shaft is a
##             LADDER link between Deck A's ShaftTop and BShaftBottom.
##   Gates     invisible barriers (the clearance BARRIER_LAYER) + red / green
##             door lamps at the doorways of rooms beyond the technician's
##             Deck B access tier.
##   Rooms     the equipment of B-01 .. B-09 (one script per room).
## PERFORMANCE: Deck B's interior is hidden while the technician is up on
## Deck A away from the shaft and no Deck B camera feed is displayed
## (collision, equipment logic and the simulation keep running).

const L = preload("res://scripts/deck_b/deck_b_layout.gd")
const MovementNodeScript = preload("res://scripts/navigation/movement_node.gd")
const EXTERIOR := 1 << 11
const BARRIER_LAYER := 1 << 9
const ROOM_SCRIPTS := {
	&"b01": "res://scripts/deck_b/lower_junction.gd",
	&"b02": "res://scripts/deck_b/water_recovery.gd",
	&"b03": "res://scripts/deck_b/thermal_plant.gd",
	&"b04": "res://scripts/deck_b/workshop.gd",
	&"b05": "res://scripts/deck_b/payload_lab.gd",
	&"b06": "res://scripts/deck_b/hydroponics.gd",
	&"b07": "res://scripts/deck_b/medical_bay.gd",
	&"b08": "res://scripts/deck_b/cargo_bay.gd",
	&"b09": "res://scripts/deck_b/data_archive.gd",
}
## Room node names (unique in the scene: SaveGame keys equipment by name).
const ROOM_NODE := {&"b01": "LowerJunction", &"b02": "WaterRecovery", &"b03": "ThermalPlant", &"b04": "Workshop",
	&"b05": "PayloadLab", &"b06": "Hydroponics", &"b07": "MedicalBay", &"b08": "CargoBay", &"b09": "DataArchive"}

var shell: Node3D
var lights: Node3D
var hull: Node3D
var rooms: Node3D
var systems: Node
var shaft: Node3D
var gates: Dictionary = {}          # room -> {body, lamp}
var wall_segments: Array = []       # [{a, b, axis, at, lo, hi, top, shared}] (tests / decor)
var plate_count: int = 0
var interior_forced: bool = false   # tests / dev: keep the interior visible
var _mats: Dictionary = {}
var _poll: float = 0.0
signal built


func _ready() -> void:
	add_to_group(&"deck_b")
	shell = _child("Shell")
	lights = _child("Lights")
	hull = _child("Hull")
	rooms = _child("Rooms")
	_make_materials()
	_build_shell()
	_build_lights()
	_build_hull()
	systems = Node.new()
	systems.name = "DeckBSystems"
	systems.set_script(load("res://scripts/deck_b/deck_b_systems.gd"))
	add_child(systems)
	shaft = Node3D.new()
	shaft.name = "VerticalShaft"
	shaft.set_script(load("res://scripts/deck_b/vertical_shaft.gd"))
	add_child(shaft)
	_build_rooms()
	_build_links()
	_build_gates()
	_tag_layers(shell)
	_tag_layers(rooms)
	_isolate_deck_a_lights.call_deferred()
	_hook_clearance.call_deferred()
	_build_nodes.call_deferred()
	_dress_exterior.call_deferred()
	built.emit()


func _child(n: String) -> Node3D:
	var c := Node3D.new()
	c.name = n
	add_child(c)
	return c


# ------------------------------------------------------------- materials
func _panel_tex(base: Color, seam: Color, cell: Vector2i, rivets: bool, seed_v: int) -> ImageTexture:
	var w := 128
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for y in w:
		for x in w:
			var n: float = rng.randf_range(-0.018, 0.018)
			var c: Color = base + Color(n, n, n)
			if x % cell.x == 0 or y % cell.y == 0:
				c = seam
			elif rivets and (x % cell.x == 4 or x % cell.x == cell.x - 4) and (y % cell.y == 4 or y % cell.y == cell.y - 4):
				c = seam.lerp(base, 0.4)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _mat(key: String, base: Color, seam: Color, cell: Vector2i, rivets: bool, scale: float, metal: float = 0.25, rough: float = 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _panel_tex(base, seam, cell, rivets, hash(key))
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.metallic = metal
	m.roughness = rough
	_mats[key] = m
	return m


func _flat(key: String, c: Color, metal: float = 0.3, rough: float = 0.6, emit: Color = Color(0, 0, 0), energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


## Room identity palettes: walls / floor / ceiling.
const PALETTE := {
	"B01": [Color(0.36, 0.39, 0.43), Color(0.2, 0.21, 0.23), Color(0.3, 0.32, 0.34)],
	"SPINE": [Color(0.33, 0.35, 0.37), Color(0.19, 0.2, 0.21), Color(0.27, 0.28, 0.3)],
	"B02": [Color(0.62, 0.68, 0.72), Color(0.32, 0.35, 0.38), Color(0.55, 0.6, 0.64)],
	"B03": [Color(0.34, 0.33, 0.32), Color(0.2, 0.19, 0.18), Color(0.28, 0.27, 0.26)],
	"B04": [Color(0.5, 0.5, 0.48), Color(0.26, 0.26, 0.25), Color(0.42, 0.42, 0.41)],
	"B05": [Color(0.82, 0.84, 0.85), Color(0.62, 0.64, 0.66), Color(0.86, 0.87, 0.88)],
	"B06": [Color(0.72, 0.76, 0.7), Color(0.34, 0.37, 0.33), Color(0.7, 0.72, 0.68)],
	"B07": [Color(0.78, 0.76, 0.7), Color(0.46, 0.45, 0.42), Color(0.8, 0.79, 0.75)],
	"B08": [Color(0.44, 0.44, 0.4), Color(0.24, 0.24, 0.22), Color(0.36, 0.36, 0.34)],
	"B09": [Color(0.2, 0.23, 0.29), Color(0.13, 0.14, 0.17), Color(0.17, 0.19, 0.23)],
	"B10": [Color(0.3, 0.3, 0.3), Color(0.2, 0.2, 0.2), Color(0.25, 0.25, 0.25)],
}


func _make_materials() -> void:
	for sp in L.SPACES:
		var id: String = sp[0]
		var pal: Array = PALETTE.get(id, PALETTE["SPINE"])
		_mat("wall_" + id, pal[0], (pal[0] as Color).darkened(0.35), Vector2i(64, 32), true, 0.5)
		_mat("floor_" + id, pal[1], (pal[1] as Color).darkened(0.4), Vector2i(32, 32), true, 0.9, 0.55, 0.5)
		_mat("ceil_" + id, pal[2], (pal[2] as Color).darkened(0.3), Vector2i(64, 64), false, 0.6)
	_flat("frame", Color(0.42, 0.44, 0.46), 0.6, 0.45)
	_flat("hazard_y", Color(0.95, 0.72, 0.1), 0.1, 0.6)
	_flat("hazard_k", Color(0.07, 0.07, 0.08), 0.1, 0.6)
	_flat("rail", Color(0.62, 0.64, 0.66), 0.8, 0.3)
	_flat("pipe_blue", Color(0.25, 0.42, 0.62), 0.5, 0.4)
	_flat("pipe_red", Color(0.62, 0.26, 0.2), 0.5, 0.4)
	_flat("pipe_grey", Color(0.52, 0.53, 0.55), 0.6, 0.4)
	_flat("tray", Color(0.3, 0.31, 0.32), 0.7, 0.5)
	_flat("cable", Color(0.08, 0.08, 0.09), 0.0, 0.8)
	_flat("fixture", Color(0.95, 0.95, 0.92), 0.0, 0.4, Color(1.0, 0.97, 0.9), 1.6)
	_flat("em_strip", Color(0.25, 0.08, 0.06), 0.0, 0.5)
	_flat("sealed", Color(0.3, 0.32, 0.34), 0.7, 0.4)
	_mats["hull_grey"] = _hull_mat(Color(0.5, 0.52, 0.55), false)
	_mats["hull_white"] = _hull_mat(Color(0.86, 0.86, 0.84), true)
	_mats["metal"] = _flat("metal_x", Color(0.62, 0.64, 0.66), 0.7, 0.4)


func _hull_mat(base: Color, quilted: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _panel_tex(base, base.darkened(0.25), Vector2i(48, 48) if quilted else Vector2i(64, 32), not quilted, hash(base))
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	m.metallic = 0.2 if quilted else 0.5
	m.roughness = 0.8 if quilted else 0.5
	return m


func mat(key: String) -> StandardMaterial3D:
	return _mats.get(key, _mats["frame"])


# ----------------------------------------------------------- primitives
## A solid box: mesh + (optionally) a static collider on layer 1.
func block(parent: Node3D, size: Vector3, centre: Vector3, m: Material, collide: bool = true, layers: int = L.LAYER) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.layers = layers
	mi.position = centre
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func cyl(parent: Node3D, r: float, h: float, centre: Vector3, m: Material, rot_deg: Vector3 = Vector3.ZERO, layers: int = L.LAYER, sides: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.layers = layers
	mi.position = centre
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func sign_label(parent: Node3D, text: String, pos: Vector3, yaw_deg: float, size: int = 22, col: Color = Color(0.95, 0.95, 0.9)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0011
	l.modulate = col
	l.outline_size = 3
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = pos
	l.rotation_degrees.y = yaw_deg
	l.double_sided = false
	l.shaded = false
	l.layers = L.LAYER
	parent.add_child(l)
	return l


func _tag_layers(n: Node) -> void:
	for c in n.get_children():
		if c is VisualInstance3D and (c as VisualInstance3D).layers == 1:
			(c as VisualInstance3D).layers = L.LAYER
		_tag_layers(c)


# ----------------------------------------------------------------- shell
func _ceil(id: String) -> float:
	return float(L.space(id)[6])


func _doors_on(a: String, b: String) -> Array:
	var out: Array = []
	for i in L.DOORS.size():
		var d: Array = L.DOORS[i]
		if (d[0] == a and d[1] == b) or (d[0] == b and d[1] == a):
			out.append(i)
	return out


func _build_shell() -> void:
	var n: int = L.SPACES.size()
	# Floors and ceilings.
	for sp in L.SPACES:
		var id: String = sp[0]
		var x0: float = sp[2]
		var x1: float = sp[3]
		var z0: float = sp[4]
		var z1: float = sp[5]
		var c: float = sp[6]
		var cx: float = (x0 + x1) * 0.5
		var cz: float = (z0 + z1) * 0.5
		block(shell, Vector3(x1 - x0, L.SLAB, z1 - z0), Vector3(cx, L.FLOOR_Y - L.SLAB * 0.5, cz), mat("floor_" + id))
		block(shell, Vector3(x1 - x0, L.SLAB, z1 - z0), Vector3(cx, c + L.SLAB * 0.5, cz), mat("ceil_" + id))
	# Shared edges (built once, by the lower index).
	var shared_by: Dictionary = {}     # "i|side" -> [[lo, hi], ...]
	for i in n:
		for j in range(i + 1, n):
			var a: String = L.SPACES[i][0]
			var b: String = L.SPACES[j][0]
			var e: Dictionary = L.shared_edge(a, b)
			if e.is_empty():
				continue
			for k in [[i, a], [j, b]]:
				var key: String = "%d|%s|%.3f" % [k[0], e["axis"], float(e["at"])]
				if not shared_by.has(key):
					shared_by[key] = []
				shared_by[key].append([float(e["lo"]), float(e["hi"])])
			var top: float = maxf(_ceil(a), _ceil(b))
			var cuts: Array = []
			for di in _doors_on(a, b):
				var d: Array = L.DOORS[di]
				if d[4] == "sealed":
					_sealed_hatch(e, float(d[2]), float(d[3]), a, b)
					continue
				cuts.append([float(d[2]) - float(d[3]) * 0.5, float(d[2]) + float(d[3]) * 0.5, di])
			_wall_line(e["axis"], float(e["at"]), float(e["lo"]), float(e["hi"]), top, cuts, a, b, true)
	# Each module's own (outer) edges minus the shared intervals.
	for i in n:
		var sp: Array = L.SPACES[i]
		var id: String = sp[0]
		var edges := [["x", float(sp[2]), float(sp[4]), float(sp[5])], ["x", float(sp[3]), float(sp[4]), float(sp[5])],
			["z", float(sp[4]), float(sp[2]), float(sp[3])], ["z", float(sp[5]), float(sp[2]), float(sp[3])]]
		for e in edges:
			var key: String = "%d|%s|%.3f" % [i, e[0], e[1]]
			var segs: Array = [[float(e[2]), float(e[3])]]
			for cut in shared_by.get(key, []):
				segs = _subtract(segs, cut[0], cut[1])
			for s in segs:
				if s[1] - s[0] > 0.01:
					_wall_line(e[0], e[1], s[0], s[1], float(sp[6]), [], id, "", false)
		# Corner posts close every T-junction and corner.
		for cx in [float(sp[2]), float(sp[3])]:
			for cz in [float(sp[4]), float(sp[5])]:
				var h: float = float(sp[6]) - L.FLOOR_Y
				block(shell, Vector3(0.2, h, 0.2), Vector3(cx, L.FLOOR_Y + h * 0.5, cz), mat("wall_" + id))
		_dress_space(sp)


func _subtract(segs: Array, lo: float, hi: float) -> Array:
	var out: Array = []
	for s in segs:
		if hi <= s[0] or lo >= s[1]:
			out.append(s)
			continue
		if lo > s[0]:
			out.append([s[0], lo])
		if hi < s[1]:
			out.append([hi, s[1]])
	return out


## One wall line along an edge with doorway cuts [[lo, hi, door index]].
func _wall_line(axis: String, at: float, lo: float, hi: float, top: float, cuts: Array, a: String, b: String, shared: bool) -> void:
	var m: Material = mat("wall_" + a)
	var pieces: Array = [[lo, hi]]
	for c in cuts:
		pieces = _subtract(pieces, c[0], c[1])
	var h: float = top - L.FLOOR_Y
	for p in pieces:
		if p[1] - p[0] < 0.005:
			continue
		_wall_box(axis, at, p[0], p[1], L.FLOOR_Y, top, m)
		wall_segments.append({"a": a, "b": b, "axis": axis, "at": at, "lo": p[0], "hi": p[1], "top": top, "shared": shared})
	for c in cuts:
		# Lintel above the doorway, up to the higher ceiling.
		_wall_box(axis, at, c[0], c[1], L.FLOOR_Y + L.DOOR_H, top, m)
		_door_frame(axis, at, c[0], c[1], int(c[2]))
	if not shared:
		_hull_for(axis, at, lo, hi, top)


func _wall_box(axis: String, at: float, lo: float, hi: float, y0: float, y1: float, m: Material) -> void:
	var len: float = hi - lo
	var mid: float = (lo + hi) * 0.5
	var size: Vector3 = Vector3(L.WALL, y1 - y0, len) if axis == "x" else Vector3(len, y1 - y0, L.WALL)
	var pos: Vector3 = Vector3(at, (y0 + y1) * 0.5, mid) if axis == "x" else Vector3(mid, (y0 + y1) * 0.5, at)
	block(shell, size, pos, m)


## A framed pressure doorway: jambs + head proud of both faces, a hazard
## threshold, and the destination's sign on each side.
func _door_frame(axis: String, at: float, lo: float, hi: float, di: int) -> void:
	var d: Array = L.DOORS[di]
	var kind: String = d[4]
	var fr: Material = mat("frame")
	var depth: float = L.WALL + (0.14 if kind == "hatch" else 0.06)
	var t: float = 0.07 if kind == "hatch" else 0.05
	for edge in [lo, hi]:
		var off: float = t * 0.5 if edge == lo else -t * 0.5
		var pos := Vector3(at, L.FLOOR_Y + L.DOOR_H * 0.5, edge + off) if axis == "x" else Vector3(edge + off, L.FLOOR_Y + L.DOOR_H * 0.5, at)
		var sz := Vector3(depth, L.DOOR_H, t) if axis == "x" else Vector3(t, L.DOOR_H, depth)
		block(shell, sz, pos, fr, false)
	var mid: float = (lo + hi) * 0.5
	var head_sz := Vector3(depth, t, hi - lo) if axis == "x" else Vector3(hi - lo, t, depth)
	var head_pos := Vector3(at, L.FLOOR_Y + L.DOOR_H - t * 0.5, mid) if axis == "x" else Vector3(mid, L.FLOOR_Y + L.DOOR_H - t * 0.5, at)
	block(shell, head_sz, head_pos, fr, false)
	# Threshold: a low raised coaming with hazard stripes (no trip hazard:
	# 1.5 cm, no collision).
	var stripes: int = 6
	for k in stripes:
		var s0: float = lo + (hi - lo) * float(k) / stripes
		var s1: float = lo + (hi - lo) * float(k + 1) / stripes
		var sm: float = (s0 + s1) * 0.5
		var ssz := Vector3(0.24, 0.012, s1 - s0) if axis == "x" else Vector3(s1 - s0, 0.012, 0.24)
		var spos := Vector3(at, L.FLOOR_Y + 0.006, sm) if axis == "x" else Vector3(sm, L.FLOOR_Y + 0.006, at)
		block(shell, ssz, spos, mat("hazard_y" if k % 2 == 0 else "hazard_k"), false)
	# Signs: on each side, the room you are about to enter.
	for side in [-1.0, 1.0]:
		var p := Vector3(at + side * (depth * 0.5 + 0.01), L.FLOOR_Y + L.DOOR_H + 0.13, mid) if axis == "x" else Vector3(mid, L.FLOOR_Y + L.DOOR_H + 0.13, at + side * (depth * 0.5 + 0.01))
		var target: String = _space_beyond(axis, at, mid, -side)
		var room: StringName = L.SPACE_ROOM.get(target, &"")
		var yaw: float = (90.0 if side > 0 else -90.0) if axis == "x" else (0.0 if side > 0 else 180.0)
		var txt: String = ("%s  %s" % [_room_code(room), L.ROOMS[room][1]]) if L.ROOMS.has(room) else ""
		if txt != "":
			sign_label(shell, txt, p, yaw, 18, Color(0.95, 0.92, 0.75))


func _room_code(room: StringName) -> String:
	return "B-" + String(room).substr(1)


func _space_beyond(axis: String, at: float, along: float, side: float) -> String:
	var p := Vector2(at + side * 0.3, along) if axis == "x" else Vector2(along, at + side * 0.3)
	return L.space_at(p.x, p.y)


## A sealed bulkhead hatch drawn on a solid wall (no opening).
func _sealed_hatch(e: Dictionary, centre: float, width: float, a: String, b: String) -> void:
	var axis: String = e["axis"]
	var at: float = e["at"]
	for side in [-1.0, 1.0]:
		var face: float = at + side * (L.WALL * 0.5 + 0.02)
		var pos := Vector3(face, L.FLOOR_Y + 1.0, centre) if axis == "x" else Vector3(centre, L.FLOOR_Y + 1.0, face)
		var sz := Vector3(0.04, 1.9, width) if axis == "x" else Vector3(width, 1.9, 0.04)
		block(shell, sz, pos, mat("sealed"), false)
		var wheel := cyl(shell, 0.16, 0.05, pos + (Vector3(side * 0.04, 0.05, 0) if axis == "x" else Vector3(0, 0.05, side * 0.04)), mat("frame"), Vector3(0, 0, 90) if axis == "x" else Vector3(90, 0, 0))
		wheel.name = "SealedHatchWheel"
		var yaw: float = (90.0 if side > 0 else -90.0) if axis == "x" else (0.0 if side > 0 else 180.0)
		sign_label(shell, "B-10  SEALED\nATTITUDE CONTROL ELECTRONICS\nNO ENTRY · PRESSURE ISOLATED", pos + Vector3(0, 0.75, 0) + (Vector3(side * 0.03, 0, 0) if axis == "x" else Vector3(0, 0, side * 0.03)), yaw, 14, Color(1.0, 0.45, 0.35))


## Corridor / room dressing that does not depend on equipment.
func _dress_space(sp: Array) -> void:
	var id: String = sp[0]
	var kind: String = sp[1]
	var x0: float = sp[2]
	var x1: float = sp[3]
	var z0: float = sp[4]
	var z1: float = sp[5]
	var c: float = sp[6]
	var along_x: bool = (x1 - x0) >= (z1 - z0)
	# Light fixtures (visual; the light itself is in _build_lights).
	for p in _fixture_points(sp):
		block(shell, Vector3(0.5, 0.04, 0.18) if along_x else Vector3(0.18, 0.04, 0.5), Vector3(p.x, c - 0.02, p.y), mat("fixture"), false)
	if kind == "corridor":
		# Exposed utilities under the corridor ceiling: a cable tray, a
		# supply (blue) and a return (red) coolant line, a grey water line.
		var len: float = (x1 - x0) if along_x else (z1 - z0)
		var mid := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
		var side_off: float = ((z1 - z0) if along_x else (x1 - x0)) * 0.5 - 0.22
		var rot := Vector3(0, 0, 90) if along_x else Vector3(90, 0, 0)
		for k in 3:
			var off: float = side_off - k * 0.09
			var pos := Vector3(mid.x, c - 0.12, mid.y + off) if along_x else Vector3(mid.x + off, c - 0.12, mid.y)
			cyl(shell, 0.035, len - 0.05, pos, mat(["pipe_blue", "pipe_red", "pipe_grey"][k]), rot)
		var tpos := Vector3(mid.x, c - 0.08, mid.y - side_off + 0.1) if along_x else Vector3(mid.x - side_off + 0.1, c - 0.08, mid.y)
		block(shell, Vector3(len - 0.05, 0.05, 0.22) if along_x else Vector3(0.22, 0.05, len - 0.05), tpos, mat("tray"), false)
		block(shell, Vector3(len - 0.05, 0.03, 0.16) if along_x else Vector3(0.16, 0.03, len - 0.05), tpos + Vector3(0, 0.035, 0), mat("cable"), false)
		# Pipe brackets every metre.
		var steps: int = int(len / 1.0)
		for k in range(1, steps + 1):
			var t: float = -len * 0.5 + len * float(k) / float(steps + 1)
			var bp := Vector3(mid.x + t, c - 0.06, mid.y + side_off - 0.09) if along_x else Vector3(mid.x + side_off - 0.09, c - 0.06, mid.y + t)
			block(shell, Vector3(0.03, 0.12, 0.3) if along_x else Vector3(0.3, 0.12, 0.03), bp, mat("frame"), false)
		# Handrails along both walls (microgravity translation aids),
		# interrupted at every side doorway.
		for s in [-1.0, 1.0]:
			var w: float = ((z1 - z0) if along_x else (x1 - x0)) * 0.5 - L.WALL * 0.5 - 0.05
			var wall_at: float = (z0 if s < 0.0 else z1) if along_x else (x0 if s < 0.0 else x1)
			var lo: float = ((x0 if along_x else z0)) + 0.25
			var hi: float = ((x1 if along_x else z1)) - 0.25
			var segs: Array = [[lo, hi]]
			for di in L.DOORS.size():
				var d: Array = L.DOORS[di]
				if d[0] != id and d[1] != id:
					continue
				var e: Dictionary = L.shared_edge(d[0], d[1])
				if e.is_empty() or e["axis"] != ("z" if along_x else "x") or absf(float(e["at"]) - wall_at) > 0.01:
					continue
				segs = _subtract(segs, float(d[2]) - float(d[3]) * 0.5 - 0.12, float(d[2]) + float(d[3]) * 0.5 + 0.12)
			for sg in segs:
				var sl: float = float(sg[1]) - float(sg[0])
				if sl < 0.2:
					continue
				var sm: float = (float(sg[0]) + float(sg[1])) * 0.5
				var rp := Vector3(sm, L.FLOOR_Y + 1.05, mid.y + s * w) if along_x else Vector3(mid.x + s * w, L.FLOOR_Y + 1.05, sm)
				cyl(shell, 0.017, sl, rp, mat("rail"), rot, L.LAYER, 8)
	# Emergency light strips at floor level along the long walls (B-01's
	# emergency lighting system drives their glow).
	if id in ["B01", "SPINE", "NHALL", "NHALL2", "CARGO_C", "ARCH_A", "ARCH_B"]:
		for s in [-1.0, 1.0]:
			var w2: float = ((z1 - z0) if along_x else (x1 - x0)) * 0.5 - L.WALL * 0.5 - 0.012
			var len2: float = ((x1 - x0) if along_x else (z1 - z0)) - 0.6
			var mid2 := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var ep := Vector3(mid2.x, L.FLOOR_Y + 0.1, mid2.y + s * w2) if along_x else Vector3(mid2.x + s * w2, L.FLOOR_Y + 0.1, mid2.y)
			var strip := block(shell, Vector3(len2, 0.025, 0.012) if along_x else Vector3(0.012, 0.025, len2), ep, mat("em_strip").duplicate(), false)
			strip.name = "EmStrip_%s_%d" % [id, int(s)]
			strip.add_to_group(&"deck_b_em_strip")
			strip.set_meta(&"zone", _em_zone(id))


func _em_zone(id: String) -> int:
	match id:
		"B01", "CARGO_C":
			return 0
		"SPINE", "ARCH_A", "ARCH_B":
			return 1
	return 2


func _fixture_points(sp: Array) -> Array:
	var x0: float = sp[2]
	var x1: float = sp[3]
	var z0: float = sp[4]
	var z1: float = sp[5]
	var lx: float = x1 - x0
	var lz: float = z1 - z0
	var pts: Array = []
	if sp[1] == "corridor":
		var n: int = maxi(1, int(maxf(lx, lz) / 2.2))
		for k in n:
			var t: float = (float(k) + 0.5) / float(n)
			pts.append(Vector2(lerpf(x0, x1, t), (z0 + z1) * 0.5) if lx >= lz else Vector2((x0 + x1) * 0.5, lerpf(z0, z1, t)))
	elif sp[1] == "room":
		if maxf(lx, lz) > 3.3:
			pts.append(Vector2(x0 + lx * 0.3, z0 + lz * 0.5) if lx >= lz else Vector2(x0 + lx * 0.5, z0 + lz * 0.3))
			pts.append(Vector2(x0 + lx * 0.7, z0 + lz * 0.5) if lx >= lz else Vector2(x0 + lx * 0.5, z0 + lz * 0.7))
		else:
			pts.append(Vector2(x0 + lx * 0.5, z0 + lz * 0.5))
	return pts


# ---------------------------------------------------------------- lights
func _build_lights() -> void:
	for sp in L.SPACES:
		var id: String = sp[0]
		if sp[1] == "sealed":
			continue
		var room: StringName = L.SPACE_ROOM.get(id, &"b01")
		var info: Array = L.ROOMS[room]
		var col: Color = info[3]
		var energy: float = float(info[4]) * (0.75 if sp[1] == "corridor" else 1.0)
		var h: float = float(sp[6]) - L.FLOOR_Y
		for p in _fixture_points(sp):
			var s := SpotLight3D.new()
			s.name = "Spot_%s" % id
			s.position = Vector3(p.x, float(sp[6]) - 0.06, p.y)
			s.rotation_degrees.x = -90.0
			s.spot_angle = 68.0
			s.spot_angle_attenuation = 0.8
			s.spot_range = h + 0.6
			s.light_color = col
			s.light_energy = energy * 1.6
			s.shadow_enabled = false
			s.add_to_group(&"deck_b_light")
			s.set_meta(&"base_energy", s.light_energy)
			s.set_meta(&"zone", _em_zone(id))
			lights.add_child(s)
			# A soft fill bounce (Deck B layer only: it can never touch Deck A).
			var o := OmniLight3D.new()
			o.position = Vector3(p.x, L.FLOOR_Y + 1.2, p.y)
			o.omni_range = 2.6
			o.light_energy = energy * 0.22
			o.light_color = col
			o.light_cull_mask = L.LAYER
			o.add_to_group(&"deck_b_light")
			o.set_meta(&"base_energy", o.light_energy)
			o.set_meta(&"zone", _em_zone(id))
			lights.add_child(o)


## Deck A lights must not light Deck B through the floor (no shadows are
## cast by the interior lights): they ignore Deck B's visual layer.
func _isolate_deck_a_lights() -> void:
	var root: Node = get_parent()
	if root == null:
		return
	for l in root.find_children("*", "Light3D", true, false):
		if is_ancestor_of(l):
			continue
		if l is DirectionalLight3D:
			continue
		(l as Light3D).light_cull_mask = (l as Light3D).light_cull_mask & ~L.LAYER


# ------------------------------------------------------------------ hull
func _hull_mat_for(id: String) -> Material:
	return _mats["hull_white"] if id in ["B05", "B06", "B07", "B02"] else _mats["hull_grey"]


func _hull_for(axis: String, at: float, lo: float, hi: float, top: float) -> void:
	var mid: float = (lo + hi) * 0.5
	for sgn in [-1.0, 1.0]:
		var probe := Vector2(at + sgn * 0.3, mid) if axis == "x" else Vector2(mid, at + sgn * 0.3)
		if L.space_at(probe.x, probe.y) != "":
			continue
		var y0: float = L.FLOOR_Y - L.SLAB - 0.12
		var y1: float = top + L.SLAB + 0.12
		var off: float = sgn * (L.WALL * 0.5 + 0.06)
		var sz := Vector3(0.12, y1 - y0, hi - lo - 0.04) if axis == "x" else Vector3(hi - lo - 0.04, y1 - y0, 0.12)
		var pos := Vector3(at + off, (y0 + y1) * 0.5, mid) if axis == "x" else Vector3(mid, (y0 + y1) * 0.5, at + off)
		var here: String = L.space_at(at - sgn * 0.3, mid) if axis == "x" else L.space_at(mid, at - sgn * 0.3)
		block(hull, sz, pos, _hull_mat_for(here), false, EXTERIOR)
		plate_count += 1


func _build_hull() -> void:
	for sp in L.SPACES:
		var x0: float = sp[2]
		var x1: float = sp[3]
		var z0: float = sp[4]
		var z1: float = sp[5]
		var c: float = sp[6]
		var cx: float = (x0 + x1) * 0.5
		var cz: float = (z0 + z1) * 0.5
		block(hull, Vector3(x1 - x0 + 0.2, 0.12, z1 - z0 + 0.2), Vector3(cx, c + L.SLAB + 0.06, cz), _hull_mat_for(sp[0]), false, EXTERIOR)
		block(hull, Vector3(x1 - x0 + 0.2, 0.12, z1 - z0 + 0.2), Vector3(cx, L.FLOOR_Y - L.SLAB - 0.06, cz), _mats["hull_grey"], false, EXTERIOR)
		plate_count += 2


## Exterior dressing that needs Deck A's footprint (Exterior is ready).
func _dress_exterior() -> void:
	var ext: Node = get_tree().get_first_node_in_group(&"exterior") if is_inside_tree() else null
	var metal: Material = _mats["metal"]
	var dress := Node3D.new()
	dress.name = "HullDressing"
	hull.add_child(dress)
	# Structural connectors between the two pressure hulls, wherever a
	# Deck B roof lies under Deck A (the stacked modules are tied together).
	for sp in L.SPACES:
		var x0: float = sp[2]
		var x1: float = sp[3]
		var z0: float = sp[4]
		var z1: float = sp[5]
		var top: float = float(sp[6]) + L.SLAB + 0.12
		var x: float = x0 + 0.5
		while x < x1 - 0.3:
			var z: float = z0 + 0.5
			while z < z1 - 0.3:
				if ext != null and ext.has_method("is_interior") and ext.is_interior(x, z):
					var h: float = -0.32 - top
					if h > 0.02:
						block(dress, Vector3(0.22, h, 0.22), Vector3(x, top + h * 0.5, z), metal, false, EXTERIOR)
				z += 1.4
			x += 1.4
	# Module labels on the outer walls (read from EVA / exterior cameras).
	for sp in L.SPACES:
		if sp[1] != "room":
			continue
		var room: StringName = L.SPACE_ROOM.get(sp[0], &"")
		var lab := Label3D.new()
		lab.text = "%s  %s" % [_room_code(room), String(L.ROOMS[room][1])]
		lab.font_size = 64
		lab.pixel_size = 0.004
		lab.modulate = Color(0.12, 0.13, 0.15)
		lab.layers = EXTERIOR
		lab.shaded = true
		var x0b: float = sp[2]
		var z0b: float = sp[4]
		var outward_south: bool = L.space_at((x0b + float(sp[3])) * 0.5, z0b - 0.3) == ""
		if outward_south:
			lab.position = Vector3((x0b + float(sp[3])) * 0.5, L.FLOOR_Y + 2.2, z0b - L.WALL * 0.5 - 0.125)
			lab.rotation_degrees.y = 180.0
		else:
			lab.position = Vector3((x0b + float(sp[3])) * 0.5, L.FLOOR_Y + 2.2, float(sp[5]) + L.WALL * 0.5 + 0.125)
		dress.add_child(lab)
	# Coolant risers: Thermal Control's supply / return lines climb the hull
	# to the radiator wings on Engineering's roof (insulated, labelled).
	for k in 2:
		var px: float = -2.05 - k * 0.14
		cyl(dress, 0.05, 6.8, Vector3(px, -0.5 + 0.6, 4.05), mat("pipe_blue" if k == 0 else "pipe_red"), Vector3.ZERO, EXTERIOR)
	# Power / data conduit along the lower hull.
	cyl(dress, 0.04, 9.0, Vector3(-4.0, L.FLOOR_Y + 0.2, 2.85), metal, Vector3(0, 0, 90), EXTERIOR)
	# Cargo berthing port on B-08's west wall: a docking ring, guide petals
	# and latch housings (capped -- no vehicle berthed in normal play).
	var port := Node3D.new()
	port.name = "CargoBerthingPort"
	port.position = Vector3(-9.6 - 0.25, L.FLOOR_Y + 1.25, 7.0)
	dress.add_child(port)
	cyl(port, 0.72, 0.3, Vector3.ZERO, _mats["hull_grey"], Vector3(0, 0, 90), EXTERIOR, 24)
	cyl(port, 0.6, 0.34, Vector3.ZERO, metal, Vector3(0, 0, 90), EXTERIOR, 24)
	for k in 4:
		var ang: float = TAU * float(k) / 4.0 + PI * 0.25
		block(port, Vector3(0.12, 0.22, 0.14), Vector3(-0.12, cos(ang) * 0.78, sin(ang) * 0.78), metal, false, EXTERIOR)
	# Hull floodlights (Deck B's corners), small and warm.
	for p in [Vector3(-9.75, -1.0, 5.0), Vector3(8.15, -1.2, 7.8), Vector3(-6.3, -0.95, 15.15)]:
		var lb := block(dress, Vector3(0.08, 0.08, 0.08), p, _flat("hull_lamp", Color(1, 0.9, 0.7), 0.0, 0.5, Color(1.0, 0.85, 0.6), 3.0), false, EXTERIOR)
		lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ----------------------------------------------------------------- graph
func _build_nodes() -> void:
	var root: Node = get_parent()
	var mn: Node = root.get_node_or_null("MovementNodes") if root != null else null
	if mn == null:
		return
	var made: Dictionary = {}
	for a in L.A_NODES:
		made[a[0]] = _movement_node(mn, a[0], Vector3(a[1], 1.6, a[2]), &"", &"A")
	for b in L.NODES:
		made[b[0]] = _movement_node(mn, b[0], Vector3(b[1], L.EYE_Y, b[2]), StringName(b[4]), &"B")
	for a in L.A_NODES:
		var nd: Node = made[a[0]]
		for l in a[3]:
			nd.neighbors.append(NodePath("../" + l))
			var other: Node = mn.get_node_or_null(l)
			if other != null and not other.neighbors.has(NodePath("../" + a[0])):
				other.neighbors.append(NodePath("../" + a[0]))
	for b in L.NODES:
		var nd2: Node = made[b[0]]
		for l in b[3]:
			nd2.neighbors.append(NodePath("../" + l))
	# The shaft: a LADDER edge (climbed through vertical_shaft.gd).
	made["ShaftTop"].ladder_neighbors.append(NodePath("../BShaftBottom"))
	made["BShaftBottom"].ladder_neighbors.append(NodePath("../ShaftTop"))
	(made["ShaftTop"] as Node).neighbors.append(NodePath("../ShaftDoorEng"))


func _movement_node(parent: Node, n: String, pos: Vector3, region: StringName, deck: StringName) -> Node3D:
	var nd := Node3D.new()
	nd.set_script(MovementNodeScript)
	nd.name = n
	nd.node_id = n.to_snake_case()
	nd.region = StringName("deck_b_" + String(region)) if region != &"" else &""
	nd.deck = deck
	parent.add_child(nd)
	nd.global_position = pos
	nd.rotation.y = PI
	return nd


# ----------------------------------------------------------------- gates
func _build_gates() -> void:
	var holder := Node3D.new()
	holder.name = "Gates"
	add_child(holder)
	for g in L.GATES:
		var room: StringName = g[0]
		var di: int = g[1]
		var d: Array = L.DOORS[di]
		var e: Dictionary = L.shared_edge(d[0], d[1])
		var w: float = float(d[3])
		var body := StaticBody3D.new()
		body.name = "Gate_%s" % room
		body.collision_layer = BARRIER_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.08, 2.0, w) if e["axis"] == "x" else Vector3(w, 2.0, 0.08)
		cs.shape = bs
		body.add_child(cs)
		holder.add_child(body)
		var p: Vector3 = L.door_point(di)
		body.global_position = p + Vector3(0, 1.0, 0)
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		var lamps: Array = []
		for side in [-1.0, 1.0]:
			var off: Vector3 = Vector3(side * (L.WALL * 0.5 + 0.02), 0, 0) if e["axis"] == "x" else Vector3(0, 0, side * (L.WALL * 0.5 + 0.02))
			var lamp := block(holder, Vector3(0.05, 0.05, 0.05), p + Vector3(0, L.DOOR_H + 0.32, 0) + off + (Vector3(0, 0, w * 0.5 - 0.06) if e["axis"] == "x" else Vector3(w * 0.5 - 0.06, 0, 0)), lm, false)
			lamps.append(lamp)
		gates[room] = {"body": body, "mat": lm, "cs": cs}
	refresh_gates()


func _hook_clearance() -> void:
	var clr: Node = _clearance()
	if clr != null and clr.has_signal(&"level_changed") and not clr.level_changed.is_connected(_on_level_changed):
		clr.level_changed.connect(_on_level_changed)
	refresh_gates()


func _on_level_changed(_l: int) -> void:
	refresh_gates()


func refresh_gates() -> void:
	var clr: Node = _clearance()
	for room in gates:
		var open: bool = clr == null or clr.deck_b_room_open(room)
		var g: Dictionary = gates[room]
		(g["cs"] as CollisionShape3D).disabled = open
		var m: StandardMaterial3D = g["mat"]
		var c: Color = Color(0.25, 0.95, 0.4) if open else Color(1.0, 0.18, 0.12)
		m.albedo_color = c
		m.emission = c
		m.emission_energy_multiplier = 1.4


func _clearance() -> Node:
	return get_tree().get_first_node_in_group(&"clearance") if is_inside_tree() else null


# ----------------------------------------------------------------- rooms
func _build_rooms() -> void:
	for room in ROOM_SCRIPTS:
		if not ResourceLoader.exists(ROOM_SCRIPTS[room]):
			continue
		var n := Node3D.new()
		n.name = ROOM_NODE[room]
		n.set_script(load(ROOM_SCRIPTS[room]))
		n.set("room_id", room)
		rooms.add_child(n)


## Deck A equipment of the shared systems (Engineering): not on Deck B's
## visual layer, never hidden with Deck B's interior.
func _build_links() -> void:
	var links := Node3D.new()
	links.name = "DeckALinks"
	add_child(links)
	var n := Node3D.new()
	n.name = "EngineeringBusLink"
	n.set_script(load("res://scripts/deck_b/engineering_link.gd"))
	links.add_child(n)


func room_node(room: StringName) -> Node:
	return rooms.get_node_or_null(ROOM_NODE.get(room, "")) if rooms != null else null


# ----------------------------------------------------------- visibility
func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	_update_visibility()
	refresh_gates()


func player_on_deck_b() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam != null and L.is_lower(cam.global_position)


func interior_needed() -> bool:
	if interior_forced:
		return true
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		var p: Vector3 = cam.global_position
		if L.is_lower(p):
			return true
		if Vector2(p.x - L.SHAFT_X, p.z - L.SHAFT_Z).length() < 3.2 or Vector2(p.x - L.HOIST_X, p.z - L.HOIST_Z).length() < 2.5:
			return true
	var net: Node = get_tree().get_first_node_in_group(&"camera_network")
	if net != null and net.has_method("demanded_ids"):
		for id in net.demanded_ids():
			for c in L.CAMERAS:
				if c[0] == id:
					return true
	return false


func _update_visibility() -> void:
	var need: bool = interior_needed()
	if shell.visible != need:
		shell.visible = need
		lights.visible = need
		rooms.visible = need
