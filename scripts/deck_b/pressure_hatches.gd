extends "res://scripts/deck_b/deck_b_room.gd"
## Round 50 -- L09 RAPID PRESSURE LOSS, played on the station's PRESSURE
## NETWORK (deck_b_systems.gd "press": Deck A, the Deck B core and three
## sealable compartments). Everything here is a physical control or
## instrument on that one model:
##   PRESSURE HATCHES   B-03 Thermal, B-04 Workshop, B-08 Cargo: a pocket
##                      pressure door in the doorway (collides when shut), a
##                      local panel on BOTH sides (this side / other side
##                      pressure, ΔP, trend, hatch + EQ state), the HATCH
##                      lever, the EQ (equalisation) valve handwheel and a
##                      PRESSURE-HOLD TEST. A hatch cannot be pulled open
##                      above HATCH_DP_MAX -- equalise first.
##   PCP-B              the lower deck's pressure control panel (Lower
##                      Junction east wall): every volume, its trend, the
##                      make-up gas flow and reserve, the inter-deck duct
##                      valve IV-AB, the alarm level, and LOG STATUS.
##   LEAK KIT           (Lower Junction east wall) temporary clamp patches,
##                      gland packing, a berthing-seal kit. The leak
##                      DETECTOR is Deck A's ultrasonic detector (Life
##                      Support instrument rack) -- one tool, not a copy.
##   DEFECT SITES       FT-3 coolant-line hull feedthrough (B-03, "pipe"),
##                      berthing-port seal BP-1 (B-08, "seal"), the B-04
##                      south-wall hull penetration ("hull", shared with
##                      the A06 EVA repair). Each hisses (positional, scaled
##                      by the REAL flow through it, silent once sealed).
## Procedure (no fixed button order -- the model decides what is true):
##   detect (alarm / PCP) -> find the compartment (close hatches one at a
##   time and watch which side falls, or follow the hiss with the detector)
##   -> STABILISE (isolate it, or clamp a temporary patch on the located
##   defect) -> REPAIR (pipe: repack the gland; seal: replace the seal;
##   hull: outside only -> A06) -> repressurise (EQ) -> HOLD TEST -> open.
## Outcomes: repaired (defect gone + hold test passed + volume back in the
## network), stabilized (temporary patch, defect remains), deferred (left
## isolated). A hull defect hands its permanent repair to A06.

const HATCHES := {
	"B03": {"door": 1, "slide": -1.0, "panels": [[Vector3(0.66, L.FLOOR_Y + 1.35, 7.51), 0.0, "BC"], [Vector3(0.66, L.FLOOR_Y + 1.35, 7.29), 180.0, "B03"]]},
	"B04": {"door": 10, "slide": -1.0, "panels": [[Vector3(-2.375, L.FLOOR_Y + 1.35, 6.51), 0.0, "BC"], [Vector3(-2.375, L.FLOOR_Y + 1.35, 6.29), 180.0, "B04"]]},
	"B08": {"door": 8, "slide": -1.0, "panels": [[Vector3(-6.32, L.FLOOR_Y + 1.35, 7.39), 180.0, "BC"], [Vector3(-6.71, L.FLOOR_Y + 1.35, 6.2), -90.0, "B08"]]},
}
## Defect site hardware: id -> [position, yaw, permanent-repair part].
const SITES := {
	"b03_feed": [Vector3(1.585, L.FLOOR_Y + 1.62, 4.62), -90.0, &"gland_packing"],
	"b08_seal": [Vector3(-9.43, L.FLOOR_Y + 1.25, 7.0), 90.0, &"berth_seal_kit"],
	"hull_b04": [Vector3(-4.75, L.FLOOR_Y + 1.72, 3.11), 0.0, &""],
}
const HOLD_S := 20.0               # pressure-hold test duration (gameplay s)
const HOLD_PASS := -0.05           # kPa/min: anything slower holds
const SLIDE_S := 1.4

var ident: String = ""             # compartment identified as the source
var ident_how: String = ""         # "isolation test" | "leak detector"
var pcp_read: bool = false
var iso_verified: bool = false
var leak_id: String = ""           # the defect this order is about
var hold := {}                     # comp -> {state, t, p0, rate, day}
var logged: String = ""            # stabilized | deferred (LOG STATUS)
var fixed_by: String = ""          # what the technician did to the defect
var _closed_s := {"B03": 0.0, "B04": 0.0, "B08": 0.0}

var _leaf := {}                    # comp -> {node, cs, closed_pos, open_pos, x}
var _readouts := {}                # comp -> [Label3D]
var _lamps := {}                   # comp -> [StandardMaterial3D]
var _eq_wheels := {}               # comp -> [Node3D]
var _levers := {}                  # comp -> [Node3D]
var _pcp: Label3D
var _alarm_lamp: StandardMaterial3D
var _duct_lever: Node3D
var _kit: Rack
var _site := {}                    # id -> {root, temp, fixed, mark, hiss}
var _last_alarm: int = 0
var _was_iso := {}


func _ready() -> void:
	room_id = &"b01"
	_room_ready([&"l09_pressure"])
	for c in HATCHES:
		_build_hatch(c)
	_build_pcp()
	_build_kit()
	for id in SITES:
		_build_site(id)
	_refresh()


func _net() -> Node:
	return sys()


