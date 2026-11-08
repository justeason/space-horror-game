extends SceneTree
## Round 33 Priority 9: 20 days of real maintenance twice with the same
## per-day seeds -- a CONTROL run that never restarts, and a run that
## SAVES and RELOADS into a freshly built station every 5 days. The final
## DayPlan, equipment and every part's owner must be identical: save/load
## must not change the outcome of play.
var _ok := true
const PATH := "user://test_r33_20days.json"
var main: Node
var carry: Node

func _init() -> void:
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var control: Dictionary = await _run(false)
	var resumed: Dictionary = await _run(true)
	print("control: day %d, services %d, cargo %d" % [control["day"], control["day_plan_raw"]["service_history"].size(), control["day_plan_raw"]["cargo_history"].size()])
	_check("both runs reached day 21", control["day"] == 21 and resumed["day"] == 21)
	var a_dp: Dictionary = control["state"]["day_plan"].duplicate()
	var b_dp: Dictionary = resumed["state"]["day_plan"].duplicate()
	a_dp.erase("shift_elapsed_s")   # real-time clock: differs with run timing
	b_dp.erase("shift_elapsed_s")
	_check("DayPlan identical after 20 days with 4 save/load restarts", JSON.stringify(a_dp) == JSON.stringify(b_dp))
	_check("equipment identical", JSON.stringify(control["state"]["equipment"]) == JSON.stringify(resumed["state"]["equipment"]))
	var a := _owners(control["state"]["items"])
	var b := _owners(resumed["state"]["items"])
	var diff: Array = []
	for k in a:
		if not b.has(k) or a[k] != b[k]:
			diff.append("%s: %s vs %s" % [k, a[k], b.get(k, "missing")])
	for k in b:
		if not a.has(k):
			diff.append("%s only after restarts" % k)
	_check("every part has the same owner in both runs %s" % str(diff.slice(0, 5)), diff.is_empty())
	_check("work really happened (%d services, %d shipments)" % [control["day_plan_raw"]["service_history"].size(), control["day_plan_raw"]["cargo_history"].size()], control["day_plan_raw"]["service_history"].size() >= 12 and control["day_plan_raw"]["cargo_history"].size() >= 3)
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _run(restarts: bool) -> Dictionary:
	seed(424242)
	main = await _fresh()
	for c in ["Geometry/StorageCabinet1", "Geometry/StorageCabinet2", "Interactables/SupplyCrate"]:
		main.get_node(c).interact()
	await create_timer(1.0).timeout
	for day in range(2, 22):
		seed(1000 + day)
		await _work_day()
		if restarts and day % 5 == 0 and day < 21:
			var sg: Node = main.get_node("SaveGame")
			var r: Dictionary = sg.save_game()
			if not r["ok"]:
				_check("day %d save ('%s')" % [day, r["message"]], false)
			main.queue_free()
			await process_frame
			main = await _fresh()
			var ar: Dictionary = main.get_node("SaveGame").apply_state(main.get_node("SaveGame").read_save()["data"])
			if not ar["ok"]:
				_check("day %d load ('%s')" % [day, ar["message"]], false)
			for c in ["Geometry/StorageCabinet1", "Geometry/StorageCabinet2", "Interactables/SupplyCrate"]:
				main.get_node(c).interact()
			await create_timer(1.0).timeout
	var sgx: Node = main.get_node("SaveGame")
	var st: Dictionary = sgx.collect_state()
	var dp: Node = main.get_node("DayPlan")
	var out := {"day": dp.day_number, "state": st, "day_plan_raw": {"service_history": dp.service_history.duplicate(), "cargo_history": dp.cargo_history.duplicate()}}
	main.queue_free()
	await process_frame
	return out


