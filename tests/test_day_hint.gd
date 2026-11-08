extends SceneTree
## Round 33 (user request): when a new day starts, the Control Room
## workstation and the bunk laptop both show which day it is and what
## today's shift is, from the same DayPlan.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var dp: Node = main.get_node("DayPlan")
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var welcome: Label = screen.get_node("Control/VBox/Content/Home/Welcome")
	var title: Label = screen.get_node("Control/VBox/TitleBar/TitleLabel")
	var laptop: Node = main.find_children("SessionLogScreen", "", true, false)[0]
	var lt: Label = laptop.get_node("Control/VBox/TitleLabel")
	var ls: Label = laptop.get_node("Control/VBox/SubtitleLabel")
	var lstat: Label = laptop.get_node("Control/VBox/SampleLabel")
	screen.show_section(screen.Section.HOME)
	_check("day 1: workstation title shows the day ('%s')" % title.text, title.text.begins_with("DAY 1 · "))
	_check("day 1: Home flags the new shift ('%s')" % welcome.text.replace("\n", " / "), welcome.text.find("NEW SHIFT — TODAY IS DAY 1") != -1)
	_check("day 1: laptop shows the day ('%s')" % lt.text, lt.text == "SESSION LOG — DAY 1")
	_check("laptop no longer shows placeholder text", ls.text.find("prototype") == -1 and lstat.text.find("SAMPLE") == -1)

	dp.reset_for_new_day()
	await process_frame
	_check("day 2: workstation updates on the new day ('%s')" % title.text, title.text.begins_with("DAY 2 · ") and welcome.text.find("TODAY IS DAY 2") != -1)
	_check("day 2: Home names today's scheduled work", welcome.text.find("Life Support Filter Service") != -1)
	_check("day 2: laptop updates too ('%s' / '%s')" % [lt.text, lstat.text], lt.text == "SESSION LOG — DAY 2" and lstat.text.find("Filter Service") != -1 and ls.text.begins_with("New shift"))

	screen.show_section(screen.Section.OVERVIEW)
	screen.run_action()   # C01 morning check-in
	screen.show_section(screen.Section.HOME)
	await process_frame
	_check("after check-in: no longer a 'new shift' ('%s')" % welcome.text.replace("\n", " / "), welcome.text.find("NEW SHIFT") == -1 and welcome.text.find("TODAY: DAY 2") != -1)
	_check("after check-in: laptop says shift in progress", ls.text == "Shift in progress.")
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
