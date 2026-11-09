extends "res://scripts/station/equipment_base.gd"
## Round 41 Priorities 3 and 5: the station's SOLAR ARRAYS and SOLAR POWER.
##
## GEOMETRY (built here, exterior layer, render-efficient): a long truss
## north of the pressurised modules (z -5.2) carries two wings, LEFT
## (x -8.7 .. -25.4) and RIGHT (x 3.3 .. 20.0), so the vehicle's span is
## ~45 m against ~13 m of modules. The truss is bolted to the hull by two
## strut pairs (Control Room and Living Quarters north faces) and carries:
##   - four longerons + battens + diagonals (MultiMesh: one draw per kind);
##   - a yellow maintenance HANDRAIL on its south (hatch) side with the
##     tether rings of eva_anchor_graph.gd (never on photovoltaic cells);
##   - a rotary joint + junction box at each wing root, a power conduit
##     to the hull, small amber service lights, markings and labels;
##   - per wing, framed panel SECTIONS (2.0 m) on both sides of the truss:
##     dark blue cells with a bus-bar grid (one shared texture), framed
##     edges, hinge brackets between sections, a tip spreader bar.
##
## POWER MODEL (lightweight, deterministic, one model -- no second power
## simulation): each wing's output = WING_KW x the faults that live in the
## three solar maintenance tasks (coupler, hinge latch, panel soiling --
## each task owns its fault, this node only multiplies them). Station load
## comes from the existing Bus A distribution panel's channel settings.
##   margin = generation - load (kW)
##   RESERVE (battery, 0..1, SAVED) charges with a surplus and drains
##   slowly with a deficit -- a lost wing takes most of a shift to matter.
## Effects: the power panel shows SOLAR / LOAD / RESERVE; Bus A voltage
## droops only when the reserve is low (< 25 %) AND there is a deficit;
## StationStatus raises an Engineering WARNING at low reserve; nothing ever
## trips or blacks out from solar alone (gradual, diagnosable).
## Derived values (output, margin) are never saved -- they rebuild from the
## tasks' saved fault state + the saved reserve.

const Graph = preload("res://scripts/exterior/eva_anchor_graph.gd")
const EXT := 1 << 11
const WING_KW := 6.0
const BASE_LOAD_KW := 5.2
const CHANNEL_KW := 0.5           # per Bus A channel step
const DRAIN_PER_KW_S := 0.0006    # reserve fraction per kW-second of deficit
const CHARGE_PER_KW_S := 0.0004
const LOW_RESERVE := 0.25
const SECTION_LEN := 2.0
const PANEL_W := 2.1              # blanket width (z) per side
const PANEL_Y := 1.12             # cell plane height (just under the truss top)

var reserve: float = 1.0          # saved (a fresh station starts fully charged)
var _tasks: Array = []            # solar task nodes (multiply faults)
var sections: Dictionary = {"L": [], "R": []}   # [Node3D] per wing (hinge task tilts one)
var _cell_mat: StandardMaterial3D
var _metal: StandardMaterial3D
var _frame_mat: StandardMaterial3D
var _readout_t: float = 0.0
var built_nodes: int = 0


func _ready() -> void:
	_base_ready(&"")
	add_to_group(&"solar_arrays")
	_metal = _m(Color(0.66, 0.68, 0.7), 0.75)
	_frame_mat = _m(Color(0.78, 0.79, 0.8), 0.6)
	_cell_mat = _cell_material()
	_build_truss()
	_build_wing("L", Graph.LEFT_WING[0], Graph.LEFT_WING[1])
	_build_wing("R", Graph.RIGHT_WING[0], Graph.RIGHT_WING[1])
	_build_roots()
	for v in find_children("*", "VisualInstance3D", true, false):
		(v as VisualInstance3D).layers = 1 | EXT
	_build_collision()
	built_nodes = find_children("*", "", true, false).size()


func register_task(t: Node) -> void:
	if not _tasks.has(t):
		_tasks.append(t)


# ---------------------------------------------------------------- model
func wing_factor(wing: String) -> float:
	var f := 1.0
	for t in _tasks:
		if t.has_method("wing_factor"):
			f *= float(t.wing_factor(wing))
	return f


func wing_output(wing: String) -> float:
	return WING_KW * wing_factor(wing)


func generation() -> float:
	return wing_output("L") + wing_output("R")


func load_kw() -> float:
	var pw: Node = get_node_or_null("../PowerDistribution")
	var steps := 6
	if pw != null:
		steps = 0
		for s in pw.setting:
			steps += int(s)
	return BASE_LOAD_KW + CHANNEL_KW * steps


