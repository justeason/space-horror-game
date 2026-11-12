extends SceneTree
## Round 48 Priorities 13-22: SOUND that is really heard.
##  - root cause of the "silent" knocks: glass_knock / hatch_knock had NO
##    stream (play_at logged them, nothing played). Now every sound kind the
##    game plays resolves to a real stream, and play_at records whether a
##    voice actually STARTED (played, length, bus);
##  - the window-hand knock: three distinct structure-borne knocks (one, a
##    pause, two) from the pane's cabin face; full level and unfiltered in
##    the Control Room, quieter and muffled elsewhere; distinct from the
##    airlock hatch knock (spectrum + length); the sequence always completes;
##  - routine foley plays DURING the action at the animation's phases (sip
##    at the tilt, bites while the hand is at the mouth, the mug set down as
##    it is lowered, brush strokes phase-locked to the scrub), nothing after
##    the action is over or cancelled;
##  - the inner voice: separate non-positional bus with its own volume
##    setting; source = recorded pack > natural system voice > captions,
##    never the robotic voices, never mixed within a session; the assistant
##    interrupts it; a missing recorded line is caption-only.
var _ok := true
var main: Node
var se: Node
var dp: Node
var snd: Node
var q: Node
var cam: Camera3D
var fb: Node
var player: Node3D
var lp: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 12: await process_frame
	se = main.get_node("StoryEvents")
	dp = main.get_node("DayPlan")
	snd = main.get_tree().get_first_node_in_group(&"station_sounds")
	q = main.get_node("Equipment/QuartersLife")
	fb = main.get_node("FreeMoveBody")
	player = main.get_node("Player")
	lp = player.get_node("LookPivot")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	main.get_node("StationAI").set_enabled(false)
	_streams()
	await _knock_levels()
	await _hand_sequence()
	await _foley()
	await _voice()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _aim(eye: Vector3, target: Vector3) -> void:
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for k in 2:
		for i in 3: await physics_frame
		var d: Vector3 = target - cam.global_position
		lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
		lp._target_yaw = lp.rotation.y
		var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
		lp.get_node("PitchPivot").rotation.x = pitch
		lp._target_pitch = pitch
	for i in 3: await process_frame


func _last(kind: String) -> Dictionary:
	for i in range(snd.heard.size() - 1, -1, -1):
		if String(snd.heard[i]["kind"]) == kind:
			return snd.heard[i]
	return {}


## Energy share below 200 Hz of a 16-bit mono WAV stream (Goertzel bands).
func _band_energy(s: AudioStreamWAV, freqs: Array) -> Array:
	var data: PackedByteArray = s.data
	var n: int = mini(data.size() / 2, 8192)
	var out: Array = []
	for f in freqs:
		var w: float = TAU * float(f) / float(s.mix_rate)
		var c: float = 2.0 * cos(w)
		var s1 := 0.0
		var s2 := 0.0
		for i in n:
			var v: float = float(data.decode_s16(i * 2)) / 32768.0
			var s0: float = v + c * s1 - s2
			s2 = s1
			s1 = s0
		out.append(s1 * s1 + s2 * s2 - c * s1 * s2)
	return out


func _streams() -> void:
	# Every kind the game plays (code + foley timelines) has a real stream.
	var kinds := {}
	var rx := RegEx.new()
	rx.compile("(?:play_at|_snd|_snd_mouth)\\(&\"([a-z_]+)\"")
	for f in ["res://scripts/story/story_events.gd", "res://scripts/story/window_hand.gd", "res://scripts/station/quarters_life.gd", "res://scripts/station/breaker_panel.gd", "res://scripts/audio/station_sounds.gd"]:
		for m in rx.search_all(FileAccess.get_file_as_string(f)):
			kinds[m.get_string(1)] = true
	for k in q.FOLEY:
		for e in q.FOLEY[k]:
			if String(e[1]) not in ["brush_scrub", "trickle"]:     # built per action (play_custom)
				kinds[String(e[1])] = true
	var silent: Array = []
	for k in kinds:
		if snd.stream_for(StringName(k)) == null:
			silent.append(k)
	_check("every sound kind the game plays has a real stream (%d kinds; silent: %s)" % [kinds.size(), str(silent)], silent.is_empty() and kinds.has("glass_knock") and kinds.has("hatch_knock"))
	var g: AudioStreamWAV = snd.stream_for(&"glass_knock")
	var h: AudioStreamWAV = snd.stream_for(&"hatch_knock")
	var ge: Array = _band_energy(g, [63, 125, 500, 1000])
	var he: Array = _band_energy(h, [63, 125, 500, 1000])
	var g_hi: float = (float(ge[2]) + float(ge[3])) / maxf(float(ge[0]) + float(ge[1]), 1e-9)
	var h_hi: float = (float(he[2]) + float(he[3])) / maxf(float(he[0]) + float(he[1]), 1e-9)
	_check("glass knock is glassy (mid/low %.2f), the hatch knock a deep steel boom (%.3f)" % [g_hi, h_hi], g_hi > h_hi * 20.0)
	_check("...and short (%.2f s) vs the hatch's long ring (%.2f s)" % [g.get_length(), h.get_length()], g.get_length() < 0.7 and h.get_length() > 1.0)
	var a: AudioStream = snd.stream_for(&"glass_knock")
	var b: AudioStream = snd.stream_for(&"glass_knock")
	_check("several takes rotate (no identical machine-gun repeats)", a != b)


