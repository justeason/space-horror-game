extends SceneTree
## Round 36 Priority 7: PORTABLE THERMAL PROBE survey (Control -> Engineering
## -> Control). Real ray + real Space presses at the dock and the terminal
## block. Proves: pickup from the dock; return UNUSED; readings follow the
## real equipment (loose lug -> hot; overloaded channel -> hot; balanced ->
## normal); re-torque only once measured hot; outdated readings after a
## change; upload only with three current normal readings + docking; order
## closes automatically; save/load of location, readings and progress; one
## probe, never stuck in the hand.
var _ok := true
var main: Node
var dp: Node
var carry: Node
var cam: Node
var ts: Node
var pw: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	dp = main.get_node("DayPlan")
	carry = main.get_node("Player/CarrySystem")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	ts = main.get_node("Equipment/ThermalSurvey")
	pw = main.get_node("Equipment/PowerDistribution")
	await _unused_return()
	await _survey()
	await _overload_reading()
	await _save_load()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _probe() -> Node3D:
	return ts.probe_anywhere()


func _count() -> int:
	var n := 0
	for it in main.find_children("*", "", true, false):
		if "item_id" in it and it.item_id == &"thermal_probe" and not it.is_queued_for_deletion():
			n += 1
	return n


func _aim(eye: Vector3, target: Vector3) -> void:
	var fb: Node = main.get_node("FreeMoveBody")
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for k in 2:
		for i in 3: await physics_frame
		var d: Vector3 = target - cam.global_position
		lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
		lp._target_yaw = lp.rotation.y
		var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
		lp.get_node("PitchPivot").rotation.x = pitch
		lp._target_pitch = pitch
	for i in 3: await physics_frame
	await process_frame


func _at_dock() -> void:
	await _aim(ts.global_transform * Vector3(0.0, 1.6 - ts.global_position.y, 0.7), ts.global_transform * Vector3(0, -0.01, 0.04))


func _at_terminal(i: int) -> void:
	var t: Node3D = pw.find_child("Click_t%d" % i, true, false)
	await _aim(pw.global_transform * Vector3(-0.2 + 0.2 * i, 0.15, 0.7), t.global_position)


func _space() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await create_timer(0.9).timeout
	await process_frame


func _click() -> void:
	var h: Object = cam.get_hovered()
	if h != null:
		h.interact()


func _measure(i: int) -> void:
	await _at_terminal(i)
	_click()
	await create_timer(1.3).timeout
	await process_frame


func _unused_return() -> void:
	var p: Node3D = _probe()
	_check("probe TP-3 starts in its Control Room dock", ts.probe() == p and _count() == 1)
	await _at_dock()
	_check("looking at the dock targets the probe ('%s')" % (cam.get_hovered().get_interact_prompt() if cam.get_hovered() != null else "nothing"), cam.get_hovered() == p)
	await _space()
	_check("Space picks the probe up", carry.is_holding(p))
	cam._update_prompt()
	_check("dock hint: 'Return thermal probe' ('%s')" % cam._prompt_label.text, cam._prompt_label.text.find("Return thermal probe") != -1)
	await _space()
	_check("returned UNUSED to its dock", ts.probe() == p and not carry.is_carrying())
	_check("returning it completes nothing", ts.done_day == -1)


func _open_order() -> void:
	dp._order_seq += 1
	dp.orders.append({"id": "WO-T%d" % dp._order_seq, "type": "thermal", "category": "D", "priority": 1, "day": dp.day_number, "seed": 4, "status": "open", "carried_from": -1})
	ts.order_rearm(4)   # loose lug on A2 (4 % 3 == 1)


