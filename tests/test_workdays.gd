extends SceneTree
## Round 28 Priority 4: authored maintenance workdays built on DayPlan's
## existing task fields + physical facts reported by real objects. Covers:
## day 1 unchanged (tutorial slices); day 2 Filter Service end-to-end through
## the real cabinet / filter housing / disposal bin / workstation; the
## separate restored -> verified -> cleanup -> closed states; guidance
## (wristwatch/map room) following the next step; Calibration day's
## Diagnostics not raising the electrical fault; serviced equipment skipped.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var dp: Node = main.get_node("DayPlan")
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var station: Node = main.get_node("Interactables/FilterHousingStation")
	var cab2: Node = main.get_node("Geometry/StorageCabinet2")
	var cartridge: Node = main.get_node("Interactables/FilterCartridge")
	var used: Node = main.get_node("Interactables/UsedFilterCartridge")
	var trash: Node = main.get_node("Interactables/TrashDisposal")
	var carry: Node = main.get_node("Player/CarrySystem")

	# ---- Day 1: unchanged tutorial slices. ----
	_check("day 1 has no workday (Slice A/B unchanged)", dp.day_number == 1 and not dp.is_workday_active())
	screen.show_section(screen.Section.OVERVIEW)
	screen.run_action()
	_check("day 1 C01 still assigns E06 (Slice A)", dp.assignment_task_id == &"e06")

	# ---- Day 2: Filter Service. ----
	dp.reset_for_new_day()
	_check("day 2 starts the Filter Service workday", dp.day_number == 2 and dp.workday == dp.Workday.FILTER_SERVICE)
	_check("guidance: receive the order at the Control Room first", dp.get_outstanding_task_room() == &"control_room")
	screen.show_section(screen.Section.OVERVIEW)
	screen.run_action()
	_check("C01 on a workday does NOT assign the Slice A E06 task", dp.is_task_done(&"c01") and dp.assignment_task_id == &"")
	_check("work order lists the workday", "\n".join(dp.get_work_order_lines(false)).find("Filter Service") != -1)
	_check("guidance: next step is inspecting the filter (Life Support)", dp.get_outstanding_task_room() == &"life_support")

	station.interact()   # opens the focused filter view = inspection
	await process_frame
	main.get_node("FocusedInteractionState").end()
	await process_frame
	_check("inspecting the real filter housing records the step", dp.has_fact(&"inspected:filter"))
	_check("guidance: next is Storage (retrieve cartridge)", dp.get_outstanding_task_room() == &"storage")

	cab2.interact()
	await create_timer(0.7).timeout
	cartridge.interact()
	await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
	await process_frame
	await process_frame
	_check("taking the cartridge from its cabinet records retrieval", dp.has_fact(&"retrieved:filter") and carry.carried_item_id() == &"filter_cartridge")

	# Round 36: any service variant (loose/seized latch, cocked cartridge).
	preload("res://tests/filter_service_solver.gd").solve(station)
	_check("filter serviced: equipment restored", dp.is_task_done(&"l02") and dp.is_equipment_restored())
	# Round 34: the system self-test VERIFIES automatically on restore; the
	# order stays open only for the mandatory cleanup -- no confirmation clicks.
	_check("restored -> verified automatically, cleanup pending, order open", dp.is_maintenance_verified() and not dp.is_cleanup_complete() and not dp.is_work_order_closed())
	_check("guidance: dispose of the used cartridge (Storage)", dp.get_outstanding_task_room() == &"storage")
	screen.show_section(screen.Section.WORK_ORDERS)
	screen.run_action()
	_check("[R] cannot close while the used cartridge awaits disposal", not dp.is_work_order_closed() and screen._workday_status.find("disposal") != -1)

	used.interact()
	await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
	trash.interact()
	_check("disposing the real used cartridge records cleanup", dp.has_fact(&"disposed:used_filter") and dp.is_cleanup_complete())
	_check("...and the order CLOSES AUTOMATICALLY (no workstation click)", dp.is_work_order_closed())
	_check("no outstanding room once closed", dp.get_outstanding_task_room() == &"")
	_check("work order status reads CLOSED", "\n".join(dp.workday_lines()).find("CLOSED") != -1)

	# ---- Day 3: Calibration -- Diagnostics reviews the warning, no fault. ----
	dp.reset_for_new_day()
	_check("day 3 starts the Calibration workday (filter already serviced is skipped)", dp.workday == dp.Workday.CALIBRATION)
	screen.show_section(screen.Section.OVERVIEW)
	screen.run_action()
	screen.show_section(screen.Section.DIAGNOSTICS)
	screen.run_action()
	_check("calibration-day Diagnostics records the warning review", dp.has_fact(&"reviewed:sensor_warning"))
	_check("...and does NOT raise the Engineering power fault", dp.fault_target == &"")
	_check("guidance: calibrate in Life Support", dp.get_outstanding_task_room() == &"life_support")
	screen.show_section(screen.Section.WORK_ORDERS)
	screen.run_action()
	_check("verify refuses before the equipment is restored", not dp.is_maintenance_verified() and screen._workday_status.find("not yet restored") != -1)
	dp.mark_done(&"l07")
	_check("calibration verified and closed automatically on restore (no cleanup step, no click)", dp.is_maintenance_verified() and dp.is_work_order_closed())

	# ---- Day 4: Electrical; day 5: Coolant inspection (Round 32); day 6:
	# the first-time rotation is exhausted, only due re-services remain. ----
	dp.reset_for_new_day()
	_check("day 4 starts Electrical Service", dp.workday == dp.Workday.ELECTRICAL_SERVICE)
	dp.mark_done(&"e05")
	dp.reset_for_new_day()
	_check("day 5 starts the Coolant Routing Inspection workday (Round 32)", dp.workday == dp.Workday.COOLANT_INSPECTION)
	dp.mark_done(&"l08")
	dp.reset_for_new_day()
	_check("with every system serviced once, day 6 schedules only a due re-service (filter, 4-day interval) -- no broken orders", dp.workday == dp.Workday.FILTER_SERVICE and not dp.is_work_order_closed())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
