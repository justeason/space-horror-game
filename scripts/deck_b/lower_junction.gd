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
var _bond_strap: MeshInstance3D
var _ir_label: Label3D
var _fan_loop: AudioStreamPlayer3D
var _em_applied: bool = false

# Round 50 -- E12 electrical short (LDP-B + terminal box TB-B).
var tb_open: bool = false
var sc_found: bool = false
var sc_steps: int = 0                  # 0..2 repair steps on the faulted terminal
var sc_fixed: bool = false
var sc_zero: bool = false              # zero volts verified on the locked circuit
var sc_reset_into_fault: int = 0       # resets attempted with the fault present
var sc_restored_read: bool = false
var sc_inspected: Array = [false, false, false, false]
var sc_circuit: int = -1
var sc_cause: String = ""
## Round 50 audit: LIVE-DEAD-LIVE -- the meter is proven on a live circuit
## before (and after) the dead reading, so a broken meter can never read
## a false 0 V that lets the technician into a live terminal box.
var sc_proved: bool = false
var _tb_door: Node3D
var _tb_terms: Array = []
var _lock_tags: Array = []

# Round 50 -- M06 interference investigation (RPT-B).
var rf_source: String = ""             # "" (not reproduced) | vent | pwm
var rf_tune: int = 1                   # channel being listened to (A/B/C)
var rf_op: int = 1                     # the repeater's operating channel
var rf_log: Array = []                 # [[channel, dB], ...] listens this order
var rf_cap_ok: bool = true             # VF-B2 motor suppression capacitor seated
var rf_cap_was_bad: bool = false
## Round 50 audit: a THIRD distinct source -- the fan housing's ground
## (bonding) strap: with it loose the motor's commutation noise radiates,
## chopped by the blades (a rhythmic whoosh on CH A only).
var rf_bond_ok: bool = true

# Round 50 -- L10 CO2 rise (CS-B sensor, CDRA-B scrubber, VF-B2 cutout).
var co2_read_csb: bool = false
var co2_read_inlet: bool = false
var co2_cause: String = ""
var co2_at_fix: float = -1.0
var co2_note: String = ""               # airflow detail captured at raise
var csb_cal_step: int = 0
var _csb_label: Label3D
var _cdra_label: Label3D
var _cdra_valve: Node3D


func _ready() -> void:
	_room_ready([&"b01_utility", &"b01_lights", &"b01_repeater", &"l06_condensation", &"e12_short", &"m06_interference", &"l10_co2"])
	_build_ldp()
	_build_terminal_box()
	_build_air()
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
		# Round 50: the lockout hasp above each breaker (a red tag when applied).
		var tag := dbox(Vector3(0.035, 0.03, 0.006), Vector3(x, 0.265, 0.088), Color(0.85, 0.12, 0.1), p)
		tag.visible = false
		_lock_tags.append(tag)
		dbox(Vector3(0.02, 0.012, 0.012), Vector3(x, 0.285, 0.086), Color(0.6, 0.6, 0.62), p)
		part(StringName("lock%d" % i), Vector3(0.06, 0.05, 0.05), Vector3(x, 0.27, 0.1), p)
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
		if not on and int(s.power["short"]) == sel:
			st = "GROUND FAULT · OFF"
		if not on and s.power["lockout"][sel]:
			st = "LOCKED OUT · 0 V" if int(s.power["short"]) != sel or sc_fixed else "LOCKED OUT · 0 V · GND FAULT"
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
	# Round 50 (M06): the maintenance headset jack, tuning and channel set
	# (behind the access door).
	button("rpt_listen", Vector3(-0.1, -0.075, 0.102), Color(0.3, 0.8, 0.95), p)
	button("rpt_tune", Vector3(0.0, -0.075, 0.102), Color(0.85, 0.85, 0.85), p)
	button("rpt_set", Vector3(0.1, -0.075, 0.102), Color(0.95, 0.75, 0.2), p)


# ------------------------------------------------- TB-B (Round 50, E12)
## The Bus B load terminal box under LDP-B: one terminal strip per circuit.
func _build_terminal_box() -> void:
	var p := Node3D.new()
	p.name = "TB_B"
	p.position = Vector3(-5.29, L.FLOOR_Y + 0.6, 9.12)
	p.rotation_degrees.y = 90.0
	add_child(p)
	dbox(Vector3(0.5, 0.32, 0.1), Vector3(0, 0, 0.05), Color(0.26, 0.28, 0.3), p)
	text("TB-B  BUS B LOAD TERMINALS", Vector3(0, 0.19, 0.08), 9, Color(0.95, 0.95, 0.9), p)
	for i in 4:
		var x: float = -0.18 + i * 0.12
		var tm := dbox(Vector3(0.07, 0.12, 0.02), Vector3(x, -0.01, 0.1), Color(0.55, 0.5, 0.42), p, 0.6)
		_tb_terms.append(tm.material_override)
		text(CIRCUITS_SHORT[i], Vector3(x, -0.1, 0.105), 8, Color(0.9, 0.9, 0.9), p)
		part(StringName("term%d" % i), Vector3(0.08, 0.14, 0.05), Vector3(x, -0.01, 0.12), p)
	_tb_door = Node3D.new()
	_tb_door.position = Vector3(-0.25, 0.0, 0.105)
	p.add_child(_tb_door)
	dbox(Vector3(0.5, 0.3, 0.012), Vector3(0.25, 0, 0), Color(0.42, 0.44, 0.47), _tb_door, 0.5)
	text("⚡ ISOLATE · LOCK OUT · VERIFY 0 V", Vector3(0.25, 0.0, 0.008), 9, Color(0.1, 0.1, 0.1), _tb_door)
	part(&"tb_cover", Vector3(0.5, 0.3, 0.04), Vector3(0.25, 0, 0.015), _tb_door)