# ------------------------------------------------------------ geometry
func _build_hatch(c: String) -> void:
	var h: Dictionary = HATCHES[c]
	var d: Array = L.DOORS[int(h["door"])]
	var e: Dictionary = L.shared_edge(d[0], d[1])
	var lo: float = float(d[2]) - float(d[3]) * 0.5
	var hi: float = float(d[2]) + float(d[3]) * 0.5
	var w: float = hi - lo + 0.06
	var along_x: bool = e["axis"] == "z"         # the edge runs along x
	var root := Node3D.new()
	root.name = "Hatch" + c
	add_child(root)
	var leaf := Node3D.new()
	leaf.name = "Leaf"
	root.add_child(leaf)
	var mid: float = float(d[2])
	var closed_pos := Vector3(mid, L.FLOOR_Y + L.DOOR_H * 0.5, float(e["at"])) if along_x else Vector3(float(e["at"]), L.FLOOR_Y + L.DOOR_H * 0.5, mid)
	var slide: Vector3 = (Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)) * float(h["slide"]) * (w + 0.06)
	leaf.position = closed_pos + slide
	if not along_x:
		leaf.rotation_degrees.y = 90.0
	# The door: a stiffened plate with a rim seal, two handles, a small
	# round viewport and hazard edging (local x = across the doorway).
	dbox(Vector3(w, L.DOOR_H, 0.05), Vector3.ZERO, Color(0.62, 0.64, 0.66), leaf, 0.55)
	for side in [-1.0, 1.0]:
		dbox(Vector3(w - 0.08, 0.05, 0.012), Vector3(0, 0.55, side * 0.031), Color(0.5, 0.52, 0.54), leaf, 0.6)
		dbox(Vector3(w - 0.08, 0.05, 0.012), Vector3(0, -0.45, side * 0.031), Color(0.5, 0.52, 0.54), leaf, 0.6)
		dbox(Vector3(0.035, 0.32, 0.03), Vector3(w * 0.5 - 0.12, 0.0, side * 0.045), Color(0.2, 0.2, 0.22), leaf, 0.7)
		dcyl(0.09, 0.014, Vector3(0, 0.25, side * 0.03), Color(0.08, 0.1, 0.12), leaf, Vector3(90, 0, 0), 0.2)
		for k in 6:
			dbox(Vector3(w / 6.0 - 0.01, 0.06, 0.006), Vector3(-w * 0.5 + w / 12.0 + k * w / 6.0, -L.DOOR_H * 0.5 + 0.08, side * 0.029), Color(0.95, 0.75, 0.1) if k % 2 == 0 else Color(0.1, 0.1, 0.1), leaf, 0.1)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, L.DOOR_H, 0.12)
	cs.shape = bs
	sb.add_child(cs)
	leaf.add_child(sb)
	_leaf[c] = {"node": leaf, "cs": cs, "closed": closed_pos, "open": closed_pos + slide, "x": 1.0}
	_readouts[c] = []
	_lamps[c] = []
	_eq_wheels[c] = []
	_levers[c] = []
	for pd in h["panels"]:
		_build_panel(c, root, pd[0], float(pd[1]), String(pd[2]))


## A local hatch panel: readout, status lamp, HATCH lever, EQ handwheel,
## TEST button. `side` = the volume this panel stands in.
func _build_panel(c: String, parent: Node3D, pos: Vector3, yaw: float, side: String) -> void:
	var p := Node3D.new()
	p.name = "Panel%s_%s" % [c, side]
	p.position = pos
	p.rotation_degrees.y = yaw
	parent.add_child(p)
	dbox(Vector3(0.24, 0.42, 0.035), Vector3(0, 0, 0.0175), Color(0.2, 0.22, 0.25), p)
	dbox(Vector3(0.25, 0.03, 0.04), Vector3(0, 0.215, 0.02), Color(0.9, 0.55, 0.1), p)
	for sx in [-0.105, 0.105]:
		for sy in [-0.19, 0.19]:
			dcyl(0.007, 0.01, Vector3(sx, sy, 0.037), Color(0.7, 0.7, 0.72), p, Vector3(90, 0, 0))
	text("%s HATCH" % c.replace("B0", "B-0"), Vector3(0, 0.175, 0.037), 8, Color(0.95, 0.95, 0.9), p)
	var r: Label3D = readout(Vector3(0, 0.09, 0.037), Vector2(0.21, 0.12), p, 7)
	_readouts[c].append(r)
	part(StringName("gauge_%s_%s" % [c, side]), Vector3(0.21, 0.12, 0.05), Vector3(0, 0.09, 0.045), p)
	var lm := dbox(Vector3(0.025, 0.025, 0.012), Vector3(0.09, 0.175, 0.04), Color(0.2, 0.9, 0.3), p)
	_lamps[c].append(lm.material_override)
	# HATCH lever (up = open, down = shut).
	var lev := Node3D.new()
	lev.position = Vector3(-0.065, -0.05, 0.045)
	p.add_child(lev)
	dbox(Vector3(0.022, 0.09, 0.022), Vector3(0, 0.04, 0), Color(0.85, 0.2, 0.15), lev)
	dcyl(0.02, 0.03, Vector3.ZERO, Color(0.3, 0.3, 0.32), lev, Vector3(90, 0, 0))
	_levers[c].append(lev)
	text("HATCH", Vector3(-0.065, -0.12, 0.037), 6, Color(0.9, 0.9, 0.9), p)
	part(StringName("hatch_%s_%s" % [c, side]), Vector3(0.08, 0.14, 0.06), Vector3(-0.065, -0.04, 0.05), p)
	# EQ valve handwheel.
	var wh: Node3D = handwheel("eq_%s_%s" % [c, side], Vector3(0.05, -0.06, 0.05), 0.04, p, true, Color(0.2, 0.45, 0.8))
	_eq_wheels[c].append(wh)
	text("EQ", Vector3(0.05, -0.12, 0.037), 6, Color(0.9, 0.9, 0.9), p)
	# Hold-test button.
	button("test_%s_%s" % [c, side], Vector3(0.0, -0.17, 0.04), Color(0.2, 0.55, 0.3), p, Vector3(0.06, 0.03, 0.02))
	text("HOLD TEST", Vector3(0.0, -0.195, 0.037), 5, Color(0.9, 0.9, 0.9), p)
	flush_clicks(p, 0.06)                       # keep picks out of the corridors


