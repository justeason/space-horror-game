extends SceneTree
## Round 37 Priorities 4-6, 10, 12, 13: EMERGENCY severity, countdown and
## warning feedback -- all from the real equipment state, one status model.
const GS = preload("res://scripts/station/game_settings.gd")
var _ok := true
var main: Node
var dp: Node
var pw: Node
var br: Node
var stn: Node
var ai: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	dp = main.get_node("DayPlan")
	pw = main.get_node("Equipment/PowerDistribution")
	br = main.get_node("Equipment/BreakerPanel")
	stn = main.get_node("StationStatus")
	ai = main.get_node("StationAI")
	GS.set_value("steady_warnings", false)
	_classification()
	_routine_power_never_overloaded()
	_plan_frequency()
	await _emergency_flow()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _classification() -> void:
	var vent: Node = main.get_node("Equipment/VentGrille")
	vent.order_rearm(1)
	_check("dirty vent = ROUTINE or WARNING by airflow (%d, eff %.2f)" % [vent.order_severity(), vent.efficiency()], vent.order_severity() == (2 if vent.efficiency() < 0.8 else 1))
	vent.dirt = [0.0, 0.0, 0.0, 0.0]
	vent.airflow_checked = true
	_check("clean vent = NORMAL", vent.order_severity() == 0)
	br.trip(1, "surge")
	_check("tripped breaker (room dark) = WARNING", br.order_severity() == 2)
	_check("...and the map shows Engineering WARNING without any order", stn.room_severity(&"engineering") == 2)
	br.on_part(&"b1")
	_check("breaker reset clears the room", stn.room_severity(&"engineering") == 0)
	pw.setting = [2, 2, 2]
	pw.demand = [2, 2, 2]
	_check("balanced bus = NORMAL", pw.order_severity() == 0 and pw.emergency_info().is_empty())
	pw.setting = [4, 2, 2]
	_check("overloaded bus = EMERGENCY with a real countdown (%.0f s)" % float(pw.emergency_info().get("seconds", -1)), pw.order_severity() == 3 and absf(float(pw.emergency_info()["seconds"]) - pw.OVERLOAD_TRIP_S) < 1.0)
	pw.setting = [2, 2, 2]
	pw._overload_s = 0.0


func _routine_power_never_overloaded() -> void:
	var bad := 0
	for seed in range(1, 200):
		pw.order_rearm(seed * 104729)
		if pw.is_overloaded():
			bad += 1
		if pw.balanced():
			bad += 1
	_check("199 routine balancing orders: none starts overloaded (nor already balanced) (%d bad)" % bad, bad == 0)
	pw.setting = [2, 2, 2]
	pw.demand = [2, 2, 2]


func _plan_frequency() -> void:
	var n := 0
	var early := 0
	var times_ok := true
	var saved: int = dp.day_number
	dp.proficiency["electrical"] = 1   # Round 38: emergencies need electrical experience
	for d in range(1, 81):
		dp.day_number = d
		dp.plan_emergency()
		if not dp.emergency_plan.is_empty():
			if d < 5:
				early += 1
			n += 1
			times_ok = times_ok and float(dp.emergency_plan["at_s"]) >= 120.0 and float(dp.emergency_plan["at_s"]) <= 301.0
	dp.day_number = saved
	dp.emergency_plan = {}
	_check("emergencies are uncommon: %d of 80 days (none before day 5: %d)" % [n, early], n >= 8 and n <= 32 and early == 0)
	_check("planned 2:00-5:00 into the shift, deterministic", times_ok)


