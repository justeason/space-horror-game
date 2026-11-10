extends "res://scripts/station/equipment_base.gd"
## Round 42 Priority 29, JUNCTION TASK B -- DISTRIBUTION PANEL INSPECTION.
## The Junction's electrical access panel (west wall of Junction A, "JDP-1")
## feeds three local circuits: J1 Junction lighting, J2 environment
## sensors, J3 vent fan. Behind its hinged cover: one connector + status
## LED per circuit and a built-in test meter with a circuit SELECTOR knob.
## Fault (from the order's seed, saved): one circuit's connector has worked
## loose -- its LED is amber and the meter reads it LOW (17.6 V instead of
## 24.1 V). Procedure: open the cover, measure each circuit (turn the
## selector), reseat the loose connector, measure that circuit again (24.1
## V), close the cover. The order closes itself when that is all true.

const CIRCUITS := ["J1 LIGHTING", "J2 SENSORS", "J3 VENT FAN"]
const NOMINAL_V := 24.1
const LOW_V := 17.6

var cover_open: bool = false
var sel: int = 0
var measured: Array = [false, false, false]
var loose: int = -1
var reseated: bool = true
var remeasured: bool = true
var _cover: Node3D
var _knob: Node3D
var _meter: Label3D
var _leds: Array = []
var _plugs: Array = []


func _ready() -> void:
	_base_ready(&"junction_panel")
	box(Vector3(0.42, 0.5, 0.06), Vector3(0, 1.15, -0.03), Color(0.2, 0.21, 0.23))
	box(Vector3(0.44, 0.03, 0.07), Vector3(0, 1.415, -0.025), Color(0.95, 0.72, 0.1))
	label("JDP-1  JUNCTION DISTRIBUTION", Vector3(0, 1.45, 0.012), 11)
	# Inside: three connector rows (visible when the cover is open).
	for i in 3:
		var y: float = 1.3 - i * 0.1
		label(CIRCUITS[i], Vector3(-0.1, y, 0.004), 9, Color(0.8, 0.85, 0.85))
		var plug := Node3D.new()
		plug.position = Vector3(0.08, y, 0.0)
		add_child(plug)
		box(Vector3(0.06, 0.04, 0.03), Vector3(0, 0, 0.015), Color(0.15, 0.15, 0.16), plug)
		box(Vector3(0.02, 0.02, 0.02), Vector3(0.04, 0, 0.012), Color(0.75, 0.6, 0.2), plug, 0.8)
		_plugs.append(plug)
		_leds.append(lamp(Vector3(0.16, y, 0.006)))
		part(StringName("c%d" % i), Vector3(0.09, 0.07, 0.06), Vector3(0.09, y, 0.02))
	# Test meter + selector.
	box(Vector3(0.18, 0.07, 0.01), Vector3(-0.08, 0.98, 0.002), Color(0.03, 0.05, 0.05))
	_meter = label("", Vector3(-0.08, 0.98, 0.009), 12, Color(0.55, 0.95, 0.75))
	_knob = Node3D.new()
	_knob.position = Vector3(0.12, 0.98, 0.01)
	add_child(_knob)
	var kc := CSGCylinder3D.new()
	kc.radius = 0.025
	kc.height = 0.025
	kc.rotation_degrees.x = 90.0
	var km := StandardMaterial3D.new()
	km.albedo_color = Color(0.1, 0.1, 0.11)
	kc.material = km
	_knob.add_child(kc)
	box(Vector3(0.006, 0.03, 0.01), Vector3(0, 0.012, 0.014), Color(0.95, 0.95, 0.9), _knob)
	part(&"knob", Vector3(0.07, 0.07, 0.06), Vector3(0.12, 0.98, 0.02))
	# Hinged cover (left hinge), swings open toward the room.
	_cover = Node3D.new()
	_cover.position = Vector3(-0.2, 1.15, 0.035)
	add_child(_cover)
	box(Vector3(0.4, 0.46, 0.015), Vector3(0.2, 0, 0), Color(0.42, 0.44, 0.47), _cover, 0.5)
	label("JDP-1 · 24 V DC · ISOLATE AT B-01", Vector3(0.2, 0.12, 0.009), 9, Color(0.1, 0.1, 0.1), _cover)
	box(Vector3(0.04, 0.08, 0.02), Vector3(0.36, 0, 0.012), Color(0.15, 0.15, 0.16), _cover)
	part(&"cover", Vector3(0.4, 0.46, 0.04), Vector3(0.2, 0, 0.02), _cover)   # swings with the cover
	_refresh()


