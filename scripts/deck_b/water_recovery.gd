extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-02 WATER RECOVERY AND WASTE PROCESSING.
## Equipment (all reading / driving deck_b_systems.water):
##   RAW and POTABLE tanks (north wall) with sight glasses (true level) and
##   the control panel's level SENSORS (which can be wrong);
##   the MF-2 multifiltration bed housing (west wall): ΔP gauge, a clamp
##   ring lid, the seated bed (a real part); spare-bed rack + spent-bed bin;
##   pump P-201 on its skid (east wall): run switch, outlet pressure gauge,
##   vibration test point, drip tray, seal housing, bleed valve + sight
##   glass; handwheels V-IN / V-OUT / V-RC (recirculation); flow meter;
##   the sample port + QA analyzer (COND / TURB / TEMP, PASS / FAIL);
##   the WRS control panel (levels, product conductivity, pump log, CYCLE).
## Sound: P-201 runs only during a processing cycle; its loop is built from
## its real condition (healthy hum / air-lock rattle and surge / seal hiss
## and drips / bearing whine).
## Tasks: b02_filter, b02_sample, b02_pump (L08), b02_flow, b02_tank.

const COND_LIMIT := 30.0
const TURB_LIMIT := 1.0
const MODES := ["COND", "TURB", "TEMP"]
# Filter service
var clamp_open: bool = false
var bed_seated: bool = true          # a bed sits in the housing
var dp_read: bool = false
var flt_installed_new: bool = false
var flt_verified: bool = false
# Sample / analyzer
var vial: String = "empty"          # empty | at_port | in_analyzer
var vial_src: String = ""           # product | potable
var vial_cond: float = 0.0
var vial_turb: float = 0.0
var mode: int = 0
var mode_seen: Array = [false, false, false]
var logged: String = ""             # "" | pass | fail
var reprocess_needed: bool = false
var sample_ok: bool = false
# Pump diagnosis / priming
var diag_choice: int = 0            # index into DIAGS
var diag_confirmed: String = ""
var vib_read: bool = false
var prime_bled: float = 0.0
var pump_fixed: bool = false
var pump_seed: String = ""
const DIAGS := ["AIR LOCK", "SEAL LEAK", "BEARING", "NO FAULT"]
# Flow restoration
var flow_ok_s: float = 0.0
var flow_read: bool = false
# Tank inspection
var glass_read: Array = [false, false]
var panel_read: bool = false
var tank_verdict: String = ""

var _housing_lid: Node3D
var _bed_visual: MeshInstance3D
var _dp_gauge: Label3D
var _wheels := {}
var _pump_switch: Node3D
var _pump_lamp: StandardMaterial3D
var _press: Label3D
var _flow: Label3D
var _drip: Node3D
var _bleed_glass: MeshInstance3D
var _bleed_handle: Node3D
var _vial_port: MeshInstance3D
var _vial_an: MeshInstance3D
var _an: Label3D
var _an_mode: Node3D
var _panel: Label3D
var _diag_label: Label3D
var _glass: Array = []
var _spares: Rack
var _spent_bin: Rack
var _seal_rack: Rack
var _pump_loop: AudioStreamPlayer3D
var _stream_cache := {}
var _flow_loop: AudioStreamPlayer3D


func _ready() -> void:
	_room_ready([&"b02_filter", &"b02_sample", &"b02_pump", &"b02_flow", &"b02_tank"])
	_build_tanks()
	_build_filter()
	_build_pump()
	_build_sampling()
	_build_panel()
	text("B-02  WATER RECOVERY", Vector3(-0.1, L.FLOOR_Y + 2.75, 10.88), 20, Color(0.9, 0.95, 1.0), self, 180.0)
	_refresh()


func w() -> Dictionary:
	var s: Node = sys()
	return s.water if s != null else {}


# ------------------------------------------------------------- geometry
func _build_tanks() -> void:
	for k in 2:
		var x: float = -1.25 + k * 0.85
		var t := Node3D.new()
		t.name = "Tank" + ["Raw", "Potable"][k]
		t.position = Vector3(x, L.FLOOR_Y, 10.58)
		add_child(t)
		dcyl(0.27, 2.1, Vector3(0, 1.05, 0), Color(0.88, 0.9, 0.92) if k == 1 else Color(0.72, 0.74, 0.7), t, Vector3.ZERO, 0.3, true)
		dcyl(0.29, 0.06, Vector3(0, 2.12, 0), Color(0.5, 0.52, 0.55), t)
		dbox(Vector3(0.05, 1.7, 0.02), Vector3(0, 1.05, -0.275), Color(0.08, 0.1, 0.12), t)
		var lvl := dbox(Vector3(0.035, 1.0, 0.012), Vector3(0, 0.7, -0.285), Color(0.3, 0.6, 0.9) if k == 1 else Color(0.55, 0.5, 0.3), t)
		glow(lvl, Color(0.25, 0.45, 0.7) if k == 1 else Color(0.4, 0.35, 0.2), 0.6)
		_glass.append(lvl)
		for m in 5:
			dbox(Vector3(0.07, 0.006, 0.01), Vector3(0, 0.2 + m * 0.4, -0.29), Color(0.9, 0.9, 0.9), t)
		text(["RAW · WASTEWATER / CONDENSATE\n60 L", "POTABLE\n200 L"][k], Vector3(0, 2.0, -0.28), 10, Color(0.1, 0.1, 0.1), t, 180.0)
		part(StringName("glass%d" % k), Vector3(0.12, 1.7, 0.08), Vector3(0, 1.05, -0.3), t)