func _build_pcp() -> void:
	var p := Node3D.new()
	p.name = "PCP_B"
	p.position = Vector3(-2.31, L.FLOOR_Y + 1.45, 6.97)
	p.rotation_degrees.y = -90.0                  # faces -x into the junction
	add_child(p)
	dbox(Vector3(0.56, 0.5, 0.05), Vector3(0, 0, 0.025), Color(0.18, 0.2, 0.23), p)
	dbox(Vector3(0.58, 0.04, 0.06), Vector3(0, 0.26, 0.03), Color(0.85, 0.15, 0.12), p)
	text("PCP-B · PRESSURE CONTROL (LOWER DECK)", Vector3(0, 0.215, 0.052), 8, Color(0.95, 0.95, 0.9), p)
	_pcp = readout(Vector3(-0.04, 0.03, 0.052), Vector2(0.46, 0.3), p, 7)
	part(&"pcp_read", Vector3(0.46, 0.3, 0.06), Vector3(-0.04, 0.03, 0.06), p)
	var am := dbox(Vector3(0.05, 0.05, 0.02), Vector3(0.23, 0.15, 0.055), Color(0.2, 0.9, 0.3), p)
	_alarm_lamp = am.material_override
	_duct_lever = Node3D.new()
	_duct_lever.position = Vector3(-0.17, -0.18, 0.06)
	p.add_child(_duct_lever)
	dbox(Vector3(0.025, 0.1, 0.025), Vector3(0, 0.045, 0), Color(0.2, 0.45, 0.8), _duct_lever)
	part(&"duct", Vector3(0.1, 0.14, 0.06), Vector3(-0.17, -0.17, 0.07), p)
	text("IV-AB DUCT", Vector3(-0.17, -0.235, 0.052), 6, Color(0.9, 0.9, 0.9), p)
	button("log", Vector3(0.12, -0.19, 0.055), Color(0.9, 0.75, 0.15), p, Vector3(0.09, 0.04, 0.02))
	text("LOG STATUS", Vector3(0.12, -0.225, 0.052), 6, Color(0.9, 0.9, 0.9), p)
	# A conduit from the panel up into the ceiling run (it is wired, not hung).
	dbox(Vector3(0.04, 1.0, 0.04), Vector3(0.2, 0.75, 0.02), Color(0.4, 0.42, 0.45), p)


func _build_kit() -> void:
	var k := Node3D.new()
	k.name = "LeakKitCabinet"
	add_child(k)
	# Wall cabinet (open front, red cross-hatched header) holding the rack.
	var base := Vector3(-2.31, L.FLOOR_Y + 1.0, 8.76)
	var c := dbox(Vector3(0.08, 0.5, 0.74), base + Vector3(-0.02, 0.08, 0.28), Color(0.3, 0.32, 0.35), k)
	c.name = "Cabinet"
	dbox(Vector3(0.1, 0.06, 0.76), base + Vector3(-0.04, 0.36, 0.28), Color(0.85, 0.15, 0.12), k)
	text("LEAK KIT · EMERGENCY", base + Vector3(-0.095, 0.36, 0.28), 8, Color(1, 1, 1), k, -90.0)
	_kit = rack("LeakKit", base + Vector3(-0.12, 0.0, 0.0), 5, 0.14, [&"leak_patch", &"gland_packing", &"berth_seal_kit"], "TEMP PATCH · PACKING · SEAL", self, -90.0)
	_stock.call_deferred()


func _stock() -> void:
	for kind in [&"leak_patch", &"leak_patch", &"gland_packing", &"berth_seal_kit"]:
		var it: Node3D = spawn_part(kind, _kit, {"history": [{"day": day(), "text": "emergency leak kit stock"}]})
		it.add_to_group(&"r50_stock")


