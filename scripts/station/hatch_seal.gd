extends "res://scripts/station/equipment_base.gd"
## Round 35 Priority 8: the AIRLOCK HATCH SEAL. Four inspectable seal
## sections (top / right / bottom / left of the EVA hatch rim), an
## INSPECTION-MODE lever and a PRESSURE-HOLD TEST panel on the tunnel wall.
## Faults (per section): "debris" (grit in the seal) or "clip" (misaligned
## retaining clip). Each fault leaks: leak_kpa() feeds the EnvironmentModel
## cabin pressure (slow drift, never a blow-out). Procedure: inspection
## mode -> examine sections -> correct the faulty ones -> secure the hatch
## -> run the hold test (passes only with no faults). Interlock: no
## inspection mode while a cargo transfer is in progress (and the cargo
## port refuses to operate while the hatch is in inspection mode).

const NAMES := ["TOP", "RIGHT", "BOTTOM", "LEFT"]
const POS := [Vector3(0, 0.88, 0.07), Vector3(0.37, 0, 0.07), Vector3(0, -0.88, 0.07), Vector3(-0.37, 0, 0.07)]
const SIZE := [Vector3(0.5, 0.05, 0.03), Vector3(0.05, 1.3, 0.03), Vector3(0.5, 0.05, 0.03), Vector3(0.05, 1.3, 0.03)]
const TEST_S := 3.0
@export var cargo_port_path: NodePath = ^"../../Interactables/CargoPort"
@export var panel_offset: Vector3 = Vector3(0.385, 0.05, 0.42)   # Round 40: on the AIRLOCK A-1 console (chamber east wall), level with the chamber panel

var faults: Array = ["", "", "", ""]
var inspected: Array = [false, false, false, false]
var inspection_mode: bool = false
var test_state: String = "pass"   # "" | "running" | "pass" | "fail"
var _test_t: float = 0.0
var _seal_mats: Array = []
var _marks: Array = []
## Round 36 Priority 6: physical fault hardware per section --
## {"brackets": [2 retaining-clip brackets], "debris": Node3D (grit
## cluster), "rolled": Node3D (gasket lip out of its groove)}.
var _hw: Array = []
var _inspect_light: SpotLight3D
const FAULT_KINDS := ["debris", "clip", "rolled"]
var _lever: CSGBox3D
var _readout: Label3D
var _mode_lamp: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"hatch_seal")
	_base_ready(&"seal")
	for i in 4:
		var s := box(SIZE[i], POS[i], Color(0.12, 0.12, 0.13))
		_seal_mats.append(s.material)
		_build_section_hardware(i)
		part(StringName("s%d" % i), SIZE[i] + Vector3(0.04, 0.04, 0.08), POS[i] + Vector3(0, 0, 0.02))
	# Round 36: a local INSPECTION LAMP over the hatch, on in inspect mode.
	_inspect_light = SpotLight3D.new()
	_inspect_light.name = "InspectionLamp"
	_inspect_light.light_color = Color(0.95, 0.97, 1.0)
	_inspect_light.light_energy = 0.0
	_inspect_light.spot_range = 2.6
	_inspect_light.spot_angle = 48.0
	_inspect_light.shadow_enabled = false
	_inspect_light.position = Vector3(0.0, 1.15, 0.75)
	add_child(_inspect_light)
	_inspect_light.look_at(global_transform * Vector3(0, 0, 0.05), Vector3.UP)
	var lamp_housing := box(Vector3(0.12, 0.05, 0.08), Vector3(0.0, 1.18, 0.75), Color(0.3, 0.32, 0.35))
	lamp_housing.name = "InspectionLampHousing"
	# Control panel on the tunnel's east wall (faces -X, into the tunnel).
	var p := Node3D.new()
	p.position = panel_offset
	p.rotation_degrees.y = -90.0
	add_child(p)
	box(Vector3(0.34, 0.42, 0.04), Vector3(0, 0, -0.02), Color(0.2, 0.22, 0.25), p)
	box(Vector3(0.36, 0.04, 0.06), Vector3(0, 0.22, -0.01), Color(0.85, 0.55, 0.1), p)
	label("HATCH SEAL", Vector3(0, 0.17, 0.005), 16, Color(0.9, 0.9, 0.85), p)
	_lever = box(Vector3(0.03, 0.09, 0.03), Vector3(-0.09, 0.05, 0.02), Color(0.85, 0.2, 0.15), p)
	label("SECURED / INSPECT", Vector3(-0.09, -0.03, 0.005), 9, Color(0.75, 0.78, 0.78), p)
	_mode_lamp = lamp(Vector3(-0.09, 0.12, 0.01), p)
	part(&"mode", Vector3(0.08, 0.14, 0.06), Vector3(-0.09, 0.05, 0.02), p)
	box(Vector3(0.07, 0.07, 0.03), Vector3(0.09, 0.05, 0.015), Color(0.2, 0.55, 0.3), p)
	label("TEST", Vector3(0.09, 0.05, 0.032), 12, Color(0.95, 0.95, 0.9), p)
	part(&"test", Vector3(0.09, 0.09, 0.06), Vector3(0.09, 0.05, 0.02), p)
	_readout = label("", Vector3(0, -0.12, 0.006), 13, Color(0.55, 0.95, 0.75), p)
	_refresh()


