extends SceneTree
## Round 49: CHAPTER TWO / PHASE THREE beats on the Lower Service Deck,
## through the existing story director.
##   - registered with the same pacing machinery; the two architecture-only
##     beats are STORY-INACTIVE (never armed), the phase-3 beats need phase
##     3; nothing is eligible before Chapter One is complete, Deck B access
##     exists and the technician KNOWS the deck (4 rooms, 2 days);
##   - "the sound below" (normal): a REAL automatic cycle runs (logged) --
##     going to B-02 finds the plausible explanation; (abnormal): the same
##     sound, nothing ran;
##   - previews never count as plays; every presentation is reversed on
##     stop (lab catalogue overlay, archive alternate record) and never
##     written into the authoritative record;
##   - the abnormal cargo beat moves the SAME part instance (no duplicate);
##   - no identity / explanation is revealed in any Deck B beat text;
##   - Chapter Two family letters: arrival after Deck B opens; the
##     follow-up letter answers the reply the technician chose.
var _ok := true
var main: Node
var se: Node
var dp: Node
var s: Node
var clr: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	main.get_node("StationAI").set_enabled(false)
	se = main.get_node("StoryEvents")
	dp = main.get_node("DayPlan")
	s = main.get_node("DeckB/DeckBSystems")
	clr = main.get_node("DayPlan/Clearance")
	clr.load_dict({"level": 3})
	var ids: Array = se.EVENTS.keys().filter(func(k): return bool(se.EVENTS[k].get("deck_b", false)))
	_check("%d Chapter Two / Phase Three beats registered" % ids.size(), ids.size() == 9)
	_check("architecture-only beats are STORY-INACTIVE (never armed)", se.eligibility(&"unknown_signal_fragment") == "disabled" and se.eligibility(&"lower_layout_contradiction") == "disabled")
	se.dev_set_phase_override(2)
	_check("Chapter One incomplete: '%s'" % se.eligibility(&"lower_sound_echo"), se.eligibility(&"lower_sound_echo").find("Chapter") != -1)
	se._add_milestone("chapter_1")
	clr.refresh()
	_check("Chapter Two opened, but the technician must know the deck first: '%s'" % se.eligibility(&"lower_sound_echo"), se.eligibility(&"lower_sound_echo").find("know the lower deck") != -1)
	dp.day_number = 12
	s.visits = {10: ["b01", "b02", "b03"], 11: ["b01", "b04"]}
	_check("familiar with the deck -> 'the sound below' eligible", se.eligibility(&"lower_sound_echo") == "")
	_check("phase-3 beats still need phase 3 ('%s')" % se.eligibility(&"archive_timestamp_drift"), se.eligibility(&"archive_timestamp_drift").find("phase 3") != -1)
	var forbidden := ["ghost", "alien", "monster", "time travel", "clone", "dead technician", "murder", "parallel universe"]
	var leak := ""
	for id in ids:
		var txt: String = (String(se.EVENTS[id]["name"]) + " " + String(se.EVENTS[id]["needs"])).to_lower()
		for f in forbidden:
			if txt.find(f) != -1:
				leak = "%s: %s" % [id, f]
	_check("no explanation / identity revealed in any beat (%s)" % (leak if leak != "" else "clean"), leak == "")
	await _sound_below()
	await _presentations()
	await _family()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _sound_below() -> void:
	var fb: Node = main.get_node("FreeMoveBody")
	fb.sync_to_eye_position(Vector3(0.0, 1.6, 4.5))     # Deck A, Junction
	for i in 4: await physics_frame
	dp.shift_elapsed_s = 150.0
	s.water["processing"] = false
	var starts0: int = s.water["starts"].size()
	se.debug_arm(&"lower_sound_echo")
	var t0: int = Time.get_ticks_msec()
	while se.active != &"lower_sound_echo" and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	_check("armed: 'the sound below' starts from Deck A (pump idle, 6 m+ away)", se.active == &"lower_sound_echo")
	_check("NORMAL variant: a real automatic cycle ran and was logged ('%s')" % (String(s.water["starts"].back()["why"]) if not s.water["starts"].is_empty() else "-"), s.water["starts"].size() == starts0 + 1 and s.water["processing"])
	var heard: Dictionary = {}
	t0 = Time.get_ticks_msec()
	while se.active == &"lower_sound_echo" and Time.get_ticks_msec() - t0 < 12000:
		await process_frame
	_check("the beat ends by itself and counts one play", se.active == &"" and int(se.state[&"lower_sound_echo"]["plays"]) == 1 and bool(se.state[&"lower_sound_echo"]["seen"]))
	_check("...and leaves an open question for a physical check", se._pending_investigation.has("lower_sound_echo"))
	fb.sync_to_eye_position(Vector3(-0.1, -2.3, 9.6))     # B-02
	for i in 40: await process_frame
	var ev: Array = se.evidence.filter(func(e): return e["event"] == "lower_sound_echo")
	_check("going to Water Recovery = the check; the WRS log offers a plausible source", se.investigations.has("lower_sound_echo") and ev.any(func(e): return String(e["text"]).find("automatic") != -1))
	# Abnormal preview (developer): nothing runs, the sound plays at B-02.
	s.water["processing"] = false
	var n0: int = s.water["starts"].size()
	fb.sync_to_eye_position(Vector3(0.0, 1.6, 4.5))
	for i in 4: await physics_frame
	se.dev_trigger(&"lower_sound_echo", "abnormal")
	await process_frame
	var snd: Node = main.get_tree().get_first_node_in_group(&"station_sounds")
	var last: Dictionary = snd.heard.back() if not snd.heard.is_empty() else {}
	_check("ABNORMAL preview: the sound really plays from B-02 (%d walls, muffled), no cycle, no log" % int(last.get("walls", 0)), String(last.get("kind", "")) == "echo_pump" and bool(last.get("played", false)) and int(last.get("walls", 0)) >= 1 and s.water["starts"].size() == n0 and not s.water["processing"])
	se.dev_cancel()
	_check("previews never count as plays", int(se.state[&"lower_sound_echo"]["plays"]) == 1)


