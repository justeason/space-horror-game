extends SceneTree
## Round 49: HYDROPONICS (B-06) and MEDICAL / EXERCISE (B-07).
##   botany   a failed GL-6 module dims its bank (real lights, real Bus B
##            load), PAR finds it, a spare module from the cabinet fixes
##            it; nutrient dosing moves the real EC (a wrong dose moves it
##            the wrong way, recoverably); a blocked emitter dries a tray
##            and the plants respond (health falls, then recovers); a
##            moisture SENSOR fault closes as "sensor_fault"; tray cleaning;
##            the personal basil is untouched by all of it.
##   medical  the health monitor reads the REAL condition (underfed ->
##            glucose flag, tired -> heart rate up); the dosimeter matches
##            the station's own dose estimate once the reader passes its
##            reference check; supply inspection flags a short bin
##            (deferred: resupply); kit inventory restored from the cabinet;
##            an exercise session is a real seated interaction (pedalling
##            moves the crank and the feet), logged for the day.
const L = preload("res://scripts/deck_b/deck_b_layout.gd")
var _ok := true
var main: Node
var dp: Node
var s: Node
var carry: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("StationAI").set_enabled(false)
	dp = main.get_node("DayPlan")
	s = main.get_node("DeckB/DeckBSystems")
	carry = main.get_node("Player/CarrySystem")
	main.get_node("DayPlan/Clearance").load_dict({"level": 3})
	main.get_node("DayPlan/Clearance").dev_set_deck_b(4)
	await _botany()
	await _medical()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _take(it: Node3D) -> Node3D:
	it.interact()
	if carry.is_reaching():
		carry.complete_grasp()
	return carry._carried_item


func _order(t: StringName) -> Dictionary:
	for o in dp.orders:
		if StringName(o["type"]) == t:
			return o
	return {}


func _wait_closed(t: StringName, max_s: float = 3.0) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
		await process_frame
		if String(_order(t).get("status", "")) == "done":
			break
	return _order(t)


