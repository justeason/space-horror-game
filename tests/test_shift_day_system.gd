extends SceneTree
## Round 34 Priorities 2/3/4/10: the DAY. A shift clock counting active
## play (paused with the tree), sleep refused until the shift ends (no
## teleport, overtime allowed), a new day ALWAYS starts awake in the bunk,
## the AUTOSAVE (start of day -> wakes in the bunk) versus a MANUAL
## mid-day save (restores the saved position), the clock surviving
## save/load, and event-driven completion (electrical order, cargo duty)
## with no duplicate closure. Own save paths only.
var _ok := true
const GameConfig = preload("res://scripts/station/game_config.gd")
const MAN := "user://test_r34_day_manual.json"
const AUTO := "user://test_r34_day_auto.json"
var main: Node

func _init() -> void:
	_clean()
	GameConfig.shift_duration_override_s = 4.0
	main = await _fresh()
	var dp: Node = main.get_node("DayPlan")
	var ss: Node = main.get_node("SleepState")
	var fb: Node3D = main.get_node("FreeMoveBody")
	_check("a 10-minute shift by default (central dev setting)", GameConfig.SHIFT_DURATION_S == 600.0)
	var e0: float = dp.shift_elapsed_s
	await create_timer(0.5).timeout
	_check("the shift clock counts active play (%.2f -> %.2f s)" % [e0, dp.shift_elapsed_s], dp.shift_elapsed_s > e0 + 0.3)
	paused = true
	var e1: float = dp.shift_elapsed_s
	for i in 20: await process_frame
	_check("pausing the game pauses the clock", absf(dp.shift_elapsed_s - e1) < 0.001)
	paused = false

	# ---- Sleep before the shift ends: refused, the player stays put. ----
	fb.sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	for i in 3: await physics_frame
	ss.begin_sitting()
	await create_timer(1.6).timeout
	ss.begin_sleep()
	await process_frame
	var msg: String = main.get_node("Player/HUD/TaskMessageLabel").text
	_check("sleep refused mid-shift with the work progress (Round 39: '%s')" % msg, not ss.is_sleeping() and msg.begins_with("Shift in progress — ") and msg.ends_with("% done."))
	_check("the seated prompt says when sleep becomes possible", main.get_node("Player/HUD/PromptLabel").text.find("Sleep after shift") != -1)
	await create_timer(4.0).timeout
	_check("the clock ends the shift by itself (report generated, no click)", dp.shift_ended and dp.shift_reported and dp.shift_history.size() == 1)
	_check("...the player was NOT moved (no forced bedtime / teleport)", ss.is_sitting() and not ss.is_sleeping())
	ss.end_sitting()
	await create_timer(3.0).timeout
	var stand: Vector3 = fb.global_position
	await create_timer(0.5).timeout
	_check("overtime: still free to work after the shift ended", not ss.is_sitting() and fb.global_position.distance_to(stand) < 0.05)

	# ---- Sleep after the shift: new day, waking IN THE BUNK. ----
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = MAN
	sg.autosave_path = AUTO
	sg.autosave_enabled = true
	fb.sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	for i in 3: await physics_frame
	ss.begin_sitting()
	await create_timer(1.6).timeout
	ss.begin_sleep()
	await create_timer(4.0).timeout
	_check("day 2 after sleeping", dp.day_number == 2)
	_check("the new day starts awake, lying IN THE BUNK", ss.is_lying_in_bed() and ss.is_sitting())
	_check("the new shift's clock restarted", not dp.shift_ended and dp.shift_elapsed_s < 4.0)
	_check("an AUTOSAVE was written at the new-day wake (protected slot)", sg.autosaves_written == 1 and FileAccess.file_exists(AUTO) and not FileAccess.file_exists(MAN))

	# ---- Manual mid-day save somewhere else, then load both. ----
	GameConfig.shift_duration_override_s = 600.0
	ss.end_sitting()
	await create_timer(3.5).timeout
	fb.sync_to_eye_position(Vector3(-0.3, 1.6, 0.6))   # Control Room
	for i in 5: await physics_frame
	dp.shift_elapsed_s = 123.0
	var sr: Dictionary = sg.save_game()
	_check("manual mid-day save in the Control Room ('%s')" % sr["message"], sr["ok"])
	var saved_pos: Vector3 = fb.global_position
	main.queue_free()
	await process_frame
	main = await _fresh()
	sg = main.get_node("SaveGame")
	sg.save_path = MAN
	sg.autosave_path = AUTO
	sg.apply_state(sg.read_save(MAN)["data"])
	await process_frame
	var fb2: Node3D = main.get_node("FreeMoveBody")
	_check("loading the MID-DAY save restores the saved position (not the bunk)", fb2.global_position.distance_to(saved_pos) < 0.05 and not main.get_node("SleepState").is_lying_in_bed())
	_check("...and the shift clock (%.1f s)" % main.get_node("DayPlan").shift_elapsed_s, absf(main.get_node("DayPlan").shift_elapsed_s - 123.0) < 2.0)
	main.queue_free()
	await process_frame
	main = await _fresh()
	sg = main.get_node("SaveGame")
	sg.apply_state(sg.read_save(AUTO)["data"])
	await create_timer(2.0).timeout
	_check("loading the AUTOSAVE starts that day awake in the bunk", main.get_node("SleepState").is_lying_in_bed() and main.get_node("DayPlan").day_number == 2)
	_check("slot listing shows both slots", sg.list_slots().size() == 2)

	# ---- Event-driven completion: electrical order + cargo duty. ----
	dp = main.get_node("DayPlan")
	var W = dp.Workday
	dp.workday = W.ELECTRICAL_SERVICE
	dp._facts.clear()
	var hist0: int = dp.service_history.size()
	for t in [&"c01", &"c02", &"e02"]:
		dp.mark_done(t)
	dp.record_fact(&"retrieved:wire")
	_check("not closed before the repair", not dp.is_work_order_closed())
	dp.mark_done(&"e05")
	_check("repair restored -> verified + CLOSED automatically", dp.is_task_done(&"c05") and dp.is_work_order_closed())
	dp.mark_done(&"e05")
	dp.record_fact(&"closed")
	_check("no duplicate closure / service entries", dp.service_history.size() == hist0 + 2 and dp.shift_stats.get("order_closed", 0) == 1)
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	screen.show_section(screen.Section.WORK_ORDERS)
	screen.run_action()
	_check("reopening the workstation does not reactivate the closed job", dp.is_work_order_closed() and dp.shift_stats.get("order_closed", 0) == 1)
	# Cargo duty (day 3 shipment) -- completes when stored + secured.
	dp.reset_for_new_day()
	var port: Node = main.get_node("Interactables/CargoPort")
	_check("day 3: the cargo duty opens with the shipment (%s)" % dp.cargo_duty, dp.cargo_duty == "open" and dp.guidance().size() > 0)
	if dp.workday != W.NONE:
		dp._facts[&"closed"] = true
	# Round 35: a tripped breaker (priority 3) outranks the cargo duty --
	# reset it for real at the panel, then the cargo step leads.
	var brk: Node = main.get_node("Equipment/BreakerPanel")
	_check("a higher-priority breaker order leads the guidance first ('%s')" % dp.guidance().get("short", ""), brk.tripped_ids().is_empty() or dp.guidance().get("short", "").begins_with("RESET"))
	for i in 4:
		if not brk.on[i]:
			brk.on_part(StringName("b%d" % i))
	await process_frame
	await process_frame
	_check("the breaker order closed automatically once the breaker was reset", not dp.has_open_order(&"breaker"))
	for o in dp.open_orders():
		if o["type"] != "breaker":
			o["status"] = "done"   # (other new orders are covered by their own tests)
	_check("guidance names the first cargo step ('%s')" % dp.guidance().get("label", ""), dp.guidance().get("short", "") == "CARGO ID")
	var crate: Node = main.get_node("Interactables/SupplyCrate")
	crate.interact()
	port.interact(); port.interact()
	await create_timer(1.7).timeout
	port.interact()
	var carry: Node = main.get_node("Player/CarrySystem")
	for p in port.carrier.parts():
		carry.pick_up(p)
		if carry.is_reaching(): carry.complete_grasp()
		carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(p)
		crate.stow(p)
	await process_frame
	await process_frame
	_check("guidance advanced by itself to 'CONFIRM' ('%s')" % dp.guidance().get("short", ""), dp.guidance().get("short", "") == "CONFIRM")
	port.interact()
	port.interact()
	await create_timer(1.4).timeout
	for i in 3: await process_frame
	_check("cargo duty completes automatically once received, stored and secured", dp.cargo_duty == "done" and dp.shift_stats.get("cargo_duty", 0) == 1)
	GameConfig.shift_duration_override_s = -1.0
	_clean()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _fresh() -> Node:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	current_scene = m
	for i in 6: await process_frame
	return m


func _clean() -> void:
	for base in [MAN, AUTO]:
		for p in [base, base + ".bak", base + ".tmp"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
