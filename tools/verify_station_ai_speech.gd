extends SceneTree
## Round 36 (fallback since Round 37): REAL OS-TTS speech playback check for the station assistant (needs a
## real display server -- not part of the headless suite):
##   SMH_SETTINGS_PATH=user://test_game_settings.cfg godot --path . --script tools/verify_station_ai_speech.gd
## Verifies through the game's own StationAI/SpeechProvider: the backend is
## platform TTS; an English and a Simplified Chinese line are actually
## spoken (the OS synthesizer reports speaking, then finishes); a second
## line interrupts the first (no overlap); Voice volume 0 mutes; tearing
## the station down stops speech and the process exits cleanly.
## Godot's movie writer cannot capture OS TTS audio -- this log is the record.
const GS = preload("res://scripts/station/game_settings.gd")
var _ok := true


func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	var ai: Node = main.get_node("StationAI")
	# Round 37: spatial intercom speech is the primary backend now (see
	# tools/verify_spatial_voice.gd); this tool verifies the OS-TTS FALLBACK.
	ai._speech.force_os_tts = true
	GS.set_value("ai_guidance", true)
	GS.set_value("ai_voice", true)
	GS.set_value("vol_Voice", 1.0)
	GS.set_value("vol_Master", 1.0)
	ai.clear_queue()
	print("backend (en): ", ai.speech_backend())
	_check("platform TTS backend available", ai.speech_backend().begins_with("platform text-to-speech"))
	await _say_and_watch(ai, &"vent_intro", "en")
	GS.set_value("language", "zh_CN")
	print("backend (zh): ", ai.speech_backend())
	await _say_and_watch(ai, &"seal_test", "zh")
	GS.set_value("language", "en")
	# Interruption: a safety line stops the current one (one voice at a time).
	ai.say_key(&"thermal_dock")
	await create_timer(1.2).timeout
	var t0: int = ai.spoken_log().size()
	ai.say_key(&"interlock_cargo")
	await create_timer(1.0).timeout
	_check("safety line interrupted the instruction (now %s, speaking=%s)" % [ai.current_key(), ai.is_speaking()], ai.current_key() == &"interlock_cargo" and ai.spoken_log().size() == t0 + 1)
	# Mute via the Voice volume.
	ai.clear_queue()
	GS.set_value("vol_Voice", 0.0)
	await create_timer(0.8).timeout
	ai.say_key(&"cargo_return")
	await create_timer(1.0).timeout
	_check("Voice volume 0: not spoken (%s)" % ai._current.get("backend", "?"), not ai.is_speaking() and String(ai._current.get("backend", "")).begins_with("muted"))
	GS.set_value("vol_Voice", 1.0)
	# Teardown while speaking.
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(&"thermal_intro")
	await create_timer(1.2).timeout
	var was: bool = ai.is_speaking()
	main.queue_free()
	await process_frame
	await process_frame
	_check("speech stops when the station is torn down (was speaking=%s, now OS speaking=%s)" % [was, DisplayServer.tts_is_speaking()], was and not DisplayServer.tts_is_speaking())
	for rec in ai.spoken_log() if is_instance_valid(ai) else []:
		print("  spoken: ", rec)
	print("ALL CHECKS PASSED" if _ok else "SOME CHECKS FAILED")
	quit(0 if _ok else 1)


func _say_and_watch(ai: Node, key: StringName, lang: String) -> void:
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(key)
	var started := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000:
		await process_frame
		if DisplayServer.tts_is_speaking():
			started = true
		if started and not DisplayServer.tts_is_speaking() and not ai.is_showing():
			break
	var log: Array = ai.spoken_log()
	var last: Dictionary = log[log.size() - 1] if not log.is_empty() else {}
	print("  %s: %s" % [lang, last])
	_check("%s line spoken by TTS: OS reported speaking, then finished (%.1f s)" % [lang, (Time.get_ticks_msec() - t0) / 1000.0], started and last.get("backend", "") == "tts" and last.get("lang", "") == lang and not DisplayServer.tts_is_speaking())


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
