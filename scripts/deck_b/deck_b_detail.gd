extends "res://scripts/deck_b/deck_b_room.gd"
## Round 50 PRODUCTION-ART PASS on the existing lower-deck equipment (no
## new rooms, no new mechanics). Each addition attaches to its equipment
## node IN THAT NODE'S OWN FRAME, so it stays aligned with what it
## dresses; all of it is visual only (no collision, no click parts -- the
## interaction targets are untouched), on Deck B's visual layer:
##   WATER     tank end domes, support saddles + feet, inlet / outlet pipes
##             with flanges and a drain valve; filter housing clamp band,
##             pipe stubs, skid; pump motor fins, coupling guard, pipework
##   THERMAL   pump motor cooling fins, terminal box, flanged suction /
##             discharge with round pressure gauges, isolation handles
##   WORKSHOP  bench legs and drawer pulls, a bench vise, recognisable tool
##             silhouettes on the board (wrench, screwdriver, pliers,
##             hammer), parts bins, a component clamp
##   LAB       glovebox frame, glove-port rings, gloves hanging in the
##             ports, interior work light, sample rack inside
##   BOTANY    irrigation manifold + drip lines, reservoir float gauge
##   MEDICAL   exam bench restraint buckles, headrest, side rails; supply
##             cabinet handles and latch
##   CARGO     container corner fittings, ratchet straps to floor rings,
##             tie-down rings, bag net on the shelving
##   ARCHIVE   rack cable management (vertical bundles), perforated doors,
##             top exhaust grilles, a worn kick-plate

func _ready() -> void:
	_dress.call_deferred()


func _r(room: StringName) -> Node:
	var b: Node = get_parent().get_parent() if get_parent() != null else null
	return b.room_node(room) if b != null and b.has_method("room_node") else null


func _n(room: StringName, path: String) -> Node3D:
	var r: Node = _r(room)
	return r.get_node_or_null(path) as Node3D if r != null else null


func _dress() -> void:
	_water()
	_thermal()
	_workshop()
	_lab()
	_botany()
	_medical()
	_cargo()
	_archive()


func _flange(p: Node3D, pos: Vector3, r: float, rot: Vector3, col: Color = Color(0.6, 0.62, 0.64)) -> void:
	dcyl(r * 1.6, 0.025, pos, col, p, rot, 0.75)
	for k in 4:
		var a: float = TAU * k / 4.0 + 0.4
		var off: Vector3 = Vector3(cos(a), 0, sin(a)) * r * 1.35
		off = Basis.from_euler(rot * PI / 180.0) * off
		dcyl(0.007, 0.035, pos + off, Color(0.78, 0.78, 0.8), p, rot, 0.9)


func _gauge(p: Node3D, pos: Vector3, facing_rot: Vector3) -> void:
	dcyl(0.045, 0.025, pos, Color(0.2, 0.2, 0.22), p, facing_rot, 0.7)
	var face := dcyl(0.038, 0.004, pos + Basis.from_euler(facing_rot * PI / 180.0) * Vector3(0, 0.014, 0), Color(0.95, 0.95, 0.92), p, facing_rot, 0.0)
	face.name = "GaugeFace"
	var needle := dbox(Vector3(0.004, 0.03, 0.002), pos + Basis.from_euler(facing_rot * PI / 180.0) * Vector3(0, 0.018, 0), Color(0.8, 0.1, 0.1), p)
	needle.rotation_degrees = facing_rot + Vector3(0, 0, 35.0)


