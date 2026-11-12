extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-05 RESEARCH AND PAYLOAD LABORATORY (clinical, quiet, the
## technician maintains the instruments -- not the science).
##   glovebox     sealed box, two glove ports (clamp rings, gloves), a
##                transfer chamber (outer / inner doors with an INTERLOCK),
##                PURGE cycle, negative-pressure gauge, LEAK TEST, work tray;
##   optical bench a laser source, a two-axis mirror (tilt X / Y knobs), a
##                lens focus knob and a sensor-rotation knob; the sensor
##                display shows the REAL spot (offset by the mirror error,
##                blurred by the focus error, crosshair rotated by the
##                sensor error) and the signal it produces;
##   imaging      sample rack (six sealed specimens with catalogue numbers),
##                microscope stage + focus, a display that draws the
##                specimen's real structure, the wall reference card;
##   incubator    setpoint / actual (deck_b_systems.lab: heater + the lab's
##                coolant branch), the research terminal with its trends;
##   PDU          payload power outlets (incubator / imager / recorder),
##                fuses, input-dropout counter (Bus B circuit B2).
## Tasks: b05_seal, b05_transfer, b05_optics, b05_incubator, b05_specimen,
## b05_power (chain: Lab -> Engineering BUS B TRANSFER -> Lab, E10).

const CLASSES := ["NEEDLE", "PLATE", "DENDRITE", "AMORPHOUS"]
## The specimens (authoritative identity): id, catalogue number, class.
const SPECIMENS := [["S-101", "CR-4471", 0], ["S-102", "CR-4472", 2], ["S-103", "CR-4480", 1], ["S-104", "CR-4483", 3], ["S-105", "CR-4490", 2], ["S-106", "CR-4491", 0]]
# Glovebox
var gb_leak: String = ""           # "" | clamp_l | clamp_r | glove_l | glove_r
var gb_test: float = -1.0
var gb_dp: float = -0.5
var gb_passed: bool = false
var gb_found: bool = false
var outer_open: bool = false
var inner_open: bool = false
var purged: bool = false
var purge_t: float = -1.0
var hands_in: bool = false
var chamber_has: bool = false
var tray_has: bool = false
var transfer_done: bool = false
var spare_glove: bool = false
# Optics
var opt: Array = [0.0, 0.0, 0.0, 0.0]   # tilt x, tilt y, focus, rotation (errors, steps of 0.1)
var opt_hold: float = 0.0
# Specimens
var stage: int = -1
var focus_err: float = 0.4
var recorded: Dictionary = {}       # specimen id -> {class, day, catalogue}
var spec_target: int = -1
var spec_recorded_ok: bool = false
var shown_overlay: Dictionary = {}  # story presentation: {id: {catalogue, class}}
# Incubator
var inc_cause: String = ""
var inc_diag: String = ""
var inc_hold: float = 0.0
var diag_i: int = 0
# Payload power
var pdu_drops: int = 0
var pwr_variant: String = ""        # chatter | transient
var pwr_hold: float = 0.0
var pwr_logged_nff: bool = false
var _was_dropout: bool = false

var _gb_gauge: Label3D
var _gb_status: Label3D
var _gloves: Array = []
var _outer: Node3D
var _inner: Node3D
var _chamber_item: MeshInstance3D
var _tray_item: MeshInstance3D
var _spot: MeshInstance3D
var _cross: Node3D
var _opt_lbl: Label3D
var _spec_view: Node3D
var _spec_fog: MeshInstance3D
var _spec_lbl: Label3D
var _inc_lbl: Label3D
var _term: Label3D
var _pdu_lbl: Label3D
var _pdu_lamps: Array = []
var _sample_rack: Rack
var _fan_loop: AudioStreamPlayer3D


func _ready() -> void:
	_room_ready([&"b05_seal", &"b05_transfer", &"b05_optics", &"b05_incubator", &"b05_specimen", &"b05_power"])
	_build_glovebox()
	_build_optics()
	_build_imaging()
	_build_incubator_and_pdu()
	text("B-05  PAYLOAD LABORATORY", Vector3(-4.6, L.FLOOR_Y + 2.75, 14.88), 20, Color(0.95, 0.98, 1.0), self, 180.0)
	_fan_loop = machine_loop(loop_stream(2.0, func(t, i): return (fmod(sin(float(i) * 12.9898) * 43758.5453, 1.0) - 0.5) * 0.18 + sin(TAU * 120.0 * t) * 0.04), Vector3(-4.6, L.FLOOR_Y + 2.6, 13.6), -24.0)
	_refresh()


# ------------------------------------------------------------- geometry
func _build_glovebox() -> void:
	var g := Node3D.new()
	g.name = "Glovebox"
	g.position = Vector3(-4.6, L.FLOOR_Y, 14.52)
	g.rotation_degrees.y = 180.0          # front faces -z (into the room)
	add_child(g)
	dbox(Vector3(1.0, 0.8, 0.6), Vector3(0, 0.4, 0), Color(0.75, 0.77, 0.8), g, 0.3, true)
	var cab := dbox(Vector3(1.0, 0.72, 0.62), Vector3(0, 1.2, 0), Color(0.85, 0.9, 0.95), g, 0.1, true)
	(cab.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(cab.material_override as StandardMaterial3D).albedo_color = Color(0.8, 0.9, 1.0, 0.28)
	dbox(Vector3(1.02, 0.05, 0.64), Vector3(0, 1.58, 0), Color(0.55, 0.57, 0.6), g)
	for s in [-1.0, 1.0]:
		var port := Node3D.new()
		port.position = Vector3(s * 0.24, 1.15, 0.32)
		g.add_child(port)
		dcyl(0.1, 0.03, Vector3.ZERO, Color(0.25, 0.27, 0.3), port, Vector3(90, 0, 0), 0.6)
		var glove := dcyl(0.075, 0.22, Vector3(0, 0, -0.12), Color(0.2, 0.22, 0.2), port, Vector3(90, 0, 0), 0.0)
		_gloves.append(glove)
		part(StringName("glove_" + ("l" if s < 0 else "r")), Vector3(0.22, 0.22, 0.08), Vector3(0, 0, 0.02), port)
		part(StringName("clamp_" + ("l" if s < 0 else "r")), Vector3(0.24, 0.05, 0.05), Vector3(0, 0.12, 0.03), port)
	_tray_item = dcyl(0.03, 0.1, Vector3(0.1, 0.9, 0.0), Color(0.85, 0.9, 0.95), g)
	_gb_gauge = readout(Vector3(-0.34, 1.68, 0.3), Vector2(0.24, 0.1), g, 10)
	_gb_status = readout(Vector3(0.0, 1.68, 0.3), Vector2(0.26, 0.1), g, 9)
	button("leak_test", Vector3(0.2, 1.66, 0.31), Color(0.95, 0.75, 0.2), g, Vector3(0.05, 0.03, 0.012))
	button("purge", Vector3(0.3, 1.66, 0.31), Color(0.3, 0.8, 0.95), g, Vector3(0.05, 0.03, 0.012))
	text("LEAK TEST   PURGE", Vector3(0.25, 1.73, 0.31), 7, Color(0.1, 0.1, 0.1), g)
	text("GLOVEBOX GB-1 · KEEP SEALED · −0.5 kPa", Vector3(0, 0.84, 0.31), 9, Color(0.1, 0.1, 0.1), g)
	# Transfer chamber on the right (west) side of the box.
	var tc := Node3D.new()
	tc.name = "TransferChamber"
	tc.position = Vector3(0.62, 1.1, 0.05)
	g.add_child(tc)
	dbox(Vector3(0.24, 0.26, 0.3), Vector3.ZERO, Color(0.7, 0.72, 0.75), tc, 0.4)
	_chamber_item = dcyl(0.025, 0.1, Vector3(0, 0, 0), Color(0.85, 0.9, 0.95), tc)
	_outer = Node3D.new()
	_outer.position = Vector3(0.12, 0, 0.15)
	tc.add_child(_outer)
	dbox(Vector3(0.02, 0.22, 0.28), Vector3(0, 0, -0.14), Color(0.45, 0.47, 0.5), _outer)
	part(&"outer_door", Vector3(0.05, 0.24, 0.3), Vector3(0.0, 0, -0.14), _outer)
	_inner = Node3D.new()
	_inner.position = Vector3(-0.12, 0, 0.0)
	tc.add_child(_inner)
	dbox(Vector3(0.02, 0.2, 0.26), Vector3.ZERO, Color(0.55, 0.57, 0.6), _inner)
	part(&"inner_door", Vector3(0.05, 0.22, 0.28), Vector3(0, 0, 0), _inner)
	part(&"chamber", Vector3(0.18, 0.2, 0.24), Vector3(0, 0, 0), tc)
	text("TRANSFER\nOUTER ▸", Vector3(0.0, 0.2, 0.16), 8, Color(0.1, 0.1, 0.1), tc)
	part(&"glove_drawer", Vector3(0.3, 0.12, 0.08), Vector3(-0.3, 0.55, 0.32), g)
	text("SPARE GLOVES", Vector3(-0.3, 0.62, 0.31), 7, Color(0.1, 0.1, 0.1), g)


func _build_optics() -> void:
	var o := Node3D.new()
	o.name = "OpticalBench"
	o.position = Vector3(-5.92, L.FLOOR_Y, 13.35)
	o.rotation_degrees.y = 90.0           # faces +x into the room
	add_child(o)
	dbox(Vector3(1.3, 0.05, 0.32), Vector3(0, 0.9, 0), Color(0.18, 0.2, 0.22), o, 0.3, true)
	dbox(Vector3(1.3, 0.85, 0.28), Vector3(0, 0.43, -0.02), Color(0.35, 0.37, 0.4), o, 0.4, true)
	dcyl(0.03, 0.18, Vector3(-0.5, 1.0, 0), Color(0.15, 0.15, 0.17), o, Vector3(0, 0, 90))
	text("LASER", Vector3(-0.5, 1.12, 0.06), 7, Color(0.95, 0.4, 0.3), o)
	dbox(Vector3(0.06, 0.1, 0.02), Vector3(-0.15, 1.0, 0), Color(0.75, 0.8, 0.85), o)
	dcyl(0.035, 0.02, Vector3(0.12, 1.0, 0), Color(0.7, 0.85, 1.0), o, Vector3(0, 0, 90), 0.1)
	# Sensor display (the real image of the spot).
	var disp := Node3D.new()
	disp.position = Vector3(0.45, 1.18, -0.04)
	o.add_child(disp)
	dbox(Vector3(0.3, 0.24, 0.02), Vector3.ZERO, Color(0.02, 0.03, 0.04), disp, 0.1)
	_cross = Node3D.new()
	_cross.position = Vector3(0, 0, 0.012)
	disp.add_child(_cross)
	var c1 := dbox(Vector3(0.22, 0.003, 0.002), Vector3.ZERO, Color(0.2, 0.9, 0.5), _cross)
	glow(c1, Color(0.2, 0.9, 0.5), 1.0)
	var c2 := dbox(Vector3(0.003, 0.18, 0.002), Vector3.ZERO, Color(0.2, 0.9, 0.5), _cross)
	glow(c2, Color(0.2, 0.9, 0.5), 1.0)
	_spot = dcyl(0.012, 0.004, Vector3(0, 0, 0.014), Color(1.0, 0.3, 0.2), disp, Vector3(90, 0, 0), 0.0)
	glow(_spot, Color(1.0, 0.35, 0.25), 2.5)
	_opt_lbl = text("", Vector3(0, -0.15, 0.012), 9, Color(0.55, 0.95, 0.75), disp)
	var names := ["TILT X", "TILT Y", "FOCUS", "SENSOR ROT"]
	for k in 4:
		var x: float = -0.45 + k * 0.28
		handwheel("opt%d" % k, Vector3(x, 0.78, 0.15), 0.035, o, true, Color(0.2, 0.45, 0.75))
		text(names[k], Vector3(x, 0.71, 0.15), 7, Color(0.95, 0.95, 0.9), o)
	text("OPTICAL BENCH OB-2", Vector3(0, 1.45, -0.1), 10, Color(0.1, 0.1, 0.1), o)


func _build_imaging() -> void:
	# Counter along the east wall.
	dbox(Vector3(0.36, 0.9, 2.2), Vector3(-3.28, L.FLOOR_Y + 0.45, 13.5), Color(0.82, 0.83, 0.85), self, 0.2, true)
	var m := Node3D.new()
	m.name = "Microscope"
	m.position = Vector3(-3.3, L.FLOOR_Y + 0.9, 13.45)
	m.rotation_degrees.y = -90.0
	add_child(m)
	dbox(Vector3(0.2, 0.04, 0.2), Vector3(0, 0.02, 0), Color(0.2, 0.22, 0.25), m)
	dbox(Vector3(0.05, 0.35, 0.05), Vector3(0, 0.2, -0.06), Color(0.85, 0.85, 0.86), m)
	dcyl(0.025, 0.12, Vector3(0, 0.3, 0.0), Color(0.15, 0.15, 0.17), m, Vector3(30, 0, 0))
	part(&"stage", Vector3(0.18, 0.06, 0.18), Vector3(0, 0.07, 0), m)
	handwheel("focus", Vector3(0.11, 0.15, -0.06), 0.03, m, false, Color(0.2, 0.45, 0.75))
	# Display.
	var d := Node3D.new()
	d.name = "ImagingDisplay"
	d.position = Vector3(-3.12, L.FLOOR_Y + 1.45, 13.45)
	d.rotation_degrees.y = -90.0
	add_child(d)
	dbox(Vector3(0.44, 0.3, 0.02), Vector3.ZERO, Color(0.02, 0.03, 0.04), d, 0.1)
	_spec_view = Node3D.new()
	_spec_view.position = Vector3(0, 0.01, 0.012)
	d.add_child(_spec_view)
	_build_specimen_shapes()
	_spec_fog = dbox(Vector3(0.42, 0.26, 0.002), Vector3(0, 0.01, 0.02), Color(0.5, 0.55, 0.6), d, 0.0)
	(_spec_fog.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spec_lbl = text("", Vector3(0, -0.13, 0.012), 9, Color(0.55, 0.95, 0.75), d)
	for k in 4:
		button("class%d" % k, Vector3(-0.15 + k * 0.1, -0.2, 0.01), Color(0.3, 0.8, 0.95), d, Vector3(0.07, 0.03, 0.012))
		text(CLASSES[k], Vector3(-0.15 + k * 0.1, -0.235, 0.012), 6, Color(0.95, 0.95, 0.9), d)
	# Reference card.
	var card := Node3D.new()
	card.position = Vector3(-3.11, L.FLOOR_Y + 1.5, 14.2)
	card.rotation_degrees.y = -90.0
	add_child(card)
	dbox(Vector3(0.34, 0.26, 0.005), Vector3.ZERO, Color(0.95, 0.95, 0.92), card)
	text("CRYSTAL HABIT REFERENCE\nNEEDLE: long thin rods\nPLATE: flat hexagons\nDENDRITE: branching trees\nAMORPHOUS: rounded blobs", Vector3(0, 0, 0.004), 7, Color(0.1, 0.1, 0.1), card)
	# Sample rack (six sealed specimens: real, clickable positions).
	var sr := Node3D.new()
	sr.position = Vector3(-3.13, L.FLOOR_Y + 1.12, 12.75)
	sr.rotation_degrees.y = -90.0
	add_child(sr)
	dbox(Vector3(0.5, 0.03, 0.12), Vector3(0.12, -0.05, 0.06), Color(0.6, 0.62, 0.65), sr)
	for k in 6:
		dcyl(0.018, 0.08, Vector3(k * 0.05 - 0.005, 0.0, 0.06), Color(0.85, 0.9, 0.95), sr, Vector3.ZERO, 0.1)
		text(SPECIMENS[k][0], Vector3(k * 0.05 - 0.005, 0.07, 0.06), 5, Color(0.1, 0.1, 0.1), sr)
		part(StringName("spec%d" % k), Vector3(0.045, 0.1, 0.06), Vector3(k * 0.05 - 0.005, 0.0, 0.06), sr)
	text("SPECIMEN RACK SR-1", Vector3(0.12, 0.12, 0.06), 8, Color(0.1, 0.1, 0.1), sr)
	_sample_rack = rack("LabSampleCarriers", Vector3(-3.22, L.FLOOR_Y + 0.98, 14.35), 2, 0.12, [&"sample_carrier"], "SEALED CARRIERS", self, -90.0)
	spawn_part.call_deferred(&"sample_carrier", _sample_rack)


func _build_specimen_shapes() -> void:
	for c in 4:
		var n := Node3D.new()
		n.name = "Class%d" % c
		_spec_view.add_child(n)
		var col := Color(0.7, 0.85, 1.0)
		for k in 9:
			var a: float = k * 0.7 + c
			var p := Vector3(cos(a) * 0.12 * (k % 3) / 2.0, sin(a * 1.3) * 0.08, 0.0)
			match c:
				0:
					var r := dbox(Vector3(0.12, 0.005, 0.002), p, col, n)
					r.rotation.z = a
				1:
					var hx := dcyl(0.025, 0.002, p, col, n, Vector3(90, 0, 0))
					(hx.mesh as CylinderMesh).radial_segments = 6
				2:
					var trunk := dbox(Vector3(0.004, 0.08, 0.002), p, col, n)
					trunk.rotation.z = a * 0.3
					for b in 3:
						var br := dbox(Vector3(0.003, 0.03, 0.002), p + Vector3(0.012 * (b - 1), 0.02 * b - 0.02, 0), col, n)
						br.rotation.z = 0.8 * (1 if b % 2 == 0 else -1)
				3:
					dcyl(0.012 + 0.01 * (k % 3), 0.002, p, col.darkened(0.2), n, Vector3(90, 0, 0))
		for ch in n.get_children():
			glow(ch, col * 0.5, 0.8)


func _build_incubator_and_pdu() -> void:
	var inc := Node3D.new()
	inc.name = "Incubator"
	inc.position = Vector3(-3.3, L.FLOOR_Y + 0.9, 12.75)
	inc.rotation_degrees.y = -90.0
	add_child(inc)
	dbox(Vector3(0.4, 0.38, 0.3), Vector3(0, 0.19, -0.02), Color(0.92, 0.93, 0.94), inc)
	_inc_lbl = readout(Vector3(0, 0.28, 0.13), Vector2(0.26, 0.1), inc, 9)
	text("INCUBATOR INC-3", Vector3(0, 0.38, 0.13), 7, Color(0.1, 0.1, 0.1), inc)
	part(&"incubator", Vector3(0.4, 0.38, 0.1), Vector3(0, 0.19, 0.1), inc)
	# Research terminal (trends + diagnosis).
	var t := Node3D.new()
	t.name = "ResearchTerminal"
	t.position = Vector3(-3.11, L.FLOOR_Y + 1.62, 12.75)
	t.rotation_degrees.y = -90.0
	add_child(t)
	dbox(Vector3(0.46, 0.3, 0.02), Vector3.ZERO, Color(0.03, 0.04, 0.05), t)
	_term = text("", Vector3(0, 0.0, 0.012), 7, Color(0.55, 0.95, 0.75), t)
	part(&"term_sel", Vector3(0.46, 0.3, 0.04), Vector3(0, 0, 0.02), t)
	button("term_ok", Vector3(0.2, -0.17, 0.01), Color(0.3, 0.9, 0.4), t, Vector3(0.05, 0.025, 0.012))
	# Payload PDU (south wall, west of the door).
	var p := Node3D.new()
	p.name = "PayloadPDU"
	p.position = Vector3(-5.6, L.FLOOR_Y + 1.35, 12.31)
	add_child(p)
	dbox(Vector3(0.5, 0.34, 0.06), Vector3(0, 0, 0.03), Color(0.22, 0.24, 0.27), p)
	text("PAYLOAD PDU · BUS B CIRCUIT B2", Vector3(0, 0.2, 0.062), 8, Color(0.95, 0.95, 0.9), p)
	for k in 3:
		var x: float = -0.15 + k * 0.15
		var lm := dbox(Vector3(0.025, 0.025, 0.01), Vector3(x, 0.08, 0.062), Color(0.2, 0.2, 0.2), p)
		_pdu_lamps.append(lm.material_override)
		text(["INCUBATOR", "IMAGER", "RECORDER"][k], Vector3(x, 0.04, 0.062), 6, Color(0.9, 0.9, 0.9), p)
		part(StringName("fuse%d" % k), Vector3(0.06, 0.05, 0.05), Vector3(x, -0.03, 0.07), p)
		dbox(Vector3(0.03, 0.04, 0.02), Vector3(x, -0.03, 0.062), Color(0.85, 0.8, 0.6), p)
	_pdu_lbl = readout(Vector3(0.0, -0.11, 0.062), Vector2(0.42, 0.07), p, 8)
	button("nff", Vector3(0.2, -0.15, 0.062), Color(0.95, 0.75, 0.2), p, Vector3(0.04, 0.025, 0.012))
	text("LOG: NO FAULT FOUND", Vector3(0.12, -0.15, 0.063), 6, Color(0.95, 0.95, 0.9), p)


# --------------------------------------------------------------- clicks
func on_part(id: StringName) -> void:
	var s: Node = sys()
	var sid: String = String(id)
	if sid.ends_with("_up") or sid.ends_with("_dn"):
		var base: String = sid.substr(0, sid.length() - 3)
		var d: float = 0.05 if sid.ends_with("_up") else -0.05
		if base.begins_with("opt"):
			var k: int = int(base.substr(3))
			opt[k] = snappedf(float(opt[k]) + d, 0.05)
			sfx(&"click")
		elif base == "focus":
			focus_err = snappedf(focus_err + d, 0.05)
			sfx(&"click")
		_refresh()
		return
	match sid:
		"leak_test":
			if outer_open or inner_open:
				say("Close the transfer doors before a leak test.")
				return
			gb_test = 0.0
			gb_dp = -0.5
			sfx(&"click")
			say("Leak test: holding −0.50 kPa for 15 s…")
		"purge":
			if outer_open or inner_open:
				say("INTERLOCK: both transfer doors must be closed to purge.")
				sfx(&"fail")
				return
			if not chamber_has:
				say("Chamber empty — nothing to purge.")
				return
			purge_t = 0.0
			sfx(&"click")
			say("Purging the transfer chamber (8 s)…")
		"outer_door":
			if inner_open:
				say("INTERLOCK: the inner door is open.")
				sfx(&"fail")
				return
			outer_open = not outer_open
			if outer_open:
				purged = false
			sfx(&"latch")
		"inner_door":
			if outer_open:
				say("INTERLOCK: the outer door is open.")
				sfx(&"fail")
				return
			if not inner_open and chamber_has and not purged:
				say("INTERLOCK: purge the chamber before opening the inner door.")
				sfx(&"fail")
				return
			inner_open = not inner_open
			sfx(&"latch")
		"glove_l", "glove_r":
			_glove(sid)
		"clamp_l", "clamp_r":
			if gb_leak == sid:
				gb_leak = ""
				gb_found = true
				sfx(&"ratchet")
				say("Clamp ring tightened. Run the leak test again.")
			else:
				say("Clamp ring tight.")
		"glove_drawer":
			spare_glove = true
			say("Spare glove taken.")
			sfx(&"click")
		"chamber":
			if hands_in and inner_open and chamber_has:
				chamber_has = false
				tray_has = true
				sfx(&"click")
				say("Container moved to the work tray (inside the box). Close the inner door.")
			elif not outer_open and not hands_in:
				say("Open the outer door to load the chamber.")
		"stage":
			if stage == -1:
				say("Select a specimen on the rack first.")
			else:
				say("%s on the stage. Focus." % SPECIMENS[stage][0])
		"incubator":
			say("INC-3: set %.1f °C, actual %.1f °C" % [float(s.lab["incubator_set"]), float(s.lab["incubator_T"])])
		"term_sel":
			diag_i = (diag_i + 1) % 3
			sfx(&"click")
		"term_ok":
			_inc_diag()
		"nff":
			_nff()
		_:
			if sid.begins_with("spec"):
				stage = int(sid.substr(4))
				focus_err = 0.4 if focus_err == 0.0 else focus_err
				sfx(&"click")
				say("%s (%s) placed on the microscope stage." % [SPECIMENS[stage][0], SPECIMENS[stage][1]])
			elif sid.begins_with("class"):
				_classify(int(sid.substr(5)))
			elif sid.begins_with("fuse"):
				var k: int = int(sid.substr(4))
				if not s.lab["fuse"][k]:
					s.lab["fuse"][k] = true
					sfx(&"click")
					say("Fuse replaced: %s outlet." % ["INCUBATOR", "IMAGER", "RECORDER"][k])
				else:
					say("Fuse intact.")
	_refresh()


func _glove(sid: String) -> void:
	var side: String = sid.right(1)
	if gb_leak == "glove_" + side:
		if spare_glove:
			gb_leak = ""
			gb_found = true
			spare_glove = false
			sfx(&"ratchet")
			say("Glove replaced (pinhole at the cuff). Run the leak test again.")
		else:
			say("Pinhole at the cuff of the %s glove — take a spare from the drawer." % ("left" if side == "l" else "right"))
		return
	if gb_leak == "clamp_" + side:
		say("The %s glove's clamp ring is loose." % ("left" if side == "l" else "right"))
		return
	hands_in = not hands_in
	sfx(&"click")
	say("Hands %s the gloves." % ("in" if hands_in else "out of"))


func _classify(k: int) -> void:
	if stage == -1:
		return
	if absf(focus_err) > 0.05:
		say("Too blurred to classify — focus first.")
		return
	var sp: Array = SPECIMENS[stage]
	recorded[sp[0]] = {"class": CLASSES[k], "day": day(), "catalogue": sp[1], "t": clock()}
	sfx(&"click")
	say("Recorded %s (%s) as %s." % [sp[0], sp[1], CLASSES[k]])
	if stage == spec_target:
		spec_recorded_ok = true


func _inc_diag() -> void:
	var s: Node = sys()
	var choice: String = ["HEATER", "COOLING", "DOOR SEAL"][diag_i]
	var truth: String = {"fuse": "HEATER", "overcool": "COOLING"}.get(inc_cause, "")
	if truth == "":
		say("INC-3 within ±0.5 °C — no drift to diagnose.")
		return
	if choice != truth:
		say("Recorded %s — the trend doesn't support it (heater duty %s, lab branch %.1f L/min)." % [choice, "0 %" if not s.lab["fuse"][0] else "100 %", float(s.branch_flows()[1])])
		sfx(&"fail")
		return
	inc_diag = truth
	sfx(&"success")
	say("Cause: %s." % ("heater outlet fuse open — replace it at the PDU" if truth == "HEATER" else "the lab coolant branch is over-cooling — reduce V2 at Thermal Control (B-03)"))


func _nff() -> void:
	var s: Node = sys()
	if pwr_variant == "transient" and s.power["feed1_fault"] == "" and pwr_hold >= 20.0:
		pwr_logged_nff = true
		sfx(&"success")
		say("Logged: NO FAULT FOUND — 20 s watched, no dropouts; earlier events in the log.")
	elif pwr_variant == "":
		say("No payload-power order open.")
	else:
		say("Watch the input for at least 20 s without a dropout before logging NFF (%d s so far)." % int(pwr_hold))


func part_prompt(id: StringName) -> String:
	var sid: String = String(id)
	if sid.ends_with("_up") or sid.ends_with("_dn"):
		return "Click: %s %s" % ["+" if sid.ends_with("_up") else "−", sid.substr(0, sid.length() - 3).to_upper()]
	match sid:
		"leak_test": return "Click: LEAK TEST"
		"purge": return "Click: PURGE transfer chamber"
		"outer_door": return "Click: %s outer transfer door" % ("close" if outer_open else "open")
		"inner_door": return "Click: %s inner transfer door" % ("close" if inner_open else "open")
		"glove_l", "glove_r": return "Click: %s glove" % ("left" if sid.ends_with("l") else "right")
		"clamp_l", "clamp_r": return "Click: glove clamp ring"
		"glove_drawer": return "Click: take a spare glove"
		"chamber": return "Click: move the container (gloves)" if hands_in and inner_open and chamber_has else "Transfer chamber"
		"stage": return "Microscope stage"
		"incubator": return "Click: read INC-3"
		"term_sel": return "Click: terminal — diagnosis (%s)" % ["HEATER", "COOLING", "DOOR SEAL"][diag_i]
		"term_ok": return "Click: record diagnosis"
		"nff": return "Click: log NO FAULT FOUND"
	if sid.begins_with("spec"):
		return "Click: put %s on the microscope" % SPECIMENS[int(sid.substr(4))][0]
	if sid.begins_with("class"):
		return "Click: record as %s" % CLASSES[int(sid.substr(5))]
	if sid.begins_with("fuse"):
		return "Click: %s outlet fuse" % ["INCUBATOR", "IMAGER", "RECORDER"][int(sid.substr(4))]
	return ""


func accepts_part(id: StringName, item: Node) -> bool:
	return id == &"chamber" and outer_open and not chamber_has and item != null and item.item_id == &"sample_carrier"


func stow_part(id: StringName, item: Node3D) -> bool:
	if not accepts_part(id, item):
		return false
	consume_part(item)
	chamber_has = true
	purged = false
	sfx(&"click")
	say("Sealed container in the chamber. Close the outer door and purge.")
	_refresh()
	return true


func stow_hint(id: StringName, item: Node) -> String:
	return "Load %s into the transfer chamber" % item.get_display_name() if id == &"chamber" else ""


# --------------------------------------------------------------- update
func _signal() -> float:
	var e: float = absf(float(opt[0])) + absf(float(opt[1])) + absf(float(opt[2])) * 0.8 + absf(float(opt[3])) * 0.6
	return clampf(1.0 - e * 1.4, 0.0, 1.0)


func _process(delta: float) -> void:
	_update_occlusion(delta)
	var s: Node = sys()
	if s == null:
		return
	if gb_test >= 0.0:
		gb_test += delta
		var rate: float = 0.028 if gb_leak != "" else 0.0015
		gb_dp = minf(gb_dp + rate * delta, 0.0)
		if gb_test >= 15.0:
			gb_test = -1.0
			gb_passed = gb_dp < -0.45
			say("Leak test: decay %.2f kPa in 15 s — %s" % [gb_dp + 0.5, "PASS" if gb_passed else "FAIL (find the leak: gloves, clamp rings)"])
			if gb_passed:
				gb_dp = -0.5
	if purge_t >= 0.0:
		purge_t += delta
		if purge_t >= 8.0:
			purge_t = -1.0
			purged = true
			say("Purge complete. The inner door may be opened.")
	if transfer_done == false and tray_has and not inner_open and not outer_open and not hands_in:
		transfer_done = true
	if has_open(&"b05_optics") and _signal() >= 0.95:
		opt_hold += delta
	else:
		opt_hold = 0.0
	var inc_err: float = absf(float(s.lab["incubator_T"]) - float(s.lab["incubator_set"]))
	if has_open(&"b05_incubator") and inc_diag != "" and inc_err <= 0.5:
		inc_hold += delta
	else:
		inc_hold = 0.0
	# Payload input dropouts (the real FEED-1 behaviour).
	var drop: bool = not s.payload_powered()
	if drop and not _was_dropout:
		pdu_drops += 1
	_was_dropout = drop
	if has_open(&"b05_power") and not drop:
		pwr_hold += delta
	elif drop:
		pwr_hold = 0.0
	set_loop(_fan_loop, null, s.payload_powered())
	if Engine.get_process_frames() % 4 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	var s: Node = sys()
	if s == null:
		return
	if _gb_gauge != null:
		_gb_gauge.text = "%.2f kPa\n%s" % [gb_dp, "TEST %d s" % int(gb_test) if gb_test >= 0.0 else ("PASS" if gb_passed else "")]
	if _gb_status != null:
		_gb_status.text = "%s\n%s" % ["SEALED" if not (outer_open or inner_open) else ("OUTER OPEN" if outer_open else "INNER OPEN"), ("PURGE %d s" % int(purge_t)) if purge_t >= 0.0 else ("PURGED" if purged else ("HANDS IN" if hands_in else "READY"))]
	if _outer != null:
		_outer.rotation_degrees.y = -100.0 if outer_open else 0.0
		_inner.rotation_degrees.y = 100.0 if inner_open else 0.0
	if _chamber_item != null:
		_chamber_item.visible = chamber_has
		_tray_item.visible = tray_has
	for k in _gloves.size():
		var gm: StandardMaterial3D = (_gloves[k] as MeshInstance3D).material_override
		gm.albedo_color = Color(0.3, 0.32, 0.28) if hands_in else Color(0.2, 0.22, 0.2)
		(_gloves[k] as Node3D).scale = Vector3(1, 1.35, 1) if hands_in else Vector3.ONE
	if _spot != null:
		_spot.position = Vector3(float(opt[0]) * 0.18, float(opt[1]) * 0.14, 0.014)
		var blur: float = 1.0 + absf(float(opt[2])) * 6.0
		_spot.scale = Vector3(blur, 1, blur)
		(_spot.material_override as StandardMaterial3D).emission_energy_multiplier = 2.5 / blur
		_cross.rotation.z = float(opt[3]) * 0.8
		_opt_lbl.text = "SIGNAL %d %%%s" % [int(_signal() * 100.0), "  LOCK" if _signal() >= 0.95 else ""]
	if _spec_view != null:
		for c in 4:
			_spec_view.get_node("Class%d" % c).visible = stage >= 0 and _presented_class(stage) == c
		var fog: float = clampf(absf(focus_err) * 2.2, 0.0, 0.92) if stage >= 0 else 0.0
		(_spec_fog.material_override as StandardMaterial3D).albedo_color = Color(0.45, 0.5, 0.55, fog)
		_spec_lbl.text = ("%s · %s · FOCUS %s" % [SPECIMENS[stage][0], _presented_catalogue(stage), "OK" if absf(focus_err) <= 0.05 else "%+.2f" % focus_err]) if stage >= 0 else "NO SPECIMEN"
	if _inc_lbl != null:
		_inc_lbl.text = "SET %.1f  ACT %.1f °C\n%s" % [float(s.lab["incubator_set"]), float(s.lab["incubator_T"]), "OK" if absf(float(s.lab["incubator_T"]) - float(s.lab["incubator_set"])) <= 0.5 else "DRIFT"]
	if _term != null:
		_term.text = "INC-3 TREND  SET %.1f  ACT %.1f °C\nHEATER DUTY %s   LAB BRANCH %.1f L/min\nPAYLOAD INPUT %s  DROPOUTS %d\nDIAG ▶ %s %s" % [float(s.lab["incubator_set"]), float(s.lab["incubator_T"]),
			"100 %" if (s.lab["fuse"][0] and s.payload_powered()) else "0 %", float(s.branch_flows()[1]), "OK" if s.payload_powered() else "LOST", pdu_drops,
			["HEATER", "COOLING", "DOOR SEAL"][diag_i], ("· RECORDED " + inc_diag) if inc_diag != "" else ""]
	for k in _pdu_lamps.size():
		var on: bool = s.payload_powered() and s.lab["pdu"][k] and s.lab["fuse"][k]
		light(_pdu_lamps[k], Color(0.3, 0.95, 0.4) if on else Color(1.0, 0.25, 0.15), true)
	if _pdu_lbl != null:
		_pdu_lbl.text = "INPUT %s · DROPOUTS %d · STABLE %d s" % ["OK" if s.payload_powered() else "LOST", pdu_drops, int(pwr_hold)]


## Story presentation hook (lab_sample_disagreement): a recorded specimen
## may be DISPLAYED with another catalogue number / structure. The truth
## (SPECIMENS, `recorded`) is never changed.
func _presented_class(i: int) -> int:
	var sp: Array = SPECIMENS[i]
	if shown_overlay.has(sp[0]):
		return int(shown_overlay[sp[0]].get("class", sp[2]))
	return int(sp[2])


func _presented_catalogue(i: int) -> String:
	var sp: Array = SPECIMENS[i]
	if shown_overlay.has(sp[0]):
		return String(shown_overlay[sp[0]].get("catalogue", sp[1]))
	return String(sp[1])


# ------------------------------------------------------------ orders
func task_rearm(t: StringName, seed: int) -> void:
	var s: Node = sys()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match t:
		&"b05_seal":
			gb_leak = ["clamp_l", "clamp_r", "glove_l", "glove_r", ""][rng.randi() % 5]
			gb_passed = false
			gb_found = false
		&"b05_transfer":
			transfer_done = false
			tray_has = false
			chamber_has = false
			purged = false
			if _sample_rack != null and _sample_rack.count(&"sample_carrier") == 0:
				spawn_part(&"sample_carrier", _sample_rack)
		&"b05_optics":
			for k in 4:
				opt[k] = snappedf(rng.randf_range(-0.45, 0.45), 0.05)
			opt_hold = 0.0
		&"b05_incubator":
			inc_cause = "fuse" if rng.randf() < 0.5 else "overcool"
			inc_diag = ""
			inc_hold = 0.0
			if s != null:
				if inc_cause == "fuse":
					s.lab["fuse"][0] = false
				else:
					s.thermal["v2"] = 1.0
					s.thermal["v1"] = minf(float(s.thermal["v1"]), 0.5)
		&"b05_specimen":
			spec_target = rng.randi() % SPECIMENS.size()
			spec_recorded_ok = false
		&"b05_power":
			pwr_variant = "chatter" if (s != null and s.power["feed1_fault"] == "chatter") or rng.randf() < 0.7 else "transient"
			if s != null:
				s.power["feed1_fault"] = "chatter" if pwr_variant == "chatter" else ""
				if pwr_variant == "transient":
					pdu_drops = maxi(pdu_drops, 3)
			pwr_hold = 0.0
			pwr_logged_nff = false
	_refresh()


func task_done(t: StringName) -> bool:
	var s: Node = sys()
	var done := false
	match t:
		&"b05_seal":
			done = gb_passed
			if done and not outcome.has(t):
				close_task(t, "repaired" if gb_found else "verified_normal", "glovebox GB-1", gb_leak if gb_found else "none", "clamp / glove fixed" if gb_found else "leak test", "decay < 0.05 kPa / 15 s")
		&"b05_transfer":
			done = transfer_done
			if done and not outcome.has(t):
				close_task(t, "verified_normal", "glovebox transfer chamber", "none", "sealed container transferred (purged)", "box sealed, −0.5 kPa")
		&"b05_optics":
			done = opt_hold >= 3.0
			if done and not outcome.has(t):
				close_task(t, "repaired", "optical bench OB-2", "misalignment", "mirror / focus / sensor aligned", "signal ≥ 95 %")
		&"b05_incubator":
			done = inc_hold >= 5.0
			if done and not outcome.has(t):
				close_task(t, "repaired", "incubator INC-3", "drift: " + inc_diag.to_lower(), "fuse replaced" if inc_diag == "HEATER" else "lab coolant branch reduced (B-03)", "INC-3 within ±0.5 °C")
		&"b05_specimen":
			done = spec_recorded_ok
			if done and not outcome.has(t):
				var sp: Array = SPECIMENS[spec_target]
				var ok: bool = String(recorded[sp[0]]["class"]) == CLASSES[int(sp[2])]
				close_task(t, "verified_normal" if ok else "inconclusive", "imaging / %s" % sp[0], "none", "classified %s" % recorded[sp[0]]["class"], "reference match" if ok else "differs from the payload team's reference — review")
		&"b05_power":
			if pwr_variant == "transient":
				done = pwr_logged_nff
				if done and not outcome.has(t):
					close_task(t, "not_reproduced", "payload PDU / FEED-1", "intermittent input dropouts (logged earlier)", "watched 20 s, traced FEED-1", "no dropout reproduced")
			else:
				done = s != null and s.power["feed1_fault"] == "" or (s != null and s.power["b2_source"] == "F2" and pwr_hold >= 10.0)
				done = done and pwr_hold >= 10.0
				if done and not outcome.has(t):
					close_task(t, "repaired", "Bus B FEED-1 / payload PDU", "FEED-1 contactor chatter (intermittent)", "B2 rerouted to FEED-2" if s.power["b2_source"] == "F2" else "contactor replaced", "payload stable 10 s")
	return done


func task_next(t: StringName) -> Dictionary:
	var s: Node = sys()
	match t:
		&"b05_seal":
			return next("Glovebox leak test; find and fix any leak; test again", "LEAK TEST")
		&"b05_transfer":
			if not chamber_has and not tray_has:
				return next("Load a sealed carrier into the transfer chamber (outer door)", "LOAD")
			if chamber_has and not purged:
				return next("Close the outer door and PURGE", "PURGE")
			if chamber_has:
				return next("Inner door open, hands in the gloves, move the container", "TRANSFER")
			return next("Close the inner door, hands out", "SEAL")
		&"b05_optics":
			return next("Align the optical bench: centre and focus the spot (signal ≥ 95 %)", "ALIGN")
		&"b05_incubator":
			if inc_diag == "":
				return next("INC-3 drifting: find the cause from the terminal trends", "DIAGNOSE")
			return next("Fix the cause (%s) and hold INC-3 within ±0.5 °C" % inc_diag.to_lower(), "FIX")
		&"b05_specimen":
			return next("Document specimen %s: microscope, focus, classify" % SPECIMENS[spec_target][0] if spec_target >= 0 else "Document a specimen", "SPECIMEN")
		&"b05_power":
			if s != null and s.power["feed1_fault"] == "chatter" and s.power["b2_source"] == "F1":
				return next("Payload power dropping out: trace Bus B — reroute B2 at Engineering's BUS B TRANSFER panel", "REROUTE")
			return next("Verify payload power stable at the PDU (or log NO FAULT FOUND)", "VERIFY")
	return {}


func task_progress(t: StringName) -> String:
	match t:
		&"b05_optics":
			return "%d %%" % int(_signal() * 100.0)
		&"b05_power":
			return "%d s" % int(pwr_hold)
	return ""


func task_detail(t: StringName) -> Array:
	return ["Payload laboratory (Deck B, north wing)."]


func state_dict() -> Dictionary:
	return {"gb_leak": gb_leak, "gb_passed": gb_passed, "gb_found": gb_found, "outer_open": outer_open, "inner_open": inner_open, "purged": purged, "hands_in": hands_in,
		"chamber_has": chamber_has, "tray_has": tray_has, "transfer_done": transfer_done, "spare_glove": spare_glove, "opt": opt.duplicate(), "stage": stage, "focus_err": focus_err,
		"recorded": recorded.duplicate(true), "spec_target": spec_target, "spec_recorded_ok": spec_recorded_ok, "inc_cause": inc_cause, "inc_diag": inc_diag,
		"pdu_drops": pdu_drops, "pwr_variant": pwr_variant, "pwr_logged_nff": pwr_logged_nff, "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in self:
			set(k, d[k])
	gb_test = -1.0
	purge_t = -1.0
	_refresh()
