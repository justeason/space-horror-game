extends SceneTree
## Round 34 Priorities 8/9: main menu, new game (wakes in the bunk), pause
## menu (Esc; pauses the shift clock; Esc priority vs. modals), settings
## that really apply (audio buses, language) and persist, credits, and
## loading through the menu. Save slots are redirected to test paths; the
## player's real settings file is backed up and restored.
var _ok := true
const GS = preload("res://scripts/station/game_settings.gd")
const SaveGameScript = preload("res://scripts/station/save_game.gd")
const MAN := "user://test_r34_menu_manual.json"
const AUTO := "user://test_r34_menu_auto.json"
var CFG: String = preload("res://scripts/station/game_settings.gd").settings_path()
var _cfg_backup: Variant = null

func _init() -> void:
	_cfg_backup = FileAccess.get_file_as_string(CFG) if FileAccess.file_exists(CFG) else null
	_clean()
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	for i in 6: await process_frame
	var menu: Node = current_scene
	menu.sg.save_path = MAN
	menu.sg.autosave_path = AUTO
	menu.show_main()
	await process_frame
	_check("main menu has Continue/New/Load/Settings/Credits/Quit", ["continue", "new", "load", "settings", "credits", "quit"].all(func(k): return menu.buttons.has(k)))
	_check("Continue is disabled with no save", menu.buttons["continue"].disabled)

	# ---- Settings: real audio buses, language, persistence. ----
	menu.buttons["settings"].pressed.emit()
	await process_frame
	var panel: Node = menu._page
	_check("all five audio buses exist", GS.AUDIO_BUSES.all(func(b): return AudioServer.get_bus_index(b) != -1))
	panel.sliders["SFX"].value = 0.5
	var db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	_check("the Effects slider changes the real SFX bus (%.1f dB)" % db, absf(db - linear_to_db(0.5)) < 0.1)
	panel.sliders["Ambient"].value = 0.0
	_check("zero volume mutes the Ambient bus", AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambient")))
	panel.language_option.item_selected.emit(1)
	await process_frame
	await process_frame
	_check("language switches to Simplified Chinese (locale %s)" % TranslationServer.get_locale(), TranslationServer.get_locale().begins_with("zh"))
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	_check("settings persisted to game_settings.cfg (language, SFX volume)", cfg.get_value("player", "language", "") == "zh_CN" and absf(float(cfg.get_value("player", "vol_SFX", 1.0)) - 0.5) < 0.01)
	menu._page.closed.emit()
	await process_frame
	_check("menu labels are localized ('%s')" % menu.buttons["new"].text, menu.buttons["new"].text == "新游戏")
	GS.set_value("language", "en")
	GS.set_value("vol_Ambient", 1.0)
	menu.show_main()
	await process_frame
	_check("back to English", menu.buttons["new"].text == "New Game")

	# ---- Credits. ----
	menu.buttons["credits"].pressed.emit()
	await process_frame
	_check("credits list only verifiable facts (Godot MIT, no third-party assets)", menu.credits_text().find("MIT License") != -1 and menu.credits_text().find("No third-party") != -1)
	menu.show_main()

	# ---- New game: wakes in the bunk, from the main menu flow. ----
	menu.buttons["new"].pressed.emit()
	for i in 12: await process_frame
	var main: Node = current_scene
	_check("New Game entered the station", main != menu and main.has_node("DayPlan"))
	main.get_node("SaveGame").save_path = MAN
	main.get_node("SaveGame").autosave_path = AUTO
	await create_timer(1.8).timeout
	var ss: Node = main.get_node("SleepState")
	_check("a new game begins awake in the bunk (day 1)", ss.is_lying_in_bed() and ss.is_sitting() and main.get_node("DayPlan").day_number == 1)

	# ---- Pause menu (Esc), clock paused, Esc priority. ----
	ss.end_sitting()
	await create_timer(3.5).timeout
	var pm: Node = main.get_node("PauseMenu")
	await _key(KEY_ESCAPE)
	_check("Esc opens the pause menu and pauses the game", pm.is_open and paused)
	var c0: float = main.get_node("DayPlan").shift_elapsed_s
	for i in 20: await process_frame
	_check("the shift clock is paused", absf(main.get_node("DayPlan").shift_elapsed_s - c0) < 0.001)
	_check("pause menu: Resume/Save/Load/Settings/Main Menu/Quit", ["resume", "save", "load", "settings", "main_menu", "quit"].all(func(k): return pm.buttons.has(k)))
	pm.buttons["save"].pressed.emit()
	_check("Save Game from the pause menu writes the manual slot ('%s')" % pm.status_label.text, FileAccess.file_exists(MAN))
	await _key(KEY_ESCAPE)
	_check("Esc again resumes", not pm.is_open and not paused)
	var ws: Node = main.get_node("WorkstationState")
	ws.begin_use()
	var t0 := Time.get_ticks_msec()
	while not ws.is_in_use() and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	await _key(KEY_ESCAPE)
	_check("Esc at the workstation closes the workstation, NOT the pause menu", not pm.is_open and not ws.is_in_use())

	# ---- Back to the main menu; Continue + Load through the menu. ----
	await create_timer(1.5).timeout
	await _key(KEY_ESCAPE)
	pm.buttons["main_menu"].pressed.emit()
	for i in 10: await process_frame
	var menu2: Node = current_scene
	_check("Return to Main Menu works", menu2.has_method("show_main"))
	menu2.sg.save_path = MAN
	menu2.sg.autosave_path = AUTO
	menu2.show_main()
	await process_frame
	_check("Continue is now enabled (a save exists)", not menu2.buttons["continue"].disabled)
	menu2.buttons["load"].pressed.emit()
	await process_frame
	_check("Load lists the manual slot (enabled) and the empty autosave (disabled)", not menu2.buttons["slot_manual"].disabled and menu2.buttons["slot_autosave"].disabled)
	menu2.buttons["slot_manual"].pressed.emit()
	for i in 14: await process_frame
	var main2: Node = current_scene
	_check("loading through the menu restores the saved station (day 1, standing)", main2.has_node("DayPlan") and main2.get_node("DayPlan").day_number == 1 and not main2.get_node("SleepState").is_lying_in_bed())
	_clean()
	_restore_cfg()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k; e.physical_keycode = k; e.pressed = true
	get_root().push_input(e)
	await process_frame
	var u := InputEventKey.new()
	u.keycode = k; u.physical_keycode = k; u.pressed = false
	get_root().push_input(u)
	await process_frame


func _clean() -> void:
	for base in [MAN, AUTO]:
		for p in [base, base + ".bak", base + ".tmp"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _restore_cfg() -> void:
	if _cfg_backup == null:
		if FileAccess.file_exists(CFG):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_string(_cfg_backup)
		f.close()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