func _build_filter() -> void:
	var f := Node3D.new()
	f.name = "FilterHousing"
	f.position = Vector3(-1.62, L.FLOOR_Y, 9.35)
	add_child(f)
	dbox(Vector3(0.3, 1.0, 0.5), Vector3(-0.02, 0.5, 0), Color(0.42, 0.45, 0.48), f, 0.5, true)
	dcyl(0.14, 0.42, Vector3(0.05, 1.21, 0), Color(0.82, 0.84, 0.86), f)
	_bed_visual = dcyl(0.11, 0.3, Vector3(0.05, 1.2, 0), Color(0.86, 0.86, 0.82), f)
	_housing_lid = Node3D.new()
	_housing_lid.position = Vector3(0.05 - 0.15, 1.43, 0)
	f.add_child(_housing_lid)
	dcyl(0.155, 0.05, Vector3(0.15, 0, 0), Color(0.62, 0.64, 0.66), _housing_lid, Vector3.ZERO, 0.8)
	dbox(Vector3(0.05, 0.03, 0.2), Vector3(0.3, 0.0, 0), Color(0.75, 0.2, 0.15), _housing_lid)
	text("MF-2 BED HOUSING · ISOLATE BEFORE OPENING", Vector3(0.19, 0.85, 0), 9, Color(0.95, 0.95, 0.9), f, 90.0)
	_dp_gauge = readout(Vector3(0.14, 1.0, 0.0), Vector2(0.16, 0.08), f, 11, Color(0.55, 0.95, 0.75), 90.0)
	part(&"dp", Vector3(0.06, 0.1, 0.18), Vector3(0.15, 1.0, 0), f)
	part(&"clamp", Vector3(0.36, 0.08, 0.36), Vector3(0.05, 1.45, 0), f)
	part(&"bed", Vector3(0.24, 0.3, 0.24), Vector3(0.05, 1.2, 0), f)
	# Spares rack and the spent-bed bin (real parts).
	_spares = rack("WaterSpareBeds", Vector3(-1.64, L.FLOOR_Y + 1.45, 10.0), 3, 0.15, [&"mf_bed", &"ix_bed"], "SPARE BEDS", self, 90.0)
	_spent_bin = rack("SpentBedBin", Vector3(-1.64, L.FLOOR_Y + 0.62, 10.0), 2, 0.15, [&"mf_bed_spent"], "SPENT BEDS → WORKSHOP SCRAP", self, 90.0)
	spawn_part.call_deferred(&"mf_bed", _spares)
	spawn_part.call_deferred(&"ix_bed", _spares)
	spawn_part.call_deferred(&"mf_bed", _spares)


func _build_pump() -> void:
	var p := Node3D.new()
	p.name = "PumpP201"
	p.position = Vector3(1.32, L.FLOOR_Y, 9.75)
	add_child(p)
	dbox(Vector3(0.42, 0.08, 0.7), Vector3(0, 0.04, 0), Color(0.3, 0.32, 0.34), p, 0.5, true)
	dcyl(0.12, 0.34, Vector3(0, 0.3, 0.12), Color(0.25, 0.42, 0.62), p, Vector3(90, 0, 0), 0.5, true)
	dcyl(0.14, 0.18, Vector3(0, 0.3, -0.16), Color(0.55, 0.57, 0.6), p, Vector3(90, 0, 0), 0.6)
	text("P-201  WRS PROCESS PUMP", Vector3(-0.22, 0.48, 0), 9, Color(0.95, 0.95, 0.9), p, -90.0)
	part(&"vib", Vector3(0.18, 0.18, 0.18), Vector3(0, 0.3, -0.16), p)
	part(&"seal", Vector3(0.16, 0.14, 0.1), Vector3(0, 0.3, -0.3), p)
	_drip = Node3D.new()
	p.add_child(_drip)
	dbox(Vector3(0.22, 0.02, 0.18), Vector3(0, 0.1, -0.32), Color(0.5, 0.52, 0.55), _drip)
	var pool := dbox(Vector3(0.16, 0.004, 0.12), Vector3(0, 0.112, -0.32), Color(0.5, 0.7, 0.9), _drip, 0.9)
	pool.name = "Pool"
	# Pipework on the east wall: inlet / outlet / recirculation with wheels.
	var py: float = 1.15
	dcyl(0.03, 1.9, Vector3(1.55, L.FLOOR_Y + py, 9.95), Color(0.52, 0.53, 0.55), self, Vector3(90, 0, 0))
	dcyl(0.03, 1.9, Vector3(1.55, L.FLOOR_Y + py + 0.45, 9.95), Color(0.25, 0.42, 0.62), self, Vector3(90, 0, 0))
	for v in [["v_in", 9.25, py, "V-IN  RAW → PUMP"], ["v_out", 10.25, py + 0.45, "V-OUT  BED → POTABLE"], ["v_rc", 10.65, py, "V-RC  RECIRCULATE"]]:
		var wh: Node3D = handwheel(v[0], Vector3(1.48, L.FLOOR_Y + float(v[2]), float(v[1])), 0.07, self, true)
		wh.rotation_degrees.y = -90.0
		_wheels[v[0]] = wh
		text(v[3], Vector3(1.585, L.FLOOR_Y + float(v[2]) + 0.12, float(v[1])), 8, Color(0.95, 0.95, 0.9), self, -90.0)
	# Run switch + lamp, outlet pressure, flow meter.
	var c := Node3D.new()
	c.name = "PumpControls"
	c.position = Vector3(1.58, L.FLOOR_Y + 1.3, 9.45)
	c.rotation_degrees.y = -90.0
	add_child(c)
	dbox(Vector3(0.3, 0.22, 0.04), Vector3(0, 0, 0.02), Color(0.22, 0.24, 0.26), c)
	_pump_switch = Node3D.new()
	_pump_switch.position = Vector3(-0.08, 0.02, 0.05)
	c.add_child(_pump_switch)
	dbox(Vector3(0.025, 0.06, 0.025), Vector3(0, 0.025, 0), Color(0.9, 0.9, 0.88), _pump_switch)
	part(&"pump_switch", Vector3(0.06, 0.1, 0.06), Vector3(-0.08, 0.02, 0.06), c)
	var lm := dbox(Vector3(0.02, 0.02, 0.01), Vector3(-0.08, -0.07, 0.042), Color(0.2, 0.2, 0.2), c)
	_pump_lamp = lm.material_override
	_press = readout(Vector3(0.06, 0.03, 0.042), Vector2(0.14, 0.12), c, 10)
	_flow = readout(Vector3(0.0, 0.55, 0.0), Vector2(0.24, 0.09), c, 11)
	part(&"flow", Vector3(0.24, 0.1, 0.06), Vector3(0, 0.55, 0.03), c)
	part(&"press", Vector3(0.14, 0.12, 0.06), Vector3(0.06, 0.03, 0.06), c)
	# Bleed valve + sight glass on the pump casing top.
	var b := Node3D.new()
	b.name = "Bleed"
	b.position = Vector3(1.32, L.FLOOR_Y + 0.5, 9.87)
	add_child(b)
	dcyl(0.012, 0.12, Vector3(0, 0.06, 0), Color(0.6, 0.6, 0.62), b)
	_bleed_glass = dcyl(0.022, 0.05, Vector3(0, 0.14, 0), Color(0.8, 0.9, 1.0), b, Vector3.ZERO, 0.1)
	_bleed_handle = Node3D.new()
	_bleed_handle.position = Vector3(0, 0.2, 0)
	b.add_child(_bleed_handle)
	dbox(Vector3(0.08, 0.012, 0.012), Vector3(0.03, 0, 0), Color(0.75, 0.2, 0.15), _bleed_handle)
	part(&"bleed", Vector3(0.12, 0.14, 0.12), Vector3(0, 0.16, 0), b)
	text("BLEED", Vector3(0, 0.27, 0), 8, Color(0.95, 0.95, 0.9), b, -90.0)
	# Diagnosis tag panel (the maintenance tag the technician fills in).
	var d := Node3D.new()
	d.name = "PumpDiag"
	d.position = Vector3(1.58, L.FLOOR_Y + 1.0, 10.45)
	d.rotation_degrees.y = -90.0
	add_child(d)
	dbox(Vector3(0.24, 0.16, 0.02), Vector3(0, 0, 0.01), Color(0.9, 0.86, 0.6), d)
	_diag_label = text("", Vector3(0, 0.02, 0.022), 9, Color(0.1, 0.1, 0.1), d)
	part(&"diag_sel", Vector3(0.16, 0.12, 0.05), Vector3(-0.03, 0.02, 0.03), d)
	button("diag_ok", Vector3(0.09, -0.05, 0.022), Color(0.3, 0.8, 0.4), d, Vector3(0.04, 0.03, 0.015))
	# Seal kits (real spares).
	_seal_rack = rack("PumpSealKits", Vector3(1.6, L.FLOOR_Y + 0.72, 10.1), 2, 0.16, [&"pump_seal_kit", &"bearing_cartridge"], "PUMP SPARES", self, -90.0)
	spawn_part.call_deferred(&"pump_seal_kit", _seal_rack)
	_pump_loop = machine_loop(_pump_stream(""), Vector3(1.32, L.FLOOR_Y + 0.3, 9.75), -9.0)
	_flow_loop = machine_loop(loop_stream(3.0, func(t, i): return (fmod(sin(float(i) * 78.233) * 43758.5453, 1.0) - 0.5) * (0.25 + 0.15 * sin(TAU * 0.7 * t))), Vector3(1.5, L.FLOOR_Y + 1.6, 9.95), -20.0)


