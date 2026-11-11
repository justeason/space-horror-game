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
## Round 46: slower, softer delivery -- reflective, not announced.
const VOICE := {"en": ["Flo (English (US))", 142], "zh": ["Flo (Chinese (China mainland))", 160]}
const VOICE_DB := -11.0             # well under the station assistant
const DUCK_DB := -5.0               # the room recedes while a thought plays
const DUCK_BUSES := ["Ambient", "SFX"]
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
	# Round 46: an INNER caption -- slanted (italic), smaller, soft warm
	# grey, no quotation marks, fading in and out; the assistant's caption
	# is upright, labelled and boxed at the bottom strip.
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	_label.add_theme_font_override("font", fv)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.9, 0.87, 0.8))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)
	_ensure_bus()
	_player = AudioStreamPlayer.new()
	_player.bus = "InnerVoice"
	_player.volume_db = VOICE_DB
	add_child(_player)


func _exit_tree() -> void:
	_set_duck(false)
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
	# Round 46: CLOSE and dry -- no room reverb (a room = a speaker in a
	# room); a gentle band (no boom, no hiss) with a little low-mid warmth,
	# like a voice right at the ear.
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 140.0
	AudioServer.add_bus_effect(i, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3400.0
	AudioServer.add_bus_effect(i, lp)
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(1, 2.5)          # ~230 Hz: proximity warmth
	eq.set_band_gain_db(4, -2.0)         # ~3.3 kHz: less announcer edge
	AudioServer.add_bus_effect(i, eq)


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


# ------------------------------------------- Round 46: everyday thoughts
## Ordinary, restrained thoughts during routine moments -- so the inner
## voice is familiar long before anything is wrong (a thought is not, by
## itself, an anomaly signal). Gated: at most EVERYDAY_PER_DAY a day, one
## per context per day, a deterministic ~45 % chance per moment, and the
## lines rotate (the same phrase does not come back day after day).
const EVERYDAY_PER_DAY := 2
const EVERYDAY_CHANCE := 0.45
const EVERYDAY := {
	"repair": [["That took longer than I expected.", "比我预想的花了更久。"], ["Good. That one's sorted.", "好。这个搞定了。"], ["Done. Hands are filthy.", "完成了。手脏得不行。"]],
	"breakfast": [["At least the food's not terrible today.", "至少今天的饭还不算难吃。"], ["Oats again. Fine.", "又是燕麦。行吧。"], ["Breakfast. Right. Day's started.", "早饭。好，一天开始了。"]],
	"dinner": [["Lentils. Again.", "扁豆。又是扁豆。"], ["Warm food. That helps.", "热饭。有用。"]],
	"tea": [["Tea helps.", "喝茶有用。"], ["Too hot. Worth it.", "太烫了。值得。"]],
	"basil": [["Still hanging in there.", "还撑着呢。"], ["Grow, little thing.", "长吧，小家伙。"]],
	"eva_back": [["Good to be back inside.", "回到里面真好。"], ["Air you don't have to think about.", "不用操心的空气。"]],
	"letter": [["I should write back.", "我该回信了。"], ["It's good to hear from them.", "能收到他们的消息真好。"]],
	"shift_end": [["That's enough work for one day.", "今天的活够多了。"], ["Bed soon.", "该睡了。"]],
}
var everyday_day: int = -1
var everyday_count: int = 0
var everyday_ctx_today: Dictionary = {}
var everyday_uses: Dictionary = {}     # context -> times used (saved: rotation)


func everyday(ctx: String) -> bool:
	if not EVERYDAY.has(ctx):
		return false
	var d: int = _day()
	if d != everyday_day:
		everyday_day = d
		everyday_count = 0
		everyday_ctx_today = {}
	if everyday_count >= EVERYDAY_PER_DAY or everyday_ctx_today.has(ctx) or not queue.is_empty() or not current.is_empty():
		return false
	everyday_ctx_today[ctx] = true
	var roll: float = float(absi(hash("%s:%d" % [ctx, d])) % 1000) / 1000.0
	if roll >= EVERYDAY_CHANCE:
		return false
	var n: int = int(everyday_uses.get(ctx, 0))
	var pool: Array = EVERYDAY[ctx]
	var line: Array = pool[n % pool.size()]
	everyday_uses[ctx] = n + 1
	everyday_count += 1
	return think("everyday:%s:%d" % [ctx, d], line[0], line[1], false)


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
		_set_duck(_player.playing)
		if _show_t <= 0.0 and not _player.playing:
			current = {}
			_fade(0.0, 0.5)
			_set_duck(false)
			_cool = COOLDOWN_S
		return
	_cool = maxf(_cool - delta, 0.0)
	if queue.is_empty() or _cool > 0.0 or _ai_busy():
		return
	current = queue.pop_front()
	_show_t = SHOW_S
	_label.text = String(current["text"])
	_label.visible = bool(GS.get_value("thought_captions"))
	_label.modulate.a = 0.0
	_fade(1.0, 0.35)
	history.append({"id": current["id"], "text": current["text"], "day": _day()})
	thought.emit(String(current["id"]), String(current["text"]))
	_start_voice(String(current["text"]), String(current["lang"]))


func _fade(to: float, s: float) -> void:
	if not is_inside_tree():
		_label.modulate.a = to
		return
	var tw := create_tween()
	tw.tween_property(_label, "modulate:a", to, s)
	if to <= 0.0:
		tw.tween_callback(func(): _label.visible = false if current.is_empty() else _label.visible)


var ducked: bool = false


## While a thought is spoken the room recedes a little (Ambient / SFX), via
## a dedicated Amplify effect on each bus -- the player's volume settings
## (bus volumes) are never touched.
func _set_duck(on: bool) -> void:
	if on == ducked:
		return
	ducked = on
	for b in DUCK_BUSES:
		var fx: AudioEffectAmplify = duck_effect(b)
		if fx != null:
			fx.volume_db = DUCK_DB if on else 0.0


static func duck_effect(bus: String) -> AudioEffectAmplify:
	var i: int = AudioServer.get_bus_index(bus)
	if i == -1:
		return null
	for k in AudioServer.get_bus_effect_count(i):
		var e: AudioEffect = AudioServer.get_bus_effect(i, k)
		if e is AudioEffectAmplify and e.resource_name == "ThoughtDuck":
			return e
	var amp := AudioEffectAmplify.new()
	amp.resource_name = "ThoughtDuck"
	amp.volume_db = 0.0
	AudioServer.add_bus_effect(i, amp)
	return amp


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
	return {"said": said.duplicate(), "history": history.slice(maxi(history.size() - 30, 0)), "everyday_uses": everyday_uses.duplicate()}


func load_dict(d: Dictionary) -> void:
	everyday_uses = (d.get("everyday_uses", {}) as Dictionary).duplicate() if d.get("everyday_uses", {}) is Dictionary else {}
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