## Along-axis and across-axis (outward from the hatch centre) for section i.
func _axes(i: int) -> Array:
	var along: Vector3 = Vector3(1, 0, 0) if i % 2 == 0 else Vector3(0, 1, 0)
	var out: Vector3 = POS[i].normalized()
	return [along, out]


func _section_len(i: int) -> float:
	return SIZE[i].x if i % 2 == 0 else SIZE[i].y


func _build_section_hardware(i: int) -> void:
	var ax: Array = _axes(i)
	var along: Vector3 = ax[0]
	var outv: Vector3 = ax[1]
	var L: float = _section_len(i)
	var front: float = POS[i].z + SIZE[i].z * 0.5
	var hw := {"brackets": []}
	# Two retaining clips per section: steel brackets straddling the gasket.
	for k in 2:
		var root := Node3D.new()
		root.position = POS[i] + along * (L * (-0.3 if k == 0 else 0.3))
		root.position.z = front
		add_child(root)
		var b := box(Vector3(0.085, 0.032, 0.014) if i % 2 == 1 else Vector3(0.032, 0.085, 0.014), Vector3(0, 0, 0.007), Color(0.72, 0.74, 0.76), root, 0.85)
		b.name = "Bracket"
		box(Vector3(0.016, 0.016, 0.01), Vector3(0, 0, 0.017), Color(0.25, 0.25, 0.27), root, 0.9)   # screw head
		hw["brackets"].append(root)
	# Debris: a wad of pale fibre and grit lodged on the sealing face (the
	# kind of thing a cargo transfer drags in) -- small, but it breaks the
	# dark gasket line and catches the light.
	var deb := Node3D.new()
	deb.position = POS[i] + along * (L * 0.08)
	deb.position.z = front
	add_child(deb)
	var grit := [[0.0, 0.0, 0.022], [0.03, 0.008, 0.016], [-0.026, -0.006, 0.014], [0.055, -0.01, 0.018], [-0.05, 0.009, 0.012], [0.016, 0.016, 0.01], [-0.012, -0.014, 0.012]]
	for g in grit:
		var gp: Vector3 = along * g[0] + outv * g[1]
		var gb := box(Vector3(g[2], g[2] * 0.8, g[2] * 0.75), gp + Vector3(0, 0, g[2] * 0.4), Color(0.6, 0.55, 0.45), deb, 0.0)
		gb.rotation_degrees.z = g[0] * 900.0
	var wad := box(Vector3(0.09, 0.026, 0.01) if i % 2 == 0 else Vector3(0.026, 0.09, 0.01), Vector3(0, 0, 0.006), Color(0.86, 0.84, 0.78), deb, 0.0)
	wad.rotation_degrees.z = 14.0
	hw["debris"] = deb
	# Misaligned clip: where the twisted bracket no longer clamps it, the
	# gasket lifts and a strip of bright bare channel shows.
	var cg := box(Vector3(0.14, 0.016, 0.004) if i % 2 == 0 else Vector3(0.016, 0.14, 0.004), POS[i] + along * (L * -0.3) - outv * 0.034, Color(0.85, 0.85, 0.82), null, 0.7)
	cg.position.z = front + 0.001
	cg.name = "ClipGap%d" % i
	hw["clip_gap"] = cg
	# Rolled lip: a length of gasket bulging out of its channel, exposing
	# the bare metal groove beside it.
	var rol := Node3D.new()
	rol.position = POS[i] + along * (L * -0.05) + outv * 0.03
	rol.position.z = front + 0.012
	add_child(rol)
	var lip := box(Vector3(L * 0.45, 0.03, 0.034) if i % 2 == 0 else Vector3(0.03, L * 0.45, 0.034), Vector3.ZERO, Color(0.24, 0.24, 0.25), rol, 0.0)
	lip.rotation_degrees.x = 22.0 if i % 2 == 0 else 0.0
	lip.rotation_degrees.y = 0.0 if i % 2 == 0 else 22.0
	var gap := box(Vector3(L * 0.45, 0.02, 0.004) if i % 2 == 0 else Vector3(0.02, L * 0.45, 0.004), -outv * 0.062 + Vector3(0, 0, -0.011), Color(0.85, 0.85, 0.82), rol, 0.7)
	gap.name = "BareChannel"
	hw["rolled"] = rol
	_hw.append(hw)


