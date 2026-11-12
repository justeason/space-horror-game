extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-01 LOWER JUNCTION / UTILITY SPINE equipment.
##   LDP-B  lower-deck distribution panel (Bus B): a hinged cover, four
##          circuit breakers with lamps, a selector knob and a meter that
##          reads each circuit (and the feeds) from the authoritative model.
##          [b01_utility] read every circuit; a tripped breaker is reset only
##          after its circuit reads "no short"; read it again; close.
##   ELP-B  emergency lighting panel: TEST switches Deck B's lights to the
##          emergency strips (the strips really glow, the ceiling lights
##          really dim) for a few seconds; a failed zone module stays dark
##          and is replaced from the panel's own spare clip.
##          [b01_lights]
##   RPT-B  lower-deck comms repeater: link LED + signal bars; a loose
##          antenna lead is reseated behind its access door. [b01_repeater]
##   Spine riser (service spine): the coolant SUPPLY riser and its
##          insulation jacket, a humidity / dew-point monitor and the local
##          vent fan. [l06_condensation] (GAME_DESIGN L06): condensation is
##          investigated physically: pipe surface temperature (IR), air
##          humidity / dew point, airflow; cause = a gap in the insulation
##          OR the local vent fan off -- each fixed where it is.

const SEL := ["B1", "B2", "B3", "B4", "FEED"]
# LDP-B
var cover_open: bool = false
var sel: int = 0
var util_read: Array = [false, false, false, false, false]
var util_reset_reads: int = 0
var util_seed: String = ""          # "" (normal) | tripped | nuisance
var util_trip: int = -1
var util_reset: bool = false
var util_reread: bool = false
# ELP-B
var em_testing: float = -1.0
var em_failed: int = -1
var em_tested_ok: bool = false
var em_tests: int = 0
var em_replaced: bool = false
var em_reset: bool = true
# RPT-B
var rpt_open: bool = false
var rpt_loose: bool = false
var rpt_was_loose: bool = false
var rpt_inspected: bool = false
# Spine riser (L06)
var cond_cause: String = ""         # "" | insulation | vent
var cond_ir: bool = false
var cond_dew: bool = false
var cond_air: bool = false
var cond_fixed: bool = false
var vent_on: bool = true
var wrap_ok: bool = true
var wet: float = 0.0

var _cover: Node3D
var _knob: Node3D
var _meter: Label3D
var _brk: Array = []
var _brk_lamps: Array = []
var _em_lamps: Array = []
var _em_bat: Label3D
var _rpt_door: Node3D
var _rpt_lamp: StandardMaterial3D
var _rpt_bars: Label3D
var _rpt_lead: Node3D
var _spare_rack: Rack
var _jacket_gap: MeshInstance3D
var _drops: Node3D
var _hum: Label3D
var _fan_lamp: StandardMaterial3D
var _fan_blades: Node3D
var _ir_label: Label3D
var _fan_loop: AudioStreamPlayer3D
var _em_applied: bool = false


func _ready() -> void:
	_room_ready([&"b01_utility", &"b01_lights", &"b01_repeater", &"l06_condensation"])
	_build_ldp()
	_build_elp()
	_build_repeater()
	_build_riser()
	_build_signs()
	_refresh()


