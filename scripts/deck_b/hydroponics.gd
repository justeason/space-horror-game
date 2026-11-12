extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-06 BOTANY / HYDROPONICS -- a compact controlled-growth room
## (supplemental food / research; NOT the station's oxygen, and fully
## separate from the personal basil in the Living Quarters).
##   three growth trays (A, B west; C east) with real plants drawn from the
##   model (size = growth, colour = health, droop = dry), a moisture sensor
##   readout, an irrigation emitter, a flow indicator and a drip pad each;
##   three LED grow-light banks that really light the trays (power on Bus B
##   B3), each with an intensity knob and a PAR sensor on its tray;
##   the nutrient reservoir: sample port, EC / pH meter, dosing pumps (A+B
##   concentrate, pH down, make-up water), the irrigation pump;
##   environmental monitor, a cabinet of spare GL-6 LED modules, the log
##   panel (tray health records).
## Tasks: b06_lights, b06_nutrient, b06_irrigation, b06_clean, b06_observe.

const TRAYS := [Vector3(-2.6, 0.0, 13.25), Vector3(-2.6, 0.0, 14.15), Vector3(-0.8, 0.0, 13.7)]
const HEALTH_WORDS := ["HEALTHY", "STRESSED", "POOR"]
var par_read: Array = [false, false, false]
var bank_inspected: int = -1
var lt_seed: String = ""            # module | schedule
var lt_bank: int = -1
var sampled: bool = false
var sample_ec: float = 0.0
var sample_ph: float = 0.0
var irr_tray: int = -1
var irr_seed: String = ""
var emitter_out: bool = false
var emitter_clean: bool = true
var irr_ok_s: float = 0.0
var irr_fixed: bool = false
var cover_off: Array = [false, false, false]
var algae: Array = [0, 0, 0]
var clean_tray: int = -1
var obs_gaze: Array = [0.0, 0.0, 0.0]
var obs_logged: Array = ["", "", ""]
var obs_choice: int = 0
var obs_tray: int = 0

var _plants: Array = []             # per tray: [Node3D plant roots]
var _bank_mats: Array = []
var _bank_lights: Array = []
var _knobs: Array = []
var _moist_lbls: Array = []
var _flow_ind: Array = []
var _drip: Array = []
var _covers: Array = []
var _algae_nodes: Array = []
var _meter: Label3D
var _env: Label3D
var _log_lbl: Label3D
var _cabinet: Rack
var _pump_loop: AudioStreamPlayer3D


func _ready() -> void:
	_room_ready([&"b06_lights", &"b06_nutrient", &"b06_irrigation", &"b06_clean", &"b06_observe"])
	for i in 3:
		_build_tray(i)
	_build_reservoir()
	text("B-06  HYDROPONICS", Vector3(-1.7, L.FLOOR_Y + 2.75, 14.68), 20, Color(0.92, 1.0, 0.9), self, 180.0)
	_pump_loop = machine_loop(loop_stream(2.0, func(t, i): return sin(TAU * 60.0 * t) * 0.14 + (fmod(sin(float(i) * 33.7) * 43758.5453, 1.0) - 0.5) * 0.1 * (0.6 + 0.4 * sin(TAU * 2.0 * t))), Vector3(-1.7, L.FLOOR_Y + 0.4, 14.5), -18.0)
	_refresh()


func h() -> Dictionary:
	var s: Node = sys()
	return s.hydro if s != null else {}


