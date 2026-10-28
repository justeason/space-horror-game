extends SceneTree
var _ok := true
func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var sleep_state := main.get_node("SleepState")
	var bunk := main.get_node("Interactables/Bunk")
	var free_body := main.get_node("FreeMoveBody")
	var dp := main.get_node("DayPlan")
	var eyes := player.get_node("HUD/EyesOverlay")
	var wristwatch := player.get_node("HUD/WristwatchLabel")
	var look := player.get_node("LookPivot")

	var near_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(near_pos)
	player.global_position = near_pos
	for i in 3: await process_frame
	bunk.interact()
	await create_timer(1.6).timeout
	_check("sitting", sleep_state.is_sitting())

	# Leave some task state dirty to verify the reset actually fires.
	dp.mark_done(&"c01")
	dp.assign_daily_task()
	_check("precondition: c01 done before sleep", dp.is_task_done(&"c01"))

	_check("eyes overlay starts transparent", eyes.color.a < 0.01)
	sleep_state.begin_sleep()
	await create_timer(0.1).timeout
	_check("sleeping state entered", sleep_state.is_sleeping())
	_check("mouse-look locked while asleep", not look.input_enabled)
	_check("movement suppressed while asleep", not free_body.active)

	await create_timer(0.35).timeout # past eyes_close_duration
	_check("eyes overlay opaque (closed) mid-sequence", eyes.color.a > 0.9)

	# Wait until just after the dark hold -- DayPlan should have reset
	# invisibly while the screen is fully dark.
	await create_timer(0.95).timeout
	_check("day_plan reset while eyes were closed", not dp.is_task_done(&"c01"))
	_check("assignment cleared by the reset", dp.assignment_task_id == &"")

	await create_timer(0.45).timeout # past eyes_open_duration
	_check("eyes overlay transparent again (open)", eyes.color.a < 0.05)
	_check("back to SITTING after waking (not auto-standing)", sleep_state.is_sitting() and not sleep_state.is_sleeping())
	_check("mouse-look restored after waking", look.input_enabled)
	_check("wristwatch glance shown automatically", wristwatch.visible)

	await create_timer(2.3).timeout
	_check("wristwatch glance disappears on its own", not wristwatch.visible)

	# Getting up afterward still works normally (reuses existing, tested
	# get-up sequence -- nothing new built for standing up).
	sleep_state.end_sitting()
	await create_timer(2.6).timeout
	_check("get-up after waking still works", not sleep_state.is_sitting())
	_check("movement restored after standing", free_body.active)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