# ---------------------------------------------------------------- LDP-B
func _build_ldp() -> void:
	var p := Node3D.new()
	p.name = "LDP_B"
	p.position = Vector3(-5.29, L.FLOOR_Y + 1.25, 9.12)
	p.rotation_degrees.y = 90.0           # faces +x into the room
	add_child(p)
	dbox(Vector3(0.56, 0.62, 0.08), Vector3(0, 0, 0.04), Color(0.22, 0.24, 0.27), p)
	dbox(Vector3(0.58, 0.05, 0.09), Vector3(0, 0.33, 0.04), Color(0.95, 0.72, 0.1), p)
	text("LDP-B  LOWER DECK DISTRIBUTION · BUS B", Vector3(0, 0.37, 0.09), 11, Color(0.95, 0.95, 0.9), p)
	for i in 4:
		var x: float = -0.18 + i * 0.12
		var b := Node3D.new()
		b.position = Vector3(x, 0.12, 0.085)
		p.add_child(b)
		dbox(Vector3(0.05, 0.1, 0.02), Vector3.ZERO, Color(0.1, 0.1, 0.11), b)
		var lever := dbox(Vector3(0.02, 0.05, 0.03), Vector3(0, 0.02, 0.02), Color(0.9, 0.9, 0.88), b)
		lever.name = "Lever"
		_brk.append(b)
		var lm := dbox(Vector3(0.02, 0.02, 0.01), Vector3(x, 0.21, 0.085), Color(0.2, 0.2, 0.2), p)
		_brk_lamps.append(lm.material_override)
		text("%s\n%s" % [CIRCUITS_SHORT[i], ["PUMPS", "LAB/ARC", "HABITAT", "LOGIST."][i]], Vector3(x, 0.02, 0.087), 8, Color(0.85, 0.88, 0.85), p)
		part(StringName("brk%d" % i), Vector3(0.07, 0.12, 0.06), Vector3(x, 0.12, 0.1), p)
	_meter = readout(Vector3(-0.08, -0.14, 0.085), Vector2(0.3, 0.12), p, 11)
	_knob = Node3D.new()
	_knob.position = Vector3(0.17, -0.14, 0.09)
	p.add_child(_knob)
	dcyl(0.03, 0.025, Vector3.ZERO, Color(0.1, 0.1, 0.11), _knob, Vector3(90, 0, 0))
	dbox(Vector3(0.006, 0.03, 0.012), Vector3(0, 0.014, 0.014), Color(0.95, 0.95, 0.9), _knob)
	part(&"ldp_knob", Vector3(0.08, 0.08, 0.06), Vector3(0.17, -0.14, 0.1), p)
	text("SELECT", Vector3(0.17, -0.2, 0.087), 8, Color(0.8, 0.8, 0.8), p)
	_cover = Node3D.new()
	_cover.position = Vector3(-0.28, 0.0, 0.1)
	p.add_child(_cover)
	dbox(Vector3(0.56, 0.56, 0.015), Vector3(0.28, 0, 0), Color(0.42, 0.44, 0.47), _cover, 0.5)
	text("LDP-B · 120 V DC\nISOLATE FEEDS AT ENGINEERING", Vector3(0.28, 0.1, 0.009), 10, Color(0.1, 0.1, 0.1), _cover)
	part(&"ldp_cover", Vector3(0.56, 0.56, 0.04), Vector3(0.28, 0, 0.02), _cover)


const CIRCUITS_SHORT := ["B1", "B2", "B3", "B4"]


func _meter_text() -> String:
	var s: Node = sys()
	if s == null:
		return ""
	if sel < 4:
		var c: Array = s.CIRCUITS[sel]
		var on: bool = s.power["on"][sel]
		var v: float = 120.0 * s.feed_factor(sel)
		var kw: float = s.load_kw(sel) if on and s.powered(sel) else 0.0
		var st: String = "OK" if on and s.powered(sel) else ("NO SHORT · OFF" if not on else "NO FEED")
		return "%s %s\n%.0f V  %.2f/%.1f kW  %s" % [c[0], c[1], v, kw, float(c[2]), st]
	var f1: String = "DROPOUT" if s.power["dropout"] else "OK"
	return "FEED-1 (ENG-AUX) %s\nFEED-2 (ESS) %.2f/%.1f kW" % [f1, s.feed2_load(), s.FEED2_RATING]


# ---------------------------------------------------------------- ELP-B
func _build_elp() -> void:
	var p := Node3D.new()
	p.name = "ELP_B"
	p.position = Vector3(-2.68, L.FLOOR_Y + 1.3, 9.49)
	p.rotation_degrees.y = 180.0          # faces -z into the room
	add_child(p)
	dbox(Vector3(0.36, 0.44, 0.07), Vector3(0, 0, 0.035), Color(0.24, 0.26, 0.28), p)
	dbox(Vector3(0.38, 0.04, 0.08), Vector3(0, 0.24, 0.035), Color(0.85, 0.2, 0.15), p)
	text("ELP-B  EMERGENCY LIGHTING", Vector3(0, 0.27, 0.075), 10, Color(0.95, 0.95, 0.9), p)
	for i in 3:
		var x: float = -0.1 + i * 0.1
		var lm := dbox(Vector3(0.03, 0.03, 0.01), Vector3(x, 0.14, 0.075), Color(0.2, 0.2, 0.2), p)
		_em_lamps.append(lm.material_override)
		text(["Z1 JCT", "Z2 SPINE", "Z3 HALLS"][i], Vector3(x, 0.1, 0.075), 8, Color(0.85, 0.85, 0.85), p)
		part(StringName("em_mod%d" % i), Vector3(0.08, 0.07, 0.05), Vector3(x, 0.14, 0.09), p)
	_em_bat = text("", Vector3(0, 0.02, 0.075), 10, Color(0.55, 0.95, 0.75), p)
	button("em_test", Vector3(-0.08, -0.1, 0.075), Color(0.95, 0.75, 0.2), p)
	text("TEST", Vector3(-0.08, -0.14, 0.075), 8, Color(0.9, 0.9, 0.9), p)
	button("em_reset", Vector3(0.08, -0.1, 0.075), Color(0.3, 0.8, 0.95), p)
	text("RESET", Vector3(0.08, -0.14, 0.075), 8, Color(0.9, 0.9, 0.9), p)
	# The spare-module clip under the panel (real parts).
	_spare_rack = rack("EmSpareClip", Vector3(-2.82, L.FLOOR_Y + 0.92, 9.42), 2, 0.12, [&"lamp_module"], "SPARE LAMP MODULES", self, 180.0)
	spawn_part.call_deferred(&"lamp_module", _spare_rack)
	spawn_part.call_deferred(&"lamp_module", _spare_rack)


