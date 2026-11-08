extends SceneTree
## Round 33: the real UI path -- [R] save at the workstation, [L] load
## reloads the whole scene and restores the save before the player resumes;
## [N] new game (press twice) starts fresh WITHOUT touching the save.
var _ok := true
const PATH := "user://test_r33_reload.json"

func _init() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	change_scene_to_file("res://scenes/main.tscn")
	for i in 8: await process_frame
	var main: Node = current_scene
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = PATH
	var dp: Node = main.get_node("DayPlan")
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	dp.reset_for_new_day()
	dp.reset_for_new_day()
	screen.show_section(screen.Section.SAVE_LOAD)
	var notice: Label = screen.get_node("Control/VBox/Content/SaveLoad/Notice")
	_check("Save/Load screen shows the current day and no save yet", notice.text.find("CURRENT SHIFT: DAY 3") != -1 and notice.text.find("SAVED GAME: none") != -1)
	screen.run_action()   # [R] save
	_check("[R] saves and reports it ('%s')" % notice.text.get_slice("\n", notice.text.get_slice_count("\n") - 1), FileAccess.file_exists(PATH) and notice.text.find("Progress saved — Day 3") != -1)
	dp.reset_for_new_day()   # progress past the save (day 4)
	screen.save_load_key(KEY_L)
	for i in 12: await process_frame
	var m2: Node = current_scene
	_check("[L] reloaded a fresh scene", m2 != main and is_instance_valid(m2))
	m2.get_node("SaveGame").save_path = PATH
	_check("...and restored the saved day 3 (not day 4, not day 1)", m2.get_node("DayPlan").day_number == 3)
	_check("...with feedback ('%s')" % m2.get_node("SaveGame").last_message, m2.get_node("SaveGame").last_message.find("Progress loaded — Day 3") != -1)
	var s2: Node = m2.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	s2.show_section(s2.Section.SAVE_LOAD)
	s2.save_load_key(KEY_N)
	_check("[N] once only arms the new game", current_scene == m2 and s2.get_node("Control/VBox/Content/SaveLoad/Notice").text.find("Press [N] again") != -1)
	s2.save_load_key(KEY_N)
	for i in 10: await process_frame
	var m3: Node = current_scene
	_check("[N] twice starts a new game on day 1", m3 != m2 and m3.get_node("DayPlan").day_number == 1)
	_check("...and the save file is untouched (still day 3)", FileAccess.get_file_as_string(PATH).find("\"day\": 3") != -1)
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
