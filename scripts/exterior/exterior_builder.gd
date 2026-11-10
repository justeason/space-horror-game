extends Node3D
## Round 38 Priorities 3-4: the station's EXTERIOR, built from the real
## interior geometry so inside and outside always agree.
##   SPACE: a procedural star sphere, a planet (low orbit: a large lit limb
##     below/west), and a SUN that lights only the EXTERIOR visual layer
##     (interiors -- and breaker darkness -- are never lit by it).
##   HULL: every outer wall of every module gets a hull panel on its
##     OUTWARD side (the side whose neighbouring point is outside every
##     room / corridor footprint -- found automatically, so a panel can
##     never appear inside a room or across a corridor), plus roof plating
##     over every ceiling and an underside. Modules get a consistent
##     design language: white MLI blankets on habitation modules, grey
##     machined plating on Engineering / Airlock / Storage.
##   EQUIPMENT: radiator panels, a solar wing, a comms dish, cable trays,
##     floodlights, handrails, hazard markings.
##   EVA SERVICE AREA: the courtyard between the Control Room (east), the
##     Airlock tunnel (west) and Engineering (north): a grated deck +
##     walkway from the outer hatch to antenna mast A1, with handrails and
##     invisible TETHER boundaries (collision) so nobody can drift away.

const EXTERIOR := 1 << 11
const DECK_Y := 0.0
## Walkway / deck pieces (x0, x1, z0, z1) -- floor top at DECK_Y.
const DECK := [
	[-5.45, -3.2, -4.35, -2.72],    # outside the outer hatch
	[-4.32, -3.2, -2.72, 2.55],     # along the airlock tunnel's east side (1.1 m clear)
	[-3.6, -2.05, -0.15, 1.75],     # antenna pad
]
## Invisible tether walls (x0, x1, z0, z1) around the deck.
const BOUNDS := [
	[-5.5, -3.1, -4.45, -4.35], [-5.55, -5.45, -4.4, -2.7],
	[-3.2, -3.1, -4.4, -0.15], [-3.2, -3.1, 1.75, 2.6], [-4.3, -3.1, 2.55, 2.65],
	[-3.1, -2.0, -0.25, -0.15], [-2.05, -1.95, -0.2, 1.8], [-3.1, -2.0, 1.75, 1.85],
]
var _hull_white: StandardMaterial3D
var _hull_grey: StandardMaterial3D
var _metal: StandardMaterial3D
var _floor_rects: Array = []      # Rect2 footprints of interior spaces
var panel_count: int = 0
var sun: DirectionalLight3D
var eva_start: Vector3 = Vector3(-4.75, 1.6, -3.45)   # eye position outside the hatch


func _ready() -> void:
	add_to_group(&"exterior")
	_hull_white = _hull_mat(Color(0.86, 0.86, 0.84), true)
	_hull_grey = _hull_mat(Color(0.48, 0.5, 0.53), false)
	_metal = _m(Color(0.62, 0.64, 0.66), 0.7)
	_build_space()
	var geo: Node = get_parent().get_node_or_null("Geometry")
	if geo != null:
		_collect_footprints(geo)
		_build_hull(geo)
	_build_equipment()
	_build_eva_area()
	_build_port_exterior()
	_build_worksite()
	if geo != null:
		_dress_hull(geo)
		_finish_walls.call_deferred()


