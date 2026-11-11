extends SceneTree
## Round 44 Priorities 4 / 6-10 / 17: records, sounds, investigations.
##  - station logs written by REAL equipment changes (airlock cycle, camera
##    offline, hourly environment, first room entries), shown on the
##    workstation RECORDS tabs;
##  - ordinary operations play FROM their equipment and are logged;
##    nothing is played in bursts;
##  - phantom airlock cycle: heard from the airlock, no state change, NO
##    log entry -> going there is a check, the AIRLOCK record is the
##    contradiction (journal + inner thought);
##  - access-log ghost entry: presentation only (authentic log unchanged),
##    thought only if the room really wasn't visited;
##  - family letter misremembering: overlay only, Sent letters authentic;
##  - inner voice: once per id, never over the assistant, captions;
##  - chapter one completes through a contradiction (or the quiet route).
var _ok := true
var main: Node
var dp: Node
var se: Node
var lg: Node
var snd: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	# Round 45: this suite tests mechanics, not story access -- full
	# technician clearance (EVA / Comms gates open; gating has its own test).
	main.get_node("DayPlan/Clearance").load_dict({"level": 3})
	dp = main.get_node("DayPlan")
	se = main.get_node("StoryEvents")
	lg = main.get_tree().get_first_node_in_group(&"station_log")
	snd = main.get_tree().get_first_node_in_group(&"station_sounds")
	main.get_node("StationAI").set_enabled(false)
	await _logs()
	await _sounds()
	await _phantom()
	await _access_and_family()
	await _voice_and_chapter()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _logs() -> void:
	var al: Node = main.get_node("AirlockChamber")
	await create_timer(0.4).timeout
	var n0: int = lg.entries["airlock"].size()
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-4.8, 1.6, -1.45))
	main.get_node("EvaSystem").set_suited(true)
	await create_timer(0.3).timeout
	al.begin_cycle_out()
	for i in 200:
		if al.sequence == "":
			break
		await create_timer(0.1).timeout
	await create_timer(0.4).timeout
	var txt: String = "\n".join(lg.lines("airlock", 30))
	_check("airlock log: a real cycle is recorded (start, hatches, vent, complete)", lg.entries["airlock"].size() > n0 + 3 and txt.find("Cycle OUT started") != -1 and txt.find("vented") != -1 and txt.find("Outer hatch opened") != -1 and txt.find("Cycle OUT complete") != -1)
	al.reset_default()
	main.get_node("EvaSystem").set_suited(false)
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(0.0, 1.6, 0.5))
	var net: Node = main.get_node("CameraNetwork")
	net.offline["INT-04"] = true
	await create_timer(0.4).timeout
	net.offline.erase("INT-04")
	await create_timer(0.4).timeout
	_check("camera log: offline + restored", lg.has_entry("camera", "INT-04 feed OFFLINE") and lg.has_entry("camera", "INT-04 feed restored"))
	dp.shift_elapsed_s += dp.shift_duration_s() / 8.0 + 2.0
	await create_timer(0.4).timeout
	_check("environment log: one line per station hour (%s)" % str(lg.entries["environment"].back()["text"] if not lg.entries["environment"].is_empty() else ""), lg.has_entry("environment", "Cabin"))
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-6.5, 1.6, 8.0))
	await create_timer(0.5).timeout
	_check("access log: first entry into Storage today", lg.has_entry("access", "STORAGE · entered", dp.day_number) and lg.visited_today(&"storage"))
	var n_acc: int = lg.entries["access"].size()
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-6.5, 1.6, 7.0))
	await create_timer(0.4).timeout
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-6.5, 1.6, 8.0))
	await create_timer(0.4).timeout
	_check("...not spammed on re-entry", lg.entries["access"].size() <= n_acc + 1)
	var shell: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen").shell
	shell.show_page(shell.Page.RECORDS)
	shell.select_record_tab("airlock")
	_check("workstation RECORDS: AIRLOCK tab shows the log", shell._records.text.find("AIRLOCK ACTIVITY") != -1 and shell._records.text.find("Cycle OUT") != -1)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(lg.state_dict()))
	var cnt: int = lg.entries["airlock"].size()
	lg.load_dict({})
	lg.load_dict(sd)
	_check("logs survive save/load", lg.entries["airlock"].size() == cnt and lg.visited_today(&"storage"))