func voltage(i: int) -> float:
	return LOW_V if (i == loose and not reseated) else NOMINAL_V


func on_part(id: StringName) -> void:
	var s := String(id)
	match s:
		"cover":
			cover_open = not cover_open
			sfx(&"latch")
			if cover_open:
				_measure()
		"knob":
			sel = (sel + 1) % 3
			sfx(&"click")
			if cover_open:
				_measure()
			else:
				say("Open the panel cover to read the meter.")
		_:
			if s.begins_with("c"):
				var i: int = int(s.substr(1))
				if not cover_open:
					say("Open the JDP-1 cover first.")
					return
				if i == loose and not reseated:
					if not measured[i]:
						say("Measure %s first (selector)." % CIRCUITS[i])
						return
					reseated = true
					remeasured = false
					sfx(&"latch")
					say("%s connector reseated — measure it again." % CIRCUITS[i])
				else:
					say("%s connector tight." % CIRCUITS[i])
	_refresh()


func _measure() -> void:
	measured[sel] = true
	if sel == loose and reseated:
		remeasured = true
	var v: float = voltage(sel)
	say("%s: %.1f V%s" % [CIRCUITS[sel], v, "  LOW" if v < 23.0 else ""])


func part_prompt(id: StringName) -> String:
	var s := String(id)
	if s == "cover":
		return "Click: %s JDP-1 cover" % ("close" if cover_open else "open")
	if s == "knob":
		return "Click: meter selector (now %s)" % CIRCUITS[sel]
	if s.begins_with("c") and cover_open:
		var i: int = int(s.substr(1))
		return "Click: reseat %s connector" % CIRCUITS[i] if (i == loose and not reseated) else "%s connector" % CIRCUITS[i]
	return ""


func _refresh() -> void:
	if _cover != null:
		_cover.rotation_degrees.y = -100.0 if cover_open else 0.0
	if _knob != null:
		_knob.rotation_degrees.z = -45.0 + sel * 45.0
	for i in _leds.size():
		set_lamp(_leds[i], Color(1.0, 0.6, 0.12) if (i == loose and not reseated) else Color(0.3, 0.9, 0.4))
		(_plugs[i] as Node3D).position.z = 0.012 if (i == loose and not reseated) else 0.0
	if _meter != null:
		_meter.text = "%s\n%.1f V" % [CIRCUITS[sel], voltage(sel)] if cover_open else ""


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	loose = rng.randi() % 3
	reseated = false
	remeasured = false
	measured = [false, false, false]
	cover_open = false
	sel = 0
	_refresh()


func order_severity() -> int:
	return 1 if not order_done() else 0


func order_feasible() -> bool:
	return reseated and not cover_open


func order_done() -> bool:
	return reseated and remeasured and not cover_open


func order_next() -> Dictionary:
	var r := &"main_junction"
	if not reseated:
		if not cover_open:
			return {"action": "Open distribution panel JDP-1", "short": "OPEN JDP-1", "room": r}
		for i in 3:
			if not measured[i]:
				return {"action": "Measure %s (selector)" % CIRCUITS[i], "short": "MEASURE J%d" % (i + 1), "room": r}
		return {"action": "Reseat the %s connector" % CIRCUITS[loose], "short": "RESEAT J%d" % (loose + 1), "room": r}
	if not remeasured:
		return {"action": "Measure %s again" % CIRCUITS[loose], "short": "RE-MEASURE", "room": r}
	return {"action": "Close the JDP-1 cover", "short": "CLOSE JDP-1", "room": r}


func order_progress() -> String:
	return "%d/3" % measured.filter(func(m): return m).size()


func order_detail() -> Array:
	var lines: Array = ["Junction distribution panel JDP-1 (Junction A, west wall). Cover %s." % ("OPEN" if cover_open else "closed")]
	for i in 3:
		lines.append("%s: %s" % [CIRCUITS[i], ("%.1f V" % voltage(i)) if measured[i] else "not measured"])
	return lines


func state_dict() -> Dictionary:
	return {"cover_open": cover_open, "sel": sel, "measured": measured.duplicate(), "loose": loose, "reseated": reseated, "remeasured": remeasured}


func load_dict(d: Dictionary) -> void:
	cover_open = bool(d.get("cover_open", false))
	sel = clampi(int(d.get("sel", 0)), 0, 2)
	measured = Array(d.get("measured", measured)).map(func(v): return bool(v))
	loose = int(d.get("loose", -1))
	reseated = bool(d.get("reseated", true))
	remeasured = bool(d.get("remeasured", true))
	_refresh()
