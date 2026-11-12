extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: B-07 MEDICAL AND EXERCISE BAY (compact; one technician).
##   fold-down examination bench with restraint strap, the health monitor
##   and its sensor clip (readings from the REAL condition: fatigue, meals,
##   drinks, cabin O2 -- deck_b_systems.vitals());
##   dosimeter reader (reference-source CAL check, gain adjust) and the
##   badge holder (the badge is a real part);
##   medical supply cabinet (three bins with counts / expiry) and the
##   sealed emergency first-aid kit (seal tag, five items);
##   a cycle ERGOMETER with a harness and handholds: the exercise session
##   is a real seated interaction (feet on the pedals, hands on the bars,
##   hold W or click to pedal); its load cell has a zero / span calibration.
## Tasks: b07_health, b07_dosimeter, b07_supplies, b07_ergo, b07_kit.
## Exercise is optional: a session counts for the day (vitals improve a
## little; nothing is required).

const BINS := ["DRESSINGS", "ANALGESICS", "TRAUMA"]
# Health check
var strapped: bool = false
var clip_on: bool = false
var measuring: float = -1.0
var vitals: Dictionary = {}
var recorded_check: bool = false
# Dosimeter
var badge_in: bool = false
var badge_payload: Dictionary = {}
var cal_checked: bool = false
var dose_read: float = -1.0
var dose_logged: bool = false
var last_read_day: int = 0
# Supplies / kit
var cab_open: bool = false
var bins: Array = [6, 4, 3]
var bin_min: Array = [4, 3, 2]
var bin_exp: Array = [190, 160, 220]
var flagged: Array = [false, false, false]
var sup_seed: int = -1
var kit_tag_ok: bool = true
var kit_open: bool = false
var kit_items: Array = [true, true, true, true, true]
var kit_taken: bool = false
var kit_checked: bool = false
var kit_sealed: bool = true
var kit_was_broken: bool = false
# Ergometer
var ergo_zero: float = 0.0
var ergo_span: float = 1.0
var ergo_zeroed: bool = false
var ergo_spanned: bool = false
var exercising: bool = false
var ex_progress: float = 0.0
var ex_crank: float = 0.0
var _ex_saved_ic: bool = true

var _monitor: Label3D
var _clip: MeshInstance3D
var _strap: MeshInstance3D
var _reader: Label3D
var _badge_vis: MeshInstance3D
var _cab_doors: Array = []
var _bin_lbls: Array = []
var _kit_lbl: Label3D
var _kit_lid: Node3D
var _ergo_lbl: Label3D
var _crank: Node3D
var _badge_holder: Rack
var _ergo_loop: AudioStreamPlayer3D
var _monitor_loop: AudioStreamPlayer3D


func _ready() -> void:
	_room_ready([&"b07_health", &"b07_dosimeter", &"b07_supplies", &"b07_ergo", &"b07_kit"])
	_build_exam()
	_build_dosimetry()
	_build_supplies()
	_build_ergometer()
	text("B-07  MEDICAL / EXERCISE", Vector3(-11.48, L.FLOOR_Y + 2.75, 11.8), 20, Color(0.98, 0.98, 0.94), self, 90.0)
	_refresh()