# ------------------------------------------ CS-B / CDRA-B (Round 50, L10)
func _build_air() -> void:
	# CS-B cabin air sensor (Lower Junction, north wall, west of the hall).
	var c := Node3D.new()
	c.name = "CS_B"
	c.position = Vector3(-4.75, L.FLOOR_Y + 1.5, 9.49)
	c.rotation_degrees.y = 180.0
	add_child(c)
	dbox(Vector3(0.26, 0.2, 0.05), Vector3(0, 0, 0.025), Color(0.22, 0.24, 0.26), c)
	text("CS-B  CABIN AIR", Vector3(0, 0.13, 0.052), 9, Color(0.95, 0.95, 0.9), c)
	_csb_label = text("", Vector3(0, 0.02, 0.052), 11, Color(0.55, 0.95, 0.75), c)
	part(&"csb_read", Vector3(0.26, 0.16, 0.06), Vector3(0, 0.02, 0.04), c)
	button("csb_cal", Vector3(0.08, -0.075, 0.052), Color(0.3, 0.8, 0.95), c)
	text("CAL", Vector3(0.0, -0.075, 0.052), 8, Color(0.9, 0.9, 0.9), c)
	# CDRA-B CO2 removal (service spine, south wall, west of the B-03 hatch).
	var d := Node3D.new()
	d.name = "CDRA_B"
	d.position = Vector3(-1.45, L.FLOOR_Y + 1.47, 7.52)   # bottom clears the handrail (1.05)
	add_child(d)                         # faces +z into the spine
	dbox(Vector3(0.6, 0.7, 0.14), Vector3(0, 0, 0.07), Color(0.62, 0.64, 0.66), d, 0.4)
	dbox(Vector3(0.62, 0.04, 0.15), Vector3(0, 0.36, 0.07), Color(0.2, 0.55, 0.85), d)
	text("CDRA-B  CO2 REMOVAL (B3 HABITAT)", Vector3(0, 0.3, 0.142), 9, Color(0.1, 0.1, 0.12), d)
	_cdra_label = text("", Vector3(-0.05, 0.08, 0.142), 10, Color(0.1, 0.35, 0.2), d)
	dbox(Vector3(0.36, 0.26, 0.004), Vector3(-0.05, 0.08, 0.141), Color(0.75, 0.9, 0.8), d)
	part(&"cdra_read", Vector3(0.38, 0.28, 0.04), Vector3(-0.05, 0.08, 0.15), d)
	_cdra_valve = Node3D.new()
	_cdra_valve.position = Vector3(0.0, -0.22, 0.15)
	d.add_child(_cdra_valve)
	dbox(Vector3(0.2, 0.03, 0.03), Vector3.ZERO, Color(0.85, 0.15, 0.1), _cdra_valve)
	dcyl(0.03, 0.03, Vector3(0, 0, -0.01), Color(0.3, 0.3, 0.32), _cdra_valve, Vector3(90, 0, 0))
	text("BED SWAP VALVE (MANUAL)", Vector3(0, -0.29, 0.142), 8, Color(0.1, 0.1, 0.12), d)
	part(&"cdra_valve", Vector3(0.24, 0.08, 0.06), Vector3(0.0, -0.22, 0.16), d)


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
	# Round 50: motor terminal cover (suppression capacitor, M06) and the
	# thermal-cutout reset (L10).
	dbox(Vector3(0.08, 0.06, 0.03), Vector3(-0.19, -0.12, 0.05), Color(0.36, 0.37, 0.4), fan)
	part(&"fan_cap", Vector3(0.1, 0.08, 0.06), Vector3(-0.19, -0.12, 0.08), fan)
	# Housing ground (bonding) strap: braided strap from the fan frame to the
	# wall stud; hangs off its stud when loose (M06 "fan" source).
	_bond_strap = dbox(Vector3(0.018, 0.12, 0.006), Vector3(-0.17, 0.1, 0.064), Color(0.72, 0.55, 0.3), fan, 0.8)
	dcyl(0.012, 0.012, Vector3(-0.17, 0.16, 0.064), Color(0.7, 0.7, 0.72), fan, Vector3(90, 0, 0), 0.8)
	part(&"fan_bond", Vector3(0.07, 0.16, 0.06), Vector3(-0.17, 0.1, 0.08), fan)
	button("fan_reset", Vector3(0.19, 0.03, 0.065), Color(0.85, 0.2, 0.15), fan)
	text("CUTOUT\nRESET", Vector3(0.19, -0.03, 0.065), 7, Color(0.9, 0.9, 0.9), fan)
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
		"tb_cover":
			tb_open = not tb_open
			sfx(&"latch")
		"rpt_listen":
			_rf_listen()
		"rpt_tune":
			if not rpt_open:
				say("Open the repeater's access door first (headset jack inside).")
			else:
				rf_tune = (rf_tune + 1) % 3
				sfx(&"click")
				say("Monitor tuned to CH %s." % "ABC"[rf_tune])
		"rpt_set":
			if not rpt_open:
				say("Open the repeater's access door first.")
			else:
				rf_op = rf_tune
				sfx(&"click")
				say("RPT-B operating channel set to CH %s." % "ABC"[rf_op])
		"fan_bond":
			if vent_on:
				say("Switch VF-B2 OFF before working on the housing.")
			elif not rf_bond_ok:
				rf_bond_ok = true
				sfx(&"ratchet")
				say("Bonding strap was hanging off its stud (nut backed off) — refitted, star washer, torqued.")
			else:
				say("Housing bonding strap: tight, clean contact.")
		"fan_cap":
			if vent_on:
				say("Switch VF-B2 OFF before opening the motor terminal cover.")
			elif not rf_cap_ok:
				rf_cap_ok = true
				sfx(&"ratchet")
				say("Suppression capacitor lead was hanging loose — reseated and the cover closed.")
			else:
				say("Motor terminals: suppression capacitor seated, no damage.")
		"fan_reset":
			if s == null:
				return
			if not s.air["fan_cutout"]:
				say("VF-B2 cutout not tripped.")
			elif vent_on:
				say("Switch VF-B2 OFF before resetting the thermal cutout.")
			else:
				s.air["fan_cutout"] = false
				sfx(&"click")
				say("Thermal cutout reset (motor cool). Switch VF-B2 back ON.")
		"csb_read":
			co2_read_csb = true
			if s != null:
				say("CS-B: CO2 %.0f ppm (%s)" % [s.co2_reading(), s.air_status()])
		"csb_cal":
			_csb_calibrate()
		"cdra_read":
			co2_read_inlet = true
			if s != null:
				say(_cdra_text().replace("\n", " · "))
		"cdra_valve":
			if s == null:
				return
			if not co2_read_inlet:
				say("Read the CDRA-B panel first (which bed is adsorbing).")
				return
			s.air["swap_stuck"] = false
			s.swap_beds("manual")
			sfx(&"ratchet")
			say("Swap valve worked by hand — it moved freely after the first stiff quarter turn. Bed %s now adsorbing." % ["A", "B"][int(s.air["active"])])
		_:
			if sid.begins_with("brk"):
				_breaker(int(sid.substr(3)))
			elif sid.begins_with("lock"):
				_lockout(int(sid.substr(4)))
			elif sid.begins_with("term"):
				_terminal(int(sid.substr(4)))
			elif sid.begins_with("em_mod"):
				_em_module(int(sid.substr(6)))
	_refresh()


