extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-03 THERMAL CONTROL AND COOLANT PLANT -- the station's MAIN
## cooling loop (Deck A Engineering only monitors / services local
## hardware). Everything reads / drives deck_b_systems.thermal:
##   pumps      P-301 (primary) and P-302 (standby) on skids (west wall),
##              changeover lever, P-301 speed-controller RESET, vibration
##              test points (motor bearing / casing / mounting foot), IR
##              bearing temperature, suction strainer (cap, basket), four
##              mounting bolts;
##   manifold   supply (blue) / return (red) headers on the south wall,
##              branch valves V1 ENGINEERING+BATTERY, V2 LAB+ARCHIVE, V3
##              BYPASS (handwheels), a return-temperature gauge per branch;
##   radiators  RAD-1 / RAD-2 control panel (loop select, flow, outlet
##              temperature, actuator command vs position), RAD-2 loop
##              isolation valve and its actuator housing (a real part);
##   HX-1, the accumulator (loop pressure, charge valve), the thermal
##   control panel (supply / returns / equipment temperatures).
## Tasks: b03_inspect (E08), b03_balance, b03_pump (acoustic diagnosis --
## design-bible sound-based diagnosis), b03_radiator, b03_overheat (E11).

const DIAGS := ["BEARING", "RESTRICTION", "CAVITATION", "LOOSE MOUNT", "NO FAULT"]
const FAULT_OF := {"BEARING": "bearing", "RESTRICTION": "restriction", "CAVITATION": "cavitation", "LOOSE MOUNT": "loose_mount", "NO FAULT": ""}
# Inspection
var insp: Dictionary = {}          # point -> reading text
# Balance
var bal_s: float = 0.0
# Pump diagnosis
var probe: Dictionary = {}         # point -> true
var diag_choice: int = 0
var diag_confirmed: String = ""
var strainer_open: bool = false
var basket_out: bool = false
var basket_clean: bool = true
var bolts: Array = [true, true, true, true]
var pump_seed: String = ""
# Radiator
var rad_sel: int = 0
var rad_read: Array = [false, false]
var rad_isolated: bool = false
var rad_found: String = ""
# Overheat
var oh_ok_s: float = 0.0
var oh_reset: bool = false

var _wheels := {}
var _ret_gauges: Array = []
var _panel: Label3D
var _radp: Label3D
var _lever: Node3D
var _p301_lamp: StandardMaterial3D
var _p302_lamp: StandardMaterial3D
var _strainer_cap: Node3D
var _basket: MeshInstance3D
var _bolt_nodes: Array = []
var _diag_label: Label3D
var _rad_iso: Node3D
var _acc: Label3D
var _spares: Rack
var _p301_loop: AudioStreamPlayer3D
var _p302_loop: AudioStreamPlayer3D
var _hiss: AudioStreamPlayer3D
var _streams := {}


func _ready() -> void:
	_room_ready([&"b03_inspect", &"b03_balance", &"b03_pump", &"b03_radiator", &"b03_overheat"])
	_build_pumps()
	_build_manifold()
	_build_radiator_and_hx()
	_build_panel()
	text("B-03  THERMAL CONTROL", Vector3(-0.1, L.FLOOR_Y + 2.75, 4.12), 20, Color(1.0, 0.9, 0.75))
	_refresh()


func th() -> Dictionary:
	var s: Node = sys()
	return s.thermal if s != null else {}


