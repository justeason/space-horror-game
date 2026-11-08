extends Node
## Round 36 Priority 5A: the STATION ASSISTANT's speech backend -- a small,
## replaceable interface (speak / stop / is_speaking / backend_name).
##
## Round 37: SPATIAL SPEECH (preferred where available). macOS's built-in
## `say` renders the line to a 16-bit WAV (worker thread, cached in
## user://voice_cache/), which is loaded at runtime (AudioStreamWAV) and
## played through a physical intercom speaker (station_speakers.gd) as an
## AudioStreamPlayer3D on the Intercom -> Voice bus: genuinely positional
## (direction + distance), and genuinely on the Voice bus. Local only: no
## network, no credentials. Elsewhere / on failure the platform TTS below
## is used (non-positional) and backend_for() reports that honestly.
##
## Backends, tried in order for every line:
##   1. RECORDED VOICE: res://audio/voice/<lang>/<line_key>.ogg (or .wav),
##      played on the Godot "Voice" bus. No such files exist yet -- this is
##      the seam for recorded voice assets later (none are invented here).
##   2. PLATFORM TEXT-TO-SPEECH: Godot's DisplayServer TTS (macOS
##      AVSpeechSynthesizer, Windows SAPI, Linux speech-dispatcher), enabled
##      by project setting audio/general/text_to_speech. This is OS audio,
##      NOT routed through Godot's audio buses: the Voice and Master bus
##      volumes are applied to its own 0-100 volume parameter instead, and a
##      silent bus mutes it. It is not captured by Godot's movie writer.
##   3. NONE (captions only): headless display, setting off, or no installed
##      voice for the language. backend_name() then says so honestly.
##
## No callbacks are registered with the OS synthesizer (polling
## tts_is_speaking() instead): a callback bound to a freed node during a
## scene reload/quit crashed the process in testing (libc++ recursive_mutex
## abort at exit); stop() is always called on exit_tree.

const GS = preload("res://scripts/station/game_settings.gd")
const PREFERRED_VOICES := {"en": ["Samantha", "Ava", "Allison", "Karen", "Daniel", "Moira"], "zh": ["Tingting", "Meijia", "Lili", "Yu-shu"]}

var spoken_log: Array = []          # [{key, lang, backend, text, volume, t}]
var _player: AudioStreamPlayer
var _voice_cache: Dictionary = {}   # lang -> voice id ("" = none)
var _tts_started_ms: int = -1
var _recorded_playing: bool = false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "RecordedVoice"
	_player.bus = "Voice" if AudioServer.get_bus_index("Voice") != -1 else "Master"
	add_child(_player)
	_player.finished.connect(func(): _recorded_playing = false)


func _exit_tree() -> void:
	stop()
	_prewarm_queue.clear()
	# Never leave a render task unawaited (scene reload / quit).
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
	_prewarm_task = -1


static func lang_family(locale: String) -> String:
	return "zh" if locale.begins_with("zh") else "en"


const SAY := "/usr/bin/say"
const CACHE_DIR := "user://voice_cache/"
const SAY_VOICE := {"en": ["Samantha", 168], "zh": ["Tingting", 185]}
var speakers: Node = null            # station_speakers.gd (set by StationAI)
var _pending: Dictionary = {}        # {task, path, unit, key, lang}
var _spatial_unit: StringName = &""
var _prewarm_queue: Array = []       # [[text, lang]]
var _prewarm_task: int = -1
var _tasks: Array = []               # every render task started (awaited on exit)


var force_os_tts: bool = false       # tools/verify_station_ai_speech.gd: test the fallback


func spatial_supported() -> bool:
	if force_os_tts or speakers == null or not FileAccess.file_exists(SAY):
		return false
	# Headless runs (the test suite) have no audio output: rendering there
	# only costs time -- unless a test asks for it explicitly.
	return DisplayServer.get_name() != "headless" or OS.get_environment("SMH_SPATIAL_SPEECH") == "1"


func _cache_path(text: String, lang: String) -> String:
	var v: Array = SAY_VOICE.get(lang, SAY_VOICE["en"])
	return CACHE_DIR + ("%s_%d_%s.wav" % [v[0], v[1], ("%s|%s" % [lang, text]).md5_text()])


## Renders `text` to the cache (blocking; worker threads only).
static func _render(text: String, path: String, voice: String, rate: int) -> void:
	var abs_path: String = ProjectSettings.globalize_path(path)
	var tmp: String = abs_path + ".part.wav"
	var out: Array = []
	var code: int = OS.execute(SAY, ["-v", voice, "-r", str(rate), "-o", tmp, "--data-format=LEI16@22050", text], out, true)
	if code == 0 and FileAccess.file_exists(tmp):
		DirAccess.rename_absolute(tmp, abs_path)


