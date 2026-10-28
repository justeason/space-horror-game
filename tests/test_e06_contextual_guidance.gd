extends SceneTree
## Coverage for this milestone's Phase D: contextual discoverability for
## E06 Tighten Loose Connection (scripts/interactables/loose_connection.gd)
## -- player feedback was "after opening the cabinet, no further
## instruction is given while E06 is pending," and investigation found
## the actual loose_connection.gd fitting (a separate, small object from
## the electrical cabinet) previously had NO get_interact_prompt() at
## all and no visual cue distinguishing it as the outstanding task.
## Both are state-derived from DayPlan directly -- no second task flag.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var day_plan := main.get_node("DayPlan")
	var loose := main.get_node("Interactables/LooseConnection")
	var light: CSGBox3D = loose.get_node("AttentionLight")

	# ============================================================
	# 1. Before C01/assignment: no cue, no spoiler -- the fitting is
	# just an ordinary (if currently unprompted-for) prop.
	# ============================================================
	_check("attention light off before any assignment exists", not light.visible)
	_check("a prompt now exists at all (previously missing entirely)", loose.get_interact_prompt() != "")

	# ============================================================
	# 2. Once E06 is actually assigned (C01 -> assign_daily_task()),
	# the light turns on -- a real, state-derived cue, not a permanent
	# quest marker.
	# ============================================================
	day_plan.mark_done(&"c01")
	day_plan.assign_daily_task()
	await process_frame
	_check("E06 actually assigned", day_plan.assignment_task_id == &"e06")
	_check("attention light turns on once E06 is assigned and outstanding", light.visible)
	_check("prompt shows real progress (0/6)", loose.get_interact_prompt().find("0/6") != -1)

	# ============================================================
	# 3. The cue updates immediately as real progress is made, and
	# disappears the instant the task is actually done -- not a fixed
	# timer, not a separate completion flag.
	# ============================================================
	loose.interact()
	loose.interact()
	await process_frame
	_check("prompt reflects real click progress (2/6)", loose.get_interact_prompt().find("2/6") != -1)
	_check("light still on -- not done yet", light.visible)

	for i in 4: loose.interact() # finishes it (6 total)
	await process_frame
	_check("E06 actually marked done in DayPlan", day_plan.is_task_done(&"e06"))
	_check("attention light turns off the instant the task completes", not light.visible)
	_check("prompt reflects the completed state", loose.get_interact_prompt().findn("Secure") != -1)

	# ============================================================
	# 4. The cue never comes back once done, even if somehow re-queried
	# repeatedly (idempotent, no flicker).
	# ============================================================
	await process_frame
	_check("cue stays off on a later frame too", not light.visible)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