func _build_site(id: String) -> void:
	var e: Array = SITES[id]
	var root := Node3D.new()
	root.name = "Site_" + id
	root.position = e[0]
	root.rotation_degrees.y = float(e[1])
	add_child(root)
	var temp := Node3D.new()
	temp.name = "TempPatch"
	root.add_child(temp)
	var fixed := Node3D.new()
	fixed.name = "Repaired"
	root.add_child(fixed)
	var mark := Node3D.new()
	mark.name = "Defect"
	root.add_child(mark)
	match id:
		"b03_feed":
			# Hull feedthrough flange: two coolant lines pass the hull here.
			dcyl(0.16, 0.03, Vector3(0, 0, 0.015), Color(0.55, 0.57, 0.6), root, Vector3(90, 0, 0), 0.7)
			for k in 8:
				var a: float = TAU * k / 8.0
				dcyl(0.01, 0.02, Vector3(cos(a) * 0.13, sin(a) * 0.13, 0.035), Color(0.75, 0.75, 0.78), root, Vector3(90, 0, 0), 0.8)
			for sx in [-0.06, 0.06]:
				# Stub out of the wall, a bend, then down the wall to the
				# floor manifold (the lines go somewhere: HX-1's return).
				var pc: Color = Color(0.2, 0.45, 0.75) if sx < 0 else Color(0.75, 0.3, 0.2)
				dcyl(0.028, 0.2, Vector3(sx, 0.0, 0.13), pc, root, Vector3(90, 0, 0), 0.5)
				dcyl(0.034, 0.07, Vector3(sx, -0.02, 0.23), pc.darkened(0.2), root, Vector3(45, 0, 0), 0.5)
				dcyl(0.028, 1.58, Vector3(sx, -0.82, 0.25), pc, root, Vector3.ZERO, 0.5)
				dcyl(0.045, 0.06, Vector3(sx, 0.0, 0.07), Color(0.62, 0.62, 0.6), root, Vector3(90, 0, 0), 0.8)
				for yy in [-0.55, -1.25]:
					dbox(Vector3(0.05, 0.03, 0.26), Vector3(sx, yy, 0.13), Color(0.5, 0.52, 0.55), root, 0.6)   # wall clamps
			text("FT-3", Vector3(0, 0.2, 0.032), 9, Color(0.95, 0.95, 0.9), root)
			dbox(Vector3(0.05, 0.012, 0.004), Vector3(-0.06, 0.06, 0.103), Color(0.7, 0.1, 0.1), mark)   # frost / staining at the gland
			dbox(Vector3(0.1, 0.1, 0.01), Vector3(-0.06, 0.0, 0.11), Color(0.85, 0.5, 0.12), temp)        # clamp
			dcyl(0.05, 0.03, Vector3(-0.06, 0.0, 0.1), Color(0.3, 0.75, 0.95), fixed, Vector3(90, 0, 0))  # fresh packing nut
		"b08_seal":
			# A segment of the berthing port's cabin-side seal (the port
			# itself is cargo_bay.gd's CBP-1).
			dbox(Vector3(0.3, 0.04, 0.03), Vector3(0.2, -0.5, 0.06), Color(0.1, 0.1, 0.11), root, 0.1)
			dbox(Vector3(0.12, 0.03, 0.02), Vector3(0.24, -0.47, 0.075), Color(0.5, 0.3, 0.15), mark)     # rolled / cut seal lip
			dbox(Vector3(0.24, 0.08, 0.03), Vector3(0.2, -0.5, 0.085), Color(0.85, 0.5, 0.12), temp)      # clamp bar
			dbox(Vector3(0.3, 0.045, 0.032), Vector3(0.2, -0.5, 0.062), Color(0.15, 0.15, 0.16), fixed)   # new seal
			text("BP-1 SEAL", Vector3(0.2, -0.6, 0.05), 7, Color(0.95, 0.95, 0.9), root)
		"hull_b04":
			# The inside of the hull plate: a small puncture through the
			# liner (frosted rim while gas escapes).
			dbox(Vector3(0.5, 0.4, 0.012), Vector3(0, 0, 0.006), Color(0.78, 0.78, 0.75), root, 0.2)
			dcyl(0.012, 0.016, Vector3(0, 0, 0.012), Color(0.02, 0.02, 0.02), mark, Vector3(90, 0, 0))
			dcyl(0.04, 0.006, Vector3(0, 0, 0.014), Color(0.92, 0.95, 1.0), mark, Vector3(90, 0, 0))
			dbox(Vector3(0.18, 0.18, 0.02), Vector3(0, 0, 0.022), Color(0.85, 0.5, 0.12), temp)
			for sx in [-0.07, 0.07]:
				for sy in [-0.07, 0.07]:
					dcyl(0.01, 0.012, Vector3(sx, sy, 0.034), Color(0.3, 0.3, 0.3), temp, Vector3(90, 0, 0))
			text("HULL B-04/S", Vector3(0, 0.24, 0.014), 7, Color(0.3, 0.3, 0.3), root)
	part(StringName("site_" + id), Vector3(0.36, 0.36, 0.2), Vector3(0, 0, 0.08) if id != "b08_seal" else Vector3(0.2, -0.5, 0.1), root)
	var hiss: AudioStreamPlayer3D = machine_loop(_hiss_stream(id), e[0] + Vector3(0, 0, 0), -80.0)
	hiss.unit_size = 1.6
	hiss.max_distance = 9.0
	_site[id] = {"root": root, "temp": temp, "fixed": fixed, "mark": mark, "hiss": hiss}


## A gas jet through a small defect: broadband hiss, colour by the defect
## (a gland whistles a little, a seal flutters, a hole is a clean rush).
static func _hiss_stream(id: String) -> AudioStreamWAV:
	var tone: float = {"b03_feed": 2600.0, "b08_seal": 900.0, "hull_b04": 0.0}.get(id, 0.0)
	return loop_stream(1.0, func(t, i):
		var n: float = fmod(sin(float(i) * 12.9898 + 4.1) * 43758.5453, 1.0) - 0.5
		var flutter: float = 1.0 + (0.35 * sin(TAU * 7.0 * t) if id == "b08_seal" else 0.0)
		return n * 0.5 * flutter + (sin(TAU * tone * t) * 0.05 if tone > 0.0 else 0.0))


# -------------------------------------------------------- interaction
func on_part(id: StringName) -> void:
	var s: Node = _net()
	if s == null:
		return
	var sid := String(id)
	if sid == "pcp_read":
		_read_pcp()
	elif sid == "duct":
		s.set_duct(not bool(s.press["duct"]))
		sfx(&"latch")
		say("Inter-deck duct IV-AB %s." % ("OPEN" if s.press["duct"] else "CLOSED — Deck B is sealed off from Deck A's air"))
	elif sid == "log":
		_log_status()
	elif sid.begins_with("hatch_"):
		_hatch(sid.get_slice("_", 1))
	elif sid.begins_with("eq_"):
		var c: String = sid.get_slice("_", 1)
		s.set_eq(c, not bool(s.press["eq"][c]))
		sfx(&"ratchet")
		say("%s EQ valve %s." % [c.replace("B0", "B-0"), "OPEN — equalising" if s.press["eq"][c] else "SHUT"])
	elif sid.begins_with("test_"):
		_start_hold(sid.get_slice("_", 1))
	elif sid.begins_with("gauge_"):
		_read_gauge(sid.get_slice("_", 1), sid.get_slice("_", 2))
	elif sid.begins_with("site_"):
		_site_click(sid.substr(5))
	_refresh()