# ------------------------------------------------------------- geometry
func _build_tray(i: int) -> void:
	var p: Vector3 = TRAYS[i]
	var east: bool = i == 2
	var t := Node3D.new()
	t.name = "Tray%s" % ["A", "B", "C"][i]
	t.position = Vector3(p.x, L.FLOOR_Y, p.z)
	t.rotation_degrees.y = -90.0 if east else 90.0     # front faces the aisle
	add_child(t)
	dbox(Vector3(0.82, 0.86, 0.5), Vector3(0, 0.43, 0), Color(0.85, 0.86, 0.87), t, 0.2, true)
	dbox(Vector3(0.84, 0.08, 0.52), Vector3(0, 0.9, 0), Color(0.25, 0.3, 0.28), t)
	var plants: Array = []
	for k in 6:
		var pr := Node3D.new()
		pr.position = Vector3(-0.3 + (k % 3) * 0.3, 0.94, -0.1 + int(k / 3) * 0.2)
		t.add_child(pr)
		dcyl(0.008, 0.18, Vector3(0, 0.09, 0), Color(0.3, 0.55, 0.25), pr, Vector3.ZERO, 0.0)
		for lf in 4:
			var leaf := dbox(Vector3(0.09, 0.006, 0.04), Vector3(0, 0.08 + lf * 0.04, 0), Color(0.3, 0.65, 0.28), pr, 0.0)
			leaf.rotation = Vector3(0.3, lf * 1.6, 0.0)
			leaf.name = "Leaf%d" % lf
		plants.append(pr)
	_plants.append(plants)
	# Covers (tray lids with algae patches).
	var cov := Node3D.new()
	cov.position = Vector3(0, 0.95, 0.24)
	t.add_child(cov)
	dbox(Vector3(0.82, 0.04, 0.03), Vector3.ZERO, Color(0.9, 0.92, 0.93), cov)
	part(StringName("cover%d" % i), Vector3(0.82, 0.08, 0.06), Vector3(0, 0, 0.01), cov)
	_covers.append(cov)
	var al: Array = []
	for k in 3:
		var a := dbox(Vector3(0.08, 0.035, 0.005), Vector3(-0.25 + k * 0.25, 0.0, 0.017), Color(0.25, 0.45, 0.2), cov)
		al.append(a)
		part(StringName("algae%d_%d" % [i, k]), Vector3(0.1, 0.05, 0.03), Vector3(-0.25 + k * 0.25, 0.0, 0.03), cov)
	_algae_nodes.append(al)
	# Front instruments: moisture readout, flow indicator, emitter, drip pad.
	_moist_lbls.append(readout(Vector3(-0.22, 0.7, 0.252), Vector2(0.24, 0.08), t, 8))
	part(StringName("moist%d" % i), Vector3(0.24, 0.08, 0.05), Vector3(-0.22, 0.7, 0.26), t)
	var fi := dcyl(0.025, 0.01, Vector3(0.1, 0.7, 0.252), Color(0.2, 0.2, 0.2), t, Vector3(90, 0, 0), 0.0)
	_flow_ind.append(fi.material_override)
	text("FLOW", Vector3(0.1, 0.64, 0.252), 7, Color(0.1, 0.1, 0.1), t)
	part(StringName("emitter%d" % i), Vector3(0.08, 0.08, 0.06), Vector3(0.3, 0.92, 0.2), t)
	dcyl(0.012, 0.05, Vector3(0.3, 0.93, 0.2), Color(0.2, 0.2, 0.22), t)
	var pad := dbox(Vector3(0.3, 0.005, 0.15), Vector3(0.25, 0.01, 0.32), Color(0.4, 0.4, 0.38), t)
	_drip.append(pad.material_override)
	text("TRAY %s" % ["A", "B", "C"][i], Vector3(0.2, 0.5, 0.252), 10, Color(0.1, 0.1, 0.1), t)
	part(StringName("tray%d" % i), Vector3(0.8, 0.3, 0.45), Vector3(0, 1.05, 0), t)
	# Grow-light bank above the tray.
	var bank := dbox(Vector3(0.8, 0.04, 0.3), Vector3(0, 1.75, 0), Color(0.9, 0.85, 0.95), t)
	_bank_mats.append(bank.material_override)
	part(StringName("bank%d" % i), Vector3(0.8, 0.08, 0.3), Vector3(0, 1.75, 0), t)
	var sl := SpotLight3D.new()
	sl.position = Vector3(0, 1.72, 0)
	sl.rotation_degrees.x = -90.0
	sl.spot_angle = 55.0
	sl.spot_range = 1.2
	sl.light_color = Color(0.95, 0.7, 1.0)
	sl.light_energy = 1.4
	t.add_child(sl)
	_bank_lights.append(sl)
	var kn: Node3D = handwheel("lux%d" % i, Vector3(0.35, 1.5, 0.15), 0.03, t, true, Color(0.75, 0.35, 0.85))
	_knobs.append(kn)
	part(StringName("par%d" % i), Vector3(0.06, 0.05, 0.06), Vector3(-0.35, 1.0, 0.2), t)
	dbox(Vector3(0.04, 0.02, 0.04), Vector3(-0.35, 0.99, 0.2), Color(0.95, 0.95, 0.9), t)