func _read() -> void:
	util_read[sel] = true
	if sel == util_trip and util_reset:
		util_reread = true
	var s: Node = sys()
	if s != null and sc_circuit >= 0 and sel < 4 and sel != sc_circuit and s.power["on"][sel] and s.powered(sel):
		if not sc_proved and has_open(&"e12_short"):
			say("Meter proven on a LIVE circuit (%s). Now the dead test." % CIRCUITS_SHORT[sel])
		sc_proved = true
	if s != null and sel == sc_circuit and sel < 4:
		if s.power["lockout"][sel] and not s.power["on"][sel]:
			if not sc_proved:
				say("%s reads 0 V — but a dead reading means nothing until the meter is proven on a LIVE circuit first (live-dead-live)." % CIRCUITS_SHORT[sel], 4.5)
				return
			sc_zero = true
		if sc_fixed and s.power["on"][sel] and s.powered(sel):
			sc_restored_read = true
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
	if s.power["lockout"][i]:
		say("%s is LOCKED OUT — remove your lockout tag before re-energising." % CIRCUITS_SHORT[i])
		return
	if not util_read[i] and sel != i:
		say("Read %s on the meter first (it must show NO SHORT)." % CIRCUITS_SHORT[i])
		return
	s.power["on"][i] = true
	sfx(&"clunk")
	if int(s.power["short"]) == i:
		# The ground fault is still there: the breaker trips again at once.
		sc_reset_into_fault += 1
		s.step(0.01)
		say("%s trips again immediately — GROUND FAULT. Do not reset into a fault: isolate and inspect." % CIRCUITS_SHORT[i])
		return
	if i == util_trip:
		util_reset = true
		util_reread = false
	say("%s reset. Read it again under load." % CIRCUITS_SHORT[i])