# ---------------------------------------------------------------- helpers
func _m(c: Color, metal: float = 0.3, emissive: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.55
	if emissive != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emissive
	return m


func _hull_mat(base: Color, quilted: bool) -> StandardMaterial3D:
	var w := 256
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 38 if quilted else 83
	for y in w:
		for x in w:
			var c: Color = base
			var n: float = (rng.randf() - 0.5) * 0.008
			c = Color(c.r + n, c.g + n, c.b + n)
			if x % 128 < 2 or y % 128 < 2:
				c = c.darkened(0.35)             # panel seams
			elif quilted and (x % 32 < 1 or y % 32 < 1):
				c = c.darkened(0.12)             # MLI stitching
			elif not quilted and (x % 128 == 8 or x % 128 == 120) and (y % 128 == 8 or y % 128 == 120):
				c = c.darkened(0.5)              # fasteners
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	m.roughness = 0.75 if quilted else 0.5
	m.metallic = 0.0 if quilted else 0.5
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.layers = 1 | EXTERIOR
	(parent if parent != null else self).add_child(mi)
	return mi


func _cyl(r: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.layers = 1 | EXTERIOR
	(parent if parent != null else self).add_child(mi)
	return mi


# ------------------------------------------------------------------ space
func _build_space() -> void:
	# Stars: an inside-facing sphere with a procedural star field.
	var img := Image.create(2048, 1024, false, Image.FORMAT_RGB8)
	img.fill(Color(0.004, 0.005, 0.01))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2038
	for i in 3600:
		var x: int = rng.randi() % 2048
		var y: int = rng.randi() % 1024
		var b: float = pow(rng.randf(), 3.0)
		var tint: Color = [Color(1, 1, 1), Color(0.8, 0.88, 1.0), Color(1.0, 0.92, 0.8)][rng.randi() % 3]
		img.set_pixel(x, y, tint * (0.25 + 0.75 * b))
		if b > 0.85 and x < 2047 and y < 1023:
			img.set_pixel(x + 1, y, tint * 0.4)
			img.set_pixel(x, y + 1, tint * 0.4)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = ImageTexture.create_from_image(img)
	sm.cull_mode = BaseMaterial3D.CULL_FRONT
	var stars := MeshInstance3D.new()
	stars.name = "StarSphere"
	var sph := SphereMesh.new()
	sph.radius = 1400.0
	sph.height = 2800.0
	stars.mesh = sph
	stars.material_override = sm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.layers = EXTERIOR
	add_child(stars)
	# Planet: a large sunlit body below and to the west (low orbit).
	var pimg := Image.create(1024, 512, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.006
	noise.fractal_octaves = 5
	var cloud := FastNoiseLite.new()
	cloud.seed = 11
	cloud.frequency = 0.012
	cloud.fractal_octaves = 4
	for y in 512:
		for x in 1024:
			var n: float = noise.get_noise_2d(x, y * 1.6)
			var ocean := Color(0.04, 0.12, 0.3).lerp(Color(0.07, 0.2, 0.4), clampf(n + 0.5, 0.0, 1.0))
			var land := Color(0.2, 0.28, 0.14).lerp(Color(0.45, 0.4, 0.3), clampf((n - 0.1) * 2.5, 0.0, 1.0))
			var c: Color = ocean.lerp(land, smoothstep(0.04, 0.1, n))
			var cl: float = smoothstep(0.05, 0.55, cloud.get_noise_2d(x * 1.3, y * 2.2) + 0.15)
			pimg.set_pixel(x, y, c.lerp(Color(0.93, 0.94, 0.96), cl * 0.85))
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = ImageTexture.create_from_image(pimg)
	pm.roughness = 0.9
	var planet := MeshInstance3D.new()
	planet.name = "Planet"
	var ps := SphereMesh.new()
	ps.radius = 640.0
	ps.height = 1280.0
	ps.radial_segments = 96
	ps.rings = 48
	planet.mesh = ps
	planet.material_override = pm
	planet.position = Vector3(-160.0, -720.0, 140.0)
	planet.rotation_degrees = Vector3(12, 40, 0)
	planet.layers = EXTERIOR
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(planet)
	var atmo := MeshInstance3D.new()
	var asp := SphereMesh.new()
	asp.radius = 652.0
	asp.height = 1304.0
	atmo.mesh = asp
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(0.45, 0.65, 1.0, 0.18)
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.cull_mode = BaseMaterial3D.CULL_FRONT
	atmo.material_override = am
	atmo.position = planet.position
	atmo.layers = EXTERIOR
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atmo)
	# The sun lights ONLY the exterior layer.
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.6
	sun.layers = EXTERIOR
	sun.light_cull_mask = EXTERIOR
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-38, 130, 0)
	add_child(sun)


# ------------------------------------------------------------------- hull
func _collect_footprints(geo: Node) -> void:
	for n in geo.get_children():
		# Round 40: every interior FLOOR slab -- not only names ending in
		# "Floor" ("JunctionFloorNorth" was missed, so the north Junction
		# counted as outside and got hull plating on its INNER walls).
		if n is CSGBox3D and _is_floor_slab(n):
			var b: CSGBox3D = n
			var c: Vector3 = b.global_position
			_floor_rects.append(Rect2(Vector2(c.x - b.size.x * 0.5, c.z - b.size.z * 0.5), Vector2(b.size.x, b.size.z)))


## Round 39: is (x, z) over the pressure hull's interior footprint?
func is_interior(x: float, z: float) -> bool:
	return _interior(x, z)


static func _is_floor_slab(b: CSGBox3D) -> bool:
	var nm: String = String(b.name)
	return nm.find("Floor") != -1 and nm.find("Basin") == -1 and b.size.y <= 0.3 and b.size.x > 0.8 and b.size.z > 0.8


func _interior(x: float, z: float) -> bool:
	for r in _floor_rects:
		if r.grow(0.02).has_point(Vector2(x, z)):
			return true
	return false


func _module_mat(name: String) -> StandardMaterial3D:
	for k in ["Engineering", "Airlock", "Storage", "Junction", "Tunnel", "Corridor", "Connector", "Bend"]:
		if name.find(k) != -1:
			return _hull_grey
	return _hull_white


func _build_hull(geo: Node) -> void:
	var hull := Node3D.new()
	hull.name = "Hull"
	add_child(hull)
	for n in geo.get_children():
		if not (n is CSGBox3D):
			continue
		var b: CSGBox3D = n
		var nm: String = String(b.name)
		var c: Vector3 = b.global_position
		var s: Vector3 = b.size
		if nm.ends_with("Ceiling") and s.y <= 0.3:
			_box(Vector3(s.x + 0.2, 0.12, s.z + 0.2), c + Vector3(0, s.y * 0.5 + 0.06, 0), _module_mat(nm), hull)
			panel_count += 1
			continue
		if _is_floor_slab(b):
			_box(Vector3(s.x + 0.2, 0.12, s.z + 0.2), c - Vector3(0, s.y * 0.5 + 0.06, 0), _hull_grey, hull)
			panel_count += 1
			continue
		if nm.find("Wall") == -1 or s.y < 0.8:
			continue
		# A thin wall: test both faces; plate the one that faces outside.
		var thin_x: bool = s.x <= 0.3 and s.z > s.x
		var thin_z: bool = s.z <= 0.3 and s.x > s.z
		if not (thin_x or thin_z):
			continue
		for sgn in [-1.0, 1.0]:
			var probe: Vector3 = c + (Vector3(sgn * (s.x * 0.5 + 0.3), 0, 0) if thin_x else Vector3(0, 0, sgn * (s.z * 0.5 + 0.3)))
			if _interior(probe.x, probe.z):
				continue
			var off: Vector3 = Vector3(sgn * (s.x * 0.5 + 0.06), 0, 0) if thin_x else Vector3(0, 0, sgn * (s.z * 0.5 + 0.06))
			# Round 40: exactly the wall's length (a 0.12 m overhang used to
			# poke past wall ends into doorways / tunnels: the walkway audit).
			# 2 cm short at each end: a plate end must never sit flush with a
			# neighbouring wall's inner face (coplanar faces z-fight -- a
			# flickering hull strip showed inside the Engineering tunnel).
			var sz: Vector3 = Vector3(0.12, s.y + 0.2, s.z - 0.04) if thin_x else Vector3(s.x - 0.04, s.y + 0.2, 0.12)
			_box(sz, c + off, _module_mat(nm), hull)
			panel_count += 1
			_wall_plates.append({"name": nm, "c": c + off, "size": sz, "thin_x": thin_x, "n": (Vector3(sgn, 0, 0) if thin_x else Vector3(0, 0, sgn))})


# -------------------------------------------------------------- equipment
func _build_equipment() -> void:
	var eq := Node3D.new()
	eq.name = "HullEquipment"
	add_child(eq)
	# Radiator wings on Engineering's roof (heat rejection for the power bus).
	for i in 3:
		var r := _box(Vector3(2.6, 0.04, 0.9), Vector3(-4.2, 3.75 + i * 0.02, 3.6 + i * 1.05), _m(Color(0.88, 0.89, 0.9), 0.2), eq)
		r.rotation_degrees.z = 8.0
	_box(Vector3(0.12, 0.4, 3.4), Vector3(-4.2, 3.55, 4.65), _metal, eq)
	# Solar wing on a truss east of the Living Quarters.
	var truss := Node3D.new()
	truss.position = Vector3(6.6, 1.8, 0.5)
	eq.add_child(truss)
	for k in 4:
		_box(Vector3(0.9, 0.06, 0.06), Vector3(0.45 + k * 0.9, 0.2, 0.0), _metal, truss)
		_box(Vector3(0.06, 0.4, 0.06), Vector3(0.9 * k, 0, 0.0), _metal, truss)
	var cell := _m(Color(0.08, 0.12, 0.28), 0.6)
	cell.roughness = 0.2
	for side in [-1, 1]:
		_box(Vector3(3.4, 0.03, 2.2), Vector3(2.0, 0.2, side * 1.25), cell, truss)
		_box(Vector3(3.4, 0.05, 0.05), Vector3(2.0, 0.21, side * 0.13), _metal, truss)
	# Comms dish on the Comms roof.
	var dish_root := Node3D.new()
	dish_root.position = Vector3(2.4, 3.55, 7.4)
	eq.add_child(dish_root)
	_cyl(0.05, 0.6, Vector3(0, 0.3, 0), _metal, Vector3.ZERO, dish_root)
	var dish := _cyl(0.55, 0.06, Vector3(0, 0.7, 0), _m(Color(0.9, 0.9, 0.88), 0.2), Vector3(-35, 0, 0), dish_root)
	(dish.mesh as CylinderMesh).bottom_radius = 0.2
	# Cable tray along the Control Room roof to the courtyard.
	_box(Vector3(0.18, 0.08, 3.2), Vector3(-1.2, 3.32, 0.5), _metal, eq)
	# Status / navigation lights.
	for p in [Vector3(1.6, 3.4, -1.45), Vector3(-5.45, 2.9, -2.75), Vector3(5.85, 3.1, 2.65)]:
		var l := _box(Vector3(0.08, 0.08, 0.08), p, _m(Color(1, 0.3, 0.2), 0.0, Color(1.0, 0.25, 0.2) * 3.0), eq)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --------------------------------------------------------------- EVA area
func _build_eva_area() -> void:
	var eva := Node3D.new()
	eva.name = "EvaServiceArea"
	add_child(eva)
	var grate := _m(Color(0.3, 0.32, 0.33), 0.7)
	for d in DECK:
		var size := Vector3(d[1] - d[0], 0.1, d[3] - d[2])
		var pos := Vector3((d[0] + d[1]) * 0.5, DECK_Y - 0.05, (d[2] + d[3]) * 0.5)
		_box(size, pos, grate, eva)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		body.position = pos
		eva.add_child(body)
		# Yellow/black hazard edge strips.
		_box(Vector3(size.x, 0.012, 0.06), pos + Vector3(0, 0.056, size.z * 0.5 - 0.03), _m(Color(0.9, 0.7, 0.1)), eva)
		_box(Vector3(size.x, 0.012, 0.06), pos + Vector3(0, 0.056, -size.z * 0.5 + 0.03), _m(Color(0.9, 0.7, 0.1)), eva)
	# Tether boundaries: invisible walls + visible handrails along them.
	for b in BOUNDS:
		var size := Vector3(maxf(b[1] - b[0], 0.1), 2.4, maxf(b[3] - b[2], 0.1))
		var pos := Vector3((b[0] + b[1]) * 0.5, 1.2, (b[2] + b[3]) * 0.5)
		# Round 39: no invisible walls any more -- EVA is tethered
		# free-floating (eva_system.gd); the rails are translation aids.
		var rail := _box(Vector3(size.x if size.x > 0.2 else 0.04, 0.04, size.z if size.z > 0.2 else 0.04), Vector3(pos.x, 1.0, pos.z), _m(Color(0.95, 0.75, 0.15), 0.4), eva)
		rail.name = "Handrail"
		for t in [0.0, 1.0]:
			var post: Vector3 = Vector3(lerpf(b[0], b[1], t), 0.5, lerpf(b[2], b[3], t))
			_box(Vector3(0.04, 1.0, 0.04), post, _metal, eva)
	# Floodlights at the hatch and the antenna (exterior layer only).
	for f in [[Vector3(-3.95, 2.6, -3.0), Vector3(-4.8, 0.0, -3.6)], [Vector3(-3.3, 2.7, 2.4), Vector3(-2.8, 0.3, 0.7)]]:
		var sl := SpotLight3D.new()
		sl.light_color = Color(0.95, 0.97, 1.0)
		sl.light_energy = 2.2
		sl.spot_range = 7.0
		sl.spot_angle = 55.0
		sl.light_cull_mask = EXTERIOR
		sl.shadow_enabled = false
		eva.add_child(sl)
		sl.look_at_from_position(f[0], f[1], Vector3.UP)
		var hous := _box(Vector3(0.16, 0.1, 0.12), f[0], _m(Color(0.3, 0.3, 0.32), 0.5, Color(0.9, 0.95, 1.0) * 0.6), eva)
		hous.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Round 39: the outer hatch is the REAL hinged hatch of the airlock
	# chamber (airlock_chamber.gd), seen from both sides -- no separate
	# exterior prop.


## Is a world point on the EVA deck (inside the tether limits)?
func on_deck(p: Vector3) -> bool:
	for d in DECK:
		if p.x >= d[0] - 0.05 and p.x <= d[1] + 0.05 and p.z >= d[2] - 0.05 and p.z <= d[3] + 0.05:
			return true
	return false



# ======================================================================
# Round 39 Priority 6B: the OBSERVATION PORT seen from OUTSIDE -- a real
# port in the hull where the Control Room's window is (rim, sun hood,
# dark glass with a faint warm cabin glow), so inside and outside agree.
# It sits behind the inside portal camera's near plane (never in its own
# view). Visible to EXT cameras and the technician on EVA.
# ======================================================================
var port_exterior: Node3D


func _build_port_exterior() -> void:
	var win: Node3D = get_parent().get_node_or_null("Interactables/WallWatchWindow")
	if win == null:
		return
	var c: Vector3 = win.global_position
	port_exterior = Node3D.new()
	port_exterior.name = "ObservationPortExterior"
	port_exterior.position = Vector3(-1.53, c.y, c.z)
	add_child(port_exterior)
	var rim_m := _m(Color(0.32, 0.33, 0.35), 0.7)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.34
	tm.outer_radius = 0.46
	tm.rings = 32
	ring.mesh = tm
	ring.rotation_degrees.z = 90.0
	ring.material_override = rim_m
	ring.layers = 1 | EXTERIOR
	port_exterior.add_child(ring)
	var glass := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 0.01
	cyl.radial_segments = 40
	glass.mesh = cyl
	glass.rotation_degrees.z = 90.0
	glass.position.x = -0.012          # just outside the hull plate (x -1.52)
	var gm := _m(Color(0.04, 0.06, 0.08), 0.9, Color(0.55, 0.45, 0.3) * 0.75)   # Round 40: warmer cabin glow, readable from outside
	gm.roughness = 0.04
	glass.material_override = gm
	glass.layers = 1 | EXTERIOR
	port_exterior.add_child(glass)
	# Round 40: painted surround ring (yellow) so the port reads at a glance.
	var paint := MeshInstance3D.new()
	var ptm := TorusMesh.new()
	ptm.inner_radius = 0.47
	ptm.outer_radius = 0.53
	ptm.rings = 32
	paint.mesh = ptm
	paint.rotation_degrees.z = 90.0
	paint.scale = Vector3(1.0, 0.15, 1.0)
	paint.position.x = 0.01
	paint.material_override = _m(Color(0.95, 0.75, 0.15), 0.2)
	port_exterior.add_child(paint)
	# Sun hood over the top half and bolts.
	var hood := _box(Vector3(0.18, 0.05, 1.0), Vector3(-0.08, 0.5, 0.0), rim_m, port_exterior)
	hood.rotation_degrees.z = -18.0
	for k in 12:
		var a: float = TAU * k / 12.0
		_box(Vector3(0.03, 0.03, 0.03), Vector3(-0.03, cos(a) * 0.4, sin(a) * 0.4), _m(Color(0.6, 0.6, 0.62), 0.8), port_exterior)
	var lbl := Label3D.new()
	lbl.text = "OBS PORT C-1"
	lbl.font_size = 40
	lbl.pixel_size = 0.0022
	lbl.position = Vector3(-0.03, -0.6, 0.0)
	lbl.rotation_degrees.y = -90.0
	lbl.modulate = Color(0.95, 0.85, 0.6)
	lbl.layers = 1 | EXTERIOR
	port_exterior.add_child(lbl)
	for n in port_exterior.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | EXTERIOR


# ======================================================================
# Round 39 Priority 6F: a FINISHED exterior -- painted module bands and
# large module IDs on every roof, panel seams, gold insulation blankets on
# the equipment modules, hazard chevrons around the airlock, roof vents /
# junction boxes, and the station's registry marking. Visual only.
# ======================================================================
const MODULE_PAINT := {
	"ControlRoomFloor": ["C-1", Color(0.25, 0.75, 0.9)],
	"LivingFloor": ["H-1", Color(0.95, 0.65, 0.35)],
	"EngineeringFloor": ["E-2", Color(0.95, 0.55, 0.15)],
	"LifeSupportFloor": ["L-3", Color(0.3, 0.85, 0.6)],
	"StorageFloor": ["S-4", Color(0.85, 0.85, 0.9)],
	"CommsFloor": ["M-5", Color(0.35, 0.6, 1.0)],
}
var dress_count: int = 0
var _wall_plates: Array = []      # outward hull wall plates (for the R43 finishing pass)
var finish_count: int = 0
var hull_lights: int = 0


func _dress_hull(geo: Node) -> void:
	var dress := Node3D.new()
	dress.name = "HullDress"
	add_child(dress)
	var seam := _m(Color(0.2, 0.21, 0.23), 0.4)
	var gold := _m(Color(0.85, 0.65, 0.25), 0.85)
	gold.roughness = 0.35
	var dark := _m(Color(0.25, 0.26, 0.28), 0.6)
	for fname in MODULE_PAINT:
		var f: CSGBox3D = geo.get_node_or_null(fname)
		var cl: CSGBox3D = geo.get_node_or_null(fname.replace("Floor", "Ceiling"))
		if f == null or cl == null:
			continue
		var c: Vector3 = f.global_position
		var sx: float = f.size.x + 0.2
		var sz: float = f.size.z + 0.2
		var top: float = cl.global_position.y + cl.size.y * 0.5 + 0.12
		var col: Color = MODULE_PAINT[fname][1]
		var band := _m(col.darkened(0.15), 0.2)
		# Painted band around the roof edge.
		for e in [[Vector3(0, 0, sz * 0.5 - 0.15), Vector3(sx, 0.01, 0.22)], [Vector3(0, 0, -sz * 0.5 + 0.15), Vector3(sx, 0.01, 0.22)], [Vector3(sx * 0.5 - 0.15, 0, 0), Vector3(0.22, 0.01, sz)], [Vector3(-sx * 0.5 + 0.15, 0, 0), Vector3(0.22, 0.01, sz)]]:
			_box(e[1], Vector3(c.x, top + 0.005, c.z) + e[0], band, dress)
			dress_count += 1
		# Panel seams every ~0.8 m.
		var nx: int = int(sx / 0.8)
		for i in range(1, nx):
			_box(Vector3(0.02, 0.008, sz - 0.5), Vector3(c.x - sx * 0.5 + i * sx / nx, top + 0.004, c.z), seam, dress)
			dress_count += 1
		var nz: int = int(sz / 0.8)
		for k in range(1, nz):
			_box(Vector3(sx - 0.5, 0.008, 0.02), Vector3(c.x, top + 0.004, c.z - sz * 0.5 + k * sz / nz), seam, dress)
			dress_count += 1
		# Big painted module ID on the roof.
		var lbl := Label3D.new()
		lbl.text = MODULE_PAINT[fname][0]
		lbl.font_size = 160
		lbl.pixel_size = 0.004
		lbl.modulate = col
		lbl.outline_size = 0
		lbl.position = Vector3(c.x, top + 0.012, c.z)
		lbl.rotation_degrees.x = -90.0
		lbl.layers = 1 | EXTERIOR
		dress.add_child(lbl)
		# A vent + junction box on each roof.
		_box(Vector3(0.4, 0.12, 0.25), Vector3(c.x + sx * 0.25, top + 0.06, c.z - sz * 0.25), dark, dress)
		for g in 4:
			_box(Vector3(0.36, 0.01, 0.02), Vector3(c.x + sx * 0.25, top + 0.125, c.z - sz * 0.25 - 0.09 + g * 0.06), seam, dress)
		_box(Vector3(0.2, 0.16, 0.2), Vector3(c.x - sx * 0.3, top + 0.08, c.z + sz * 0.3), _m(Color(0.75, 0.76, 0.74), 0.4), dress)
		dress_count += 3
	# Gold insulation blankets on Engineering / Comms side walls.
	for spec in [[Vector3(2.0, 1.7, 8.535), Vector3(2.2, 2.4, 0.02)], [Vector3(3.635, 1.6, 6.25), Vector3(0.02, 2.4, 0.6)], [Vector3(-2.9, 1.7, 12.235), Vector3(2.6, 2.4, 0.02)]]:
		_box(spec[1], spec[0], gold, dress)
		dress_count += 1
	# Hazard chevrons around the outer hatch, on the hull face.
	var yel := _m(Color(0.95, 0.72, 0.1), 0.2)
	var blk := _m(Color(0.08, 0.08, 0.09), 0.2)
	for k in 10:
		var bx := _box(Vector3(0.12, 0.05, 0.012), Vector3(-5.35 + k * 0.12, 2.55, -2.715), yel if k % 2 == 0 else blk, dress)
		bx.rotation_degrees.z = 35.0
		dress_count += 1
	# Registry marking along the Living Quarters' outer wall.
	var reg := Label3D.new()
	reg.text = "KESTREL-7  ·  RELAY & SURVEY STATION"
	reg.font_size = 64
	reg.pixel_size = 0.004
	reg.modulate = Color(0.25, 0.27, 0.3)
	reg.position = Vector3(5.94, 2.2, 0.5)
	reg.rotation_degrees.y = 90.0
	reg.layers = 1 | EXTERIOR
	dress.add_child(reg)
	for n in dress.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).layers = 1 | EXTERIOR
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF



# ======================================================================
# Round 40 Priority 4: a believable EVA WORK SITE at antenna A1 -- foot
# restraints on the walkway, a worklight on a post aimed at the feed box,
# a tool caddy on the handrail and a site plate. Visual only.
# ======================================================================
func _build_worksite() -> void:
	var ws := Node3D.new()
	ws.name = "WorksiteA1"
	add_child(ws)
	var yel := _m(Color(0.95, 0.72, 0.1), 0.3)
	var grey := _m(Color(0.45, 0.47, 0.5), 0.6)
	# Foot restraints (two loops) on the walkway facing the feed box.
	for dz in [-0.14, 0.14]:
		var loop := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.07
		tm.outer_radius = 0.1
		loop.mesh = tm
		loop.scale = Vector3(1.0, 1.0, 0.6)
		loop.material_override = yel
		loop.position = Vector3(-3.55, 0.03, 0.75 + dz)
		ws.add_child(loop)
	_box(Vector3(0.36, 0.02, 0.5), Vector3(-3.55, 0.01, 0.75), grey, ws)
	# Worklight on a short post, aimed at the feed box.
	_box(Vector3(0.05, 1.5, 0.05), Vector3(-3.75, 0.75, 1.25), grey, ws)
	var head := _box(Vector3(0.16, 0.1, 0.12), Vector3(-3.72, 1.52, 1.2), _m(Color(0.3, 0.3, 0.32), 0.5, Color(0.95, 0.95, 1.0) * 0.8), ws)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sl := SpotLight3D.new()
	sl.light_color = Color(0.95, 0.97, 1.0)
	sl.light_energy = 1.6
	sl.spot_range = 3.0
	sl.spot_angle = 40.0
	sl.light_cull_mask = EXTERIOR
	ws.add_child(sl)
	sl.look_at_from_position(Vector3(-3.7, 1.5, 1.18), Vector3(-3.06, 0.85, 0.75), Vector3.UP)
	# Tool caddy clipped to the walkway rail.
	_box(Vector3(0.22, 0.16, 0.12), Vector3(-3.25, 0.9, 0.2), _m(Color(0.75, 0.3, 0.12), 0.3), ws)
	_box(Vector3(0.2, 0.02, 0.02), Vector3(-3.25, 1.0, 0.2), grey, ws)
	var plate := Label3D.new()
	plate.text = "WORKSITE A1\nFEED BOX · TETHER A3"
	plate.font_size = 28
	plate.pixel_size = 0.0016
	plate.modulate = Color(0.95, 0.85, 0.4)
	plate.position = Vector3(-3.74, 1.72, 1.25)
	plate.rotation_degrees.y = -90.0
	ws.add_child(plate)
	for n in ws.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | EXTERIOR