# ======================================================================
# Round 42 Priority 18: the PRESSURE-HOLD test is a CLOSED-HATCH test of
# the outer hatch seal, driven by the airlock's AUTHORITATIVE state
# (airlock_chamber.gd) -- no separate fake seal state:
#   cannot start: HATCH OPEN (outer hatch open), CYCLING (a sequence is
#   running), LOW PRESSURE (the chamber is not at station pressure -- a
#   hold test needs the full 14.7 psi across the seal), SECURE HATCH
#   (inspection mode);
#   running: aborts the moment any of those becomes true;
#   PASS / FAIL describe THAT closure: opening the outer hatch again
#   clears the result (a new closure has not been tested).
# ======================================================================
var last_block: String = ""


func _airlock() -> Node:
	return get_tree().get_first_node_in_group(&"airlock") if is_inside_tree() else null


## Why the hold test cannot run now ("" = it can).
func test_blocker() -> String:
	if inspection_mode:
		return "SECURE HATCH"
	var a: Node = _airlock()
	if a == null:
		return ""
	if a.outer_open:
		return "HATCH OPEN"
	if a.sequence != "":
		return "CYCLING"
	if a.psi < 14.5:
		return "LOW PRESSURE"
	return ""


var _idle_t: float = 0.0


func _process(delta: float) -> void:
	_idle_t += delta
	if _idle_t >= 0.5 and test_state != "running":
		_idle_t = 0.0
		_refresh()
	var a: Node = _airlock()
	if a != null and a.outer_open and test_state in ["pass", "fail"]:
		test_state = ""
		if _dp != null:
			_dp.log_event("Hatch seal hold result cleared (outer hatch opened)")
		_refresh()
	if test_state == "running":
		var why: String = test_blocker()
		if why != "":
			test_state = ""
			last_block = why
			sfx(&"fail")
			say("Pressure-hold test ABORTED — %s." % why.to_lower())
			_refresh()
			return
		_test_t += delta
		if _test_t >= TEST_S:
			test_state = "pass" if leak_kpa() == 0.0 else "fail"
			sfx(&"success" if test_state == "pass" else &"fail")
			say("Pressure-hold test %s." % ("PASSED — 0.0 kPa/min" if test_state == "pass" else "FAILED — %.1f kPa/min" % (leak_kpa() * 0.6)))
			if _dp != null:
				_dp.log_event("Hatch seal hold test %s" % test_state.to_upper())
			_refresh()


func leak_kpa() -> float:
	var n := 0
	for f in faults:
		if String(f) != "":
			n += 1
	return 1.2 * n


func _cargo_busy() -> bool:
	var port: Node = get_node_or_null(cargo_port_path)
	return port != null and port.state != port.PortState.SECURED


