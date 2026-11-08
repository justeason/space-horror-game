extends SceneTree
## Round 33 Priority 1/9: save/load round trip on a FRESH station, plus
## failure handling. Builds a messy mid-game state (shelf/reserve stock
## changed, an installed filter, a used cartridge awaiting disposal, a
## loose dropped part, a part in the hand, an electrical repair mid-
## procedure, a calibration drift, a partially unloaded cargo shipment,
## coolant valves moved, a laptop entry), saves, rebuilds the station from
## scratch, loads, and compares every part's owner and every saved field.
## Uses its own save path (never the player's real save).
var _ok := true
const PATH := "user://test_r33_savegame.json"
var main: Node

func _init() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	main = await _fresh()
	var sg: Node = main.get_node("SaveGame")
	var dp: Node = main.get_node("DayPlan")
	var carry: Node = main.get_node("Player/CarrySystem")
	_check("missing save: read reports it cleanly", not sg.read_save()["ok"] and sg.read_save()["message"] == "No saved game found." and not sg.has_save())

	# ---- Build a mid-game state. ----
	var cab1: Node = main.get_node("Geometry/StorageCabinet1")
	var cab2: Node = main.get_node("Geometry/StorageCabinet2")
	var crate: Node = main.get_node("Interactables/SupplyCrate")
	var port: Node = main.get_node("Interactables/CargoPort")
	var housing: Node = main.get_node("Interactables/FilterHousingStation")
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	for c in [cab1, cab2, crate]:
		c.interact()
	await create_timer(1.0).timeout
	dp.reset_for_new_day()                         # day 2: filter service
	var cart: Node3D = main.get_node("Interactables/FilterCartridge3")
	_take(carry, cart)
	# Round 36: any service variant (loose/seized latch, cocked cartridge).
	preload("res://tests/filter_service_solver.gd").solve(housing)
	await process_frame
	_check("setup: filter installed, used cartridge ejected", cart.is_installed() and housing._used_cartridge.is_ejected())
	# Restock one reserve filter onto the shelf (ownership changes).
	var rf: Node3D = crate.get_node("ReserveFilter1")
	_take(carry, rf)
	_stow(carry, rf, cab2)
	dp.reset_for_new_day()                         # day 3: cargo arrives
	_check("setup: day 3 shipment arrived", port.state == port.PortState.ARRIVED)
	port.interact(); port.interact()
	await create_timer(1.7).timeout
	port.interact()                                # restraint released
	var first: Node3D = port._parts[0]
	_take(carry, first)
	_stow(carry, first, crate)                     # one part transferred
	# A loose part on the floor, a part in the hand.
	var loose: Node3D = main.get_node("Interactables/WireComponent2")
	_take(carry, loose)
	carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(loose)
	loose.place_in_world(Transform3D(Basis(Vector3.UP, 0.7), Vector3(3.2, 0.103, -0.2)))
	var held: Node3D = main.get_node("Interactables/WireSignal2")
	_take(carry, held)
	# Electrical repair mid-procedure, calibration drift, valves moved.
	panel._config_index = -1
	panel._apply_config(3)
	panel._repair_stage = panel.RepairStage.TRACED
	panel._procedure = panel.ProcedureStage.DISCONNECT
	panel._disconnected = [&"coolant"]
	main.get_node("Interactables/SensorCalibrationStation")._rearm_for_service(12345)
	var valve: Node = main.get_node("Interactables/ValveRoutingStation")
	valve.toggle_valve(1)
	dp.record_fact(&"inspected:filter")
	main.get_node("Player/LaptopView")._saved_entry = "Day 3: cargo half unloaded."
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-6.4, 1.6, 7.6))
	for i in 5: await physics_frame

	# ---- Unsafe moments are refused deterministically. ----
	carry.drop()
	await process_frame
	var other: Node3D = main.get_node("Interactables/WireComponent4")
	carry.pick_up(other)
	_check("saving is refused mid-reach ('%s')" % sg.save_blocker(), sg.save_blocker() != "" and not sg.save_game()["ok"] and not FileAccess.file_exists(PATH))
	carry.cancel_reach()
	_take(carry, held)
	await process_frame
	var expected: Dictionary = sg.collect_state()
	var r: Dictionary = sg.save_game()
	_check("save succeeds ('%s')" % r["message"], r["ok"] and FileAccess.file_exists(PATH) and not FileAccess.file_exists(PATH + ".tmp"))
	var stock_before: Array = _stock(main)
	var port_before: int = port.parts_in_port()

	# ---- Fresh station, load. ----
	main.queue_free()
	await process_frame
	main = await _fresh()
	sg = main.get_node("SaveGame")
	dp = main.get_node("DayPlan")
	carry = main.get_node("Player/CarrySystem")
	_check("fresh station starts on day 1 (nothing persisted implicitly)", dp.day_number == 1)
	var rr: Dictionary = sg.read_save()
	var t0 := Time.get_ticks_msec()
	var ar: Dictionary = sg.apply_state(rr["data"])
	var load_ms: int = Time.get_ticks_msec() - t0
	await process_frame
	await process_frame
	_check("load succeeds ('%s') in %d ms" % [ar["message"], load_ms], ar["ok"] and load_ms < 2000)
	var got: Dictionary = sg.collect_state()
	_check("day and workday restored (day %d)" % dp.day_number, dp.day_number == 3 and got["day_plan"]["workday"] == expected["day_plan"]["workday"])
	var e_dp: Dictionary = expected["day_plan"].duplicate()
	var g_dp: Dictionary = got["day_plan"].duplicate()
	var e_clock: float = float(e_dp.get("shift_elapsed_s", 0.0))
	var g_clock: float = float(g_dp.get("shift_elapsed_s", 0.0))
	e_dp.erase("shift_elapsed_s")
	g_dp.erase("shift_elapsed_s")
	_check("DayPlan fields identical (facts, service log, cargo schedule, statuses)", JSON.stringify(g_dp) == JSON.stringify(e_dp))
	_check("Round 34: the shift clock is restored (%.1f s saved-time vs %.1f s)" % [e_clock, g_clock], absf(g_clock - e_clock) < 3.0)
	_check("equipment fields identical (panel mid-procedure, housing, calibration, valves, port)", JSON.stringify(got["equipment"]) == JSON.stringify(expected["equipment"]))
	var em := _by_id(expected["items"])
	var gm := _by_id(got["items"])
	_check("same set of parts (%d saved, %d loaded)" % [em.size(), gm.size()], em.keys().size() == gm.keys().size() and em.keys().all(func(k): return gm.has(k)))
	var owner_mismatch: Array = []
	for k in em:
		if gm.has(k) and not _same_owner(em[k]["owner"], gm[k]["owner"]):
			owner_mismatch.append("%s: %s -> %s" % [k, JSON.stringify(em[k]["owner"]), JSON.stringify(gm[k]["owner"])])
	_check("every part has the same single owner after load %s" % str(owner_mismatch), owner_mismatch.is_empty())
	var names := {}
	var dup := false
	for it in sg._all_items():
		if names.has(String(it.name)): dup = true
		names[String(it.name)] = true
	_check("no part exists twice", not dup)
	_check("shelf/reserve stock identical %s == %s" % [str(_stock(main)), str(stock_before)], _stock(main) == stock_before)
	_check("the held part is back in the hand", carry.is_carrying() and carry._carried_item.name == "WireSignal2")
	var l2: Node3D = main.get_node("Interactables/WireComponent2")
	_check("the dropped part lies where it was, visible and collidable", l2.global_position.distance_to(Vector3(3.2, 0.103, -0.2)) < 0.001 and l2.visible and not l2.get_node("Collision").disabled)
	var h2: Node = main.get_node("Interactables/FilterHousingStation")
	_check("installed filter restored inside the housing", is_instance_valid(h2._installed_cartridge) and h2._installed_cartridge.name == "FilterCartridge3" and h2._installed_cartridge.is_installed())
	_check("used cartridge still awaiting disposal, on the floor", is_instance_valid(h2._used_cartridge) and h2._used_cartridge.is_ejected() and h2._used_cartridge.visible)
	var p2: Node = main.get_node("Interactables/CargoPort")
	_check("cargo still mid-unload: %d parts in the port (was %d), restraint released" % [p2.parts_in_port(), port_before], p2.state == p2.PortState.UNLOADING and p2.parts_in_port() == port_before and p2._parts.all(func(p): return p.visible))
	var pn2: Node = main.get_node("Geometry/EngineeringCabinet1")
	_check("electrical fault kept (not re-rolled): config %d, procedure DISCONNECT" % pn2._config_index, pn2._config_index == 3 and pn2._procedure == pn2.ProcedureStage.DISCONNECT and pn2.required_component_id == &"wire_signal_22ga")
	_check("calibration drift kept", main.get_node("Interactables/SensorCalibrationStation").has_recorded_drift())
	_check("laptop entry kept", main.get_node("Player/LaptopView")._saved_entry == "Day 3: cargo half unloaded.")
	_check("player position kept", main.get_node("FreeMoveBody").global_position.distance_to(sg._dec(expected["player"]["pos"])) < 0.01)
	# The restored world keeps working: finish unloading and receive.
	var c2: Node = main.get_node("Interactables/SupplyCrate")
	carry.drop()
	await process_frame
	c2.interact()
	await create_timer(0.8).timeout
	for p in p2._parts.duplicate():
		if p2.in_port(p):
			_take(carry, p)
			_stow(carry, p, c2)
	p2.interact()
	_check("after load the shipment can be finished and received once", p2.state == p2.PortState.RECEIVED and p2.received_shipments == ["CS-0001"])

	# ---- Failure handling. ----
	var s2: Dictionary = sg.save_game()
	_check("second save keeps the previous file as backup", s2["ok"] and FileAccess.file_exists(PATH + ".bak"))
	_write(PATH, "{\"schema\": 1, \"game\": \"satellite_maintenance_horror\", \"day\": 3, \"items\": [")
	var fb: Dictionary = sg.read_save()
	_check("corrupt main save -> falls back to the backup", fb["ok"] and fb["from_backup"])
	_write(PATH, "")
	_write(PATH + ".tmp", "{\"partial")
	_check("interrupted write (empty main, stray tmp) -> backup still loads", sg.read_save()["ok"])
	var s3: Dictionary = sg.save_game()
	_check("saving again after an interrupted write works and clears the tmp", s3["ok"] and not FileAccess.file_exists(PATH + ".tmp") and sg.read_save()["ok"] and not sg.read_save()["from_backup"])
	var newer: Dictionary = sg.read_save()["data"].duplicate(true)
	newer["schema"] = 99
	_check("unsupported (newer) schema rejected with a clear reason", not sg.validate(newer)["ok"] and sg.validate(newer)["message"].find("newer") != -1)
	var dupd: Dictionary = sg.read_save()["data"].duplicate(true)
	dupd["items"].append(dupd["items"][0])
	_check("a save listing a part twice is rejected", not sg.validate(dupd)["ok"])
	var badref: Dictionary = sg.read_save()["data"].duplicate(true)
	badref["items"][0]["owner"] = {"kind": "warp"}
	_check("a part with an invalid owner is rejected", not sg.validate(badref)["ok"])
	var day_before: int = dp.day_number
	var bad: Dictionary = sg.apply_state(dupd)
	_check("a rejected load leaves the world untouched", not bad["ok"] and dp.day_number == day_before)
	_write(PATH, "garbage")
	_write(PATH + ".bak", "garbage")
	var none: Dictionary = sg.read_save()
	_check("both files corrupt -> load refused with a message ('%s')" % none["message"], not none["ok"] and none["message"].find("corrupt") != -1)
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _fresh() -> Node:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	m.get_node("SaveGame").save_path = PATH
	get_root().add_child(m)
	current_scene = m
	for i in 6: await process_frame
	return m