func part_prompt(id: StringName) -> String:
	var s: Node = _net()
	var sid := String(id)
	if s == null:
		return ""
	if sid == "pcp_read":
		return "Click: Read PCP-B (every volume, trend, make-up gas)"
	if sid == "duct":
		return "Click: %s inter-deck duct IV-AB" % ("Close" if s.press["duct"] else "Open")
	if sid == "log":
		return "Click: Log pressure status (stabilised / deferred)"
	if sid.begins_with("hatch_"):
		var c: String = sid.get_slice("_", 1)
		return "Click: %s %s hatch (ΔP %.1f kPa)" % ["Close" if s.hatch_open(c) else "Open", c.replace("B0", "B-0"), absf(s.hatch_dp(c))]
	if sid.begins_with("eq_"):
		var c2: String = sid.get_slice("_", 1)
		return "Click: %s %s equalisation valve" % ["Shut" if s.press["eq"][c2] else "Open", c2.replace("B0", "B-0")]
	if sid.begins_with("test_"):
		return "Click: Pressure-hold test (%d s)" % int(HOLD_S)
	if sid.begins_with("gauge_"):
		return "Click: Read the hatch gauge"
	if sid.begins_with("site_"):
		var lid: String = sid.substr(5)
		var hk: StringName = held_kind()
		if hk == &"leak_detector":
			return "Click: Sweep %s with the leak detector" % _site_name(lid)
		if hk == &"leak_patch":
			return "Click: Clamp a temporary patch on %s" % _site_name(lid)
		if hk != &"" and hk == SITES[lid][2]:
			return "Click: Repair %s (%s)" % [_site_name(lid), Part.KINDS[hk]["name"]]
		return "Click: Inspect %s" % _site_name(lid)
	return ""


static func _site_name(id: String) -> String:
	return {"b03_feed": "feedthrough FT-3", "b08_seal": "berthing seal BP-1", "hull_b04": "hull plate B-04/S"}.get(id, id)


func _hatch(c: String) -> void:
	var s: Node = _net()
	var open_now: bool = s.hatch_open(c)
	var why: String = s.set_hatch(c, not open_now)
	if why != "":
		sfx(&"fail")
		say("%s hatch will not move: %s." % [c.replace("B0", "B-0"), why])
		return
	sfx(&"latch")
	sfx(&"clunk")
	_closed_s[c] = 0.0
	say("%s hatch %s." % [c.replace("B0", "B-0"), "closing — sealed" if open_now else "opening"])


func _read_gauge(c: String, side: String) -> void:
	var s: Node = _net()
	var here: String = c if side != "BC" else "BC"
	var other: String = "BC" if side != "BC" else c
	say("%s: here %.1f kPa (%+.2f/min) · other side %.1f kPa · ΔP %.1f · hatch %s · EQ %s" % [c.replace("B0", "B-0"), s.pressure(here), s.trend(here), s.pressure(other), absf(s.hatch_dp(c)),
		"OPEN" if s.hatch_open(c) else "SHUT", "OPEN" if s.press["eq"][c] else "SHUT"], 5.0)
	_note_isolation_evidence(c)


func _read_pcp() -> void:
	var s: Node = _net()
	pcp_read = true
	var lines: Array = []
	for c in ["A", "BC", "B03", "B04", "B08"]:
		lines.append("%s %.1f (%+.2f)" % [c, s.pressure(c), s.trend(c)])
	say("PCP-B %s · %s · make-up %.2f kPa·m³/s" % [s.alarm_word(int(s.press["alarm"])), " · ".join(lines), float(s.press["makeup_flow"])], 6.0)
	for c in HATCHES:
		_note_isolation_evidence(c)
	if has_open(&"l09_pressure") and _source_isolated() and float(s.trend("BC")) > -0.08 and float(s.press["makeup_flow"]) < MAKEUP_HOLD:
		if not iso_verified:
			iso_verified = true
			say("PCP-B: %s isolated — the station volume is holding (%+.2f kPa/min)." % [_comp_word(_leak_comp()), s.trend("BC")], 4.5)
			_ai(&"press_isolated")


const MAKEUP_HOLD := 1.35          # below MAKEUP_MAX: the PCS is no longer saturated


## The REAL diagnostic: with a hatch shut, a falling pressure on its far
## side (and the station holding) points at that compartment.
func _note_isolation_evidence(c: String) -> void:
	var s: Node = _net()
	if not has_open(&"l09_pressure") or ident != "" or s.hatch_open(c):
		return
	if float(_closed_s.get(c, 0.0)) >= 6.0 and s.trend(c) < -0.3 and s.leak_flow(c) > 0.0:
		ident = c
		ident_how = "isolation test"
		say("%s keeps falling with its hatch shut — the leak is IN %s." % [_comp_word(c), _comp_word(c)], 4.5)


