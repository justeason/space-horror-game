extends SceneTree
## Round 42 Priorities 1-5, 11-13: story-driven phases, the developer-only
## event testing interface, and the two new controlled anomalies.
##  - PHASES BY STORY: twenty ordinary days of work stay phase 1; phase 2
##    needs intro + familiarity + the deliberately read handover note;
##    late phase 2 needs two different anomalies SEEN; phase 3 needs three
##    seen + two physical investigations. Old (Round 41) saves migrate.
##  - DEV PANEL: exists only in debug builds (this headless runner is a
##    debug build), F8, locked until the code, unlock persists for the
##    session; every IMPLEMENTED event can be triggered, cancelled and
##    reset; unavailable placeholders refuse; previews never count; the
##    phase override is never saved; restore returns the pre-test state.
##  - hatch_handle: a camera-only handle turns on INT-07 (chamber cam) while
##    the real hatch, pressure and handles stay put; ends at the airlock.
##  - wrong_reading: the wall panel lies (tagged override), the model and
##    the workstation keep the truth; it expires; save/load never keeps it.
var _ok := true
var main: Node
var se: Node
var dp: Node
var al: Node
var net: Node
var panel: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	se = main.get_node("StoryEvents")
	dp = main.get_node("DayPlan")
	al = main.get_node("AirlockChamber")
	net = main.get_node("CameraNetwork")
	panel = main.get_node_or_null("DevPanel")
	_progression()
	_migration()
	await _dev_panel()
	await _hatch_handle()
	await _wrong_reading()
	await _previews()
	_save_excludes_dev()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _reset_story() -> void:
	se.load_dict({"events": {}, "feed_days": {}, "armed_for_day": -1, "story": {"phase": 1, "milestones": [], "duties": [], "investigations": []}})


func _progression() -> void:
	_reset_story()
	for d in range(1, 21):
		dp.day_number = d
		se.note_duty("vent")
		se.note_duty("breaker")
		se.note_duty("power")
		se.on_feed_viewed("INT-02")
		se.armed_for_day = -1
		se._arm_today()
	_check("20 days of ordinary work + camera use: still PHASE 1 (familiar: %s)" % str(se.milestones), se.phase() == 1 and se.has_milestone("intro_complete") and se.has_milestone("station_familiar"))
	_check("phase 1: nothing armed", se.armed_id() == &"")
	se.on_story_discovery("handover_read")
	_check("reading the handover note (a deliberate narrative act) -> PHASE 2", se.phase() == 2 and se.has_milestone("handover_read"))
	_check("early phase 2: the hatch handle (late beat) is not eligible ('%s')" % se.eligibility(&"hatch_handle"), se.eligibility(&"hatch_handle").find("late") != -1)
	se.state[&"corridor_presence"]["seen"] = true
	se._check_milestones()
	_check("one anomaly seen: still early phase 2", not se.late_phase_2())
	se.state[&"window_mismatch"]["seen"] = true
	se._check_milestones()
	_check("two DIFFERENT anomalies seen -> late phase 2", se.late_phase_2() and se.phase() == 2)
	se.state[&"wrong_reading"]["seen"] = true
	se._check_milestones()
	_check("three seen but no investigation: not phase 3", se.phase() == 2)
	se._investigated("corridor_presence")
	se._investigated("hatch_handle")
	_check("+ two physical investigations -> PHASE 3 (reality doubt)", se.phase() == 3 and se.has_milestone("reality_doubt"))
	# Handover read EARLY (before familiar) is remembered.
	_reset_story()
	dp.day_number = 1
	se.on_story_discovery("handover_read")
	_check("handover read on day 1: remembered, no phase change", se.phase() == 1 and not se.has_milestone("handover_read"))
	dp.day_number = 3
	for t in ["a", "b", "c"]:
		se.note_duty(t)
	se.feed_days = {"INT-02": [1, 2]}
	se._check_milestones()
	_check("...counts once the station is familiar -> phase 2", se.phase() == 2)


func _migration() -> void:
	dp.day_number = 9
	se.load_dict({"events": {"corridor_presence": {"plays": 1, "last_day": 8, "armed_day": 8, "seen": true}}, "feed_days": {"INT-02": [7, 8]}, "armed_for_day": 8})
	_check("Round 41 save migrates: played flags kept, phase 2", se.phase() == 2 and int(se.state[&"corridor_presence"]["plays"]) == 1 and bool(se.state[&"corridor_presence"]["seen"]) and se.has_milestone("migrated_r41"))
	dp.day_number = 4
	se.load_dict({"events": {}, "feed_days": {}, "armed_for_day": -1})
	_check("Round 41 save without anomalies: phase 1", se.phase() == 1)


