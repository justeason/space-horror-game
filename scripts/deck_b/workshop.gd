extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-04 FABRICATION AND REPAIR WORKSHOP (not a magic factory).
##   workbench   a vise (clamp lever), a magnifier lamp, a precision driver,
##               the part on the bench with its cover screws and three real
##               sub-components; spare-subcomponent drawers;
##   test bench  fixture (receptacle), + / − / SIG terminals and two leads,
##               a range selector (5 / 12 / 24 V), limited test power, a
##               readout; SERVICEABLE (green) and REPAIR (red) trays;
##   torque      a mounting plate with four bolts on a stand, a torque
##               driver (12 N·m) and a feeler-gauge gap indicator;
##   fabricator  bed-level knobs (three corners) with probe offsets, a
##               template selector (flight-critical parts locked out), a
##               material spool, an output tray and the magnifier check;
##   tool board  the torque driver's calibration check against the
##               reference, the multimeter self-test and its spare leads.
## Components keep their authoritative instance state (payload: condition,
## grade, calibrated, state, history) -- a reconditioned part leaves here a
## serviceable part; a failed one goes to the REPAIR tray.
## Tasks: b04_bench, b04_reassembly, b04_torque, b04_fab, b04_tools,
## b04_recondition (chained from Thermal / Water / Cargo).

const SUBS := {&"valve_actuator": ["SEAL", "SPRING", "GEAR"], &"bearing_cartridge": ["SEAL", "BALLS", "RACE"]}
const RANGES := [5, 12, 24]
const TEMPLATES := ["BRACKET", "CABLE GUIDE", "COVER CLIP", "EVA SUIT PART"]
const TPL_KIND := {"BRACKET": &"bracket", "CABLE GUIDE": &"cable_guide", "COVER CLIP": &"bracket"}
# Bench test
var fix_kind: StringName = &""
var fix_payload: Dictionary = {}
var leads: Array = ["", ""]           # terminal for lead A / B: "+" "-" "SIG"
var rng_i: int = 0
var powered: bool = false
var reading: String = ""
var verdict: String = ""             # "" | pass | fail (player's call)
var bench_truth: bool = true          # the part really passes
var bench_sorted: bool = false
# Reassembly (vise)
var vise_kind: StringName = &""
var vise_payload: Dictionary = {}
var vise_clamped: bool = false
var screws: Array = [true, true, true, true]
var cover_on: bool = true
var sub_state: Array = ["ok", "ok", "ok"]   # ok | worn | out | new
var sub_seen: Array = [false, false, false]
var picked_sub: String = ""
var assembly_tested: bool = false
var reasm_type: StringName = &""
# Torque
var bolt_t: Array = [0, 0, 0, 0]      # 0 / 50 / 100 (%) ; -1 = over
var final_order: Array = []
var gap_uneven: bool = false
var torque_verified: bool = false
# Fabricator
var bed_off: Array = [0.0, 0.0, 0.0]
var tpl: int = 0
var spool: float = 0.62
var printing: float = -1.0
var printed_ok: bool = false
var inspected: bool = false
var fab_started_ok: bool = false
# Tools
var td_offset: float = 0.0            # torque-driver error (fraction)
var td_checked: bool = false
var mm_leads_ok: bool = true
var mm_tested: bool = false
var crimper_seen: bool = false

var _vise_jaw: Node3D
var _vise_part: Node3D
var _cover: MeshInstance3D
var _screw_nodes: Array = []
var _sub_nodes: Array = []
var _fix_part: Node3D
var _lead_lbl: Label3D
var _bench_lbl: Label3D
var _range_knob: Node3D
var _bolt_nodes: Array = []
var _gap: Label3D
var _fab_lbl: Label3D
var _fab_head: Node3D
var _tool_lbl: Label3D
var _inbox: Rack
var _trays := {}
var _out_tray: Rack
var _fab_loop: AudioStreamPlayer3D
var _spare_drawer: Rack


func _ready() -> void:
	_room_ready([&"b04_bench", &"b04_reassembly", &"b04_torque", &"b04_fab", &"b04_tools", &"b04_recondition"])
	_build_bench()
	_build_test_bench()
	_build_torque()
	_build_fabricator()
	_build_tool_board()
	text("B-04  FABRICATION & REPAIR", Vector3(-3.9, L.FLOOR_Y + 2.75, 3.12), 20, Color(1.0, 0.97, 0.9))
	_refresh()