func _site_click(id: String) -> void:
	var s: Node = _net()
	var lk: Dictionary = s.leak(id)
	var live: bool = not lk.is_empty() and String(lk["state"]) != "repaired"
	var hk: StringName = held_kind()
	var flow: float = s.leak_c(lk) * s.pressure(String(lk["comp"])) if live else 0.0
	if hk == &"leak_detector":
		if not live or flow < 0.02:
			say("Leak detector at %s: background only (%d dB)." % [_site_name(id), 18 + randi() % 4])
			return
		lk["found"] = true
		if ident == "":
			ident = String(lk["comp"])
			ident_how = "leak detector"
		say("Leak detector at %s: %d dB ultrasonic — %s." % [_site_name(id), int(40.0 + 12.0 * log(flow + 1.0)), {"pipe": "the packing gland is blowing", "seal": "the seal lip is rolled out of its groove", "hull": "a puncture through the hull plate"}[String(lk["kind"])]], 4.5)
		sfx(&"relay")
		return
	if hk == &"leak_patch":
		if not live or String(lk["state"]) != "active":
			say("Nothing here needs a clamp patch.")
			return
		if not bool(lk.get("found", false)):
			say("Find the exact point first (leak detector) — a patch on the wrong spot does nothing.")
			return
		consume_part(held())
		s.set_leak_state(id, "temp")
		fixed_by = "temporary clamp patch"
		sfx(&"latch")
		say("Clamp patch seated over %s. The hiss drops to a whisper — temporary only." % _site_name(id), 4.0)
		return
	if live and hk != &"" and hk == SITES[id][2]:
		if not bool(lk.get("found", false)):
			say("Locate the leak first (leak detector).")
			return
		consume_part(held())
		s.set_leak_state(id, "repaired")
		fixed_by = {"b03_feed": "gland repacked and torqued", "b08_seal": "seal replaced and seated"}.get(id, "repaired")
		sfx(&"success")
		say("%s: %s. Now prove it — a pressure-hold test on the compartment." % [_site_name(id), fixed_by], 4.5)
		return
	if not live:
		say("%s: no hiss, no frost, seal seated." % _site_name(id).capitalize())
		return
	if String(lk["kind"]) == "hull":
		say("A puncture in the hull plate%s. Inside, only a temporary patch is possible — the permanent repair is from OUTSIDE (EVA)." % (" — gas is rushing out" if flow > 0.5 else ""), 5.0)
	else:
		say("You can hear it — %s. Bring the leak detector to pin it down." % ("a high whistle at the gland" if id == "b03_feed" else "a fluttering hiss at the seal"), 4.0)


func _start_hold(c: String) -> void:
	var s: Node = _net()
	if s.hatch_open(c) or bool(s.press["eq"][c]):
		sfx(&"fail")
		say("Hold test: shut the hatch AND the EQ valve first (the compartment must be sealed).")
		return
	if s.pressure(c) < 99.0:
		sfx(&"fail")
		say("Hold test: %s is at %.1f kPa — repressurise (EQ valve) to station pressure first." % [_comp_word(c), s.pressure(c)])
		return
	hold[c] = {"state": "running", "t": 0.0, "p0": s.pressure(c), "rate": 0.0, "day": day()}
	sfx(&"click")
	say("Pressure-hold test running on %s (%d s)…" % [_comp_word(c), int(HOLD_S)])


func _log_status() -> void:
	var s: Node = _net()
	if not has_open(&"l09_pressure"):
		say("PCP-B: no pressure order open.")
		return
	var lk: Dictionary = s.leak(leak_id)
	if lk.is_empty() or String(lk["state"]) == "repaired":
		say("PCP-B: the defect is repaired — finish with a hold test, then reopen the hatch.")
		return
	var c: String = String(lk["comp"])
	var stable: bool = s.trend("BC") > -0.1 and s.pressure("BC") > s.P_CAUTION - 1.0 and float(s.press["makeup_flow"]) < MAKEUP_HOLD
	if String(lk["state"]) == "temp" and stable:
		logged = "stabilized"
	elif not s.hatch_open(c) and stable:
		logged = "deferred"
	else:
		sfx(&"fail")
		say("PCP-B: not stable yet — the station is still losing gas. Isolate %s or patch the leak." % (_comp_word(ident) if ident != "" else "the leaking compartment"), 4.0)
		return
	sfx(&"success")
	say("PCP-B: logged %s — %s." % [logged.to_upper(), "temporary patch holding, permanent repair still due" if logged == "stabilized" else "%s left isolated, repair scheduled" % _comp_word(c)], 4.5)


func _comp_word(c: String) -> String:
	var s: Node = _net()
	return String(s.COMP_NAME.get(c, c)) if s != null else c


func _leak_comp() -> String:
	var s: Node = _net()
	var lk: Dictionary = s.leak(leak_id) if s != null else {}
	return String(lk.get("comp", ""))


func _source_isolated() -> bool:
	var s: Node = _net()
	var c: String = _leak_comp()
	return c != "" and c != "A" and c != "BC" and not s.hatch_open(c) and not bool(s.press["eq"][c])


func _ai(key: StringName) -> void:
	for a in get_tree().get_nodes_in_group(&"station_ai"):
		a.event(key)


# ---------------------------------------------------------------- tick
func _process(delta: float) -> void:
	var s: Node = _net()
	if s == null:
		return
	var gd: float = _dp.gameplay_delta(delta) if _dp != null and _dp.has_method("gameplay_delta") and int(s.press["alarm"]) == 0 else delta
	for c in HATCHES:
		var lf: Dictionary = _leaf[c]
		var want: float = 1.0 if s.hatch_open(c) else 0.0
		lf["x"] = move_toward(float(lf["x"]), want, delta / SLIDE_S)
		(lf["node"] as Node3D).position = (lf["closed"] as Vector3).lerp(lf["open"], smoothstep(0.0, 1.0, float(lf["x"])))
		(lf["cs"] as CollisionShape3D).disabled = float(lf["x"]) > 0.6
		_closed_s[c] = 0.0 if s.hatch_open(c) else float(_closed_s[c]) + gd
		if hold.has(c) and hold[c]["state"] == "running":
			var h: Dictionary = hold[c]
			if s.hatch_open(c) or bool(s.press["eq"][c]):
				h["state"] = "aborted"
			else:
				h["t"] = float(h["t"]) + gd
				if float(h["t"]) >= HOLD_S:
					h["rate"] = (s.pressure(c) - float(h["p0"])) / float(h["t"]) * 60.0
					h["state"] = "pass" if float(h["rate"]) > HOLD_PASS else "fail"
					sfx(&"success" if h["state"] == "pass" else &"fail")
					say("Hold test %s: %s %+.2f kPa/min." % ["PASSED" if h["state"] == "pass" else "FAILED", _comp_word(c), float(h["rate"])], 4.5)
		if _was_iso.get(c, true) != s.hatch_open(c):
			_was_iso[c] = s.hatch_open(c)
	# Hiss: the real flow through each defect, scaled; the volume drops to
	# nothing as the pressure behind it goes, or once it is sealed.
	for id in _site:
		var lk: Dictionary = s.leak(id)
		var q: float = s.leak_c(lk) * s.pressure(String(lk["comp"])) if not lk.is_empty() else 0.0
		var ap: AudioStreamPlayer3D = _site[id]["hiss"]
		var on: bool = q > 0.01
		if on and not ap.playing:
			ap.play()
		elif not on and ap.playing:
			ap.stop()
		ap.volume_db = linear_to_db(clampf(q / 6.0, 0.02, 1.0)) - 6.0
	# Station alarm escalation (short, from the real level).
	var al: int = int(s.press["alarm"])
	if al > _last_alarm:
		_ai([&"", &"press_caution", &"press_warning", &"press_critical"][al])
	_last_alarm = al
	_poll_t += delta
	if _poll_t > 0.25:
		_poll_t = 0.0
		_refresh()