func _build_sampling() -> void:
	var a := Node3D.new()
	a.name = "Analyzer"
	a.position = Vector3(1.1, L.FLOOR_Y + 0.95, 8.72)
	add_child(a)                          # faces +z into the room
	dbox(Vector3(0.6, 0.04, 0.32), Vector3(0, -0.02, 0.16), Color(0.55, 0.57, 0.6), a, 0.4, true)
	dbox(Vector3(0.3, 0.26, 0.2), Vector3(0.1, 0.13, 0.12), Color(0.88, 0.89, 0.9), a)
	_an = readout(Vector3(0.1, 0.19, 0.225), Vector2(0.22, 0.09), a, 10)
	text("QA ANALYZER  ·  LIMITS: COND ≤ 30 µS/cm · TURB ≤ 1.0 NTU", Vector3(0.1, 0.29, 0.22), 7, Color(0.1, 0.1, 0.1), a)
	_an_mode = Node3D.new()
	_an_mode.position = Vector3(0.0, 0.07, 0.225)
	a.add_child(_an_mode)
	dcyl(0.022, 0.02, Vector3.ZERO, Color(0.1, 0.1, 0.11), _an_mode, Vector3(90, 0, 0))
	dbox(Vector3(0.005, 0.02, 0.01), Vector3(0, 0.01, 0.01), Color(0.95, 0.95, 0.9), _an_mode)
	part(&"an_mode", Vector3(0.06, 0.06, 0.05), Vector3(0.0, 0.07, 0.235), a)
	button("an_pass", Vector3(0.12, 0.06, 0.225), Color(0.3, 0.9, 0.4), a, Vector3(0.04, 0.03, 0.012))
	button("an_fail", Vector3(0.19, 0.06, 0.225), Color(0.95, 0.3, 0.2), a, Vector3(0.04, 0.03, 0.012))
	text("PASS   FAIL", Vector3(0.155, 0.025, 0.225), 7, Color(0.1, 0.1, 0.1), a)
	_vial_an = dcyl(0.012, 0.07, Vector3(-0.12, 0.08, 0.14), Color(0.8, 0.9, 1.0), a, Vector3.ZERO, 0.1)
	part(&"an_slot", Vector3(0.08, 0.12, 0.08), Vector3(-0.12, 0.08, 0.16), a)
	# Sample port on the product line (south wall, west of the analyzer).
	var sp := Node3D.new()
	sp.name = "SamplePort"
	sp.position = Vector3(0.6, L.FLOOR_Y + 1.25, 8.72)
	add_child(sp)
	dcyl(0.02, 0.5, Vector3(0, 0, 0.03), Color(0.25, 0.42, 0.62), sp, Vector3(0, 0, 90))
	dcyl(0.012, 0.08, Vector3(0, -0.05, 0.05), Color(0.7, 0.7, 0.72), sp)
	_vial_port = dcyl(0.012, 0.07, Vector3(0, -0.13, 0.05), Color(0.8, 0.9, 1.0), sp, Vector3.ZERO, 0.1)
	text("SAMPLE PORT  SP-2", Vector3(0, 0.08, 0.06), 8, Color(0.95, 0.95, 0.9), sp)
	part(&"port", Vector3(0.1, 0.2, 0.1), Vector3(0, -0.06, 0.06), sp)