## Round 50 (E12): apply / remove the technician's lockout tag.
func _lockout(i: int) -> void:
	var s: Node = sys()
	if s == null:
		return
	if not cover_open:
		say("Open the LDP-B cover first.")
		return
	if s.power["lockout"][i]:
		if tb_open:
			say("Close the terminal box TB-B before removing the lockout.")
			return
		s.power["lockout"][i] = false
		sfx(&"latch")
		say("Lockout tag removed from %s." % CIRCUITS_SHORT[i])
		return
	if s.power["on"][i]:
		say("%s is ON — a lockout goes on an OFF breaker." % CIRCUITS_SHORT[i])
		return
	s.power["lockout"][i] = true
	sfx(&"latch")
	say("%s locked out and tagged (TECH-1). Verify 0 V on the meter." % CIRCUITS_SHORT[i])


## Round 50 (E12): inspect / repair a load terminal in TB-B.
func _terminal(i: int) -> void:
	var s: Node = sys()
	if s == null:
		return
	if not tb_open:
		say("Open the terminal box TB-B first.")
		return
	if s.power["on"][i]:
		say("%s is LIVE. Isolate it at LDP-B, lock it out and verify 0 V first." % CIRCUITS_SHORT[i])
		return
	if not s.power["lockout"][i]:
		say("%s is off but NOT locked out — apply your lockout tag at LDP-B first." % CIRCUITS_SHORT[i])
		return
	if i == sc_circuit and not sc_zero:
		say("Verify 0 V on %s at the LDP-B meter before touching the terminals." % CIRCUITS_SHORT[i])
		return
	sc_inspected[i] = true
	if i != sc_circuit or sc_fixed:
		say("%s terminals: clean, dry, torque marks intact." % CIRCUITS_SHORT[i])
		return
	if not sc_found:
		sc_found = true
		say("%s: %s" % [CIRCUITS_SHORT[i], "scorched lug — insulation melted back at the load terminal." if sc_cause == "terminal" else "terminal wet — tracking marks between the lug and the enclosure (condensate)."])
		return
	sc_steps += 1
	sfx(&"ratchet")
	if sc_steps == 1:
		say("Cut back to clean conductor." if sc_cause == "terminal" else "Terminal dried and cleaned of tracking residue.")
	else:
		sc_fixed = true
		s.clear_short()
		say("New lug crimped and torqued. Insulation test: >20 MΩ." if sc_cause == "terminal" else "Terminal sealed with a boot. Insulation test: >20 MΩ.")


func _rf_noise(ch: int) -> float:
	var s: Node = sys()
	var db: float = -96.0
	if s == null:
		return db
	if rf_source == "vent" and s.vent_flow() and not rf_cap_ok and ch in [0, 1]:
		db = maxf(db, -68.0)
	if rf_source == "fan" and s.vent_flow() and not rf_bond_ok and ch == 0:
		db = maxf(db, -71.0)
	if rf_source == "pwm" and ch in [1, 2]:
		for k in 3:
			var lv: float = s.light_output(k)
			if lv > 0.05 and lv < 0.95:
				db = maxf(db, -64.0)
	return db


func _rf_pattern(ch: int) -> String:
	var db: float = _rf_noise(ch)
	if db < -90.0:
		return "clean (receiver hiss only)"
	var s: Node = sys()
	if rf_source == "vent" and s != null and s.vent_flow() and not rf_cap_ok and ch in [0, 1]:
		return "steady buzz, 96 Hz, with irregular crackle bursts (unstable)"
	if rf_source == "fan" and s != null and s.vent_flow() and not rf_bond_ok and ch == 0:
		return "rhythmic whoosh — the hiss chopped ~24 times a second (blade rate)"
	return "pulsed comb — repeating clicks, very regular"


func _rf_listen() -> void:
	if not rpt_open:
		say("Open the repeater's access door first (headset jack inside).")
		return
	var db: float = _rf_noise(rf_tune)
	rf_log.append([rf_tune, db])
	_rf_sound(db, _rf_pattern(rf_tune))
	say("CH %s: noise %.0f dB — %s" % ["ABC"[rf_tune], db, _rf_pattern(rf_tune)], 4.5)


## Two listens on one channel that disagree = the technician changed
## something and compared (or all three channels heard clean).
func _rf_compared() -> bool:
	for a in rf_log:
		for b in rf_log:
			if int(a[0]) == int(b[0]) and absf(float(a[1]) - float(b[1])) > 10.0:
				return true
	return false


func _rf_heard_all() -> bool:
	var seen := {}
	for a in rf_log:
		seen[int(a[0])] = true
	return seen.size() == 3


var _rf_streams := {}


func _rf_sound(db: float, pattern: String) -> void:
	var kind: String = "clean" if db < -90.0 else ("hum" if pattern.begins_with("steady") else ("fan" if pattern.begins_with("rhythmic") else "pwm"))
	if not _rf_streams.has(kind):
		_rf_streams[kind] = rf_stream(kind)
	var snd: Node = get_tree().get_first_node_in_group(&"station_sounds") if is_inside_tree() else null
	if snd != null and snd.has_method("play_custom"):
		snd.play_custom(StringName("rpt_" + kind), _rf_streams[kind], Vector3(-4.95, L.FLOOR_Y + 1.85, 6.6))


