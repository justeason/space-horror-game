extends SceneTree
## Round 37: REAL spatial-voice measurement on the audio device (needs a
## real display + audio output; not part of the headless suite):
##   SMH_SETTINGS_PATH=user://test_game_settings.cfg godot --path . --script tools/verify_spatial_voice.gd
## Plays a rendered voice line (macOS say -> WAV) from the ENGINEERING
## intercom speaker and measures the Intercom bus's actual left/right peak
## output while the listener (player camera) faces the speaker, has it on
## the right, on the left, and stands far away. Then runs the real
## assistant path once and checks audio is produced on the room speaker.
## This is level-meter evidence, not human listening.
const GS = preload("res://scripts/station/game_settings.gd")
var _ok := true
var main: Node
var sp: Node
var cam: Camera3D


func _init() -> void:
	GS.set_value("vol_Voice", 1.0)
	GS.set_value("vol_Master", 1.0)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 8: await process_frame
	sp = main.get_node("StationSpeakers")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	var prov: Node = main.get_node("StationAI/Speech")
	var r: Dictionary = prov._start_render("Breaker panel E P S 2. A lit red lamp marks a tripped breaker. Check its fault lamp before you reset it.", "en")
	if int(r["task"]) != -1:
		WorkerThreadPool.wait_for_task_completion(int(r["task"]))
	var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(String(r["path"]))
	_check("voice line rendered (%.1f s)" % (stream.get_length() if stream else 0.0), stream != null and stream.get_length() > 2.0)
	var spk: Vector3 = sp.unit_position(&"engineering")
	var bus: int = AudioServer.get_bus_index("Intercom")
	var near_eye := Vector3(spk.x + 1.2, 1.6, spk.z - 0.2)
	var front: Dictionary = await _measure(stream, near_eye, spk, 0.0, bus)
	# +yaw turns the view LEFT (counter-clockwise seen from above), which
	# puts the speaker on the listener's RIGHT.
	var right: Dictionary = await _measure(stream, near_eye, spk, 90.0, bus)
	var left: Dictionary = await _measure(stream, near_eye, spk, -90.0, bus)
	var far_eye := Vector3(0.0, 1.6, -0.5)   # Control Room, ~8 m away
	var far: Dictionary = await _measure(stream, far_eye, spk, 0.0, bus)
	print("  facing speaker:   L %.1f dB  R %.1f dB" % [front["l"], front["r"]])
	print("  speaker on right: L %.1f dB  R %.1f dB" % [right["l"], right["r"]])
	print("  speaker on left:  L %.1f dB  R %.1f dB" % [left["l"], left["r"]])
	print("  8 m away:         L %.1f dB  R %.1f dB" % [far["l"], far["r"]])
	_check("audible output from the speaker (facing: %.1f dB)" % maxf(front["l"], front["r"]), maxf(front["l"], front["r"]) > -40.0)
	_check("facing the speaker: balanced (|L-R| = %.1f dB)" % absf(front["l"] - front["r"]), absf(front["l"] - front["r"]) < 3.0)
	_check("speaker on the RIGHT: right channel louder (%.1f dB)" % (right["r"] - right["l"]), right["r"] - right["l"] > 3.0)
	_check("speaker on the LEFT: left channel louder (%.1f dB)" % (left["l"] - left["r"]), left["l"] - left["r"] > 3.0)
	_check("moving 8 m away is quieter (%.1f dB drop)" % (maxf(front["l"], front["r"]) - maxf(far["l"], far["r"])), maxf(front["l"], front["r"]) - maxf(far["l"], far["r"]) > 6.0)
	# The real assistant path, standing in Engineering.
	var ai: Node = main.get_node("StationAI")
	main.get_node("FreeMoveBody").sync_to_eye_position(near_eye)
	main.get_node("Player").global_position = near_eye
	for i in 4: await physics_frame
	ai.clear_queue()
	await create_timer(0.8).timeout
	ai.say_key(&"emerg_clear")
	var peak := -200.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await process_frame
		peak = maxf(peak, maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0)))
	var rec: Dictionary = ai.spoken_log()[-1] if not ai.spoken_log().is_empty() else {}
	print("  assistant line: ", rec)
	_check("assistant line spoken spatially from the Engineering speaker (peak %.1f dB)" % peak, rec.get("backend", "") == "spatial" and rec.get("unit", "") == "engineering" and peak > -40.0)
	print("ALL CHECKS PASSED" if _ok else "SOME CHECKS FAILED")
	quit(0 if _ok else 1)


## Plays the stream from the Engineering unit with the listener at `eye`
## turned `yaw_offset` degrees from facing the speaker; returns the mean of
## per-frame peak dB over 1.6 s.
func _measure(stream: AudioStream, eye: Vector3, target: Vector3, yaw_offset: float, bus: int) -> Dictionary:
	var fb: Node = main.get_node("FreeMoveBody")
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for i in 4: await physics_frame
	var d: Vector3 = target - cam.global_position
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y + deg_to_rad(yaw_offset)
	lp._target_yaw = lp.rotation.y
	lp.get_node("PitchPivot").rotation.x = 0.0
	lp._target_pitch = 0.0
	for i in 3: await process_frame
	sp.play_voice(&"engineering", stream, 1.0)
	var ls := 0.0
	var rs := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1600:
		await process_frame
		var l: float = AudioServer.get_bus_peak_volume_left_db(bus, 0)
		var r: float = AudioServer.get_bus_peak_volume_right_db(bus, 0)
		if l > -150.0 or r > -150.0:
			ls += maxf(l, -90.0)
			rs += maxf(r, -90.0)
			n += 1
	sp.stop_voice()
	await create_timer(0.3).timeout
	return {"l": ls / maxi(n, 1), "r": rs / maxi(n, 1)}


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