# ------------------------------------------------------------- geometry
func _build_bench() -> void:
	var b := Node3D.new()
	b.name = "Workbench"
	b.position = Vector3(-5.2, L.FLOOR_Y, 4.6)
	b.rotation_degrees.y = 90.0          # the worker faces -x (the wall)
	add_child(b)
	dbox(Vector3(2.0, 0.05, 0.6), Vector3(0, 0.9, 0), Color(0.5, 0.48, 0.42), b, 0.2, true)
	dbox(Vector3(2.0, 0.85, 0.5), Vector3(0, 0.43, 0.04), Color(0.32, 0.34, 0.36), b, 0.4, true)
	for k in 4:
		dbox(Vector3(0.45, 0.16, 0.02), Vector3(-0.72 + k * 0.48, 0.62, -0.215), Color(0.42, 0.44, 0.46), b)
	# Task light over the bench.
	var tl := dbox(Vector3(0.6, 0.04, 0.12), Vector3(0, 1.75, 0.18), Color(0.9, 0.9, 0.86), b)
	glow(tl, Color(1.0, 0.97, 0.9), 1.4)
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 1.72, 0.18)
	lamp.rotation_degrees.x = -90.0
	lamp.spot_angle = 50.0
	lamp.spot_range = 1.4
	lamp.light_energy = 1.6
	b.add_child(lamp)
	# Vise.
	var v := Node3D.new()
	v.position = Vector3(-0.55, 0.93, 0.05)
	b.add_child(v)
	dbox(Vector3(0.24, 0.08, 0.14), Vector3(0, 0.04, 0), Color(0.25, 0.4, 0.6), v, 0.6)
	dbox(Vector3(0.04, 0.12, 0.14), Vector3(-0.1, 0.12, 0), Color(0.25, 0.4, 0.6), v, 0.6)
	_vise_jaw = Node3D.new()
	_vise_jaw.position = Vector3(0.1, 0.12, 0)
	v.add_child(_vise_jaw)
	dbox(Vector3(0.04, 0.12, 0.14), Vector3.ZERO, Color(0.25, 0.4, 0.6), _vise_jaw, 0.6)
	text("VISE", Vector3(0, 0.03, 0.075), 8, Color(0.95, 0.95, 0.9), v)
	part(&"vise", Vector3(0.28, 0.2, 0.18), Vector3(0, 0.12, 0), v)
	part(&"vise_lever", Vector3(0.08, 0.08, 0.08), Vector3(0.16, 0.06, 0.09), v)
	_vise_part = Node3D.new()
	_vise_part.position = Vector3(0, 0.16, 0)
	v.add_child(_vise_part)
	dbox(Vector3(0.12, 0.08, 0.1), Vector3.ZERO, Color(0.3, 0.33, 0.36), _vise_part)
	_cover = dbox(Vector3(0.13, 0.015, 0.11), Vector3(0, 0.048, 0), Color(0.55, 0.57, 0.6), _vise_part)
	for k in 4:
		var sn := dcyl(0.006, 0.01, Vector3(-0.05 + (k % 2) * 0.1, 0.06, -0.04 + int(k / 2) * 0.08), Color(0.8, 0.8, 0.82), _vise_part)
		_screw_nodes.append(sn)
		part(StringName("screw%d" % k), Vector3(0.035, 0.035, 0.035), Vector3(-0.05 + (k % 2) * 0.1, 0.06, -0.04 + int(k / 2) * 0.08), _vise_part)
	for k in 3:
		var sn2 := dcyl(0.012, 0.03, Vector3(-0.035 + k * 0.035, 0.03, 0), Color(0.7, 0.7, 0.72), _vise_part)
		_sub_nodes.append(sn2)
		part(StringName("sub%d" % k), Vector3(0.03, 0.04, 0.05), Vector3(-0.035 + k * 0.035, 0.03, 0), _vise_part)
	part(&"cover", Vector3(0.14, 0.03, 0.12), Vector3(0, 0.05, 0), _vise_part)
	# Magnifier lamp.
	var mg := dcyl(0.05, 0.01, Vector3(-0.3, 1.25, 0.05), Color(0.8, 0.9, 1.0), b, Vector3(60, 0, 0), 0.1)
	glow(mg, Color(0.6, 0.7, 0.8), 0.4)
	part(&"magnifier", Vector3(0.12, 0.08, 0.12), Vector3(-0.3, 1.25, 0.05), b)
	# Spare-subcomponent drawer (three compartments).
	for k in 3:
		var dname: String = ["SEALS", "SPRINGS / BALLS", "GEARS / RACES"][k]
		text(dname, Vector3(-0.72 + k * 0.48, 0.66, -0.23), 8, Color(0.95, 0.95, 0.9), b, 180.0)
		part(StringName("drawer%d" % k), Vector3(0.44, 0.16, 0.05), Vector3(-0.72 + k * 0.48, 0.62, -0.24), b)
	# Inbox rack (parts to work on) at the bench's north end.
	_inbox = rack("BenchInbox", Vector3(-5.3, L.FLOOR_Y + 0.98, 5.45), 2, 0.16, [], "BENCH INBOX", self, 90.0)
	text("WORKBENCH", Vector3(-5.48, L.FLOOR_Y + 1.6, 4.6), 12, Color(0.95, 0.95, 0.9), self, 90.0)