func _take(carry: Node, item: Node3D) -> void:
	if carry.is_carrying():
		carry.drop()
	carry.pick_up(item)
	if carry.is_reaching():
		carry.complete_grasp()


func _stow(carry: Node, item: Node3D, home: Node) -> void:
	carry._carried_item = null
	carry._carried_item_id = &""
	carry._release_physics(item)
	home.stow(item)


func _stock(m: Node) -> Array:
	var out: Array = []
	for t in [&"filter_cartridge", &"wire_control_16ga", &"wire_signal_22ga"]:
		out.append(m.get_node("Geometry/StorageCabinet1").stock_count(t) + m.get_node("Geometry/StorageCabinet2").stock_count(t))
		out.append(m.get_node("Interactables/SupplyCrate").reserve_count(t))
	return out


func _by_id(items: Array) -> Dictionary:
	var d := {}
	for rec in items:
		d[rec["id"]] = rec
	return d


func _same_owner(a: Dictionary, b: Dictionary) -> bool:
	if a["kind"] != b["kind"]:
		return false
	if a["kind"] == "loose":
		var xa: Array = a["xf"]["$xf"]
		var xb: Array = b["xf"]["$xf"]
		for i in 12:
			if absf(float(xa[i]) - float(xb[i])) > 0.002:
				return false
		return true
	return JSON.stringify(a) == JSON.stringify(b)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
