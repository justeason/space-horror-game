extends SceneTree
## Round 32 Priority 3: physical cargo resupply through the airlock cargo
## transfer port. Shipments are finite (the storage shortfall, capped by the
## port's cargo slots), arrive on DayPlan's deterministic schedule, stay
## physically inside the secured compartment until the receiving procedure
## is performed, and reach Storage stock only when each part is carried
## there. Received exactly once; nothing regenerates.
var _ok := true
var main: Node
var carry: Node

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var dp: Node = main.get_node("DayPlan")
	var port: Node = main.get_node("Interactables/CargoPort")
	var crate: Node = main.get_node("Interactables/SupplyCrate")
	var cab2: Node = main.get_node("Geometry/StorageCabinet2")
	carry = main.get_node("Player/CarrySystem")
	var S = port.PortState

	_check("day 1: port secured, no shipment", port.state == S.SECURED and port.shipment_id == "" and dp.next_cargo_day == 3)
	dp.reset_for_new_day()
	_check("day 2: still no shipment (scheduled for day 3)", not port.is_busy())
	dp.mark_done(&"l02")   # day 2's filter restored (Round 33: unrestored work would carry over)
	var needs: Dictionary = dp.cargo_needs()
	_check("needs = real shortfall (filters 2, 16GA 0, 22GA 1): %s" % str(needs), needs[&"filter_cartridge"] == 2 and needs[&"wire_control_16ga"] == 0 and needs[&"wire_signal_22ga"] == 1)
	var shelf_f0: int = cab2.stock_count(&"filter_cartridge")
	var res_f0: int = crate.reserve_count(&"filter_cartridge")
	var res_s0: int = crate.reserve_count(&"wire_signal_22ga")
	dp.reset_for_new_day()
	_check("day 3: shipment %s ARRIVED with the shortfall manifest %s" % [port.shipment_id, str(port.manifest)], port.state == S.ARRIVED and port.manifest.get(&"filter_cartridge", 0) == 2 and port.manifest.get(&"wire_signal_22ga", 0) == 1 and port.parts_in_port() == 3)
	_check("no premature stock increase on arrival", cab2.stock_count(&"filter_cartridge") == shelf_f0 and crate.reserve_count(&"filter_cartridge") == res_f0)
	var parts: Array = port._parts.duplicate()
	_check("delivered parts are secured: hidden and not clickable behind the closed hatch", parts.all(func(p): return not p.visible and p.get_node("Collision").disabled))
	_check("a busy port refuses a second shipment", not port.receive_shipment("CS-X", {&"filter_cartridge": 1}) and port.parts_in_port() == 3)
	_check("work orders show the arrival", "\n".join(dp.supply_warnings()).find("SHIPMENT ARRIVED") != -1)
	var warn: String = "\n".join(dp.supply_warnings())
	_check("work orders show a compact real stock line (shelf+reserve)", warn.find("STOCK (shelf+reserve): FILTER %d+%d" % [cab2.stock_count(&"filter_cartridge"), crate.reserve_count(&"filter_cartridge")]) != -1)
	# P7 wristwatch: once today's order is closed, the waiting shipment is
	# the glanceable hint.
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	screen.show_section(screen.Section.OVERVIEW)
	screen.run_action()
	dp.mark_done(&"l07")
	var brk: Node = main.get_node("Equipment/BreakerPanel")
	for i in 4:   # Round 35: reset the day's tripped breaker (higher priority)
		if not brk.on[i]:
			brk.on_part(StringName("b%d" % i))
	await process_frame
	for o in dp.open_orders():
		o["status"] = "done" if o["type"] != "breaker" else o["status"]
	screen.show_section(screen.Section.WORK_ORDERS)
	for k in 3:
		screen.run_action()
	_check("upcoming maintenance listed from the service log", "\n".join(dp.supply_warnings()).find("UPCOMING: ") != -1)
	var watch: Node = main.get_node("Player/Wristwatch")
	watch._refresh_text()
	var face: Label3D = main.get_node("Player/LookPivot/PitchPivot/Camera3D/FirstPersonWatchRig/ArmGroup/WatchAssembly/WatchFaceText")
	_check("wristwatch: order closed + shipment waiting -> the cargo duty's next step 'CARGO ID / AIRLOCK' (got '%s')" % face.text.replace("\n", " / "), dp.get_outstanding_task_room() == &"" and face.text.begins_with("CARGO ID\nAIRLOCK · "))

	# ---- Receiving procedure. ----
	port.interact()
	_check("1. shipment ID checked", port.state == S.ID_CHECKED)
	port.interact()
	await create_timer(1.6).timeout
	_check("2. hatch unlocked, pressure equalised, opened", port.state == S.OPEN and (port._hatch as Node3D).position.y > 0.4)
	_check("   parts still restrained (not yet usable)", parts.all(func(p): return not p.visible))
	port.interact()
	await create_timer(0.4).timeout
	_check("3. restraint released: parts usable", port.state == S.UNLOADING and parts.all(func(p): return p.visible and not p.get_node("Collision").disabled))
	port.interact()
	_check("   confirm is not possible while parts remain", port.state == S.UNLOADING)

	# ---- Transfer to the Storage reserve crate (real carries). ----
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-4.8, 1.6, -1.3))
	for i in 10: await physics_frame
	crate.interact()
	await create_timer(0.8).timeout
	var i_part := 0
	for p in parts:
		p.interact()
		await create_timer(1.3).timeout
		_check("carry part %d out of the compartment" % i_part, carry.is_holding(p) and not port.in_port(p))
		var before: int = crate.reserve_count(p.item_id)
		_check("   the crate accepts the compatible part", crate.accepts_item(p))
		carry._carried_item = null
		carry._carried_item_id = &""
		carry._release_physics(p)
		crate.stow(p)
		_check("   reserve +1 exactly at the transfer (%d -> %d)" % [before, crate.reserve_count(p.item_id)], crate.reserve_count(p.item_id) == before + 1)
		i_part += 1
	await process_frame
	_check("compartment empty -> ready to confirm", port.state == S.EMPTY and port.parts_in_port() == 0)
	_check("reserve now holds the delivered parts (filters %d -> %d, 22GA %d -> %d)" % [res_f0, crate.reserve_count(&"filter_cartridge"), res_s0, crate.reserve_count(&"wire_signal_22ga")], crate.reserve_count(&"filter_cartridge") == res_f0 + 2 and crate.reserve_count(&"wire_signal_22ga") == res_s0 + 1)
	port.interact()
	_check("4. receipt confirmed exactly once", port.state == S.RECEIVED and port.received_shipments == ["CS-0001"] and dp.has_fact(&"received:cargo"))
	port.interact()
	await create_timer(1.2).timeout
	_check("5. hatch closed and secured", port.state == S.SECURED and port.shipment_id == "")
	port.interact()
	port.interact()
	await create_timer(1.0).timeout
	_check("re-operating a secured empty port creates nothing", port.parts_in_port() == 0 and port.received_shipments.size() == 1)
	_check("next cargo scheduled 4 days later (day 7)", dp.next_cargo_day == 7)
	var count := 0
	for n in main.find_children("CargoCS*", "", true, false):
		count += 1
	_check("exactly the 3 delivered parts exist (no duplicates)", count == 3)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