func _build_test_bench() -> void:
	var t := Node3D.new()
	t.name = "TestBench"
	t.position = Vector3(-5.2, L.FLOOR_Y + 0.93, 3.75)
	t.rotation_degrees.y = 90.0
	add_child(t)
	dbox(Vector3(0.22, 0.06, 0.16), Vector3(0, 0.03, 0), Color(0.15, 0.16, 0.18), t)
	_fix_part = Node3D.new()
	_fix_part.position = Vector3(0, 0.08, 0)
	t.add_child(_fix_part)
	dbox(Vector3(0.08, 0.05, 0.1), Vector3.ZERO, Color(0.2, 0.22, 0.25), _fix_part)
	part(&"fixture", Vector3(0.22, 0.1, 0.18), Vector3(0, 0.06, 0), t)
	for k in 3:
		var term: String = ["+", "-", "SIG"][k]
		var p := Vector3(-0.08 + k * 0.08, 0.07, 0.1)
		dcyl(0.012, 0.02, p, [Color(0.9, 0.2, 0.15), Color(0.1, 0.1, 0.1), Color(0.9, 0.8, 0.2)][k], t, Vector3(90, 0, 0))
		text(term, p + Vector3(0, 0.03, 0.01), 9, Color(0.95, 0.95, 0.9), t)
		part(StringName("term%d" % k), Vector3(0.05, 0.05, 0.05), p, t)
	var psu := Node3D.new()
	psu.position = Vector3(0.3, 0.12, 0.0)
	t.add_child(psu)
	dbox(Vector3(0.26, 0.2, 0.18), Vector3.ZERO, Color(0.85, 0.86, 0.88), psu)
	_bench_lbl = readout(Vector3(0, 0.04, 0.091), Vector2(0.22, 0.09), psu, 9)
	_range_knob = Node3D.new()
	_range_knob.position = Vector3(-0.07, -0.06, 0.095)
	psu.add_child(_range_knob)
	dcyl(0.02, 0.02, Vector3.ZERO, Color(0.1, 0.1, 0.11), _range_knob, Vector3(90, 0, 0))
	dbox(Vector3(0.004, 0.018, 0.008), Vector3(0, 0.009, 0.01), Color(0.95, 0.95, 0.9), _range_knob)
	part(&"range", Vector3(0.05, 0.05, 0.04), Vector3(-0.07, -0.06, 0.1), psu)
	button("power", Vector3(0.02, -0.06, 0.092), Color(0.95, 0.3, 0.2), psu, Vector3(0.04, 0.03, 0.012))
	button("pass", Vector3(0.07, -0.06, 0.092), Color(0.3, 0.9, 0.4), psu, Vector3(0.03, 0.025, 0.012))
	button("fail", Vector3(0.105, -0.06, 0.092), Color(0.95, 0.5, 0.15), psu, Vector3(0.03, 0.025, 0.012))
	part(&"release", Vector3(0.08, 0.06, 0.06), Vector3(0, 0.14, 0), t)
	_lead_lbl = text("", Vector3(0.0, 0.2, 0.1), 8, Color(0.95, 0.95, 0.9), t)
	text("TEST BENCH · LIMITED TEST POWER", Vector3(0.15, 0.36, 0.0), 9, Color(0.95, 0.95, 0.9), t)
	_trays["serviceable"] = rack("TrayServiceable", Vector3(-2.45, L.FLOOR_Y + 1.0, 3.25), 3, 0.15, [], "SERVICEABLE", self, -90.0)
	_trays["repair"] = rack("TrayRepair", Vector3(-2.45, L.FLOOR_Y + 1.0, 3.85), 3, 0.15, [], "REPAIR QUEUE", self, -90.0)
	_spare_drawer = rack("WorkshopStock", Vector3(-2.45, L.FLOOR_Y + 1.5, 3.25), 4, 0.15, [], "WORKSHOP STOCK", self, -90.0)
	spawn_part.call_deferred(&"relay_module", _spare_drawer)
	spawn_part.call_deferred(&"bearing_cartridge", _spare_drawer)


func _build_torque() -> void:
	var t := Node3D.new()
	t.name = "TorqueStand"
	t.position = Vector3(-2.55, L.FLOOR_Y, 4.95)
	t.rotation_degrees.y = -90.0
	add_child(t)
	dbox(Vector3(0.4, 0.95, 0.3), Vector3(0, 0.475, 0), Color(0.3, 0.32, 0.34), t, 0.5, true)
	dbox(Vector3(0.3, 0.02, 0.22), Vector3(0, 0.96, 0), Color(0.6, 0.62, 0.65), t, 0.7)
	for k in 4:
		var ang: float = PI * 0.25 + k * PI * 0.5
		var p := Vector3(cos(ang) * 0.1, 0.98, sin(ang) * 0.07)
		var bn := Node3D.new()
		bn.position = p
		t.add_child(bn)
		dcyl(0.012, 0.03, Vector3.ZERO, Color(0.75, 0.75, 0.77), bn, Vector3.ZERO, 0.9)
		_bolt_nodes.append(bn)
		text(str(k + 1), p + Vector3(0, 0.03, 0.02), 9, Color(0.95, 0.85, 0.2), t)
		part(StringName("tbolt%d" % k), Vector3(0.04, 0.04, 0.04), p, t)
	_gap = readout(Vector3(0, 1.15, 0.12), Vector2(0.24, 0.1), t, 9)
	button("backoff", Vector3(-0.08, 1.04, 0.12), Color(0.95, 0.6, 0.15), t, Vector3(0.04, 0.025, 0.012))
	button("tverify", Vector3(0.08, 1.04, 0.12), Color(0.3, 0.9, 0.4), t, Vector3(0.04, 0.025, 0.012))
	text("BACK OFF     VERIFY", Vector3(0, 1.0, 0.13), 7, Color(0.95, 0.95, 0.9), t)
	text("TORQUE 12 N·m · CROSS PATTERN", Vector3(0, 1.28, 0.0), 9, Color(0.95, 0.95, 0.9), t)


func _build_fabricator() -> void:
	var f := Node3D.new()
	f.name = "Fabricator"
	f.position = Vector3(-4.0, L.FLOOR_Y, 3.42)
	add_child(f)
	dbox(Vector3(0.7, 1.1, 0.55), Vector3(0, 0.55, 0), Color(0.82, 0.83, 0.85), f, 0.3, true)
	dbox(Vector3(0.5, 0.4, 0.02), Vector3(0, 0.75, 0.28), Color(0.2, 0.25, 0.3), f, 0.1)
	_fab_head = Node3D.new()
	_fab_head.position = Vector3(0, 0.85, 0.2)
	f.add_child(_fab_head)
	dbox(Vector3(0.06, 0.05, 0.06), Vector3.ZERO, Color(0.9, 0.5, 0.15), _fab_head)
	_fab_lbl = readout(Vector3(0.0, 1.2, 0.28), Vector2(0.5, 0.14), f, 9)
	for k in 3:
		var x: float = -0.2 + k * 0.2
		handwheel("bed%d" % k, Vector3(x, 0.38, 0.29), 0.035, f, true, Color(0.2, 0.45, 0.75))
		text(["BED L", "BED C", "BED R"][k], Vector3(x, 0.3, 0.29), 7, Color(0.1, 0.1, 0.1), f)
	part(&"tpl", Vector3(0.12, 0.06, 0.04), Vector3(0.28, 1.05, 0.29), f)
	button("fab_start", Vector3(0.28, 0.98, 0.285), Color(0.3, 0.8, 0.95), f, Vector3(0.05, 0.03, 0.012))
	text("TEMPLATE ▸\nSTART", Vector3(0.28, 1.02, 0.29), 7, Color(0.1, 0.1, 0.1), f)
	_out_tray = rack("FabOutput", Vector3(-3.6, L.FLOOR_Y + 0.62, 3.73), 2, 0.14, [], "OUTPUT", self, 0.0)
	part(&"fab_inspect", Vector3(0.3, 0.1, 0.12), Vector3(-3.53, L.FLOOR_Y + 0.62, 3.73))
	_fab_loop = machine_loop(loop_stream(1.0, func(t, i): return sin(TAU * 220.0 * t) * 0.08 * (0.5 + 0.5 * sin(TAU * 4.0 * t)) + sin(TAU * 880.0 * t) * 0.04 + (fmod(sin(float(i) * 12.9) * 43758.5453, 1.0) - 0.5) * 0.04), Vector3(-4.0, L.FLOOR_Y + 0.8, 3.42), -14.0)
	text("SMALL-PARTS FABRICATOR · NON-CRITICAL PARTS ONLY", Vector3(-4.0, L.FLOOR_Y + 1.42, 3.71), 9, Color(0.1, 0.1, 0.1))


