extends SceneTree
## Round 33 Priorities 2/3: the technician's day -- morning BRIEFING from
## real state, the order worked with real parts, the END-OF-SHIFT REPORT
## derived from what actually happened, the shift-completion action, and
## CARRY-OVER of essential unfinished work into the next day.
var _ok := true
var main: Node
var carry: Node

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var dp: Node = main.get_node("DayPlan")
	var W = dp.Workday
	carry = main.get_node("Player/CarrySystem")
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var status: Label = screen.get_node("Control/VBox/Content/Home/Welcome")
	var orders: Label = screen.get_node("Control/VBox/Content/WorkOrders/List")
	var station: Node = main.get_node("Interactables/FilterHousingStation")
	var cab2: Node = main.get_node("Geometry/StorageCabinet2")
	var trash: Node = main.get_node("Interactables/TrashDisposal")
	cab2.interact()
	await create_timer(0.9).timeout

	# ---- Day 2 briefing. ----
	dp.reset_for_new_day()
	screen.show_section(screen.Section.HOME)
	var b: String = status.text
	_check("briefing names the day", b.find("TODAY IS DAY 2") != -1)
	_check("briefing shows live system status on one line (filter due)", b.find("Systems: ") != -1 and b.find("FILTER service due") != -1)
	_check("briefing names today's order", b.find("Scheduled: Life Support Filter Service") != -1)
	_check("briefing shows cargo expected", b.find("Cargo: next shipment day 3") != -1)
	_check("the shift clock is running (%s remaining)" % dp.clock_text(dp.shift_remaining_s()), not dp.shift_ended and dp.shift_remaining_s() > 590.0)
	screen.show_section(screen.Section.OVERVIEW)
	screen.run_action()   # C01
	screen.show_section(screen.Section.HOME)
	_check("after check-in the briefing gives the highest-priority step", status.text.find("Priority: ") != -1)

	# ---- The work, with real parts -- no confirmation clicks (Round 34). ----
	station.interact()
	await process_frame
	main.get_node("FocusedInteractionState").end()
	var cart: Node3D = _first_stowed(cab2)
	_take(cart)
	# Round 36: any service variant (loose/seized latch, cocked cartridge).
	preload("res://tests/filter_service_solver.gd").solve(station)
	await process_frame
	_check("restored -> verified automatically; cleanup still pending", dp.is_maintenance_verified() and not dp.is_work_order_closed())
	_check("mid-shift report lists the cleanup still pending", "\n".join(dp.shift_report_lines()).find("verified, cleanup pending") != -1)
	screen.show_section(screen.Section.WORK_ORDERS)
	_check("Work Orders: one line per duty with the next action (FILTER — Dispose old cartridge · Storage)", orders.text.find("SHIFT ") != -1 and orders.text.find("FILTER — Dispose old cartridge · Storage") != -1)
	_take(station._used_cartridge)
	trash.interact()
	_check("disposal closes the order automatically", dp.is_work_order_closed())
	_check("no report yet: the shift is still running", not dp.shift_reported)
	dp.end_shift_now()
	_check("shift end generates the report automatically (no submit click)", dp.shift_reported and dp.shift_history.size() == 1)
	screen._refresh_work_orders()
	screen.select_work_order(-1)   # the REPORT row is the last row
	screen.toggle_work_order_details()
	_check("Work Orders shows SHIFT ENDED and the report (REPORT row details)", orders.text.find("SHIFT ENDED") != -1 and orders.text.find("SHIFT REPORT — DAY 2") != -1)
	screen.toggle_work_order_details()
	var rep: String = "\n".join(dp.shift_history[-1]["report"])
	_check("report: the filter was serviced", rep.find("Equipment serviced: Life Support Filter Service") != -1)
	_check("report: 1 order closed, 1 part consumed, 1 discarded", rep.find("Work orders closed: 1") != -1 and rep.find("Parts consumed: 1   discarded: 1") != -1)
	_check("report: no cargo, nothing unfinished (all real)", rep.find("Cargo received: none") != -1 and rep.find("Unfinished: none") != -1)
	dp.end_shift_now()
	_check("ending twice is harmless (one report)", dp.shift_history.size() == 1)

	# ---- Day 3: calibration NOT done -> carries over to day 4. ----
	dp.reset_for_new_day()
	_check("day 3: calibration; the report flag and the shift clock reset for the new shift", dp.workday == W.CALIBRATION and not dp.shift_reported and not dp.shift_ended and dp.shift_elapsed_s < 1.0 and dp.shift_stats.is_empty())
	dp.mark_done(&"c01")
	dp.record_fact(&"reviewed:sensor_warning")
	_check("day 3 report lists the unrestored order as carrying over", "\n".join(dp.shift_report_lines()).find("Pressure Sensor Calibration — next: Calibrate the coupled chambers (carries over)") != -1)
	dp.reset_for_new_day()
	_check("day 4: the unfinished calibration CARRIED OVER (not erased)", dp.workday == W.CALIBRATION and dp.carried_over_from == 3)
	_check("...with its progress kept (warning already reviewed)", dp.has_fact(&"reviewed:sensor_warning") and not dp.is_work_order_closed())
	screen.show_section(screen.Section.HOME)
	_check("...and the briefing says so", status.text.find("Carried over from day 3") != -1)
	# Restored but never verified: NOT carried (the equipment works).
	dp.mark_done(&"l07")
	dp.reset_for_new_day()
	_check("day 5: a restored (unverified) order does not carry over", dp.workday != W.CALIBRATION and dp.carried_over_from == -1)
	_check("service history kept across the days", dp.service_history.size() == 2)
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _take(item: Node3D) -> void:
	if carry.is_carrying():
		carry.drop()
	carry.pick_up(item)
	if carry.is_reaching():
		carry.complete_grasp()


func _first_stowed(cab: Node) -> Node3D:
	for it in cab._items:
		if is_instance_valid(it) and cab.is_item_stowed(it):
			return it
	return null


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
