extends SceneTree
## Round 46 Priorities 13-14, 23-27: messages per person, basil care and
## the Phase 3 return, the inner voice, ordinary everyday thoughts.
var _ok := true
var main: Node
var dp: Node
var se: Node
var q: Node
var scr: Node


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 10: await process_frame
	dp = main.get_node("DayPlan")
	se = main.get_node("StoryEvents")
	q = main.get_node("Equipment/QuartersLife")
	scr = main.get_node("Player/LaptopView")._log_screen
	_messages()
	_basil()
	_voice()
	_everyday()
	_pacing_and_consequences()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _messages() -> void:
	var fm: Node = se.family
	fm.load_dict({})
	se.evidence = []
	dp.day_number = 2
	_check("day 2: Mara's first letter", fm.contacts_available() == ["mara"])
	dp.day_number = 3
	se.observe("corridor_presence", "seen")          # an anomaly on day 3
	dp.day_number = 4
	_check("two letters from Mara arrived (eating?, far away)", fm.arrived("mara_eating") and fm.arrived("mara_distracted"))
	scr.set_editing(true)
	scr.mail_open = ""
	scr.open_app(&"messages")
	var mara_buttons: Array = scr._mail_list.get_children().filter(func(b): return String(b.name).begins_with("Contact_mara"))
	var all_contacts: Array = scr._mail_list.get_children().filter(func(b): return String(b.name).begins_with("Contact_"))
	_check("ONE conversation for Mara (not one per letter): %d contact buttons" % all_contacts.size(), mara_buttons.size() == 1 and all_contacts.size() == fm.contacts_available().size())
	scr.open_contact("mara")
	var t: String = scr._mail_text.text
	_check("Mara's history in order: first letter, then the later one", t.find("Still eating properly") != -1 and t.find("far away") != -1 and t.find("Still eating properly") < t.find("far away"))
	_check("unanswered for 2+ days -> the later letter says so (tone changed)", t.find("never answered my last one") != -1)
	_check("reply buttons answer the OLDEST unanswered letter", fm.pending_conv("mara") == "mara_eating" and scr._mail_opts.get_child_count() >= 2)
	(scr._mail_opts.get_child(0) as Button).pressed.emit()
	_check("reply goes into the same conversation", fm.state("mara_eating") == "replied" and scr._mail_text.text.find("You · day 4") != -1)
	_check("...next the far-away letter is pending (same thread)", fm.pending_conv("mara") == "mara_distracted")
	dp.day_number = 5
	scr.open_contact("mara")
	_check("next-day answer appears in the SAME thread, after the reply", scr._mail_text.text.find("Mara · day 5") > scr._mail_text.text.find("You · day 4"))
	_check("no duplicate send", not fm.reply("mara_eating", "B"))
	# Mum: a letter left unanswered brings a follow-up in her thread.
	dp.day_number = 7
	_check("Mum's 'no news' follow-up arrives (sleep letter unanswered)", fm.arrived("mum_quiet") and fm.contact_convs("mum") == ["mum_sleep", "mum_quiet"])
	var fm2 := {"threads": {"mum_sleep": {"state": "replied", "choice": "A", "reply_day": 4, "answer_day": 5, "arrived_day": 4, "answer_read": true}}}
	fm.load_dict(fm2)
	_check("...not if she was answered in time", not fm.arrived("mum_quiet"))
	# Old (Round 44/45) save: per-letter threads load into per-person views.
	var old := {"threads": {"mara_eating": {"state": "replied", "choice": "B", "reply_day": 2, "answer_day": 3, "arrived_day": 2, "answer_read": true}, "mara_distracted": {"state": "read", "arrived_day": 4, "choice": "", "reply_day": -1, "answer_day": -1, "answer_read": false}}}
	fm.load_dict(JSON.parse_string(JSON.stringify(old)))
	var lines: String = "\n".join(fm.contact_lines("mara"))
	_check("old save: one Mara conversation, the sent reply kept once", fm.contacts_available().count("mara") == 1 and lines.count("You · day 2") == 1 and lines.find("Pip") != -1)
	scr.open_app(&"home")
	scr.set_editing(false)
	se.evidence = []
	dp.day_number = 1


