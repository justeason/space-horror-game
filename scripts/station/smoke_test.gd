extends Node
## Round 45 Priority 31: an automated SMOKE TEST for exported builds (the
## test harness cannot drive a packaged app). Runs ONLY when the
## environment variable SMH_SMOKE_TEST=1 is set; a normal player never
## triggers it. Prints "SMOKE: ..." lines and quits:
##   build kind + user-data folder, main menu, New Game into the station,
##   movement, laptop open / focus / close (clock + hold), workstation use,
##   save then read back + apply, the developer panel's absence in
##   release builds, audio buses / device, then quit.

var _ok := true


## SAFETY: only ever inside the exported demo's OWN save namespace
## (project setting custom_user_dir_name.template) -- the smoke test saves,
## so it must never run against the editor's / a player's real save folder.
const DEMO_DIR := "SatelliteMaintenanceHorrorDemo"


static func wanted() -> bool:
	return OS.get_environment("SMH_SMOKE_TEST") == "1" and OS.get_user_data_dir().ends_with(DEMO_DIR)


var _lines: Array = []


func _say(name: String, cond: bool, detail: String = "") -> void:
	var line: String = "SMOKE: %s %s%s" % ["PASS" if cond else "FAIL", name, (" — " + detail) if detail != "" else ""]
	print(line)
	_lines.append(line)
	var f := FileAccess.open("user://smoke_results.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
	if not cond:
		_ok = false


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func run(menu: Node) -> void:
	await _wait(1.0)
	_say("build", true, "%s · user dir %s" % ["DEBUG" if OS.is_debug_build() else "RELEASE", OS.get_user_data_dir()])
	_say("main menu shown", menu != null and menu.is_inside_tree())
	menu.start_new_game()
	await _wait(6.0)
	var main: Node = get_tree().current_scene
	_say("New Game -> station scene", main != null and main.get_node_or_null("DayPlan") != null, String(main.name) if main != null else "")
	if main == null or main.get_node_or_null("DayPlan") == null:
		_finish()
		return
	var dp: Node = main.get_node("DayPlan")
	var ss: Node = main.get_node("SleepState")
	_say("day 1 starts in the bunk at 08:00", dp.day_number == 1 and dp.clock_text_hhmm().begins_with("08:0"), dp.clock_text_hhmm())
	ss._sit_up_then_get_up()
	await _wait(4.0)
	var fb: Node3D = main.get_node("FreeMoveBody")
	var p0: Vector3 = fb.global_position
	fb.velocity = Vector3(0.0, 0.0, 1.2)
	for i in 30:
		await get_tree().physics_frame
		if fb.has_method("move_and_slide"):
			fb.velocity = Vector3(0.0, fb.velocity.y, 1.2)
	_say("character can move", fb.global_position.distance_to(p0) > 0.05, "%.2f m" % fb.global_position.distance_to(p0))
	# Laptop: sit, open, focus, close.
	fb.sync_to_eye_position(Vector3(4.0, 1.6, -0.3))
	await _wait(0.4)
	ss.begin_sitting()
	await _wait(2.0)
	ss.open_laptop(false)
	await _wait(2.5)
	ss.begin_editing()
	await _wait(1.5)
	var scr: Node = main.get_node("Player/LaptopView")._log_screen
	var c0: int = dp.clock_minutes()
	scr.open_app(&"note")
	await _wait(1.0)
	_say("laptop focused: Today open, shift budget held", ss.is_editing() and dp.clock_paused() and scr.current_view() == &"note")
	ss.close_laptop()
	await _wait(2.0)
	_say("CLOSE LAPTOP closes it; clock continuous", not ss.is_laptop_open() and dp.clock_minutes() >= c0, "%d -> %d min" % [c0, dp.clock_minutes()])
	ss.end_sitting()
	await _wait(3.0)
	# Workstation.
	var ws: Node = main.get_node("WorkstationState")
	ws.begin_use()
	await _wait(2.0)
	var screen: Node = main.get_node("Interactables/WorkstationConsole/WorkstationScreen")
	screen.shell.show_page(screen.shell.Page.OPS)
	await _wait(0.5)
	_say("workstation in use, Operations page", ws.is_in_use() if ws.has_method("is_in_use") else true)
	ws.end_use()
	await _wait(2.0)
	# Round 49: the Lower Service Deck is built and still sealed on day 1.
	var deckb: Node = main.get_node_or_null("DeckB")
	var shaft: Node = main.get_node_or_null("DeckB/VerticalShaft")
	var rooms_n: int = deckb.get_node("Rooms").get_child_count() if deckb != null and deckb.has_node("Rooms") else 0
	var why: String = shaft.refusal(true) if shaft != null else "no shaft"
	_say("lower deck built (%d rooms), shaft sealed on day 1" % rooms_n, rooms_n >= 9 and why != "" and main.get_node("DayPlan/Clearance").deck_b_tier() == 0, why)
	# Save + read back + apply.
	var sg: Node = main.get_node("SaveGame")
	var r: Dictionary = sg.save_game()
	_say("save", bool(r.get("ok", false)), String(r.get("message", "")))
	var rd: Dictionary = sg.read_save()
	_say("save reads back valid", bool(rd.get("ok", false)))
	if bool(rd.get("ok", false)):
		var ap: Dictionary = sg.apply_state(rd["data"])
		_say("load applies", bool(ap.get("ok", false)), String(ap.get("message", "")))
	_say("developer panel absent in release", OS.is_debug_build() or main.find_child("DevPanel", true, false) == null)
	_say("audio buses + output device", AudioServer.bus_count >= 5 and AudioServer.get_output_device() != "", AudioServer.get_output_device())
	_finish()


func _finish() -> void:
	print("SMOKE: %s" % ("ALL PASSED" if _ok else "SOME FAILED"))
	get_tree().quit(0 if _ok else 1)
