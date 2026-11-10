extends SceneTree
## Round 36 Priority 5: STATION OPERATIONS ASSISTANT. Headless: speech
## backend is "none" (captions only) -- real speech playback is verified by
## tools/verify_station_ai_speech.gd on a real display. Covers: first-day
## greeting; captions; one line at a time; first-time equipment guidance on
## arrival; step-change narration from REAL equipment state; completion
## acknowledgement; no repeated lessons; held during focused views; safety
## priority; skip / repeat; voice off / muted / disabled; save/load of
## tutorial progress (no intro replay); legacy saves; new game resets;
## zh_CN captions; settings rows; gameplay never locked.
const GS = preload("res://scripts/station/game_settings.gd")
var _ok := true
var main: Node
var ai: Node
var dp: Node
var cam: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	ai = main.get_node("StationAI")
	dp = main.get_node("DayPlan")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	for k in ["ai_guidance", "ai_voice", "ai_captions"]:
		GS.set_value(k, true)
	GS.set_value("language", "en")
	await _intro()
	await _controls()
	await _equipment_guidance()
	await _focused_hold_and_safety()
	await _settings_paths()
	await _save_load()
	await _zh()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _wait_key(key: String, timeout: float = 8.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		if ai.history.any(func(h): return h["key"] == key):
			return true
		await process_frame
	return false


func _keys() -> Array:
	return ai.history.map(func(h): return h["key"])


func _intro() -> void:
	_check("speech backend reported honestly (headless: '%s')" % ai.speech_backend(), ai.speech_backend().begins_with("none"))
	var got: bool = await _wait_key("intro_greet")
	if not got:
		print("  dbg awake=%s enabled=%s alive=%.1f since=%.1f intro=%s hist=%s q=%d day=%d" % [ai._awake(), ai.enabled(), ai._alive_t, ai._awake_since, ai.intro_done, str(_keys()), ai._queue.size(), dp.day_number])
	_check("first-day greeting plays", got)
	_check("caption shows the greeting text ('%s')" % ai.caption_text(), ai.caption_text().find("Good morning, Technician") != -1)
	_check("one line at a time (queue holds the rest)", ai.is_showing() and ai._queue.size() >= 2)
	_check("the player is never locked while it speaks", cam.interactions_enabled)
	_check("intro continues: job + wristwatch + go to Control", await _wait_key("intro_control", 30.0) and _keys().has("intro_job") and _keys().has("intro_watch"))
	var n: int = _keys().filter(func(k): return k == "intro_greet").size()
	for i in 30: await process_frame
	_check("the greeting is not repeated (%d)" % n, _keys().filter(func(k): return k == "intro_greet").size() == 1)


func _controls() -> void:
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(&"filter_get")
	ai.say_key(&"data_capture")
	await process_frame
	await process_frame
	_check("a line is showing", ai.current_key() == &"filter_get")
	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await create_timer(0.8).timeout
	_check("J skips to the next line (%s)" % ai.current_key(), ai.current_key() == &"data_capture")
	ai.clear_queue()
	await create_timer(0.8).timeout
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_H
	ev2.pressed = true
	Input.parse_input_event(ev2)
	await process_frame
	await create_timer(0.8).timeout
	_check("H repeats the last instruction (%s)" % ai.current_key(), ai.current_key() == &"data_capture")
	_check("a taught lesson is not queued again", not ai.say_key(&"filter_get"))
	ai.clear_queue()
	# Voice off -> captions only; Voice volume 0 -> muted; disabled -> nothing.
	GS.set_value("ai_voice", false)
	await create_timer(0.8).timeout
	ai.say_key(&"cargo_return")
	await create_timer(0.2).timeout
	_check("voice off: caption still shown, no speech ('%s')" % ai._current.get("backend", ""), ai.caption_text() != "" and String(ai._current.get("backend", "")).begins_with("captions only"))
	GS.set_value("ai_voice", true)
	var vol: float = float(GS.get_value("vol_Voice"))
	GS.set_value("vol_Voice", 0.0)
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(&"disposal_intro")
	await create_timer(0.2).timeout
	_check("Voice volume 0 mutes speech ('%s')" % ai._current.get("backend", ""), String(ai._current.get("backend", "")).begins_with("muted"))
	GS.set_value("vol_Voice", vol)
	ai.set_enabled(false)
	await process_frame
	_check("disabled: line stopped, caption hidden", not ai.is_showing() and ai.caption_text() == "")
	_check("disabled: nothing is queued", not ai.say_key(&"storage_intro"))
	ai.set_enabled(true)
	GS.set_value("ai_captions", false)
	ai.say_key(&"storage_intro")
	await create_timer(0.8).timeout
	_check("captions off: line plays without a caption panel", ai.is_showing() and ai.caption_text() == "")
	GS.set_value("ai_captions", true)
	ai.clear_queue()


func _stand(eye: Vector3, target: Vector3) -> void:
	var fb: Node = main.get_node("FreeMoveBody")
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for i in 4: await physics_frame
	var d: Vector3 = target - cam.global_position
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y


func _equipment_guidance() -> void:
	var vent: Node3D = main.get_node("Equipment/VentGrille")
	dp._order_seq += 1
	dp.orders.append({"id": "WO-T%d" % dp._order_seq, "type": "vent", "category": "B", "priority": 2, "day": dp.day_number, "seed": 9, "status": "open", "carried_from": -1})
	vent.order_rearm(9)
	await create_timer(0.8).timeout
	_check("no vent lesson while the player is elsewhere", not _keys().has("vent_intro"))
	await _stand(vent.global_transform * Vector3(0, 0.5, 0.9), vent.global_position)
	_check("first arrival at the grille: 'release both clips' lesson", await _wait_key("vent_intro"))
	vent.on_part(&"gauge")
	vent.on_part(&"c0"); vent.on_part(&"c1")
	_check("step narration follows real state: clips released -> 'open the grille'", await _wait_key("vent_open"))
	vent.on_part(&"cover")
	_check("cover open -> 'remove debris'", await _wait_key("vent_clean"))
	for i in 4:
		for k in 3:
			vent.on_part(StringName("s%d" % i))
	_check("cleaned -> 'close the grille and secure both clips'", await _wait_key("vent_close"))
	vent.on_part(&"cover"); vent.on_part(&"c1"); vent.on_part(&"c0")
	_check("done -> 'Airflow restored.'", await _wait_key("vent_done", 15.0))
	# A second vent order on a later service: no lesson replay.
	ai.clear_queue()
	var before: int = ai.history.size()
	dp._order_seq += 1
	dp.orders.append({"id": "WO-T%d" % dp._order_seq, "type": "vent", "category": "B", "priority": 2, "day": dp.day_number, "seed": 10, "status": "open", "carried_from": -1})
	vent.order_rearm(10)
	vent.on_part(&"gauge"); vent.on_part(&"c0"); vent.on_part(&"c1"); vent.on_part(&"cover")
	await create_timer(1.5).timeout
	var vent_keys: Array = ai.history.slice(before).map(func(h): return h["key"]).filter(func(k): return String(k).begins_with("vent"))
	_check("second vent service: no tutorial replay (%s)" % str(vent_keys), vent_keys.is_empty())
	vent.on_part(&"cover"); vent.on_part(&"c0"); vent.on_part(&"c1")
	vent.dirt = [0.0, 0.0, 0.0, 0.0]
	vent._refresh()
	# Breaker panel lesson only once a breaker order is open.
	var br: Node3D = main.get_node("Equipment/BreakerPanel")
	await _stand(br.global_transform * Vector3(0, 0.15, 0.9), br.global_position)
	await create_timer(1.0).timeout
	_check("no breaker lesson without a breaker task", not _keys().has("breaker_intro"))
	dp._order_seq += 1
	dp.orders.append({"id": "WO-T%d" % dp._order_seq, "type": "breaker", "category": "A", "priority": 3, "day": dp.day_number, "seed": 1, "status": "open", "carried_from": -1})
	br.order_rearm(1)
	_check("breaker task open + at the panel -> breaker lesson", await _wait_key("breaker_intro"))
	for i in 4:
		if not br.on[i]:
			br.on_part(StringName("b%d" % i))
	_check("breaker reset -> 'Power restored. The circuit is operating normally.'", await _wait_key("breaker_done", 15.0))


func _focused_hold_and_safety() -> void:
	ai.clear_queue()
	await create_timer(0.8).timeout
	var st: Node = main.get_node("Interactables/FilterHousingStation")
	await _stand(st.global_position + Vector3(0.8, 0.2, 0.0), st.global_position)
	st.interact()
	await process_frame
	_check("focused filter view open", main.get_node("FocusedInteractionState").is_active())
	ai.say_key(&"calib_intro")
	await create_timer(1.0).timeout
	_check("instruction held while a focused view is open", not ai.is_showing())
	ai.say_key(&"overload_warn")
	await create_timer(0.3).timeout
	_check("a SAFETY line still plays over it", ai.current_key() == &"overload_warn")
	main.get_node("FocusedInteractionState").end()
	await _wait_key("calib_intro", 12.0)
	_check("the held instruction plays once the view closes", _keys().has("calib_intro"))
	# Safety interrupts an instruction.
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(&"coolant_intro")
	await create_timer(0.3).timeout
	ai.say_key(&"interlock_cargo")
	await process_frame
	await process_frame
	_check("safety interrupts a lower-priority line (%s)" % ai.current_key(), ai.current_key() == &"interlock_cargo")
	_check("safety lines respect a cooldown (no spam)", not ai.say_key(&"interlock_cargo"))
	# A real breaker trip mid-day raises an outage announcement.
	ai.clear_queue()
	var br: Node = main.get_node("Equipment/BreakerPanel")
	br.trip(1, "surge")
	_check("real outage announced (safety)", await _wait_key("outage"))
	br.on_part(&"b1")


func _settings_paths() -> void:
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	var keys: Array = screen.settings_rows().map(func(r): return r[0])
	_check("workstation Settings has assistant guidance/voice/captions", keys.has("ai_guidance") and keys.has("ai_voice") and keys.has("ai_captions"))
	var panel = preload("res://scripts/ui/settings_panel.gd").new()
	get_root().add_child(panel)
	await process_frame
	_check("menu Settings panel has the three assistant toggles", ["ai_guidance", "ai_voice", "ai_captions"].all(func(k): return panel.ai_checks.has(k)))
	panel.queue_free()


func _save_load() -> void:
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_station_ai.json"
	var r: Dictionary = sg.save_game()
	_check("save: %s" % r["message"], r["ok"])
	var data: Dictionary = sg.read_save()["data"]
	var sai: Dictionary = sg._dec(data["station_ai"]) if data.has("station_ai") else {}
	_check("tutorial progress saved (%d taught)" % Array(sai.get("taught", [])).size(), Array(sai.get("taught", [])).has("vent_intro") and bool(sai.get("intro_done", false)))
	# Fresh station (as a load does): load restores progress, no intro.
	main.queue_free()
	await process_frame
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 4: await process_frame
	ai = main.get_node("StationAI")
	dp = main.get_node("DayPlan")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_check("NEW GAME (fresh station): nothing taught yet", ai.taught.is_empty() and not ai.intro_done)
	main.get_node("SaveGame").apply_state(data)
	await create_timer(4.0).timeout
	_check("loaded: lessons remembered, intro NOT replayed", ai.taught.has(&"vent_intro") and not _keys().has("intro_greet"))
	# Legacy (pre-Round-36) save: no station_ai section.
	var legacy: Dictionary = data.duplicate(true)
	legacy.erase("station_ai")
	main.get_node("SaveGame").apply_state(legacy)
	_check("legacy save: treated as already oriented (no intro replay)", ai.intro_done)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_station_ai.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_station_ai.json.bak"))


func _zh() -> void:
	GS.set_value("language", "zh_CN")
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(&"seal_test", [], -1)
	await create_timer(0.3).timeout
	_check("zh_CN captions ('%s')" % ai.caption_text(), ai.caption_text().find("保压测试") != -1)
	GS.set_value("language", "en")
	ai.clear_queue()


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