func _survey() -> void:
	_open_order()
	_check("order arms one loose lug (A2)", ts.loose == [false, true, false])
	_check("guidance: take the probe to Engineering", ts.order_next()["short"] == "TAKE PROBE")
	var p: Node3D = _probe()
	# Measuring without the probe is refused with a pointer to the dock.
	await _at_terminal(0)
	_click()
	await create_timer(1.3).timeout
	_check("no probe in hand -> no reading", (p.readings() as Dictionary).is_empty())
	await _at_dock()
	await _space()
	_check("probe carried", carry.is_holding(p))
	await _at_terminal(0)
	cam._update_prompt()
	_check("terminal prompt: 'Measure A1 LS-FANS' ('%s')" % cam._prompt_label.text, cam._prompt_label.text.find("Measure A1") != -1)
	await _measure(0)
	await _measure(1)
	await _measure(2)
	var r: Dictionary = p.readings()
	_check("three readings stored (%s)" % str(r.keys()), r.size() == 3)
	var t1: float = float(r["1"]["temp"])
	var t0: float = float(r["0"]["temp"])
	_check("A2 (loose lug) reads HOT: %d C vs A1 %d C" % [roundi(t1), roundi(t0)], ts.is_abnormal(1, t1) and not ts.is_abnormal(0, t0))
	_check("guidance: re-torque A2", ts.order_next()["short"] == "TORQUE A2")
	# Re-torque refused on a terminal that was not measured hot.
	ts.on_part(&"n0")
	_check("re-torque refused on a normal terminal (A1 lug unchanged)", ts.loose == [false, true, false])
	ts.on_part(&"n1")
	_check("A2 re-torqued after being measured hot", ts.loose == [false, false, false])
	_check("A2's hot reading is now OUTDATED -> survey incomplete", ts.survey_status(p)["valid"] == 2)
	_check("guidance: re-measure A2", ts.order_next()["short"] == "MEASURE A2")
	# Docking now (incomplete) uploads nothing.
	await _at_dock()
	await _space()
	_check("docking mid-survey is allowed, nothing lost, order not done", ts.probe() == p and not ts.order_done() and (p.readings() as Dictionary).size() == 3)
	await _space()
	await _measure(1)
	_check("A2 re-measured: normal", not ts.is_abnormal(1, float(p.readings()["1"]["temp"])))
	await _at_dock()
	cam._update_prompt()
	_check("dock hint: 'upload thermal survey' ('%s')" % cam._prompt_label.text, cam._prompt_label.text.find("upload thermal survey") != -1)
	await _space()
	_check("docked: survey uploaded, order done", ts.order_done() and ts.probe() == p)
	for i in 5: await process_frame
	var o: Dictionary = dp.orders.filter(func(x): return x["type"] == "thermal")[0]
	_check("DayPlan closed the order automatically", o["status"] == "done")
	_check("exactly one probe", _count() == 1)


func _overload_reading() -> void:
	# An overloaded channel is a relevant abnormal reading too.
	dp.day_number += 1
	_open_order()
	ts.loose = [false, false, false]
	pw.setting = [4, 2, 4]
	pw.demand = [2, 2, 2]
	_check("panel overloaded", pw.is_overloaded())
	_check("overloaded channel A1 reads abnormal (%d C, expected %d)" % [roundi(ts.terminal_temp(0)), roundi(ts.expected_temp(0))], ts.is_abnormal(0, ts.terminal_temp(0)))
	_check("an un-overloaded channel stays normal", not ts.is_abnormal(1, ts.terminal_temp(1)))
	pw.setting = [2, 2, 2]
	_check("balanced: all terminals normal", not ts.is_abnormal(0, ts.terminal_temp(0)) and not ts.is_abnormal(2, ts.terminal_temp(2)))
	ts.loose = [false, false, true]


func _save_load() -> void:
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_thermal_probe.json"
	var p: Node3D = _probe()
	await _at_dock()
	await _space()
	await _measure(2)
	_check("mid-survey: probe in hand with 1 current reading", carry.is_holding(p) and ts.survey_status(p)["valid"] == 1)
	var r: Dictionary = sg.save_game()
	_check("save while carrying the probe: %s" % r["message"], r["ok"])
	var want: Dictionary = p.readings().duplicate(true)
	p.clear_readings()
	ts.loose = [true, true, true]
	sg.apply_state(sg.read_save()["data"])
	await process_frame
	p = _probe()
	_check("load: probe in the hand, its reading and the armed fault restored", carry.is_holding(p) and p.readings().has("2") and absf(float(p.readings()["2"]["temp"]) - float(want["2"]["temp"])) < 0.01 and ts.loose == [false, false, true] and _count() == 1)
	await _at_dock()
	await _space()
	sg.save_game()
	sg.apply_state(sg.read_save()["data"])
	await process_frame
	_check("load: probe docked", ts.probe() == _probe() and not carry.is_carrying() and _count() == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_thermal_probe.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_thermal_probe.json.bak"))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