var _poll_t: float = 0.0


func _refresh() -> void:
	var s: Node = _net()
	if s == null or _pcp == null:
		return
	for c in HATCHES:
		var op: bool = s.hatch_open(c)
		var eq: bool = bool(s.press["eq"][c])
		var h: Dictionary = hold.get(c, {})
		var ht: String = ""
		if not h.is_empty():
			ht = "\nTEST %s" % ("%d s" % int(HOLD_S - float(h["t"])) if h["state"] == "running" else ("PASS" if h["state"] == "pass" else ("FAIL %+.2f" % float(h["rate"]) if h["state"] == "fail" else "ABORT")))
		var i := 0
		for r in _readouts[c]:
			var here: String = "BC" if i == 0 else c
			var other: String = c if i == 0 else "BC"
			(r as Label3D).text = "HERE %5.1f %s\nFAR  %5.1f\nΔP %.1f %s%s" % [s.pressure(here), "▼" if s.trend(here) < -0.1 else ("▲" if s.trend(here) > 0.1 else "="), s.pressure(other), absf(s.hatch_dp(c)),
				"OPEN" if op else ("EQ" if eq else "SHUT"), ht]
			i += 1
		var col: Color = Color(0.2, 0.9, 0.3) if op else (Color(1.0, 0.7, 0.1) if s.pressure(c) > 99.0 else Color(1.0, 0.15, 0.1))
		for m in _lamps[c]:
			(m as StandardMaterial3D).albedo_color = col
			(m as StandardMaterial3D).emission_enabled = true
			(m as StandardMaterial3D).emission = col
		for lv in _levers[c]:
			(lv as Node3D).rotation_degrees.z = 0.0 if op else 180.0
		for w in _eq_wheels[c]:
			set_wheel(w, 1.0 if eq else 0.0)
	var al: int = int(s.press["alarm"])
	var acol: Color = [Color(0.2, 0.9, 0.3), Color(1.0, 0.8, 0.1), Color(1.0, 0.4, 0.05), Color(1.0, 0.1, 0.1)][al]
	_alarm_lamp.albedo_color = acol
	_alarm_lamp.emission_enabled = true
	_alarm_lamp.emission = acol
	_duct_lever.rotation_degrees.z = 0.0 if s.press["duct"] else 90.0
	var rows: Array = []
	for c in ["A", "BC", "B03", "B04", "B08"]:
		var tag: String = "" if c == "A" or c == "BC" else (" ISO" if not s.hatch_open(c) else "")
		rows.append("%-4s %5.1f %+5.2f%s" % [c, s.pressure(c), s.trend(c), tag])
	_pcp.text = "%s   kPa  /min\n%s\nMAKEUP %.2f  RES %d%%\nDUCT %s" % [s.alarm_word(al), "\n".join(rows), float(s.press["makeup_flow"]), int(100.0 * float(s.press["makeup"]) / 26000.0), "OPEN" if s.press["duct"] else "SHUT"]
	for id in _site:
		var lk: Dictionary = s.leak(id)
		var st: String = String(lk.get("state", "none"))
		var leaking: bool = st == "active" or st == "temp"
		_site[id]["mark"].visible = leaking
		_site[id]["temp"].visible = st == "temp"
		_site[id]["fixed"].visible = st == "repaired"


# ------------------------------------------------------------ L09 order
func task_rearm(t: StringName, seed: int) -> void:
	if t != &"l09_pressure":
		return
	var s: Node = _net()
	ident = ""
	ident_how = ""
	pcp_read = false
	iso_verified = false
	logged = ""
	fixed_by = ""
	hold = {}
	leak_id = ""
	if s == null:
		return
	# The defect this order is about: the real one the network has (a
	# raise from a live fault), else the developer / a story raise injects
	# one from the order's seed (Cargo's seal and the B-04 hull only once
	# those rooms are open to the technician).
	var best := ""
	var q := -1.0
	for lk in s.active_leaks():
		if String(lk["comp"]) in ["B03", "B04", "B08"]:
			var lq: float = s.leak_c(lk) * s.pressure(String(lk["comp"])) + (0.0 if String(lk["state"]) == "active" else 0.001)
			if lq > q:
				q = lq
				best = String(lk["id"])
	if best == "":
		var clr: Node = get_tree().get_first_node_in_group(&"clearance")
		var tier: int = int(clr.deck_b_tier()) if clr != null and clr.has_method("deck_b_tier") else 1
		var pool: Array = ["b03_feed"] + (["b08_seal", "hull_b04"] if tier >= 2 else [])
		best = pool[absi(seed) % pool.size()]
		s.inject_leak(best, 1 + absi(seed / 7) % 3)
	leak_id = best