func _build_tool_board() -> void:
	var tb := Node3D.new()
	tb.name = "ToolBoard"
	tb.position = Vector3(-4.6, L.FLOOR_Y + 1.6, 6.29)
	tb.rotation_degrees.y = 180.0
	add_child(tb)
	dbox(Vector3(1.4, 0.7, 0.03), Vector3(0, 0, 0.015), Color(0.25, 0.27, 0.3), tb)
	var names := ["TORQUE DRIVER", "MULTIMETER", "CRIMPER", "PRECISION DRIVER", "REF. TORQUE"]
	for k in names.size():
		var x: float = -0.56 + k * 0.28
		dbox(Vector3(0.05, 0.2, 0.03), Vector3(x, 0.05, 0.045), [Color(0.85, 0.2, 0.15), Color(0.95, 0.75, 0.1), Color(0.2, 0.4, 0.75), Color(0.15, 0.15, 0.16), Color(0.6, 0.6, 0.62)][k], tb)
		text(names[k], Vector3(x, -0.12, 0.035), 7, Color(0.95, 0.95, 0.9), tb)
		part(StringName("tool%d" % k), Vector3(0.12, 0.3, 0.06), Vector3(x, 0.03, 0.05), tb)
	_tool_lbl = readout(Vector3(0.0, 0.29, 0.035), Vector2(0.9, 0.08), tb, 9)
	button("td_adjust", Vector3(0.62, -0.22, 0.035), Color(0.95, 0.6, 0.15), tb, Vector3(0.05, 0.03, 0.012))
	text("ADJUST\nCAL", Vector3(0.62, -0.28, 0.035), 7, Color(0.95, 0.95, 0.9), tb)
	part(&"mm_leads", Vector3(0.12, 0.08, 0.06), Vector3(0.62, 0.15, 0.05), tb)
	text("SPARE\nLEADS", Vector3(0.62, 0.22, 0.035), 7, Color(0.95, 0.95, 0.9), tb)
	# Scrap container.
	dbox(Vector3(0.4, 0.5, 0.35), Vector3(-5.2, L.FLOOR_Y + 0.25, 3.35), Color(0.3, 0.35, 0.3), self, 0.3, true)
	text("SCRAP", Vector3(-5.2, L.FLOOR_Y + 0.52, 3.53), 10, Color(0.95, 0.95, 0.9))
	part(&"scrap", Vector3(0.4, 0.2, 0.35), Vector3(-5.2, L.FLOOR_Y + 0.55, 3.35))


# --------------------------------------------------------------- clicks
func on_part(id: StringName) -> void:
	var sid: String = String(id)
	if sid.begins_with("bed") and (sid.ends_with("_up") or sid.ends_with("_dn")):
		var k: int = int(sid.substr(3, 1))
		bed_off[k] = snappedf(float(bed_off[k]) + (0.025 if sid.ends_with("_up") else -0.025), 0.005)
		sfx(&"click")
		say("Bed %s probe offset %+.3f mm" % [["L", "C", "R"][k], float(bed_off[k])])
		_refresh()
		return
	match sid:
		"vise_lever":
			if vise_kind == &"":
				say("Nothing in the vise.")
				return
			vise_clamped = not vise_clamped
			sfx(&"ratchet")
		"cover":
			_cover_click()
		"magnifier":
			if vise_kind != &"" and not cover_on:
				for k in 3:
					sub_seen[k] = true
				var worn: Array = []
				for k in 3:
					if sub_state[k] == "worn":
						worn.append(SUBS[vise_kind][k])
				say("Magnifier: %s" % ("worn / cracked: " + ", ".join(worn) if not worn.is_empty() else "all sub-components sound"))
			elif _out_tray.count() > 0:
				_inspect_output()
			else:
				say("Magnifier: nothing under it.")
		"range":
			rng_i = (rng_i + 1) % RANGES.size()
			powered = false
			sfx(&"click")
		"power":
			_bench_power()
		"pass", "fail":
			_bench_verdict(sid == "pass")
		"release":
			_release_fixture()
		"backoff":
			bolt_t = [0, 0, 0, 0]
			final_order = []
			gap_uneven = false
			torque_verified = false
			sfx(&"ratchet")
			say("All four bolts backed off.")
		"tverify":
			if bolt_t.all(func(v): return v == 100) and not gap_uneven:
				torque_verified = true
				sfx(&"success")
				say("Torque verified: 12 N·m ×4, gap even.")
			else:
				say("Not verifiable: %s" % ("gap uneven — back off and redo in a cross pattern" if gap_uneven else ("over-torqued bolt" if bolt_t.has(-1) else "bolts not at final torque")))
				sfx(&"fail")
		"tpl":
			tpl = (tpl + 1) % TEMPLATES.size()
			sfx(&"click")
		"fab_start":
			_fab_start()
		"fab_inspect":
			_inspect_output()
		"td_adjust":
			if td_checked and absf(td_offset) > 0.04:
				td_offset = 0.0
				sfx(&"ratchet")
				say("Torque driver adjusted to the reference. Check again.")
				td_checked = false
			else:
				say("Check the driver against the reference first.")
		"mm_leads":
			if not mm_leads_ok:
				mm_leads_ok = true
				sfx(&"click")
				say("Multimeter leads replaced. Self-test again.")
		"scrap":
			var h: Node3D = held()
			if h != null and String(h.payload.get("state", "")) in ["spent", "failed"] or (h != null and h.item_id == &"mf_bed_spent"):
				consume_part(h)
				sfx(&"clunk")
				say("Scrapped.")
			else:
				say("Scrap container (spent / failed parts only).")
		_:
			if sid.begins_with("screw"):
				_screw(int(sid.substr(5)))
			elif sid.begins_with("sub"):
				_sub(int(sid.substr(3)))
			elif sid.begins_with("drawer"):
				var dk: int = int(sid.substr(6))
				picked_sub = SUBS[vise_kind][dk] if SUBS.has(vise_kind) else ["SEAL", "SPRING", "GEAR"][dk]
				say("Taken from the drawer: new %s." % picked_sub)
				sfx(&"click")
			elif sid.begins_with("term"):
				_lead(int(sid.substr(4)))
			elif sid.begins_with("tbolt"):
				_torque(int(sid.substr(5)))
			elif sid.begins_with("tool"):
				_tool(int(sid.substr(4)))
	_refresh()