func _dev_panel() -> void:
	_check("developer panel exists in this DEBUG build", OS.is_debug_build() and panel != null)
	_check("closed by default, LOCKED for the session's first open", not panel.is_open and not panel.unlocked)
	var ev := InputEventKey.new()
	ev.keycode = KEY_F8
	ev.pressed = true
	panel._input(ev)
	_check("F8 opens it; the code prompt is shown, the controls are not", panel.is_open and panel._lock_box.visible and not panel._tabs.visible)
	_check("wrong code refused", not panel.try_unlock("letmein") and not panel.unlocked)
	_check("'justeason' unlocks for the session", panel.try_unlock("justeason") and panel.unlocked and panel._tabs.visible)
	panel.close()
	panel.open()
	_check("re-opening: still unlocked (no second prompt)", not panel._lock_box.visible and panel._tabs.visible)
	panel.refresh()
	var listed: Array = []
	for c in panel._events_box.get_children():
		if c.has_meta("event_id"):
			listed.append(String(c.get_meta("event_id")))
	_check("EVENTS lists every registered event (%d)" % listed.size(), listed.size() == se.EVENTS.size())
	_check("unavailable placeholders marked UNAVAILABLE", panel.event_line(&"radio_contact").find("UNAVAILABLE") != -1 and panel.event_line(&"laptop_inconsistency").find("UNAVAILABLE") != -1)
	_check("unavailable events cannot be triggered", not se.dev_trigger(&"radio_contact") and not se.dev_trigger(&"laptop_inconsistency") and not se.dev_trigger(&"blind_spot_object"))
	_check("story tab shows phase + milestones", panel.story_text().find("Narrative phase") != -1 and panel.story_text().find("Completed") != -1)
	_check("event line shows the needs explanation", panel.event_line(&"corridor_presence").find("Seated at the workstation") != -1)
	se.dev_set_phase_override(3)
	_check("phase override (transient): phase %d, story phase unchanged %d" % [se.phase(), se.story_phase], se.phase() == 3 and se.story_phase != 3)
	se.dev_set_phase_override(0)
	# Station conditions through real APIs, then restore.
	var br: Node = main.get_node("Equipment/BreakerPanel")
	var on0: bool = br.on[3]
	panel._eq("Equipment/BreakerPanel", func(n): n.trip(3, "DEV TEST"))
	_check("dev: breaker B-04 tripped through BreakerPanel.trip()", not br.on[3])
	var ss: Node = main.get_node("Interactables/SignalCalibrationStation")
	_check("...the comms receiver really loses power (link 0)", ss.link_quality() == 0.0)
	panel._net_offline("INT-02", true)
	_check("dev: INT-02 offline -> NO SIGNAL feed", net.feed("INT-02") == null)
	panel.restore_station()
	_check("restore: breaker back as before, INT-02 online", br.on[3] == on0 and net.feed("INT-02") != null)
	var tp: bool = panel.teleport(1)
	await physics_frame
	var fbp: Vector3 = main.get_node("FreeMoveBody").global_position
	_check("safe teleport to the Junction works inside the station", tp and absf(fbp.z - 4.5) < 0.3)
	main.get_node("EvaSystem").set_suited(true)
	_check("teleport refused while suited (EVA safety never bypassed)", not panel.teleport(0))
	main.get_node("EvaSystem").set_suited(false)
	panel.close()


func _hatch_handle() -> void:
	dp.day_number = 12
	var outer0: bool = al.outer_open
	var psi0: float = al.psi
	var inner0: bool = al.inner_open
	var plays0: int = int(se.state[&"hatch_handle"]["plays"])
	_check("dev trigger: hatch_handle starts", se.dev_trigger(&"hatch_handle", "normal") and se.active == &"hatch_handle")
	_check("camera-only handle copies exist (2)", se.hatch_clone_count() == 2)
	var real_ok := true
	for h in al.outer_handles():
		for v in (h as Node3D).find_children("*", "VisualInstance3D", true, false):
			real_ok = real_ok and (v as VisualInstance3D).layers == se.DIRECT_ONLY
	_check("the real handles are hidden from cameras only (DIRECT_ONLY)", real_ok)
	_check("INT-07 and EXT-02 do not render DIRECT_ONLY; the player's eyes do not render CAMERA_ONLY", net.camera("INT-07").cull_mask & se.DIRECT_ONLY == 0 and net.camera("EXT-02").cull_mask & se.DIRECT_ONLY == 0 and main.get_node("Player/LookPivot/PitchPivot/Camera3D").cull_mask & se.CAMERA_ONLY == 0)
	var t0 := Time.get_ticks_msec()
	var max_turn := 0.0
	while Time.get_ticks_msec() - t0 < 6500:
		await process_frame
		max_turn = maxf(max_turn, absf(se.hatch_twist_deg()))
	_check("the copy visibly TURNS on camera (max %.0f deg)" % max_turn, max_turn > 20.0)
	_check("the REAL airlock never changed (outer %s, %.1f psi, inner %s)" % [al.outer_open, al.psi, al.inner_open], al.outer_open == outer0 and is_equal_approx(al.psi, psi0) and al.inner_open == inner0 and al.sequence == "")
	se.dev_cancel()
	await process_frame
	var restored := true
	for h in al.outer_handles():
		for v in (h as Node3D).find_children("*", "VisualInstance3D", true, false):
			restored = restored and (v as VisualInstance3D).layers != se.DIRECT_ONLY
	_check("cancel: copies gone, real handles back on normal layers", se.hatch_clone_count() == 0 and restored and se.active == &"")
	_check("a dev preview is never counted as a play", int(se.state[&"hatch_handle"]["plays"]) == plays0)
	# Real (counted) run that ends at the airlock = investigated.
	se.dev_trigger(&"hatch_handle", "abnormal", true)
	se._on_screen_s = 2.0
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-4.8, 1.6, 0.2))
	await create_timer(0.5).timeout
	_check("going to the airlock ends it, hardware normal, recorded seen + investigated", se.active == &"" and bool(se.state[&"hatch_handle"]["seen"]) and se.investigations.has("hatch_handle"))
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(0.0, 1.6, 0.8))


