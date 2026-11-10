extends "res://scripts/station/equipment_base.gd"
## Round 42 Priority 29, JUNCTION TASK A -- EMERGENCY LIGHTING TEST.
## A key-switch TEST panel on the Junction's east wall puts the Junction's
## four emergency light fixtures (EL-J1 .. EL-J4, high on its walls) on
## their test circuit. One fixture's lamp module has failed (which one is
## chosen from the work order's seed, saved, never re-rolled): it stays
## DARK while the others glow amber. The technician walks the Junction,
## checks each fixture (click), swaps the dead module (click it again) and
## returns the panel to NORMAL. The order closes itself when every fixture
## was checked, the failed one replaced and the test switch is back off.
## Physical, short, repeatable: different fixture each time.

## Fixture world positions + the direction their face points.
const FIXTURES := [
	[Vector3(-0.885, 2.22, 4.05), Vector3(1, 0, 0)],
	[Vector3(0.885, 2.22, 3.68), Vector3(-1, 0, 0)],
	[Vector3(1.285, 2.22, 5.82), Vector3(-1, 0, 0)],
	[Vector3(0.7, 2.22, 7.185), Vector3(0, 0, -1)],
]
const AMBER := Color(1.0, 0.62, 0.15)

var test_on: bool = false
var checked: Array = [false, false, false, false]
var failed: int = -1              # the fixture whose module is dead (-1 none)
var replaced: bool = true
var _lamps: Array = []            # StandardMaterial3D per fixture
var _glow: Array = []             # OmniLight3D per fixture
var _key: Node3D
var _readout: Label3D
var _panel_lamp: StandardMaterial3D


func _ready() -> void:
	_base_ready(&"emerg_lights")
	# Panel (local +z faces into the Junction).
	box(Vector3(0.3, 0.36, 0.04), Vector3(0, 1.35, -0.02), Color(0.16, 0.17, 0.19))
	box(Vector3(0.32, 0.035, 0.06), Vector3(0, 1.545, -0.01), Color(0.85, 0.15, 0.1))
	label("EMERGENCY LIGHTING", Vector3(0, 1.49, 0.005), 13)
	label("JUNCTION · EL-J1..J4", Vector3(0, 1.455, 0.005), 9, Color(0.75, 0.78, 0.78))
	_key = Node3D.new()
	_key.position = Vector3(-0.07, 1.33, 0.01)
	add_child(_key)
	var cyl := CSGCylinder3D.new()
	cyl.radius = 0.028
	cyl.height = 0.02
	cyl.rotation_degrees.x = 90.0
	var km := StandardMaterial3D.new()
	km.albedo_color = Color(0.7, 0.7, 0.72)
	km.metallic = 0.8
	cyl.material = km
	_key.add_child(cyl)
	box(Vector3(0.012, 0.045, 0.02), Vector3(0, 0, 0.015), Color(0.95, 0.75, 0.15), _key)
	label("NORM   TEST", Vector3(-0.07, 1.385, 0.006), 8)
	part(&"test", Vector3(0.08, 0.08, 0.06), Vector3(-0.07, 1.33, 0.02))
	_panel_lamp = lamp(Vector3(0.08, 1.37, 0.006))
	_readout = label("", Vector3(0.0, 1.24, 0.006), 10, Color(0.6, 0.95, 0.75))
	# Fixtures, mounted on the real Junction walls.
	for i in FIXTURES.size():
		var f := Node3D.new()
		f.name = "EmergencyFixture%d" % (i + 1)
		add_child(f)
		var n: Vector3 = FIXTURES[i][1]
		f.global_transform = Transform3D(Basis.looking_at(-n, Vector3.UP), FIXTURES[i][0])
		box(Vector3(0.2, 0.08, 0.05), Vector3(0, 0, 0.025), Color(0.22, 0.23, 0.25), f)
		box(Vector3(0.22, 0.012, 0.055), Vector3(0, 0.046, 0.025), Color(0.85, 0.15, 0.1), f)
		var lens := CSGBox3D.new()
		lens.size = Vector3(0.15, 0.045, 0.012)
		lens.position = Vector3(0, -0.005, 0.054)
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		lens.material = lm
		f.add_child(lens)
		_lamps.append(lm)
		label("EL-J%d" % (i + 1), Vector3(0, -0.06, 0.052), 9, Color(0.85, 0.85, 0.8), f)
		var gl := OmniLight3D.new()
		gl.light_color = AMBER
		gl.omni_range = 1.6
		gl.light_energy = 0.0
		gl.shadow_enabled = false
		gl.position = Vector3(0, -0.05, 0.15)
		f.add_child(gl)
		_glow.append(gl)
		part(StringName("fx%d" % i), Vector3(0.26, 0.14, 0.12), Vector3(0, 0, 0.04), f)
	_refresh()


