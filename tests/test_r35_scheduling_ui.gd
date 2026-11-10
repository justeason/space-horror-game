extends SceneTree
## Round 35: busier, multi-order workdays and the simplified workstation.
## Scheduling: progressive introduction of the new tasks, a time-weighted
## budget (quiet/normal/busy), determinism, no duplicate or incompatible
## orders, carry-over. UI: every Work Orders row is ONE short line, the
## optional details panel, the workstation Settings tab driving the SAME
## GameSettings as the main menu, and a one-objective wristwatch.
var _ok := true
const GS = preload("res://scripts/station/game_settings.gd")
var CFG: String = preload("res://scripts/station/game_settings.gd").settings_path()
var _cfg_backup: Variant = null

func _init() -> void:
	_cfg_backup = FileAccess.get_file_as_string(CFG) if FileAccess.file_exists(CFG) else null
	var main: Node = await _fresh()
	var dp: Node = main.get_node("DayPlan")
	var log_a: Array = []
	var max_open := 0
	var min_open := 99
	var types_seen := {}
	for d in range(2, 12):
		dp.reset_for_new_day()
		var open: Array = dp.open_orders()
		var tset := {}
		var dup := false
		for o in open:
			if tset.has(o["type"]): dup = true
			tset[o["type"]] = true
			types_seen[o["type"]] = true
		if dup:
			_check("day %d: no duplicate open order types" % dp.day_number, false)
		if dp.cargo_duty == "open" and tset.has("seal") and int(dp.orders.filter(func(x): return x["type"] == "seal" and x["status"] == "open")[0]["day"]) == dp.day_number:
			_check("day %d: no new hatch-seal order on a cargo day" % dp.day_number, false)
		var duties: int = dp.order_rows().filter(func(r): return not r.get("done", false)).size()
		max_open = maxi(max_open, duties)
		min_open = mini(min_open, duties)
		log_a.append([dp.day_number, dp.day_type, open.map(func(o): return o["type"])])
		if d == 2:
			_check("day 2 introduces the breaker task (gentle start)", tset.has("breaker") and dp.day_type == "quiet")
		if d == 6:
			_check("by day 6 the data-transfer task is introduced", types_seen.has("data"))
		# Resolve the day's work like a player would (cargo received, every
		# new order except the breaker fixed at its equipment); the breaker
		# order is left unfinished to exercise carry-over.
		_resolve_day(main, dp)
	print("schedule: ", log_a)
	_check("all five new task types were scheduled", ["breaker", "vent", "power", "seal", "data"].all(func(t): return types_seen.has(t)))
	_check("busier days: up to %d concurrent duties (target 3-7)" % max_open, max_open >= 4 and max_open <= 8)
	var carried: Array = dp.open_orders().filter(func(o): return int(o.get("carried_from", -1)) > 0)
	_check("unfinished orders carried over (%d), shown with ↺" % carried.size(), not carried.is_empty() and dp.order_rows().any(func(r): return r.get("carried", false)))
	# Determinism: a second fresh station, same days -> same schedule.
	main.queue_free()
	await process_frame
	var main2: Node = await _fresh()
	var dp2: Node = main2.get_node("DayPlan")
	var log_b: Array = []
	for d in range(2, 12):
		dp2.reset_for_new_day()
		log_b.append([dp2.day_number, dp2.day_type, dp2.open_orders().map(func(o): return o["type"])])
		_resolve_day(main2, dp2)
	_check("the schedule is deterministic (same days -> same orders)", JSON.stringify(log_a) == JSON.stringify(log_b))

	dp2.reset_for_new_day()   # a fresh day with open duties for the UI checks
	# ---- One-line Work Orders. ----
	var screen: Node = main2.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	screen.show_section(screen.Section.WORK_ORDERS)
	var rows: Array = screen.work_order_rows()
	var lines: Array = rows.map(func(r): return dp2.format_row(r))
	_check("%d duties listed, each ONE short line (<= 60 chars, no wrap)" % rows.size(), rows.size() >= 3 and lines.all(func(l): return l.find("\n") == -1 and l.length() <= 60))
	print("rows: ", lines)
	var label: Label = screen.get_node("Control/VBox/Content/WorkOrders/List")
	_check("the list shows exactly those lines", lines.all(func(l): return label.text.find(l) != -1))
	_check("rows name tag — action · room (e.g. '%s')" % lines[0], lines.all(func(l): return l.find(" — ") != -1))
	var ws: Node = main2.get_node("WorkstationState")
	ws.begin_use()
	var t0 := Time.get_ticks_msec()
	while not ws.is_in_use() and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	await _key(KEY_2)
	await _key(KEY_DOWN)
	_check("↓ selects the next row", screen._wo_sel == 1)
	var before: int = label.text.split("\n").size()
	await _key(KEY_ENTER)
	_check("Enter opens the optional details panel", screen._wo_details and label.text.split("\n").size() > before)
	await _key(KEY_ENTER)
	_check("Enter closes it again", not screen._wo_details)

	# ---- Workstation Settings == main-menu settings. ----
	await _key(KEY_6)
	_check("workstation [6] opens Settings with every shared option", screen.settings_rows().size() == 15)   # Round 36: + 3 assistant rows
	screen.settings_sel = 3   # SFX volume
	var v0: float = float(GS.get_value("vol_SFX"))
	await _key(KEY_LEFT)
	var v1: float = float(GS.get_value("vol_SFX"))
	var db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	_check("← lowers the SFX volume on the real bus (%.2f -> %.2f, %.1f dB)" % [v0, v1, db], v1 < v0 and absf(db - linear_to_db(maxf(v1, 0.0001))) < 0.2)
	var panel = preload("res://scripts/ui/settings_panel.gd").new()
	get_root().add_child(panel)
	await process_frame
	_check("the main-menu Settings panel shows the same value", absf(panel.sliders["SFX"].value - v1) < 0.001)
	panel.queue_free()
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	_check("persisted to game_settings.cfg (survives restart)", absf(float(cfg.get_value("player", "vol_SFX", -1.0)) - v1) < 0.001)
	screen.settings_sel = screen.settings_rows().map(func(r): return r[0]).find("language")
	await _key(KEY_RIGHT)
	_check("language change applies live on the workstation (%s)" % screen.settings_rows()[1][1], TranslationServer.get_locale().begins_with("zh") and screen.settings_rows()[1][1] == "主音量")
	await _key(KEY_LEFT)
	_check("the work-order list is untouched by settings changes", dp2.open_orders().size() > 0 and ws.is_in_use())
	await _key(KEY_ESCAPE)
	_check("Esc leaves the workstation (no pause menu)", not ws.is_in_use() and not main2.get_node("PauseMenu").is_open)

	# ---- Wristwatch: one objective. ----
	main2.get_node("Player/Wristwatch")._refresh_text()
	var face: Label3D = main2.get_node("Player/LookPivot/PitchPivot/Camera3D/FirstPersonWatchRig/ArmGroup/WatchAssembly/WatchFaceText")
	# Round 42: line 1 is the station CLOCK (day + time), then ONE objective
	# and its destination -- never a work percentage.
	_check("wristwatch shows the clock + ONE objective + destination ('%s')" % face.text.replace("\n", " / "), face.text.split("\n").size() == 3 and face.text.begins_with("DAY ") and face.text.split("\n")[0].find(":") != -1 and face.text.find(" · ") != -1 and face.text.find("%") == -1)
	_restore_cfg()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _resolve_day(m: Node, dp: Node) -> void:
	var port: Node = m.get_node("Interactables/CargoPort")
	if dp.cargo_duty == "open":
		port.received_shipments.append(dp.cargo_duty_id)
		port.state = port.PortState.SECURED
		for p in port._parts:
			if is_instance_valid(p): p.queue_free()
		port._parts = []
		dp.cargo_duty = "done"
	var eqs := {"vent": "VentGrille", "power": "PowerDistribution", "seal": "HatchSeal", "data": "UploadPort"}
	for o in dp.open_orders():
		match o["type"]:
			"vent":
				var v: Node = m.get_node("Equipment/VentGrille")
				v.load_dict({"dirt": [0, 0, 0, 0], "clips_released": [false, false], "cover_open": false, "airflow_checked": true})
			"power":
				var p: Node = m.get_node("Equipment/PowerDistribution")
				p.load_dict({"demand": p.demand, "setting": p.demand.duplicate(), "verified": true})
			"seal":
				var s: Node = m.get_node("Equipment/HatchSeal")
				s.load_dict({"faults": ["", "", "", ""], "inspected": [true, true, true, true], "inspection_mode": false, "test_state": "pass"})
			"data":
				var u: Node = m.get_node("Equipment/UploadPort")
				u.uploaded_day = dp.day_number
	dp._poll_orders()


func _fresh() -> Node:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	current_scene = m
	for i in 6: await process_frame
	return m


func _key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k; e.physical_keycode = k; e.pressed = true
	get_root().push_input(e)
	await process_frame
	var u := InputEventKey.new()
	u.keycode = k; u.physical_keycode = k; u.pressed = false
	get_root().push_input(u)
	await process_frame


func _restore_cfg() -> void:
	if _cfg_backup == null:
		if FileAccess.file_exists(CFG):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_string(_cfg_backup)
		f.close()
	GS._values_loaded = false


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