func _presentations() -> void:
	var lab: Node = main.get_node("DeckB/Rooms/PayloadLab")
	lab.recorded["S-102"] = {"class": "DENDRITE", "day": dp.day_number - 1, "catalogue": "CR-4472", "t": "10:00"}
	var rec_before: String = JSON.stringify(lab.recorded)
	se.dev_trigger(&"lab_sample_disagreement", "normal")
	await process_frame
	var shown: String = lab._presented_catalogue(1)
	_check("the documented specimen is DISPLAYED with another catalogue number (%s vs CR-4472)" % shown, shown != "CR-4472" and lab.stage == 1)
	_check("...the record itself is unchanged", JSON.stringify(lab.recorded) == rec_before)
	se.dev_cancel()
	_check("stop: presentation removed", lab._presented_catalogue(1) == "CR-4472")
	var arc: Node = main.get_node("DeckB/Rooms/DataArchive")
	arc.page = 4
	se.dev_trigger(&"archive_prev_record")
	await process_frame
	_check("the previous technician's entry reads differently at the console", arc._page_text().find("Nobody started it") != -1)
	se.dev_cancel()
	_check("stop: the original entry is back", arc._page_text().find("Nobody started it") == -1 and arc._page_text().find("Bled the pump") != -1)
	# Cargo, abnormal: the same instance moves; nothing duplicated.
	var water: Node = main.get_node("DeckB/Rooms/WaterRecovery")
	var spares: Node = water.find_child("WaterSpareBeds", true, false)
	var part: Node3D = spares.items()[0]
	var nm: String = String(part.name)
	var ret: bool = water.part_stow(&"rack_WaterSpareBeds", part) if false else true
	s.note_stow("WaterSpareBeds", nm, "b02")
	s.player_stows.back()["day"] = dp.day_number - 1
	var count0: int = get_nodes_in_group(&"deck_b_part").size()
	se.dev_trigger(&"cargo_missing_item", "abnormal")
	await process_frame
	var q: Node = main.get_node("DeckB/Rooms/CargoBay").find_child("DestQuarantine", true, false)
	_check("ABNORMAL: the technician's part is physically in quarantine (same instance %s)" % nm, ret and q.items().any(func(it): return String(it.name) == nm) and get_nodes_in_group(&"deck_b_part").size() == count0)
	var lg: Node = main.get_node("DayPlan/StationLog")
	_check("...and the SERVICE record shows a transfer nobody made (presentation)", lg.display_entries("maintenance").any(func(e): return bool(e["overlay"]) and String(e["text"]).find("TRANSFER") != -1))
	se.dev_cancel()
	_check("stop: the presented transfer line is gone (the move itself stays real)", not lg.display_entries("maintenance").any(func(e): return bool(e["overlay"])))


func _family() -> void:
	var fam: Node = main.get_node("StoryEvents/FamilyMail")
	s.tier1_day = dp.day_number
	_check("Chapter Two letter not before the day after Deck B opened", not fam.arrived("mara_work"))
	dp.day_number += 1
	_check("...arrives the next day", fam.arrived("mara_work"))
	fam.reply("mara_work", "B")
	dp.day_number += 3
	_check("the follow-up letter answers the chosen reply ('%s')" % fam.letter_text("mara_work_followup").left(40), fam.arrived("mara_work_followup") and fam.letter_text("mara_work_followup").find("stressful") != -1)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