func _knock_levels() -> void:
	var hp: Vector3 = load("res://scripts/story/window_hand.gd").KNOCK_POS
	var spots := {"observation spot": Vector3(-0.45, 1.6, 1.13), "Control Room centre": Vector3(0.3, 1.6, 0.0), "at the workstation": Vector3(0.6, 1.6, -0.6), "Engineering (walls between)": Vector3(-3.0, 1.6, 4.4)}
	var res := {}
	for k in spots:
		await _aim(spots[k], spots[k] + Vector3(0, 0, -1))
		snd.play_at(&"glass_knock", hp, false)
		res[k] = _last("glass_knock")
		print("  glass knock heard at %s: %.1f m, %d walls, %.1f dB, low-pass %.0f Hz, played %s" % [k, float(res[k]["dist"]), int(res[k]["walls"]), float(res[k]["db"]), float(res[k]["cutoff"]), res[k].get("played")])
	for k in ["observation spot", "Control Room centre", "at the workstation"]:
		_check("Control Room (%s): REALLY played, no wall, unfiltered, %.1f dB" % [k, float(res[k]["db"])], bool(res[k]["played"]) and int(res[k]["walls"]) == 0 and float(res[k]["cutoff"]) >= 8000.0 and float(res[k]["db"]) > -6.0)
	var far: Dictionary = res["Engineering (walls between)"]
	_check("from Engineering: through walls, quieter and muffled (%.1f dB, %d walls)" % [float(far["db"]), int(far["walls"])], int(far["walls"]) >= 1 and float(far["db"]) < float(res["Control Room centre"]["db"]) - 8.0 and float(far["cutoff"]) < 3000.0)
	_check("on the SFX bus (not muted by a missing bus)", String(res["observation spot"].get("bus", "")) == "SFX" and not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	_check("source is the pane's cabin face (x %.2f, inside the hull)" % hp.x, hp.x > -1.2 and hp.x < -1.1)


func _hand_sequence() -> void:
	dp.day_number = 5
	await _aim(Vector3(0.3, 1.6, 0.4), Vector3(1.5, 1.4, -0.8))
	snd.heard = []
	se.dev_trigger(&"window_hand")
	se.set_process(false)
	var h: Node3D = se.hand_node()
	var dt := 1.0 / 60.0
	var times: Array = []
	var t := 0.0
	var vis_during := true
	# The player turns to look at it right after the FIRST knock: the other
	# two must still come.
	while t < 1.4:
		var looking: bool = t > 0.1
		h.tick(dt, looking)
		t += dt
		for e in snd.heard:
			if String(e["kind"]) == "glass_knock" and not e.has("_seen"):
				e["_seen"] = true
				times.append(t)
				vis_during = vis_during and h.visible
	var gaps: Array = []
	for i in range(1, times.size()):
		gaps.append(snappedf(float(times[i]) - float(times[i - 1]), 0.01))
	_check("three knocks even when looked at during them (%s, gaps %s)" % [str(times.size()), str(gaps)], times.size() == 3)
	_check("rhythm: one ... a pause ... two (gaps %s)" % str(gaps), gaps.size() == 2 and float(gaps[0]) > 0.45 and float(gaps[1]) < 0.35)
	_check("all three really played", snd.heard.filter(func(e): return String(e["kind"]) == "glass_knock").all(func(e): return bool(e.get("played", false))))
	_check("the hand is at the glass while it knocks", vis_during)
	var w := 0.0
	while h.state != "gone" and w < 3.0:
		h.tick(dt, false)
		w += dt
	_check("...then it withdraws (%.2f s after the last knock)" % w, h.state == "gone" and w < 1.6)
	_check("no real airlock effect (hatch untouched)", snd.heard.all(func(e): return String(e["kind"]) != "hatch_knock"))
	se.set_process(true)


## Drives a foley timeline in 60 Hz steps for `seconds`; returns the log.
func _run_foley(kind: String, seconds: float) -> Array:
	q._pending = kind
	q.start_foley(kind, seconds)
	var t := 0.0
	while t < seconds - 0.001:
		q._tick_foley(1.0 / 60.0)
		t += 1.0 / 60.0
	var log: Array = q.foley_log.duplicate()
	q._pending = ""
	q._tick_foley(0.0)
	return log


func _at(log: Array, kind: String) -> float:
	for e in log:
		if String(e["kind"]) == kind:
			return float(e["t"])
	return -1.0


func _foley() -> void:
	await _aim(Vector3(3.1, 1.6, -0.3), Vector3(3.1, 1.0, -1.2))
	var D: float = q.DRINK_S
	var tea: Array = _run_foley("tea", D)
	_check("tea: lift -> liquid -> sip -> swallow -> mug down, in that order (%s)" % str(tea.map(func(e): return e["kind"])), tea.map(func(e): return String(e["kind"])) == ["cup_lift", "liquid_tilt", "sip", "swallow", "cup_down"])
	_check("...the sip at the cup's tilt (at the mouth: %.2f s of %.1f)" % [_at(tea, "sip"), D], _at(tea, "sip") >= 0.28 * D and _at(tea, "sip") <= 0.6 * D)
	_check("...the mug set down as the arm lowers (%.2f s), not after" % _at(tea, "cup_down"), _at(tea, "cup_down") >= 0.78 * D and _at(tea, "cup_down") < D)
	var E: float = q.EAT_S
	var meal: Array = _run_foley("meal", E)
	var bites: Array = meal.filter(func(e): return String(e["kind"]) == "bite")
	_check("pouch meal: tear, 2 bites while the hand is at the mouth, chews, swallow, pouch away", meal.size() == 7 and bites.size() == 2 and bites.all(func(e): return float(e["t"]) >= 0.28 * E and float(e["t"]) <= 0.78 * E))
	var dinner: Array = _run_foley("dinner", E + 0.6)
	_check("tray dinner differs (tray + fork clinks, %d sounds)" % dinner.size(), dinner.any(func(e): return String(e["kind"]) == "fork_clink") and not dinner.any(func(e): return String(e["kind"]) == "pouch_tear"))
	var B: float = q.BRUSH_S
	snd.heard = []
	var brush: Array = _run_foley("brush", B)
	var scrub: Dictionary = _last("brush_scrub")
	_check("brushing: tap, scrub from the moment the brush reaches the mouth (%.2f s), tap" % _at(brush, "brush_scrub"), brush.map(func(e): return String(e["kind"])) == ["brush_tap", "brush_scrub", "brush_tap"] and absf(_at(brush, "brush_scrub") - 0.28 * B) < 0.05)
	_check("...the scrub lasts exactly the at-mouth phase (%.2f s), quiet, at the mouth" % float(scrub.get("len", 0.0)), absf(float(scrub.get("len", 0.0)) - 0.5 * B) < 0.02 and float(scrub["db"]) < -12.0 and float(scrub["dist"]) < 0.3)
	_check("no running water while brushing (no rinse in the animation)", not brush.any(func(e): return String(e["kind"]) in ["trickle", "dispense"]))
	# Cancelled half-way: nothing more plays.
	q._pending = "tea"
	q.start_foley("tea", D)
	for i in 30:
		q._tick_foley(1.0 / 60.0)
	q._pending = ""
	var n0: int = q.foley_log.size()
	for i in 120:
		q._tick_foley(1.0 / 60.0)
	_check("an interrupted action plays nothing more (%d sounds)" % n0, q.foley_log.size() == n0)
	# Mouth sounds are quiet; hull impacts are not.
	snd.heard = []
	q._pending = "tea"
	q.start_foley("tea", D)
	for i in int(D * 60.0):
		q._tick_foley(1.0 / 60.0)
	q._pending = ""
	_check("the sip is understated (%.1f dB at the mouth)" % float(_last("sip")["db"]), float(_last("sip")["db"]) < -12.0 and bool(_last("sip")["played"]))


func _voice() -> void:
	var iv: Node = main.get_tree().get_first_node_in_group(&"inner_voice")
	var IV: Script = iv.get_script()
	_check("inner voice: non-positional player on its own InnerVoice bus (not the assistant's)", iv._player is AudioStreamPlayer and iv._player.bus == "InnerVoice" and AudioServer.get_bus_index("InnerVoice") != -1)
	var GS: Script = load("res://scripts/station/game_settings.gd")
	var vol0: float = float(GS.get_value("thought_volume"))
	GS._values["thought_volume"] = 0.5
	GS.apply_one("thought_volume")
	_check("its own volume setting drives the InnerVoice bus (%.1f dB at 50%%)" % AudioServer.get_bus_volume_db(AudioServer.get_bus_index("InnerVoice")), absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("InnerVoice")) - linear_to_db(0.5)) < 0.1)
	GS._values["thought_volume"] = vol0
	GS.apply_one("thought_volume")
	_check("no robotic fallback: with no natural voice and no pack, captions only (%s)" % iv.backend(), iv.voice_source("en") == "captions" or IV.natural_voice("en") != "" or IV.has_recorded_pack("en"))
	# A recorded pack in a temp folder (never the player's user dir).
	var tmp: String = OS.get_environment("TMPDIR").path_join("smh_voice_test_%d/" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(tmp + "en")
	var w: AudioStreamWAV = load("res://scripts/audio/foley_synth.gd").sip()
	w.save_to_wav(tmp + "en/" + IV.line_key("test:line") + ".wav")
	var dirs0: Array = IV.RECORDED_DIRS.duplicate()
	IV.RECORDED_DIRS = [tmp]
	_check("a recorded pack is detected and preferred", IV.has_recorded_pack("en") and iv.voice_source("en") == "recorded" and iv.backend().begins_with("recorded"))
	iv.queue = []
	iv.current = {"id": "test:line", "text": "Was that always there?", "lang": "en"}
	iv._start_voice("Was that always there?", "en")
	_check("...the recorded line plays (%s)" % iv.last_played.get_file(), iv._player.playing and iv.last_played.ends_with(".wav"))
	iv._player.stop()
	iv.last_played = ""
	iv.current = {"id": "test:missing", "text": "Something else.", "lang": "en"}
	iv._start_voice("Something else.", "en")
	_check("...a line the pack lacks is caption-only (never another voice)", not iv._player.playing and iv.last_played == "")
	# The assistant interrupts a spoken thought.
	iv.current = {"id": "test:line", "text": "Was that always there?", "lang": "en"}
	iv._show_t = 4.0
	iv._start_voice("Was that always there?", "en")
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nfunc is_showing() -> bool:\n\treturn true\n"
	stub_script.reload()
	var stub := Node.new()
	stub.set_script(stub_script)
	stub.add_to_group(&"station_ai")
	main.add_child(stub)
	var i0: int = iv.interrupted
	iv._process(0.016)
	_check("the station assistant interrupts a spoken thought (caption stays)", not iv._player.playing and iv.interrupted == i0 + 1 and not iv.current.is_empty())
	stub.queue_free()
	iv.current = {}
	IV.RECORDED_DIRS = dirs0
	for f in DirAccess.get_files_at(tmp + "en"):
		DirAccess.remove_absolute(tmp + "en/" + f)
	DirAccess.remove_absolute(tmp + "en")
	DirAccess.remove_absolute(tmp)
	_check("temp voice pack cleaned up", not DirAccess.dir_exists_absolute(tmp))
	# Settings show what will be heard, in both languages.
	var L10N: Script = load("res://scripts/ui/localization.gd")
	_check("settings explain the voice source (EN + ZH strings)", String(L10N.TABLES["en"].get("VOICE_SRC_NONE", "")).contains("Enhanced") and String(L10N.TABLES["zh_CN"].get("VOICE_SRC_NONE", "")) != "")


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
