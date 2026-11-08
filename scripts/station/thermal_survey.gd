extends "res://scripts/station/equipment_base.gd"
## Round 36 Priority 7: THERMAL SURVEY of the Bus A power terminals -- a
## portable-instrument, multi-room task (Control -> Engineering -> Control).
##
## This node IS the probe's charging/data DOCK (Control Room west wall). It
## also builds TERMINAL BLOCK TB-A under the Engineering power distribution
## panel: three cable-lug terminals (A1 LS-FANS, A2 ENG-AUX, A3 COMMS), each
## with a measuring point (the lug barrel) and its lug nut.
##
## Temperatures come from REAL equipment state (power_distribution.gd):
##   T = 28 + 9 x setting  (+8 per level of excess load on that channel)
##       (+44 if that terminal's lug is LOOSE -- high-resistance joint)
## A reading is ABNORMAL when it exceeds the expected value for its load by
## more than 12 C (a loose lug, or an overloaded channel).
## A work order arms one loose lug (it looks like the others: only the probe
## tells you which). Procedure: take the probe -> measure A1..A3 -> the hot
## terminal is re-torqued (only once it has been MEASURED hot -- nobody
## disturbs a live joint without a reason) -> re-measure -> dock the probe
## in Control, which uploads the survey. Readings taken before a change
## (load setting, re-torque) are outdated and must be re-measured.
## The probe can always be docked unused or mid-survey (nothing is lost).

const POINTS := ["A1 LS-FANS", "A2 ENG-AUX", "A3 COMMS"]
const MEASURE_S := 1.1
const ABNORMAL_MARGIN := 12.0
@export var power_path: NodePath = ^"../PowerDistribution"
@export var carry_system_path: NodePath = ^"../../Player/CarrySystem"

var loose: Array = [false, false, false]
var request_day: int = -1
var done_day: int = -1
var last_upload: Dictionary = {}       # {day, temps: [..], ok}
var history: Array = []
var measuring: int = -1                # point being measured (-1 none)
var _measure_t: float = 0.0
var _slot: Node3D
var _screen: Label3D
var _lamp: StandardMaterial3D
var _block: Node3D
var _nuts: Array = []
var _had_probe: bool = true


func _ready() -> void:
	add_to_group(&"item_dock")
	_base_ready(&"thermal")
	# ---- The dock (charging cradle + data contacts), Control Room. ----
	box(Vector3(0.24, 0.3, 0.06), Vector3(0, 0, -0.03), Color(0.2, 0.22, 0.25))
	box(Vector3(0.26, 0.035, 0.08), Vector3(0, 0.16, -0.02), Color(0.85, 0.55, 0.1))
	label("THERMAL PROBE DOCK", Vector3(0, 0.115, 0.005), 13)
	box(Vector3(0.09, 0.05, 0.05), Vector3(0, -0.035, 0.02), Color(0.06, 0.07, 0.08))   # cradle
	_slot = Node3D.new()
	_slot.name = "ProbeSlot"
	_slot.position = Vector3(0, 0.0, 0.06)
	_slot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # tip down into the cradle
	add_child(_slot)
	_lamp = lamp(Vector3(0.085, 0.08, 0.01))
	_screen = label("", Vector3(0, -0.1, 0.006), 11, Color(0.55, 0.95, 0.75))
	part(&"dock", Vector3(0.14, 0.2, 0.06), Vector3(0, -0.01, 0.03))
	var probe := StaticBody3D.new()
	probe.set_script(preload("res://scripts/interactables/thermal_probe.gd"))
	probe.name = "ThermalProbe"
	var cs: Node = get_node_or_null(carry_system_path)
	var ml: Node = get_node_or_null(message_label_path)
	probe.carry_system_path = cs.get_path() if cs != null else NodePath()
	probe.message_label_path = ml.get_path() if ml != null else NodePath()
	_slot.add_child(probe)
	seat(probe)
	_build_terminal_block()
	_refresh()


