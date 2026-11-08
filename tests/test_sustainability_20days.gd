extends SceneTree
## Round 32 Priority 6: 20 consecutive in-game days of routine maintenance
## on finite stock, resupplied ONLY by physical cargo through the airlock
## port. Each day the "technician" receives any shipment, restocks low
## shelves from the reserve, performs the day's assigned service with real
## parts from real slots (installing consumes them; used cartridges are
## disposed of), then verifies and closes at the workstation. Audited daily:
## every part has exactly one owner, totals are consistent with deliveries
## minus consumption, no impossible order is ever assigned, and work keeps
## going past the initial stock.
var _ok := true
var main: Node
var dp: Node
var carry: Node
var W
var fails_today := 0

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	dp = main.get_node("DayPlan")
	W = dp.Workday
	carry = main.get_node("Player/CarrySystem")
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var station: Node = main.get_node("Interactables/FilterHousingStation")
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var trash: Node = main.get_node("Interactables/TrashDisposal")
	var port: Node = main.get_node("Interactables/CargoPort")
	var crate: Node = main.get_node("Interactables/SupplyCrate")
	var cab1: Node = main.get_node("Geometry/StorageCabinet1")
	var cab2: Node = main.get_node("Geometry/StorageCabinet2")
	for c in [cab1, cab2, crate]:
		c.interact()
	await create_timer(1.0).timeout

	var initial: Dictionary = _on_hand(cab1, cab2, crate, port)
	var delivered := {}
	var consumed := {}
	var services := {}
	var fault_labels := {}
	var blocked_days := 0
	var max_blocked_streak := 0
	var streak := 0
	for day in range(2, 22):
		dp.reset_for_new_day()
		var tag := "day %d" % dp.day_number
		# 1) Cargo: receive and transfer to the reserve (or shelves).
		if port.state == port.PortState.ARRIVED:
			for t in port.manifest:
				delivered[t] = delivered.get(t, 0) + port.manifest[t]
			port.interact()                      # ID
			port.interact()                      # unlock/open
			await create_timer(1.6).timeout
			port.interact()                      # release restraint
			for p in port._parts.duplicate():
				if port.in_port(p):
					_take(p)
					if not _stow_any(p, [crate, cab1, cab2]):
						_check("%s: delivered part has somewhere to go" % tag, false)
			# Confirm in the SAME frame as the last transfer (regression: the
			# port only noticed "empty" on its next _process).
			port.interact()                      # confirm receipt
			port.interact()                      # close & secure
			await create_timer(1.0).timeout
		# 2) Restock low shelves from the reserve (physical transfers).
		for pair in [[cab2, &"filter_cartridge"], [cab1, &"wire_control_16ga"], [cab1, &"wire_signal_22ga"]]:
			var cab: Node = pair[0]
			while cab.stock_count(pair[1]) < cab.capacity(pair[1]) and crate.reserve_count(pair[1]) > 0:
				var src: Node3D = _first_in_reserve(crate, pair[1])
				_take(src)
				_stow_any(src, [cab])
		# 3) The day's assigned service, with real parts.
		var wd: int = dp.workday
		if dp.blocked_services.size() > 0:
			blocked_days += 1
			streak += 1
		else:
			streak = 0
		max_blocked_streak = maxi(max_blocked_streak, streak)
		if wd != W.NONE:
			services[wd] = services.get(wd, 0) + 1
			screen.show_section(screen.Section.OVERVIEW)
			screen.run_action()
		match wd:
			W.FILTER_SERVICE:
				var cart: Node3D = _first_stowed(cab2, &"filter_cartridge")
				_check("%s: filter order only when a clean cartridge is on the shelf" % tag, cart != null)
				if cart != null:
					_take(cart)
					# Round 36: any service variant (loose/seized latch, cocked cartridge).
					preload("res://tests/filter_service_solver.gd").solve(station)
					consumed[&"filter_cartridge"] = consumed.get(&"filter_cartridge", 0) + 1
					await process_frame
					var used = station._used_cartridge
					_check("%s: the old cartridge came out as a real used item" % tag, is_instance_valid(used) and used.is_ejected())
					if is_instance_valid(used):
						_take(used)
						trash.interact()
			W.ELECTRICAL_SERVICE:
				if panel._config_index == -1:
					panel._select_repair_config()
				var need: StringName = panel.required_component_id
				fault_labels[panel.fault_config_label()] = true
				var part: Node3D = _first_stowed(cab1, need)
				_check("%s: electrical order only when its compatible spare (%s) is on the shelf" % [tag, need], part != null)
				if part != null:
					_take(part)
					panel._procedure = panel.ProcedureStage.REPLACE
					var r: Dictionary = panel.install_replacement_wire()
					_check("%s: compatible spare installs" % tag, r["ok"])
					consumed[need] = consumed.get(need, 0) + 1
					panel._repair_stage = panel.RepairStage.REPAIRED
					panel._procedure = panel.ProcedureStage.COMPLETE
					dp.mark_done(&"e05")
			W.CALIBRATION:
				dp.mark_done(&"l07")
			W.COOLANT_INSPECTION:
				dp.mark_done(&"l08")
			W.INSPECTION_ROUND, W.COMMS_CHECK:
				# Round 33 routine days: click the physical inspection points
				# the order asks for (status tags, the Storage audit placard).
				if wd == W.COMMS_CHECK:
					dp.mark_done(&"m02")
				var lamps: Node = main.find_child("EquipmentStatusLamps", true, false)
				for point in lamps.tags():
					if dp.WORKDAY_STEPS[wd].any(func(st): return st[3] == StringName("reading:%s" % point.inspect_id)):
						point.interact()
				_check("%s: every required reading logged" % tag, dp.is_equipment_restored())
		if wd != W.NONE:
			screen.show_section(screen.Section.WORK_ORDERS)
			for k in 3:
				screen.run_action()
			_check("%s: %s order completed and closed" % [tag, dp.WORKDAY_TITLES.get(wd, "?")], dp.is_work_order_closed())
		# 4) Daily audit.
		var now: Dictionary = _on_hand(cab1, cab2, crate, port)
		for t in [&"filter_cartridge", &"wire_control_16ga", &"wire_signal_22ga"]:
			var expect: int = initial.get(t, 0) + delivered.get(t, 0) - consumed.get(t, 0)
			if now.get(t, 0) != expect:
				_check("%s: %s on hand %d == initial %d + delivered %d - consumed %d" % [tag, t, now.get(t, 0), initial.get(t, 0), delivered.get(t, 0), consumed.get(t, 0)], false)
		_check("%s: every part has exactly one owner" % tag, _single_owner_audit(cab1, cab2, crate, port))

	print("services performed: ", services, "  deliveries: ", dp.cargo_history.size(), "  delivered: ", delivered, "  consumed: ", consumed, "  blocked days: ", blocked_days, "  electrical faults seen: ", fault_labels.keys())
	_check("all four service types recurred over 20 days", [W.FILTER_SERVICE, W.CALIBRATION, W.ELECTRICAL_SERVICE, W.COOLANT_INSPECTION].all(func(w): return services.get(w, 0) >= 2))
	_check("routine inspection days happened on quiet days (round %d, comms %d)" % [services.get(W.INSPECTION_ROUND, 0), services.get(W.COMMS_CHECK, 0)], services.get(W.INSPECTION_ROUND, 0) + services.get(W.COMMS_CHECK, 0) >= 1)
	_check("several cargo shipments arrived and were received", dp.cargo_history.size() >= 4 and port.received_shipments.size() == dp.cargo_history.size())
	_check("work kept going on resupplied stock (filters used %d, initial %d)" % [consumed.get(&"filter_cartridge", 0), initial.get(&"filter_cartridge", 0)], consumed.get(&"filter_cartridge", 0) > initial.get(&"filter_cartridge", 0) - 2)
	_check("different electrical faults occurred (%d configurations)" % fault_labels.size(), fault_labels.size() >= 2)
	_check("never stuck: any blockage resolved within a cargo cycle (max streak %d days)" % max_blocked_streak, max_blocked_streak <= dp.CARGO_INTERVAL_DAYS + 1)
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _take(item: Node3D) -> void:
	if carry.is_carrying():
		_check("hand empty before taking %s" % item.name, false)
	carry.pick_up(item)
	if carry.is_reaching():
		carry.complete_grasp()


