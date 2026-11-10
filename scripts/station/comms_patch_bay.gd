extends "res://scripts/station/equipment_base.gd"
## Round 42 Priority 28, COMMS TASK A -- SIGNAL PATCH BAY SERVICE.
## A six-port coaxial patch bay ("PB-2") on the Communications east wall
## routes the antenna feed through the receivers. Fault (order seed,
## saved): one patch plug has worked loose -- it visibly sits proud of its
## jack, its link LED flickers amber, and the station's comms LINK drops
## (signal_calibration_station.gd multiplies link_factor() in). Procedure:
## find the loose port (click: identify), pull it (click), reseat it firmly
## (click), then press LINK TEST (0 errors). The order closes itself.

const PORTS := 6

var loose: int = -1
var stage: int = 2                # 0 loose (not found), 1 pulled, 2 seated
var found: bool = true
var link_tested: bool = true
var _plugs: Array = []
var _leds: Array = []
var _readout: Label3D
var _t: float = 0.0


func _ready() -> void:
	_base_ready(&"patch_bay")
	add_to_group(&"comms_patch_bay")
	box(Vector3(0.46, 0.34, 0.05), Vector3(0, 1.32, -0.025), Color(0.13, 0.14, 0.16))
	box(Vector3(0.48, 0.03, 0.06), Vector3(0, 1.505, -0.02), Color(0.3, 0.6, 0.85))
	label("PB-2  SIGNAL PATCH BAY", Vector3(0, 1.46, 0.004), 11)
	for i in PORTS:
		var col: int = i % 3
		var row: int = i / 3
		var p := Vector3(-0.14 + col * 0.14, 1.38 - row * 0.12, 0.0)
		box(Vector3(0.05, 0.05, 0.01), p + Vector3(0, 0, 0.005), Color(0.55, 0.56, 0.58), null, 0.8)
		var plug := Node3D.new()
		plug.position = p
		add_child(plug)
		var c := CSGCylinder3D.new()
		c.radius = 0.014
		c.height = 0.05
		c.rotation_degrees.x = 90.0
		c.position = Vector3(0, 0, 0.03)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.75, 0.76, 0.78)
		m.metallic = 0.8
		c.material = m
		plug.add_child(c)
		var cable := CSGCylinder3D.new()
		cable.radius = 0.006
		cable.height = 0.12
		cable.position = Vector3(0, -0.06, 0.055)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.1, 0.1, 0.12)
		cable.material = cm
		plug.add_child(cable)
		_plugs.append(plug)
		_leds.append(lamp(p + Vector3(0.04, 0.03, 0.006), null, 0.008))
		label("P%d" % (i + 1), p + Vector3(-0.035, 0.035, 0.006), 8, Color(0.8, 0.85, 0.85))
		part(StringName("p%d" % i), Vector3(0.08, 0.08, 0.08), p + Vector3(0, 0, 0.03))
	box(Vector3(0.1, 0.045, 0.02), Vector3(0.12, 1.2, 0.01), Color(0.2, 0.5, 0.3))
	label("LINK TEST", Vector3(0.12, 1.2, 0.022), 8)
	part(&"test", Vector3(0.12, 0.06, 0.05), Vector3(0.12, 1.2, 0.02))
	_readout = label("", Vector3(-0.08, 1.2, 0.006), 9, Color(0.6, 0.95, 0.75))
	_refresh()


## Multiplies into the station's end-to-end comms link.
func link_factor() -> float:
	return 0.6 if (loose >= 0 and stage < 2) else 1.0


func on_part(id: StringName) -> void:
	var s := String(id)
	if s == "test":
		if loose >= 0 and stage < 2:
			link_tested = false
			sfx(&"fail")
			say("LINK TEST: FAIL — errors on a patch path.")
		else:
			link_tested = true
			sfx(&"success")
			say("LINK TEST: PASS — 0 errors.")
			if _dp != null and loose >= 0:
				_dp.log_event("Patch bay PB-2: P%d reseated, link test passed" % (loose + 1))
	elif s.begins_with("p"):
		var i: int = int(s.substr(1))
		if i != loose or stage == 2:
			say("P%d: seated, link green." % (i + 1))
		elif not found:
			found = true
			sfx(&"click")
			say("P%d: LOOSE — plug not fully home. Click to pull it." % (i + 1))
		elif stage == 0:
			stage = 1
			sfx(&"latch")
			say("P%d pulled. Click to reseat it firmly." % (i + 1))
		else:
			stage = 2
			link_tested = false
			sfx(&"latch")
			say("P%d reseated — run LINK TEST." % (i + 1))
	_refresh()


func part_prompt(id: StringName) -> String:
	var s := String(id)
	if s == "test":
		return "Click: LINK TEST"
	if s.begins_with("p"):
		var i: int = int(s.substr(1))
		if i == loose and stage < 2 and found:
			return "Click: %s P%d" % ["pull" if stage == 0 else "reseat", i + 1]
		return "Click: check P%d" % (i + 1)
	return ""


func _process(delta: float) -> void:
	_t += delta
	if loose >= 0 and stage == 0 and _leds.size() > loose:
		set_lamp(_leds[loose], Color(1.0, 0.6, 0.12), fmod(_t, 0.7) < 0.45)


func _refresh() -> void:
	for i in _plugs.size():
		var bad: bool = i == loose and stage < 2
		(_plugs[i] as Node3D).position.z = (0.015 if stage == 0 else 0.07) if bad else 0.0
		set_lamp(_leds[i], Color(1.0, 0.6, 0.12) if bad and stage == 0 else (Color(0.25, 0.25, 0.25) if bad else Color(0.3, 0.9, 0.4)), not (bad and stage == 1))
	if _readout != null:
		_readout.text = "LINK %s" % ("OK" if link_factor() >= 1.0 else "ERRORS")


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	loose = rng.randi() % PORTS
	stage = 0
	found = false
	link_tested = false
	_refresh()


func order_severity() -> int:
	return 1 if not order_done() else 0


func order_feasible() -> bool:
	return stage == 2


func order_done() -> bool:
	return stage == 2 and link_tested


func order_next() -> Dictionary:
	var r := &"communications"
	if stage < 2:
		if not found:
			return {"action": "Patch bay PB-2: find the loose plug", "short": "FIND PLUG", "room": r}
		return {"action": "%s plug P%d" % ["Pull" if stage == 0 else "Reseat", loose + 1], "short": "%s P%d" % ["PULL" if stage == 0 else "RESEAT", loose + 1], "room": r}
	return {"action": "Run the PB-2 LINK TEST", "short": "LINK TEST", "room": r}


func order_progress() -> String:
	return "%d/3" % (0 if not found else (1 if stage == 0 else (2 if stage == 1 else 3)))


func order_detail() -> Array:
	return ["Patch bay PB-2 (Communications, east wall), 6 ports.", ("Loose plug: %s." % ("P%d" % (loose + 1) if found else "not found yet")) if stage < 2 else "All plugs seated.", "Link test: %s." % ("passed" if link_tested else "not run")]


func state_dict() -> Dictionary:
	return {"loose": loose, "stage": stage, "found": found, "link_tested": link_tested}


func load_dict(d: Dictionary) -> void:
	loose = int(d.get("loose", -1))
	stage = clampi(int(d.get("stage", 2)), 0, 2)
	found = bool(d.get("found", true))
	link_tested = bool(d.get("link_tested", true))
	_refresh()