func _build_reservoir() -> void:
	var r := Node3D.new()
	r.name = "Reservoir"
	r.position = Vector3(-1.7, L.FLOOR_Y, 14.55)
	r.rotation_degrees.y = 180.0
	add_child(r)
	dbox(Vector3(0.9, 0.7, 0.25), Vector3(0, 0.35, 0), Color(0.82, 0.86, 0.84), r, 0.2, true)
	dcyl(0.012, 0.08, Vector3(-0.3, 0.75, 0.12), Color(0.7, 0.7, 0.72), r)
	part(&"sample", Vector3(0.08, 0.12, 0.08), Vector3(-0.3, 0.75, 0.13), r)
	text("SAMPLE", Vector3(-0.3, 0.86, 0.13), 7, Color(0.1, 0.1, 0.1), r)
	_meter = readout(Vector3(-0.05, 0.95, 0.12), Vector2(0.26, 0.1), r, 9)
	for k in 4:
		var x: float = 0.12 + k * 0.08
		button("dose%d" % k, Vector3(x, 0.78, 0.126), [Color(0.3, 0.8, 0.4), Color(0.3, 0.6, 0.95), Color(0.95, 0.6, 0.2), Color(0.6, 0.8, 0.95)][k], r, Vector3(0.05, 0.03, 0.012))
		text(["A+B", "WATER", "pH−", "IRR\nPUMP"][k], Vector3(x, 0.84, 0.126), 6, Color(0.1, 0.1, 0.1), r)
	text("NUTRIENT RESERVOIR · EC 1.2-2.2 · pH 5.6-6.6", Vector3(0, 0.66, 0.126), 7, Color(0.1, 0.1, 0.1), r)
	_env = readout(Vector3(0.0, 1.55, 0.13), Vector2(0.5, 0.1), r, 9)
	# Log panel (tray health records).
	var lp := Node3D.new()
	lp.position = Vector3(0.0, 1.22, 0.13)
	r.add_child(lp)
	dbox(Vector3(0.5, 0.14, 0.01), Vector3.ZERO, Color(0.03, 0.04, 0.05), lp)
	_log_lbl = text("", Vector3(0, 0, 0.007), 7, Color(0.55, 0.95, 0.75), lp)
	part(&"obs_tray", Vector3(0.16, 0.12, 0.04), Vector3(-0.16, 0, 0.02), lp)
	part(&"obs_class", Vector3(0.16, 0.12, 0.04), Vector3(0.02, 0, 0.02), lp)
	button("obs_log", Vector3(0.2, -0.04, 0.007), Color(0.3, 0.9, 0.4), lp, Vector3(0.05, 0.03, 0.012))
	_cabinet = rack("BotanyCabinet", Vector3(-0.62, L.FLOOR_Y + 1.25, 14.6), 2, 0.25, [&"grow_light_module"], "SPARE GL-6 MODULES", self, 180.0)
	spawn_part.call_deferred(&"grow_light_module", _cabinet)