func _build_exam() -> void:
	var b := Node3D.new()
	b.name = "ExamBench"
	b.position = Vector3(-11.2, L.FLOOR_Y, 11.75)
	b.rotation_degrees.y = 90.0
	add_child(b)
	dbox(Vector3(1.6, 0.08, 0.55), Vector3(0, 0.62, 0), Color(0.75, 0.78, 0.8), b, 0.2, true)
	dbox(Vector3(1.55, 0.06, 0.5), Vector3(0, 0.69, 0), Color(0.35, 0.55, 0.6), b, 0.0)
	dbox(Vector3(0.06, 0.6, 0.06), Vector3(-0.7, 0.3, -0.2), Color(0.6, 0.62, 0.65), b)
	dbox(Vector3(0.06, 0.6, 0.06), Vector3(0.7, 0.3, -0.2), Color(0.6, 0.62, 0.65), b)
	_strap = dbox(Vector3(0.06, 0.015, 0.52), Vector3(0.1, 0.73, 0), Color(0.15, 0.15, 0.16), b)
	part(&"strap", Vector3(0.2, 0.08, 0.55), Vector3(0.1, 0.74, 0), b)
	for s in [-1.0, 1.0]:
		dcyl(0.015, 0.4, Vector3(s * 0.85, 0.9, 0.2), Color(0.7, 0.72, 0.75), b, Vector3(90, 0, 0), 0.8)
	text("EXAM BENCH · RESTRAINT HANDLES", Vector3(0, 0.55, 0.28), 8, Color(0.1, 0.1, 0.1), b)
	var m := Node3D.new()
	m.name = "HealthMonitor"
	m.position = Vector3(-11.49, L.FLOOR_Y + 1.5, 11.75)
	m.rotation_degrees.y = 90.0
	add_child(m)
	dbox(Vector3(0.44, 0.3, 0.04), Vector3(0, 0, 0.02), Color(0.88, 0.89, 0.9), m)
	_monitor = readout(Vector3(0, 0.02, 0.042), Vector2(0.4, 0.22), m, 9, Color(0.55, 0.95, 0.75))
	button("start_meas", Vector3(-0.12, -0.13, 0.042), Color(0.3, 0.8, 0.95), m, Vector3(0.05, 0.025, 0.012))
	button("record_meas", Vector3(0.12, -0.13, 0.042), Color(0.3, 0.9, 0.4), m, Vector3(0.05, 0.025, 0.012))
	text("START            RECORD", Vector3(0, -0.165, 0.042), 7, Color(0.1, 0.1, 0.1), m)
	_clip = dbox(Vector3(0.03, 0.02, 0.05), Vector3(-11.35, L.FLOOR_Y + 1.15, 12.05), Color(0.9, 0.9, 0.92), self)
	part(&"clip", Vector3(0.08, 0.08, 0.1), Vector3(-11.35, L.FLOOR_Y + 1.15, 12.05))
	text("SENSOR CLIP", Vector3(-11.4, L.FLOOR_Y + 1.22, 12.05), 7, Color(0.1, 0.1, 0.1), self, 90.0)
	_monitor_loop = machine_loop(loop_stream(1.0, func(t, _i): return sin(TAU * 1000.0 * t) * (0.25 if fmod(t, 1.0) < 0.06 else 0.0)), Vector3(-11.45, L.FLOOR_Y + 1.5, 11.75), -26.0)


func _build_dosimetry() -> void:
	var d := Node3D.new()
	d.name = "DosimeterReader"
	d.position = Vector3(-9.11, L.FLOOR_Y + 1.3, 12.75)
	d.rotation_degrees.y = -90.0
	add_child(d)
	dbox(Vector3(0.3, 0.24, 0.12), Vector3(0, 0, 0.06), Color(0.85, 0.86, 0.88), d)
	_reader = readout(Vector3(0, 0.05, 0.121), Vector2(0.24, 0.1), d, 9)
	_badge_vis = dbox(Vector3(0.05, 0.012, 0.07), Vector3(0, -0.06, 0.13), Color(0.9, 0.9, 0.88), d)
	part(&"reader_slot", Vector3(0.12, 0.06, 0.06), Vector3(0, -0.06, 0.13), d)
	button("cal_check", Vector3(-0.09, -0.09, 0.121), Color(0.95, 0.75, 0.2), d, Vector3(0.04, 0.025, 0.012))
	button("cal_adj", Vector3(-0.04, -0.09, 0.121), Color(0.95, 0.5, 0.15), d, Vector3(0.04, 0.025, 0.012))
	button("dose_read", Vector3(0.05, -0.09, 0.121), Color(0.3, 0.8, 0.95), d, Vector3(0.04, 0.025, 0.012))
	button("dose_log", Vector3(0.1, -0.09, 0.121), Color(0.3, 0.9, 0.4), d, Vector3(0.04, 0.025, 0.012))
	text("CAL  ADJ   READ  LOG", Vector3(0, -0.115, 0.121), 6, Color(0.1, 0.1, 0.1), d)
	text("DOSIMETER READER · REF SOURCE 100 µSv", Vector3(0, 0.14, 0.121), 7, Color(0.1, 0.1, 0.1), d)
	_badge_holder = rack("BadgeHolder", Vector3(-9.12, L.FLOOR_Y + 1.62, 12.55), 1, 0.1, [&"dosimeter_badge"], "BADGE", self, -90.0, false)
	spawn_part.call_deferred(&"dosimeter_badge", _badge_holder, {"serial": "DB-0007", "condition": 1.0, "state": "in_service", "issued_day": 1, "history": []})