# ------------------------------------------------------------- geometry
func _build_pumps() -> void:
	for k in 2:
		var p := Node3D.new()
		p.name = ["PumpP301", "PumpP302"][k]
		p.position = Vector3(-1.48, L.FLOOR_Y, 4.75 if k == 0 else 6.55)
		p.rotation_degrees.y = 90.0                # shaft along x, front faces +x
		add_child(p)
		dbox(Vector3(0.6, 0.08, 0.5), Vector3(0, 0.04, 0), Color(0.28, 0.3, 0.32), p, 0.5, true)
		dcyl(0.14, 0.32, Vector3(-0.08, 0.3, 0), Color(0.62, 0.28, 0.2) if k == 0 else Color(0.5, 0.52, 0.55), p, Vector3(0, 0, 90), 0.5, true)
		dcyl(0.12, 0.2, Vector3(0.18, 0.3, 0), Color(0.55, 0.57, 0.6), p, Vector3(0, 0, 90), 0.6)
		var lm := dbox(Vector3(0.03, 0.03, 0.01), Vector3(0.0, 0.52, 0.18), Color(0.2, 0.2, 0.2), p)
		if k == 0:
			_p301_lamp = lm.material_override
		else:
			_p302_lamp = lm.material_override
		text("%s  %s" % [["P-301", "P-302"][k], ["PRIMARY", "STANDBY"][k]], Vector3(0.0, 0.6, 0.2), 10, Color(0.95, 0.95, 0.9), p)
		if k == 0:
			part(&"pt_bearing", Vector3(0.12, 0.14, 0.16), Vector3(-0.22, 0.3, 0.0), p)
			part(&"pt_casing", Vector3(0.16, 0.16, 0.2), Vector3(0.18, 0.3, 0.0), p)
			part(&"pt_foot", Vector3(0.12, 0.08, 0.12), Vector3(0.24, 0.06, 0.2), p)
			# Mounting bolts.
			for b in 4:
				var bx: float = -0.24 + (b % 2) * 0.48
				var bz: float = -0.19 + int(b / 2) * 0.38
				var bn := Node3D.new()
				bn.position = Vector3(bx, 0.09, bz)
				p.add_child(bn)
				dcyl(0.018, 0.03, Vector3.ZERO, Color(0.7, 0.7, 0.72), bn, Vector3.ZERO, 0.8)
				_bolt_nodes.append(bn)
				part(StringName("bolt%d" % b), Vector3(0.06, 0.06, 0.06), Vector3(bx, 0.1, bz), p)
			# Suction strainer.
			var st := Node3D.new()
			st.position = Vector3(0.32, 0.22, -0.12)
			p.add_child(st)
			dcyl(0.06, 0.18, Vector3.ZERO, Color(0.25, 0.42, 0.62), st)
			_basket = dcyl(0.045, 0.12, Vector3(0, 0.0, 0), Color(0.5, 0.45, 0.35), st, Vector3.ZERO, 0.3)
			_strainer_cap = Node3D.new()
			_strainer_cap.position = Vector3(-0.065, 0.1, 0)
			st.add_child(_strainer_cap)
			dcyl(0.068, 0.03, Vector3(0.065, 0, 0), Color(0.75, 0.2, 0.15), _strainer_cap)
			part(&"strainer_cap", Vector3(0.14, 0.06, 0.14), Vector3(0, 0.11, 0), st)
			part(&"basket", Vector3(0.1, 0.14, 0.1), Vector3(0, 0.0, 0), st)
			text("STRAINER", Vector3(0, 0.2, 0.07), 8, Color(0.95, 0.95, 0.9), st)
			# Diagnosis tag.
			var d := Node3D.new()
			d.position = Vector3(0.0, 0.85, 0.22)
			p.add_child(d)
			dbox(Vector3(0.26, 0.16, 0.02), Vector3(0, 0, 0), Color(0.9, 0.86, 0.6), d)
			_diag_label = text("", Vector3(0, 0.02, 0.012), 9, Color(0.1, 0.1, 0.1), d)
			part(&"diag_sel", Vector3(0.16, 0.12, 0.05), Vector3(-0.03, 0.02, 0.02), d)
			button("diag_ok", Vector3(0.1, -0.05, 0.012), Color(0.3, 0.8, 0.4), d, Vector3(0.04, 0.03, 0.015))
			part(&"ir_bearing", Vector3(0.1, 0.1, 0.1), Vector3(-0.22, 0.46, 0.0), p)
		else:
			button("standby_start", Vector3(0.12, 0.52, 0.18), Color(0.3, 0.8, 0.95), p, Vector3(0.05, 0.03, 0.015))
	# Changeover lever (between the pumps, on the west wall).
	var lv := Node3D.new()
	lv.name = "Changeover"
	lv.position = Vector3(-1.79, L.FLOOR_Y + 1.15, 5.65)
	lv.rotation_degrees.y = 90.0
	add_child(lv)
	dbox(Vector3(0.24, 0.3, 0.04), Vector3(0, 0, 0.02), Color(0.24, 0.26, 0.28), lv)
	_lever = Node3D.new()
	_lever.position = Vector3(0, 0, 0.05)
	lv.add_child(_lever)
	dbox(Vector3(0.03, 0.16, 0.03), Vector3(0, 0.07, 0), Color(0.95, 0.72, 0.1), _lever)
	part(&"changeover", Vector3(0.12, 0.24, 0.08), Vector3(0, 0.02, 0.06), lv)
	text("PUMP CHANGEOVER\nP-301 ◄ ► P-302", Vector3(0, 0.2, 0.042), 9, Color(0.95, 0.95, 0.9), lv)
	button("p301_reset", Vector3(0.0, -0.11, 0.042), Color(0.95, 0.6, 0.15), lv, Vector3(0.05, 0.03, 0.012))
	text("P-301 SPEED CTRL RESET", Vector3(0, -0.15, 0.042), 7, Color(0.9, 0.9, 0.9), lv)
	_spares = rack("ThermalSpares", Vector3(-1.79, L.FLOOR_Y + 0.62, 5.5), 3, 0.15, [&"valve_actuator", &"bearing_cartridge", &"coolant_sensor"], "THERMAL SPARES", self, 90.0)
	spawn_part.call_deferred(&"valve_actuator", _spares)
	spawn_part.call_deferred(&"coolant_sensor", _spares)