func _cover_click() -> void:
	if vise_kind == &"":
		return
	if not vise_clamped:
		say("Clamp the part in the vise first.")
		return
	if cover_on:
		if screws.any(func(v): return v):
			say("Remove the four cover screws first (precision driver).")
			return
		cover_on = false
		sfx(&"click")
		say("Cover off. Inspect the sub-components (magnifier).")
	else:
		if sub_state.has("out"):
			say("The cover won't seat — the %s isn't in." % SUBS[vise_kind][sub_state.find("out")])
			sfx(&"fail")
			return
		cover_on = true
		sfx(&"click")
		say("Cover on. Refit the four screws.")


func _screw(k: int) -> void:
	if vise_kind == &"" or not vise_clamped:
		say("Clamp the part first.")
		return
	if screws[k]:
		screws[k] = false
		sfx(&"ratchet")
	elif cover_on:
		screws[k] = true
		sfx(&"ratchet")
	else:
		say("Put the cover on before refitting screws.")


func _sub(k: int) -> void:
	if vise_kind == &"" or cover_on:
		return
	if sub_state[k] == "worn":
		sub_state[k] = "out"
		sfx(&"click")
		say("%s removed (worn)." % SUBS[vise_kind][k])
	elif sub_state[k] == "out":
		if picked_sub == "":
			say("Take a new %s from the drawer." % SUBS[vise_kind][k])
			return
		if picked_sub != SUBS[vise_kind][k]:
			say("A %s doesn't fit the %s seat." % [picked_sub, SUBS[vise_kind][k]])
			sfx(&"fail")
			return
		sub_state[k] = "new"
		picked_sub = ""
		sfx(&"latch")
		say("New %s fitted." % SUBS[vise_kind][k])
	else:
		say("%s sound." % SUBS[vise_kind][k])


func _lead(term: int) -> void:
	var t: String = ["+", "-", "SIG"][term]
	if leads[0] == t or leads[1] == t:
		if leads[0] == t:
			leads[0] = ""
		else:
			leads[1] = ""
	elif leads[0] == "":
		leads[0] = t
	elif leads[1] == "":
		leads[1] = t
	else:
		say("Both leads are connected (click a terminal to remove its lead).")
		return
	powered = false
	sfx(&"click")


func _need_terms() -> Array:
	return ["+", "-"] if fix_kind in [&"relay_module", &"valve_actuator", &"bearing_cartridge"] else ["+", "SIG"]


func _need_range() -> int:
	return 0 if fix_kind == &"coolant_sensor" else 2


func _bench_power() -> void:
	if fix_kind == &"":
		say("Put a component in the fixture first.")
		return
	var need: Array = _need_terms()
	if not (leads.has(need[0]) and leads.has(need[1])):
		say("No reading — check the lead placement (%s: %s / %s)." % [Part.KINDS[fix_kind]["name"], need[0], need[1]])
		sfx(&"fail")
		return
	if rng_i != _need_range():
		say("Over/under range: test PSU limited at %d V; this part is rated %d V. Select its range." % [RANGES[rng_i], RANGES[_need_range()]])
		sfx(&"fail")
		return
	powered = true
	sfx(&"click")
	match fix_kind:
		&"relay_module":
			reading = "COIL 41 mA\nCONTACTS 18 mΩ" if bench_truth else "COIL 40 mA\nCONTACTS 186 mΩ"
		&"coolant_sensor":
			reading = "OUT 1.62 V @20 °C" if bench_truth else "OUT 1.31 V @20 °C\nDRIFT"
		_:
			reading = "TRAVEL 0-100 %% %s" % ("SMOOTH" if bench_truth else "STICKS 40 %")
	say("Reading: " + reading.replace("\n", " · "))