func _work_day() -> void:
	var dp: Node = main.get_node("DayPlan")
	var W = dp.Workday
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var station: Node = main.get_node("Interactables/FilterHousingStation")
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var trash: Node = main.get_node("Interactables/TrashDisposal")
	var port: Node = main.get_node("Interactables/CargoPort")
	var crate: Node = main.get_node("Interactables/SupplyCrate")
	var cab1: Node = main.get_node("Geometry/StorageCabinet1")
	var cab2: Node = main.get_node("Geometry/StorageCabinet2")
	dp.reset_for_new_day()
	if port.state == port.PortState.ARRIVED:
		port.interact(); port.interact()
		await create_timer(1.6).timeout
		port.interact()
		for p in port._parts.duplicate():
			if port.in_port(p):
				_take(p)
				for h in [crate, cab1, cab2]:
					if h.accepts_item(p):
						_stow(p, h)
						break
		port.interact()
		port.interact()
		await create_timer(1.0).timeout
	for pair in [[cab2, &"filter_cartridge"], [cab1, &"wire_control_16ga"], [cab1, &"wire_signal_22ga"]]:
		var cab: Node = pair[0]
		while cab.stock_count(pair[1]) < cab.capacity(pair[1]) and crate.reserve_count(pair[1]) > 0:
			var src: Node3D = null
			for it in crate._items:
				if is_instance_valid(it) and it.item_id == pair[1] and crate.is_in_reserve(it):
					src = it
					break
			_take(src)
			_stow(src, cab)
	var wd: int = dp.workday
	if wd != W.NONE:
		screen.show_section(screen.Section.OVERVIEW)
		screen.run_action()
	match wd:
		W.FILTER_SERVICE:
			var cart: Node3D = _first_stowed(cab2, &"filter_cartridge")
			if cart != null:
				_take(cart)
				# Round 36: any service variant (loose/seized latch, cocked cartridge).
				preload("res://tests/filter_service_solver.gd").solve(station)
				await process_frame
				var used = station._used_cartridge
				if is_instance_valid(used):
					_take(used)
					trash.interact()
		W.ELECTRICAL_SERVICE:
			if panel._config_index == -1:
				panel._select_repair_config()
			var part: Node3D = _first_stowed(cab1, panel.required_component_id)
			if part != null:
				_take(part)
				panel._procedure = panel.ProcedureStage.REPLACE
				panel.install_replacement_wire()
				panel._repair_stage = panel.RepairStage.REPAIRED
				panel._procedure = panel.ProcedureStage.COMPLETE
				dp.mark_done(&"e05")
		W.CALIBRATION:
			dp.mark_done(&"l07")
		W.COOLANT_INSPECTION:
			dp.mark_done(&"l08")
		W.INSPECTION_ROUND, W.COMMS_CHECK:
			if wd == W.COMMS_CHECK:
				dp.mark_done(&"m02")
			for point in main.get_node("EquipmentStatusLamps").tags():
				if dp.WORKDAY_STEPS[wd].any(func(st): return st[3] == StringName("reading:%s" % point.inspect_id)):
					point.interact()
	if wd != W.NONE:
		screen.show_section(screen.Section.WORK_ORDERS)
		for k in 4:
			screen.run_action()
	await process_frame


func _fresh() -> Node:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	m.get_node("SaveGame").save_path = PATH
	get_root().add_child(m)
	current_scene = m
	for i in 6: await process_frame
	carry = m.get_node("Player/CarrySystem")
	return m


func _take(item: Node3D) -> void:
	if carry.is_carrying():
		carry.drop()
	carry.pick_up(item)
	if carry.is_reaching():
		carry.complete_grasp()


func _stow(item: Node3D, home: Node) -> void:
	carry._carried_item = null
	carry._carried_item_id = &""
	carry._release_physics(item)
	home.stow(item)


func _first_stowed(cab: Node, id: StringName) -> Node3D:
	for it in cab._items:
		if is_instance_valid(it) and it.item_id == id and cab.is_item_stowed(it):
			return it
	return null


func _owners(items: Array) -> Dictionary:
	var d := {}
	for rec in items:
		var o: Dictionary = rec["owner"]
		d[rec["id"]] = o["kind"] + "/" + String(o.get("at", "")) + "/" + JSON.stringify(o.get("slot", ""))
	return d


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