func _build_panel() -> void:
	var c := Node3D.new()
	c.name = "WrsPanel"
	c.position = Vector3(-1.15, L.FLOOR_Y + 1.45, 8.72)
	add_child(c)
	dbox(Vector3(0.5, 0.4, 0.04), Vector3(0, 0, 0.02), Color(0.2, 0.22, 0.25), c)
	text("WRS CONTROL", Vector3(0, 0.22, 0.042), 10, Color(0.95, 0.95, 0.9), c)
	_panel = readout(Vector3(0, 0.0, 0.042), Vector2(0.44, 0.32), c, 9)
	part(&"panel", Vector3(0.44, 0.32, 0.06), Vector3(0, 0, 0.05), c)
	button("cycle", Vector3(0.19, -0.17, 0.042), Color(0.3, 0.8, 0.95), c, Vector3(0.05, 0.03, 0.012))
	button("lvl_cal", Vector3(-0.19, -0.17, 0.042), Color(0.95, 0.75, 0.2), c, Vector3(0.05, 0.03, 0.012))
	text("CAL LEVEL            START CYCLE", Vector3(0, -0.215, 0.042), 7, Color(0.85, 0.85, 0.85), c)
	button("tank_ok", Vector3(-0.06, -0.17, 0.042), Color(0.3, 0.9, 0.4), c, Vector3(0.04, 0.03, 0.012))
	button("tank_bad", Vector3(0.06, -0.17, 0.042), Color(0.95, 0.3, 0.2), c, Vector3(0.04, 0.03, 0.012))
	text("AGREE  SENSOR?", Vector3(0, -0.14, 0.042), 7, Color(0.85, 0.85, 0.85), c)