func fixture_lit(i: int) -> bool:
	return test_on and not (i == failed and not replaced)


func on_part(id: StringName) -> void:
	var s := String(id)
	if s == "test":
		test_on = not test_on
		sfx(&"latch")
		say("Emergency lighting: %s." % ("TEST — check each fixture" if test_on else "NORMAL"))
		if _dp != null and not test_on and replaced and failed >= 0:
			_dp.log_event("Emergency lighting test complete (EL-J%d module replaced)" % (failed + 1))
	elif s.begins_with("fx"):
		var i: int = int(s.substr(2))
		if not test_on:
			say("EL-J%d is off — turn the Junction TEST switch on first." % (i + 1))
			return
		if not checked[i]:
			checked[i] = true
			sfx(&"click")
			say("EL-J%d: %s" % [i + 1, "NO LIGHT — lamp module failed. Click again to swap it." if (i == failed and not replaced) else "lit, OK."])
		elif i == failed and not replaced:
			replaced = true
			sfx(&"latch")
			say("EL-J%d: new lamp module seated — lit." % (i + 1))
		else:
			say("EL-J%d: lit, OK." % (i + 1))
	_refresh()


func part_prompt(id: StringName) -> String:
	var s := String(id)
	if s == "test":
		return "Click: emergency lighting %s" % ("back to NORMAL" if test_on else "TEST")
	if s.begins_with("fx"):
		var i: int = int(s.substr(2))
		if not test_on:
			return "EL-J%d (test switch: Junction panel)" % (i + 1)
		if checked[i] and i == failed and not replaced:
			return "Click: swap EL-J%d lamp module" % (i + 1)
		return "Click: check EL-J%d" % (i + 1)
	return ""


func _refresh() -> void:
	for i in _lamps.size():
		var lit: bool = fixture_lit(i)
		var m: StandardMaterial3D = _lamps[i]
		m.albedo_color = AMBER if lit else Color(0.2, 0.18, 0.15)
		m.emission = AMBER * 1.4 if lit else Color(0, 0, 0)
		(_glow[i] as OmniLight3D).light_energy = 0.35 if lit else 0.0
	if _key != null:
		_key.rotation_degrees.z = -50.0 if test_on else 0.0
	if _panel_lamp != null:
		set_lamp(_panel_lamp, AMBER if test_on else Color(0.3, 0.9, 0.4))
	if _readout != null:
		var n: int = 0
		for i in 4:
			if fixture_lit(i):
				n += 1
		_readout.text = ("TEST · %d/4 LIT" % n) if test_on else "NORMAL"


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	failed = rng.randi() % FIXTURES.size()
	replaced = false
	test_on = false
	checked = [false, false, false, false]
	_refresh()


func order_severity() -> int:
	return 1 if not order_done() else 0


func order_feasible() -> bool:
	return replaced and not test_on


func order_done() -> bool:
	return replaced and not test_on and checked.all(func(c): return c)


func order_next() -> Dictionary:
	var r := &"main_junction"
	if not test_on and not (replaced and checked.all(func(c): return c)):
		return {"action": "Junction panel: emergency lighting TEST", "short": "EM TEST ON", "room": r}
	for i in 4:
		if not checked[i]:
			return {"action": "Check fixture EL-J%d" % (i + 1), "short": "CHECK EL-J%d" % (i + 1), "room": r}
	if not replaced:
		return {"action": "Swap the EL-J%d lamp module" % (failed + 1), "short": "SWAP EL-J%d" % (failed + 1), "room": r}
	return {"action": "Return emergency lighting to NORMAL", "short": "EM NORMAL", "room": r}


func order_progress() -> String:
	return "%d/4" % checked.filter(func(c): return c).size()


func order_detail() -> Array:
	var lines: Array = ["Emergency lighting EL-J1..J4 (Junction). Switch %s." % ("TEST" if test_on else "NORMAL")]
	for i in 4:
		lines.append("EL-J%d: %s" % [i + 1, "not checked" if not checked[i] else ("FAILED — swap module" if (i == failed and not replaced) else "OK")])
	return lines


func state_dict() -> Dictionary:
	return {"test_on": test_on, "checked": checked.duplicate(), "failed": failed, "replaced": replaced}


func load_dict(d: Dictionary) -> void:
	test_on = bool(d.get("test_on", false))
	checked = Array(d.get("checked", checked)).map(func(v): return bool(v))
	failed = int(d.get("failed", -1))
	replaced = bool(d.get("replaced", true))
	_refresh()