func _build_supplies() -> void:
	var c := Node3D.new()
	c.name = "SupplyCabinet"
	c.position = Vector3(-10.6, L.FLOOR_Y + 1.25, 10.45)
	add_child(c)
	dbox(Vector3(0.8, 0.9, 0.3), Vector3(0, 0, 0), Color(0.92, 0.92, 0.9), c, 0.2, true)
	dbox(Vector3(0.12, 0.12, 0.01), Vector3(0, 0.3, 0.152), Color(0.85, 0.15, 0.15), c)
	for k in 3:
		var y: float = 0.25 - k * 0.25
		_bin_lbls.append(text("", Vector3(0, y - 0.05, 0.158), 8, Color(0.1, 0.1, 0.1), c))
		part(StringName("bin%d" % k), Vector3(0.7, 0.2, 0.06), Vector3(0, y - 0.05, 0.17), c)
	for s in [-1.0, 1.0]:
		var hg := Node3D.new()
		hg.position = Vector3(s * 0.4, 0, 0.16)
		c.add_child(hg)
		dbox(Vector3(0.4, 0.88, 0.02), Vector3(-s * 0.2, 0, 0), Color(0.88, 0.88, 0.86), hg)
		_cab_doors.append(hg)
	part(&"cab_door", Vector3(0.8, 0.9, 0.04), Vector3(0, 0, 0.18), c)
	text("MEDICAL SUPPLIES", Vector3(0, 0.5, 0.17), 9, Color(0.1, 0.1, 0.1), c)
	# Emergency kit on the wall.
	var k := Node3D.new()
	k.name = "FirstAidKit"
	k.position = Vector3(-9.55, L.FLOOR_Y + 1.45, 10.33)
	add_child(k)
	dbox(Vector3(0.36, 0.26, 0.12), Vector3(0, 0, 0.06), Color(0.85, 0.15, 0.12), k)
	_kit_lid = Node3D.new()
	_kit_lid.position = Vector3(0, 0.13, 0.12)
	k.add_child(_kit_lid)
	dbox(Vector3(0.36, 0.26, 0.02), Vector3(0, -0.13, 0), Color(0.9, 0.2, 0.15), _kit_lid)
	_kit_lbl = text("", Vector3(0, -0.13, 0.012), 7, Color(0.95, 0.95, 0.9), _kit_lid)
	part(&"kit", Vector3(0.36, 0.26, 0.06), Vector3(0, 0, 0.14), k)
	part(&"kit_tag", Vector3(0.06, 0.04, 0.04), Vector3(0.15, -0.12, 0.14), k)


