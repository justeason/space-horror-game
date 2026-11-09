extends Node3D
## Round 39 Priority 6E: a REAL two-hatch airlock. The south end of the
## airlock tunnel (z -0.5 .. -2.5) is the CHAMBER, closed by a hinged INNER
## HATCH (station side, z -0.4) and the hinged OUTER HATCH (hull, z -2.6).
##
##   EXIT:  enter the chamber -> close inner hatch -> depressurize
##          (14.7 -> 0 psi) -> open outer hatch -> out to EVA.
##   ENTER: back into the chamber -> close outer hatch -> repressurize
##          (0 -> 14.7 psi) -> open inner hatch -> back in the station.
##
## One click on a panel runs the whole sequence ("EXIT" / "ENTER"); every
## step is VISIBLE (the hatches swing, the pressure readout falls / rises,
## the chamber light goes green -> amber -> red) and each step re-checks
## its interlocks:
##   - never both hatches open; a hatch only opens at matching pressure
##     (inner: >= 14.5 psi; outer: <= 0.2 psi);
##   - no depressurizing with an unsuited person in the chamber;
##   - a hatch never closes on someone standing in its doorway (the
##     sequence waits: "Clear the hatch");
##   - cargo transfer / seal inspection must not be in progress.
## Panels: STATION (tunnel, by the inner hatch: brings the chamber to
## station pressure and opens the inner hatch), CHAMBER (EXIT / ENTER),
## OUTSIDE (on the hull beside the outer hatch: opens it, cycling the
## chamber down first if needed -- the technician is never locked out).
## The suit itself runs at 4.3 psi pure O2 (shown on the visor).
## Not saved: a load always starts with the chamber pressurized, inner
## hatch open, outer closed (saving is refused during EVA / cycling).

const STATION_PSI := 14.7
const SUIT_PSI := 4.3
const CYCLE_S := 4.0
const DOOR_S := 1.1
const X_LO := -5.2
const X_HI := -4.4
const Z_INNER := -0.4
const Z_OUTER := -2.6
const DOOR_W := 0.7
const DOOR_H := 2.18

var inner_open: bool = true
var outer_open: bool = false
var psi: float = STATION_PSI
var sequence: String = ""          # "" | "out" | "in"
var step: String = ""              # current step, shown on the panels
var waiting: String = ""           # why the sequence is paused ("" = not)
var events: Array = []             # [{event, t}]
signal state_changed()
signal sequence_finished(kind: String)

var _inner_door: Node3D
var _outer_door: Node3D
var _inner_k: float = 1.0          # 0 closed .. 1 open (animated)
var _outer_k: float = 0.0
var _light: OmniLight3D
var _beacon_mat: StandardMaterial3D
var _screens: Array = []           # Label3D
var _big: Label3D
var _t: float = 0.0
var _step_t: float = 0.0


func _ready() -> void:
	add_to_group(&"airlock")
	_build_inner_bulkhead()
	_build_outer_bulkhead()
	_build_panels()
	_build_console()
	_light = OmniLight3D.new()
	_light.position = Vector3(-4.8, 2.3, -1.5)
	_light.omni_range = 2.6
	_light.light_energy = 0.9
	add_child(_light)
	_big = Label3D.new()
	_big.position = Vector3(-4.415, 2.2, -1.62)
	_big.rotation_degrees.y = -90.0
	_big.font_size = 40
	_big.pixel_size = 0.0012
	_big.outline_size = 8
	add_child(_big)
	_apply_doors()
	_refresh()