func on_part(id: StringName) -> void:
	var s := String(id)
	if s == "mode":
		var eva: Node = get_tree().get_first_node_in_group(&"eva_system")
		if eva != null and eva.is_eva_active():
			say("Airlock in EVA use — inspection locked out.")
			sfx(&"fail")
			return
		if not inspection_mode and _cargo_busy():
			say("Cargo transfer in progress — finish it before inspecting the hatch.")
			sfx(&"fail")
			ai_event(&"interlock_cargo")
			return
		inspection_mode = not inspection_mode
		if inspection_mode:
			test_state = ""
		sfx(&"latch")
	elif s == "test":
		var why: String = test_blocker()
		if why != "":
			last_block = why
			say({"SECURE HATCH": "Secure the hatch before the pressure-hold test.", "HATCH OPEN": "Outer hatch OPEN — close it before a pressure-hold test.", "CYCLING": "Airlock cycling — wait for it to finish.", "LOW PRESSURE": "Chamber not at station pressure — pressurise it first."}.get(why, why))
			sfx(&"fail")
			_refresh()
			return
		last_block = ""
		test_state = "running"
		_test_t = 0.0
		sfx(&"hiss")
	elif s.begins_with("s"):
		var i: int = int(s.substr(1))
		if not inspection_mode:
			say("Put the hatch in INSPECT mode first (lever on the tunnel wall).")
			return
		if not inspected[i]:
			inspected[i] = true
			sfx(&"click")
			say("%s seal: %s" % [NAMES[i], _fault_text(faults[i])])
		elif String(faults[i]) != "":
			say("%s seal: %s." % [NAMES[i], _FIXED_TEXT.get(String(faults[i]), "corrected")])
			faults[i] = ""
			test_state = ""
			sfx(&"latch")
			if _dp != null:
				_dp.log_event("Hatch seal %s corrected" % NAMES[i])
		else:
			say("%s seal: good." % NAMES[i])
	_refresh()


func _fault_text(f: String) -> String:
	match f:
		"debris": return "DEBRIS trapped in the gasket — click to remove"
		"clip": return "retaining clip MISALIGNED — click to realign"
		"rolled": return "gasket lip ROLLED out of its groove — click to reseat"
	return "good"


const _FIX_VERB := {"debris": "Remove debris", "clip": "Realign clip", "rolled": "Reseat gasket"}
const _FIXED_TEXT := {"debris": "debris removed", "clip": "clip realigned", "rolled": "gasket reseated"}


func part_prompt(id: StringName) -> String:
	var s := String(id)
	if s == "mode":
		return "Click: %s hatch" % ("Secure" if inspection_mode else "Inspect (unlock)")
	if s == "test":
		var why: String = test_blocker()
		return "Click: Run pressure-hold test" if why == "" else "Pressure test: %s" % why
	if s.begins_with("s"):
		var i: int = int(s.substr(1))
		if not inspection_mode:
			return ""
		if not inspected[i]:
			return "Click: Inspect %s seal" % NAMES[i]
		return ("Click: %s" % _FIX_VERB.get(String(faults[i]), "Correct fault")) if String(faults[i]) != "" else "%s seal good" % NAMES[i]
	return ""


func _refresh() -> void:
	for i in 4:
		var f: String = String(faults[i])
		# The fault is PHYSICAL and visible before inspection; inspecting a
		# faulty section only adds a subtle tag colour on its gasket.
		(_seal_mats[i] as StandardMaterial3D).albedo_color = Color(0.12, 0.12, 0.13) if f == "" or not inspected[i] else Color(0.32, 0.2, 0.12)
		var hw: Dictionary = _hw[i]
		(hw["debris"] as Node3D).visible = f == "debris"
		(hw["rolled"] as Node3D).visible = f == "rolled"
		var b0: Node3D = hw["brackets"][0]
		var outv: Vector3 = _axes(i)[1]
		var base: Vector3 = POS[i] + _axes(i)[0] * (_section_len(i) * -0.3)
		base.z = POS[i].z + SIZE[i].z * 0.5
		(hw["clip_gap"] as Node3D).visible = f == "clip"
		if f == "clip":
			# Twisted ~40 deg off the gasket line, tipped and lifted off it.
			b0.position = base + outv * 0.03 + Vector3(0, 0, 0.026)
			b0.rotation_degrees = Vector3(25.0 if i % 2 == 1 else 0.0, 25.0 if i % 2 == 0 else 0.0, 40.0)
		else:
			b0.position = base
			b0.rotation_degrees = Vector3.ZERO
	if _inspect_light != null:
		_inspect_light.light_energy = 1.6 if inspection_mode else 0.0
	if _lever != null:
		_lever.rotation_degrees.z = 40.0 if inspection_mode else 0.0
		set_lamp(_mode_lamp, Color(1.0, 0.65, 0.1) if inspection_mode else Color(0.3, 0.9, 0.4), true)
	if _readout != null:
		var blk: String = test_blocker() if is_inside_tree() else ""
		var idle: String = "HOLD TEST: %s" % (blk if blk != "" else "READY")
		var t: String = {"": idle, "running": "HOLD TEST: RUNNING...", "pass": "HOLD TEST: PASS", "fail": "HOLD TEST: FAIL"}.get(test_state, "")
		_readout.text = "%s\nLEAK %.1f kPa/min" % [t, leak_kpa() * 0.6] if test_state in ["pass", "fail"] else t
		_readout.modulate = Color(0.55, 0.95, 0.75) if test_state == "pass" else (Color(1.0, 0.4, 0.3) if test_state == "fail" else Color(0.85, 0.85, 0.8))


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = 1 + rng.randi() % 2
	# Round 38: two faults at once only for a practised technician.
	if _dp != null and _dp.has_method("proficiency_level") and _dp.proficiency_level("mechanical") < 2:
		n = 1
	var used := {}
	for k in n:
		var i: int = rng.randi() % 4
		while used.has(i):
			i = (i + 1) % 4
		used[i] = true
		faults[i] = FAULT_KINDS[rng.randi() % FAULT_KINDS.size()]
	inspected = [false, false, false, false]
	test_state = ""
	_refresh()