func _build_ergometer() -> void:
	var e := Node3D.new()
	e.name = "Ergometer"
	e.position = Vector3(-10.5, L.FLOOR_Y, 12.95)
	e.rotation_degrees.y = 180.0            # rider faces +z (the wall)
	add_child(e)
	dbox(Vector3(0.5, 0.06, 0.8), Vector3(0, 0.03, 0), Color(0.3, 0.32, 0.34), e, 0.4, true)
	dbox(Vector3(0.08, 0.5, 0.08), Vector3(0, 0.3, 0.25), Color(0.4, 0.42, 0.45), e, 0.5, true)
	dbox(Vector3(0.3, 0.05, 0.25), Vector3(0, 0.58, 0.25), Color(0.15, 0.15, 0.16), e)
	dbox(Vector3(0.08, 0.5, 0.08), Vector3(0, 0.55, -0.25), Color(0.4, 0.42, 0.45), e)
	dcyl(0.015, 0.5, Vector3(0, 0.82, -0.25), Color(0.7, 0.72, 0.75), e, Vector3(0, 0, 90), 0.8)
	_crank = Node3D.new()
	_crank.position = Vector3(0, 0.3, -0.05)
	e.add_child(_crank)
	dcyl(0.12, 0.03, Vector3.ZERO, Color(0.55, 0.57, 0.6), _crank, Vector3(0, 0, 90))
	for s in [-1.0, 1.0]:
		dbox(Vector3(0.02, 0.17, 0.03), Vector3(s * 0.12, s * 0.07, 0), Color(0.6, 0.62, 0.65), _crank)
	_ergo_lbl = readout(Vector3(0, 1.0, -0.28), Vector2(0.24, 0.1), e, 9)
	_ergo_lbl.rotation_degrees.y = 180.0
	part(&"harness", Vector3(0.4, 0.3, 0.3), Vector3(0, 0.75, 0.2), e)
	button("ergo_zero", Vector3(-0.08, 1.12, -0.28), Color(0.95, 0.75, 0.2), e, Vector3(0.04, 0.025, 0.012))
	button("ergo_ref", Vector3(0.0, 1.12, -0.28), Color(0.3, 0.8, 0.95), e, Vector3(0.04, 0.025, 0.012))
	button("ergo_span", Vector3(0.08, 1.12, -0.28), Color(0.95, 0.5, 0.15), e, Vector3(0.04, 0.025, 0.012))
	text("ZERO  REF100  SPAN", Vector3(0, 1.16, -0.29), 6, Color(0.95, 0.95, 0.9), e, 180.0)
	text("CYCLE ERGOMETER · HARNESS", Vector3(0, 1.25, -0.29), 8, Color(0.95, 0.95, 0.9), e, 180.0)
	_ergo_loop = machine_loop(loop_stream(1.0, func(t, i): return sin(TAU * 180.0 * t) * 0.08 + (fmod(sin(float(i) * 7.3) * 43758.5453, 1.0) - 0.5) * 0.12 * (0.5 + 0.5 * sin(TAU * 2.0 * t))), Vector3(-10.5, L.FLOOR_Y + 0.3, 12.95), -14.0)