# ------------------------------------------------------------- geometry
func _mat(c: Color, metal: float = 0.5, em: Color = Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.5
	if em != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = em
	return m


func _csg(size: Vector3, pos: Vector3, mat: Material, parent: Node3D, collide: bool = true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	b.use_collision = collide
	parent.add_child(b)
	return b


func _label(text: String, pos: Vector3, yaw: float, size: int, col: Color, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees.y = yaw
	l.font_size = size
	l.pixel_size = 0.001
	l.modulate = col
	l.outline_size = 5
	parent.add_child(l)
	return l


## A bulkhead across the 1.0 m tunnel with a 0.7 x 2.05 m doorway.
func _bulkhead(name: String, z: float, thick: float, frame_col: Color) -> Node3D:
	var root := Node3D.new()
	root.name = name
	add_child(root)
	var fm := _mat(frame_col, 0.6)
	var x0: float = -5.4
	var x1: float = -4.2
	var dl: float = -4.8 - DOOR_W * 0.5
	var dr: float = -4.8 + DOOR_W * 0.5
	_csg(Vector3(dl - x0, 2.8, thick), Vector3((x0 + dl) * 0.5, 1.3, z), fm, root)
	_csg(Vector3(x1 - dr, 2.8, thick), Vector3((dr + x1) * 0.5, 1.3, z), fm, root)
	_csg(Vector3(DOOR_W, 2.8 - DOOR_H, thick), Vector3(-4.8, DOOR_H + (2.8 - DOOR_H) * 0.5, z), fm, root)
	# Flush sill under the doorway (no gap to the void below an open hatch).
	_csg(Vector3(1.2, 0.2, thick + 0.12), Vector3(-4.8, -0.1, z), _mat(Color(0.22, 0.23, 0.25), 0.6), root)
	# Hazard-striped jamb edges (yellow / dark), both faces.
	var yel := _mat(Color(0.95, 0.72, 0.1), 0.2)
	var blk := _mat(Color(0.08, 0.08, 0.09), 0.2)
	for side in [-1.0, 1.0]:
		var xe: float = -4.8 + side * (DOOR_W * 0.5 + 0.025)
		for k in 8:
			_csg(Vector3(0.05, DOOR_H / 8.0, thick + 0.02), Vector3(xe, (k + 0.5) * DOOR_H / 8.0, z), yel if k % 2 == 0 else blk, root, false)
	_csg(Vector3(DOOR_W + 0.1, 0.05, thick + 0.02), Vector3(-4.8, DOOR_H + 0.025, z), yel, root, false)
	return root


## A hinged hatch leaf (StaticBody: it blocks the doorway when shut).
func _door(name: String, hinge: Vector3, extend_sign: float, face_col: Color, porthole: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = name
	pivot.position = hinge
	add_child(pivot)
	var body := StaticBody3D.new()
	body.name = "Leaf"
	pivot.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(DOOR_W - 0.02, DOOR_H - 0.04, 0.07)
	cs.shape = bs
	cs.position = Vector3(extend_sign * (DOOR_W * 0.5), DOOR_H * 0.5, 0)
	body.add_child(cs)
	var leaf := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	leaf.mesh = bm
	leaf.material_override = _mat(face_col, 0.55)
	leaf.position = cs.position
	body.add_child(leaf)
	var c: Vector3 = cs.position
	# Raised rim, dogging wheel and (inner hatch) a small porthole.
	for zf in [-1.0, 1.0]:
		var rim := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(DOOR_W - 0.12, DOOR_H - 0.16, 0.012)
		rim.mesh = rm
		rim.material_override = _mat(face_col.darkened(0.25), 0.6)
		rim.position = c + Vector3(0, 0, zf * 0.04)
		body.add_child(rim)
		var wheel := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.1
		tm.outer_radius = 0.13
		wheel.mesh = tm
		wheel.rotation_degrees.x = 90.0
		wheel.material_override = _mat(Color(0.75, 0.76, 0.78), 0.8)
		wheel.position = c + Vector3(0, -0.15, zf * 0.065)
		body.add_child(wheel)
		if porthole:
			var glass := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.09
			cyl.bottom_radius = 0.09
			cyl.height = 0.08
			glass.mesh = cyl
			glass.rotation_degrees.x = 90.0
			var gm := _mat(Color(0.1, 0.16, 0.2), 0.9)
			gm.roughness = 0.05
			glass.material_override = gm
			glass.position = c + Vector3(0, 0.5, 0)
			body.add_child(glass)
	return pivot


func _build_inner_bulkhead() -> void:
	_bulkhead("InnerBulkhead", Z_INNER, 0.16, Color(0.3, 0.32, 0.35))
	# Hinge on the west jamb; opens INTO the chamber (towards -z).
	_inner_door = _door("InnerHatch", Vector3(-4.8 - DOOR_W * 0.5, 0.0, Z_INNER), 1.0, Color(0.42, 0.45, 0.48), true)
	var beacon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	beacon.mesh = sm
	_beacon_mat = _mat(Color(0.3, 0.9, 0.4), 0.0, Color(0.3, 0.9, 0.4))
	beacon.material_override = _beacon_mat
	beacon.position = Vector3(-4.8, 2.2, Z_INNER + 0.1)
	add_child(beacon)
	_label("AIRLOCK CHAMBER", Vector3(-4.8, 2.35, Z_INNER + 0.085), 0.0, 22, Color(0.95, 0.85, 0.5), self)


func _build_outer_bulkhead() -> void:
	_bulkhead("OuterBulkhead", Z_OUTER, 0.2, Color(0.28, 0.29, 0.31))
	# Hinge on the east jamb; opens OUTWARD (towards -z, onto the hull).
	_outer_door = _door("OuterHatch", Vector3(-4.8 + DOOR_W * 0.5, 0.0, Z_OUTER), -1.0, Color(0.72, 0.18, 0.14), false)
	_label("OUTER HATCH", Vector3(-4.8, 2.35, Z_OUTER + 0.105), 0.0, 20, Color(0.95, 0.6, 0.5), self)
	var outside := _label("AIRLOCK A-1  ·  EVA EXIT", Vector3(-4.8, 2.35, Z_OUTER - 0.105), 180.0, 20, Color(0.95, 0.85, 0.5), self)
	outside.layers = 1 | (1 << 11)


## Panels: [id, position, yaw, title].
const PANELS := [
	[&"station", Vector3(-4.415, 1.35, -0.1), -90.0, "AIRLOCK"],
	[&"chamber", Vector3(-4.415, 1.35, -1.35), -90.0, "CHAMBER"],
	[&"outside", Vector3(-3.95, 1.3, -2.81), 180.0, "AIRLOCK A-1"],
]


func _build_panels() -> void:
	for p in PANELS:
		var root := Node3D.new()
		root.name = "Panel_%s" % String(p[0])
		root.position = p[1]
		root.rotation_degrees.y = p[2]
		add_child(root)
		var back := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.34, 0.42, 0.05)
		back.mesh = bm
		back.material_override = _mat(Color(0.18, 0.2, 0.22), 0.5)
		back.position.z = -0.02
		root.add_child(back)
		var bar := MeshInstance3D.new()
		var brm := BoxMesh.new()
		brm.size = Vector3(0.36, 0.035, 0.07)
		bar.mesh = brm
		bar.material_override = _mat(Color(0.95, 0.72, 0.1), 0.2)
		bar.position = Vector3(0, 0.22, -0.01)
		root.add_child(bar)
		_label(String(p[3]), Vector3(0, 0.17, 0.006), 0.0, 14, Color(0.95, 0.9, 0.8), root)
		var scr := _label("", Vector3(0, 0.05, 0.006), 0.0, 13, Color(0.55, 0.95, 0.75), root)
		_screens.append(scr)
		if p[0] == &"chamber":
			_button(root, &"exit", Vector3(-0.08, -0.12, 0.0), "OUT >>", Color(0.75, 0.2, 0.15))
			_button(root, &"enter", Vector3(0.08, -0.12, 0.0), "<< IN", Color(0.2, 0.55, 0.3))
		else:
			_button(root, p[0], Vector3(0, -0.12, 0.0), "OPEN" if p[0] == &"outside" else "CYCLE", Color(0.75, 0.2, 0.15) if p[0] == &"outside" else Color(0.2, 0.55, 0.3))
		if p[0] == &"outside":
			for v in root.find_children("*", "VisualInstance3D", true, false):
				(v as VisualInstance3D).layers = 1 | (1 << 11)


func _button(root: Node3D, id: StringName, pos: Vector3, text: String, col: Color) -> void:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.13, 0.07, 0.03)
	b.mesh = bm
	b.material_override = _mat(col, 0.2, col * 0.4)
	b.position = pos + Vector3(0, 0, 0.01)
	root.add_child(b)
	_label(text, pos + Vector3(0, 0, 0.03), 0.0, 11, Color(1, 1, 1), root)
	preload("res://scripts/interactables/click_part.gd").make(self, id, Vector3(0.14, 0.08, 0.06), root, pos + Vector3(0, 0, 0.02))


# ---------------------------------------------------------- interaction
func on_part(id: StringName) -> void:
	match id:
		&"exit":
			begin_cycle_out()
		&"enter", &"station":
			begin_cycle_in()
		&"outside":
			begin_open_from_outside()


func part_prompt(id: StringName) -> String:
	if sequence != "":
		return waiting if waiting != "" else "Cycling: %s" % step
	match id:
		&"exit":
			var why: String = exit_blocker()
			return "Click: OUT — seal inner, vent, open outer" if why == "" else "OUT: %s" % why
		&"enter":
			return "Click: IN — seal outer, pressurize, open inner" if not (inner_open and psi >= 14.5) else ""
		&"station":
			return "Click: open the inner hatch" if not inner_open else ""
		&"outside":
			return "Click: open the outer hatch" if not outer_open else ""
	return ""


func _ai(key: StringName) -> void:
	for a in get_tree().get_nodes_in_group(&"station_ai"):
		a.event(key)


func _say(text: String, s: float = 3.0) -> void:
	var ml: Label = get_node_or_null(^"../Player/HUD/TaskMessageLabel") as Label
	preload("res://scripts/ui/hud_message.gd").show(ml, get_instance_id(), text, s)


func _sfx(kind: StringName) -> void:
	var s: Node = get_node_or_null(^"../Player/HUD/MechanicalSfx")
	if s != null and s.has_method("play_kind"):
		s.play_kind(kind)


# --------------------------------------------------------------- queries
func _eye() -> Vector3:
	var fb: Node3D = get_node_or_null(^"../FreeMoveBody")
	return fb.global_position if fb != null else Vector3.INF


static func in_chamber(p: Vector3) -> bool:
	return p.x > X_LO and p.x < X_HI and p.z < Z_INNER - 0.08 and p.z > Z_OUTER + 0.1


## Something stands in the doorway of the hatch at `z`.
func _doorway_blocked(z: float) -> bool:
	var p: Vector3 = _eye()
	return absf(p.z - z) < 0.42 and p.x > -5.3 and p.x < -4.3


func _suited() -> bool:
	var eva: Node = get_tree().get_first_node_in_group(&"eva_system")
	return eva != null and eva.suited


func exit_blocker() -> String:
	if sequence != "":
		return "cycle in progress"
	if not _suited():
		return "suit required"
	var port: Node = get_node_or_null(^"../Interactables/CargoPort")
	if port != null and "state" in port and port.state != port.PortState.SECURED:
		return "cargo transfer in progress"
	var hs: Node = get_node_or_null(^"../Equipment/HatchSeal")
	if hs != null and (hs.inspection_mode or hs.test_state == "running"):
		return "hatch seal inspection / test in progress"
	if not in_chamber(_eye()):
		return "step into the chamber first"
	return ""


func is_pressurized() -> bool:
	return psi >= 14.5


func is_vacuum() -> bool:
	return psi <= 0.2


func is_default_state() -> bool:
	return sequence == "" and inner_open and not outer_open and is_pressurized()


## Invariant (tests): never both hatches open; each open hatch at the
## pressure on its other side.
func is_safe_state() -> bool:
	if inner_open and outer_open:
		return false
	if outer_open and not is_vacuum():
		return false
	if inner_open and not is_pressurized():
		return false
	return true


# -------------------------------------------------------------- sequences
func begin_cycle_out() -> bool:
	var why: String = exit_blocker()
	if why != "":
		_say("Airlock: %s." % why)
		_sfx(&"fail")
		_ai(&"eva_interlock")
		return false
	_start("out", ["close_inner", "depressurize", "open_outer"])
	_ai(&"airlock_cycle_out")
	return true


func begin_cycle_in() -> bool:
	if sequence != "":
		return false
	if inner_open and is_pressurized():
		return false
	var steps: Array = []
	if outer_open:
		steps.append("close_outer")
	if not is_pressurized():
		steps.append("repressurize")
	steps.append("open_inner")
	_start("in", steps)
	_ai(&"airlock_cycle_in")
	return true


## Outside panel: brings the chamber down (closing the inner hatch if it
## was left open) and opens the outer hatch -- never locked out.
func begin_open_from_outside() -> bool:
	if sequence != "" or outer_open:
		return false
	var steps: Array = []
	if inner_open:
		steps.append("close_inner")
	if not is_vacuum():
		steps.append("depressurize")
	steps.append("open_outer")
	_start("out", steps)
	return true


var _steps: Array = []


func _start(kind: String, steps: Array) -> void:
	sequence = kind
	_steps = steps.duplicate()
	_step_total = steps.size()
	events.append({"event": "seq_" + kind, "t": _t})
	_next_step()


func _next_step() -> void:
	waiting = ""
	if _steps.is_empty():
		var k: String = sequence
		sequence = ""
		step = ""
		events.append({"event": "done_" + k, "t": _t})
		_sfx(&"success")
		_say("Outer hatch open. Tether clips on as you go out." if k == "out" and outer_open else ("Inner hatch open. Welcome back." if k == "in" else "Airlock ready."), 3.5)
		sequence_finished.emit(k)
		state_changed.emit()
		return
	step = _steps.pop_front()
	_step_t = 0.0
	match step:
		"close_inner", "close_outer", "open_inner", "open_outer":
			_sfx(&"latch")
		"depressurize":
			_sfx(&"hiss")
			_say("Depressurizing — %.1f psi" % psi, 2.0)
		"repressurize":
			_sfx(&"hiss")
			_say("Repressurizing...", 2.0)
	state_changed.emit()


func _process(delta: float) -> void:
	_t += delta
	if sequence != "":
		_run_step(delta)
	_animate_doors(delta)
	_refresh()


func _run_step(delta: float) -> void:
	match step:
		"close_inner":
			if _doorway_blocked(Z_INNER):
				waiting = "Clear the inner hatch"
				return
			waiting = ""
			inner_open = false
			if _inner_k <= 0.001:
				events.append({"event": "inner_closed", "t": _t})
				_next_step()
		"close_outer":
			if _doorway_blocked(Z_OUTER):
				waiting = "Clear the outer hatch"
				return
			waiting = ""
			outer_open = false
			if _outer_k <= 0.001:
				events.append({"event": "outer_closed", "t": _t})
				_next_step()
		"depressurize":
			# Interlocks re-checked at the moment of venting.
			if inner_open or outer_open:
				_abort("hatch not sealed")
				return
			if in_chamber(_eye()) and not _suited():
				_abort("unsuited person in the chamber")
				return
			_step_t += delta
			psi = lerpf(STATION_PSI, 0.0, clampf(_step_t / CYCLE_S, 0.0, 1.0))
			if _step_t >= CYCLE_S:
				psi = 0.0
				events.append({"event": "vacuum", "t": _t})
				_next_step()
		"repressurize":
			if inner_open or outer_open:
				_abort("hatch not sealed")
				return
			_step_t += delta
			psi = lerpf(0.0, STATION_PSI, clampf(_step_t / CYCLE_S, 0.0, 1.0))
			if _step_t >= CYCLE_S:
				psi = STATION_PSI
				events.append({"event": "pressurized", "t": _t})
				_next_step()
		"open_outer":
			if inner_open or not is_vacuum():
				_abort("pressure / inner hatch")
				return
			outer_open = true
			if _outer_k >= 0.999:
				events.append({"event": "outer_open", "t": _t})
				_next_step()
		"open_inner":
			if outer_open or not is_pressurized():
				_abort("pressure / outer hatch")
				return
			inner_open = true
			if _inner_k >= 0.999:
				events.append({"event": "inner_open", "t": _t})
				_next_step()


func _abort(why: String) -> void:
	_say("Airlock interlock: %s. Sequence stopped." % why, 3.5)
	_sfx(&"fail")
	events.append({"event": "abort", "why": why, "t": _t})
	sequence = ""
	step = ""
	_steps.clear()
	state_changed.emit()


func _animate_doors(delta: float) -> void:
	var r: float = delta / DOOR_S if delta > 0.0 else 1.0
	_inner_k = move_toward(_inner_k, 1.0 if inner_open else 0.0, r)
	_outer_k = move_toward(_outer_k, 1.0 if outer_open else 0.0, r)
	_apply_doors()


func _apply_doors() -> void:
	if _inner_door != null:
		_inner_door.rotation.y = deg_to_rad(95.0) * smoothstep(0.0, 1.0, _inner_k)
	if _outer_door != null:
		_outer_door.rotation.y = deg_to_rad(-95.0) * smoothstep(0.0, 1.0, _outer_k)


## Snap doors to their target (tests / load).
func settle() -> void:
	_inner_k = 1.0 if inner_open else 0.0
	_outer_k = 1.0 if outer_open else 0.0
	_apply_doors()


func reset_default() -> void:
	sequence = ""
	step = ""
	waiting = ""
	_steps.clear()
	inner_open = true
	outer_open = false
	psi = STATION_PSI
	settle()
	_refresh()


func state_word() -> String:
	if sequence != "":
		return "CYCLING"
	if is_vacuum():
		return "VACUUM"
	if is_pressurized():
		return "PRESSURIZED"
	return "PARTIAL"


func _refresh() -> void:
	var col: Color = Color(1.0, 0.65, 0.15) if sequence != "" else (Color(1.0, 0.25, 0.15) if is_vacuum() else Color(0.3, 0.95, 0.45))
	if _light != null:
		_light.light_color = col
	if _beacon_mat != null:
		_beacon_mat.albedo_color = col
		_beacon_mat.emission = col
	var txt: String = "%s\n%4.1f psi" % [state_word(), psi]
	if sequence != "":
		txt = "%s\n%4.1f psi" % [step_text(), psi]
	if waiting != "":
		txt = "%s\n%s" % [waiting.to_upper(), step_text()]
	_refresh_console()
	for s in _screens:
		(s as Label3D).text = txt
	if _big != null:
		_big.text = "%4.1f psi" % psi
		_big.modulate = col



# ======================================================================
# Round 40 Priority 2: ONE airlock control module. The chamber panel and
# the HATCH SEAL panel (hatch_seal.gd, same wall) sit together on one
# console "AIRLOCK A-1", under one header and a STATUS STRIP of four
# lamps -- INNER (green = open), CHAMBER (green pressurized / amber
# cycling / red vacuum), OUTER (red = open to space), SEAL (green = last
# hold test passed, red = failed, amber = inspecting / testing, grey =
# not tested). Step text on the screens is short ("2/3 VENT").
# ======================================================================
var _lamps: Dictionary = {}       # name -> StandardMaterial3D
const STEP_NAMES := {"close_inner": "SEAL INNER", "depressurize": "VENT", "open_outer": "OPEN OUTER", "close_outer": "SEAL OUTER", "repressurize": "PRESSURIZE", "open_inner": "OPEN INNER"}
var _step_total: int = 0


func step_text() -> String:
	if sequence == "" or step == "":
		return state_word()
	var n: int = _step_total - _steps.size()
	return "%d/%d %s" % [n, _step_total, STEP_NAMES.get(step, step.to_upper())]


func _build_console() -> void:
	var root := Node3D.new()
	root.name = "ControlConsole"
	add_child(root)
	# Backplate along the chamber's east wall behind both panels.
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.95, 1.18)
	back.mesh = bm
	back.material_override = _mat(Color(0.14, 0.15, 0.17), 0.5)
	back.position = Vector3(-4.404, 1.47, -1.62)
	root.add_child(back)
	var trim := MeshInstance3D.new()
	var tmm := BoxMesh.new()
	tmm.size = Vector3(0.02, 0.03, 1.18)
	trim.mesh = tmm
	trim.material_override = _mat(Color(0.95, 0.72, 0.1), 0.2)
	trim.position = Vector3(-4.408, 1.955, -1.62)
	root.add_child(trim)
	_label("AIRLOCK A-1", Vector3(-4.41, 1.9, -1.62), -90.0, 20, Color(0.95, 0.9, 0.8), root)
	var names := ["INNER", "CHAMBER", "OUTER", "SEAL"]
	for k in names.size():
		var z: float = -1.2 - k * 0.28
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		lamp.mesh = sm
		var m := _mat(Color(0.3, 0.3, 0.3), 0.0, Color(0.1, 0.1, 0.1))
		lamp.material_override = m
		lamp.position = Vector3(-4.412, 1.78, z)
		root.add_child(lamp)
		_lamps[names[k]] = m
		_label(names[k], Vector3(-4.41, 1.73, z), -90.0, 11, Color(0.8, 0.85, 0.85), root)
		if k < names.size() - 1:
			var link := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.006, 0.006, 0.2)
			link.mesh = lm
			link.material_override = _mat(Color(0.5, 0.5, 0.52), 0.3)
			link.position = Vector3(-4.41, 1.78, z - 0.14)
			root.add_child(link)