# ---------------------------------------------------------------- water
func _water() -> void:
	for nm in ["TankRaw", "TankPotable"]:
		var t: Node3D = _n(&"b02", nm)
		if t == null:
			continue
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.27
		sm.height = 0.22
		dome.mesh = sm
		dome.position = Vector3(0, 2.15, 0)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.8, 0.82, 0.84)
		m.metallic = 0.3
		m.roughness = 0.45
		dome.material_override = m
		dome.layers = LAYER
		t.add_child(dome)
		for y in [0.3, 1.8]:
			dcyl(0.285, 0.05, Vector3(0, y, 0), Color(0.45, 0.47, 0.5), t, Vector3.ZERO, 0.7)     # support saddles
		for k in 4:
			var a: float = TAU * k / 4.0 + PI * 0.25
			dbox(Vector3(0.05, 0.3, 0.05), Vector3(cos(a) * 0.25, 0.15, sin(a) * 0.25), Color(0.4, 0.42, 0.45), t, 0.6)
			dbox(Vector3(0.1, 0.012, 0.1), Vector3(cos(a) * 0.27, 0.006, sin(a) * 0.27), Color(0.35, 0.37, 0.4), t, 0.6)
		# Bottom outlet with a drain valve, top inlet up to the ceiling run.
		dcyl(0.022, 0.24, Vector3(0.0, 0.2, 0.37), Color(0.55, 0.57, 0.6), t, Vector3(90, 0, 0), 0.6)
		_flange(t, Vector3(0.0, 0.2, 0.27), 0.022, Vector3(90, 0, 0))
		dbox(Vector3(0.12, 0.016, 0.016), Vector3(0.0, 0.25, 0.42), Color(0.8, 0.2, 0.15), t, 0.3)
		dcyl(0.02, 0.6, Vector3(0.08, 2.5, 0.0), Color(0.55, 0.57, 0.6), t, Vector3.ZERO, 0.6)
		_flange(t, Vector3(0.08, 2.24, 0.0), 0.02, Vector3.ZERO)
	var f: Node3D = _n(&"b02", "FilterHousing")
	if f != null:
		dcyl(0.15, 0.04, Vector3(0.05, 1.05, 0), Color(0.5, 0.52, 0.55), f, Vector3.ZERO, 0.8)        # clamp band
		dbox(Vector3(0.025, 0.05, 0.03), Vector3(0.05, 1.05, 0.16), Color(0.75, 0.2, 0.15), f, 0.4)  # band latch
		for sz in [-0.18, 0.18]:
			dcyl(0.02, 0.2, Vector3(0.05, 0.85, sz * 1.0), Color(0.55, 0.57, 0.6), f, Vector3.ZERO, 0.6)
		_gauge(f, Vector3(0.14, 0.82, 0.0), Vector3(0, 0, -90))
	var p: Node3D = _n(&"b02", "PumpP201")
	if p != null:
		for k in 6:
			dbox(Vector3(0.006, 0.26, 0.2), Vector3(-0.1 + k * 0.04, 0.3, 0.12), Color(0.2, 0.36, 0.55), p, 0.5)   # motor fins
		dbox(Vector3(0.18, 0.12, 0.08), Vector3(0, 0.3, -0.02), Color(0.9, 0.72, 0.1), p, 0.3)                      # coupling guard
		_flange(p, Vector3(0, 0.3, -0.27), 0.03, Vector3(90, 0, 0))


# -------------------------------------------------------------- thermal
func _thermal() -> void:
	var r: Node = _r(&"b03")
	if r == null:
		return
	var k := 0
	for c in r.get_children():
		if not (c is Node3D) or not String(c.name).begins_with("Pump"):
			continue
		var p: Node3D = c
		for i in 7:
			dcyl(0.15, 0.012, Vector3(-0.2 + i * 0.04, 0.3, 0), Color(0.3, 0.32, 0.34), p, Vector3(0, 0, 90), 0.6)  # cooling fins
		dbox(Vector3(0.1, 0.08, 0.06), Vector3(-0.08, 0.48, 0.0), Color(0.3, 0.32, 0.34), p, 0.4)                  # terminal box
		dcyl(0.035, 0.22, Vector3(0.3, 0.3, 0), Color(0.55, 0.57, 0.6), p, Vector3(0, 0, 90), 0.6)               # discharge
		_flange(p, Vector3(0.28, 0.3, 0), 0.035, Vector3(0, 0, 90))
		_gauge(p, Vector3(0.36, 0.42, 0.0), Vector3(0, 0, -90))
		k += 1


