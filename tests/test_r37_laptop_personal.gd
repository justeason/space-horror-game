extends SceneTree
## Round 37 Priority 11: personal laptop content -- Messages (by day,
## unread count, read state saved), Schedule (DayPlan's real day), Photos
## (honest empty album). No horror content.
var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	var dp: Node = main.get_node("DayPlan")
	var lv: Node = main.get_node("Player/LaptopView")
	var scr: Node = lv._log_screen
	_check("day 1: two messages, both unread", scr.messages_today().size() == 2 and scr.unread_count() == 2)
	# Round 44: Schedule folded into TODAY (&"note").
	_check("app bar has Messages (2) / Today / Photos", scr.button(&"messages").text == "Messages (2)" and scr.button(&"note") != null and scr.button(&"photos") != null)
	scr.open_app(&"messages")
	_check("Messages view lists them, newest first (Older mail, Round 44 mail view)", scr.current_view() == &"messages" and scr._mail_text.text.find("Mara") != -1)
	_check("opening Messages marks them read", scr.unread_count() == 0 and scr.button(&"messages").text == "Messages")
	scr.open_app(&"home")
	scr.open_app(&"schedule")
	_check("Schedule = DayPlan's real day ('%s')" % scr._report.text.get_slice("\n", 0), scr._report.text.find("DAY %d" % dp.day_number) != -1 and scr._report.text.find(dp.today_title()) != -1)
	scr.open_app(&"home")
	scr.open_app(&"photos")
	_check("Photos (Round 38): original stylized photos with captions", scr._photo.texture != null and scr._photo_caption.text.find("Family dinner") != -1)
	scr.open_app(&"home")
	# Messages arrive by day.
	dp.reset_for_new_day()
	dp.reset_for_new_day()
	scr.refresh_day()
	_check("day 3: new messages arrive (unread %d)" % scr.unread_count(), scr.unread_count() == 2)
	# Read state is saved.
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_r37_laptop.json"
	sg.save_game()
	scr.read_messages = {}
	sg.apply_state(sg.read_save()["data"])
	_check("load restores which messages were read", scr.read_messages.has("m1") and scr.read_messages.has("m2") and not scr.read_messages.has("m3"))
	# Content check: ordinary correspondence, no horror vocabulary.
	var bad := ["blood", "dead", "death", "scream", "ghost", "shadow", "alone", "watching", "help me", "don't trust", "voice", "missing", "strange", "noise"]
	var hits: Array = []
	for m in scr.MESSAGES:
		for w in bad:
			if String(m["text"]).to_lower().find(w) != -1:
				hits.append("%s:%s" % [m["id"], w])
	_check("messages contain no horror hints (%s)" % str(hits), hits.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r37_laptop.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_r37_laptop.json.bak"))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