func _start_render(text: String, lang: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var path: String = _cache_path(text, lang)
	if FileAccess.file_exists(path):
		return {"task": -1, "path": path}
	var v: Array = SAY_VOICE.get(lang, SAY_VOICE["en"])
	var t: int = WorkerThreadPool.add_task(_render.bind(text, path, String(v[0]), int(v[1])), false, "say render")
	_tasks.append(t)
	return {"task": t, "path": path}


## Background pre-rendering of known lines (one at a time, low priority).
func prewarm(lines: Array) -> void:
	if not spatial_supported():
		return
	for l in lines:
		if not FileAccess.file_exists(_cache_path(l[0], l[1])):
			_prewarm_queue.append(l)


func _process(_d: float) -> void:
	if _prewarm_task != -1 and WorkerThreadPool.is_task_completed(_prewarm_task):
		WorkerThreadPool.wait_for_task_completion(_prewarm_task)
		_tasks.erase(_prewarm_task)
		_prewarm_task = -1
	if _prewarm_task == -1 and _pending.is_empty() and not _prewarm_queue.is_empty():
		var l: Array = _prewarm_queue.pop_front()
		var r: Dictionary = _start_render(l[0], l[1])
		_prewarm_task = int(r["task"])
	if _pending.is_empty():
		return
	var task: int = int(_pending["task"])
	if task != -1 and not WorkerThreadPool.is_task_completed(task):
		if Time.get_ticks_msec() - int(_pending["t0"]) > 6000:
			_fallback_pending()   # renderer stuck: speak via the OS instead
		return
	if task != -1:
		WorkerThreadPool.wait_for_task_completion(task)
		_tasks.erase(task)
	var path: String = String(_pending["path"])
	var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	if stream == null:
		_fallback_pending()
		return
	speakers.play_voice(_pending["unit"], stream, 0.985)
	_spatial_unit = _pending["unit"]
	_pending = {}


func _fallback_pending() -> void:
	var p: Dictionary = _pending
	_pending = {}
	if tts_supported() and voice_for(p["lang"]) != "":
		DisplayServer.tts_speak(p["text"], voice_for(p["lang"]), effective_volume(), 1.0, 1.0, 0, true)
		_tts_started_ms = Time.get_ticks_msec()
		if not spoken_log.is_empty():
			spoken_log[spoken_log.size() - 1]["backend"] = "tts (spatial render failed)"


func tts_supported() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return false
	return true


## The voice id used for a language family ("" when none is installed).
func voice_for(lang: String) -> String:
	if _voice_cache.has(lang):
		return _voice_cache[lang]
	var id := ""
	if tts_supported():
		var all: Array = DisplayServer.tts_get_voices()
		for want in PREFERRED_VOICES.get(lang, []):
			for v in all:
				if String(v.get("name", "")) == want and String(v.get("language", "")).begins_with("zh" if lang == "zh" else "en"):
					id = String(v.get("id", ""))
					break
			if id != "":
				break
		if id == "":
			var ids: PackedStringArray = DisplayServer.tts_get_voices_for_language(lang)
			if ids.size() > 0:
				id = ids[0]
	_voice_cache[lang] = id
	return id


func _recorded_stream(key: StringName, lang: String) -> AudioStream:
	for ext in ["ogg", "wav"]:
		var p := "res://audio/voice/%s/%s.%s" % [lang, String(key), ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null


## 0..100 from the Master and Voice bus settings (0 = silent).
static func effective_volume() -> int:
	var m: float = clampf(float(GS.get_value("vol_Master")), 0.0, 1.0)
	var v: float = clampf(float(GS.get_value("vol_Voice")), 0.0, 1.0)
	return roundi(100.0 * m * v)


## Which backend a line in `lang` would use right now.
func backend_for(key: StringName, lang: String) -> String:
	if _recorded_stream(key, lang) != null:
		return "recorded"
	if spatial_supported():
		return "spatial"
	if tts_supported() and voice_for(lang) != "":
		return "tts"
	return "none"


func backend_name(lang: String = "en") -> String:
	match backend_for(&"", lang):
		"recorded": return "recorded voice files (Voice bus)"
		"spatial": return "spatial intercom speech (macOS say -> AudioStreamPlayer3D at the room speaker, Intercom/Voice bus, voice %s)" % SAY_VOICE.get(lang, SAY_VOICE["en"])[0]
		"tts": return "platform text-to-speech (%s, voice %s)" % [DisplayServer.get_name(), voice_for(lang)]
	if DisplayServer.get_name() == "headless":
		return "none (headless display: captions only)"
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return "none (text-to-speech disabled in project settings: captions only)"
	return "none (no installed %s voice: captions only)" % lang


## Speaks one line, interrupting anything still playing. Returns the
## backend used ("recorded" | "tts" | "none" | "muted").
func speak(key: StringName, text: String, lang: String, unit: StringName = &"") -> String:
	stop()
	var vol: int = effective_volume()
	var backend: String = backend_for(key, lang)
	if vol <= 0:
		backend = "muted"
	if backend == "spatial" and unit == &"":
		backend = "tts" if tts_supported() and voice_for(lang) != "" else "none"
	match backend:
		"spatial":
			var r: Dictionary = _start_render(text, lang)
			_pending = {"task": r["task"], "path": r["path"], "unit": unit, "key": key, "lang": lang, "text": text, "t0": Time.get_ticks_msec()}
		"recorded":
			_player.stream = _recorded_stream(key, lang)
			_player.volume_db = 0.0   # the Voice bus carries the setting
			_player.play()
			_recorded_playing = true
		"tts":
			DisplayServer.tts_speak(text, voice_for(lang), vol, 1.0, 1.0, 0, true)
			_tts_started_ms = Time.get_ticks_msec()
	spoken_log.append({"key": String(key), "lang": lang, "backend": backend, "text": text, "volume": vol, "t": Time.get_ticks_msec(), "unit": String(unit)})
	return backend


func stop() -> void:
	_pending = {}
	if speakers != null and is_instance_valid(speakers):
		speakers.stop_voice()
	_spatial_unit = &""
	if _player != null and _player.playing:
		_player.stop()
	_recorded_playing = false
	if _tts_started_ms >= 0 and tts_supported():
		DisplayServer.tts_stop()
	_tts_started_ms = -1


func is_speaking() -> bool:
	if _recorded_playing:
		return true
	if not _pending.is_empty():
		return true
	if _spatial_unit != &"" and speakers != null and is_instance_valid(speakers) and speakers.voice_playing():
		return true
	if _tts_started_ms >= 0 and tts_supported():
		# The synthesizer may need a moment to report "speaking" at all.
		if DisplayServer.tts_is_speaking():
			return true
		return Time.get_ticks_msec() - _tts_started_ms < 400
	return false