func _build_terminal_block() -> void:
	var pw: Node3D = get_node_or_null(power_path)
	if pw == null:
		return
	_block = Node3D.new()
	_block.name = "TerminalBlockTBA"
	_block.position = Vector3(0, -0.43, 0.0)
	pw.add_child(_block)
	box(Vector3(0.6, 0.13, 0.05), Vector3(0, 0, -0.025), Color(0.14, 0.15, 0.16), _block)
	box(Vector3(0.6, 0.012, 0.03), Vector3(0, 0.07, -0.01), Color(0.85, 0.55, 0.1), _block)
	label("TERMINAL BLOCK TB-A  ·  THERMAL CHECK POINTS", Vector3(0, 0.05, 0.003), 9, Color(0.75, 0.78, 0.78), _block)
	for i in 3:
		var x: float = -0.2 + 0.2 * i
		# Cable entering from below, crimped lug, nut on the stud.
		var cable := CSGCylinder3D.new()
		cable.radius = 0.011
		cable.height = 0.09
		cable.position = Vector3(x, -0.075, 0.012)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.12, 0.12, 0.12)
		cable.material = cm
		_block.add_child(cable)
		box(Vector3(0.03, 0.05, 0.016), Vector3(x, -0.012, 0.01), Color(0.72, 0.5, 0.28), _block, 0.85)   # lug barrel
		var nut := box(Vector3(0.026, 0.026, 0.014), Vector3(x, 0.025, 0.017), Color(0.68, 0.7, 0.72), _block, 0.9)
		_nuts.append(nut)
		label(POINTS[i].get_slice(" ", 0), Vector3(x + 0.045, 0.02, 0.003), 11, Color(0.9, 0.9, 0.85), _block)
		# Measuring point = the lug barrel; the nut is re-torqued separately.
		part(StringName("t%d" % i), Vector3(0.05, 0.06, 0.05), Vector3(x, -0.015, 0.02), _block)
		part(StringName("n%d" % i), Vector3(0.04, 0.032, 0.04), Vector3(x, 0.03, 0.025), _block)


# ------------------------------------------------------------ dock / item
func probe() -> Node3D:
	for c in _slot.get_children():
		if "item_id" in c and c.item_id == &"thermal_probe":
			return c
	return null


func probe_anywhere() -> Node3D:
	for n in get_tree().get_nodes_in_group(&"thermal_probe"):
		if not n.is_queued_for_deletion():
			return n
	return null


func seat(item: Node3D) -> void:
	if item.has_method("set_rest_global"):
		item.set_rest_global(_slot.global_transform, _slot)
	item.return_to_rest()
	item.transform = Transform3D()
	item.visible = true
	var c: Node = item.get_node_or_null("Collision")
	if c != null:
		c.disabled = false


func accepts_item(item: Node) -> bool:
	return item != null and "item_id" in item and item.item_id == &"thermal_probe" and probe() == null


func stow(item: Node3D) -> bool:
	if not accepts_item(item):
		return false
	seat(item)
	sfx(&"insert")
	_upload(item)
	_refresh()
	return true


func part_accepts_item(id: StringName, item: Node) -> bool:
	return id == &"dock" and accepts_item(item)


func part_stow(id: StringName, item: Node3D) -> bool:
	return id == &"dock" and stow(item)


func part_stow_hint(id: StringName, item: Node) -> String:
	if id != &"dock" or item == null:
		return ""
	if not survey_requested():
		return "Return thermal probe to dock"
	var st: Dictionary = survey_status(item)
	if st["complete"] and st["abnormal"].is_empty():
		return "Dock probe: upload thermal survey"
	if (item.readings() as Dictionary).is_empty():
		return "Return thermal probe unused"
	return "Dock probe (survey incomplete: %d/3 current)" % st["valid"]


