extends SceneTree
## Round 37 Priority 3: station intercom SPEAKERS + spatial voice.
## Headless audio output is a dummy driver, so loudness/direction are
## measured by tools/verify_spatial_voice.gd on a real display. Here:
## speaker geometry & selection, the voice line's unit, the real
## `say` -> WAV -> AudioStreamPlayer3D path (enabled with
## SMH_SPATIAL_SPEECH=1), one voice at a time, indicator, cleanup.
var _ok := true
var main: Node
var ai: Node
var sp: Node
var cam: Node3D


func _init() -> void:
	OS.set_environment("SMH_SPATIAL_SPEECH", "1")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	ai = main.get_node("StationAI")
	sp = main.get_node("StationSpeakers")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	var ids: Array = sp.units.keys().filter(func(k): return k != &"suit_radio")   # Round 38: + suit radio channel
	_check("eight intercom units: %s" % str(ids), ids.size() == 8 and [&"living_quarters", &"control_room", &"engineering", &"life_support", &"storage", &"communications", &"airlock", &"main_junction"].all(func(r): return ids.has(r)))
	var colliders := 0
	for id in ids:
		colliders += (sp.units[id]["root"] as Node).find_children("*", "CollisionObject3D", true, false).size()
	_check("speakers have no colliders (never block walking / interaction)", colliders == 0)
	_check("each unit is ceiling-mounted inside its room", ids.all(func(id): return id == &"main_junction" or sp.room_at(sp.unit_position(id) - Vector3(0, 0.3, 0)) == id))
	_check("room detection: Engineering point -> engineering", sp.room_at(Vector3(-4.2, 1.6, 5.0)) == &"engineering")
	_check("corridor point -> nearest unit", sp.unit_for(Vector3(0.0, 1.6, 2.8)) != &"")
	_check("backend reported: %s" % ai.speech_backend(), ai.speech_backend().begins_with("spatial intercom speech"))
	# Living Quarters: the line plays from the Quarters speaker.
	await _stand(Vector3(3.7, 1.6, 0.6))
	_check("listener in Quarters -> unit living_quarters", ai.listener_unit() == &"living_quarters")
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(&"intro_greet")
	var played: bool = await _wait_voice(&"living_quarters")
	_check("greeting rendered by say and PLAYING on the Quarters speaker (AudioStreamPlayer3D)", played)
	_check("speaker indicator lit while speaking", sp.is_lit(&"living_quarters") or sp.units[&"living_quarters"]["glow"].light_energy > 0.0)
	_check("one voice at a time (only that unit playing)", ids.filter(func(id): return sp.units[id]["player"].playing).size() == 1)
	_check("voice player is on the Intercom bus -> Voice", sp.units[&"living_quarters"]["player"].bus == "Intercom" and AudioServer.get_bus_send(AudioServer.get_bus_index("Intercom")) == "Voice")
	# Walking out mid-line does not move the voice.
	await _stand(Vector3(-4.2, 1.6, 5.0))
	await process_frame
	_check("moving mid-line keeps the same speaker (no jump)", sp.active_unit() == &"living_quarters")
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(&"breaker_intro")
	_check("next line in Engineering plays from the Engineering speaker", await _wait_voice(&"engineering"))
	_check("the Quarters unit is silent now", not sp.units[&"living_quarters"]["player"].playing)
	ai.skip(true)
	await process_frame
	_check("J / skip stops the voice", not sp.voice_playing())
	# Cache: a repeated line starts without re-rendering.
	var files: Array = DirAccess.get_files_at(ProjectSettings.globalize_path("user://voice_cache/"))
	_check("rendered lines are cached (%d files)" % files.size(), files.size() >= 2)
	# Scene teardown: render tasks awaited, voice stopped, nothing crashes.
	ai.say_key(&"vent_intro")
	await process_frame
	main.queue_free()
	await process_frame
	await process_frame
	_check("station freed mid-line without errors", not is_instance_valid(main))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _stand(eye: Vector3) -> void:
	main.get_node("FreeMoveBody").sync_to_eye_position(eye)
	main.get_node("Player").global_position = eye
	for i in 4: await physics_frame


func _wait_voice(unit: StringName) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await process_frame
		if sp.units[unit]["player"].playing:
			return true
	return false


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