# ------------------------------------------------------------- workshop
func _workshop() -> void:
	var b: Node3D = _n(&"b04", "Workbench")
	if b != null:
		for k in 4:
			dbox(Vector3(0.08, 0.015, 0.02), Vector3(-0.72 + k * 0.48, 0.66, -0.23), Color(0.75, 0.76, 0.78), b, 0.8)   # drawer pulls
		# Bench vise at the left end: jaws, screw, handle.
		var v := Node3D.new()
		v.name = "BenchVise"
		v.position = Vector3(-0.8, 0.93, 0.1)
		b.add_child(v)
		dbox(Vector3(0.14, 0.05, 0.1), Vector3(0, 0.0, 0), Color(0.2, 0.35, 0.55), v, 0.6)
		dbox(Vector3(0.14, 0.07, 0.02), Vector3(0, 0.06, -0.04), Color(0.25, 0.4, 0.6), v, 0.6)
		dbox(Vector3(0.14, 0.07, 0.02), Vector3(0, 0.06, 0.03), Color(0.25, 0.4, 0.6), v, 0.6)
		dcyl(0.008, 0.2, Vector3(0, 0.04, 0.12), Color(0.7, 0.7, 0.72), v, Vector3(90, 0, 0), 0.9)
		dcyl(0.006, 0.14, Vector3(0, 0.04, 0.22), Color(0.7, 0.7, 0.72), v, Vector3(0, 0, 90), 0.9)
		# Component clamp + small parts bins.
		for k in 3:
			dbox(Vector3(0.1, 0.06, 0.12), Vector3(0.45 + k * 0.12, 0.955, 0.18), [Color(0.85, 0.3, 0.15), Color(0.2, 0.45, 0.8), Color(0.95, 0.75, 0.1)][k], b, 0.1)
	var tb: Node3D = _n(&"b04", "ToolBoard")
	if tb != null:
		# Recognisable silhouettes on the board (outlines painted behind).
		var y0 := -0.2
		# open-end wrench
		dbox(Vector3(0.025, 0.2, 0.01), Vector3(0.45, y0, 0.035), Color(0.7, 0.72, 0.75), tb, 0.85)
		for sx in [-0.02, 0.02]:
			dbox(Vector3(0.012, 0.04, 0.01), Vector3(0.45 + sx, y0 + 0.11, 0.035), Color(0.7, 0.72, 0.75), tb, 0.85)
		# screwdriver
		dbox(Vector3(0.03, 0.08, 0.02), Vector3(0.55, y0 + 0.06, 0.04), Color(0.9, 0.75, 0.1), tb, 0.2)
		dcyl(0.005, 0.12, Vector3(0.55, y0 - 0.04, 0.04), Color(0.75, 0.75, 0.78), tb, Vector3.ZERO, 0.9)
		# pliers
		for sx in [-0.015, 0.015]:
			var arm := dbox(Vector3(0.012, 0.14, 0.01), Vector3(-0.5 + sx, y0, 0.035), Color(0.85, 0.2, 0.15), tb, 0.2)
			arm.rotation_degrees.z = sx * 300.0
		# hammer
		dbox(Vector3(0.02, 0.18, 0.015), Vector3(-0.6, y0, 0.035), Color(0.55, 0.4, 0.25), tb, 0.1)
		dbox(Vector3(0.08, 0.035, 0.03), Vector3(-0.6, y0 + 0.1, 0.04), Color(0.4, 0.42, 0.45), tb, 0.8)
		for x in [0.45, 0.55, -0.5, -0.6]:
			dbox(Vector3(0.06, 0.006, 0.02), Vector3(x, y0 + 0.14, 0.03), Color(0.6, 0.6, 0.62), tb, 0.8)        # hooks


# ------------------------------------------------------------------ lab
func _lab() -> void:
	var g: Node3D = _n(&"b05", "Glovebox")
	if g == null:
		return
	# Window frame round the cabinet front + gasket, a work light inside,
	# gloves hanging in the ports, a sample rack on the floor of the box.
	for e in [[Vector3(1.02, 0.03, 0.02), Vector3(0, 1.55, -0.32)], [Vector3(1.02, 0.03, 0.02), Vector3(0, 0.85, -0.32)], [Vector3(0.03, 0.72, 0.02), Vector3(-0.5, 1.2, -0.32)], [Vector3(0.03, 0.72, 0.02), Vector3(0.5, 1.2, -0.32)]]:
		dbox(e[0], e[1], Color(0.35, 0.37, 0.4), g, 0.7)
	var lamp := dbox(Vector3(0.6, 0.02, 0.06), Vector3(0, 1.53, 0.0), Color(0.95, 0.97, 1.0), g)
	glow(lamp, Color(0.9, 0.95, 1.0), 1.2)
	for s in [-0.25, 0.25]:
		dcyl(0.11, 0.02, Vector3(s, 1.15, -0.33), Color(0.75, 0.75, 0.78), g, Vector3(90, 0, 0), 0.8)   # port ring
		dcyl(0.07, 0.3, Vector3(s, 1.05, 0.0), Color(0.1, 0.1, 0.12), g, Vector3(70, 0, 0), 0.0)      # glove sleeve inside
	for k in 4:
		dcyl(0.015, 0.06, Vector3(-0.15 + k * 0.1, 0.9, 0.12), Color(0.85, 0.9, 0.95), g, Vector3.ZERO, 0.1)  # vials in rack
	dbox(Vector3(0.45, 0.02, 0.08), Vector3(0, 0.865, 0.12), Color(0.6, 0.62, 0.65), g, 0.6)


