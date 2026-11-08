extends SceneTree
## Round 31 Priorities 1-4: finite multi-item stock, restocking from the
## reserve crate, and a repeatable multi-day maintenance routine built on
## DayPlan (no second registry): filter, calibration and electrical service
## recur on the SAME equipment (re-armed, never rebuilt), parts are
## consumed and never reappear in Storage, used parts are real items that
## must be disposed of, and impossible work orders are never scheduled.
var _ok := true
var main: Node
var dp: Node
var W

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	dp = main.get_node("DayPlan")
	W = dp.Workday
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var station: Node = main.get_node("Interactables/FilterHousingStation")
	var cab1: Node = main.get_node("Geometry/StorageCabinet1")
	var cab2: Node = main.get_node("Geometry/StorageCabinet2")
	var crate: Node = main.get_node("Interactables/SupplyCrate")
	var trash: Node = main.get_node("Interactables/TrashDisposal")
	var carry: Node = main.get_node("Player/CarrySystem")
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var calib: Node = main.get_node("Interactables/SensorCalibrationStation")

	# ---- Stock: several real parts, labels from real counts. ----
	_check("filter cabinet holds 4 real cartridges (4 slots)", cab2.stock_count() == 4 and cab2.capacity() == 4)
	_check("electrical cabinet holds 4 real 16GA harnesses (+2 shielded signal cables, Round 32)", cab1.stock_count(&"wire_control_16ga") == 4 and cab1.capacity(&"wire_control_16ga") == 4 and cab1.stock_count(&"wire_signal_22ga") == 2)
	_check("reserve crate: 2 filters, 3 harnesses", crate.reserve_count(&"filter_cartridge") == 2 and crate.reserve_count(&"wire_control_16ga") == 3)
	_check("placard reads the real count", (cab2.get_node("DoorHinge/StockLabel") as Label3D).text.find("4 AVAILABLE") != -1)
	cab2.interact()
	cab2.interact()
	await create_timer(1.2).timeout
	_check("reopening a cabinet never spawns stock (%d shelf parts, %d reserve)" % [_count("FilterCartridge"), _count("ReserveFilter")], cab2.stock_count() == 4 and _count("FilterCartridge") == 4 and _count("ReserveFilter") == 2)

	# ---- Day 1 unchanged. ----
	_check("day 1: tutorial day, no workday", dp.day_number == 1 and not dp.is_workday_active())

	# ---- Day 2: filter service through the real objects. ----
	dp.reset_for_new_day()
	_check("day 2: Filter Service", dp.workday == W.FILTER_SERVICE)
	await _filter_service(screen, station, cab2, carry, trash, "day 2")
	_check("day 2: one clean cartridge consumed (shelf 3/4)", cab2.stock_count() == 3)

	dp.reset_for_new_day()
	_check("day 3: Calibration", dp.workday == W.CALIBRATION)
	dp.mark_done(&"l07")
	dp.reset_for_new_day()
	_check("day 4: Electrical", dp.workday == W.ELECTRICAL_SERVICE)
	dp.mark_done(&"e05")
	dp.reset_for_new_day()
	_check("day 5: first Coolant Routing Inspection (Round 32)", dp.workday == W.COOLANT_INSPECTION)
	dp.mark_done(&"l08")

	# ---- Day 6: the filter recurs on the SAME housing (due day 6; with the
	# Round 32 four-workday rotation it now comes up before calibration). ----
	dp.reset_for_new_day()
	_check("day 6: filter service recurs (4-day interval)", dp.workday == W.FILTER_SERVICE)
	_check("the housing was re-armed (back to isolation) with the old cartridge still seated", station.stage() == station.Stage.ISOLATE and station.condition() == &"service_due")
	var installed_before: Node = station._installed_cartridge
	_check("the cartridge installed on day 2 is tracked as the seated one", is_instance_valid(installed_before))
	await _filter_service(screen, station, cab2, carry, trash, "day 6")
	_check("day 6: another clean cartridge consumed (shelf 2/4)", cab2.stock_count() == 2)
	_check("the day-2 cartridge came out as the used item (gone, not back in Storage)", not is_instance_valid(installed_before))
	_check("installed parts never reappear on the shelf", not cab2.is_item_stowed(station._installed_cartridge))

	dp.reset_for_new_day()
	_check("day 7: calibration recurs (3-day interval, due since day 6)", dp.workday == W.CALIBRATION and calib.service_seed() != 0)
	var seed6: int = calib.service_seed()
	dp.mark_done(&"l07")

	# ---- Day 9: electrical recurs on a different fixed circuit. ----
	# Electrical is due from day 9 (serviced day 4); other due systems
	# that come up first in the rotation are simply serviced.
	for d in 4:
		dp.reset_for_new_day()
		if dp.workday == W.ELECTRICAL_SERVICE:
			break
		if dp.workday == W.CALIBRATION:
			dp.mark_done(&"l07")
	_check("day %d: electrical service recurs (due after its 5-day interval)" % dp.day_number, dp.workday == W.ELECTRICAL_SERVICE and dp.day_number >= 9)
	_check("the panel was re-armed to UNDIAGNOSED (same 10-wire infrastructure)", not panel.is_repaired() and panel.condition() == &"fault")
	var label9: String = panel.fault_config_label()
	panel.debug_force_config_label("relay_fault" if label9 != "relay_fault" else "telemetry_fault")
	_check("the day's fault stays FIXED for the work order (no re-roll) [%s]" % label9, panel.fault_config_label() == label9)
	_check("calibration drift seeds differ by day", calib.service_seed() == 0 or calib.service_seed() != seed6)

	# ---- Restock: reserve -> shelf, real transfer. ----
	var rf: Node3D = crate.get_node("ReserveFilter1")
	var before_shelf: int = cab2.stock_count()
	if not cab2.is_open():
		cab2.interact()
	crate.interact()
	await create_timer(0.9).timeout
	rf.interact()
	await create_timer(1.6).timeout
	_check("reserve part picked up from the crate", carry.is_holding(rf) and crate.reserve_count(&"filter_cartridge") == 1)
	_check("a compatible reserve part is accepted by the open cabinet", cab2.accepts_item(rf))
	carry._carried_item = null
	carry._carried_item_id = &""
	carry._release_physics(rf)
	cab2.stow(rf)
	_check("restock: shelf +1 exactly when reserve -1 (%d -> %d)" % [before_shelf, cab2.stock_count()], cab2.stock_count() == before_shelf + 1 and crate.reserve_count(&"filter_cartridge") == 1)
	_check("restocked part is cabinet stock now (home parent)", rf.get_parent().name == "Interactables")

	# ---- Impossible work orders are never scheduled. ----
	for c in [cab2]:
		for it in c._items.duplicate():
			if c.is_item_stowed(it):
				it.queue_free()
	for it in crate._items:
		if is_instance_valid(it) and it.item_id == &"filter_cartridge" and crate.is_in_reserve(it):
			it.queue_free()
	await process_frame
	await process_frame
	_check("no clean cartridge anywhere -> filter service infeasible", not dp.is_service_feasible(W.FILTER_SERVICE))
	for d in 6:
		dp.reset_for_new_day()
		_check("day %d: never an impossible filter order" % dp.day_number, dp.workday != W.FILTER_SERVICE)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _filter_service(screen: Node, station: Node, cab2: Node, carry: Node, trash: Node, tag: String) -> void:
	screen.show_section(screen.Section.OVERVIEW)
	screen.run_action()
	station.interact()
	await process_frame
	main.get_node("FocusedInteractionState").end()
	await process_frame
	if not cab2.is_open():
		cab2.interact()
		await create_timer(0.8).timeout
	var pick: Node3D = null
	for it in cab2._items:
		if cab2.is_item_stowed(it):
			pick = it
			break
	var s0: int = cab2.stock_count()
	pick.interact()
	await create_timer(1.6).timeout
	_check("%s: a clean cartridge taken from the shelf (stock %d -> %d)" % [tag, s0, cab2.stock_count()], carry.is_holding(pick) and cab2.stock_count() == s0 - 1)
	_check("%s: retrieval recorded" % tag, dp.has_fact(&"retrieved:filter"))
	# Round 36: any service variant (loose/seized latch, cocked cartridge).
	preload("res://tests/filter_service_solver.gd").solve(station)
	_check("%s: restored (l02) with the new cartridge installed" % tag, dp.is_task_done(&"l02") and station._installed_cartridge == pick and pick.is_installed())
	await process_frame
	var used: Node = station._used_cartridge
	_check("%s: the old cartridge is a real used item on the floor" % tag, is_instance_valid(used) and used.visible and used.is_ejected())
	screen.show_section(screen.Section.WORK_ORDERS)
	screen.run_action()
	screen.run_action()
	_check("%s: verified but NOT closed while the used cartridge waits" % tag, dp.is_maintenance_verified() and not dp.is_work_order_closed())
	used.interact()
	await create_timer(1.6).timeout
	trash.interact()
	await process_frame
	_check("%s: used cartridge disposed (cleanup)" % tag, dp.is_cleanup_complete())
	screen.run_action()
	_check("%s: work order closed" % tag, dp.is_work_order_closed())


func _count(prefix: String) -> int:
	var n := 0
	for x in main.find_children(prefix + "*", "", true, false):
		if not str(x.name).begins_with("Used"):
			n += 1
	return n


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