## Round 37 severity: a leaking seal (cabin pressure falling) = warning.
func order_severity() -> int:
	if leak_kpa() > 0.0:
		return 2
	return 1 if test_state != "pass" else 0


func order_feasible() -> bool:
	return leak_kpa() == 0.0 and not inspection_mode and not _cargo_busy()


func order_done() -> bool:
	return leak_kpa() == 0.0 and not inspection_mode and test_state == "pass"


func order_next() -> Dictionary:
	var r := &"airlock"
	if leak_kpa() > 0.0:
		if not inspection_mode:
			return {"action": "Unlock hatch", "short": "INSPECT MODE", "room": r}
		for i in 4:
			if not inspected[i]:
				return {"action": "Inspect %s seal" % NAMES[i].to_lower(), "short": "INSPECT %s" % NAMES[i], "room": r}
		for i in 4:
			if String(faults[i]) != "":
				return {"action": "%s %s seal" % [{"debris": "Clean", "clip": "Realign clip,", "rolled": "Reseat"}.get(String(faults[i]), "Fix"), NAMES[i].to_lower()], "short": "FIX %s" % NAMES[i], "room": r}
	if inspection_mode:
		return {"action": "Secure the hatch", "short": "SECURE HATCH", "room": r}
	if test_state == "running":
		return {"action": "Pressure test running", "short": "TESTING", "room": r}
	match test_blocker():
		"HATCH OPEN": return {"action": "Close the outer hatch (airlock IN>>)", "short": "SEAL FIRST", "room": r}
		"CYCLING": return {"action": "Wait for the airlock cycle", "short": "CYCLING", "room": r}
		"LOW PRESSURE": return {"action": "Pressurise the chamber", "short": "PRESSURIZE", "room": r}
	return {"action": "Run pressure-hold test", "short": "PRESSURE HOLD", "room": r}


func order_progress() -> String:
	return "%d/4" % inspected.filter(func(v): return v).size()


func order_detail() -> Array:
	var lines: Array = ["EVA hatch seal (Airlock). Leak %.1f kPa/min; hatch %s; test %s." % [leak_kpa() * 0.6, "INSPECT" if inspection_mode else "secured", test_state if test_state != "" else "not run"]]
	for i in 4:
		lines.append("%s: %s" % [NAMES[i], ("not inspected" if not inspected[i] else _fault_text(faults[i]).get_slice(" —", 0))])
	return lines


func state_dict() -> Dictionary:
	return {"faults": faults.duplicate(), "inspected": inspected.duplicate(), "inspection_mode": inspection_mode, "test_state": test_state if test_state != "running" else ""}


func load_dict(d: Dictionary) -> void:
	faults = Array(d.get("faults", faults)).map(func(v): return String(v))
	inspected = Array(d.get("inspected", inspected)).map(func(v): return bool(v))
	inspection_mode = bool(d.get("inspection_mode", inspection_mode))
	test_state = String(d.get("test_state", test_state))
	_refresh()
