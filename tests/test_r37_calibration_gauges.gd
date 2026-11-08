extends SceneTree
## Round 37 Priority 2: ONE authoritative six-chamber sensor state on the
## physical calibration station; the focused view and the six physical
## dials are two views of it.
## Before: the view owned the values and reset them on every open; the
## station had one static decorative dial.
var _ok := true
var main: Node
var dp: Node
var st: Node
var view: Node
var focused: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	dp = main.get_node("DayPlan")
	st = main.get_node("Interactables/SensorCalibrationStation")
	view = main.get_node("Player/HUD/SensorCalibrationView")
	focused = main.get_node("FocusedInteractionState")
	_check("six physical chamber dials exist on the station", st.get_node_or_null("ChamberGauges") != null and st._dials.size() == 6)
	# A calibration TASK day.
	dp.workday = dp.Workday.CALIBRATION
	st._rearm_for_service(424242)
	var key: String = st.calibration_instance_key()
	_check("a calibration task instance key exists (%s)" % key, key != "")
	st.interact()
	await process_frame
	_check("focused view open", focused.is_active())
	_check("the view uses the STATION's own chamber state (shared objects)", is_same(view._reading, st.cal["reading"]) and is_same(view._setpoint, st.cal["setpoint"]))
	await _check_dials("open, initial drift")
	var drifted: Array = view.CHAMBERS.filter(func(ch): return absf(view._reading[ch] - view._TARGETS[ch]) > view._tolerance)
	_check("the day's drift: %d chamber(s) out of range on both" % drifted.size(), drifted.size() == st.service_required_count())
	# Partial calibration: move each chamber's regulator a little.
	for i in view.CHAMBERS.size():
		var ch: StringName = view.CHAMBERS[i]
		view._setpoint[ch] = float(view._setpoint[ch]) + (3.0 + i)
	view._damping = 5.0
	await create_timer(0.8).timeout
	await _check_dials("open, after partial adjustment")
	var snap := {}
	for ch in view.CHAMBERS:
		snap[ch] = float(st.cal["setpoint"][ch])
	focused.end()
	await process_frame
	_check("closing keeps the damping on the station (%.1f)" % float(st.cal["damping"]), absf(float(st.cal["damping"]) - 5.0) < 0.01)
	await create_timer(0.6).timeout
	await _check_dials("closed (the station keeps settling the same springs)")
	st.interact()
	await process_frame
	var same := true
	for ch in view.CHAMBERS:
		same = same and absf(float(view._setpoint[ch]) - float(snap[ch])) < 0.001
	_check("reopening shows the SAME regulator settings (no reset)", same and is_same(view._reading, st.cal["reading"]))
	await _check_dials("reopened")
	focused.end()
	await process_frame
	# Save / load mid-calibration.
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r37_calib.json"
	var r: Dictionary = sg.save_game()
	_check("save mid-calibration: %s" % r["message"], r["ok"])
	var want := {}
	for ch in view.CHAMBERS:
		want[ch] = [float(st.cal["setpoint"][ch]), float(st.cal["reading"][ch])]
	for ch in view.CHAMBERS:
		st.cal["setpoint"][ch] = 0.0
		st.cal["reading"][ch] = 0.0
	sg.apply_state(sg.read_save()["data"])
	var restored := true
	for ch in view.CHAMBERS:
		restored = restored and absf(float(st.cal["setpoint"][ch]) - want[ch][0]) < 0.01 and absf(float(st.cal["reading"][ch]) - want[ch][1]) < 0.05
	_check("load restores all six setpoints and readings", restored)
	await process_frame
	await _check_dials("after load")
	st.interact()
	await process_frame
	_check("after load the view adopts the restored state", is_same(view._reading, st.cal["reading"]))
	# Complete it for real (solve the coupled system).
	var solution: Dictionary = view._solve_equilibrium(view._coupling, view._TARGETS)
	for ch in view.CHAMBERS:
		view._setpoint[ch] = solution[ch]
	view._damping = view.CRITICAL_DAMPING
	await create_timer(5.0).timeout
	_check("calibration completes (l07 done)", view._done and dp.is_task_done(&"l07"))
	focused.end()
	await create_timer(0.5).timeout
	var all_ok := true
	for i in 6:
		all_ok = all_ok and absf(st.dial_value(i) - view._TARGETS[view.CHAMBERS[i]]) <= view._tolerance
	_check("completed: all six physical dials show in-range readings", all_ok)
	# A new recurring drift is a NEW instance.
	dp.day_number += 3
	dp.l07_status = dp.TaskStatus.PENDING
	st._rearm_for_service(77)
	st.interact()
	await process_frame
	var fresh: bool = view.CHAMBERS.any(func(ch): return absf(view._reading[ch] - view._TARGETS[ch]) > view._tolerance)
	_check("a new recurring calibration starts a NEW drift (different instance key)", fresh and st.cal["key"] == st.calibration_instance_key())
	focused.end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r37_calib.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r37_calib.json.bak"))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check_dials(tag: String) -> void:
	await process_frame
	var worst := 0.0
	for i in 6:
		var ch: StringName = view.CHAMBERS[i]
		worst = maxf(worst, absf(st.dial_value(i) - clampf(float(st.cal["reading"][ch]), -4.0, 104.0)))
	_check("%s: each of the six dials shows its chamber's reading (max error %.2f)" % [tag, worst], worst < 0.5)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
