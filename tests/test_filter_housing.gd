extends SceneTree
## Round 15 Priority 4 regression coverage for L02 Filter Replacement --
## a maintenance procedure built on ALIGNMENT AND INSERTION (rotate the
## new cartridge to match the housing's fixed keyway, then attempt to
## seat it), distinct in kind from electrical repair's click-sequence
## memory and the coolant loop's discrete valve routing. Confirms: the
## full documented procedure (isolate -> open latches -> remove old ->
## align+insert -> close latches -> restore -> verify) via the REAL
## diorama raycast dispatch path; an insert attempt at the wrong
## rotation fails harmlessly and recoverably (no progress lost, no
## silent acceptance); latch state and the valve's open/closed visual
## stay correct and independent of each other (a shared-material bug
## was found and fixed here during this round -- see
## filter_housing_diorama.gd's sync_full_state() doc comment); the
## world-view twin stays in sync; and reopening after completion shows
## the done state immediately.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var day_plan := main.get_node("DayPlan")
	var station := main.get_node("Interactables/FilterHousingStation")
	var player := main.get_node("Player")
	var view := player.get_node("HUD/FilterHousingView")
	var focused := main.get_node("FocusedInteractionState")
	var world_diorama := station.get_node("WorldDiorama")

	_check("l02 not done at start", not day_plan.is_task_done(&"l02"))
	_check("prompt invites service before completion", station.get_interact_prompt().findn("Service") != -1)
	_check("cartridge starts away from the target keyway angle (real work required)", absf(station.cartridge_angle_deg() - station.target_angle_deg()) > station.tolerance_deg())

	station.interact()
	await process_frame
	_check("focused session active", focused.is_active())
	_check("filter view visible", view.visible)

	var diorama: Node3D = view.get_node("Panel/VBox/DioramaContainer/DioramaViewport/FilterHousingDiorama")
	var valve_handle_mat: StandardMaterial3D = diorama.get_node("Valve/HandleRoot/Handle").material

	_check("valve starts visually OPEN (not yet isolated)", not station.is_isolated())
	_check("valve handle renders the OPEN color at start", valve_handle_mat.albedo_color.is_equal_approx(diorama.COLOR_VALVE_OPEN))

	# ============================================================
	# STAGE 1: isolate, via the real diorama click path.
	# ============================================================
	await _click(diorama, &"valve")
	_check("valve click isolates airflow", station.is_isolated())
	_check("valve handle renders the CLOSED color once isolated", valve_handle_mat.albedo_color.is_equal_approx(diorama.COLOR_VALVE_CLOSED))

	# ============================================================
	# STAGE 2: both latches, via real clicks. Confirms the two latches
	# are visually INDEPENDENT (a real shared-material bug briefly made
	# toggling one latch, or even an unrelated valve/cartridge action,
	# bleed into the other's or the valve's own displayed color).
	# ============================================================
	var latch1_mat: StandardMaterial3D = diorama.get_node("Housing/Latch1/Latch1Body").material
	var latch2_mat: StandardMaterial3D = diorama.get_node("Housing/Latch2/Latch2Body").material
	_check("latch materials are genuinely independent resources", latch1_mat != latch2_mat)

	await _click(diorama, &"latch:1")
	_check("latch 1 opens", station.latch_open(1))
	_check("latch 2 NOT affected by latch 1's own click", not station.latch_open(2))
	_check("valve handle STILL renders CLOSED (unaffected by an unrelated latch click)", valve_handle_mat.albedo_color.is_equal_approx(diorama.COLOR_VALVE_CLOSED))

	await _click(diorama, &"latch:2")
	_check("both latches open -> advances to REMOVE_OLD", station.stage() == 2) # Stage.REMOVE_OLD

	# ============================================================
	# STAGE 3: remove the old cartridge.
	# ============================================================
	await _click(diorama, &"old_cartridge")
	_check("removing the old cartridge advances to ALIGN_INSERT", station.stage() == 3) # Stage.ALIGN_INSERT
	_check("valve handle STILL renders CLOSED (unaffected by cartridge removal)", valve_handle_mat.albedo_color.is_equal_approx(diorama.COLOR_VALVE_CLOSED))

	# ============================================================
	# STAGE 4: a wrong-rotation insert attempt must fail harmlessly and
	# recoverably -- no progress lost, not silently accepted.
	# ============================================================
	_check("cartridge starts at a rotation that does NOT match the target", absf(station.cartridge_angle_deg() - station.target_angle_deg()) > station.tolerance_deg())
	var result_wrong: Dictionary = station.attempt_insert()
	_check("wrong-rotation insert attempt does not seat", not result_wrong.get("seated", true))
	_check("stage unchanged after a failed insert attempt (recoverable, no progress lost)", station.stage() == 3) # Stage.ALIGN_INSERT
	_check("l02 still not done after a failed insert attempt", not day_plan.is_task_done(&"l02"))

	# Rotate to the correct angle (135 = 3 steps of 45) and retry.
	for i in 3:
		await _click(diorama, &"new_cartridge")
	_check("rotation reaches the fixed target angle", is_equal_approx(station.cartridge_angle_deg(), station.target_angle_deg()))

	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	main.get_viewport().push_input(ev)
	await process_frame
	_check("correctly-aligned insert seats and advances to CLOSE_LATCHES", station.stage() == 4) # Stage.CLOSE_LATCHES

	# ============================================================
	# STAGE 5/6: close latches, restore airflow, verify completion.
	# ============================================================
	await _click(diorama, &"latch:1")
	await _click(diorama, &"latch:2")
	_check("both latches closed -> advances to RESTORE", station.stage() == 5) # Stage.RESTORE

	await _click(diorama, &"valve")
	_check("restoring airflow completes the procedure", station.is_complete())
	_check("l02 marked done", day_plan.is_task_done(&"l02"))
	_check("valve handle renders OPEN again once restored", valve_handle_mat.albedo_color.is_equal_approx(diorama.COLOR_VALVE_OPEN))

	# World-view twin must reflect the exact same state.
	await create_timer(0.4).timeout
	var world_valve_mat: StandardMaterial3D = world_diorama.get_node("Valve/HandleRoot/Handle").material
	_check("world diorama valve handle matches the focused one's color (independent materials, same computed state)", world_valve_mat.albedo_color.is_equal_approx(valve_handle_mat.albedo_color))

	# Re-entry after completion shows the done state immediately.
	focused.end()
	await process_frame
	_check("prompt reflects nominal status", station.get_interact_prompt().findn("Nominal") != -1)
	station.interact()
	await process_frame
	_check("reopening after completion still shows COMPLETE", station.stage() == 6) # Stage.COMPLETE
	_check("l02 still done on reopen (not reset)", day_plan.is_task_done(&"l02"))
	focused.end()
	await process_frame

	main.queue_free()
	await process_frame

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()



func _click(diorama: Node3D, action: StringName) -> void:
	var pos: Vector2 = diorama.click_position(action)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	diorama._unhandled_input(down)
	await physics_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