# ---------------------------------------------------------------- RPT-B
func _build_repeater() -> void:
	var p := Node3D.new()
	p.name = "RPT_B"
	p.position = Vector3(-4.95, L.FLOOR_Y + 1.85, 6.51)
	add_child(p)                         # faces +z (default)
	dbox(Vector3(0.3, 0.24, 0.1), Vector3(0, 0, 0.05), Color(0.3, 0.32, 0.35), p)
	text("RPT-B  INTERCOM / DATA REPEATER", Vector3(0, 0.16, 0.101), 9, Color(0.95, 0.95, 0.9), p)
	var lm := dbox(Vector3(0.025, 0.025, 0.01), Vector3(-0.1, 0.07, 0.102), Color(0.2, 0.2, 0.2), p)
	_rpt_lamp = lm.material_override
	_rpt_bars = text("", Vector3(0.04, 0.07, 0.102), 11, Color(0.55, 0.95, 0.75), p)
	dcyl(0.006, 0.34, Vector3(0.11, 0.3, 0.05), Color(0.2, 0.2, 0.22), p)
	_rpt_lead = Node3D.new()
	_rpt_lead.position = Vector3(0.0, -0.04, 0.06)
	p.add_child(_rpt_lead)
	dbox(Vector3(0.05, 0.03, 0.03), Vector3.ZERO, Color(0.75, 0.6, 0.2), _rpt_lead, 0.8)
	part(&"rpt_lead", Vector3(0.08, 0.06, 0.06), Vector3(0.0, -0.04, 0.08), p)
	_rpt_door = Node3D.new()
	_rpt_door.position = Vector3(-0.14, -0.04, 0.105)
	p.add_child(_rpt_door)
	dbox(Vector3(0.28, 0.1, 0.01), Vector3(0.14, 0, 0), Color(0.45, 0.47, 0.5), _rpt_door)
	part(&"rpt_door", Vector3(0.28, 0.1, 0.04), Vector3(0.14, 0, 0.01), _rpt_door)