func _set_lamp(name: String, c: Color) -> void:
	var m: StandardMaterial3D = _lamps.get(name, null)
	if m != null:
		m.albedo_color = c
		m.emission = c * 0.9


func _refresh_console() -> void:
	if _lamps.is_empty():
		return
	var grey := Color(0.25, 0.26, 0.27)
	_set_lamp("INNER", Color(0.3, 0.95, 0.45) if inner_open else grey)
	_set_lamp("OUTER", Color(1.0, 0.25, 0.15) if outer_open else grey)
	_set_lamp("CHAMBER", Color(1.0, 0.65, 0.15) if sequence != "" else (Color(1.0, 0.25, 0.15) if is_vacuum() else Color(0.3, 0.95, 0.45)))
	_set_lamp("SEAL", seal_color())


func seal_color() -> Color:
	var hs: Node = get_node_or_null(^"../Equipment/HatchSeal")
	if hs == null:
		return Color(0.25, 0.26, 0.27)
	if hs.inspection_mode or hs.test_state == "running":
		return Color(1.0, 0.65, 0.15)
	if hs.test_state == "pass":
		return Color(0.3, 0.95, 0.45)
	if hs.test_state == "fail":
		return Color(1.0, 0.25, 0.15)
	return Color(0.25, 0.26, 0.27)