# --------------------------------------------------------- measurement
## Expected (healthy) temperature of a terminal for its present load.
func expected_temp(i: int) -> float:
	var pw: Node = get_node_or_null(power_path)
	var s: int = int(pw.setting[i]) if pw != null else 2
	return 28.0 + 9.0 * s


## The REAL temperature of terminal i now.
func terminal_temp(i: int) -> float:
	var pw: Node = get_node_or_null(power_path)
	var t: float = expected_temp(i)
	if pw != null:
		t += 8.0 * maxi(int(pw.setting[i]) - int(pw.demand[i]), 0) * (2.0 if pw.is_overloaded() else 1.0)
	if bool(loose[i]):
		t += 44.0
	return t


func is_abnormal(i: int, temp: float) -> bool:
	return temp - expected_temp(i) > ABNORMAL_MARGIN


## What a reading of point i depends on (changes => reading outdated).
func point_sig(i: int) -> String:
	var pw: Node = get_node_or_null(power_path)
	return "%s|%s|%s|%s" % [str(pw.setting[i]) if pw != null else "-", str(pw.demand[i]) if pw != null else "-", str(loose[i]), str(pw.is_overloaded()) if pw != null else "-"]


func _carried_probe() -> Node3D:
	var cs: Node = get_node_or_null(carry_system_path)
	if cs != null and cs.is_carrying() and cs.carried_item_id() == &"thermal_probe":
		return cs._carried_item
	return null


func on_part(id: StringName) -> void:
	var s := String(id)
	if s == "dock":
		var cs: Node = get_node_or_null(carry_system_path)
		var held: Node3D = _carried_probe()
		if held != null and accepts_item(held):
			var item: Node3D = cs.take_carried_item_if_matches(&"thermal_probe")
			if item != null:
				stow(item)
		elif probe() == null:
			say("Thermal probe dock: empty (probe TP-3 is out).")
		return
	var i: int = int(s.substr(1))
	if s.begins_with("t"):
		var p: Node3D = _carried_probe()
		if p == null:
			say("Thermal probe required — TP-3 is in its dock in the Control Room.")
			sfx(&"click")
			return
		if measuring >= 0:
			return
		measuring = i
		_measure_t = 0.0
		sfx(&"click")
		say("Measuring %s..." % POINTS[i], 1.2)
	elif s.begins_with("n"):
		var p2: Node3D = probe_anywhere()
		var rec: Dictionary = p2.readings().get(str(i), {}) if p2 != null else {}
		if rec.is_empty() or not is_abnormal(i, float(rec.get("temp", 0.0))):
			say("Measure %s first — don't disturb a live joint without a reason." % POINTS[i].get_slice(" ", 0))
			sfx(&"click")
			return
		if not bool(loose[i]):
			say("%s lug is already at torque." % POINTS[i].get_slice(" ", 0))
			sfx(&"click")
			return
		loose[i] = false
		sfx(&"ratchet")
		say("%s lug re-torqued. Re-measure to confirm." % POINTS[i].get_slice(" ", 0))
		_animate_nut(i)
		if _dp != null:
			_dp.log_event("Terminal %s lug re-torqued" % POINTS[i].get_slice(" ", 0))
	_refresh()


func part_prompt(id: StringName) -> String:
	var s := String(id)
	if s == "dock":
		var cs: Node = get_node_or_null(carry_system_path)
		if cs != null and cs.is_carrying():
			return ""
		return "" if probe() != null else "Thermal probe dock (empty)"
	var i: int = int(s.substr(1))
	var tag: String = POINTS[i].get_slice(" ", 0)
	if s.begins_with("t"):
		if measuring == i:
			return "Measuring %s..." % tag
		return ("Click: Measure %s (thermal probe)" % POINTS[i]) if _carried_probe() != null else "%s terminal (thermal probe needed)" % tag
	if s.begins_with("n"):
		return "Click: Re-torque %s lug" % tag
	return ""