# ======================================================================
# Round 43 Priority 18: EXTERIOR FINISHING PASS. Every outward hull wall
# plate (recorded by _build_hull, so inside and outside always agree) gets
# real spacecraft structure on top of its flat plate:
#   - STRUCTURAL RIBS (vertical frames every ~1.5 m, slightly raised);
#   - top / bottom STRINGERS (edge longerons) and a painted module BELT
#     stripe in the module's identity colour, with the module ID stencilled;
#   - SMALL HULL LIGHTS (warm, emissive) under the roof edge -- the
#     shaded side of the station is no longer a black slab;
#   - a SERVICE HATCH (outlined panel, latch, label) on longer walls;
#   - CABLE CONDUIT + brackets on the grey machinery modules;
#   - THERMAL BLANKET quilting patches (white modules) and HAZARD stencils.
# All visual only (no collision), on the exterior layer, shadows off, and
# KEPT CLEAR of the observation window, the airlock outer hatch, the
# exterior cameras and every tether anchor (KEEP_OUT radius), so nothing
# blocks a window, a camera, a ring or an EVA route.
# ======================================================================
const KEEP_OUT_R := 1.0


func _keep_outs() -> Array:
	var out: Array = []
	var root: Node = get_parent()
	for path in ["Interactables/WallWatchWindow", "AirlockChamber", "TetherAnchors"]:
		var n: Node = root.get_node_or_null(path)
		if n is Node3D:
			out.append((n as Node3D).global_position)
		if n != null:
			for c in n.get_children():
				if c is Node3D:
					out.append((c as Node3D).global_position)
	var net: Node = root.get_node_or_null("CameraNetwork")
	if net != null and "cams" in net:
		for id in net.cams:
			var cam: Node = net.cams[id].get("cam")
			if cam is Node3D and (cam as Node3D).is_inside_tree():
				out.append((cam as Node3D).global_position)
	out.append(Vector3(-4.75, 1.4, -2.75))      # outer hatch
	return out