func _bench_verdict(pass_btn: bool) -> void:
	if not powered or reading == "":
		say("Take a reading first.")
		return
	verdict = "pass" if pass_btn else "fail"
	fix_payload["state"] = "serviceable" if pass_btn else "repair"
	fix_payload["calibrated"] = pass_btn
	sfx(&"click")
	say("Logged %s. Release the part and put it on the %s tray." % [verdict.to_upper(), "SERVICEABLE" if pass_btn else "REPAIR QUEUE"])


func _release_fixture() -> void:
	if fix_kind == &"" or held() != null:
		return
	if verdict == "":
		say("Log PASS / FAIL before releasing the part.")
		return
	var p: Node3D = spawn_part(fix_kind, null, fix_payload)
	p.global_position = _fix_part.global_position
	var c: Node = _carry()
	if c != null:
		c.pick_up(p)
	fix_kind = &""
	fix_payload = {}
	powered = false
	reading = ""
	leads = ["", ""]
	sfx(&"click")


func _torque(k: int) -> void:
	if bolt_t[k] == -1:
		say("Bolt %d over-torqued — back off and redo." % (k + 1))
		return
	if bolt_t[k] == 100:
		bolt_t[k] = -1
		sfx(&"fail")
		say("Clicked past final torque: bolt %d OVER-TORQUED. Back off all bolts and redo." % (k + 1))
		return
	if bolt_t[k] == 50 and not bolt_t.all(func(v): return v >= 50 or v == -1):
		say("Snug all four first, then final torque.")
		return
	bolt_t[k] += 50
	sfx(&"ratchet")
	if bolt_t[k] == 100:
		# Cross pattern on a square plate: finals go in DIAGONAL pairs
		# (1-3, then 2-4): the second bolt of each pair must be opposite
		# the first, or the plate is pulled down unevenly.
		final_order.append(k)
		var i: int = final_order.size() - 1
		if i % 2 == 1 and absi(int(final_order[i - 1]) - k) != 2:
			gap_uneven = true


func _tool(k: int) -> void:
	match k:
		0, 4:
			td_checked = true
			var got: float = 12.0 * (1.0 + td_offset)
			say("Torque driver vs reference: %.1f N·m at 12.0 set (tolerance ±4 %%) %s" % [got, "OUT OF CAL" if absf(td_offset) > 0.04 else "OK"])
		1:
			mm_tested = true
			say("Multimeter self-test: %s" % ("LEAD OPEN — replace the leads" if not mm_leads_ok else "PASS (continuity 0.2 Ω)"))
		2:
			crimper_seen = true
			say("Crimper: jaws aligned, ratchet releases. OK.")
		3:
			say("Precision driver set: complete.")


func _fab_start() -> void:
	if printing >= 0.0:
		return
	if TEMPLATES[tpl] == "EVA SUIT PART":
		say("REFUSED: flight-critical / pressure-suit parts are not certified for local fabrication.")
		sfx(&"fail")
		return
	if spool < 0.04:
		say("Material spool empty — restock from cargo.")
		sfx(&"fail")
		return
	if _out_tray.free_slot() == -1:
		say("Output tray full.")
		return
	fab_started_ok = bed_off.all(func(v): return absf(float(v)) <= 0.05)
	printing = 0.0
	spool -= 0.04
	sfx(&"click")
	say("Fabricating %s (10 s)…" % TEMPLATES[tpl])


func _inspect_output() -> void:
	var items: Array = _out_tray.items()
	if items.is_empty():
		say("Output tray empty.")
		return
	var it: Node3D = items.back()
	inspected = true
	var ok: bool = String(it.payload.get("state", "")) == "serviceable"
	say("Magnifier: %s" % ("clean layers, dimensions in tolerance — PASS." if ok else "layer shift / warped first layer — FAIL (scrap it, recalibrate the bed)."))
	if ok:
		printed_ok = true


# Fixture / vise receptacles.
func accepts_part(id: StringName, item: Node) -> bool:
	if item == null:
		return false
	if id == &"fixture":
		return fix_kind == &"" and item.item_id in [&"relay_module", &"coolant_sensor", &"valve_actuator", &"bearing_cartridge"]
	if id == &"vise":
		return vise_kind == &"" and SUBS.has(item.item_id)
	return false


func stow_part(id: StringName, item: Node3D) -> bool:
	if not accepts_part(id, item):
		return false
	if id == &"fixture":
		fix_kind = item.item_id
		fix_payload = item.payload.duplicate(true)
		bench_truth = float(fix_payload.get("condition", 1.0)) >= 0.7 and String(fix_payload.get("state", "")) != "failed"
		verdict = ""
		powered = false
		reading = ""
		consume_part(item)
		say("%s in the fixture (rated %d V; test %s / %s)." % [Part.KINDS[fix_kind]["name"], RANGES[_need_range()], _need_terms()[0], _need_terms()[1]])
	else:
		vise_kind = item.item_id
		vise_payload = item.payload.duplicate(true)
		vise_clamped = false
		cover_on = true
		screws = [true, true, true, true]
		assembly_tested = false
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(vise_payload.get("serial", "")))
		sub_state = ["ok", "ok", "ok"]
		if float(vise_payload.get("condition", 1.0)) < 0.7 or String(vise_payload.get("state", "")) in ["repair", "failed"]:
			sub_state[rng.randi() % 3] = "worn"
		sub_seen = [false, false, false]
		consume_part(item)
		say("%s on the bench. Clamp it in the vise." % Part.KINDS[vise_kind]["name"])
	sfx(&"clunk")
	_refresh()
	return true


func stow_hint(id: StringName, item: Node) -> String:
	if id == &"fixture":
		return "Put %s in the test fixture" % item.get_display_name()
	if id == &"vise":
		return "Put %s in the vise" % item.get_display_name()
	return ""