func _botany() -> void:
	var b: Node = main.get_node("DeckB/Rooms/Hydroponics")
	var hy: Dictionary = s.hydro
	var q: Node = main.get_node("Equipment/QuartersLife")
	var basil_before: String = JSON.stringify([q.get("basil_dead"), q.get("basil_dead_day"), q.get("basil_return_day")])
	# ---- Grow lights.
	dp.raise_order(&"b06_lights", "test")
	b.lt_seed = "module"
	b.lt_bank = 1
	hy["light_ok"] = [true, false, true]
	hy["light"] = [1.0, 1.0, 1.0]
	var load_bad: float = s.load_kw(2)
	b._refresh()
	_check("a failed GL-6 module really dims its bank (output %.2f, light energy %.2f)" % [s.light_output(1), (b._bank_lights[1] as SpotLight3D).light_energy], s.light_output(1) < 0.5 and (b._bank_lights[1] as SpotLight3D).light_energy < 1.0)
	for i in 3:
		b.on_part(StringName("par%d" % i))
	var mod: Node3D = _take(b.find_child("BotanyCabinet", true, false).items()[0])
	carry._carried_item = null
	carry._carried_item = mod
	b.on_part(&"bank1")
	carry._carried_item = null
	b._refresh()
	_check("module replaced: bank B full output, Bus B B3 load %.2f -> %.2f kW" % [load_bad, s.load_kw(2)], s.light_output(1) > 0.95 and s.load_kw(2) > load_bad)
	var lo: Dictionary = await _wait_closed(&"b06_lights")
	_check("grow-light order -> %s" % lo.get("outcome", "?"), lo.get("status", "") == "done")
	# ---- Nutrients.
	dp.raise_order(&"b06_nutrient", "test")
	hy["ec"] = 0.85
	hy["ph"] = 6.0
	b.on_part(&"sample")
	b.on_part(&"dose1")
	_check("a wrong adjustment (water) moves EC the wrong way, recoverably (%.2f)" % float(hy["ec"]), float(hy["ec"]) < 0.85 and float(hy["ec"]) > 0.0)
	for i in 5:
		b.on_part(&"dose0")
	b.on_part(&"sample")
	var no: Dictionary = await _wait_closed(&"b06_nutrient")
	_check("dosed to EC %.2f -> %s" % [float(hy["ec"]), no.get("outcome", "?")], no.get("status", "") == "done")
	# ---- Irrigation: blocked emitter -> plants respond -> fixed.
	dp.raise_order(&"b06_irrigation", "test")
	b.irr_tray = 2
	b.irr_seed = "blocked"
	hy["line"] = ["", "", "blocked"]
	hy["sensor_bias"] = [0.0, 0.0, 0.0]
	hy["trays"][2]["moist"] = 0.3
	var h0: float = float(hy["trays"][2]["health"])
	for i in 2000:
		s._step_hydro(0.05)
	_check("a blocked emitter: tray C stays dry and its plants decline (%.2f -> %.2f)" % [h0, float(hy["trays"][2]["health"])], float(hy["trays"][2]["health"]) < h0 - 0.1)
	for i in 3:
		b.on_part(&"emitter2")
	for i in 400:
		s._step_hydro(0.05)
	var io: Dictionary = await _wait_closed(&"b06_irrigation", 8.0)
	_check("emitter cleared: moisture %.2f, order -> %s" % [s.moisture_reading(2), io.get("outcome", "?")], io.get("status", "") == "done" and io.get("outcome", "") == "repaired")
	# ---- Sensor fault outcome.
	io["status"] = "cancelled"
	b.outcome.erase(&"b06_irrigation")
	dp.raise_order(&"b06_irrigation", "test2")
	b.irr_tray = 0
	b.irr_seed = "sensor"
	b.irr_fixed = false
	b._recal_armed = false
	hy["line"] = ["", "", ""]
	hy["sensor_bias"] = [-0.32, 0.0, 0.0]
	hy["trays"][0]["moist"] = 0.62
	b.on_part(&"moist0")
	b.on_part(&"moist0")
	var so: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await process_frame
		for o in dp.orders:
			if StringName(o["type"]) == &"b06_irrigation" and o["status"] == "done":
				so = o
		if not so.is_empty():
			break
	_check("moisture reads low but the tray is damp: recalibrated -> '%s'" % so.get("outcome", "?"), so.get("outcome", "") == "sensor_fault")
	# ---- Cleaning.
	dp.raise_order(&"b06_clean", "test")
	b.clean_tray = 1
	b.algae[1] = 3
	b.on_part(&"cover1")
	for k in 3:
		b.on_part(StringName("algae1_%d" % k))
	b.on_part(&"cover1")
	var co: Dictionary = await _wait_closed(&"b06_clean")
	_check("tray B cover cleaned -> %s (clean %.1f)" % [co.get("outcome", "?"), float(hy["trays"][1]["clean"])], co.get("status", "") == "done" and float(hy["trays"][1]["clean"]) > 0.99)
	_check("the personal basil is untouched by hydroponics work", JSON.stringify([q.get("basil_dead"), q.get("basil_dead_day"), q.get("basil_return_day")]) == basil_before)


