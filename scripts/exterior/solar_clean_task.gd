extends "res://scripts/exterior/solar_task_base.gd"
## Round 41 Priority 6, TASK C -- OUTER PANEL INSPECTION / CLEANING (wing
## outer service edge, ring L5 / R5 -- the outermost rings: the worksite
## refuses unless a tether is secured THERE, so the task always uses the
## outer anchors).
## Contamination (thruster plume residue) lies on the outer panel section
## as three real film PATCHES on the cell surface, and on the lens of the
## wing-tip SUN SENSOR. Consequence while dirty: the wing gives
## (1 - 0.45 x soil) of its output, and the sun sensor under-reads (the
## array points slightly off the sun -- shown in the readings).
## Procedure: stabilise at the outer worksite -> wipe each patch -> wipe
## the sensor lens -> read the sensor (verifies the panel + sensor status)
## -> return inside (the order closes once back in the station).

const TIP := {"L": -25.2, "R": 19.8}
const RING := {"L": "L5", "R": "R5"}
const STANCE := {"L": Vector3(-23.6, 2.05, -4.35), "R": Vector3(18.2, 2.05, -4.35)}

var patches: Array = [0.0, 0.0, 0.0]    # film per patch (0 clean .. 1)
var sensor_dirty: bool = false
var sensor_read: bool = true
var _patch_nodes: Dictionary = {}       # wing -> [MeshInstance3D]
var _sensor_film: Dictionary = {}
var _sensor_lamp: Dictionary = {}
var _film_mat: StandardMaterial3D


func _ready() -> void:
	_solar_ready(&"solar_clean")
	_film_mat = StandardMaterial3D.new()
	_film_mat.albedo_color = Color(0.45, 0.36, 0.25, 0.8)
	_film_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_film_mat.albedo_texture = preload("res://scripts/exterior/camera_lens_task.gd")._grime_texture()
	_film_mat.roughness = 0.9
	for w in ["L", "R"]:
		_build(w)
	_refresh()


func _patch_positions(w: String) -> Array:
	var s: float = -1.0 if w == "L" else 1.0
	var x: float = TIP[w]
	return [Vector3(x - s * 1.6, 1.125, -4.55), Vector3(x - s * 1.0, 1.125, -4.25), Vector3(x - s * 0.45, 1.125, -4.6)]


func _build(w: String) -> void:
	var root := Node3D.new()
	root.name = "OuterSite" + w
	add_child(root)
	var nodes: Array = []
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.5, 0.36)
	var i := 0
	for p in _patch_positions(w):
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = _film_mat
		mi.position = p
		mi.rotation_degrees.y = 17.0 * i
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		part(StringName("patch%d" % i), Vector3(0.5, 0.08, 0.36), p + Vector3(0, 0.03, 0), root)
		nodes.append(mi)
		i += 1
	_patch_nodes[w] = nodes
	# Sun sensor on the truss end: a small housing + lens + status lamp.
	var sp := Vector3(TIP[w] - (-1.0 if w == "L" else 1.0) * 0.15, 1.42, -5.2)
	box(Vector3(0.14, 0.08, 0.14), sp, Color(0.85, 0.85, 0.82), root)
	var lens := CSGCylinder3D.new()
	lens.radius = 0.045
	lens.height = 0.02
	lens.position = sp + Vector3(0, 0.05, 0)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.1, 0.12, 0.2)
	lm.metallic = 0.9
	lm.roughness = 0.1
	lens.material = lm
	root.add_child(lens)
	var film := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.046
	fc.bottom_radius = 0.046
	fc.height = 0.004
	film.mesh = fc
	film.material_override = _film_mat
	film.position = sp + Vector3(0, 0.062, 0)
	root.add_child(film)
	_sensor_film[w] = film
	_sensor_lamp[w] = lamp(sp + Vector3(0.05, 0.045, 0.06), root, 0.012)
	label("SUN SNSR %s-5" % w, sp + Vector3(0, 0.043, 0.075), 18, Color(0.12, 0.12, 0.12), root).rotation_degrees.x = -90.0
	part(&"sensor", Vector3(0.18, 0.14, 0.18), sp + Vector3(0, 0.04, 0), root)
	_ext_layers(root)
	_hw[w] = root
	var hold_x: float = STANCE[w].x
	_worksite.call_deferred("outer_" + w, self, Vector3(hold_x, Graph.RAIL_Y, Graph.RAIL_Z + 0.06), STANCE[w], Vector3(TIP[w] - (-1.0 if w == "L" else 1.0) * 1.0, 1.15, -4.5), RING[w], "OUTER " + w)


func soil() -> float:
	var s := 0.0
	for p in patches:
		s += float(p)
	return s / 3.0


func wing_factor(w: String) -> float:
	return 1.0 - 0.45 * soil() if w == wing else 1.0