## M06 -> M07 FOUNDATION. The ORDINARY interference signatures a
## technician learns here (each tied to real equipment that can be switched
## and fixed). A later, story-gated M07 transmission is defined by
## VIOLATING them: a rhythm no equipment runs at, on a channel nothing
## occupies, that does not change when any source is switched off.
const KNOWN_RF := {"vent": "96 Hz buzz + irregular crackle, CH A/B, stops with VF-B2", "fan": "24 Hz chopped hiss, CH A, stops with VF-B2",
	"pwm": "120 Hz click comb, CH B/C, follows the grow-light dimming"}
var rf_anomalies: Array = []


## Story-gated hook (never in normal play): preview = developer F8 (returns
## the would-be record, stores nothing, changes no channel).
func rf_anomaly(preview: bool) -> Dictionary:
	var rec := {"day": day(), "ch": "C", "pattern": "17.3 Hz pulse train — no equipment runs at this rate; unchanged with VF-B2 and the grow lights OFF", "preview": preview}
	if not preview:
		rf_anomalies.append(rec)
	return rec


## The headset audio of each interference signature (built once, cached):
##   hum   capacitor: a 96 Hz motor buzz + harmonics with IRREGULAR crackle
##         bursts (a failing / loose part: no rhythm)
##   fan   bonding strap: receiver hiss CHOPPED at the 24 Hz blade rate
##         (mechanical periodicity, no tone)
##   pwm   dimmer: very regular 120 Hz click comb with a 1.2 kHz ring
##   clean receiver hiss only
## Peak level <= 0.5 full scale before the custom-sound bus (never a
## piercing tone: the highest tonal component is a 1.2 kHz ring at 0.3).
static func rf_stream(kind: String) -> AudioStreamWAV:
	return loop_stream(1.6, func(t, i):
		var n: float = fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5
		match kind:
			"hum":
				var burst: float = 1.0 if fmod(sin(floor(t * 9.0) * 78.233) * 43758.5453, 1.0) > 0.72 else 0.0
				return sin(TAU * 96.0 * t) * 0.22 + sin(TAU * 288.0 * t) * 0.08 + n * (0.06 + 0.5 * burst * (0.5 + 0.5 * sin(TAU * 31.0 * t)))
			"fan":
				var chop: float = 0.5 + 0.5 * sin(TAU * 24.0 * t)
				return n * (0.08 + 0.42 * chop * chop)
			"pwm":
				return (0.3 if fmod(t * 120.0, 1.0) < 0.08 else 0.0) * sin(TAU * 1200.0 * t) + n * 0.08
		return n * 0.12)


func _csb_calibrate() -> void:
	var s: Node = sys()
	if s == null:
		return
	if not co2_read_inlet:
		say("Compare first: read the CDRA-B inlet CO2 (service spine) against CS-B.")
		return
	var diff: float = absf(s.co2_reading() - float(s.air["co2"]))
	if diff < 300.0 and csb_cal_step == 0:
		say("CS-B agrees with the CDRA-B inlet within %.0f ppm — no calibration needed." % diff)
		return
	csb_cal_step += 1
	sfx(&"click")
	if csb_cal_step == 1:
		say("CS-B zero: reference air applied, offset measured %+.0f ppm." % float(s.air["sensor_bias"]))
	else:
		s.air["sensor_bias"] = 0.0
		csb_cal_step = 0
		say("CS-B span set against the CDRA-B inlet. Reading now %.0f ppm." % s.co2_reading())