func _process(delta: float) -> void:
	var has_p: bool = probe() != null
	if has_p != _had_probe:
		_had_probe = has_p
		_refresh()
	if measuring < 0:
		return
	_measure_t += delta
	if _measure_t < MEASURE_S:
		return
	var i: int = measuring
	measuring = -1
	var p: Node3D = _carried_probe()
	if p == null:
		say("Measurement interrupted — the probe left the terminal.")
		_refresh()
		return
	var t: float = terminal_temp(i)
	p.set_reading(i, {"temp": snappedf(t, 0.1), "sig": point_sig(i), "day": _dp.day_number if _dp != null else 0})
	var bad: bool = is_abnormal(i, t)
	sfx(&"warn" if bad else &"success")
	say("%s: %d °C — %s (expected ≈%d °C)." % [POINTS[i], roundi(t), "HOT, abnormal" if bad else "normal", roundi(expected_temp(i))], 4.0)
	if _dp != null:
		_dp.log_event("Thermal reading %s %d C%s" % [POINTS[i].get_slice(" ", 0), roundi(t), " HOT" if bad else ""])
	_refresh()


func _animate_nut(i: int) -> void:
	var n: Node3D = _nuts[i]
	var tw := create_tween()
	tw.tween_property(n, "rotation_degrees:z", n.rotation_degrees.z + 90.0, 0.3)


# ------------------------------------------------------------- survey state
func survey_requested() -> bool:
	return request_day != -1 and done_day < request_day


## {valid: n current readings, complete: all 3 current, abnormal: [i..]}
func survey_status(p: Node) -> Dictionary:
	var valid := 0
	var abnormal: Array = []
	var r: Dictionary = p.readings() if p != null else {}
	for i in 3:
		var rec: Dictionary = r.get(str(i), {})
		if rec.is_empty() or String(rec.get("sig", "")) != point_sig(i) or int(rec.get("day", -1)) < request_day:
			continue
		valid += 1
		if is_abnormal(i, float(rec.get("temp", 0.0))):
			abnormal.append(i)
	return {"valid": valid, "complete": valid == 3, "abnormal": abnormal}


func _upload(p: Node3D) -> void:
	if not survey_requested():
		say("Thermal probe TP-3 docked." + ("" if (p.readings() as Dictionary).is_empty() else " No survey is requested — readings kept."))
		return
	var st: Dictionary = survey_status(p)
	if (p.readings() as Dictionary).is_empty():
		say("Thermal probe docked unused. Survey still open: measure TB-A in Engineering.")
		return
	if not st["complete"]:
		say("Probe docked. Survey incomplete — %d of 3 current readings (re-measure after any change)." % st["valid"])
		return
	if not st["abnormal"].is_empty():
		var names: Array = []
		for i in st["abnormal"]:
			names.append(POINTS[i].get_slice(" ", 0))
		say("Survey shows %s HOT — correct the joint, re-measure, then dock again." % ", ".join(names))
		sfx(&"fail")
		return
	var temps: Array = []
	for i in 3:
		temps.append(float(p.readings()[str(i)]["temp"]))
	done_day = _dp.day_number if _dp != null else 0
	last_upload = {"day": done_day, "temps": temps, "ok": true}
	history.append(last_upload.duplicate())
	sfx(&"success")
	say("Thermal survey uploaded: TB-A %s °C — all terminals normal." % "/".join(temps.map(func(t): return str(roundi(t)))))
	if _dp != null:
		_dp.log_event("Thermal survey uploaded (TB-A)")