## Sun sensor reading (%) -- under-reads while its lens is filmed.
func sensor_reading() -> int:
	return 99 if not sensor_dirty else 71


func repaired() -> bool:
	return soil() <= 0.001 and not sensor_dirty and sensor_read


func on_part(id: StringName) -> void:
	if not at_site("outer_" + wing):
		var here_w: String = site_wing_here("outer_")
		if here_w != "" and here_w != wing:
			say("This outer panel is fine — the work order is for the %s wing (ring %s)." % [wing_word(wing), RING[wing]])
			return
		say("Grab the outer handhold first (tether on %s)." % RING[wing] if outside() else "The outer panel is at the wing tip.")
		return
	var s := String(id)
	if s.begins_with("patch"):
		var i: int = int(s.substr(5))
		if float(patches[i]) <= 0.001:
			say("That section is clean.")
			return
		patches[i] = 0.0
		sfx(&"scrub")
		var left: int = patches.filter(func(p): return float(p) > 0.001).size()
		say("Film wiped." + ("" if left == 0 else " %d left." % left))
	elif id == &"sensor":
		if sensor_dirty:
			sensor_dirty = false
			sensor_read = false
			sfx(&"scrub")
			say("Sensor lens wiped — read it.")
		else:
			sensor_read = true
			sfx(&"success" if soil() <= 0.001 else &"click")
			say("SUN SENSOR %s-5: %d %%%s" % [wing, sensor_reading(), "" if soil() <= 0.001 else " — panel film remains"])
	_refresh()


func part_prompt(id: StringName) -> String:
	if not outside():
		return ""
	if not at_site("outer_" + wing):
		return "Grab the handhold to work"
	var s := String(id)
	if s.begins_with("patch"):
		return "Click: wipe the panel film" if float(patches[int(s.substr(5))]) > 0.001 else ""
	if id == &"sensor":
		return "Click: wipe the sensor lens" if sensor_dirty else "Click: read the sun sensor"
	return ""


func _refresh() -> void:
	for w in ["L", "R"]:
		var nodes: Array = _patch_nodes.get(w, [])
		for i in nodes.size():
			(nodes[i] as Node3D).visible = w == wing and float(patches[i]) > 0.001
		if _sensor_film.has(w):
			(_sensor_film[w] as Node3D).visible = w == wing and sensor_dirty
			set_lamp(_sensor_lamp[w], Color(1.0, 0.6, 0.15) if (w == wing and (sensor_dirty or soil() > 0.0)) else Color(0.3, 0.9, 0.4), true)


func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	wing = ["L", "R"][rng.randi() % 2]
	var level: float = 0.6 + 0.1 * float(rng.randi() % 4)
	patches = [level, level, level]
	sensor_dirty = true
	sensor_read = false
	request_day = _today()
	verified_day = -1
	_refresh()


func order_done() -> bool:
	return request_day != -1 and repaired() and not outside()


func order_next() -> Dictionary:
	if repaired():
		return {"action": "Return along the truss, press IN>>", "short": "AIRLOCK IN", "room": &"airlock"}
	var step: Dictionary
	if not at_site("outer_" + wing):
		step = {"action": "Out to %s (outer edge), grab the handhold" % RING[wing], "short": "TO OUTER %s" % wing, "room": &"airlock"}
	elif soil() > 0.001:
		step = {"action": "Wipe the film off the outer panel", "short": "WIPE PANEL", "room": &"airlock"}
	elif sensor_dirty:
		step = {"action": "Wipe the sun sensor lens", "short": "WIPE SENSOR", "room": &"airlock"}
	else:
		step = {"action": "Read the sun sensor", "short": "READ SENSOR", "room": &"airlock"}
	return _route_step(step, RING[wing])


func order_progress() -> String:
	return "%d%%" % roundi((1.0 - soil()) * 100.0)


func order_detail() -> Array:
	return ["Outer panel + sun sensor, wing %s tip (truss ring %s)." % [wing, RING[wing]], "Panel film %d %% · sun sensor %d %%." % [roundi(soil() * 100.0), sensor_reading()]]


func state_dict() -> Dictionary:
	return {"wing": wing, "patches": patches.duplicate(), "sensor_dirty": sensor_dirty, "sensor_read": sensor_read, "request_day": request_day, "verified_day": verified_day}


func load_dict(d: Dictionary) -> void:
	wing = String(d.get("wing", "L"))
	patches = Array(d.get("patches", [0.0, 0.0, 0.0])).duplicate()
	sensor_dirty = bool(d.get("sensor_dirty", false))
	sensor_read = bool(d.get("sensor_read", true))
	request_day = int(d.get("request_day", -1))
	verified_day = int(d.get("verified_day", -1))
	_refresh()