func _emergency_flow() -> void:
	ai.clear_queue()
	await create_timer(0.7).timeout
	dp.fire_emergency("overload", 1)
	await process_frame
	var e: Dictionary = stn.emergency()
	_check("the surge creates a REAL overload emergency (%s)" % stn.emergency_line(), not e.is_empty() and pw.is_overloaded() and StringName(e["room"]) == &"engineering")
	_check("an emergency balancing order is opened (DayPlan)", dp.orders.any(func(o): return o["status"] == "open" and o["type"] == "power" and o.get("emergency", false)))
	_check("map: Engineering is EMERGENCY (red)", stn.room_severity(&"engineering") == 3)
	await process_frame
	_check("top-screen banner shows it ('%s')" % stn.banner_text(), stn.banner_text().find("POWER OVERLOAD") != -1 and stn.banner_text().find("ENGINEERING") != -1)
	var ww: Node = main.get_node("Player/Wristwatch")
	ww._refresh_text()
	var watch_txt: String = ww._watch_rig._watch_face_text.text
	_check("wristwatch shows the countdown ('%s')" % watch_txt.replace("\n", " / "), watch_txt.find("OVERLOAD") != -1 and watch_txt.find(":") != -1)
	await create_timer(0.6).timeout
	_check("red beacons on in Engineering and its corridor, off elsewhere", stn.beacon_energy(&"engineering") > 0.0 and stn.beacon_energy(&"main_junction") > 0.0 and stn.beacon_energy(&"life_support") == 0.0 and stn.beacon_energy(&"airlock") == 0.0)
	var e1: float = stn.beacon_energy(&"engineering")
	await create_timer(0.5).timeout
	var e2: float = stn.beacon_energy(&"engineering")
	_check("slow pulse (energy changes %.2f -> %.2f, no strobe)" % [e1, e2], absf(e1 - e2) > 0.01)
	GS.set_value("steady_warnings", true)
	await create_timer(0.2).timeout
	var s1: float = stn.beacon_energy(&"engineering")
	await create_timer(0.4).timeout
	_check("'steady warning lights' setting: constant illumination", absf(stn.beacon_energy(&"engineering") - s1) < 0.0001 and s1 > 0.0)
	GS.set_value("steady_warnings", false)
	_check("alert tone at onset (positional, room speaker)", stn.alert_log.any(func(a): return a["kind"] == "onset" and a["room"] == "engineering"))
	_check("assistant announces the emergency (safety line)", await _wait_ai("emerg_overload"))
	# Countdown is the real timer: decreases in play, stops while paused.
	var s_a: float = float(stn.emergency()["seconds"])
	await create_timer(1.0).timeout
	var s_b: float = float(stn.emergency()["seconds"])
	_check("countdown runs in play (%.1f -> %.1f)" % [s_a, s_b], s_a - s_b > 0.7)
	paused = true
	await create_timer(1.0, true).timeout
	var s_c: float = float(stn.emergency()["seconds"])
	paused = false
	_check("countdown frozen while paused (%.2f -> %.2f)" % [s_b, s_c], absf(s_c - s_b) < 0.1)
	# Save / load: same remaining time, no restart, no duplicate onset.
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r37_emergency.json"
	var left: float = float(stn.emergency()["seconds"])
	sg.save_game()
	pw._overload_s = 0.0
	sg.apply_state(sg.read_save()["data"])
	_check("load keeps the remaining time (%.1f vs %.1f)" % [float(stn.emergency()["seconds"]), left], absf(float(stn.emergency()["seconds"]) - left) < 0.6)
	# Escalation (30 s) then the consequence at zero.
	pw._overload_s = pw.OVERLOAD_TRIP_S - 29.0
	_check("30 s escalation announced", await _wait_ai("emerg_30"))
	pw._overload_s = pw.OVERLOAD_TRIP_S + 0.1
	await create_timer(0.4).timeout
	_check("at zero the REAL consequence: B-03 trips (Engineering dark)", not br.on[2] and main.get_node("Lights/Light_Engineering").light_energy == 0.0)
	_check("the countdown disappears once the consequence happened", stn.emergency().is_empty() and stn.banner_text() == "")
	_check("Engineering stays a WARNING (breaker to reset); beacons off", stn.room_severity(&"engineering") >= 2 and stn.beacon_energy(&"engineering") == 0.0)
	_check("assistant: 'Breaker B-03 tripped. Emergency lighting active...'", await _wait_ai("overload_trip"))
	# Recovery: balance, then reset.
	pw.setting = pw.demand.duplicate()
	br.on_part(&"b2")
	_check("recovery: balanced bus + reset breaker restores Engineering", br.on[2] and main.get_node("Lights/Light_Engineering").light_energy > 0.0)
	await create_timer(4.6).timeout
	_check("...and the emergency order closes automatically", dp.orders.filter(func(o): return o["type"] == "power" and o.get("emergency", false))[0]["status"] == "done")
	_check("no stale warnings: Engineering back to NORMAL", stn.room_severity(&"engineering") == 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r37_emergency.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r37_emergency.json.bak"))


func _wait_ai(key: String, timeout: float = 10.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		if ai.history.any(func(h): return h["key"] == key):
			return true
		await process_frame
	return false


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