# --------------------------------------------------------------- botany
func _botany() -> void:
	var r: Node = _r(&"b06")
	if r == null:
		return
	var res: Node3D = r.get_node_or_null("Reservoir") as Node3D
	if res != null:
		dcyl(0.04, 0.012, Vector3(0.3, 0.71, -0.13), Color(0.2, 0.6, 0.9), res, Vector3(90, 0, 0))          # float gauge
		dcyl(0.012, 1.6, Vector3(0.38, 0.75, 0.0), Color(0.3, 0.6, 0.85), res, Vector3(0, 0, 90), 0.2)       # supply manifold
	for c in r.get_children():
		if c is Node3D and String(c.name).begins_with("Tray"):
			var t: Node3D = c
			dcyl(0.008, 1.0, Vector3(0, 0.82, 0.18), Color(0.25, 0.55, 0.85), t, Vector3(0, 0, 90), 0.2)    # drip line
			for k in 4:
				dcyl(0.006, 0.05, Vector3(-0.35 + k * 0.23, 0.8, 0.18), Color(0.2, 0.2, 0.22), t)          # emitters


# -------------------------------------------------------------- medical
func _medical() -> void:
	var b: Node3D = _n(&"b07", "ExamBench")
	if b != null:
		dbox(Vector3(0.3, 0.08, 0.45), Vector3(-0.6, 0.76, 0), Color(0.3, 0.5, 0.56), b, 0.0)            # headrest
		for s in [-0.29, 0.29]:
			dbox(Vector3(1.4, 0.03, 0.02), Vector3(0.0, 0.76, s), Color(0.7, 0.72, 0.75), b, 0.8)         # side rails
		for x in [-0.3, 0.45]:
			dbox(Vector3(0.06, 0.015, 0.54), Vector3(x, 0.73, 0), Color(0.15, 0.15, 0.16), b, 0.1)        # restraint straps
			dbox(Vector3(0.05, 0.02, 0.04), Vector3(x, 0.74, 0.28), Color(0.75, 0.75, 0.78), b, 0.8)      # buckles
	var c: Node3D = _n(&"b07", "SupplyCabinet")
	if c != null:
		for s in [-0.03, 0.03]:
			dbox(Vector3(0.012, 0.12, 0.02), Vector3(s, 0.0, 0.165), Color(0.75, 0.76, 0.78), c, 0.8)     # handles


# ---------------------------------------------------------------- cargo
func _cargo() -> void:
	var r: Node = _r(&"b08")
	if r == null:
		return
	for c in r.get_children():
		if c is Node3D and String(c.name).begins_with("CTB"):
			var t: Node3D = c
			for sx in [-0.37, 0.37]:
				for sz in [-0.22, 0.22]:
					dbox(Vector3(0.04, 0.04, 0.04), Vector3(sx, 0.48, sz), Color(0.55, 0.57, 0.6), t, 0.8)  # corner fittings
			for sx in [-0.25, 0.25]:
				# Ratchet strap down to a floor ring on both sides.
				dbox(Vector3(0.035, 0.5, 0.004), Vector3(sx, 0.25, 0.228), Color(0.95, 0.72, 0.1), t, 0.1)
				dbox(Vector3(0.035, 0.5, 0.004), Vector3(sx, 0.25, -0.228), Color(0.95, 0.72, 0.1), t, 0.1)
				dbox(Vector3(0.05, 0.03, 0.02), Vector3(sx, 0.3, 0.235), Color(0.6, 0.6, 0.62), t, 0.8)     # ratchet
				dcyl(0.025, 0.008, Vector3(sx, -0.04, 0.26), Color(0.6, 0.62, 0.65), t, Vector3(90, 0, 0), 0.8)  # floor ring


# -------------------------------------------------------------- archive
func _archive() -> void:
	var r: Node = _r(&"b09")
	if r == null:
		return
	for c in r.get_children():
		if c is Node3D and String(c.name).begins_with("StorageRack"):
			var rk: Node3D = c
			dcyl(0.035, 1.9, Vector3(0.27, 1.0, 0.2), Color(0.1, 0.1, 0.12), rk, Vector3.ZERO, 0.1)        # cable bundle
			for k in 8:
				dbox(Vector3(0.08, 0.012, 0.012), Vector3(0.27, 0.2 + k * 0.23, 0.2), Color(0.25, 0.25, 0.27), rk, 0.6)  # ties
			for k in 5:
				dbox(Vector3(0.5, 0.008, 0.01), Vector3(0, 2.0, -0.2 + k * 0.1), Color(0.05, 0.05, 0.06), rk)        # top grille
			dbox(Vector3(0.6, 0.08, 0.012), Vector3(0, 0.04, 0.256), Color(0.3, 0.3, 0.32), rk, 0.7)      # scuffed kick-plate