func _basil() -> void:
	q.dev_basil_state(0)
	q.basil_dead = false
	q.basil_dead_day = -1
	q.basil_seen_dead = false
	var d0: int = dp.day_number
	var cols: Array = []
	q._refresh()
	cols.append((q._leaves[0].material as StandardMaterial3D).albedo_color)
	_check("starts HEALTHY", q.basil_state_name() == "HEALTHY")
	for k in 3:
		q.basil_day = -1
		q.on_new_day(d0 + k)
		cols.append((q._leaves[0].material as StandardMaterial3D).albedo_color)
		_check("neglected day %d -> %s" % [k + 1, q.basil_state_name()], q.basil_state_name() == ["DRY", "WILTING", "DEAD"][k])
	_check("states look different (green -> dull -> yellowed -> brown)", cols[0] != cols[1] and cols[1] != cols[2] and cols[2] != cols[3] and cols[3].r > cols[3].g)
	_check("dead: collapsed (leaves flattened onto the soil)", q._leaves[0].scale.y < 0.5 and q.basil_health() == 0.0)
	q.on_part(&"basil")
	_check("dead: water refused, no pour gesture", not main.get_node("Player/PlayerBody").is_consuming() and q._pending == "")
	var note: Dictionary = preload("res://scripts/ui/daily_note.gd").build(dp, q, false)
	_check("dead: no 'Water the basil' chore any more", not note["items"].any(func(it): return it["id"] == "basil"))
	q.on_new_day(d0 + 3)
	_check("a dead plant does not come back by itself", q.basil_state_name() == "DEAD")
	# Gradual recovery.
	q.dev_basil_state(2)
	q.basil_day = q._today()
	_check("watering a wilting plant: no instant undo", q.basil_state_name() == "WILTING")
	q.on_new_day(q._today())
	_check("...one step better next morning (DRY)", q.basil_state_name() == "DRY")
	# Old save migration: Round 43-45 capped "dry" at 3 (alive).
	q.load_dict({"basil_dry": 3, "basil_day": -1})
	_check("old save at the old maximum: WILTING, never killed on load", not q.basil_dead and q.basil_state_name() == "WILTING")
	# Phase 3 return: gating.
	q.dev_basil_state(3)
	q.basil_seen_dead = false
	q.basil_dead_day = q._today() - 1
	_check("return: not before Phase 3", not q.basil_return_eligible(1) and not q.basil_return_eligible(2))
	_check("return: not if the plant was never SEEN dead", not q.basil_return_eligible(3))
	q.basil_seen_dead = true
	_check("return: Phase 3 + died + seen dead + a later day -> eligible", q.basil_return_eligible(3))
	q.basil_dead_day = q._today()
	_check("return: never on the day it died", not q.basil_return_eligible(3))
	q.basil_dead_day = q._today() - 1
	var old_override: int = se.dev_phase_override
	se.dev_phase_override = 3
	se.state[&"basil_return"] = se._blank()
	se._on_day_started(dp.day_number)
	_check("story day start presents it alive (presentation)", q.basil_return_day >= 0 and q.basil_state_name() == "HEALTHY")
	_check("...true history kept (still recorded dead on day %d)" % q.basil_dead_day, q.basil_dead and q.basil_dead_day >= 0)
	q.basil_return_seen = false
	q.basil_return_noticed.emit()
	_check("noticing it: an observation on record", se.investigation_state("basil_return") == "observed")
	var sd: Dictionary = JSON.parse_string(JSON.stringify(q.state_dict()))
	q.load_dict({})
	q.load_dict(sd)
	_check("save/load keeps death, seen-dead and the return", q.basil_dead and q.basil_seen_dead and q.basil_return_day >= 0)
	q.basil_return_reset()
	se.dev_phase_override = old_override
	q.dev_basil_state(1)
	se.dev_trigger(&"basil_return")
	_check("developer preview: shown alive, never saved", q.basil_return_day >= 0 and int(q.state_dict()["basil_return_day"]) == -1)
	se.dev_cancel()
	q.basil_return_reset()
	q.dev_basil_state(0)
	se.evidence = []