func _medical() -> void:
	var m: Node = main.get_node("DeckB/Rooms/MedicalBay")
	# ---- Health check from the real condition.
	dp.raise_order(&"b07_health", "test")
	dp.underfed = false
	var v_ok: Dictionary = s.vitals()
	dp.underfed = true
	var v_bad: Dictionary = s.vitals()
	_check("vitals follow the real state: underfed -> glucose %.1f, HR %d -> %d" % [float(v_bad["glucose"]), int(v_ok["hr"]), int(v_bad["hr"])], float(v_bad["glucose"]) < 4.0 and float(v_bad["hr"]) > float(v_ok["hr"]) and v_bad["flags"].has("GLUCOSE LOW"))
	dp.underfed = false
	m.on_part(&"start_meas")
	_check("measurement refused without strap and sensor clip", m.measuring < 0.0)
	m.on_part(&"strap")
	m.on_part(&"clip")
	m.on_part(&"start_meas")
	await create_timer(6.3).timeout
	m.on_part(&"record_meas")
	var ho: Dictionary = await _wait_closed(&"b07_health")
	_check("health check recorded (HR %d) -> %s" % [int(m.vitals.get("hr", 0)), ho.get("outcome", "?")], ho.get("status", "") == "done")
	# ---- Dosimeter.
	dp.raise_order(&"b07_dosimeter", "test")
	s.med["reader_gain"] = 0.9
	var holder: Node = m.find_child("BadgeHolder", true, false)
	var badge: Node3D = _take(holder.items()[0])
	carry._carried_item = null
	m.stow_part(&"reader_slot", badge)
	m.on_part(&"cal_check")
	m.on_part(&"dose_read")
	_check("dose read refused while the reader fails its reference check", m.dose_read < 0.0)
	m.on_part(&"cal_adj")
	m.on_part(&"cal_check")
	m.on_part(&"dose_read")
	var expected: float = s.expected_dose_usv(maxi(dp.day_number - m.last_read_day, 1))
	_check("badge dose %.0f µSv matches the station estimate %.0f µSv" % [m.dose_read, expected], absf(m.dose_read - expected) < 1.0)
	m.on_part(&"dose_log")
	m.on_part(&"reader_slot")
	if carry.is_reaching():
		carry.complete_grasp()
	var bdg: Node3D = carry._carried_item
	carry._carried_item = null
	m.part_stow(&"rack_BadgeHolder", bdg)
	var dco: Dictionary = await _wait_closed(&"b07_dosimeter")
	_check("badge back in its holder -> %s" % dco.get("outcome", "?"), dco.get("status", "") == "done")
	# ---- Supplies.
	dp.raise_order(&"b07_supplies", "test")
	m.on_part(&"cab_door")
	for k in 3:
		m.on_part(StringName("bin%d" % k))
	m.on_part(&"cab_door")
	var spo: Dictionary = await _wait_closed(&"b07_supplies")
	_check("short / expired bin flagged -> %s (resupply)" % spo.get("outcome", "?"), spo.get("status", "") == "done" and spo.get("outcome", "") == "deferred")
	# ---- Kit.
	dp.raise_order(&"b07_kit", "test")
	m.kit_tag_ok = false
	m.kit_items = [true, false, true, true, true]
	m.kit_sealed = false
	m.on_part(&"kit_tag")
	m.on_part(&"kit")
	m.on_part(&"cab_door")
	m.on_part(&"bin2")
	m.on_part(&"kit")
	m.on_part(&"kit")
	m.on_part(&"cab_door")
	var ko: Dictionary = await _wait_closed(&"b07_kit")
	_check("first-aid kit restored from the cabinet and resealed -> %s" % ko.get("outcome", "?"), ko.get("status", "") == "done" and ko.get("outcome", "") == "repaired")
	# ---- Exercise.
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-9.75, L.EYE_Y, 12.55))
	for i in 3: await physics_frame
	_check("strapped into the ergometer (seated, free walking off)", m.begin_exercise() and not main.get_node("FreeMoveBody").active)
	var crank0: float = m.ex_crank
	for i in 70:
		m._pedal(0.3)
		await process_frame
	_check("pedalling turns the crank and the feet follow it (pose %.2f)" % main.get_node("Player/PlayerBody").climb_pose_weight(), m.ex_crank > crank0 + 5.0 and main.get_node("Player/PlayerBody").climb_pose_weight() > 0.3)
	m.end_exercise()
	_check("session complete and logged for today; walking restored", s.med["exercise_days"].has(dp.day_number) and main.get_node("FreeMoveBody").active)
	_check("exercise lowers the measured heart rate slightly", float(s.vitals()["hr"]) < float(v_ok["hr"]))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