# --------------------------------------------------------------- clicks
func on_part(id: StringName) -> void:
	var s: Node = sys()
	var sid: String = String(id)
	match sid:
		"strap":
			strapped = not strapped
			sfx(&"latch")
			say("Restraint strap %s." % ("secured" if strapped else "released"))
		"clip":
			clip_on = not clip_on
			sfx(&"click")
			say("Sensor clip %s." % ("on the finger" if clip_on else "off"))
		"start_meas":
			if not (strapped and clip_on):
				say("Secure the strap and attach the sensor clip first.")
				return
			measuring = 0.0
			sfx(&"click")
		"record_meas":
			if vitals.is_empty():
				say("Run a measurement first.")
				return
			recorded_check = true
			s.med["checks"].append({"day": day(), "t": clock(), "hr": int(vitals["hr"]), "spo2": int(vitals["spo2"]), "flags": vitals["flags"]})
			sfx(&"success")
			say("Health check recorded%s." % ((" — flagged: " + ", ".join(vitals["flags"])) if not vitals["flags"].is_empty() else ""))
		"cal_check":
			if not badge_in:
				say("Insert the badge first (the reference source sits under it).")
				return
			cal_checked = true
			say("Reference source: %.0f µSv (expect 100 ± 5) %s" % [100.0 * float(s.med["reader_gain"]), "CAL OUT" if absf(float(s.med["reader_gain"]) - 1.0) > 0.05 else "OK"])
		"cal_adj":
			if cal_checked and absf(float(s.med["reader_gain"]) - 1.0) > 0.05:
				s.med["reader_gain"] = 1.0
				cal_checked = false
				sfx(&"ratchet")
				say("Reader gain adjusted. Check it again.")
		"dose_read":
			if not (badge_in and cal_checked and absf(float(s.med["reader_gain"]) - 1.0) <= 0.05):
				say("Insert the badge and pass the CAL check first.")
				return
			var days: int = maxi(day() - last_read_day, 1)
			dose_read = s.expected_dose_usv(days) * float(s.med["reader_gain"])
			say("Badge %s: %.0f µSv over %d day(s). Station estimate %.0f µSv. %s" % [badge_payload.get("serial", "DB"), dose_read, days, s.expected_dose_usv(days), "CONSISTENT"])
		"dose_log":
			if dose_read < 0.0:
				return
			dose_logged = true
			s.med["total_msv"] = float(s.med["total_msv"]) + dose_read / 1000.0
			last_read_day = day()
			sfx(&"success")
			say("Dose logged. Return the badge to its holder.")
		"reader_slot":
			if badge_in and held() == null:
				var p: Node3D = spawn_part(&"dosimeter_badge", null, badge_payload)
				p.global_position = _badge_vis.global_position
				badge_in = false
				var c: Node = _carry()
				if c != null:
					c.pick_up(p)
		"cab_door":
			cab_open = not cab_open
			sfx(&"latch")
		"kit_tag":
			kit_checked = true
			if not kit_tag_ok or kit_items.has(false):
				kit_was_broken = true
			say("Seal tag %s." % ("intact, number matches the log" if kit_tag_ok else "BROKEN — the kit has been opened"))
		"kit":
			if not kit_open:
				kit_open = true
				sfx(&"latch")
				var missing: Array = []
				var names := ["DRESSINGS", "TOURNIQUET", "BURN GEL", "SPLINT", "ANALGESICS"]
				for k in 5:
					if not kit_items[k]:
						missing.append(names[k])
				say("Kit contents: %s" % ("complete (5/5)" if missing.is_empty() else "MISSING " + ", ".join(missing)))
			elif kit_items.has(false) and kit_taken:
				kit_items[kit_items.find(false)] = true
				kit_taken = false
				sfx(&"click")
				say("Item replaced from the cabinet.")
			else:
				kit_open = false
				kit_sealed = true
				kit_tag_ok = true
				sfx(&"latch")
				say("Kit closed and resealed (new tag).")
		"harness":
			if exercising:
				end_exercise()
			else:
				begin_exercise()
		"ergo_zero":
			ergo_zero = 0.0
			ergo_zeroed = true
			sfx(&"click")
		"ergo_ref":
			say("Reference 100 W applied: reads %.0f W" % (100.0 * ergo_span + ergo_zero))
		"ergo_span":
			if not ergo_zeroed:
				say("ZERO first.")
				return
			ergo_span = 1.0
			ergo_spanned = true
			sfx(&"click")
			say("Span set: 100 W reads 100 W.")
		_:
			if sid.begins_with("bin"):
				var k: int = int(sid.substr(3))
				if not cab_open:
					say("Open the cabinet first.")
				elif kit_open and kit_items.has(false) and k == 2 and bins[2] > 0:
					bins[2] -= 1
					kit_taken = true
					say("Took a tourniquet from TRAUMA (%d left)." % bins[2])
				else:
					var low: bool = bins[k] < bin_min[k] or bin_exp[k] < day()
					if low:
						flagged[k] = true
						sfx(&"click")
						say("%s: %d (min %d), exp. day %d — FLAGGED for resupply." % [BINS[k], bins[k], bin_min[k], bin_exp[k]])
					else:
						say("%s: %d (min %d), exp. day %d — OK." % [BINS[k], bins[k], bin_min[k], bin_exp[k]])
	_refresh()


func part_prompt(id: StringName) -> String:
	var sid: String = String(id)
	match sid:
		"strap": return "Click: %s restraint strap" % ("release" if strapped else "secure")
		"clip": return "Click: %s sensor clip" % ("remove" if clip_on else "attach")
		"start_meas": return "Click: START measurement"
		"record_meas": return "Click: RECORD"
		"cal_check": return "Click: CAL check (reference source)"
		"cal_adj": return "Click: adjust reader gain"
		"dose_read": return "Click: READ badge"
		"dose_log": return "Click: LOG dose"
		"reader_slot": return "Click: take the badge out" if badge_in else "Reader slot (insert badge: Space)"
		"cab_door": return "Click: %s supply cabinet" % ("close" if cab_open else "open")
		"kit_tag": return "Click: check the seal tag"
		"kit": return "Click: %s first-aid kit" % ("close and reseal" if kit_open and not (kit_items.has(false) and kit_taken) else ("replace the item" if kit_open else "open"))
		"harness": return "Click: %s" % ("release harness" if exercising else "strap into the ergometer (exercise)")
		"ergo_zero": return "Click: ZERO load cell"
		"ergo_ref": return "Click: apply 100 W reference"
		"ergo_span": return "Click: SPAN to reference"
	if sid.begins_with("bin"):
		return "Click: check %s" % BINS[int(sid.substr(3))]
	return ""