func task_done(t: StringName) -> bool:
	if t != &"l09_pressure":
		return true
	var s: Node = _net()
	if s == null or leak_id == "":
		return false
	var lk: Dictionary = s.leak(leak_id)
	var c: String = String(lk.get("comp", "B03"))
	var st: String = String(lk.get("state", "repaired"))
	if st == "repaired":
		var h: Dictionary = hold.get(c, {})
		if h.get("state", "") == "pass" and s.hatch_open(c) and s.pressure(c) > 99.0:
			close_task(t, "repaired", "%s (%s)" % [_comp_word(c), _site_name(leak_id)], String(lk.get("kind", "")) + " leak", fixed_by if fixed_by != "" else "repaired", "hold test %+.2f kPa/min; hatch reopened" % float(h.get("rate", 0.0)))
			return true
		return false
	if logged != "":
		var action: String = fixed_by if logged == "stabilized" else "compartment isolated (hatch shut, EQ shut)"
		close_task(t, logged, "%s (%s)" % [_comp_word(c), _site_name(leak_id)], String(lk.get("kind", "")) + " leak", action,
			"station volume holding %+.2f kPa/min; located by %s" % [s.trend("BC"), ident_how if ident_how != "" else "—"])
		if String(lk.get("kind", "")) == "hull" and _dp != null and not _dp.has_open_order(&"a06_hull"):
			_dp.raise_order(&"a06_hull", "B-04 hull penetration — permanent repair needs EVA")
		return true
	return false


func task_next(t: StringName) -> Dictionary:
	if t != &"l09_pressure":
		return {}
	var s: Node = _net()
	var lk: Dictionary = s.leak(leak_id) if s != null else {}
	var c: String = String(lk.get("comp", "B03"))
	var st: String = String(lk.get("state", "active"))
	if not pcp_read:
		return next("Lower Junction PCP-B: read every volume's pressure and trend", "READ PCP-B")
	if st == "repaired":
		var h: Dictionary = hold.get(c, {})
		if s.pressure(c) < 99.0:
			return next("%s: open the EQ valve and bring it back to station pressure" % c.replace("B0", "B-0"), "REPRESSURISE")
		if h.get("state", "") != "pass":
			return next("%s: shut the hatch and EQ, run the pressure-hold test" % c.replace("B0", "B-0"), "HOLD TEST")
		return next("%s: reopen the hatch (the compartment rejoins the station)" % c.replace("B0", "B-0"), "OPEN HATCH")
	if ident == "":
		return next("Find the leaking compartment: shut one hatch at a time and watch which side falls — or follow the hiss with the leak detector (Life Support rack)", "FIND LEAK")
	if not bool(lk.get("found", false)) and st == "active" and s.hatch_open(c):
		return next("Pin the defect with the leak detector in %s" % _comp_word(c), "LOCATE")
	if st == "active" and s.hatch_open(c):
		return next("Stabilise: clamp a temporary patch (LEAK KIT) or shut the %s hatch" % c.replace("B0", "B-0"), "STABILISE")
	if String(lk.get("kind", "")) != "hull" and _have_part(SITES[leak_id][2]):
		return next("Repair %s (%s from the LEAK KIT) — or log the status at PCP-B to defer" % [_site_name(leak_id), Part.KINDS[SITES[leak_id][2]]["name"]], "REPAIR")
	return next("PCP-B: LOG STATUS (stabilised / deferred) — the station must be holding", "LOG STATUS")


func _have_part(kind: StringName) -> bool:
	if kind == &"":
		return false
	for p in get_tree().get_nodes_in_group(&"deck_b_part"):
		if p.get("item_id") == kind:
			return true
	return false


func task_progress(t: StringName) -> String:
	if t != &"l09_pressure":
		return ""
	var s: Node = _net()
	if s == null:
		return ""
	return "%s · source %s · %s" % [s.alarm_word(int(s.press["alarm"])), _comp_word(ident) if ident != "" else "unknown", String(s.leak(leak_id).get("state", "—"))]


func task_detail(t: StringName) -> Array:
	if t != &"l09_pressure":
		return []
	var s: Node = _net()
	var lk: Dictionary = s.leak(leak_id) if s != null else {}
	return ["Station %s, Deck B %.1f kPa (%+.2f/min)" % [s.alarm_word(int(s.press["alarm"])), s.pressure("BC"), s.trend("BC")] if s != null else "",
		"Source: %s%s" % [_comp_word(ident) if ident != "" else "not yet found", (" (by %s)" % ident_how) if ident_how != "" else ""],
		"Defect: %s" % (String(lk.get("state", "")) if bool(lk.get("found", false)) else "not located"),
		"Stabilise = isolate or temporary patch. Repair = defect gone + hold test."]


func task_severity(t: StringName) -> int:
	var s: Node = _net()
	return 3 if t == &"l09_pressure" and s != null and int(s.press["alarm"]) >= 2 else 2


func task_feasible(_t: StringName) -> bool:
	return true                    # isolation + deferral always exists


func state_dict() -> Dictionary:
	return {"outcome": outcome.duplicate(), "ident": ident, "ident_how": ident_how, "pcp_read": pcp_read, "iso_verified": iso_verified, "leak_id": leak_id,
		"hold": hold.duplicate(true), "logged": logged, "fixed_by": fixed_by}


func load_dict(d: Dictionary) -> void:
	outcome = d.get("outcome", {})
	ident = String(d.get("ident", ""))
	ident_how = String(d.get("ident_how", ""))
	pcp_read = bool(d.get("pcp_read", false))
	iso_verified = bool(d.get("iso_verified", false))
	leak_id = String(d.get("leak_id", ""))
	hold = d.get("hold", {})
	for c in hold:
		if hold[c].get("state", "") == "running":
			hold[c]["state"] = "aborted"     # a test never resumes half-way
	logged = String(d.get("logged", ""))
	fixed_by = String(d.get("fixed_by", ""))
	var s: Node = _net()
	if s != null:
		for c in HATCHES:
			_leaf[c]["x"] = 1.0 if s.hatch_open(c) else 0.0
	_refresh()