func _build_manifold() -> void:
	var z: float = 4.13
	dcyl(0.05, 2.9, Vector3(-0.15, L.FLOOR_Y + 1.75, z + 0.1), Color(0.25, 0.42, 0.62), self, Vector3(0, 0, 90))
	dcyl(0.05, 2.9, Vector3(-0.15, L.FLOOR_Y + 0.75, z + 0.1), Color(0.62, 0.26, 0.2), self, Vector3(0, 0, 90))
	text("SUPPLY HEADER →", Vector3(-1.2, L.FLOOR_Y + 1.88, z + 0.16), 9, Color(0.6, 0.8, 1.0))
	text("← RETURN HEADER", Vector3(-1.2, L.FLOOR_Y + 0.62, z + 0.16), 9, Color(1.0, 0.65, 0.55))
	for v in [["v1", -0.9, "V1  ENGINEERING / BATTERY"], ["v2", -0.1, "V2  LAB / ARCHIVE"], ["v3", 0.7, "V3  BYPASS"]]:
		var x: float = v[1]
		dcyl(0.035, 1.0, Vector3(x, L.FLOOR_Y + 1.25, z + 0.1), Color(0.5, 0.52, 0.55), self)
		var wh: Node3D = handwheel(v[0], Vector3(x, L.FLOOR_Y + 1.25, z + 0.2), 0.08, self, true)
		_wheels[v[0]] = wh
		text(v[2], Vector3(x, L.FLOOR_Y + 1.05, z + 0.16), 8, Color(0.95, 0.95, 0.9))
		if v[0] != "v3":
			_ret_gauges.append(readout(Vector3(x, L.FLOOR_Y + 1.5, z + 0.17), Vector2(0.18, 0.08), self, 10))
			part(StringName("gauge_" + v[0]), Vector3(0.18, 0.1, 0.06), Vector3(x, L.FLOOR_Y + 1.5, z + 0.2))
	part(&"gauge_supply", Vector3(0.3, 0.12, 0.08), Vector3(0.0, L.FLOOR_Y + 1.75, z + 0.18))
	_hiss = machine_loop(loop_stream(3.0, func(t, i): return (fmod(sin(float(i) * 78.233) * 43758.5453, 1.0) - 0.5) * (0.2 + 0.08 * sin(TAU * 0.4 * t))), Vector3(-0.15, L.FLOOR_Y + 1.3, z + 0.1), -22.0)


func _build_radiator_and_hx() -> void:
	var r := Node3D.new()
	r.name = "RadiatorControl"
	r.position = Vector3(1.59, L.FLOOR_Y + 1.4, 5.7)
	r.rotation_degrees.y = -90.0
	add_child(r)
	dbox(Vector3(0.5, 0.42, 0.04), Vector3(0, 0, 0.02), Color(0.2, 0.22, 0.25), r)
	text("RADIATOR CONTROL  RAD-1 / RAD-2", Vector3(0, 0.24, 0.042), 9, Color(0.95, 0.95, 0.9), r)
	_radp = readout(Vector3(0, 0.03, 0.042), Vector2(0.44, 0.24), r, 9)
	part(&"rad_sel", Vector3(0.44, 0.24, 0.06), Vector3(0, 0.03, 0.05), r)
	# RAD-2 loop isolation valve + actuator housing (below the panel).
	_rad_iso = handwheel("rad_iso", Vector3(-0.12, -0.36, 0.06), 0.06, r, true, Color(0.2, 0.45, 0.75))
	text("RAD-2 ISOLATION", Vector3(-0.12, -0.27, 0.042), 8, Color(0.95, 0.95, 0.9), r)
	dbox(Vector3(0.14, 0.12, 0.1), Vector3(0.14, -0.36, 0.05), Color(0.3, 0.33, 0.36), r)
	text("VA-3 ACTUATOR", Vector3(0.14, -0.27, 0.042), 8, Color(0.95, 0.95, 0.9), r)
	part(&"actuator", Vector3(0.16, 0.14, 0.12), Vector3(0.14, -0.36, 0.06), r)
	# HX-1 and the accumulator.
	dbox(Vector3(0.34, 1.2, 0.56), Vector3(1.42, L.FLOOR_Y + 0.6, 6.7), Color(0.55, 0.57, 0.6), self, 0.6, true)
	text("HX-1  LOOP ⇄ RADIATORS", Vector3(1.24, L.FLOOR_Y + 1.3, 6.7), 9, Color(0.95, 0.95, 0.9), self, -90.0)
	part(&"hx", Vector3(0.1, 0.5, 0.5), Vector3(1.24, L.FLOOR_Y + 0.8, 6.7))
	dcyl(0.15, 0.9, Vector3(1.38, L.FLOOR_Y + 0.45, 4.48), Color(0.85, 0.85, 0.82), self, Vector3.ZERO, 0.3, true)
	_acc = readout(Vector3(1.2, L.FLOOR_Y + 1.05, 4.48), Vector2(0.14, 0.08), self, 10, Color(0.55, 0.95, 0.75), -90.0)
	button("acc_charge", Vector3(1.22, L.FLOOR_Y + 0.92, 4.48), Color(0.3, 0.8, 0.95), self, Vector3(0.015, 0.03, 0.05))
	text("ACCUMULATOR\nCHARGE", Vector3(1.21, L.FLOOR_Y + 1.18, 4.48), 8, Color(0.95, 0.95, 0.9), self, -90.0)
	_p301_loop = machine_loop(_pump_stream(""), Vector3(-1.48, L.FLOOR_Y + 0.3, 4.75), -8.0)
	_p302_loop = machine_loop(_pump_stream("standby"), Vector3(-1.48, L.FLOOR_Y + 0.3, 6.55), -9.0)


func _build_panel() -> void:
	var c := Node3D.new()
	c.name = "ThermalPanel"
	c.position = Vector3(-1.15, L.FLOOR_Y + 1.45, 7.29)
	c.rotation_degrees.y = 180.0
	add_child(c)
	dbox(Vector3(0.56, 0.42, 0.04), Vector3(0, 0, 0.02), Color(0.2, 0.22, 0.25), c)
	text("MAIN COOLANT LOOP", Vector3(0, 0.24, 0.042), 10, Color(0.95, 0.95, 0.9), c)
	_panel = readout(Vector3(0, 0.0, 0.042), Vector2(0.5, 0.34), c, 9)
	part(&"panel", Vector3(0.5, 0.34, 0.06), Vector3(0, 0, 0.05), c)


