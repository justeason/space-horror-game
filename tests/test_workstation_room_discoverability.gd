extends SceneTree
## Round 16 Priority 8 regression coverage: the Control Room
## workstation's room-info text for Communications, Life Support, and
## Engineering used to be stale/inaccurate the moment a free-standing
## task (M02, L07/L08/L02, E09) existed in that room -- Communications
## and Life Support both said "not used by any currently active task"
## even with real, playable stations physically present, and
## Engineering's own no-work-order fallback line never mentioned the
## E09 diagnostic bench at all. This is flavor/discoverability text
## only (read via DayPlan's existing done-flags) -- confirms the fix
## without claiming these free-standing tasks were injected into the
## Work Orders panel or Slice B chain, which they explicitly are not.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var day_plan := main.get_node("DayPlan")
	var screen := main.get_node("Interactables/WorkstationConsole/WorkstationScreen")

	_check("communications: mentions the signal console before m02 is done", screen._room_info_text(&"communications", "Communications").findn("Signal calibration") != -1)
	_check("communications: no longer claims 'not used by any task'", screen._room_info_text(&"communications", "Communications").findn("not used by any") == -1)

	_check("life_support: mentions available equipment before any L0x task is done", screen._room_info_text(&"life_support", "Life Support").findn("Available:") != -1)
	_check("life_support: no longer claims 'not used by any task'", screen._room_info_text(&"life_support", "Life Support").findn("not used by any") == -1)

	_check("engineering: mentions the E09 diagnostic bench when no Slice B work order is open", screen._room_info_text(&"engineering", "Engineering").findn("E09") != -1)

	day_plan.mark_done(&"m02")
	_check("communications: text changes once m02 is actually done", screen._room_info_text(&"communications", "Communications").findn("serviced") != -1)

	day_plan.mark_done(&"l07")
	day_plan.mark_done(&"l08")
	day_plan.mark_done(&"l02")
	_check("life_support: text reflects all three being serviced", screen._room_info_text(&"life_support", "Life Support").findn("All routine maintenance here is serviced") != -1)

	day_plan.mark_done(&"e09")
	_check("engineering: no longer offers E09 once it's done", screen._room_info_text(&"engineering", "Engineering").findn("Diagnostic bench available") == -1)

	main.queue_free()
	await process_frame

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