func _refresh() -> void:
	var p: Node3D = probe()
	var txt := ""
	var c := Color(0.4, 0.45, 0.45)
	if p == null:
		txt = "PROBE OUT"
		c = Color(1.0, 0.75, 0.3)
	elif survey_requested():
		txt = "SURVEY REQUESTED"
		c = Color(1.0, 0.75, 0.3)
	elif done_day >= 0 and done_day == (_dp.day_number if _dp != null else -2):
		txt = "SURVEY UPLOADED"
		c = Color(0.3, 0.9, 0.4)
	else:
		txt = "CHARGING · READY"
		c = Color(0.3, 0.9, 0.4)
	if _screen != null:
		_screen.text = txt
	if _lamp != null:
		set_lamp(_lamp, c, true)
	# Note: a loose lug deliberately LOOKS like the others -- only the probe
	# finds it (that is the point of carrying it there).


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	request_day = _dp.day_number if _dp != null else 0
	loose = [false, false, false]
	loose[posmod(seed, 3)] = true
	_refresh()


## Round 37 severity: routine survey; a terminal measured HOT = warning.
func order_severity() -> int:
	if not survey_requested():
		return 0
	var p: Node3D = probe_anywhere()
	if p != null and not survey_status(p)["abnormal"].is_empty():
		return 2
	return 1


func order_feasible() -> bool:
	return not survey_requested() and probe_anywhere() != null


func order_done() -> bool:
	return request_day != -1 and done_day >= request_day


func order_next() -> Dictionary:
	var cr := &"control_room"
	var en := &"engineering"
	var p: Node3D = probe_anywhere()
	var held: bool = _carried_probe() != null
	if p == null:
		return {"action": "Find thermal probe TP-3", "short": "FIND PROBE", "room": cr}
	var st: Dictionary = survey_status(p)
	if not held and probe() == p:
		if st["complete"] and st["abnormal"].is_empty():
			return {"action": "Dock probe to upload survey", "short": "DOCK PROBE", "room": cr}
		return {"action": "Take thermal probe to Engineering", "short": "TAKE PROBE", "room": cr}
	for i in st["abnormal"]:
		if bool(loose[i]):
			return {"action": "Re-torque %s lug" % POINTS[i].get_slice(" ", 0), "short": "TORQUE %s" % POINTS[i].get_slice(" ", 0), "room": en}
		return {"action": "Re-measure %s" % POINTS[i].get_slice(" ", 0), "short": "MEASURE %s" % POINTS[i].get_slice(" ", 0), "room": en}
	if not st["complete"]:
		for i in 3:
			var rec: Dictionary = p.readings().get(str(i), {})
			if rec.is_empty() or String(rec.get("sig", "")) != point_sig(i) or int(rec.get("day", -1)) < request_day:
				return {"action": "Measure terminal %s" % POINTS[i].get_slice(" ", 0), "short": "MEASURE %s" % POINTS[i].get_slice(" ", 0), "room": en}
	return {"action": "Dock probe in Control (upload)", "short": "DOCK PROBE", "room": cr}


func order_progress() -> String:
	var p: Node3D = probe_anywhere()
	return "%d/3" % (survey_status(p)["valid"] if p != null else 0)


func order_detail() -> Array:
	var lines: Array = ["Thermal survey, terminal block TB-A (Engineering, under the power panel).", "Probe TP-3: dock on the Control Room west wall."]
	var p: Node3D = probe_anywhere()
	for i in 3:
		var rec: Dictionary = p.readings().get(str(i), {}) if p != null else {}
		var t: String = "not measured" if rec.is_empty() else "%d °C%s%s" % [roundi(float(rec["temp"])), " HOT" if is_abnormal(i, float(rec["temp"])) else "", "" if String(rec.get("sig", "")) == point_sig(i) else " (outdated)"]
		lines.append("%s: %s" % [POINTS[i], t])
	return lines


func state_dict() -> Dictionary:
	return {"loose": loose.duplicate(), "request_day": request_day, "done_day": done_day, "last_upload": last_upload.duplicate(true), "history": history.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	loose = Array(d.get("loose", loose)).map(func(v): return bool(v))
	request_day = int(d.get("request_day", request_day))
	done_day = int(d.get("done_day", done_day))
	last_upload = Dictionary(d.get("last_upload", {}))
	history = Array(d.get("history", []))
	measuring = -1
	_refresh()