# --------------------------------------------------------------- clicks
func on_part(id: StringName) -> void:
	var s: Node = sys()
	if s == null:
		return
	var hy: Dictionary = s.hydro
	var sid: String = String(id)
	if sid.begins_with("lux") and (sid.ends_with("_up") or sid.ends_with("_dn")):
		var i: int = int(sid.substr(3, 1))
		hy["light"][i] = clampf(float(hy["light"][i]) + (0.2 if sid.ends_with("_up") else -0.2), 0.0, 1.0)
		sfx(&"click")
		say("Bank %s intensity %d %%" % [["A", "B", "C"][i], int(float(hy["light"][i]) * 100.0)])
		_refresh()
		return
	match sid:
		"sample":
			sampled = true
			sample_ec = float(hy["ec"])
			sample_ph = float(hy["ph"])
			sfx(&"click")
			say("Nutrient sample: EC %.2f mS/cm · pH %.1f" % [sample_ec, sample_ph])
		"dose0":
			hy["ec"] = float(hy["ec"]) + 0.2
			sampled = false
			sfx(&"click")
		"dose1":
			hy["ec"] = maxf(float(hy["ec"]) - 0.25, 0.2)
			hy["ph"] = move_toward(float(hy["ph"]), 7.0, 0.05)
			sampled = false
			sfx(&"click")
		"dose2":
			hy["ph"] = float(hy["ph"]) - 0.3
			sampled = false
			sfx(&"click")
		"dose3":
			hy["pump_ok"] = not hy["pump_ok"]
			sfx(&"clunk")
			say("Irrigation pump %s" % ("ON" if hy["pump_ok"] else "OFF"))
		"obs_tray":
			obs_tray = (obs_tray + 1) % 3
			sfx(&"click")
		"obs_class":
			obs_choice = (obs_choice + 1) % 3
			sfx(&"click")
		"obs_log":
			if obs_gaze[obs_tray] < 2.0:
				say("Look at tray %s properly first (2 s)." % ["A", "B", "C"][obs_tray])
				return
			obs_logged[obs_tray] = HEALTH_WORDS[obs_choice]
			sfx(&"click")
			say("Tray %s recorded %s." % [["A", "B", "C"][obs_tray], HEALTH_WORDS[obs_choice]])
			var hlog: Array = hy["log"]
			hlog.append({"day": day(), "t": clock(), "tray": obs_tray, "health": HEALTH_WORDS[obs_choice]})
			if hlog.size() > 30:
				hlog.pop_front()
		_:
			if sid.begins_with("par"):
				var i2: int = int(sid.substr(3))
				par_read[i2] = true
				var out: float = s.light_output(i2)
				say("PAR tray %s: %d µmol/m²/s (target ≥ 300)%s" % [["A", "B", "C"][i2], int(out * 380.0), "  LOW" if out < 0.79 else ""])
			elif sid.begins_with("bank"):
				var i3: int = int(sid.substr(4))
				bank_inspected = i3
				if not hy["light_ok"][i3]:
					if held_kind() == &"grow_light_module":
						consume_part(held())
						hy["light_ok"][i3] = true
						sfx(&"ratchet")
						say("GL-6 module replaced in bank %s." % ["A", "B", "C"][i3])
					else:
						say("Bank %s: GL-6 module driver fault (flicker, 35 %% output). Fetch a spare module." % ["A", "B", "C"][i3])
				else:
					say("Bank %s LEDs OK (%d %%)." % [["A", "B", "C"][i3], int(float(hy["light"][i3]) * 100.0)])
			elif sid.begins_with("moist"):
				var i4: int = int(sid.substr(5))
				var mr: float = s.moisture_reading(i4)
				say("Tray %s moisture %d %%%s" % [["A", "B", "C"][i4], int(mr * 100.0), "  LOW" if mr < 0.4 else ""])
				if irr_seed == "sensor" and i4 == irr_tray and held() == null:
					say("Tray %s moisture %d %% — but the medium is visibly damp and the plants are fine. Recalibrate? (click again)" % [["A", "B", "C"][i4], int(mr * 100.0)])
					if irr_fixed == false and _recal_armed:
						hy["sensor_bias"][i4] = 0.0
						irr_fixed = true
						sfx(&"click")
						say("Moisture sensor recalibrated.")
					_recal_armed = true
			elif sid.begins_with("emitter"):
				_emitter(int(sid.substr(7)))
			elif sid.begins_with("cover"):
				var i5: int = int(sid.substr(5))
				cover_off[i5] = not cover_off[i5]
				sfx(&"click")
			elif sid.begins_with("algae"):
				var parts := sid.substr(5).split("_")
				var ti: int = int(parts[0])
				if algae[ti] > 0 and cover_off[ti]:
					algae[ti] -= 1
					sfx(&"ratchet")
					if algae[ti] == 0:
						hy["trays"][ti]["clean"] = 1.0
						say("Tray %s cover clean." % ["A", "B", "C"][ti])
				elif not cover_off[ti]:
					say("Take the cover off to wipe it.")
			elif sid.begins_with("tray"):
				var i6: int = int(sid.substr(4))
				var tr: Dictionary = hy["trays"][i6]
				say("Tray %s: growth %d %%, leaves %s%s" % [["A", "B", "C"][i6], int(float(tr["growth"]) * 100.0), "green" if float(tr["health"]) > 0.75 else ("yellowing" if float(tr["health"]) > 0.45 else "brown, wilted"), ", drooping" if float(tr["moist"]) < 0.38 else ""])
	_refresh()


