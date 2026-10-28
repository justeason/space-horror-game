extends SceneTree
## Milestone coverage for the press-and-hold wristwatch
## (scripts/player/wristwatch_view.gd + the separate, camera-child
## first_person_watch_rig.gd): raises while C is held -- as a
## dedicated first-person-only visual rig attached to Camera3D, NOT by
## moving PlayerBody/StandingPose's own arm (Round 11's architecture
## split -- see first_person_watch_rig.gd's class doc comment for why
## the PREVIOUS "move the world body's own arm" approach was also the
## root cause of a body-disappearing regression) -- hides the instant
## it's released, reads the same authoritative DayPlan summary the
## workstation's Work Orders section uses, and stays completely inert
## during every exclusive state this task explicitly called out
## (sitting on the bed, seated at the workstation).
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var player := main.get_node("Player")
	var watch := player.get_node("Wristwatch")
	var body := player.get_node("PlayerBody")
	var dp := main.get_node("DayPlan")
	var rig := player.get_node("LookPivot/PitchPivot/Camera3D/FirstPersonWatchRig")
	var watch_face: Label3D = rig.get_node("ArmGroup/WatchAssembly/WatchFaceText")

	_check("not raised at start", not watch.is_raised())
	_check("not raised at start (rig)", not rig.is_raised())
	_check("rig hidden at start", not rig.visible)

	# ============================================================
	# 1. Holding C raises it (physically -- the rig becomes visible and
	# its arm group leaves its lowered-offscreen position); releasing
	# dismisses it and returns the rig to hidden.
	# ============================================================
	await _press(KEY_C)
	await create_timer(0.4).timeout
	_check("raised while C is held", watch.is_raised())
	_check("rig visible while held", rig.visible)
	_check("shows a concise check-in prompt before C01 (Round 12: one glanceable status, not a paragraph)", watch_face.text.findn("CHECK IN") != -1 and watch_face.text.findn("CONTROL ROOM") != -1)
	_check("body still visible while watch is raised (the actual Round 11 regression)", body.visible)

	# ============================================================
	# 1b. Round 12 Workstream A5 regression: the Label3D's own physical
	# footprint (width/line-height in METERS, via pixel_size -- not
	# just "a string exists") must actually fit inside the recessed
	# face plate's real diameter. The Round 10/11 version of this watch
	# face was 0.286m of text block against a 0.062m face -- a concrete,
	# measurable overflow, not a subjective complaint -- so this checks
	# the actual geometry that bug lived in, not merely that SOME text
	# is present.
	# ============================================================
	var face_plate: CSGCylinder3D = rig.get_node("ArmGroup/WatchAssembly/WatchCase/FacePlate")
	var face_diameter: float = face_plate.radius * 2.0
	var text_width_m: float = watch_face.width * watch_face.pixel_size
	_check(
		"watch face text block width fits inside the physical face diameter (text=%.3fm face=%.3fm)" % [text_width_m, face_diameter],
		text_width_m <= face_diameter
	)
	var line_count: int = watch_face.text.split("\n").size()
	var text_height_m: float = line_count * watch_face.font_size * watch_face.pixel_size * 1.2 # ~1.2x line-spacing factor
	_check(
		"watch face text block height (for its current %d-line content) fits inside the physical face diameter (text=%.3fm face=%.3fm)" % [line_count, text_height_m, face_diameter],
		text_height_m <= face_diameter
	)

	await _release(KEY_C)
	await create_timer(0.4).timeout
	_check("dismissed immediately on release", not watch.is_raised())
	_check("rig hidden after release", not rig.visible)

	# ============================================================
	# 2. Content matches DayPlan.get_work_order_lines() -- single
	# source of truth, not a separately formatted copy.
	# ============================================================
	dp.mark_done(&"c01")
	dp.assign_daily_task()
	await _press(KEY_C)
	await create_timer(0.4).timeout
	var expected_room: String = String(dp.get_outstanding_task_room()).replace("_", " ").to_upper()
	_check("watch text includes the real room from DayPlan.get_outstanding_task_room() (%s)" % expected_room, watch_face.text.findn(expected_room) != -1)
	_check("watch text includes the real assignment task ID (%s)" % String(dp.assignment_task_id), watch_face.text.findn(String(dp.assignment_task_id)) != -1)
	await _release(KEY_C)
	await create_timer(0.4).timeout

	# ============================================================
	# 3. Inert while sitting on the bed (an exclusive state).
	# ============================================================
	var bunk := main.get_node("Interactables/Bunk")
	var sleep_state := main.get_node("SleepState")
	var free_body := main.get_node("FreeMoveBody")
	free_body.set_active(false)
	var bed_pos := Vector3(bunk.global_position.x - 1.0, 1.6, bunk.global_position.z)
	free_body.sync_to_eye_position(bed_pos)
	player.global_position = bed_pos
	await process_frame
	sleep_state.begin_sitting()
	await create_timer(1.3).timeout
	_check("precondition: actually sitting", sleep_state.is_sitting())
	await _press(KEY_C)
	await create_timer(0.4).timeout
	_check("holding C while sitting does not raise the watch", not watch.is_raised())
	_check("rig still hidden while sitting", not rig.visible)
	await _release(KEY_C)
	sleep_state.end_sitting()
	await create_timer(2.5).timeout
	_check("back to AWAKE after standing up", not sleep_state.is_sitting())

	# ============================================================
	# 4. Inert while seated at the workstation (the other exclusive
	# state explicitly called out by this task).
	# ============================================================
	var console := main.get_node("Interactables/WorkstationConsole")
	var wstate := main.get_node("WorkstationState")
	var console_pos: Vector3 = console.global_position + Vector3(0, 1.6 - console.global_position.y, 0.6)
	free_body.sync_to_eye_position(console_pos)
	free_body.velocity = Vector3.ZERO
	player.global_position = console_pos
	await process_frame
	console.interact()
	await create_timer(1.0).timeout
	_check("precondition: seated at workstation", wstate.is_in_use())
	await _press(KEY_C)
	await create_timer(0.4).timeout
	_check("holding C while at the workstation does not raise the watch", not watch.is_raised())
	await _release(KEY_C)
	wstate.end_use()
	await create_timer(1.3).timeout

	# ============================================================
	# 5. Normal free-roam afterward still works (no stuck state left
	# behind by the exclusive-state checks above).
	# ============================================================
	await _press(KEY_C)
	await create_timer(0.4).timeout
	_check("watch works normally again after both exclusive states end", watch.is_raised())
	_check("rig visible again", rig.visible)
	await _release(KEY_C)
	await create_timer(0.4).timeout
	_check("dismissed cleanly", not watch.is_raised())
	_check("rig hidden cleanly", not rig.visible)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

## Input.is_key_pressed() (what wristwatch_view.gd polls, matching
## free_move_controller.gd's own WASD convention) does not reflect a
## parse_input_event() call until one frame later -- confirmed by direct
## measurement, not assumed -- so these await a frame before returning.
func _press(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame

func _release(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
