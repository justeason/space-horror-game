extends CanvasLayer
## Round 44 Priority 4: the technician's INNER VOICE -- short, rare,
## first-person thoughts when something worth a second look has REALLY been
## observed ("That's strange. I haven't been in Storage today."). It never
## explains and never gives the answer; it only says what the character
## noticed.
##
## Distinct from the Station Operations Assistant in every channel:
##   - caption: centred, warm pale tone in quotation marks, above the
##     assistant's caption strip; no speaker label;
##   - voice (optional, setting "thought_voice"): a quieter, more natural
##     local voice (macOS `say`, "Flo"), NON-spatial, on its own
##     "InnerVoice" bus (low-passed, a touch of room) feeding Voice -- it
##     sounds inside the head, never from a wall speaker. Headless runs and
##     platforms without `say` show captions only (honestly reported by
##     backend()).
## Pacing: each thought id at most once (saved), a cooldown between
## thoughts, never over an assistant line (waits for it to finish).

const GS = preload("res://scripts/station/game_settings.gd")
const SAY := "/usr/bin/say"
const VOICE := {"en": ["Flo (English (US))", 160], "zh": ["Flo (Chinese (China mainland))", 175]}
const COOLDOWN_S := 20.0
const SHOW_S := 4.2
const CACHE_DIR := "user://voice_cache/"

var said: Dictionary = {}          # id -> day first thought (saved)
var history: Array = []            # [{id, text, day}] (session + saved, journal source)
var queue: Array = []              # [{id, text, lang}]
var current: Dictionary = {}
var _label: Label
var _show_t: float = 0.0
var _cool: float = 0.0
var _player: AudioStreamPlayer
var _task: int = -1
var _task_path: String = ""
signal thought(id: String, text: String)


func _ready() -> void:
	layer = 6
	add_to_group(&"inner_voice")
	_label = Label.new()
	_label.name = "ThoughtCaption"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -360
	_label.offset_right = 360
	_label.offset_top = -168
	_label.offset_bottom = -128
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)
	_ensure_bus()
	_player = AudioStreamPlayer.new()
	_player.bus = "InnerVoice"
	_player.volume_db = -5.0
	add_child(_player)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


static func _ensure_bus() -> void:
	if AudioServer.get_bus_index("InnerVoice") != -1:
		return
	AudioServer.add_bus()
	var i: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, "InnerVoice")
	AudioServer.set_bus_send(i, "Voice" if AudioServer.get_bus_index("Voice") != -1 else "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3800.0
	AudioServer.add_bus_effect(i, lp)
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.15
	rv.wet = 0.08
	rv.dry = 0.95
	AudioServer.add_bus_effect(i, rv)


func _lang() -> String:
	return "zh" if String(GS.get_value("language")).begins_with("zh") else "en"


## Queue a thought. Returns false if this id was already thought.
func think(id: String, en: String, zh: String = "", once: bool = true) -> bool:
	if once and said.has(id):
		return false
	for q in queue:
		if q["id"] == id:
			return false
	var lang: String = _lang()
	var text: String = zh if lang == "zh" and zh != "" else en
	said[id] = _day()
	queue.append({"id": id, "text": text, "lang": lang})
	return true


func _day() -> int:
	var dp: Node = get_tree().get_first_node_in_group(&"day_plan") if is_inside_tree() else null
	return int(dp.day_number) if dp != null else 1


func _ai_busy() -> bool:
	for a in get_tree().get_nodes_in_group(&"station_ai"):
		if a.has_method("is_showing") and a.is_showing():
			return true
	return false


func is_showing() -> bool:
	return not current.is_empty()


func backend() -> String:
	if not bool(GS.get_value("thought_voice")):
		return "captions (voice off)"
	if DisplayServer.get_name() == "headless" or not FileAccess.file_exists(SAY):
		return "captions only (no local voice)"
	return "local voice (say: %s)" % VOICE[_lang()][0]


func _process(delta: float) -> void:
	if not current.is_empty():
		_show_t -= delta
		_poll_voice()
		if _show_t <= 0.0 and not _player.playing:
			current = {}
			_label.visible = false
			_cool = COOLDOWN_S
		return
	_cool = maxf(_cool - delta, 0.0)
	if queue.is_empty() or _cool > 0.0 or _ai_busy():
		return
	current = queue.pop_front()
	_show_t = SHOW_S
	_label.text = "“%s”" % current["text"]
	_label.visible = bool(GS.get_value("thought_captions"))
	history.append({"id": current["id"], "text": current["text"], "day": _day()})
	thought.emit(String(current["id"]), String(current["text"]))
	_start_voice(String(current["text"]), String(current["lang"]))


func _start_voice(text: String, lang: String) -> void:
	if not backend().begins_with("local voice"):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var v: Array = VOICE.get(lang, VOICE["en"])
	var path: String = CACHE_DIR + "thought_%s.wav" % ("%s|%s|%s" % [v[0], lang, text]).md5_text()
	_task_path = path
	if FileAccess.file_exists(path):
		_task = -1
		_play(path)
		return
	_task = WorkerThreadPool.add_task(_render.bind(text, ProjectSettings.globalize_path(path), String(v[0]), int(v[1])), false, "thought render")


static func _render(text: String, abs_path: String, voice: String, rate: int) -> void:
	var tmp: String = abs_path + ".part.wav"
	var out: Array = []
	if OS.execute(SAY, ["-v", voice, "-r", str(rate), "-o", tmp, "--data-format=LEI16@22050", text], out, true) == 0 and FileAccess.file_exists(tmp):
		DirAccess.rename_absolute(tmp, abs_path)


func _poll_voice() -> void:
	if _task == -1 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if not current.is_empty():
		_play(_task_path)


func _play(path: String) -> void:
	var s: AudioStreamWAV = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	if s != null:
		_player.stream = s
		_player.play()


## Developer / tests: flush the queue (show the next one now).
func flush() -> void:
	_cool = 0.0


func state_dict() -> Dictionary:
	return {"said": said.duplicate(), "history": history.slice(maxi(history.size() - 30, 0))}


func load_dict(d: Dictionary) -> void:
	said = {}
	var s: Dictionary = d.get("said", {})
	for k in s:
		said[String(k)] = int(s[k])
	history = []
	for h in Array(d.get("history", [])):
		if h is Dictionary:
			history.append({"id": String(h.get("id", "")), "text": String(h.get("text", "")), "day": int(h.get("day", 1))})
	queue = []
	current = {}
	if _label != null:
		_label.visible = false