func _sounds() -> void:
	var h0: int = snd.heard.size()
	var e0: int = lg.entries["environment"].size()
	snd.run_operation("relay")
	var last: Dictionary = snd.heard.back()
	_check("ordinary op: relay self-test heard FROM the Engineering breaker panel", snd.heard.size() == h0 + 1 and bool(last["real"]) and (last["pos"] as Vector3).distance_to(Vector3(-5.6, 1.5, 3.75)) < 0.5)
	_check("...and it is on record (environment log)", lg.entries["environment"].size() == e0 + 1 and lg.has_entry("environment", "relay self-test"))
	snd.run_operation("fan")
	_check("fan speed change logged at Life Support", lg.has_entry("environment", "Life Support fan"))
	_check("ordinary ops are paced (min gap %.0f s, <= %d a day)" % [snd.MIN_GAP_S, snd.MAX_OPS_PER_DAY], snd._gap >= snd.MIN_GAP_S)
	var br: Node = main.get_node("Equipment/BreakerPanel")
	var snap: Dictionary = br.state_dict()
	br.trip(3, "TEST")
	_check("a real breaker trip is heard from the breaker panel", (snd.heard.back()["pos"] as Vector3).distance_to(br.global_position) < 0.1 and snd.heard.back()["kind"] == "breaker")
	br.load_dict(snap)


func _phantom() -> void:
	se.story_phase = 2
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(0.0, 1.6, 0.5))
	await create_timer(0.3).timeout
	var al: Node = main.get_node("AirlockChamber")
	var inner0: bool = al.inner_open
	var log0: int = lg.entries["airlock"].size()
	_check("phantom: developer trigger", se.dev_trigger(&"phantom_cycle", "normal", true))
	await create_timer(6.5).timeout
	var ph: Array = snd.heard.filter(func(h): return not bool(h["real"]))
	_check("phantom sounds came FROM the airlock (%d)" % ph.size(), ph.size() >= 3 and ph.all(func(h): return (h["pos"] as Vector3).distance_to(snd.AIRLOCK_POS) < 0.1))
	_check("...nothing changed: hatch, pressure, no sequence", al.inner_open == inner0 and al.sequence == "" and al.psi > 14.0)
	_check("...and NOTHING was logged", lg.entries["airlock"].size() == log0)
	_check("heard = noticed (observation, journal)", se.investigation_state("phantom_cycle") == "observed" and main.get_tree().get_first_node_in_group(&"journal").has("obs:phantom_cycle"))
	main.get_node("FreeMoveBody").sync_to_eye_position(Vector3(-4.8, 1.6, -1.2))
	await create_timer(0.6).timeout
	_check("going to the airlock = a physical check", se.investigation_state("phantom_cycle") == "checked")
	var shell: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen").shell
	shell.select_record_tab("airlock")
	_check("the AIRLOCK record contradicts it", se.investigation_state("phantom_cycle") == "contradicted" and main.get_tree().get_first_node_in_group(&"journal").has("contra:phantom_cycle:airlock_log"))
	var iv: Node = main.get_tree().get_first_node_in_group(&"inner_voice")
	_check("inner thoughts queued: heard + record ('%s')" % str(iv.said.keys()), iv.said.has("heard_phantom") and iv.said.has("airlock_log"))
	se.dev_reset(&"phantom_cycle")
	_check("developer reset clears the event state", int(se.state[&"phantom_cycle"]["plays"]) == 0)


