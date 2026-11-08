extends SceneTree
## Round 34 Priority 1 (release blocker): LOAD through the REAL player
## input path -- seated at the Control Room workstation, keys 5 (Save/Load
## tab), R (save) and L (load) pushed through the viewport exactly like a
## keyboard. Round 33 crashed here: the scene reload happened INSIDE the
## workstation's _unhandled_input, which then touched a node already out of
## the tree (get_viewport() == null) while the old scene was torn down.
## Also: repeated loads in one session, load with no save / corrupt save
## (the running game must stay intact), and no SCRIPT ERRORs (the runner
## fails any test that prints one).
var _ok := true
const PATH := "user://test_r34_click_load.json"

func _init() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10: await process_frame
	var main: Node = current_scene
	_use_test_path(main)
	var dp: Node = main.get_node("DayPlan")
	var ws: Node = main.get_node("WorkstationState")

	# ---- No save yet: [L] must not disturb the running game. ----
	await _sit(main)
	await _key(KEY_5)
	await _key(KEY_L)
	for i in 6: await process_frame
	_check("[L] with no save: same running scene, still seated, clear message", current_scene == main and ws.is_in_use() and main.get_node("SaveGame").last_message.find("No saved game") != -1)

	# ---- Save, change the world, load through the keyboard. ----
	dp.reset_for_new_day()
	dp.reset_for_new_day()   # day 3
	await _key(KEY_R)
	_check("[R] saved day 3", FileAccess.file_exists(PATH) and FileAccess.get_file_as_string(PATH).find("\"day\": 3") != -1)
	dp.reset_for_new_day()   # day 4 (unsaved progress)
	for round in 3:
		await _key(KEY_L)
		for i in 15: await process_frame
		var m2: Node = current_scene
		_check("load #%d via the real [L] key: a NEW scene is running" % (round + 1), m2 != main and is_instance_valid(m2) and m2.is_inside_tree())
		_check("load #%d: the saved day 3 is restored" % (round + 1), m2.get_node("DayPlan").day_number == 3)
		_check("load #%d: the old scene is gone (no leftover station)" % (round + 1), not is_instance_valid(main) or not main.is_inside_tree())
		_check("load #%d: player is free to move (not stuck seated)" % (round + 1), not m2.get_node("WorkstationState").is_in_use() and m2.get_node("Player/LookPivot").input_enabled)
		main = m2
		_use_test_path(main)
		await _sit(main)
		await _key(KEY_5)

	# ---- Corrupt save: refused, the running game stays. ----
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var b := FileAccess.open(PATH + ".bak", FileAccess.WRITE)
	b.store_string("garbage")
	b.close()
	var before: Node = current_scene
	await _key(KEY_L)
	for i in 8: await process_frame
	_check("corrupt save: load refused, running game untouched", current_scene == before and before.get_node("DayPlan").day_number == 3)
	_check("...with an error message ('%s')" % before.get_node("SaveGame").last_message, before.get_node("SaveGame").last_message.begins_with("Load failed"))
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _use_test_path(m: Node) -> void:
	m.get_node("SaveGame").save_path = PATH


func _sit(m: Node) -> void:
	var ws: Node = m.get_node("WorkstationState")
	if ws.is_in_use():
		return
	ws.begin_use()
	var t0 := Time.get_ticks_msec()
	while not ws.is_in_use() and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	for i in 3: await process_frame


func _key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	get_root().push_input(e)
	await process_frame
	var u := InputEventKey.new()
	u.keycode = k
	u.physical_keycode = k
	u.pressed = false
	get_root().push_input(u)
	await process_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