func accepts_part(id: StringName, item: Node) -> bool:
	return id == &"reader_slot" and not badge_in and item != null and item.item_id == &"dosimeter_badge"


func stow_part(id: StringName, item: Node3D) -> bool:
	if not accepts_part(id, item):
		return false
	badge_payload = item.payload.duplicate(true)
	consume_part(item)
	badge_in = true
	dose_read = -1.0
	sfx(&"click")
	_refresh()
	return true


func stow_hint(id: StringName, item: Node) -> String:
	return "Insert %s into the reader" % item.get_display_name() if id == &"reader_slot" else ""


# ----------------------------------------------------------- exercise
const SEAT_EYE := Vector3(-10.5, L.FLOOR_Y + 1.42, 12.88)


func _main() -> Node:
	return _dp.get_parent() if _dp != null else null


func begin_exercise() -> bool:
	var m: Node = _main()
	if m == null:
		return false
	var c: Node = _carry()
	if c != null and c.is_carrying():
		say("Put down what you are carrying first.")
		return false
	exercising = true
	ex_progress = 0.0
	var fb: Node = m.get_node("FreeMoveBody")
	fb.velocity = Vector3.ZERO
	fb.set_active(false)
	m.get_node("GlobalFreeMove").mirror_enabled = false
	var player: Node3D = m.get_node("Player")
	player.global_position = SEAT_EYE
	var lp: Node3D = player.get_node("LookPivot")
	lp.rotation.y = wrapf(PI - player.rotation.y, -PI, PI)
	lp._target_yaw = lp.rotation.y
	var ic: Node = m.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_ex_saved_ic = ic.interactions_enabled
	ic.interactions_enabled = false
	sfx(&"latch")
	say("Harness secured. Hold W (or click) to pedal · E: release.")
	return true


func end_exercise() -> void:
	var m: Node = _main()
	exercising = false
	if m == null:
		return
	var player: Node3D = m.get_node("Player")
	var stand := Vector3(-9.75, L.EYE_Y, 12.55)
	player.global_position = stand
	var fb: Node = m.get_node("FreeMoveBody")
	fb.sync_to_eye_position(stand)
	fb.set_active(true)
	m.get_node("GlobalFreeMove").mirror_enabled = true
	m.get_node("Player/LookPivot/PitchPivot/Camera3D").interactions_enabled = _ex_saved_ic
	var body: Node = m.get_node_or_null("Player/PlayerBody")
	if body != null and body.has_method("set_climb_pose"):
		body.set_climb_pose({})
	sfx(&"latch")
	if ex_progress >= 1.0:
		var s: Node = sys()
		if s != null and not s.med["exercise_days"].has(day()):
			s.med["exercise_days"].append(day())
		say("Session complete (20 s). Logged for today.")


func _unhandled_input(event: InputEvent) -> void:
	if not exercising:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		end_exercise()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pedal(0.35)
		get_viewport().set_input_as_handled()


func _pedal(dt: float) -> void:
	ex_progress = minf(ex_progress + dt / 20.0, 1.0)
	ex_crank += dt * 6.0


func _exercise_pose() -> void:
	var m: Node = _main()
	var body: Node = m.get_node_or_null("Player/PlayerBody") if m != null else null
	if body == null or not body.has_method("set_climb_pose") or _crank == null:
		return
	var c: Vector3 = _crank.global_position
	var r: float = 0.17
	var f_l := c + Vector3(-0.12, sin(ex_crank) * r, cos(ex_crank) * r)
	var f_r := c + Vector3(0.12, sin(ex_crank + PI) * r, cos(ex_crank + PI) * r)
	var bar: Vector3 = SEAT_EYE + Vector3(0, -0.6, 0.42)
	body.set_climb_pose({"hand_l": bar + Vector3(-0.2, 0, 0), "hand_r": bar + Vector3(0.2, 0, 0), "foot_l": f_l, "foot_r": f_r, "blend": 1.0})