var _recal_armed: bool = false


func _emitter(i: int) -> void:
	var hy: Dictionary = h()
	if hy["line"][i] == "blocked":
		if not emitter_out:
			emitter_out = true
			emitter_clean = false
			sfx(&"click")
			say("Emitter out: clogged with root fibre and salt.")
		elif not emitter_clean:
			emitter_clean = true
			sfx(&"ratchet")
			say("Emitter cleared.")
		else:
			emitter_out = false
			hy["line"][i] = ""
			irr_fixed = true
			sfx(&"latch")
			say("Emitter refitted — flow restored.")
	elif hy["line"][i] == "leak":
		hy["line"][i] = ""
		irr_fixed = true
		sfx(&"ratchet")
		say("Feed-line connector reseated (it was weeping onto the drip pad).")
	else:
		say("Emitter %s flowing." % ["A", "B", "C"][i])


func part_prompt(id: StringName) -> String:
	var sid: String = String(id)
	if sid.ends_with("_up") or sid.ends_with("_dn"):
		return "Click: bank intensity %s" % ("+" if sid.ends_with("_up") else "−")
	match sid:
		"sample": return "Click: take a nutrient sample"
		"dose0": return "Click: dose A+B concentrate (EC +)"
		"dose1": return "Click: add make-up water (EC −)"
		"dose2": return "Click: dose pH down"
		"dose3": return "Click: irrigation pump on/off"
		"obs_tray": return "Click: log panel — tray %s" % ["A", "B", "C"][obs_tray]
		"obs_class": return "Click: log panel — %s" % HEALTH_WORDS[obs_choice]
		"obs_log": return "Click: record tray %s as %s" % [["A", "B", "C"][obs_tray], HEALTH_WORDS[obs_choice]]
	if sid.begins_with("par"): return "Click: PAR sensor"
	if sid.begins_with("bank"): return "Click: inspect the LED bank"
	if sid.begins_with("moist"): return "Click: moisture sensor"
	if sid.begins_with("emitter"): return "Click: irrigation emitter / connector"
	if sid.begins_with("cover"): return "Click: tray cover"
	if sid.begins_with("algae"): return "Click: wipe algae"
	if sid.begins_with("tray"): return "Click: look at the plants"
	return ""