## The reassembled part is tested in place and released serviceable.
func _finish_assembly() -> void:
	if vise_kind == &"" or not cover_on or screws.has(false) or sub_state.has("out") or sub_state.has("worn"):
		return
	if vise_clamped:
		return
	assembly_tested = true
	vise_payload["condition"] = 1.0
	vise_payload["state"] = "serviceable"
	vise_payload["grade"] = "B"
	vise_payload["calibrated"] = true
	var h: Array = vise_payload.get("history", [])
	h.append({"day": day(), "text": "reconditioned at B-04"})
	vise_payload["history"] = h
	var kind: StringName = vise_kind
	var p: Node3D = spawn_part(kind, _trays["serviceable"], vise_payload)
	vise_kind = &""
	say("Bench test PASS: %s serviceable (SERVICEABLE tray)." % p.get_display_name())
	sfx(&"success")


func on_rack_stowed(r: Rack, item: Node3D) -> void:
	if r == _trays.get("serviceable") or r == _trays.get("repair"):
		var want: String = "serviceable" if r == _trays["serviceable"] else "repair"
		if String(item.payload.get("state", "")) == want and has_open(&"b04_bench"):
			bench_sorted = true


# --------------------------------------------------------------- update
func _process(delta: float) -> void:
	_update_occlusion(delta)
	if printing >= 0.0:
		printing += delta
		if _fab_head != null:
			_fab_head.position.x = sin(printing * 5.0) * 0.18
		if printing >= 10.0:
			printing = -1.0
			var kind: StringName = TPL_KIND.get(TEMPLATES[tpl], &"bracket")
			spawn_part(kind, _out_tray, {"condition": 1.0 if fab_started_ok else 0.4, "state": "serviceable" if fab_started_ok else "failed", "grade": "A" if fab_started_ok else "C", "calibrated": fab_started_ok, "history": [{"day": day(), "text": "fabricated %s" % TEMPLATES[tpl]}]})
			sfx(&"success")
			say("Fabrication complete. Inspect it under the magnifier.")
	set_loop(_fab_loop, null, printing >= 0.0)
	# A reassembled part is released by un-clamping the vise.
	if vise_kind != &"" and not vise_clamped and cover_on and not screws.has(false) and sub_state.has("new"):
		_finish_assembly()
	if Engine.get_process_frames() % 6 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	if _vise_jaw != null:
		_vise_jaw.position.x = 0.07 if vise_clamped else 0.1
	if _vise_part != null:
		_vise_part.visible = vise_kind != &""
	if _cover != null:
		_cover.visible = cover_on
	for k in _screw_nodes.size():
		(_screw_nodes[k] as Node3D).visible = screws[k]
	for k in _sub_nodes.size():
		var m: StandardMaterial3D = (_sub_nodes[k] as MeshInstance3D).material_override
		(_sub_nodes[k] as Node3D).visible = sub_state[k] != "out"
		m.albedo_color = Color(0.45, 0.32, 0.2) if sub_state[k] == "worn" else (Color(0.85, 0.85, 0.8) if sub_state[k] == "new" else Color(0.7, 0.7, 0.72))
	if _fix_part != null:
		_fix_part.visible = fix_kind != &""
	if _lead_lbl != null:
		_lead_lbl.text = "LEAD A %s · LEAD B %s" % [leads[0] if leads[0] != "" else "-", leads[1] if leads[1] != "" else "-"]
	if _range_knob != null:
		_range_knob.rotation_degrees.z = -40.0 + rng_i * 40.0
	if _bench_lbl != null:
		_bench_lbl.text = "%d V  %s\n%s" % [RANGES[rng_i], "ON" if powered else "OFF", reading if powered else (("LOGGED " + verdict.to_upper()) if verdict != "" else "")]
	for k in _bolt_nodes.size():
		var v: int = bolt_t[k]
		(_bolt_nodes[k] as Node3D).position.y = 0.98 + (0.02 if v == 0 else (0.01 if v == 50 else 0.0))
	if _gap != null:
		_gap.text = "TORQUE %s\nGAP %s" % [" ".join(bolt_t.map(func(v): return "OVR" if v == -1 else "%d%%" % v)), "UNEVEN" if gap_uneven else "EVEN"]
	if _fab_lbl != null:
		_fab_lbl.text = "BED %s mm  TOL ±0.05\nTEMPLATE %s  SPOOL %d %%  %s" % [" ".join(bed_off.map(func(v): return "%+.3f" % v)), TEMPLATES[tpl], int(spool * 100.0), ("PRINTING %d %%" % int(printing * 10.0)) if printing >= 0.0 else "READY"]
	if _tool_lbl != null:
		_tool_lbl.text = "TOOL CHECK: DRIVER %s · METER %s · CRIMPER %s" % ["OUT OF CAL" if td_checked and absf(td_offset) > 0.04 else ("OK" if td_checked else "-"), ("LEAD OPEN" if not mm_leads_ok else "OK") if mm_tested else "-", "OK" if crimper_seen else "-"]


# ------------------------------------------------------------ orders
func _inbox_spawn(kind: StringName, pl: Dictionary) -> void:
	if _inbox != null and _inbox.free_slot() != -1:
		spawn_part(kind, _inbox, pl)