# ---------------------------------------------------------------- sound
func _pump_stream(fault: String) -> AudioStream:
	if _streams.has(fault):
		return _streams[fault]
	var gen: Callable
	match fault:
		"bearing":
			gen = func(t, i): return sin(TAU * 49.0 * t) * 0.2 + sin(TAU * 147.0 * t) * 0.1 + sin(TAU * 3100.0 * t) * (0.07 + 0.04 * sin(TAU * 13.0 * t)) + (fmod(sin(float(i) * 3.7) * 43758.5453, 1.0) - 0.5) * 0.14
		"restriction":
			gen = func(t, i): return sin(TAU * 52.0 * t) * 0.22 + sin(TAU * 156.0 * t) * 0.16 + sin(TAU * 312.0 * t) * 0.06 + (fmod(sin(float(i) * 12.9) * 43758.5453, 1.0) - 0.5) * 0.04
		"cavitation":
			gen = func(t, i):
				var crack: float = (fmod(sin(float(i) * 91.7) * 43758.5453, 1.0) - 0.5) * (1.0 if fmod(t * 23.0 + sin(t * 7.0) * 0.5, 1.0) < 0.3 else 0.15) * 0.9
				return sin(TAU * 49.0 * t) * 0.18 + sin(TAU * 147.0 * t) * 0.08 + crack * 0.6
		"loose_mount":
			gen = func(t, i):
				var knock: float = sin(TAU * 260.0 * t) * exp(-fmod(t, 1.0 / 24.5) * 140.0) * 0.5
				return sin(TAU * 24.5 * t) * 0.25 + sin(TAU * 49.0 * t) * 0.18 + knock + (fmod(sin(float(i) * 12.9) * 43758.5453, 1.0) - 0.5) * 0.05
		"speed_drop":
			gen = func(t, i): return sin(TAU * 18.0 * t) * 0.16 + sin(TAU * 54.0 * t) * 0.06 + (fmod(sin(float(i) * 12.9) * 43758.5453, 1.0) - 0.5) * 0.03
		"standby":
			gen = func(t, i): return sin(TAU * 58.0 * t) * 0.2 + sin(TAU * 174.0 * t) * 0.08 + (fmod(sin(float(i) * 12.9) * 43758.5453, 1.0) - 0.5) * 0.05
		_:
			gen = func(t, i): return sin(TAU * 49.0 * t) * 0.22 + sin(TAU * 147.0 * t) * 0.1 + sin(TAU * 294.0 * t) * 0.03 + (fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.05
	# A 2.0 s loop: every component above has a whole number of cycles
	# (24.5 Hz -> 49 cycles) so the loop is seamless.
	var s: AudioStream = loop_stream(2.0, gen)
	_streams[fault] = s
	return s


# --------------------------------------------------------------- clicks
func on_part(id: StringName) -> void:
	var s: Node = sys()
	if s == null:
		return
	var t: Dictionary = s.thermal
	var sid: String = String(id)
	if sid.ends_with("_up") or sid.ends_with("_dn"):
		var v: String = sid.substr(0, sid.length() - 3)
		if v == "rad_iso":
			rad_isolated = sid.ends_with("_dn")
			sfx(&"ratchet")
			say("RAD-2 loop %s" % ("ISOLATED" if rad_isolated else "open"))
		elif t.has(v):
			t[v] = clampf(float(t[v]) + (0.25 if sid.ends_with("_up") else -0.25), 0.0, 1.0)
			sfx(&"ratchet")
			say("%s %d %% open" % [v.to_upper(), int(float(t[v]) * 100.0)])
		_refresh()
		return
	match sid:
		"gauge_supply":
			insp["supply"] = "%.1f °C" % float(t["supply"])
			say("Supply header %.1f °C (normal 4-8.5)" % float(t["supply"]))
		"gauge_v1":
			insp["ret_eng"] = "%.1f °C" % float(t["ret_eng"])
			say("V1 return (Engineering) %.1f °C" % float(t["ret_eng"]))
		"gauge_v2":
			insp["ret_lab"] = "%.1f °C" % float(t["ret_lab"])
			say("V2 return (Lab / Archive) %.1f °C" % float(t["ret_lab"]))
		"hx":
			insp["hx"] = "ΔT %.1f" % (float(t["ret_eng"]) - float(t["supply"]))
			say("HX-1 in %.1f / out %.1f °C" % [(float(t["ret_eng"]) + float(t["ret_lab"])) * 0.5, float(t["supply"])])
		"pt_bearing", "pt_casing", "pt_foot":
			probe[sid] = true
			insp["vibration"] = "%.1f mm/s" % s.pump_vibration()
			say(_probe_text(sid))
		"ir_bearing":
			probe["ir"] = true
			var bt: float = 68.0 if t["fault"] == "bearing" else 41.0
			say("IR: P-301 drive-end bearing %.0f °C (normal < 55)" % bt)
		"diag_sel":
			diag_choice = (diag_choice + 1) % DIAGS.size()
			sfx(&"click")
		"diag_ok":
			_confirm_diag()
		"strainer_cap":
			if not strainer_open and not t["standby"]:
				say("P-301 is running — change over to P-302 before opening the strainer.")
				sfx(&"fail")
				return
			strainer_open = not strainer_open
			sfx(&"latch")
		"basket":
			if not strainer_open:
				say("Open the strainer cap first.")
			elif not basket_out:
				basket_out = true
				say("Basket out: %s" % ("clogged with debris and coolant scale." if not basket_clean else "clean."))
			elif not basket_clean:
				basket_clean = true
				sfx(&"ratchet")
				say("Basket cleaned.")
			else:
				basket_out = false
				sfx(&"latch")
				if t["fault"] == "restriction":
					t["fault"] = ""
				say("Basket refitted.")
		"changeover":
			t["standby"] = not t["standby"]
			sfx(&"clunk")
			say("Coolant loop on %s" % ("STANDBY P-302" if t["standby"] else "PRIMARY P-301"))
		"standby_start":
			if not t["standby"]:
				t["standby"] = true
				sfx(&"clunk")
				say("P-302 started; loop on standby.")
		"p301_reset":
			if t["fault"] == "speed_drop":
				if not t["standby"]:
					say("Change over to P-302 before resetting P-301's controller.")
					sfx(&"fail")
					return
				t["fault"] = ""
				oh_reset = true
				sfx(&"success")
				say("P-301 speed controller reset. Change back to the primary pump.")
			else:
				say("P-301 controller: no fault latched.")
		"acc_charge":
			t["accum"] = minf(float(t["accum"]) + 15.0, 215.0)
			sfx(&"ratchet")
			if t["fault"] == "cavitation" and float(t["accum"]) >= 200.0:
				t["fault"] = ""
			say("Loop pressure %.0f kPa" % float(t["accum"]))
		"rad_sel":
			rad_sel = (rad_sel + 1) % 2
			rad_read[rad_sel] = true
			sfx(&"click")
		"actuator":
			_actuator()
		"panel":
			insp["panel"] = s.thermal_status()
			say("Coolant loop: %s" % s.thermal_status())
		_:
			if sid.begins_with("bolt"):
				var b: int = int(sid.substr(4))
				if not bolts[b]:
					bolts[b] = true
					sfx(&"ratchet")
					say("Bolt %d torqued." % (b + 1))
					if bolts.all(func(x): return x) and t["fault"] == "loose_mount":
						t["fault"] = ""
				else:
					say("Bolt %d tight." % (b + 1))
	_refresh()


func _probe_text(pt: String) -> String:
	var s: Node = sys()
	var f: String = String(s.thermal["fault"])
	var at: String = {"pt_bearing": "DRIVE-END BEARING", "pt_casing": "PUMP CASING", "pt_foot": "MOUNTING FOOT"}[pt]
	var mm: float = 1.8
	var band: String = "1x running speed, smooth"
	match f:
		"bearing":
			mm = 7.8 if pt == "pt_bearing" else 3.1
			band = "HIGH-FREQUENCY 2-5 kHz" if pt == "pt_bearing" else "1x + HF"
		"loose_mount":
			mm = 9.5 if pt == "pt_foot" else 4.0
			band = "1/2x and 1x, rocking" if pt == "pt_foot" else "1x"
		"cavitation":
			mm = 4.6 if pt == "pt_casing" else 2.0
			band = "broadband crackle, random" if pt == "pt_casing" else "1x"
		"restriction":
			mm = 2.2
			band = "1x, blade-pass slightly up"
		"speed_drop":
			mm = 0.9
			band = "low speed (~0.35x)"
	if s.thermal["standby"]:
		mm = 0.2
		band = "P-301 stopped"
	return "%s: %.1f mm/s · %s" % [at, mm, band]


func _confirm_diag() -> void:
	var s: Node = sys()
	var t: Dictionary = s.thermal
	var truth: String = "NO FAULT"
	for k in FAULT_OF:
		if FAULT_OF[k] == String(t["fault"]):
			truth = k
	if probe.size() < 2:
		say("Probe at least two test points (and listen) before recording a diagnosis.")
		return
	if DIAGS[diag_choice] != truth:
		var flow: float = s.coolant_flow()
		say("Recorded %s — readings don't support it (flow %.0f L/min, worst vibration where?). Compare sound, vibration, temperature and flow." % [DIAGS[diag_choice], flow])
		sfx(&"fail")
		return
	diag_confirmed = truth
	sfx(&"success")
	match truth:
		"BEARING": say("Bearing wear: replace the bearing cartridge (P-301 on standby).")
		"RESTRICTION": say("Strainer restriction: change over to P-302, open the strainer, clean the basket.")
		"CAVITATION": say("Cavitation: loop pressure is low — charge the accumulator to 200 kPa+.")
		"LOOSE MOUNT": say("Loose mount: torque the four mounting bolts.")
		_: say("No fault found — logged as normal.")


func _actuator() -> void:
	var s: Node = sys()
	var t: Dictionary = s.thermal
	if t["rad_fault"] != "actuator":
		say("VA-3 actuator: command and position agree.")
		return
	if not rad_isolated:
		say("Isolate the RAD-2 loop before removing its actuator.")
		sfx(&"fail")
		return
	if held_kind() != &"valve_actuator":
		say("Stuck actuator: position 0 % at 100 % command. Fetch a VA-3 actuator (THERMAL SPARES).")
		rad_found = "actuator"
		return
	consume_part(held())
	t["rad_fault"] = ""
	t["rad"][1] = 1.0
	rad_found = "actuator"
	sfx(&"ratchet")
	say("VA-3 actuator replaced. Open the RAD-2 loop again.")


func part_prompt(id: StringName) -> String:
	var t: Dictionary = th()
	var sid: String = String(id)
	if sid.ends_with("_up") or sid.ends_with("_dn"):
		var v: String = sid.substr(0, sid.length() - 3)
		if v == "rad_iso":
			return "Click: %s RAD-2 loop" % ("isolate" if sid.ends_with("_dn") else "open")
		return "Click: %s %s (now %d %%)" % ["open" if sid.ends_with("_up") else "close", v.to_upper(), int(float(t.get(v, 0.0)) * 100.0)]
	match sid:
		"gauge_supply": return "Click: read the supply header temperature"
		"gauge_v1": return "Click: read the V1 (Engineering) return"
		"gauge_v2": return "Click: read the V2 (Lab / Archive) return"
		"hx": return "Click: read HX-1 temperatures"
		"pt_bearing", "pt_casing", "pt_foot": return "Click: vibration probe (%s)" % {"pt_bearing": "bearing", "pt_casing": "casing", "pt_foot": "mounting foot"}[sid]
		"ir_bearing": return "Click: IR the drive-end bearing"
		"diag_sel": return "Click: diagnosis tag (%s)" % DIAGS[diag_choice]
		"diag_ok": return "Click: record diagnosis %s" % DIAGS[diag_choice]
		"strainer_cap": return "Click: %s strainer cap" % ("close" if strainer_open else "open")
		"basket": return "Click: strainer basket" if strainer_open else ""
		"changeover": return "Click: change over to %s" % ("PRIMARY P-301" if t.get("standby", false) else "STANDBY P-302")
		"standby_start": return "Click: start P-302"
		"p301_reset": return "Click: reset P-301 speed controller"
		"acc_charge": return "Click: charge the accumulator (+15 kPa)"
		"rad_sel": return "Click: radiator panel — select loop (RAD-%d)" % (rad_sel + 1)
		"actuator": return "Click: VA-3 actuator (RAD-2)"
		"panel": return "Click: read the coolant loop status"
	if sid.begins_with("bolt"):
		return "Click: torque mounting bolt %d" % (int(sid.substr(4)) + 1)
	return ""


# --------------------------------------------------------------- update
func _process(delta: float) -> void:
	_update_occlusion(delta)
	var s: Node = sys()
	if s == null:
		return
	var t: Dictionary = s.thermal
	if has_open(&"b03_balance") and _in_band():
		bal_s += delta
	else:
		bal_s = 0.0
	if has_open(&"b03_overheat") and t["fault"] == "" and not t["standby"] and float(t["eng_T"]) < 30.0 and float(t["batt_T"]) < 30.0:
		oh_ok_s += delta
	else:
		oh_ok_s = 0.0
	var p1: bool = not t["standby"] and s.powered(0)
	set_loop(_p301_loop, _pump_stream(String(t["fault"])), p1)
	set_loop(_p302_loop, null, t["standby"] and s.powered(0))
	set_loop(_hiss, null, s.coolant_flow() > 2.0)
	if Engine.get_process_frames() % 5 == 0 and is_visible_in_tree():
		_refresh()


func _in_band() -> bool:
	var t: Dictionary = th()
	return float(t["ret_eng"]) >= 10.0 and float(t["ret_eng"]) <= 14.0 and float(t["ret_lab"]) >= 9.0 and float(t["ret_lab"]) <= 13.0 and float(t["v3"]) <= 0.26


func _refresh() -> void:
	var s: Node = sys()
	if s == null:
		return
	var t: Dictionary = s.thermal
	var hl: int = hint_level("mechanical")
	for v in _wheels:
		set_wheel(_wheels[v], float(t[v]))
	set_wheel(_rad_iso, 0.0 if rad_isolated else 1.0)
	if _ret_gauges.size() == 2:
		var bands := ["10-14", "9-13"]
		for k in 2:
			var val: float = float(t["ret_eng"]) if k == 0 else float(t["ret_lab"])
			var ok: bool = (val >= 10.0 and val <= 14.0) if k == 0 else (val >= 9.0 and val <= 13.0)
			(_ret_gauges[k] as Label3D).text = "RET %.1f °C\n%s" % [val, (("BAND " + bands[k]) if hl == 0 else ("OK" if ok else "HIGH" if val > 12.0 else "LOW")) if hl < 2 else ""]
	light(_p301_lamp, Color(0.3, 0.95, 0.4) if t["fault"] == "" else Color(1.0, 0.6, 0.1), not t["standby"])
	light(_p302_lamp, Color(0.3, 0.95, 0.4), t["standby"])
	if _lever != null:
		_lever.rotation_degrees.z = -35.0 if t["standby"] else 35.0
	if _strainer_cap != null:
		_strainer_cap.rotation_degrees.z = 80.0 if strainer_open else 0.0
	if _basket != null:
		_basket.visible = not basket_out
		(_basket.material_override as StandardMaterial3D).albedo_color = Color(0.45, 0.4, 0.3) if (t["fault"] == "restriction" and not basket_clean) else Color(0.7, 0.7, 0.72)
	for b in _bolt_nodes.size():
		(_bolt_nodes[b] as Node3D).position.y = 0.09 if bolts[b] else 0.12
	if _diag_label != null:
		_diag_label.text = "P-301 DIAGNOSIS\n▶ %s\n%s" % [DIAGS[diag_choice], ("RECORDED: " + diag_confirmed) if diag_confirmed != "" else ""]
	if _acc != null:
		_acc.text = "%.0f kPa" % float(t["accum"])
	if _radp != null:
		var rows: Array = []
		for k in 2:
			var eff: float = float(t["rad"][k])
			var flow_ok: bool = not (k == 1 and (t["rad_fault"] == "actuator" or rad_isolated))
			var outlet: float = float(t["supply"]) - 2.0 + (1.0 - eff) * 9.0
			var cmd: String = "CMD 100 %%  POS %s" % ("0 %" if (k == 1 and t["rad_fault"] == "actuator") else "100 %")
			rows.append("%sRAD-%d  FLOW %s  OUT %.1f °C\n   %s" % ["▶ " if rad_sel == k else "  ", k + 1, "OK" if flow_ok else "NONE", outlet, cmd])
		_radp.text = "\n".join(rows) + "\nSUPPLY %.1f °C  %s" % [float(t["supply"]), "HIGH" if float(t["supply"]) > 9.0 else "OK"]
	if _panel != null:
		var fl: Array = s.branch_flows()
		_panel.text = "STATUS %s   PUMP %s %s\nFLOW %.0f L/min  SUPPLY %.1f °C\nV1 %3d%% RET %.1f · V2 %3d%% RET %.1f · V3 %3d%%\nENG %.1f  BATT %.1f  LAB %.1f  ARCH %.1f °C\nRADIATORS %d %%   LOOP %.0f kPa" % [
			s.thermal_status(), "P-302" if t["standby"] else "P-301", "FAULT" if t["fault"] != "" and not t["standby"] else "", s.coolant_flow(), float(t["supply"]),
			int(float(t["v1"]) * 100.0), float(t["ret_eng"]), int(float(t["v2"]) * 100.0), float(t["ret_lab"]), int(float(t["v3"]) * 100.0),
			float(t["eng_T"]), float(t["batt_T"]), float(t["lab_T"]), float(t["arch_T"]), int(s.rad_eff() * 100.0), float(t["accum"])]


# ------------------------------------------------------------ orders
func task_rearm(type: StringName, seed: int) -> void:
	var s: Node = sys()
	if s == null:
		return
	var t: Dictionary = s.thermal
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match type:
		&"b03_inspect":
			insp = {}
		&"b03_balance":
			var seeds := [[0.25, 1.0, 0.5], [0.5, 0.25, 0.75], [1.0, 1.0, 0.75]]
			var pick: Array = seeds[rng.randi() % seeds.size()]
			t["v1"] = pick[0]
			t["v2"] = pick[1]
			t["v3"] = pick[2]
			bal_s = 0.0
		&"b03_pump":
			pump_seed = ["bearing", "restriction", "cavitation", "loose_mount"][rng.randi() % 4]
			t["fault"] = pump_seed
			probe = {}
			diag_confirmed = ""
			basket_clean = pump_seed != "restriction"
			basket_out = false
			strainer_open = false
			if pump_seed == "loose_mount":
				bolts = [true, false, true, false]
			if pump_seed == "cavitation":
				t["accum"] = 150.0
		&"b03_radiator":
			t["rad_fault"] = "actuator" if rng.randf() < 0.65 else "panel"
			t["rad"][1] = 0.35 if t["rad_fault"] == "actuator" else 0.8
			rad_read = [false, false]
			rad_isolated = false
			rad_found = ""
		&"b03_overheat":
			if t["fault"] == "":
				t["fault"] = "speed_drop"
			oh_ok_s = 0.0
			oh_reset = false
	_refresh()


func task_done(type: StringName) -> bool:
	var s: Node = sys()
	if s == null:
		return false
	var t: Dictionary = s.thermal
	var done := false
	match type:
		&"b03_inspect":
			done = insp.has("supply") and insp.has("ret_eng") and insp.has("ret_lab") and insp.has("vibration") and insp.has("hx")
			if done and not outcome.has(type):
				var normal: bool = s.thermal_status() == "OK"
				close_task(type, "verified_normal" if normal else "inconclusive", "main coolant loop", "none" if normal else s.thermal_status(), "inspection round (5 points)", "supply %s · vibration %s" % [insp["supply"], insp["vibration"]])
				if not normal and _dp != null:
					_dp.raise_order(&"b03_pump" if t["fault"] != "" else &"b03_balance", "found during loop inspection")
		&"b03_balance":
			done = bal_s >= 6.0
			if done and not outcome.has(type):
				close_task(type, "repaired", "coolant manifold", "branch flows unbalanced", "V1 %d %% · V2 %d %% · V3 %d %%" % [int(float(t["v1"]) * 100), int(float(t["v2"]) * 100), int(float(t["v3"]) * 100)], "returns in band 6 s")
		&"b03_pump":
			if diag_confirmed == "BEARING" and t["fault"] == "bearing":
				done = true
				if not outcome.has(type):
					close_task(type, "deferred" if _spares.count(&"bearing_cartridge") == 0 else "inconclusive", "P-301", "bearing wear (HF vibration, 68 °C bearing)", "diagnosed; bearing cartridge needed — workshop recondition", "standby available")
					if _dp != null:
						_dp.raise_order(&"b04_recondition", "P-301 bearing cartridge")
			else:
				done = diag_confirmed != "" and t["fault"] == "" and not strainer_open and not basket_out and not t["standby"]
				if done and not outcome.has(type):
					close_task(type, "repaired", "P-301", diag_confirmed.to_lower(), {"RESTRICTION": "strainer cleaned", "CAVITATION": "accumulator charged", "LOOSE MOUNT": "bolts torqued"}.get(diag_confirmed, "none"), "vibration %.1f mm/s, flow %.0f L/min" % [s.pump_vibration(), s.coolant_flow()])
		&"b03_radiator":
			if t["rad_fault"] == "panel" and rad_read[1]:
				done = true
				if not outcome.has(type):
					var clr: Node = _dp.clearance() if _dp != null else null
					close_task(type, "deferred" if clr != null and clr.allows("eva") else "needs_clearance", "RAD-2 radiator panel", "exterior panel degraded (flow OK, outlet warm)", "traced to the exterior panel", "EVA radiator inspection required")
			else:
				done = t["rad_fault"] == "" and not rad_isolated and rad_found == "actuator"
				if done and not outcome.has(type):
					close_task(type, "repaired", "RAD-2 VA-3 actuator", "actuator stuck (POS 0 % at CMD 100 %)", "loop isolated, actuator replaced", "supply %.1f °C" % float(t["supply"]))
		&"b03_overheat":
			done = oh_ok_s >= 5.0
			if done and not outcome.has(type):
				close_task(type, "repaired", "coolant loop / P-301", "speed controller fault, Engineering overheating", "standby pump, controller reset, primary restored", "ENG %.0f °C BATT %.0f °C" % [float(t["eng_T"]), float(t["batt_T"])])
	return done


func task_next(type: StringName) -> Dictionary:
	var t: Dictionary = th()
	match type:
		&"b03_inspect":
			for k in [["supply", "Read the supply header (Thermal Control)", "SUPPLY"], ["ret_eng", "Read the V1 return", "V1 RET"], ["ret_lab", "Read the V2 return", "V2 RET"], ["vibration", "Probe P-301 vibration", "VIBRATION"], ["hx", "Read HX-1", "HX-1"]]:
				if not insp.has(k[0]):
					return next(k[1], k[2])
		&"b03_balance":
			return next("Balance the branches: V1 return 10-14 °C, V2 return 9-13 °C, bypass ≤ 25 %", "BALANCE")
		&"b03_pump":
			if diag_confirmed == "":
				return next("Listen to P-301; probe vibration, IR the bearing; record a diagnosis", "DIAGNOSE")
			return next("Correct the fault (%s) and return to P-301" % diag_confirmed.to_lower(), "REPAIR")
		&"b03_radiator":
			if not rad_read[1]:
				return next("Trace the supply temperature: radiator panel, select RAD-2", "TRACE")
			if t.get("rad_fault", "") == "actuator":
				return next("Isolate RAD-2 and replace its VA-3 actuator", "ACTUATOR")
			return next("Open the RAD-2 loop", "RESTORE")
		&"b03_overheat":
			if t.get("fault", "") == "speed_drop" and not t.get("standby", false):
				return next("Cooling flow low — change over to STANDBY P-302", "CHANGEOVER")
			if t.get("fault", "") == "speed_drop":
				return next("Reset the P-301 speed controller", "RESET P-301")
			if t.get("standby", false):
				return next("Change back to PRIMARY P-301", "PRIMARY")
			return next("Hold Engineering and battery below 30 °C", "STABILISE")
	return {}


func task_progress(type: StringName) -> String:
	match type:
		&"b03_inspect":
			return "%d/5" % insp.size()
		&"b03_balance":
			return "%d s" % int(bal_s)
	return ""


func task_detail(_type: StringName) -> Array:
	var s: Node = sys()
	return ["Coolant loop: %s · supply %.1f °C · ENG %.1f · BATT %.1f °C" % [s.thermal_status(), float(s.thermal["supply"]), float(s.thermal["eng_T"]), float(s.thermal["batt_T"])]] if s != null else []


func task_severity(type: StringName) -> int:
	var t: Dictionary = th()
	if type == &"b03_overheat":
		return 3 if float(t.get("batt_T", 0.0)) > 33.0 else 2
	return 1


func state_dict() -> Dictionary:
	return {"insp": insp.duplicate(), "probe": probe.duplicate(), "diag_choice": diag_choice, "diag_confirmed": diag_confirmed, "strainer_open": strainer_open,
		"basket_out": basket_out, "basket_clean": basket_clean, "bolts": bolts.duplicate(), "pump_seed": pump_seed, "rad_sel": rad_sel, "rad_read": rad_read.duplicate(),
		"rad_isolated": rad_isolated, "rad_found": rad_found, "oh_reset": oh_reset, "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in self:
			set(k, d[k])
	_refresh()