func _stow_any(item: Node3D, homes: Array) -> bool:
	for h in homes:
		if h.accepts_item(item):
			carry._carried_item = null
			carry._carried_item_id = &""
			carry._release_physics(item)
			h.stow(item)
			return true
	return false


func _first_stowed(cab: Node, id: StringName) -> Node3D:
	for it in cab._items:
		if is_instance_valid(it) and it.item_id == id and cab.is_item_stowed(it):
			return it
	return null


func _first_in_reserve(crate: Node, id: StringName) -> Node3D:
	for it in crate._items:
		if is_instance_valid(it) and it.item_id == id and crate.is_in_reserve(it):
			return it
	return null


func _on_hand(cab1: Node, cab2: Node, crate: Node, port: Node) -> Dictionary:
	var out := {}
	for t in [&"filter_cartridge", &"wire_control_16ga", &"wire_signal_22ga"]:
		out[t] = cab1.stock_count(t) + cab2.stock_count(t) + crate.reserve_count(t) + port.parts_in_port(t)
	return out


## No part is simultaneously stowed + reserved + in port + held + installed.
func _single_owner_audit(cab1: Node, cab2: Node, crate: Node, port: Node) -> bool:
	for it in main.find_children("*", "", true, false):
		if not ("item_id" in it) or not it.has_method("return_to_rest"):
			continue
		var owners := 0
		if cab1.is_item_stowed(it) or cab2.is_item_stowed(it): owners += 1
		if crate.is_in_reserve(it): owners += 1
		if port.in_port(it): owners += 1
		if carry.is_holding(it): owners += 1
		if it.has_method("is_installed") and it.is_installed(): owners += 1
		if owners > 1:
			print("  OWNER CONFLICT: ", it.get_path())
			return false
	return true


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