func task_rearm(t: StringName, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match t:
		&"b04_bench":
			var kind: StringName = [&"relay_module", &"coolant_sensor"][rng.randi() % 2]
			var good: bool = rng.randf() < 0.5
			_inbox_spawn(kind, {"condition": 0.95 if good else 0.4, "state": "returned", "grade": "B", "calibrated": false, "history": [{"day": day(), "text": "returned for bench test"}]})
			bench_sorted = false
			verdict = ""
		&"b04_reassembly":
			_inbox_spawn(&"valve_actuator", {"condition": 0.45, "state": "repair", "grade": "C", "calibrated": false, "history": [{"day": day(), "text": "removed: sticking"}]})
			reasm_type = t
			assembly_tested = false
		&"b04_recondition":
			# The damaged component the chain brought here (P-301's bearing);
			# a cartridge only appears if none is already waiting.
			var have: bool = _trays["repair"].count(&"bearing_cartridge") > 0 or _inbox.count(&"bearing_cartridge") > 0
			if not have:
				_inbox_spawn(&"bearing_cartridge", {"condition": 0.3, "state": "repair", "grade": "C", "calibrated": false, "history": [{"day": day(), "text": "P-301 bearing, worn (HF vibration)"}]})
			reasm_type = t
			assembly_tested = false
		&"b04_torque":
			bolt_t = [0, 0, 0, 0]
			final_order = []
			gap_uneven = false
			torque_verified = false
		&"b04_fab":
			bed_off = [snappedf(rng.randf_range(-0.15, 0.15), 0.025), snappedf(rng.randf_range(-0.15, 0.15), 0.025), snappedf(rng.randf_range(0.075, 0.15), 0.025)]
			printed_ok = false
			inspected = false
		&"b04_tools":
			td_offset = 0.06 if rng.randf() < 0.5 else 0.0
			mm_leads_ok = rng.randf() < 0.6
			td_checked = false
			mm_tested = false
			crimper_seen = false
			_tools_were_ok = td_offset == 0.0 and mm_leads_ok
	_refresh()


func task_done(t: StringName) -> bool:
	var done := false
	match t:
		&"b04_bench":
			done = bench_sorted
			if done and not outcome.has(t):
				close_task(t, "verified_normal" if verdict == "pass" else "repaired", "test bench", "component returned for test", "bench test, %s" % verdict.to_upper(), "sorted to %s" % ("SERVICEABLE" if verdict == "pass" else "REPAIR QUEUE"))
		&"b04_reassembly", &"b04_recondition":
			done = assembly_tested and reasm_type == t
			if done and not outcome.has(t):
				close_task(t, "repaired", "workbench", "worn sub-component", "disassembled, sub-component replaced, reassembled", "bench test PASS")
		&"b04_torque":
			done = torque_verified
			if done and not outcome.has(t):
				close_task(t, "verified_normal", "torque stand", "none", "cross-pattern torque 12 N·m", "gap even")
		&"b04_fab":
			done = printed_ok and inspected
			if done and not outcome.has(t):
				close_task(t, "repaired", "fabricator", "bed out of level", "bed levelled, test part printed", "part inspected PASS")
		&"b04_tools":
			done = td_checked and absf(td_offset) <= 0.04 and mm_tested and mm_leads_ok and crimper_seen
			if done and not outcome.has(t):
				close_task(t, "verified_normal" if _tools_were_ok else "repaired", "tool board", "tool out of calibration / open leads", "calibrated / leads replaced", "all tools checked")
	return done


var _tools_were_ok: bool = true


func task_next(t: StringName) -> Dictionary:
	match t:
		&"b04_bench":
			if fix_kind == &"" and verdict == "":
				return next("Put the returned component (bench inbox) in the test fixture", "FIXTURE")
			if not powered and verdict == "":
				return next("Connect the leads, select the range, apply test power", "TEST")
			if verdict == "":
				return next("Log PASS or FAIL from the reading", "VERDICT")
			return next("Release the part and sort it to the matching tray", "SORT")
		&"b04_reassembly", &"b04_recondition":
			if vise_kind == &"":
				return next("Put the part (bench inbox) in the vise", "VISE")
			if cover_on and screws.has(true):
				return next("Clamp, remove the cover screws, lift the cover", "OPEN")
			if sub_state.has("worn") or sub_state.has("out"):
				return next("Find the worn sub-component (magnifier) and replace it from the drawer", "REPLACE")
			return next("Cover on, screws in, un-clamp (bench test)", "REASSEMBLE")
		&"b04_torque":
			return next("Torque the plate: snug all four, then final in a cross pattern; VERIFY", "TORQUE")
		&"b04_fab":
			if printed_ok:
				return next("Inspect the part under the magnifier", "INSPECT")
			return next("Level the fabricator bed (±0.05 mm), print a BRACKET, inspect it", "CALIBRATE")
		&"b04_tools":
			return next("Check the torque driver, multimeter and crimper on the tool board", "TOOLS")
	return {}


func task_feasible(t: StringName) -> bool:
	if t == &"b04_fab":
		return spool >= 0.04
	return _inbox == null or _inbox.free_slot() != -1 or t in [&"b04_torque", &"b04_tools", &"b04_fab"]


func state_dict() -> Dictionary:
	return {"fix_kind": String(fix_kind), "fix_payload": fix_payload.duplicate(true), "leads": leads.duplicate(), "rng_i": rng_i, "verdict": verdict, "bench_truth": bench_truth, "bench_sorted": bench_sorted,
		"vise_kind": String(vise_kind), "vise_payload": vise_payload.duplicate(true), "vise_clamped": vise_clamped, "screws": screws.duplicate(), "cover_on": cover_on,
		"sub_state": sub_state.duplicate(), "assembly_tested": assembly_tested, "reasm_type": String(reasm_type), "bolt_t": bolt_t.duplicate(), "final_order": final_order.duplicate(),
		"gap_uneven": gap_uneven, "torque_verified": torque_verified, "bed_off": bed_off.duplicate(), "tpl": tpl, "spool": spool, "printed_ok": printed_ok, "inspected": inspected,
		"td_offset": td_offset, "td_checked": td_checked, "mm_leads_ok": mm_leads_ok, "mm_tested": mm_tested, "crimper_seen": crimper_seen, "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in ["fix_kind", "vise_kind", "reasm_type"]:
			set(k, StringName(String(d[k])))
		elif k in self:
			set(k, d[k])
	printing = -1.0
	_refresh()