func _access_and_family() -> void:
	lg.rooms_today = {}
	var real_before: Array = lg.entries["access"].duplicate(true)
	se.dev_trigger(&"access_ghost", "normal", true)
	var shown: Array = lg.display_entries("access", 30)
	_check("access ghost: an extra line is DISPLAYED (overlay)", shown.any(func(e): return bool(e["overlay"]) and String(e["text"]).find("entered") != -1))
	_check("...the authentic access history is unchanged", lg.entries["access"] == real_before)
	var shell: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen").shell
	shell.select_record_tab("access")
	var iv: Node = main.get_tree().get_first_node_in_group(&"inner_voice")
	_check("reading it (room not visited) -> seen + contradiction + thought", bool(se.state[&"access_ghost"]["seen"]) and se.investigation_state("access_ghost") == "contradicted" and iv.said.has("access_log"))
	var q: Array = iv.queue.filter(func(x): return x["id"] == "access_log")
	_check("thought names the room ('%s')" % (q[0]["text"] if not q.is_empty() else ""), not q.is_empty() and String(q[0]["text"]).find("haven't been in") != -1)
	se.dev_cancel()
	_check("cancel removes the overlay", not lg.display_entries("access", 30).any(func(e): return bool(e["overlay"])))
	# Family misremembering.
	var fm: Node = main.get_tree().get_first_node_in_group(&"family_mail")
	dp.day_number = 2
	fm.reply("mara_eating", "A")
	dp.day_number = 3
	var authentic: String = "\n".join(fm.thread_lines("mara_eating"))
	se.dev_trigger(&"family_misremember", "normal", true)
	var shown2: String = "\n".join(fm.thread_lines("mara_eating"))
	_check("family overlay: the answer quotes a detail never written", shown2.find("corridor light") != -1 and authentic.find("corridor light") == -1)
	_check("...the stored reply is still A", fm.threads["mara_eating"]["choice"] == "A" and "\n".join(fm.sent_lines()).find("Just busy") != -1)
	se.on_letter_opened("mara_eating")
	se.on_record_viewed("sent_mail")
	_check("letter seen + Sent letters checked -> contradiction", se.investigation_state("family_misremember") == "contradicted")
	se.dev_cancel()
	_check("after cancel the letter reads as written", "\n".join(fm.thread_lines("mara_eating")).find("corridor light") == -1)
	var data: Dictionary = main.get_node("SaveGame").collect_state()
	_check("no overlay text ever reaches the save", not JSON.stringify(data).contains("corridor light keeps you awake"))
	dp.day_number = 1


func _voice_and_chapter() -> void:
	var iv: Node = main.get_tree().get_first_node_in_group(&"inner_voice")
	_check("a thought id is thought only once", not iv.think("airlock_log", "x"))
	iv.queue = []
	iv.current = {}
	iv._cool = 0.0
	var ai: Node = main.get_node("StationAI")
	ai.set_enabled(true)
	ai.say_key(&"repeat_none")
	iv.think("test_wait", "Testing.")
	await process_frame
	await process_frame
	_check("never over the assistant: waits while it speaks", not iv.is_showing() or not ai.is_showing())
	ai.skip(true)
	ai.set_enabled(false)
	for i in 30:
		await process_frame
	_check("then shows as a caption (distinct, in quotes): '%s'" % iv._label.text, iv.history.any(func(h): return h["id"] == "test_wait") and iv._label.text.begins_with("“"))
	_check("voice backend reported honestly: %s" % iv.backend(), iv.backend().begins_with("captions"))
	var sd: Dictionary = JSON.parse_string(JSON.stringify(iv.state_dict()))
	iv.load_dict({})
	iv.load_dict(sd)
	_check("thought memory saved (no repeats after load)", iv.said.has("airlock_log"))
	# Chapter one: phase 2 + a contradiction -> next morning.
	se.story_phase = 2
	se.milestones.erase("chapter_1")
	dp.end_shift_now()
	dp.reset_for_new_day()
	await process_frame
	# Round 45: the chapter's climax is the window encounter -- a record
	# contradiction alone no longer ends it (test_r45_window_access covers
	# the window route); the long quiet fallback is 8 phase-2 days.
	_check("a contradiction alone no longer ends Chapter One (window climax required)", not se.chapter_one_complete())
	se.milestones.erase("chapter_1")
	se.evidence = []
	se.phase2_day = dp.day_number
	for i in 8:
		dp.end_shift_now()
		dp.reset_for_new_day()
	_check("quiet fallback: eight phase-2 days also end the chapter", se.chapter_one_complete() and main.find_child("ChapterCard", true, false) != null)
	_check("the story keeps going (phase not locked)", se.story_phase >= 2)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
