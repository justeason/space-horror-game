extends SceneTree
## Round 33 Priority 4: routine INSPECTION work on quiet days -- physical
## status readings at the equipment tags, a Storage SUPPLY AUDIT that needs
## the cabinet open, the workstation CROSS-CHECK of logged readings against
## live equipment state, and the routine COMMUNICATIONS check variant.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var dp: Node = main.get_node("DayPlan")
	var W = dp.Workday
	var lamps: Node = main.get_node("EquipmentStatusLamps")
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var cab1: Node = main.get_node("Geometry/StorageCabinet1")
	var tags := {}
	for t in lamps.tags():
		tags[String(t.inspect_id)] = t
	_check("inspection points exist for filter, power, sensors, coolant and the Storage audit", ["filter", "power", "sensors", "coolant", "storage_audit"].all(func(k): return tags.has(k)))
	_check("inspection points are pickable-only (layer 16): never block the player or physics", lamps.tags().all(func(t): return t.collision_layer == 16 and t.collision_mask == 0))

	# Every service done once, nothing due -> a quiet day becomes routine work.
	for w in [W.FILTER_SERVICE, W.CALIBRATION, W.ELECTRICAL_SERVICE, W.COOLANT_INSPECTION]:
		dp._serviced[w] = 3
	dp.day_number = 3
	dp.reset_for_new_day()   # day 4
	_check("a quiet day schedules routine work (%s)" % dp.today_title(), dp.workday in dp.ROUTINE_WORKDAYS)
	dp.workday = W.INSPECTION_ROUND
	dp.mark_done(&"c01")
	screen.show_section(screen.Section.WORK_ORDERS)
	screen.run_action()
	_check("filing before the readings is refused ('%s')" % screen._workday_status, screen._workday_status.begins_with("Cannot file yet") and not dp.is_maintenance_verified())
	tags["storage_audit"].interact()
	_check("supply audit needs the cabinet open (counting the real shelf)", not dp.has_reading(&"storage_audit") and main.get_node("Player/HUD/TaskMessageLabel").text.find("Open the cabinet") != -1)
	cab1.interact()
	await create_timer(0.8).timeout
	tags["storage_audit"].interact()
	_check("audit logs the physical count ('%s')" % dp.reading_of(&"storage_audit"), dp.reading_of(&"storage_audit") == "16GA 4/4 · 22GA SIG 2/2")
	for k in ["filter", "coolant"]:
		tags[k].interact()
	_check("the tag prompt shows the logged value", tags["filter"].get_interact_prompt().find("logged (NOMINAL)") != -1)
	_check("readings logged so far are live (%s)" % str(dp.readings), dp.reading_of(&"filter") == "NOMINAL" and not dp.is_maintenance_verified())
	# The filter reading goes STALE before the last reading is logged: the
	# automatic cross-check (run on the last reading) must catch it.
	var housing: Node = main.get_node("Interactables/FilterHousingStation")
	housing.toggle_isolate()   # filter now IN SERVICE
	tags["power"].interact()
	_check("the automatic cross-check catches the stale filter reading ('%s')" % main.get_node("Player/HUD/TaskMessageLabel").text, not dp.has_reading(&"filter") and not dp.is_maintenance_verified() and main.get_node("Player/HUD/TaskMessageLabel").text.begins_with("Cross-check failed"))
	housing.toggle_isolate()
	tags["filter"].interact()
	_check("re-reading verifies and CLOSES the routine order automatically (no filing click)", dp.is_maintenance_verified() and dp.is_work_order_closed())
	_check("the shift report lists the inspections", "\n".join(dp.shift_report_lines()).find("filter NOMINAL") != -1 and "\n".join(dp.shift_report_lines()).find("electrical 16GA 4/4") != -1)

	# Comms check variant.
	dp.reset_for_new_day()
	dp.workday = W.COMMS_CHECK
	dp.mark_done(&"c01")
	_check("comms check: the routine signal check (M02) is a real step", dp.next_workday_step()["label"] == "Run the routine signal check")
	dp.mark_done(&"m02")
	tags["sensors"].interact(); tags["power"].interact()
	_check("comms check cross-checked and closed automatically", dp.is_work_order_closed())
	dp.reset_for_new_day()
	_check("an unfinished routine order is NOT carried over", dp.carried_over_from == -1 and dp.readings.is_empty())
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