# --------------------------------------------------------------- update
func _process(delta: float) -> void:
	_update_occlusion(delta)
	var s: Node = sys()
	if measuring >= 0.0:
		measuring += delta
		if measuring >= 6.0:
			measuring = -1.0
			vitals = s.vitals() if s != null else {}
			sfx(&"success")
	if exercising:
		if Input.is_key_pressed(KEY_W):
			_pedal(delta)
		_exercise_pose()
		if _crank != null:
			_crank.rotation.x = ex_crank
	set_loop(_ergo_loop, null, exercising and Input.is_key_pressed(KEY_W))
	set_loop(_monitor_loop, null, clip_on and measuring >= 0.0)
	if Engine.get_process_frames() % 6 == 0 and is_visible_in_tree():
		_refresh()


func _refresh() -> void:
	if _monitor != null:
		if measuring >= 0.0:
			_monitor.text = "MEASURING %d s\n" % int(6.0 - measuring)
		elif not vitals.is_empty():
			_monitor.text = "HR %d bpm   (60-85)\nSpO2 %d %%  (≥ 95)\nTEMP %.1f °C  GLU %.1f mmol/L\n%s" % [int(vitals["hr"]), int(vitals["spo2"]), float(vitals["temp"]), float(vitals["glucose"]), ("FLAGS: " + ", ".join(vitals["flags"])) if not vitals["flags"].is_empty() else "WITHIN NORMAL RANGES"]
		else:
			_monitor.text = "HEALTH MONITOR\nSTRAP + CLIP, THEN START"
	if _strap != null:
		_strap.visible = strapped
	if _clip != null:
		_clip.position.y = L.FLOOR_Y + (1.3 if clip_on else 1.15)
	if _badge_vis != null:
		_badge_vis.visible = badge_in
	var s: Node = sys()
	if _reader != null and s != null:
		_reader.text = "%s\n%s" % ["BADGE " + String(badge_payload.get("serial", "")) if badge_in else "NO BADGE", ("%.0f µSv" % dose_read) if dose_read >= 0.0 else ("CAL OK" if cal_checked and absf(float(s.med["reader_gain"]) - 1.0) <= 0.05 else "")]
	for k in _cab_doors.size():
		(_cab_doors[k] as Node3D).rotation_degrees.y = (100.0 if k == 0 else -100.0) if cab_open else 0.0
	for k in _bin_lbls.size():
		(_bin_lbls[k] as Label3D).text = "%s  %d  (min %d) EXP D%d%s" % [BINS[k], bins[k], bin_min[k], bin_exp[k], "  ⚑" if flagged[k] else ""] if cab_open else ""
	if _kit_lid != null:
		_kit_lid.rotation_degrees.x = -100.0 if kit_open else 0.0
		_kit_lbl.text = "FIRST AID\nSEAL %s" % ("OK" if kit_tag_ok and kit_sealed else "BROKEN")
	if _ergo_lbl != null:
		_ergo_lbl.text = "%s\nREF %.0f W" % [("SESSION %d %%" % int(ex_progress * 100.0)) if exercising else ("ZERO %+.0f W" % ergo_zero), 100.0 * ergo_span + ergo_zero]


# ------------------------------------------------------------ orders
func task_rearm(t: StringName, seed: int) -> void:
	var s: Node = sys()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match t:
		&"b07_health":
			recorded_check = false
			vitals = {}
		&"b07_dosimeter":
			cal_checked = false
			dose_read = -1.0
			dose_logged = false
			if s != null:
				s.med["reader_gain"] = 0.9 if rng.randf() < 0.4 else 1.0
			if _badge_holder != null and _badge_holder.count(&"dosimeter_badge") == 0 and not badge_in and held_kind() != &"dosimeter_badge":
				spawn_part(&"dosimeter_badge", _badge_holder, {"serial": "DB-0007", "condition": 1.0, "state": "in_service", "history": []})
		&"b07_supplies":
			sup_seed = rng.randi() % 3
			flagged = [false, false, false]
			if rng.randf() < 0.5:
				bins[sup_seed] = bin_min[sup_seed] - 1
			else:
				bin_exp[sup_seed] = day() - 1
		&"b07_ergo":
			ergo_zero = snappedf(rng.randf_range(4.0, 9.0), 0.5)
			ergo_span = 0.92
			ergo_zeroed = false
			ergo_spanned = false
		&"b07_kit":
			kit_tag_ok = rng.randf() < 0.4
			kit_items = [true, true, true, true, true]
			if not kit_tag_ok:
				kit_items[1] = false
			kit_open = false
			kit_checked = false
			kit_sealed = kit_tag_ok
			kit_was_broken = false
	_refresh()