func margin() -> float:
	return generation() - load_kw()


func reserve_low() -> bool:
	return reserve < LOW_RESERVE and margin() < 0.0


## Bus A droop from solar (V): only a meaningful, sustained shortfall.
func bus_droop() -> float:
	if not reserve_low():
		return 0.0
	return clampf((LOW_RESERVE - reserve) * 8.0 + 0.4, 0.4, 2.4)


func _process(delta: float) -> void:
	var m: float = margin()
	if m < 0.0:
		reserve = maxf(reserve + m * DRAIN_PER_KW_S * delta, 0.0)
	else:
		reserve = minf(reserve + m * CHARGE_PER_KW_S * delta, 1.0)


func readout() -> String:
	return "SOLAR %.1f kW (L %.1f · R %.1f) · LOAD %.1f · RES %d%%" % [generation(), wing_output("L"), wing_output("R"), load_kw(), roundi(reserve * 100.0)]


## StationStatus: a low reserve with a deficit is a WARNING in Engineering
## (only when no solar order already explains it).
func condition_duty() -> Dictionary:
	if not reserve_low():
		return {}
	return {"room": &"engineering", "tag": "SOLAR", "action": "Solar reserve low — check the arrays", "severity": 2, "id": "COND-solar"}


func state_dict() -> Dictionary:
	return {"reserve": reserve}


func load_dict(d: Dictionary) -> void:
	reserve = clampf(float(d.get("reserve", reserve)), 0.0, 1.0)