func _cdra_text() -> String:
	var s: Node = sys()
	if s == null:
		return ""
	var a: int = int(s.air["active"])
	var lines: Array = []
	for b in 2:
		var st: String = "ADSORBING" if b == a else ("REGEN %d s" % int(s.REGEN_S - float(s.air["regen"])) if float(s.air["regen"]) >= 0.0 else "READY")
		lines.append("BED %s %3d %%  %s" % [["A", "B"][b], int(float(s.air["beds"][b]) * 100.0), st])
	lines.append("INLET CO2 %.0f ppm" % float(s.air["co2"]))
	lines.append("AIRFLOW %s%s" % ["OK" if s.vent_flow() else "LOW", "  AUTO-CYCLE FAULT" if s.air["swap_stuck"] else ""])
	if not s.scrubber_powered():
		lines = ["NO POWER (B3 HABITAT)"]
	return "\n".join(lines)


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
		"tb_cover":
			return "Click: %s terminal box TB-B" % ("close" if tb_open else "open")
		"rpt_listen":
			return "Click: listen on the monitor headset (CH %s)" % "ABC"[rf_tune] if rpt_open else ""
		"rpt_tune":
			return "Click: tune the monitor (now CH %s)" % "ABC"[rf_tune] if rpt_open else ""
		"rpt_set":
			return "Click: set operating channel to CH %s (now CH %s)" % ["ABC"[rf_tune], "ABC"[rf_op]] if rpt_open else ""
		"fan_cap":
			return "Click: open the VF-B2 motor terminal cover"
		"fan_bond":
			return "Click: check the VF-B2 housing bonding strap"
		"fan_reset":
			return "Click: reset the VF-B2 thermal cutout"
		"csb_read":
			return "Click: read CS-B cabin CO2"
		"csb_cal":
			return "Click: calibrate CS-B (zero / span)"
		"cdra_read":
			return "Click: read the CDRA-B panel"
		"cdra_valve":
			return "Click: work the bed swap valve by hand"
	if sid.begins_with("lock"):
		var li: int = int(sid.substr(4))
		var sy: Node = sys()
		var locked: bool = sy != null and sy.power["lockout"][li]
		return "Click: %s lockout tag on %s" % ["remove the" if locked else "apply a", CIRCUITS_SHORT[li]]
	if sid.begins_with("term"):
		return "Click: inspect the %s load terminal" % CIRCUITS_SHORT[int(sid.substr(4))] if tb_open else ""
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
	var sy: Node = sys()
	if sy != null:
		sy.air["vent_switch"] = vent_on
		if has_open(&"l10_co2") and co2_at_fix < 0.0 and co2_cause != "" and sy.air_fault() == "":
			co2_at_fix = sy.co2_reading()
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
	var link: bool = not rpt_loose and _rf_noise(rf_op) < -90.0
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
	if _bond_strap != null:
		_bond_strap.rotation_degrees.z = 0.0 if rf_bond_ok else 35.0
		_bond_strap.position = Vector3(-0.17, 0.1, 0.064) if rf_bond_ok else Vector3(-0.15, 0.08, 0.064)
	var flowing: bool = vent_on and (s == null or not s.air["fan_cutout"])
	light(_fan_lamp, Color(1.0, 0.6, 0.12) if (s != null and s.air["fan_cutout"]) else Color(0.3, 0.95, 0.4), vent_on or (s != null and s.air["fan_cutout"]))
	set_loop(_fan_loop, null, flowing and is_inside_tree())
	if _fan_blades != null and flowing:
		_fan_blades.rotation.z += 0.9
	if _ir_label != null:
		_ir_label.text = "DRIP TRAY: WET" if wet > 0.15 else ""
	# Round 50 displays.
	if _tb_door != null:
		_tb_door.rotation_degrees.y = -100.0 if tb_open else 0.0
	for i in _lock_tags.size():
		(_lock_tags[i] as Node3D).visible = s != null and s.power["lockout"][i]
	for i in _tb_terms.size():
		var bad: bool = i == sc_circuit and sc_found and not sc_fixed
		(_tb_terms[i] as StandardMaterial3D).albedo_color = (Color(0.12, 0.1, 0.08) if sc_cause == "terminal" else Color(0.35, 0.45, 0.5)) if bad else Color(0.55, 0.5, 0.42)
	if _csb_label != null and s != null:
		_csb_label.text = "CO2 %.0f ppm\n%s" % [s.co2_reading(), s.air_status()]
		_csb_label.modulate = Color(1.0, 0.55, 0.2) if s.co2_reading() > s.CO2_CAUTION else Color(0.55, 0.95, 0.75)
	if _cdra_label != null:
		_cdra_label.text = _cdra_text()
	if _rpt_bars != null and rpt_open:
		_rpt_bars.text += "\nOP CH %s · MON CH %s" % ["ABC"[rf_op], "ABC"[rf_tune]]


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
		&"e12_short":
			if s != null and int(s.power["short"]) < 0:
				s.inject_short(2 + rng.randi() % 2, "moisture" if rng.randf() < 0.35 else "terminal")
			if s != null and s.power["on"][int(s.power["short"])]:
				s.step(0.01)              # the fault trips its breaker
			sc_circuit = int(s.power["short"]) if s != null else -1
			sc_cause = String(s.power["short_cause"]) if s != null else "terminal"
			sc_found = false
			sc_steps = 0
			sc_fixed = false
			sc_zero = false
			sc_proved = false
			sc_reset_into_fault = 0
			sc_restored_read = false
			sc_inspected = [false, false, false, false]
			tb_open = false
		&"m06_interference":
			var r6: float = rng.randf()
			rf_source = "vent" if r6 < 0.27 else ("fan" if r6 < 0.54 else ("pwm" if r6 < 0.8 else ""))
			rf_cap_ok = rf_source != "vent"
			rf_cap_was_bad = not rf_cap_ok
			rf_bond_ok = rf_source != "fan"
			rf_op = 1
			rf_tune = 1
			rf_log = []
			if rf_source == "pwm" and s != null:
				# The grow lights were dimmed for the young trays (PWM drivers).
				for k in 3:
					if s.light_output(k) >= 0.95 or s.light_output(k) <= 0.05:
						s.hydro["light"][k] = 0.6
		&"l10_co2":
			if s != null and s.air_fault() == "" and s.co2_reading() <= s.CO2_CAUTION:
				s.inject_air_fault(["bed", "airflow", "sensor"][rng.randi() % 3])
				if s.air_fault() != "sensor":
					s.air["co2"] = s.CO2_CAUTION + 600.0
			co2_cause = s.air_fault() if s != null else ""
			co2_note = ("thermal cutout" if s.air["fan_cutout"] else "fan switched off") if co2_cause == "airflow" else ""
			co2_read_csb = false
			co2_read_inlet = false
			co2_at_fix = -1.0
			csb_cal_step = 0
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
		&"e12_short":
			var sy: Node = sys()
			if sy == null or sc_circuit < 0:
				return true
			var ok: bool = sc_fixed and sy.power["on"][sc_circuit] and sc_restored_read and not sy.power["lockout"].has(true) and not tb_open and not cover_open
			if ok and not outcome.has(t):
				close_task(t, "repaired", "Bus B %s load terminal (TB-B)" % CIRCUITS_SHORT[sc_circuit], "ground fault: %s" % ("scorched lug" if sc_cause == "terminal" else "condensate tracking"), "isolated, locked out, 0 V verified; %s; re-energised%s" % ["lug replaced" if sc_cause == "terminal" else "dried and sealed", " (%d reset into the fault)" % sc_reset_into_fault if sc_reset_into_fault > 0 else ""], ">20 MΩ, %s holds under load" % CIRCUITS_SHORT[sc_circuit])
			return ok
		&"m06_interference":
			var quiet: bool = _rf_noise(rf_op) < -90.0
			# Verified: the operating channel is clean, the repeater closed, the
			# diagnosis was real (a comparison), and NOTHING the station needs
			# was left switched off to get there (the vent fan back ON; the
			# grow lights not simply switched off unless the link moved away).
			var lights_ok: bool = true
			var sy6: Node = sys()
			if rf_source == "pwm" and rf_op != 0 and sy6 != null:
				for k in 3:
					if float(sy6.hydro["light"][k]) < 0.05:
						lights_ok = false
			var ok6: bool = quiet and not rpt_open and (_rf_compared() if rf_source != "" else _rf_heard_all()) and (not rf_source in ["vent", "fan"] or vent_on) and lights_ok
			if ok6 and not outcome.has(t):
				match rf_source:
					"vent":
						if rf_cap_ok:
							close_task(t, "repaired", "RPT-B / VF-B2", "96 Hz buzz on CH A/B: fan motor suppression capacitor loose", "capacitor reseated", "CH %s clean, link 4/5" % "ABC"[rf_op])
						else:
							close_task(t, "deferred", "RPT-B / VF-B2", "96 Hz buzz on CH A/B from the vent fan motor", "repeater moved to CH C (source not removed)", "CH C clean; VF-B2 suppression to follow up")
					"fan":
						if rf_bond_ok:
							close_task(t, "repaired", "RPT-B / VF-B2", "rhythmic noise on CH A (blade rate): fan housing bonding strap loose", "bonding strap re-torqued", "CH %s clean, link 4/5" % "ABC"[rf_op])
						else:
							close_task(t, "deferred", "RPT-B / VF-B2", "rhythmic noise on CH A from the vent fan", "repeater moved to CH %s (source not removed)" % "ABC"[rf_op], "CH %s clean; VF-B2 bonding to follow up" % "ABC"[rf_op])
					"pwm":
						close_task(t, "repaired", "RPT-B", "pulsed comb on CH B/C: grow-light driver PWM harmonics", "repeater moved to CH A" if rf_op == 0 else "grow-light banks set out of the PWM range", "CH %s clean, link 4/5" % "ABC"[rf_op])
					_:
						close_task(t, "not_reproduced", "RPT-B", "reported noise not present", "all channels monitored", "CH A/B/C clean")
			return ok6
		&"l10_co2":
			var sy2: Node = sys()
			if sy2 == null:
				return true
			var compared: bool = co2_read_csb and co2_read_inlet
			var falling: bool = co2_at_fix >= 0.0 and (sy2.co2_reading() < co2_at_fix - 200.0 or sy2.co2_reading() < 4200.0)
			if co2_cause == "" and compared and sy2.co2_reading() < sy2.CO2_CAUTION:
				falling = true
			var ok10: bool = compared and sy2.air_fault() == "" and falling
			if ok10 and not outcome.has(t):
				# The cause is fixed and CO2 is coming down: the air model is
				# RECOVERING -- no fresh order while it settles (a new fault
				# ends the recovery and raises one again).
				sy2.air["recovering"] = true
				match co2_cause:
					"sensor":
						close_task(t, "sensor_fault", "CS-B cabin CO2 sensor", "CS-B read %.0f ppm high against the CDRA-B inlet" % 3400.0, "zero / span calibration", "CS-B %.0f ppm = inlet" % sy2.co2_reading())
					"bed":
						close_task(t, "repaired", "CDRA-B scrubber", "adsorbing bed saturated, auto-cycle swap valve stuck", "valve worked by hand, beds swapped, saturated bed regenerating", "CO2 falling (%.0f ppm)" % sy2.co2_reading())
					"airflow":
						close_task(t, "repaired", "VF-B2 spine vent", "no airflow through the scrubber (%s)" % co2_note, "fan restored", "CO2 falling (%.0f ppm)" % sy2.co2_reading())
					"power":
						close_task(t, "repaired", "CDRA-B scrubber", "no power (B3 HABITAT off)", "B3 restored", "CO2 falling (%.0f ppm)" % sy2.co2_reading())
					_:
						close_task(t, "verified_normal", "lower deck air", "transient rise (exercise)", "CS-B and inlet compared", "CO2 %.0f ppm, below caution" % sy2.co2_reading())
			return ok10
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
		&"e12_short":
			var sy: Node = sys()
			if sy == null or sc_circuit < 0:
				return {}
			var c: String = CIRCUITS_SHORT[sc_circuit]
			if not sc_fixed:
				if not cover_open:
					return next("Open LDP-B and identify the tripped circuit", "OPEN LDP-B")
				if not util_read[sc_circuit]:
					return next("Read each circuit on the LDP-B meter (find the GROUND FAULT)", "READ " + c)
				if sy.power["on"][sc_circuit]:
					return next("Switch %s OFF" % c, "ISOLATE " + c)
				if not sy.power["lockout"][sc_circuit]:
					return next("Apply your lockout tag to %s" % c, "LOCK OUT " + c)
				if not sc_proved:
					return next("Prove the meter on a LIVE circuit first (select another ON circuit, READ)", "PROVE METER")
				if not sc_zero:
					return next("Verify 0 V on %s at the meter (live-dead-live)" % c, "VERIFY 0 V")
				if not tb_open:
					return next("Open the terminal box TB-B under LDP-B", "OPEN TB-B")
				return next("Inspect and repair the %s load terminal" % c, "REPAIR " + c)
			if tb_open:
				return next("Close TB-B", "CLOSE TB-B")
			if sy.power["lockout"][sc_circuit]:
				return next("Remove your lockout tag from %s" % c, "UNLOCK " + c)
			if not sy.power["on"][sc_circuit]:
				return next("Reset %s" % c, "RESET " + c)
			if not sc_restored_read:
				return next("Read %s under load" % c, "READ " + c)
			return next("Close the LDP-B cover", "CLOSE LDP-B")
		&"m06_interference":
			if not rpt_open:
				return next("Open RPT-B (Lower Junction) and listen on the monitor headset", "OPEN RPT-B") if rf_log.is_empty() or _rf_noise(rf_op) >= -90.0 else next("Close the repeater door", "CLOSE RPT-B")
			if rf_log.is_empty():
				return next("Listen on the operating channel (headset)", "LISTEN")
			if rf_source == "" and not _rf_heard_all():
				return next("Compare the channels: tune and listen on A, B and C", "COMPARE CH")
			if rf_source != "" and not _rf_compared():
				return next("Find the pattern's source: switch nearby equipment and listen again on the same channel", "COMPARE")
			if _rf_noise(rf_op) >= -90.0:
				return next("Remove the source or move the repeater to a clean channel", "FIX / RETUNE")
			return next("Close the repeater door", "CLOSE RPT-B")
		&"l10_co2":
			var sy3: Node = sys()
			if not co2_read_csb:
				return next("Read CS-B cabin CO2 (Lower Junction, north wall)", "READ CS-B")
			if not co2_read_inlet:
				return next("Compare with the CDRA-B inlet (service spine)", "READ CDRA-B")
			if sy3 != null and sy3.air_fault() != "":
				return next("Find the cause: scrubber, sensor or airflow — and correct it", "FIX CAUSE")
			return next("Verify CO2 falling on CS-B", "VERIFY")
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
		&"l10_co2":
			var sy: Node = sys()
			return "%.0f ppm" % sy.co2_reading() if sy != null else ""
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
		&"e12_short":
			return ["A Bus B breaker tripped on a ground fault. Identify it at LDP-B, isolate, lock out, verify 0 V, inspect TB-B, restore safely. Never reset into a fault."]
		&"m06_interference":
			return ["Noise reported on the lower-deck intercom link (RPT-B). Listen, compare channels and patterns, find the source."]
		&"l10_co2":
			return ["CS-B shows lower-deck CO2 above caution. Determine: scrubber (CDRA-B), sensor (CS-B) or airflow (VF-B2)."]
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
		"cond_cause": cond_cause, "cond_ir": cond_ir, "cond_dew": cond_dew, "cond_air": cond_air, "cond_fixed": cond_fixed, "vent_on": vent_on, "wrap_ok": wrap_ok, "wet": wet, "outcome": outcome.duplicate(),
		"tb_open": tb_open, "sc_found": sc_found, "sc_steps": sc_steps, "sc_fixed": sc_fixed, "sc_zero": sc_zero, "sc_proved": sc_proved, "sc_reset_into_fault": sc_reset_into_fault, "sc_restored_read": sc_restored_read, "sc_inspected": sc_inspected.duplicate(), "sc_circuit": sc_circuit, "sc_cause": sc_cause,
		"rf_source": rf_source, "rf_tune": rf_tune, "rf_op": rf_op, "rf_log": rf_log.duplicate(true), "rf_cap_ok": rf_cap_ok, "rf_cap_was_bad": rf_cap_was_bad, "rf_bond_ok": rf_bond_ok, "rf_anomalies": rf_anomalies.duplicate(true),
		"co2_read_csb": co2_read_csb, "co2_read_inlet": co2_read_inlet, "co2_cause": co2_cause, "co2_at_fix": co2_at_fix, "co2_note": co2_note, "csb_cal_step": csb_cal_step}


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