# ---------------------------------------------------------------- sound
func _pump_stream(fault: String) -> AudioStream:
	if _stream_cache.has(fault):
		return _stream_cache[fault]
	var seed_f: float = float(hash(fault) % 97)
	var gen: Callable
	match fault:
		"air_lock":
			gen = func(t, i):
				var surge: float = 0.6 + 0.4 * sin(TAU * 1.3 * t)
				var rattle: float = (1.0 if fmod(t * 37.0 + sin(t * 9.0), 1.0) < 0.12 else 0.0) * (fmod(sin(float(i) * 12.9898 + seed_f) * 43758.5453, 1.0) - 0.5) * 1.6
				return sin(TAU * 50.0 * t) * 0.18 * surge + sin(TAU * 148.0 * t) * 0.1 * surge + rattle * 0.5
		"seal_leak":
			gen = func(t, i):
				var hiss: float = (fmod(sin(float(i) * 78.233 + seed_f) * 43758.5453, 1.0) - 0.5) * 0.35
				var drip: float = sin(TAU * 1200.0 * t) * exp(-fmod(t, 0.9) * 60.0) * 0.4
				return sin(TAU * 50.0 * t) * 0.22 + sin(TAU * 150.0 * t) * 0.1 + hiss * 0.6 + drip
		"worn_bearing":
			gen = func(t, i):
				var grind: float = (fmod(sin(float(i) * 3.13 + seed_f) * 43758.5453, 1.0) - 0.5) * 0.25 * (0.6 + 0.4 * sin(TAU * 24.0 * t))
				return sin(TAU * 50.0 * t) * 0.2 + sin(TAU * 150.0 * t) * 0.1 + sin(TAU * 2750.0 * t) * 0.09 + grind
		_:
			gen = func(t, i):
				return sin(TAU * 50.0 * t) * 0.24 + sin(TAU * 150.0 * t) * 0.12 + sin(TAU * 300.0 * t) * 0.03 + (fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.06
	var s: AudioStream = loop_stream(2.0, gen)
	_stream_cache[fault] = s
	return s


# --------------------------------------------------------------- clicks
func _isolated() -> bool:
	var ww: Dictionary = w()
	return ww.is_empty() or float(ww["v_in"]) < 0.05 or not ww["pump_on"] or not ww["processing"]


func on_part(id: StringName) -> void:
	var s: Node = sys()
	if s == null:
		return
	var ww: Dictionary = s.water
	var sid: String = String(id)
	if sid.ends_with("_up") or sid.ends_with("_dn"):
		var v: String = sid.substr(0, sid.length() - 3)
		if ww.has(v):
			ww[v] = clampf(float(ww[v]) + (0.25 if sid.ends_with("_up") else -0.25), 0.0, 1.0)
			sfx(&"ratchet")
			say("%s %d %% open" % [v.to_upper().replace("_", "-"), int(float(ww[v]) * 100.0)])
		_refresh()
		return
	match sid:
		"dp":
			dp_read = true
			say("Bed ΔP %.0f kPa  (%s)" % [s.filter_dp(), "FILTER — replace bed" if s.filter_dp() > 62.0 else ("no flow" if s.filter_dp() == 0.0 else "normal < 60")])
		"clamp":
			if not clamp_open and not _isolated():
				say("Housing pressurised — close V-IN or stop P-201 before opening the clamp.")
				sfx(&"fail")
				return
			clamp_open = not clamp_open
			sfx(&"latch")
		"bed":
			if not clamp_open:
				say("Open the housing clamp first.")
			elif bed_seated and held() == null:
				# Lift the bed out: it becomes the real spent part in the hand.
				bed_seated = false
				var spent: Node3D = spawn_part(&"mf_bed_spent" if ww["filter_kind"] == "mf_bed" else &"ix_bed", null, {"condition": float(ww["filter_life"]), "state": "spent", "serial": "MF2-IN-SERVICE", "history": []})
				spent.global_position = _bed_visual.global_position
				ww["filter_life"] = 0.0
				var c: Node = _carry()
				if c != null:
					c.pick_up(spent)
				sfx(&"clunk")
				say("Spent bed out. Put it in the spent-bed bin; fetch an MF-2 bed from the spares rack.")
			elif not bed_seated:
				say("Housing empty — carry an MF-2 bed here and press Space to seat it.")
		"pump_switch":
			ww["pump_on"] = not ww["pump_on"]
			if ww["pump_on"] and ww["processing"]:
				s._pump_start("manual")
			sfx(&"clunk")
			say("P-201 %s" % ("ON" if ww["pump_on"] else "OFF"))
		"vib":
			vib_read = true
			var mm: float = {"worn_bearing": 6.9, "air_lock": 4.1, "seal_leak": 2.4}.get(String(ww["pump_fault"]), 1.6) if ww["processing"] and ww["pump_on"] else 0.2
			var band: String = {"worn_bearing": "HIGH-FREQ (bearing)", "air_lock": "IRREGULAR (surging)", "seal_leak": "steady"}.get(String(ww["pump_fault"]), "steady") if ww["processing"] and ww["pump_on"] else "-"
			say("P-201 vibration %.1f mm/s · %s" % [mm, band])
		"seal":
			_seal_click()
		"bleed":
			ww["bleed"] = not ww["bleed"]
			sfx(&"ratchet")
			say("Bleed valve %s" % ("OPEN — venting air" if ww["bleed"] else "closed"))
		"press":
			say("P-201 outlet %.0f kPa (normal 160-190)" % s.water_pressure())
		"flow":
			flow_read = true
			say("Process flow %.1f L/h (normal ≥ 9 while cycling)" % s.water_flow())
		"diag_sel":
			diag_choice = (diag_choice + 1) % DIAGS.size()
			sfx(&"click")
		"diag_ok":
			_confirm_diag()
		"port":
			if vial != "empty":
				say("The vial is %s." % ("at the port" if vial == "at_port" else "in the analyzer"))
				return
			vial = "at_port"
			vial_src = "product" if (ww["processing"] and ww["pump_on"] and s.water_flow() > 0.5) else "potable"
			vial_cond = s.product_cond() if vial_src == "product" else float(ww["pot_cond"])
			vial_turb = 0.25 + (1.0 - float(ww["filter_life"])) * 0.5 + (0.9 if ww["filter_kind"] != "mf_bed" else 0.0)
			logged = ""
			mode_seen = [false, false, false]
			sfx(&"click")
			say("Sample drawn (%s water)." % vial_src)
		"an_slot":
			if vial == "at_port":
				vial = "in_analyzer"
				sfx(&"click")
				say("Vial in the analyzer. Select a mode and read.")
			elif vial == "in_analyzer" and logged != "":
				vial = "empty"
				say("Vial emptied and stowed.")
		"an_mode":
			mode = (mode + 1) % MODES.size()
			if vial == "in_analyzer":
				mode_seen[mode] = true
			sfx(&"click")
		"an_pass", "an_fail":
			_log_result(sid == "an_pass")
		"panel":
			panel_read = true
			say("Panel levels: RAW %.0f L · POTABLE %.0f L" % [s.tank_level_reading(false), s.tank_level_reading(true)])
		"cycle":
			ww["processing"] = true
			if ww["pump_on"]:
				s._pump_start("manual cycle")
			sfx(&"click")
			say("Processing cycle started.")
		"lvl_cal":
			if not (glass_read[0] and glass_read[1] and panel_read):
				say("Compare both sight glasses with the panel first.")
				return
			ww["level_bias"] = 0.0
			sfx(&"click")
			say("Level sensors recalibrated to the sight glasses.")
		"tank_ok", "tank_bad":
			_tank_verdict(sid == "tank_ok")
		_:
			if sid.begins_with("glass"):
				var k: int = int(sid.substr(5))
				glass_read[k] = true
				var vv: float = float(ww["potable_l"]) if k == 1 else float(ww["raw_l"])
				say("%s sight glass: %.0f L" % ["POTABLE" if k == 1 else "RAW", vv])
	_refresh()


func _seal_click() -> void:
	var s: Node = sys()
	var ww: Dictionary = s.water
	if ww["pump_fault"] == "seal_leak" or (ww["pump_fault"] == "worn_bearing" and held_kind() == &"bearing_cartridge"):
		if ww["pump_on"] or float(ww["v_in"]) > 0.05 or float(ww["v_out"]) > 0.05:
			say("Stop P-201 and close V-IN and V-OUT before opening the pump.")
			return
		var need: StringName = &"pump_seal_kit" if ww["pump_fault"] == "seal_leak" else &"bearing_cartridge"
		if held_kind() != need:
			say("Hold a %s to replace it." % ("pump seal kit (PUMP SPARES)" if need == &"pump_seal_kit" else "bearing cartridge"))
			return
		consume_part(held())
		ww["pump_fault"] = ""
		pump_fixed = true
		sfx(&"ratchet")
		say("%s replaced. Restore the valves and run the pump." % ("Seal" if need == &"pump_seal_kit" else "Bearing cartridge"))
	else:
		say("Shaft seal dry." if ww["pump_fault"] != "seal_leak" else "")


func _confirm_diag() -> void:
	var s: Node = sys()
	var ww: Dictionary = s.water
	var truth: String = {"air_lock": "AIR LOCK", "seal_leak": "SEAL LEAK", "worn_bearing": "BEARING", "": "NO FAULT"}.get(String(ww["pump_fault"]), "NO FAULT")
	if not vib_read and DIAGS[diag_choice] != "NO FAULT":
		say("Take the vibration reading and outlet pressure before recording a diagnosis.")
		return
	if DIAGS[diag_choice] != truth:
		say("Recorded %s — but the readings don't support it (pressure %.0f kPa, flow %.1f L/h, drip tray %s). Listen again." % [DIAGS[diag_choice], s.water_pressure(), s.water_flow(), "wet" if ww["pump_fault"] == "seal_leak" else "dry"])
		sfx(&"fail")
		return
	diag_confirmed = truth
	sfx(&"success")
	match truth:
		"AIR LOCK":
			say("Air lock: prime the pump — P-201 OFF, close V-OUT, open BLEED until liquid shows, close BLEED, run, open V-OUT.")
		"SEAL LEAK":
			say("Seal leak: P-201 OFF, close V-IN and V-OUT, replace the seal kit.")
		"BEARING":
			say("Worn bearing: needs a bearing cartridge (workshop recondition / cargo).")
		_:
			say("No fault found.")


func _log_result(pass_btn: bool) -> void:
	if vial != "in_analyzer" or not (mode_seen[0] and mode_seen[1]):
		say("Read COND and TURB first.")
		return
	var bad: bool = vial_cond > COND_LIMIT or vial_turb > TURB_LIMIT
	if pass_btn and bad:
		say("QA refuses PASS: %.0f µS/cm / %.2f NTU is above the limit printed on the analyzer." % [vial_cond, vial_turb])
		sfx(&"fail")
		return
	if not pass_btn and not bad:
		say("QA refuses FAIL: within limits (%.0f µS/cm, %.2f NTU)." % [vial_cond, vial_turb])
		sfx(&"fail")
		return
	logged = "pass" if pass_btn else "fail"
	sfx(&"success" if pass_btn else &"click")
	if not pass_btn:
		reprocess_needed = true
		say("Logged FAIL. Reprocess: open V-RC to recirculate the potable tank through the bed, then sample again.")
	else:
		say("Logged PASS (%.0f µS/cm, %.2f NTU)." % [vial_cond, vial_turb])
		if vial_src == "product" and flt_installed_new:
			flt_verified = true
		if vial_src == "potable" or vial_src == "product":
			sample_ok = true


func _tank_verdict(agree: bool) -> void:
	if not (glass_read[0] and glass_read[1] and panel_read):
		say("Read both sight glasses and the panel first.")
		return
	var s: Node = sys()
	var bias: float = absf(float(s.water["level_bias"]))
	if agree and bias > 5.0:
		say("The potable sight glass and the panel differ by %.0f L — they don't agree." % bias)
		sfx(&"fail")
		return
	if not agree and bias <= 5.0:
		say("Within tolerance (±5 L): the sensors agree with the glasses.")
		sfx(&"fail")
		return
	tank_verdict = "agree" if agree else "sensor"
	sfx(&"success")
	if not agree:
		say("Level sensor fault recorded. Recalibrate it (CAL LEVEL).")


func part_prompt(id: StringName) -> String:
	var s: Node = sys()
	var ww: Dictionary = s.water if s != null else {}
	var sid: String = String(id)
	if sid.ends_with("_up") or sid.ends_with("_dn"):
		var v: String = sid.substr(0, sid.length() - 3)
		return "Click: %s %s (now %d %%)" % ["open" if sid.ends_with("_up") else "close", v.to_upper().replace("_", "-"), int(float(ww.get(v, 0.0)) * 100.0)]
	match sid:
		"dp": return "Click: read bed ΔP gauge"
		"clamp": return "Click: %s housing clamp" % ("close" if clamp_open else "open")
		"bed": return ("Click: lift out the bed" if bed_seated else "Housing empty") if clamp_open else ""
		"pump_switch": return "Click: P-201 %s" % ("OFF" if ww.get("pump_on", true) else "ON")
		"vib": return "Click: vibration test point (P-201)"
		"seal": return "Click: pump seal housing"
		"bleed": return "Click: %s bleed valve" % ("close" if ww.get("bleed", false) else "open")
		"press": return "Click: read outlet pressure"
		"flow": return "Click: read process flow"
		"diag_sel": return "Click: diagnosis tag (%s)" % DIAGS[diag_choice]
		"diag_ok": return "Click: record diagnosis %s" % DIAGS[diag_choice]
		"port": return "Click: draw a sample" if vial == "empty" else ""
		"an_slot": return "Click: put the vial in the analyzer" if vial == "at_port" else ("Click: empty the vial" if vial == "in_analyzer" and logged != "" else "")
		"an_mode": return "Click: analyzer mode (%s)" % MODES[mode]
		"an_pass": return "Click: log PASS"
		"an_fail": return "Click: log FAIL"
		"panel": return "Click: read WRS panel levels"
		"cycle": return "Click: START processing cycle"
		"lvl_cal": return "Click: CAL LEVEL (recalibrate the level sensor)"
		"tank_ok": return "Click: log — levels AGREE"
		"tank_bad": return "Click: log — SENSOR disagrees"
	if sid.begins_with("glass"):
		return "Click: read the %s sight glass" % ("POTABLE" if sid == "glass1" else "RAW")
	return ""


# Receptacle: the empty housing takes a bed.
func accepts_part(id: StringName, item: Node) -> bool:
	return id == &"bed" and clamp_open and not bed_seated and item != null and item.item_id in [&"mf_bed", &"ix_bed"]


func stow_part(id: StringName, item: Node3D) -> bool:
	if not accepts_part(id, item):
		return false
	var s: Node = sys()
	if item.item_id == &"ix_bed":
		# Physical fit check: the IX-1 bed's key ring doesn't match.
		item.return_to_rest()
		say("IX-1 won't seat — this housing is keyed for MF-2 beds. (IX-1 goes in the polishing column.)")
		sfx(&"fail")
		var c: Node = _carry()
		if c != null and not c.is_carrying():
			c.pick_up(item)
		return true
	s.water["filter_life"] = clampf(float(item.payload.get("condition", 1.0)), 0.0, 1.0)
	s.water["filter_kind"] = "mf_bed"
	consume_part(item)
	bed_seated = true
	flt_installed_new = true
	sfx(&"clunk")
	say("MF-2 bed seated. Close the clamp, restore flow, then sample the PRODUCT water.")
	_refresh()
	return true


func stow_hint(id: StringName, item: Node) -> String:
	return "Seat %s in the housing" % item.get_display_name() if id == &"bed" else ""


# --------------------------------------------------------------- update
func _process(delta: float) -> void:
	_update_occlusion(delta)
	var s: Node = sys()
	if s == null:
		return
	var ww: Dictionary = s.water
	# Priming: bleeding with the pump stopped and V-OUT closed vents the air.
	if ww["bleed"] and not ww["pump_on"] and float(ww["v_out"]) < 0.05:
		prime_bled += delta
		if prime_bled > 4.0 and ww["pump_fault"] == "air_lock":
			ww["pump_fault"] = ""
			pump_fixed = true
			say("Liquid at the bleed sight glass — air vented. Close BLEED.")
	elif ww["bleed"] and ww["pump_on"]:
		prime_bled = 0.0
	if has_open(&"b02_flow") and ww["processing"] and s.water_flow() >= 9.0:
		flow_ok_s += delta
	else:
		flow_ok_s = 0.0
	var running: bool = ww["processing"] and ww["pump_on"] and s.powered(0)
	set_loop(_pump_loop, _pump_stream(String(ww["pump_fault"])), running)
	set_loop(_flow_loop, null, running and s.water_flow() > 1.0)
	if Engine.get_process_frames() % 5 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	var s: Node = sys()
	if s == null:
		return
	var ww: Dictionary = s.water
	if _housing_lid != null:
		_housing_lid.rotation_degrees.z = 75.0 if clamp_open else 0.0
	if _bed_visual != null:
		_bed_visual.visible = bed_seated
	if _dp_gauge != null:
		_dp_gauge.text = "ΔP %.0f kPa\n%s" % [s.filter_dp(), "FILTER" if s.filter_dp() > 62.0 else "OK"]
	for v in _wheels:
		set_wheel(_wheels[v], float(ww[v]))
	if _pump_switch != null:
		_pump_switch.rotation_degrees.x = -30.0 if ww["pump_on"] else 30.0
	var running: bool = ww["processing"] and ww["pump_on"] and s.powered(0)
	light(_pump_lamp, Color(0.3, 0.95, 0.4) if ww["pump_fault"] == "" else Color(1.0, 0.6, 0.1), running)
	if _press != null:
		_press.text = "%.0f\nkPa" % s.water_pressure()
	if _flow != null:
		_flow.text = "FLOW %.1f L/h\n%s" % [s.water_flow(), "RUN" if running else ("IDLE" if ww["pump_on"] else "OFF")]
	if _drip != null:
		_drip.get_node("Pool").visible = ww["pump_fault"] == "seal_leak"
	if _bleed_handle != null:
		_bleed_handle.rotation_degrees.y = 90.0 if ww["bleed"] else 0.0
	if _bleed_glass != null:
		var m: StandardMaterial3D = _bleed_glass.material_override
		m.albedo_color = Color(0.95, 0.97, 1.0) if (ww["pump_fault"] == "air_lock" and prime_bled < 4.0) else Color(0.35, 0.55, 0.85)
	if _vial_port != null:
		_vial_port.visible = vial == "at_port"
		_vial_an.visible = vial == "in_analyzer"
	if _an_mode != null:
		_an_mode.rotation_degrees.z = -40.0 + mode * 40.0
	if _an != null:
		if vial == "in_analyzer":
			var val: String = ["%.0f µS/cm" % vial_cond, "%.2f NTU" % vial_turb, "22.1 °C"][mode]
			_an.text = "%s %s\n%s" % [MODES[mode], val, ("LOGGED " + logged.to_upper()) if logged != "" else vial_src.to_upper()]
		else:
			_an.text = "READY\nINSERT VIAL"
	if _panel != null:
		var st: Array = ww["starts"]
		var last: String = ("%s D%d %s" % [st.back()["t"], int(st.back()["day"]), st.back()["why"]]) if not st.is_empty() else "-"
		_panel.text = "STATUS %s\nRAW %3.0f L   POTABLE %3.0f L\nPRODUCT %.0f µS/cm  POT %.0f\nBED ΔP %.0f kPa  LIFE %d %%\nP-201 %s  %s\nLAST START %s" % [
			s.water_status(), s.tank_level_reading(false), s.tank_level_reading(true), s.product_cond(), float(ww["pot_cond"]),
			s.filter_dp(), int(float(ww["filter_life"]) * 100.0), "RUN" if running else ("IDLE" if ww["pump_on"] else "OFF"),
			"FAULT" if ww["pump_fault"] != "" and running else "", last]
	if _diag_label != null:
		_diag_label.text = "DIAGNOSIS TAG\n▶ %s\n%s" % [DIAGS[diag_choice], ("RECORDED: " + diag_confirmed) if diag_confirmed != "" else ""]
	for k in _glass.size():
		var vol: float = float(ww["potable_l"]) / 200.0 if k == 1 else float(ww["raw_l"]) / 60.0
		var g: MeshInstance3D = _glass[k]
		g.scale.y = clampf(vol, 0.02, 1.0) * 1.6
		g.position.y = 0.2 + 0.5 * clampf(vol, 0.02, 1.0) * 1.6


# ------------------------------------------------------------ orders
func task_rearm(t: StringName, seed: int) -> void:
	var s: Node = sys()
	if s == null:
		return
	var ww: Dictionary = s.water
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match t:
		&"b02_filter":
			if float(ww["filter_life"]) > 0.36:
				ww["filter_life"] = 0.3
			dp_read = false
			flt_installed_new = false
			flt_verified = false
		&"b02_sample":
			vial = "empty"
			logged = ""
			sample_ok = false
			reprocess_needed = false
			if rng.randf() < 0.5:
				ww["pot_cond"] = 46.0 + rng.randf() * 10.0
		&"b02_pump":
			pump_seed = ["air_lock", "seal_leak", "worn_bearing"][rng.randi() % 3]
			ww["pump_fault"] = pump_seed
			ww["processing"] = true
			diag_confirmed = ""
			vib_read = false
			pump_fixed = false
			prime_bled = 0.0
		&"b02_flow":
			ww["v_in"] = 0.25
			ww["v_rc"] = 0.75 if rng.randf() < 0.5 else 0.0
			ww["v_out"] = 1.0 if ww["v_rc"] > 0.0 else 0.5
			flow_ok_s = 0.0
			flow_read = false
		&"b02_tank":
			glass_read = [false, false]
			panel_read = false
			tank_verdict = ""
			ww["level_bias"] = 18.0 if rng.randf() < 0.35 else 0.0
	_refresh()


func task_done(t: StringName) -> bool:
	var s: Node = sys()
	if s == null:
		return false
	var ww: Dictionary = s.water
	var done := false
	match t:
		&"b02_filter":
			done = flt_installed_new and flt_verified and bed_seated and not clamp_open and float(ww["v_in"]) > 0.9 and ww["pump_on"]
			if done and not outcome.has(t):
				close_task(t, "repaired", "MF-2 bed housing", "bed spent (ΔP high)", "bed replaced", "product %.0f µS/cm PASS" % vial_cond)
		&"b02_sample":
			done = sample_ok and logged == "pass" and float(ww["v_rc"]) < 0.05
			if done and not outcome.has(t):
				close_task(t, "repaired" if reprocess_needed else "verified_normal", "QA analyzer / potable tank", "conductivity above limit" if reprocess_needed else "none", "recirculated through the bed" if reprocess_needed else "sample", "%.0f µS/cm %.2f NTU PASS" % [vial_cond, vial_turb])
		&"b02_pump":
			if diag_confirmed == "BEARING" and ww["pump_fault"] == "worn_bearing":
				# Recorded and deferred: no bearing cartridge on hand.
				done = true
				if not outcome.has(t):
					close_task(t, "deferred", "P-201", "worn bearing (whine, HF vibration)", "diagnosed; bearing cartridge needed (workshop / cargo)", "pump left running, monitored")
			else:
				done = diag_confirmed != "" and ww["pump_fault"] == "" and not ww["bleed"] and ww["pump_on"] and float(ww["v_out"]) > 0.9 and float(ww["v_in"]) > 0.9
				if done and not outcome.has(t):
					close_task(t, "repaired", "P-201", diag_confirmed.to_lower(), "primed" if pump_seed == "air_lock" else "seal kit replaced", "outlet %.0f kPa steady" % s.water_pressure())
		&"b02_flow":
			done = flow_read and flow_ok_s >= 5.0 and float(ww["v_rc"]) < 0.05
			if done and not outcome.has(t):
				close_task(t, "repaired", "WRS valves", "valves mis-set (low flow)", "V-IN / V-OUT open, V-RC closed", "flow %.1f L/h" % s.water_flow())
		&"b02_tank":
			done = tank_verdict != "" and absf(float(ww["level_bias"])) <= 5.0
			if done and not outcome.has(t):
				close_task(t, "sensor_fault" if tank_verdict == "sensor" else "verified_normal", "WRS tank level sensors", "potable level sensor offset" if tank_verdict == "sensor" else "none", "recalibrated" if tank_verdict == "sensor" else "sight glasses compared", "panel = sight glasses")
	return done


func task_next(t: StringName) -> Dictionary:
	var s: Node = sys()
	var ww: Dictionary = s.water if s != null else {}
	match t:
		&"b02_filter":
			if not flt_installed_new:
				if not dp_read:
					return next("Read the MF-2 bed ΔP gauge (Water Recovery, west wall)", "READ ΔP")
				if not _isolated() and not clamp_open:
					return next("Isolate the bed: close V-IN or stop P-201", "ISOLATE")
				if not clamp_open:
					return next("Open the housing clamp", "OPEN CLAMP")
				if bed_seated:
					return next("Lift out the spent bed", "REMOVE BED")
				return next("Seat a new MF-2 bed (spares rack)", "INSTALL MF-2")
			if clamp_open:
				return next("Close the housing clamp", "CLOSE CLAMP")
			if float(ww.get("v_in", 1.0)) < 0.9 or not ww.get("pump_on", true):
				return next("Restore flow: open V-IN, P-201 ON", "RESTORE")
			return next("Sample the PRODUCT water during a cycle and log PASS", "QA SAMPLE")
		&"b02_sample":
			if logged == "fail" and float(ww.get("v_rc", 0.0)) < 0.4:
				return next("Reprocess: open V-RC and run a cycle", "REPROCESS")
			if logged == "fail":
				return next("Sample again after recirculating", "RESAMPLE")
			if logged == "pass" and float(ww.get("v_rc", 0.0)) > 0.05:
				return next("Close V-RC", "CLOSE V-RC")
			return next("Take a water sample (port SP-2) and analyse it", "SAMPLE")
		&"b02_pump":
			if diag_confirmed == "":
				return next("Diagnose P-201: listen, read pressure / flow / vibration, record it", "DIAGNOSE")
			if ww.get("pump_fault", "") != "":
				return next("Repair P-201 (%s)" % diag_confirmed.to_lower(), "REPAIR P-201")
			return next("Restore: bleed closed, valves open, P-201 ON", "RESTORE")
		&"b02_flow":
			if not flow_read:
				return next("Read the WRS process flow (Water Recovery)", "READ FLOW")
			return next("Set V-IN / V-OUT open, V-RC closed; hold ≥ 9 L/h", "SET VALVES")
		&"b02_tank":
			if not (glass_read[0] and glass_read[1] and panel_read):
				return next("Compare the tank sight glasses with the panel levels", "COMPARE")
			return next("Log the result (AGREE / SENSOR)", "LOG")
	return {}


func task_progress(t: StringName) -> String:
	match t:
		&"b02_flow":
			return "%d s" % int(flow_ok_s)
		&"b02_tank":
			return "%d/3" % (int(glass_read[0]) + int(glass_read[1]) + int(panel_read))
	return ""


func task_detail(t: StringName) -> Array:
	var s: Node = sys()
	if s == null:
		return []
	return ["WRS: %s · raw %.0f L · potable %.0f L · product %.0f µS/cm · ΔP %.0f kPa" % [s.water_status(), float(s.water["raw_l"]), float(s.water["potable_l"]), s.product_cond(), s.filter_dp()]]


func task_feasible(t: StringName) -> bool:
	if t == &"b02_filter":
		return _spares == null or _spares.count(&"mf_bed") > 0
	if t == &"b02_pump":
		return _seal_rack == null or _seal_rack.count(&"pump_seal_kit") > 0
	return true


func task_severity(t: StringName) -> int:
	var s: Node = sys()
	if s != null and t == &"b02_filter" and float(s.water["pot_cond"]) > 45.0:
		return 2
	return 1


func state_dict() -> Dictionary:
	return {"clamp_open": clamp_open, "bed_seated": bed_seated, "dp_read": dp_read, "flt_installed_new": flt_installed_new, "flt_verified": flt_verified,
		"vial": vial, "vial_src": vial_src, "vial_cond": vial_cond, "vial_turb": vial_turb, "mode": mode, "mode_seen": mode_seen.duplicate(), "logged": logged,
		"reprocess_needed": reprocess_needed, "sample_ok": sample_ok, "diag_choice": diag_choice, "diag_confirmed": diag_confirmed, "vib_read": vib_read,
		"pump_fixed": pump_fixed, "pump_seed": pump_seed, "flow_read": flow_read, "glass_read": glass_read.duplicate(), "panel_read": panel_read,
		"tank_verdict": tank_verdict, "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in self:
			set(k, d[k])
	_refresh()
