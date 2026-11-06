extends SceneTree
## Round 29 Priority 8: repeatable-maintenance FOUNDATION on DayPlan (no
## second registry). DayPlan's Round 28 boolean "serviced" set became a
## service log (last serviced day + history) with per-system service
## intervals. A serviced system is scheduled again only once it is DUE and
## its equipment has registered a re-arm handler that can put it back into
## a real fault -- no station registers one yet, so the shipped behaviour
## is exactly Round 28's (covered by test_workdays.gd). Here a stand-in
## handler proves the scheduling path end to end.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var dp: Node = main.get_node("DayPlan")
	var W = dp.Workday

	_check("day 1 unchanged: no workday", dp.day_number == 1 and not dp.is_workday_active())
	# Service every system once (days 2-4), as the real stations would.
	dp.reset_for_new_day()
	_check("day 2: Filter Service", dp.workday == W.FILTER_SERVICE)
	dp.mark_done(&"l02")
	dp.reset_for_new_day()
	_check("day 3: Calibration", dp.workday == W.CALIBRATION)
	dp.mark_done(&"l07")
	dp.reset_for_new_day()
	_check("day 4: Electrical", dp.workday == W.ELECTRICAL_SERVICE)
	dp.mark_done(&"e05")
	_check("service log records the day each system was serviced", dp.last_serviced_day(W.FILTER_SERVICE) == 2 and dp.last_serviced_day(W.CALIBRATION) == 3 and dp.last_serviced_day(W.ELECTRICAL_SERVICE) == 4)
	_check("service history keeps every completed service in order", dp.service_history.size() == 3 and dp.service_history[0]["workday"] == W.FILTER_SERVICE and dp.service_history[2]["day"] == 4)

	# Round 30: the REAL calibration station opts in; filter and electrical
	# (physical parts / no restock yet) do not.
	var station: Node = main.get_node("Interactables/SensorCalibrationStation")
	_check("the calibration station registered its re-arm with DayPlan", dp.has_service_rearm(W.CALIBRATION))
	_check("Round 31: filter and electrical stations registered their re-arm too", dp.has_service_rearm(W.FILTER_SERVICE) and dp.has_service_rearm(W.ELECTRICAL_SERVICE))
	dp.reset_for_new_day()   # day 5: calibration serviced day 3 -> not yet due
	_check("day 5: calibration not yet due; the first coolant inspection runs instead (Round 32)", dp.workday == W.COOLANT_INSPECTION and not dp.is_service_due(W.CALIBRATION))
	dp.mark_done(&"l08")
	dp.reset_for_new_day()   # day 6: the filter (due day 6) comes first in the rotation
	_check("day 6: the filter recurs first (rotation order, Round 32)", dp.workday == W.FILTER_SERVICE)
	dp.mark_done(&"l02")
	dp.reset_for_new_day()   # day 7: calibration 4 days since -> due -> recurs
	_check("day 7: calibration is due and recurs as a new work order", dp.workday == W.CALIBRATION)
	_check("...the station records a sensor drift for today", station.has_recorded_drift())
	var req: int = station.service_required_count()
	_check("...with a day-specific requirement (1-3 chambers, got %d)" % req, req >= 1 and req <= 3)
	_check("...and the prompt says so", station.get_interact_prompt().find("drift detected") != -1)
	_check("...the recurring order is open (not pre-closed, not serviced)", not dp.is_work_order_closed() and not dp.is_equipment_serviced(W.CALIBRATION))
	_check("history of the earlier services is preserved", dp.service_history.size() == 5)
	var view: Node = main.get_node("Player/HUD/SensorCalibrationView")
	_check("the requirement is stable within the day (seeded, never re-rolled)", station.service_required_count() == req and dp.daily_variant_seed(W.CALIBRATION) == dp.daily_variant_seed(W.CALIBRATION))
	view.open_station(station)
	await process_frame
	var drifted := 0
	for ch in view.CHAMBERS:
		if not is_equal_approx(view._setpoint[ch], view._TARGETS[ch]):
			drifted += 1
	_check("the real calibration view starts with exactly the day's drifted chambers (%d of %d)" % [drifted, req], drifted == req)
	main.get_node("FocusedInteractionState").end()
	await process_frame
	var seed_today: int = dp.daily_variant_seed(W.CALIBRATION)
	dp.mark_done(&"l07")
	_check("calibrating clears the drift", not station.has_recorded_drift())
	_check("the re-service is logged", dp.service_history.size() == 6 and dp.last_serviced_day(W.CALIBRATION) == 7)
	dp.reset_for_new_day()
	_check("variant seed differs on another day", dp.daily_variant_seed(W.CALIBRATION) != seed_today)
	_check("a re-serviced system is not re-scheduled immediately", dp.workday != W.CALIBRATION)
	_check("yesterday's drift does not linger", station.service_required_count() == 0)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