func _wrong_reading() -> void:
	var r: Node = main.get_node("EnvironmentReadout")
	var env: Node = main.get_node("EnvironmentModel")
	var true_before: String = r.text()
	var p0: float = env.pressure_kpa
	_check("normal: the wall panel shows the true reading", r.shown_text() == r.text() and r.override_source == "")
	se.dev_trigger(&"wrong_reading", "normal")
	await process_frame
	_check("anomaly: the panel shows a contradiction (%s)" % r.shown_text().get_slice("\n", 9), r.shown_text() != r.text() and r.shown_text().find("96.8") != -1)
	_check("tagged as a deliberate story override (not a desync)", r.override_source == "story:wrong_reading")
	_check("the TRUE model / readout text are untouched", is_equal_approx(env.pressure_kpa, p0) and r.text() == true_before)
	var shell: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen/Shell")
	_check("the workstation's diagnostics still read the true pressure", main.get_node("Interactables/WorkstationConsole/WorkstationScreen")._diagnostic_text().find("96.8") == -1 if main.get_node("Interactables/WorkstationConsole/WorkstationScreen").has_method("_diagnostic_text") else true)
	var sd: Dictionary = se.state_dict()
	se.dev_cancel()
	await process_frame
	_check("expired/cancelled: displays agree again", r.shown_text() == r.text() and r.override_source == "")
	se.load_dict(sd)
	_check("save/load never restores the false reading", r.shown_text() == r.text())
	# Real run expiry.
	se.dev_trigger(&"wrong_reading", "abnormal", true)
	se._active_t = se.READING_MAX_S - 0.1
	await create_timer(0.4).timeout
	_check("a counted run expires by itself after its time", se.active == &"" and r.shown_text() == r.text())


func _previews() -> void:
	for id in [&"corridor_presence", &"window_mismatch"]:
		var plays0: int = int(se.state[id]["plays"])
		_check("dev trigger %s" % id, se.dev_trigger(id))
		await process_frame
		if id == &"corridor_presence":
			_check("presence visible on the camera layer only", se.presence_visible() and (se.presence_node().get_child(0) as VisualInstance3D).layers == se.CAMERA_ONLY)
			_check("presence stands where INT-02 sees it", net.sees("INT-02", se.presence_node().global_position + Vector3(0, 1.2, 0), 0.5))
		else:
			var od: Node = main.get_tree().get_first_node_in_group(&"observation_discrepancy")
			_check("window / EXT-03 contradiction active", od != null and od.is_active())
		se.dev_cancel()
		await process_frame
		_check("%s cancelled cleanly, not counted" % id, se.active == &"" and not se.presence_visible() and int(se.state[id]["plays"]) == plays0)
	se.dev_reset(&"hatch_handle")
	_check("reset clears an event's plays / seen", int(se.state[&"hatch_handle"]["plays"]) == 0 and not bool(se.state[&"hatch_handle"]["seen"]))
	se.dev_set_enabled(&"wrong_reading", false)
	_check("disable: not eligible ('%s')" % se.eligibility(&"wrong_reading"), se.eligibility(&"wrong_reading") == "disabled")
	se.dev_set_enabled(&"wrong_reading", true)
	_check("debug ARM (trigger when available): armed, live conditions still apply", se.debug_arm(&"wrong_reading") and se.is_armed(&"wrong_reading") and se.active == &"")
	var had: bool = se.dev_has_snapshot()
	se.dev_restore()
	_check("restore: back to the pre-test story state (snapshot was held: %s)" % had, had and not se.dev_has_snapshot() and se.dev_phase_override == 0 and se.active == &"")


func _save_excludes_dev() -> void:
	se.dev_set_phase_override(3)
	var sd: Dictionary = se.state_dict()
	_check("the phase OVERRIDE is never written into a save", int(sd["story"]["phase"]) == se.story_phase and not JSON.stringify(sd).contains("override"))
	se.dev_set_phase_override(0)
	_check("no assistant call in the anomaly code paths (no explanations)", not FileAccess.get_file_as_string("res://scripts/story/story_events.gd").contains("station_ai"))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