func task_done(t: StringName) -> bool:
	var s: Node = sys()
	var done := false
	match t:
		&"b07_health":
			done = recorded_check
			if done and not outcome.has(t):
				close_task(t, "verified_normal" if vitals.get("flags", []).is_empty() else "inconclusive", "health monitor", "none" if vitals.get("flags", []).is_empty() else ", ".join(vitals["flags"]), "measured HR / SpO2 / temperature", "HR %d SpO2 %d" % [int(vitals.get("hr", 0)), int(vitals.get("spo2", 0))])
		&"b07_dosimeter":
			done = dose_logged and not badge_in and _badge_holder != null and _badge_holder.count(&"dosimeter_badge") == 1
			if done and not outcome.has(t):
				close_task(t, "verified_normal", "dosimeter reader", "reader gain drift" if s != null else "", "CAL check / gain adjust, badge read", "%.0f µSv, consistent with the station estimate" % dose_read)
		&"b07_supplies":
			done = sup_seed >= 0 and flagged[sup_seed] and not cab_open
			if done and not outcome.has(t):
				close_task(t, "deferred", "medical supply cabinet", "%s below minimum / expired" % BINS[sup_seed], "flagged for resupply", "resupply requested (cargo)")
		&"b07_ergo":
			done = ergo_zeroed and ergo_spanned
			if done and not outcome.has(t):
				close_task(t, "repaired", "ergometer load cell", "zero / span drift", "zero and span calibrated", "100 W reads 100 W")
		&"b07_kit":
			done = kit_checked and not kit_open and kit_sealed and not kit_items.has(false)
			if done and not outcome.has(t):
				close_task(t, "repaired" if kit_was_broken else "verified_normal", "first-aid kit", "seal broken, tourniquet missing" if kit_was_broken else "none", "item replaced, kit resealed" if kit_was_broken else "seal and contents checked", "5/5 items, seal intact")
	return done


func task_next(t: StringName) -> Dictionary:
	match t:
		&"b07_health":
			return next("Health check: strap, sensor clip, START, RECORD (Medical bay)", "HEALTH")
		&"b07_dosimeter":
			if dose_logged:
				return next("Return the badge to its holder", "BADGE BACK")
			return next("Read the dosimeter badge: reader CAL check, READ, LOG", "DOSIMETER")
		&"b07_supplies":
			return next("Inspect the medical supply cabinet; flag what needs resupply", "SUPPLIES")
		&"b07_ergo":
			return next("Calibrate the ergometer load cell: ZERO, REF 100 W, SPAN", "ERGO CAL")
		&"b07_kit":
			return next("Check the first-aid kit's seal and contents; restore and reseal", "KIT")
	return {}


func state_dict() -> Dictionary:
	return {"strapped": strapped, "clip_on": clip_on, "recorded_check": recorded_check, "badge_in": badge_in, "badge_payload": badge_payload.duplicate(true), "cal_checked": cal_checked,
		"dose_read": dose_read, "dose_logged": dose_logged, "last_read_day": last_read_day, "cab_open": cab_open, "bins": bins.duplicate(), "bin_exp": bin_exp.duplicate(),
		"flagged": flagged.duplicate(), "sup_seed": sup_seed, "kit_tag_ok": kit_tag_ok, "kit_open": kit_open, "kit_items": kit_items.duplicate(), "kit_checked": kit_checked, "kit_was_broken": kit_was_broken,
		"kit_sealed": kit_sealed, "ergo_zero": ergo_zero, "ergo_span": ergo_span, "ergo_zeroed": ergo_zeroed, "ergo_spanned": ergo_spanned, "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	for k in d:
		if k == "outcome":
			outcome = {}
			for ok in d[k]:
				outcome[StringName(ok)] = d[k][ok]
		elif k in self:
			set(k, d[k])
	measuring = -1.0
	exercising = false
	_refresh()