# -------------------------------------------------------------- geometry
func _m(c: Color, metal: float = 0.3, em: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.5
	if em != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = em
	return m


func _cell_material() -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for y in n:
		for x in n:
			var c := Color(0.05, 0.08, 0.2)
			var cx: int = x % 16
			var cy: int = y % 16
			if cx == 0 or cy == 0:
				c = Color(0.55, 0.57, 0.6)                  # cell gaps / bus bars
			elif cx == 8:
				c = Color(0.3, 0.33, 0.38)                  # finger bar
			else:
				var v: float = rng.randf_range(-0.012, 0.012)
				c = Color(c.r + v, c.g + v * 1.5, c.b + v * 2.0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(4, 4, 1)
	m.metallic = 0.55
	m.roughness = 0.22
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _multi(mesh: Mesh, xforms: Array, mat: Material, name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


func _label(text: String, pos: Vector3, size: int, col: Color, yaw: float = 0.0, pitch: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0025
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees = Vector3(pitch, yaw, 0)
	add_child(l)
	return l


func _build_truss() -> void:
	var x0: float = Graph.LEFT_WING[1] - 0.25
	var x1: float = Graph.RIGHT_WING[1] + 0.25
	var L: float = x1 - x0
	var cx: float = (x0 + x1) * 0.5
	var z: float = Graph.TRUSS_Z
	var y: float = Graph.TRUSS_Y
	var h := 0.17                       # half the truss section (0.34 m)
	var truss := Node3D.new()
	truss.name = "Truss"
	add_child(truss)
	# Four longerons.
	for dy in [-h, h]:
		for dz in [-h, h]:
			_box(Vector3(L, 0.05, 0.05), Vector3(cx, y + dy, z + dz), _metal, truss)
	# Battens (square frames) and diagonals every 1.0 m: MultiMesh.
	var bat := BoxMesh.new()
	bat.size = Vector3(0.035, 0.035, 2.0 * h)
	var batv := BoxMesh.new()
	batv.size = Vector3(0.035, 2.0 * h, 0.035)
	var diag := BoxMesh.new()
	diag.size = Vector3(0.025, 1.0, 0.025)      # scaled to each bay's diagonal
	var xb: Array = []
	var xv: Array = []
	var xd: Array = []
	var n: int = int(L / 1.0)
	var bay: float = L / n
	var dlen: float = sqrt(bay * bay + 4.0 * h * h)
	var ang: float = atan2(bay, 2.0 * h)
	for i in n + 1:
		var x: float = x0 + i * bay
		for dy in [-h, h]:
			xb.append(Transform3D(Basis(), Vector3(x, y + dy, z)))
		for dz in [-h, h]:
			xv.append(Transform3D(Basis(), Vector3(x, y, z + dz)))
		if i < n:
			var flip: float = 1.0 if i % 2 == 0 else -1.0
			# Side faces (x-y plane): a diagonal across each bay.
			for dz in [-h, h]:
				xd.append(Transform3D(Basis(Vector3(0, 0, 1), ang * flip) * Basis.from_scale(Vector3(1, dlen, 1)), Vector3(x + bay * 0.5, y, z + dz)))
	_multi(bat, xb, _metal, "TrussBattens")
	_multi(batv, xv, _metal, "TrussPosts")
	_multi(diag, xd, _metal, "TrussDiagonals")
	# Maintenance handrail on the south (hatch) side, with standoffs.
	var yel := _m(Color(0.95, 0.75, 0.15), 0.4)
	_box(Vector3(L - 0.6, 0.04, 0.04), Vector3(cx, Graph.RAIL_Y - 0.07, Graph.RAIL_Z), yel, truss)
	var post := BoxMesh.new()
	post.size = Vector3(0.03, Graph.RAIL_Y - 0.07 - (y + h), 0.03)
	var xp: Array = []
	var k: int = int((L - 0.6) / 1.75)
	for i in k + 1:
		var x: float = x0 + 0.3 + i * (L - 0.6) / k
		xp.append(Transform3D(Basis(), Vector3(x, (Graph.RAIL_Y - 0.07 + y + h) * 0.5, Graph.RAIL_Z)))
	_multi(post, xp, _metal, "RailStandoffs")
	# Power conduit along the truss top (north side) to the hull struts.
	var conduit := _m(Color(0.18, 0.19, 0.21), 0.3)
	_box(Vector3(L - 1.0, 0.06, 0.08), Vector3(cx, y + h + 0.05, z - 0.1), conduit, truss)
	# Hull attachment: two strut pairs to the Control Room and Living
	# Quarters north faces (real hull), with a base fitting at each end.
	for spec in [[-0.55, -1.33], [0.55, -1.33], [3.1, -1.63], [4.3, -1.63]]:
		var a := Vector3(spec[0], 1.3, spec[1])
		var b := Vector3(spec[0] * 0.92, y, z + h)
		var mid: Vector3 = (a + b) * 0.5
		var strut := _box(Vector3(0.09, 0.09, a.distance_to(b)), mid, _metal, truss)
		strut.look_at_from_position(mid, b, Vector3.UP)
		_box(Vector3(0.24, 0.24, 0.06), a - Vector3(0, 0, 0.02), _m(Color(0.4, 0.42, 0.45), 0.6), truss)
	# A truss segment label + amber service lights every ~7 m.
	_label("S0 TRUSS · KESTREL-7", Vector3(-2.6, y + h + 0.012, z), 46, Color(0.2, 0.22, 0.25), 0.0, -90.0)
	var amber := _m(Color(1.0, 0.65, 0.2), 0.0, Color(1.0, 0.6, 0.15) * 1.4)
	var lamp := SphereMesh.new()
	lamp.radius = 0.03
	lamp.height = 0.06
	var xl: Array = []
	var x := x0 + 1.0
	while x < x1 - 0.5:
		xl.append(Transform3D(Basis(), Vector3(x, y + h + 0.03, z + h)))
		x += 7.0
	var lights := _multi(lamp, xl, amber, "ServiceLights")
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_wing(wing: String, x_root: float, x_tip: float) -> void:
	var root := Node3D.new()
	root.name = "Wing" + wing
	add_child(root)
	var sgn: float = signf(x_tip - x_root)
	var length: float = absf(x_tip - x_root)
	var count: int = int(length / SECTION_LEN)
	var seg: float = length / count
	var cells := PlaneMesh.new()
	cells.size = Vector2(seg - 0.12, PANEL_W - 0.12)
	var bar_x := BoxMesh.new()
	bar_x.size = Vector3(seg, 0.035, 0.05)
	var bar_z := BoxMesh.new()
	bar_z.size = Vector3(0.05, 0.035, PANEL_W)
	var frames_x: Array = []
	var frames_z: Array = []
	var hinges: Array = []
	var z0: float = Graph.TRUSS_Z
	for i in count:
		var xc: float = x_root + sgn * (i + 0.5) * seg
		for side in [-1.0, 1.0]:
			var zc: float = z0 + side * (0.24 + PANEL_W * 0.5)
			var sec := Node3D.new()
			sec.name = "Section%d%s" % [i, "N" if side < 0 else "S"]
			# Pivot on the truss edge, so a restricted section tilts about
			# its hinge line (hinge task) instead of floating.
			sec.position = Vector3(xc, PANEL_Y, z0 + side * 0.24)
			root.add_child(sec)
			var mi := MeshInstance3D.new()
			mi.mesh = cells
			mi.material_override = _cell_mat
			mi.position = Vector3(0, 0, side * PANEL_W * 0.5)
			sec.add_child(mi)
			# Frame (two long + two short bars) as part of the section.
			for dz in [0.0, side * PANEL_W]:
				_box(Vector3(seg, 0.035, 0.05), Vector3(0, -0.005, dz), _frame_mat, sec)
			for dx in [-seg * 0.5, seg * 0.5]:
				_box(Vector3(0.05, 0.035, PANEL_W), Vector3(dx, -0.005, side * PANEL_W * 0.5), _frame_mat, sec)
			# Back stiffener.
			_box(Vector3(seg - 0.2, 0.02, 0.04), Vector3(0, -0.03, side * PANEL_W * 0.5), _frame_mat, sec)
			sections[wing].append(sec)
			# Hinge brackets on the truss edge.
			hinges.append(Transform3D(Basis(), Vector3(xc - seg * 0.3, PANEL_Y, z0 + side * 0.22)))
			hinges.append(Transform3D(Basis(), Vector3(xc + seg * 0.3, PANEL_Y, z0 + side * 0.22)))
	var hm := BoxMesh.new()
	hm.size = Vector3(0.1, 0.08, 0.1)
	_multi(hm, hinges, _m(Color(0.45, 0.47, 0.5), 0.7), "Hinges" + wing)
	# Tip spreader bar + blanket box.
	_box(Vector3(0.12, 0.12, PANEL_W * 2.0 + 0.5), Vector3(x_tip + sgn * 0.08, PANEL_Y, z0), _metal, root)
	_box(Vector3(0.3, 0.22, 0.6), Vector3(x_tip + sgn * 0.2, PANEL_Y + 0.1, z0), _m(Color(0.88, 0.86, 0.8), 0.1), root)
	# Markings on the cells near the root.
	var id_lbl := _label("SAW-%s  P%d" % [wing, 4 if wing == "L" else 2], Vector3(x_root + sgn * 1.0, PANEL_Y + 0.006, z0 + 1.5), 60, Color(0.85, 0.85, 0.82), 0.0, -90.0)
	id_lbl.pixel_size = 0.004


## Round 41: ONE static body with five boxes (truss beam + the two panel
## blankets of each wing) so a floating technician bumps into the structure
## instead of drifting through it. Cheap: no per-section bodies.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "ArrayCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var x0: float = Graph.LEFT_WING[1] - 0.25
	var x1: float = Graph.RIGHT_WING[1] + 0.25
	var shapes := [[Vector3(x1 - x0, 0.36, 0.36), Vector3((x0 + x1) * 0.5, Graph.TRUSS_Y, Graph.TRUSS_Z)]]
	for w in [Graph.LEFT_WING, Graph.RIGHT_WING]:
		for side in [-1.0, 1.0]:
			shapes.append([Vector3(absf(w[1] - w[0]), 0.06, PANEL_W), Vector3((w[0] + w[1]) * 0.5, PANEL_Y - 0.01, Graph.TRUSS_Z + side * (0.24 + PANEL_W * 0.5))])
	for sh in shapes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sh[0]
		cs.shape = bs
		cs.position = sh[1]
		body.add_child(cs)


func _build_roots() -> void:
	for wing in ["L", "R"]:
		var xr: float = Graph.LEFT_WING[0] if wing == "L" else Graph.RIGHT_WING[0]
		var sgn: float = -1.0 if wing == "L" else 1.0
		# Rotary joint (wing root) on the truss.
		var j := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.3
		cm.bottom_radius = 0.3
		cm.height = 0.35
		j.mesh = cm
		j.material_override = _m(Color(0.82, 0.83, 0.82), 0.5)
		j.rotation_degrees.z = 90.0
		j.position = Vector3(xr - sgn * 0.25, Graph.TRUSS_Y, Graph.TRUSS_Z)
		add_child(j)
		var band := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.31
		bc.bottom_radius = 0.31
		bc.height = 0.06
		band.mesh = bc
		band.material_override = _m(Color(0.85, 0.65, 0.25), 0.8)
		band.rotation_degrees.z = 90.0
		band.position = j.position
		add_child(band)
		_label("SARJ-%s" % wing, j.position + Vector3(0, 0.32, 0.0), 34, Color(0.2, 0.22, 0.25), 0.0, -90.0)