# ------------------------------------------------------- spine riser L06
func _build_riser() -> void:
	var x: float = 1.25
	var zf: float = 7.52                   # spine south wall face
	var p := Node3D.new()
	p.name = "SpineRiser"
	p.position = Vector3(x, L.FLOOR_Y, zf)
	add_child(p)
	dcyl(0.04, 2.55, Vector3(0, 1.28, 0.075), Color(0.25, 0.42, 0.62), p)
	# Insulation jacket in two halves; the GAP (when present) shows bare pipe.
	dcyl(0.06, 0.95, Vector3(0, 0.6, 0.075), Color(0.75, 0.75, 0.72), p, Vector3.ZERO, 0.0)
	dcyl(0.06, 0.95, Vector3(0, 2.0, 0.075), Color(0.75, 0.75, 0.72), p, Vector3.ZERO, 0.0)
	_jacket_gap = dcyl(0.06, 0.45, Vector3(0, 1.3, 0.075), Color(0.75, 0.75, 0.72), p, Vector3.ZERO, 0.0)
	_drops = Node3D.new()
	p.add_child(_drops)
	for k in 7:
		var d := dcyl(0.006, 0.01, Vector3(sin(k * 1.7) * 0.042, 1.12 + k * 0.05, 0.075 + cos(k * 1.7) * 0.042), Color(0.75, 0.85, 0.95), _drops, Vector3(90, 0, 0), 0.9)
		d.name = "Drop%d" % k
	dbox(Vector3(0.22, 0.03, 0.18), Vector3(0, 0.015, 0.12), Color(0.5, 0.52, 0.55), p)
	text("CS-SUPPLY RISER · 7 °C", Vector3(0.14, 1.7, 0.03), 9, Color(0.9, 0.92, 0.9), p)
	part(&"riser", Vector3(0.14, 2.4, 0.12), Vector3(0, 1.25, 0.07), p)
	part(&"wrap", Vector3(0.15, 0.5, 0.12), Vector3(0, 1.3, 0.08), p)
	# Humidity / dew-point monitor and the local vent fan (north wall).
	var m := Node3D.new()
	m.name = "SpineClimate"
	m.position = Vector3(0.75, L.FLOOR_Y + 1.5, 8.49)
	m.rotation_degrees.y = 180.0
	add_child(m)
	dbox(Vector3(0.22, 0.14, 0.05), Vector3(0, 0, 0.025), Color(0.22, 0.24, 0.26), m)
	_hum = text("", Vector3(0, 0, 0.052), 10, Color(0.55, 0.95, 0.75), m)
	part(&"hum", Vector3(0.24, 0.16, 0.06), Vector3(0, 0, 0.04), m)
	var fan := Node3D.new()
	fan.name = "SpineVentFan"
	fan.position = Vector3(1.7, L.FLOOR_Y + 2.15, 8.49)
	fan.rotation_degrees.y = 180.0
	add_child(fan)
	dbox(Vector3(0.3, 0.3, 0.06), Vector3(0, 0, 0.03), Color(0.3, 0.31, 0.33), fan)
	_fan_blades = Node3D.new()
	_fan_blades.position = Vector3(0, 0, 0.065)
	fan.add_child(_fan_blades)
	for k in 4:
		var bl := dbox(Vector3(0.11, 0.035, 0.008), Vector3(0.06, 0, 0), Color(0.15, 0.15, 0.16), _fan_blades)
		bl.rotation.z = k * PI * 0.5
		bl.position = Vector3(cos(k * PI * 0.5) * 0.06, sin(k * PI * 0.5) * 0.06, 0)
	var fl := dbox(Vector3(0.03, 0.03, 0.01), Vector3(0.18, -0.12, 0.06), Color(0.2, 0.2, 0.2), fan)
	_fan_lamp = fl.material_override
	part(&"fan_switch", Vector3(0.1, 0.1, 0.06), Vector3(0.18, -0.12, 0.08), fan)
	text("LOCAL VENT VF-B2", Vector3(0, 0.2, 0.065), 9, Color(0.9, 0.9, 0.9), fan)
	_ir_label = text("", Vector3(1.4, L.FLOOR_Y + 1.92, 7.53), 10, Color(0.95, 0.85, 0.5))
	_fan_loop = machine_loop(loop_stream(2.0, func(t, _i): return sin(TAU * 96.0 * t) * 0.18 + sin(TAU * 192.0 * t) * 0.05 + (fmod(sin(float(_i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.12), Vector3(1.7, L.FLOOR_Y + 2.15, 8.45), -18.0)


func _build_signs() -> void:
	text("◄ B-08 CARGO\n▲ B-05 LAB · B-06 BOTANY · B-07 MEDICAL\n▼ B-04 WORKSHOP\n► B-02 WATER · B-03 THERMAL · B-09 ARCHIVE", Vector3(-2.31, L.FLOOR_Y + 2.35, 9.05), 12, Color(0.95, 0.92, 0.75), self, -90.0)
	text("B-01  LOWER JUNCTION", Vector3(-3.6, L.FLOOR_Y + 2.6, 6.52), 20, Color(0.95, 0.95, 0.9))


# --------------------------------------------------------------- clicks
func on_part(id: StringName) -> void:
	var s: Node = sys()
	var sid: String = String(id)
	match sid:
		"ldp_cover":
			cover_open = not cover_open
			sfx(&"latch")
			if cover_open:
				_read()
		"ldp_knob":
			sel = (sel + 1) % SEL.size()
			sfx(&"click")
			if cover_open:
				_read()
			else:
				say("Open the LDP-B cover to read the meter.")
		"em_test":
			if em_testing >= 0.0:
				return
			em_testing = 0.0
			em_reset = false
			sfx(&"click")
			say("Emergency lighting test: Deck B switches to the strips (6 s).")
		"em_reset":
			if em_testing >= 0.0:
				say("Wait for the test to finish.")
				return
			em_reset = true
			sfx(&"click")
			if em_tested_ok and has_open(&"b01_lights"):
				close_task(&"b01_lights", "repaired" if em_replaced else "verified_normal", "ELP-B emergency lighting", "zone Z%d module failed" % (em_failed + 1) if em_replaced else "none", "module replaced, retested" if em_replaced else "test", "all zones lit on battery")
		"rpt_door":
			rpt_open = not rpt_open
			if rpt_open:
				rpt_inspected = true
			sfx(&"latch")
		"rpt_lead":
			if not rpt_open:
				say("Open the repeater's access door first.")
			elif rpt_loose:
				rpt_loose = false
				sfx(&"latch")
				say("Antenna lead reseated. Watch the link.")
			else:
				say("Antenna lead seated.")
		"riser":
			cond_ir = true
			var t_pipe: float = float(s.thermal["supply"]) if s != null else 7.0
			say("IR: riser surface %.1f °C %s" % [t_pipe + (0.0 if (cond_cause == "insulation" and not wrap_ok) else 9.5), "(bare pipe at the jacket gap)" if cond_cause == "insulation" and not wrap_ok else "(jacket surface)"])
		"hum":
			cond_dew = true
			say("Spine air %.0f %% RH · 22 °C · dew point %.1f °C" % [_rh(), _dew()])
		"fan_switch":
			vent_on = not vent_on
			cond_air = true
			sfx(&"click")
			say("Local vent VF-B2 %s." % ("ON" if vent_on else "OFF"))
		"wrap":
			if cond_cause == "insulation" and not wrap_ok:
				if not cond_ir:
					say("Check the pipe's surface temperature first (IR).")
					return
				wrap_ok = true
				sfx(&"ratchet")
				say("Insulation jacket closed over the bare section.")
			else:
				say("Jacket intact.")
		_:
			if sid.begins_with("brk"):
				_breaker(int(sid.substr(3)))
			elif sid.begins_with("em_mod"):
				_em_module(int(sid.substr(6)))
	_refresh()


func _read() -> void:
	util_read[sel] = true
	if sel == util_trip and util_reset:
		util_reread = true
	say(_meter_text().replace("\n", " · "))


func _breaker(i: int) -> void:
	var s: Node = sys()
	if s == null:
		return
	if not cover_open:
		say("Open the LDP-B cover first.")
		return
	if s.power["on"][i]:
		say("%s is ON. (Do not switch live circuits off without isolating their loads.)" % CIRCUITS_SHORT[i])
		return
	if not util_read[i] and sel != i:
		say("Read %s on the meter first (it must show NO SHORT)." % CIRCUITS_SHORT[i])
		return
	s.power["on"][i] = true
	sfx(&"clunk")
	if i == util_trip:
		util_reset = true
		util_reread = false
	say("%s reset. Read it again under load." % CIRCUITS_SHORT[i])


func _em_module(i: int) -> void:
	if i != em_failed or em_replaced:
		say("Zone Z%d module OK." % (i + 1))
		return
	if held_kind() != &"lamp_module":
		say("Zone Z%d module failed — take a spare lamp module from the clip under the panel." % (i + 1))
		return
	consume_part(held())
	em_replaced = true
	em_tested_ok = false
	sfx(&"latch")
	say("Zone Z%d module replaced. Run the test again." % (i + 1))


func part_prompt(id: StringName) -> String:
	var sid: String = String(id)
	match sid:
		"ldp_cover":
			return "Click: %s LDP-B cover" % ("close" if cover_open else "open")
		"ldp_knob":
			return "Click: meter selector (now %s)" % SEL[sel]
		"em_test":
			return "Click: TEST emergency lighting" if em_testing < 0.0 else "Testing…"
		"em_reset":
			return "Click: RESET (end of test)"
		"rpt_door":
			return "Click: %s repeater access door" % ("close" if rpt_open else "open")
		"rpt_lead":
			return "Click: reseat antenna lead" if rpt_open else ""
		"riser":
			return "Click: IR-check the riser surface"
		"hum":
			return "Click: read humidity / dew point"
		"fan_switch":
			return "Click: local vent VF-B2 %s" % ("OFF" if vent_on else "ON")
		"wrap":
			return "Click: close the insulation jacket" if (cond_cause == "insulation" and not wrap_ok) else "Insulation jacket"
	if sid.begins_with("brk"):
		var i: int = int(sid.substr(3))
		var s: Node = sys()
		var on: bool = s != null and s.power["on"][i]
		return "Breaker %s %s%s" % [CIRCUITS_SHORT[i], "ON" if on else "OFF — click to reset", "" if cover_open else " (cover closed)"]
	if sid.begins_with("em_mod"):
		var j: int = int(sid.substr(6))
		return "Zone Z%d module%s" % [j + 1, " — click to replace (holding a spare)" if j == em_failed and not em_replaced else ""]
	return ""


func _rh() -> float:
	return 58.0 if vent_on else 74.0


func _dew() -> float:
	var rh: float = _rh()
	var a := 17.27
	var b := 237.7
	var g: float = a * 22.0 / (b + 22.0) + log(rh / 100.0)
	return b * g / (a - g)


func _condensing() -> bool:
	var s: Node = sys()
	var pipe: float = float(s.thermal["supply"]) if s != null else 7.0
	var surface: float = pipe if (cond_cause == "insulation" and not wrap_ok) else pipe + 9.5
	return surface < _dew()


# -------------------------------------------------------------- update
func _process(delta: float) -> void:
	_update_occlusion(delta)
	if em_testing >= 0.0:
		em_testing += delta
		if em_testing >= 6.0:
			em_testing = -1.0
			em_tests += 1
			em_tested_ok = em_failed == -1 or em_replaced
			say("Test complete: %s" % ("all zones lit." if em_tested_ok else "zone Z%d DARK." % (em_failed + 1)))
	var cond: bool = _condensing()
	wet = clampf(wet + (delta * 0.05 if cond else -delta * 0.03), 0.0, 1.0)
	if cond_cause != "" and not cond_fixed and not cond and cond_ir and cond_dew and wet <= 0.05:
		cond_fixed = true
		if has_open(&"l06_condensation"):
			close_task(&"l06_condensation", "repaired", "spine supply riser", "condensation: %s" % ("insulation gap" if cond_cause == "insulation" else "local vent off"), "jacket closed" if cond_cause == "insulation" else "vent VF-B2 restored", "riser dry, surface above dew point")
	# The emergency-lighting switch-over is REAL light state (not just a
	# display): applied whenever the test starts / ends, visible or not.
	if (em_testing >= 0.0) != _em_applied:
		_em_applied = em_testing >= 0.0
		_apply_emergency_lights(_em_applied)
	if Engine.get_process_frames() % 6 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	var s: Node = sys()
	if _cover != null:
		_cover.rotation_degrees.y = -105.0 if cover_open else 0.0
	if _knob != null:
		_knob.rotation_degrees.z = -60.0 + sel * 30.0
	if _meter != null:
		_meter.text = _meter_text() if cover_open else ""
	for i in _brk.size():
		var on: bool = s == null or s.power["on"][i]
		(_brk[i] as Node3D).get_node("Lever").position.y = 0.02 if on else -0.02
		light(_brk_lamps[i], Color(0.3, 0.95, 0.4) if on else Color(1.0, 0.6, 0.12), true)
	var testing: bool = em_testing >= 0.0
	for i in _em_lamps.size():
		var lit: bool = testing and not (i == em_failed and not em_replaced)
		light(_em_lamps[i], Color(0.95, 0.3, 0.2) if testing else Color(0.3, 0.9, 0.4), lit or not testing)
	if _em_bat != null:
		_em_bat.text = "BATTERY 98 %%\n%s" % ("TEST" if testing else ("READY" if em_reset else "RESET?"))
	_apply_emergency_lights(testing)
	var link: bool = not rpt_loose
	light(_rpt_lamp, Color(0.3, 0.95, 0.4) if link else Color(1.0, 0.6, 0.12), true)
	if _rpt_bars != null:
		_rpt_bars.text = "LINK %s\n%s" % ["▮▮▮▮▯" if link else "▮▯▯▯▯", "OK" if link else "LOW"]
		if has_meta(&"rx_fragment"):
			_rpt_bars.text += "\n" + String(get_meta(&"rx_fragment"))
	if _rpt_door != null:
		_rpt_door.rotation_degrees.y = -100.0 if rpt_open else 0.0
	if _rpt_lead != null:
		_rpt_lead.position.z = 0.075 if rpt_loose else 0.06
	if _jacket_gap != null:
		_jacket_gap.visible = cond_cause != "insulation" or wrap_ok
	if _drops != null:
		_drops.visible = wet > 0.15
	if _hum != null:
		_hum.text = "RH %.0f %%  DEW %.1f °C" % [_rh(), _dew()]
	light(_fan_lamp, Color(0.3, 0.95, 0.4), vent_on)
	set_loop(_fan_loop, null, vent_on and is_inside_tree())
	if _fan_blades != null and vent_on:
		_fan_blades.rotation.z += 0.9
	if _ir_label != null:
		_ir_label.text = "DRIP TRAY: WET" if wet > 0.15 else ""


## The emergency lighting test REALLY changes Deck B's lights: ceiling
## lights dim to 12 %, the strips glow (a failed zone stays dark).
func _apply_emergency_lights(testing: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for l in tree.get_nodes_in_group(&"deck_b_light"):
		var base: float = float(l.get_meta(&"base_energy", 1.0))
		(l as Light3D).light_energy = base * (0.12 if testing else 1.0)
	for st in tree.get_nodes_in_group(&"deck_b_em_strip"):
		var zone: int = int(st.get_meta(&"zone", 0))
		var lit: bool = testing and not (zone == em_failed and not em_replaced)
		var m: StandardMaterial3D = (st as MeshInstance3D).material_override
		m.emission_enabled = true
		m.emission = Color(1.0, 0.3, 0.18) if lit else Color(0, 0, 0)
		m.emission_energy_multiplier = 2.2 if lit else 0.0


# ------------------------------------------------------------ orders
func task_rearm(t: StringName, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s: Node = sys()
	match t:
		&"b01_utility":
			util_read = [false, false, false, false, false]
			util_reset = false
			util_reread = false
			util_trip = -1
			var r: int = rng.randi() % 3
			util_seed = ["", "tripped", "nuisance"][r]
			if util_seed == "tripped" and s != null:
				util_trip = 2 + rng.randi() % 2          # B3 HABITAT or B4 LOGISTICS
				s.power["on"][util_trip] = false
				s.power["last_trip"] = CIRCUITS_SHORT[util_trip]
			cover_open = false
		&"b01_lights":
			em_failed = rng.randi() % 3 if rng.randf() < 0.7 else -1
			em_replaced = false
			em_tested_ok = false
			em_reset = true
			em_tests = 0
		&"b01_repeater":
			rpt_loose = rng.randf() < 0.75
			rpt_was_loose = rpt_loose
			rpt_inspected = false
			rpt_open = false
		&"l06_condensation":
			cond_cause = "insulation" if rng.randf() < 0.6 else "vent"
			cond_ir = false
			cond_dew = false
			cond_air = false
			cond_fixed = false
			wrap_ok = cond_cause != "insulation"
			vent_on = cond_cause != "vent"
			wet = 0.6
	_refresh()


func task_done(t: StringName) -> bool:
	match t:
		&"b01_utility":
			var s: Node = sys()
			var all_read: bool = util_read.slice(0, 4).all(func(v): return v)
			var fixed: bool = util_trip == -1 or (s != null and s.power["on"][util_trip] and util_reread)
			var ok: bool = all_read and util_read[4] and fixed and not cover_open
			if ok and not outcome.has(t):
				close_task(t, {"": "verified_normal", "tripped": "repaired", "nuisance": "fluctuation"}.get(util_seed, "verified_normal"), "LDP-B Bus B", "breaker %s tripped" % CIRCUITS_SHORT[util_trip] if util_trip >= 0 else ("trip-history entry, loads normal" if util_seed == "nuisance" else "none"), "breaker reset after NO SHORT reading" if util_trip >= 0 else "all circuits read", "all circuits powered and within rating")
			return ok
		&"b01_lights":
			return em_tested_ok and em_reset and outcome.has(t)
		&"b01_repeater":
			var ok: bool = not rpt_loose and not rpt_open and rpt_inspected
			if ok and not outcome.has(t):
				close_task(t, "repaired" if rpt_was_loose else "verified_normal", "RPT-B repeater", "loose antenna lead" if rpt_was_loose else "none", "lead reseated" if rpt_was_loose else "link inspected", "LINK 4/5")
			return ok
		&"l06_condensation":
			return cond_fixed
	return true


func task_next(t: StringName) -> Dictionary:
	match t:
		&"b01_utility":
			var s: Node = sys()
			if not cover_open and not util_read.slice(0, 5).all(func(v): return v):
				return next("Open the Bus B distribution panel LDP-B (Lower Junction)", "OPEN LDP-B")
			for i in 5:
				if not util_read[i]:
					return next("Read %s on the LDP-B meter (selector)" % SEL[i], "READ " + SEL[i])
			if util_trip >= 0 and s != null and not s.power["on"][util_trip]:
				return next("Reset breaker %s" % CIRCUITS_SHORT[util_trip], "RESET " + CIRCUITS_SHORT[util_trip])
			if util_trip >= 0 and not util_reread:
				return next("Read %s again under load" % CIRCUITS_SHORT[util_trip], "RE-READ")
			return next("Close the LDP-B cover", "CLOSE LDP-B")
		&"b01_lights":
			if em_tests == 0 or (em_failed >= 0 and not em_replaced and em_tested_ok == false and em_tests > 0):
				if em_tests > 0 and em_failed >= 0 and not em_replaced:
					return next("Replace the zone Z%d lamp module (spare clip under ELP-B)" % (em_failed + 1), "REPLACE Z%d" % (em_failed + 1))
				return next("TEST the emergency lighting at ELP-B", "TEST ELP-B")
			if not em_tested_ok:
				return next("TEST again", "RETEST")
			return next("RESET the emergency lighting panel", "RESET ELP-B")
		&"b01_repeater":
			if not rpt_inspected:
				return next("Open the repeater RPT-B access door (Lower Junction, south wall)", "CHECK RPT-B")
			if rpt_loose:
				return next("Reseat the antenna lead", "RESEAT LEAD")
			return next("Close the repeater door", "CLOSE RPT-B")
		&"l06_condensation":
			if not cond_ir:
				return next("Inspect the condensation on the spine supply riser (IR the surface)", "IR RISER")
			if not cond_dew:
				return next("Read the spine humidity / dew point", "DEW POINT")
			return next("Remove the cause (insulation / local vent) and let the riser dry", "FIX CAUSE")
	return {}


func task_progress(t: StringName) -> String:
	match t:
		&"b01_utility":
			return "%d/5" % util_read.filter(func(v): return v).size()
		&"b01_lights":
			return "test %d" % em_tests
		&"l06_condensation":
			return "wet %d%%" % int(wet * 100.0)
	return ""


func task_detail(t: StringName) -> Array:
	var s: Node = sys()
	match t:
		&"b01_utility":
			var out: Array = ["LDP-B Bus B distribution (Lower Junction, west wall). Cover %s." % ("OPEN" if cover_open else "closed")]
			if s != null:
				for i in 4:
					out.append("%s %s: %s" % [CIRCUITS_SHORT[i], s.CIRCUITS[i][1], ("ON" if s.power["on"][i] else "OFF") if util_read[i] else "not read"])
			return out
		&"b01_lights":
			return ["ELP-B emergency lighting (Lower Junction, north wall). Tests run: %d." % em_tests]
		&"l06_condensation":
			return ["Water dripping under the coolant supply riser (service spine). Find the cause physically: pipe surface, air dew point, airflow."]
	return []


func task_feasible(t: StringName) -> bool:
	if t == &"b01_lights":
		return _spare_rack == null or _spare_rack.count(&"lamp_module") > 0
	return true


# ---------------------------------------------------------- save/load
func state_dict() -> Dictionary:
	return {"cover_open": cover_open, "sel": sel, "util_read": util_read.duplicate(), "util_seed": util_seed, "util_trip": util_trip, "util_reset": util_reset, "util_reread": util_reread,
		"em_failed": em_failed, "em_tested_ok": em_tested_ok, "em_tests": em_tests, "em_replaced": em_replaced, "em_reset": em_reset,
		"rpt_open": rpt_open, "rpt_loose": rpt_loose, "rpt_was_loose": rpt_was_loose, "rpt_inspected": rpt_inspected,
		"cond_cause": cond_cause, "cond_ir": cond_ir, "cond_dew": cond_dew, "cond_air": cond_air, "cond_fixed": cond_fixed, "vent_on": vent_on, "wrap_ok": wrap_ok, "wet": wet, "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in self:
			set(k, d[k])
	em_testing = -1.0
	_refresh()