func _voice() -> void:
	var iv: Node = se.inner
	var bi: int = AudioServer.get_bus_index("InnerVoice")
	var has_reverb := false
	var has_eq := false
	for k in AudioServer.get_bus_effect_count(bi):
		var e: AudioEffect = AudioServer.get_bus_effect(bi, k)
		has_reverb = has_reverb or e is AudioEffectReverb
		has_eq = has_eq or e is AudioEffectEQ6
	_check("inner voice: dry and close (no room reverb, warmth EQ), not spatial", not has_reverb and has_eq and iv._player is AudioStreamPlayer)
	_check("inner voice: quiet (%.0f dB) and slower than the assistant" % iv._player.volume_db, iv._player.volume_db <= -10.0 and int(iv.VOICE["en"][1]) < 168)
	var amb: int = AudioServer.get_bus_index("Ambient")
	var vol0: float = AudioServer.get_bus_volume_db(amb)
	iv._set_duck(true)
	var duck: AudioEffectAmplify = iv.duck_effect("Ambient")
	_check("the room recedes while a thought plays (duck %.0f dB)" % duck.volume_db, duck.volume_db < -3.0 and is_equal_approx(AudioServer.get_bus_volume_db(amb), vol0))
	iv._set_duck(false)
	_check("...and comes back; the player's bus volume untouched", is_zero_approx(duck.volume_db) and is_equal_approx(AudioServer.get_bus_volume_db(amb), vol0))
	iv.flush()
	iv.current = {}
	iv.queue = []
	iv.think("r46_test", "Was that always on the list?", "清单上一直有这一项吗？", false)
	iv._cool = 0.0
	iv._process(0.016)
	_check("caption: no quotation marks, slanted (italic) font", iv._label.text == "Was that always on the list?" and (iv._label.get_theme_font("font") as FontVariation) != null and absf((iv._label.get_theme_font("font") as FontVariation).variation_transform.y.x) > 0.1)
	_check("captions-only fallback is reported honestly in headless", iv.backend().begins_with("captions"))
	iv.current = {}
	iv.queue = []


func _everyday() -> void:
	var iv: Node = se.inner
	iv.everyday_day = -1
	iv.everyday_uses = {}
	var got: Array = []
	var per_day: Array = []
	for d in range(1, 13):
		dp.day_number = d
		var n := 0
		for ctx in ["repair", "breakfast", "dinner", "tea", "basil", "letter", "shift_end"]:
			iv.queue = []
			iv.current = {}
			if iv.everyday(ctx):
				n += 1
				got.append(ctx)
		per_day.append(n)
	_check("ordinary thoughts happen (%d over 12 days)" % got.size(), got.size() >= 8)
	_check("...restrained: never more than 2 a day (%s)" % str(per_day), per_day.max() <= 2)
	_check("...not every moment (chance + daily cap)", got.size() < 12 * 7 / 2)
	iv.queue = []
	iv.current = {}
	dp.day_number = 20
	iv.everyday_day = -1
	var a: bool = iv.everyday("tea")
	var b: bool = iv.everyday("tea")
	_check("one thought per context per day", not (a and b))
	var hist: Array = []
	for u in 4:
		var pool: Array = iv.EVERYDAY["breakfast"]
		hist.append(pool[u % pool.size()][0])
	_check("lines rotate (no same phrase two uses in a row)", hist[0] != hist[1] and hist[1] != hist[2])
	var zh_ok := true
	for ctx in iv.EVERYDAY:
		for line in iv.EVERYDAY[ctx]:
			zh_ok = zh_ok and String(line[1]) != "" and String(line[1]) != String(line[0])
	_check("every ordinary thought has Simplified Chinese", zh_ok)
	iv.queue = []
	dp.day_number = 1


func _pacing_and_consequences() -> void:
	_check("tiers: corridor crossing is MEDIUM, window figure MAJOR, peripheral SUBTLE", se.tier(&"corridor_presence") == "medium" and se.tier(&"window_figure") == "major" and se.tier(&"peripheral_figure") == "subtle")
	dp.day_number = 6
	se.dev_set_phase_override(2)
	se.state[&"hatch_handle"]["last_day"] = 5
	se.state[&"hatch_handle"]["plays"] = 1
	_check("an ordinary day between medium events ('%s')" % se.eligibility(&"corridor_presence"), se.eligibility(&"corridor_presence").begins_with("pacing"))
	se.state[&"hatch_handle"]["last_day"] = 6
	_check("the major window encounter never shares a day with a medium one", not se.window.is_ready_now())
	se.state[&"hatch_handle"] = se._blank()
	se.dev_set_phase_override(0)
	# Overnight escalation + the morning note.
	dp.orders.append({"id": "T-ESC", "type": &"vent", "category": "routine", "priority": 1, "day": 5, "seed": 1, "status": "open", "carried_from": 5})
	var row: Array = dp.order_rows().filter(func(r): return String(r.get("id", "")) == "T-ESC")
	_check("a job left open overnight is more serious now (severity %d)" % (int(row[0]["severity"]) if not row.is_empty() else -1), not row.is_empty() and int(row[0]["severity"]) >= 2 and bool(row[0]["escalated"]))
	var note: Dictionary = preload("res://scripts/ui/daily_note.gd").build(dp, q, false)
	_check("...and the morning note says so", "\n".join(note["header"]).find("Unresolved from yesterday") != -1)
	dp.orders = dp.orders.filter(func(o): return String(o["id"]) != "T-ESC")
	dp.day_number = 1


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