func _clear_of(p: Vector3, keep: Array, r: float = KEEP_OUT_R) -> bool:
	for k in keep:
		if (k as Vector3).distance_to(p) < r:
			return false
	return true


func _module_paint_for(nm: String) -> Array:
	for k in [["ControlRoom", "C-1"], ["Living", "H-1"], ["Engineering", "E-2"], ["LifeSupport", "L-3"], ["Storage", "S-4"], ["Comms", "M-5"]]:
		if nm.find(k[0]) != -1:
			return [k[1], MODULE_PAINT[k[0] + "Floor"][1]]
	return ["", Color(0.6, 0.62, 0.65)]


func _finish_walls() -> void:
	var fin := Node3D.new()
	fin.name = "HullFinish"
	add_child(fin)
	var keep: Array = _keep_outs()
	var rib_m := _m(Color(0.56, 0.58, 0.61), 0.6)
	var rib_w := _m(Color(0.78, 0.78, 0.76), 0.2)
	var dark := _m(Color(0.16, 0.17, 0.19), 0.5)
	var hatch_m := _m(Color(0.68, 0.7, 0.72), 0.5)
	var lamp_m := _m(Color(1.0, 0.92, 0.75), 0.0, Color(1.0, 0.86, 0.62) * 2.2)
	var conduit_m := _m(Color(0.3, 0.32, 0.36), 0.6)
	var yel := _m(Color(0.95, 0.72, 0.1), 0.2)
	var quilt := _m(Color(0.93, 0.93, 0.9), 0.0)
	quilt.roughness = 0.9
	for wp in _wall_plates:
		var nm: String = wp["name"]
		var c: Vector3 = wp["c"]
		var sz: Vector3 = wp["size"]
		var tx: bool = wp["thin_x"]
		var n: Vector3 = wp["n"]
		var length: float = sz.z if tx else sz.x
		var h: float = sz.y
		if length < 0.7:
			continue
		var along := Vector3(0, 0, 1) if tx else Vector3(1, 0, 0)
		var face: Vector3 = c + n * 0.06
		var grey: bool = _module_mat(nm) == _hull_grey
		var paint: Array = _module_paint_for(nm)
		var col: Color = paint[1]
		var y0: float = c.y - h * 0.5
		var y1: float = c.y + h * 0.5
		var dims := func(a: float, hh: float, d: float) -> Vector3:
			return Vector3(d, hh, a) if tx else Vector3(a, hh, d)
		# Stringers along the top and bottom edges.
		_box(dims.call(length, 0.1, 0.05), Vector3(face.x, y1 - 0.08, face.z) + n * 0.025, rib_m if grey else rib_w, fin)
		_box(dims.call(length, 0.1, 0.05), Vector3(face.x, y0 + 0.1, face.z) + n * 0.025, rib_m if grey else rib_w, fin)
		finish_count += 2
		# Module belt stripe (identity colour) at 0.55 of the height.
		var belt_y: float = lerpf(y0, y1, 0.42)
		if col != Color(0.6, 0.62, 0.65):
			_box(dims.call(length - 0.1, 0.09, 0.015), Vector3(face.x, belt_y, face.z) + n * 0.008, _m(col.darkened(0.1), 0.2), fin)
			finish_count += 1
		# Structural ribs.
		var bays: int = maxi(int(round(length / 1.5)), 1)
		for i in range(0, bays + 1):
			var t: float = -length * 0.5 + length * float(i) / float(bays)
			t = clampf(t, -length * 0.5 + 0.06, length * 0.5 - 0.06)
			var rp: Vector3 = Vector3(face.x, c.y, face.z) + along * t + n * 0.03
			if not _clear_of(rp, keep, 0.7):
				continue
			_box(dims.call(0.09, h - 0.05, 0.06), rp, rib_m if grey else rib_w, fin)
			finish_count += 1
		# Bays: hull lights, quilting, hatches, conduit.
		for i in bays:
			var tm: float = -length * 0.5 + length * (float(i) + 0.5) / float(bays)
			var bay: Vector3 = Vector3(face.x, c.y, face.z) + along * tm
			if not _clear_of(bay, keep):
				continue
			# Small hull light under the roof edge (every other bay).
			if i % 2 == 0:
				_box(dims.call(0.16, 0.05, 0.05), Vector3(bay.x, y1 - 0.22, bay.z) + n * 0.03, dark, fin)
				_box(dims.call(0.12, 0.025, 0.02), Vector3(bay.x, y1 - 0.25, bay.z) + n * 0.055, lamp_m, fin)
				finish_count += 2
				# A real (exterior-layer-only) pool of light from every other
				# lamp on longer walls: the shaded hull reads as a hull.
				if i % 4 == 0 and length >= 2.0:
					var hlt := OmniLight3D.new()
					hlt.light_color = Color(1.0, 0.88, 0.7)
					hlt.light_energy = 0.9
					hlt.omni_range = 2.6
					hlt.light_cull_mask = EXTERIOR
					hlt.shadow_enabled = false
					hlt.position = Vector3(bay.x, y1 - 0.35, bay.z) + n * 0.45
					fin.add_child(hlt)
					hull_lights += 1
			if not grey and i % 2 == 1:
				# A raised thermal-blanket patch with stitching.
				var qp: Vector3 = Vector3(bay.x, lerpf(y0, y1, 0.7), bay.z) + n * 0.012
				_box(dims.call(minf(length / bays - 0.35, 1.0), 0.55, 0.02), qp, quilt, fin)
				for q in 3:
					_box(dims.call(minf(length / bays - 0.4, 0.95), 0.008, 0.024), qp + Vector3(0, -0.18 + q * 0.18, 0), _m(Color(0.75, 0.75, 0.72), 0.0), fin)
				finish_count += 4
		# One service hatch on longer walls, in the bay nearest a quarter-length.
		if length >= 2.6:
			var hp: Vector3 = Vector3(face.x, lerpf(y0, y1, 0.3), face.z) + along * (-length * 0.25) + n * 0.02
			if _clear_of(hp, keep, 1.1):
				_box(dims.call(0.62, 0.52, 0.02), hp, dark, fin)
				_box(dims.call(0.56, 0.46, 0.03), hp + n * 0.005, hatch_m, fin)
				_box(dims.call(0.14, 0.03, 0.04), hp + n * 0.02 + Vector3(0, -0.14, 0), yel, fin)
				var hl := Label3D.new()
				hl.text = "SERVICE ACCESS %s" % (paint[0] if paint[0] != "" else "")
				hl.font_size = 28
				hl.pixel_size = 0.0035
				hl.modulate = Color(0.12, 0.13, 0.15)
				hl.outline_size = 0
				hl.position = hp + n * 0.025 + Vector3(0, 0.15, 0)
				hl.rotation_degrees.y = 90.0 * n.x if tx else (0.0 if n.z > 0 else 180.0)
				hl.layers = 1 | EXTERIOR
				fin.add_child(hl)
				finish_count += 4
		# Conduit with brackets on machinery modules.
		if grey and length >= 1.5:
			var cy: float = lerpf(y0, y1, 0.62)
			var cp: Vector3 = Vector3(face.x, cy, face.z) + n * 0.09
			if _clear_of(cp, keep, 0.9):
				_cyl(0.035, length - 0.3, cp, conduit_m, Vector3(90, 0, 0) if tx else Vector3(0, 0, 90), fin)
				for b in range(0, int(length / 0.7)):
					var bp: Vector3 = cp + along * (-length * 0.5 + 0.35 + b * 0.7) - n * 0.04
					_box(dims.call(0.04, 0.09, 0.09), bp, rib_m, fin)
				finish_count += 1 + int(length / 0.7)
		# Stencilled module ID beside the belt.
		if paint[0] != "" and length >= 2.0:
			var lp: Vector3 = Vector3(face.x, belt_y + 0.32, face.z) + along * (length * 0.28) + n * 0.02
			if _clear_of(lp, keep):
				var l := Label3D.new()
				l.text = "%s" % paint[0]
				l.font_size = 120
				l.pixel_size = 0.003
				l.modulate = col.darkened(0.25)
				l.outline_size = 0
				l.position = lp
				l.rotation_degrees.y = 90.0 * n.x if tx else (0.0 if n.z > 0 else 180.0)
				l.layers = 1 | EXTERIOR
				fin.add_child(l)
				finish_count += 1
	for g in fin.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = 1 | EXTERIOR
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