# --------------------------------------------------------------- update
func _process(delta: float) -> void:
	_update_occlusion(delta)
	var s: Node = sys()
	if s == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		for i in 3:
			var tp: Vector3 = Vector3(TRAYS[i].x, L.FLOOR_Y + 1.0, TRAYS[i].z)
			var d: Vector3 = tp - cam.global_position
			if d.length() < 2.6 and (-cam.global_basis.z).dot(d.normalized()) > 0.9:
				obs_gaze[i] += delta
	if has_open(&"b06_irrigation") and irr_tray >= 0:
		var hy: Dictionary = s.hydro
		var ok: bool = hy["line"][irr_tray] == "" and s.moisture_reading(irr_tray) >= 0.4 and hy["pump_ok"]
		irr_ok_s = irr_ok_s + delta if ok else 0.0
	set_loop(_pump_loop, null, s.hydro["pump_ok"] and s.powered(2))
	if Engine.get_process_frames() % 8 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	var s: Node = sys()
	if s == null:
		return
	var hy: Dictionary = s.hydro
	var t_ms: int = Time.get_ticks_msec()
	for i in 3:
		var tr: Dictionary = hy["trays"][i]
		var hp: float = float(tr["health"])
		var col: Color = Color(0.55, 0.42, 0.18).lerp(Color(0.25, 0.62, 0.25), clampf((hp - 0.3) / 0.6, 0.0, 1.0))
		var droop: float = 0.9 if float(tr["moist"]) < 0.38 else 0.3
		for pr in _plants[i]:
			(pr as Node3D).scale = Vector3.ONE * (0.6 + 0.8 * float(tr["growth"]))
			for lf in (pr as Node3D).get_children():
				if String(lf.name).begins_with("Leaf"):
					((lf as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = col
					(lf as Node3D).rotation.x = droop
		var out: float = s.light_output(i)
		var flicker: bool = not hy["light_ok"][i] and (t_ms / 90) % 3 == 0
		var lvl: float = out * (0.4 if flicker else 1.0)
		light(_bank_mats[i], Color(0.95, 0.65, 1.0) * maxf(lvl, 0.05), lvl > 0.02)
		(_bank_lights[i] as SpotLight3D).light_energy = 1.4 * lvl
		(_bank_lights[i] as SpotLight3D).visible = lvl > 0.02
		set_wheel(_knobs[i], float(hy["light"][i]))
		var feeding: bool = hy["pump_ok"] and hy["line"][i] != "blocked" and s.powered(2)
		light(_flow_ind[i], Color(0.3, 0.8, 1.0), feeding and (t_ms / 250 + i) % 2 == 0)
		(_drip[i] as StandardMaterial3D).albedo_color = Color(0.3, 0.45, 0.6) if hy["line"][i] == "leak" else Color(0.4, 0.4, 0.38)
		(_moist_lbls[i] as Label3D).text = "MOIST %d %%" % int(s.moisture_reading(i) * 100.0)
		(_covers[i] as Node3D).position.y = 1.05 if cover_off[i] else 0.95
		(_covers[i] as Node3D).position.z = 0.4 if cover_off[i] else 0.24
		for k in 3:
			(_algae_nodes[i][k] as Node3D).visible = k < algae[i]
	if _meter != null:
		_meter.text = "EC %.2f  pH %.1f\n%s" % [sample_ec, sample_ph, "SAMPLE" if sampled else "STALE — RESAMPLE"] if sample_ec > 0.0 else "EC/pH METER\nTAKE SAMPLE"
	if _env != null:
		_env.text = "CHAMBER 24.0 °C · RH 68 %% · LIGHTS %s · PUMP %s" % ["ON" if s.powered(2) else "NO POWER", "ON" if hy["pump_ok"] else "OFF"]
	if _log_lbl != null:
		_log_lbl.text = "TRAY ▶ %s   %s\nA %s · B %s · C %s" % [["A", "B", "C"][obs_tray], HEALTH_WORDS[obs_choice], obs_logged[0] if obs_logged[0] != "" else "-", obs_logged[1] if obs_logged[1] != "" else "-", obs_logged[2] if obs_logged[2] != "" else "-"]
		if has_meta(&"story_line"):
			_log_lbl.text += "\n" + String(get_meta(&"story_line"))


func _health_word(i: int) -> String:
	var hp: float = float(h()["trays"][i]["health"])
	return "HEALTHY" if hp > 0.72 else ("STRESSED" if hp > 0.45 else "POOR")


# ------------------------------------------------------------ orders
func task_rearm(t: StringName, seed: int) -> void:
	var s: Node = sys()
	if s == null:
		return
	var hy: Dictionary = s.hydro
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match t:
		&"b06_lights":
			lt_bank = rng.randi() % 3
			lt_seed = "module" if rng.randf() < 0.6 else "schedule"
			if lt_seed == "module":
				hy["light_ok"][lt_bank] = false
			else:
				hy["light"][lt_bank] = 0.4
			par_read = [false, false, false]
			bank_inspected = -1
		&"b06_nutrient":
			var r: int = rng.randi() % 3
			if r == 0:
				hy["ec"] = 0.85
			elif r == 1:
				hy["ec"] = 2.6
			else:
				hy["ph"] = 7.2
			sampled = false
			sample_ec = 0.0
		&"b06_irrigation":
			irr_tray = rng.randi() % 3
			irr_seed = ["blocked", "leak", "sensor"][rng.randi() % 3]
			if irr_seed == "sensor":
				hy["sensor_bias"][irr_tray] = -0.32
			else:
				hy["line"][irr_tray] = irr_seed
				hy["trays"][irr_tray]["moist"] = 0.33
			irr_fixed = false
			irr_ok_s = 0.0
			emitter_out = false
			emitter_clean = true
			_recal_armed = false
		&"b06_clean":
			clean_tray = rng.randi() % 3
			algae[clean_tray] = 3
			hy["trays"][clean_tray]["clean"] = 0.3
			cover_off = [false, false, false]
		&"b06_observe":
			obs_gaze = [0.0, 0.0, 0.0]
			obs_logged = ["", "", ""]
	_refresh()


func task_done(t: StringName) -> bool:
	var s: Node = sys()
	if s == null:
		return false
	var hy: Dictionary = s.hydro
	var done := false
	match t:
		&"b06_lights":
			var all_ok: bool = true
			for i in 3:
				all_ok = all_ok and s.light_output(i) >= 0.79
			done = par_read.all(func(v): return v) and all_ok
			if done and not outcome.has(t):
				close_task(t, "repaired", "grow-light bank %s" % ["A", "B", "C"][lt_bank], "GL-6 module fault" if lt_seed == "module" else "bank dimmed by schedule (40 %)", "module replaced" if lt_seed == "module" else "intensity restored", "PAR ≥ 300 on all trays")
		&"b06_nutrient":
			var ec: float = float(hy["ec"])
			var ph: float = float(hy["ph"])
			done = sampled and ec >= 1.2 and ec <= 2.2 and ph >= 5.6 and ph <= 6.6
			if done and not outcome.has(t):
				close_task(t, "repaired", "nutrient reservoir", "EC / pH out of band", "dosed", "EC %.2f pH %.1f" % [ec, ph])
		&"b06_irrigation":
			done = irr_fixed and irr_ok_s >= 5.0
			if done and not outcome.has(t):
				close_task(t, "sensor_fault" if irr_seed == "sensor" else "repaired", "tray %s irrigation" % ["A", "B", "C"][irr_tray], {"blocked": "blocked emitter", "leak": "leaking connector", "sensor": "moisture sensor offset"}.get(irr_seed, ""), {"blocked": "emitter cleared", "leak": "connector reseated", "sensor": "sensor recalibrated"}.get(irr_seed, ""), "flow and moisture normal")
		&"b06_clean":
			done = clean_tray >= 0 and algae[clean_tray] == 0 and not cover_off[clean_tray]
			if done and not outcome.has(t):
				close_task(t, "repaired", "tray %s" % ["A", "B", "C"][clean_tray], "algae on the cover", "cover cleaned", "cover refitted")
		&"b06_observe":
			done = not obs_logged.has("")
			if done and not outcome.has(t):
				var ok: bool = true
				for i in 3:
					ok = ok and obs_logged[i] == _health_word(i)
				close_task(t, "verified_normal" if ok else "inconclusive", "growth trays", "none", "visual health records", "A %s · B %s · C %s" % obs_logged)
	return done


func task_next(t: StringName) -> Dictionary:
	match t:
		&"b06_lights":
			return next("Check PAR on all three trays; find and fix the weak bank", "GROW LIGHTS")
		&"b06_nutrient":
			return next("Sample the reservoir; dose to EC 1.2-2.2 / pH 5.6-6.6; resample", "NUTRIENT")
		&"b06_irrigation":
			return next("Tray %s looks wrong: compare flow, moisture, drip pad, plants; fix the cause" % (["A", "B", "C"][irr_tray] if irr_tray >= 0 else "?"), "IRRIGATION")
		&"b06_clean":
			return next("Clean the algae off tray %s's cover" % (["A", "B", "C"][clean_tray] if clean_tray >= 0 else "?"), "CLEAN")
		&"b06_observe":
			return next("Look at each tray and record its health on the log panel", "OBSERVE")
	return {}


func task_feasible(t: StringName) -> bool:
	if t == &"b06_lights":
		return _cabinet == null or _cabinet.count(&"grow_light_module") > 0
	return true


func state_dict() -> Dictionary:
	return {"par_read": par_read.duplicate(), "lt_seed": lt_seed, "lt_bank": lt_bank, "sampled": sampled, "sample_ec": sample_ec, "sample_ph": sample_ph,
		"irr_tray": irr_tray, "irr_seed": irr_seed, "irr_fixed": irr_fixed, "cover_off": cover_off.duplicate(), "algae": algae.duplicate(), "clean_tray": clean_tray,
		"obs_logged": obs_logged.duplicate(), "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in self:
			set(k, d[k])
	_refresh()
