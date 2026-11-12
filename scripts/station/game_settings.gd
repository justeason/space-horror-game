extends Object
## Round 10 Workstream E: the ONE authoritative global "Game Difficulty"
## setting, consulted by every difficulty-sensitive system in the game
## instead of each task owning its own duplicate difficulty field.
## Player request verbatim: "Difficulty must apply across the entire
## game, rather than belonging to an individual electrical repair task."
##
## Currently consulted by: electrical_panel.gd (E05 hints/screw count)
## and workstation_screen.gd's C02 diagnostic readout verbosity. Any
## future difficulty-sensitive task should call GameSettings.get_difficulty()
## directly rather than exporting its own copy.
##
## NOT a scene-tree autoload, and deliberately NOT a `class_name` global
## either: this environment's own headless test scripts (tests/*.gd,
## extends SceneTree, manually instantiate main.tscn) run via
## `godot --headless --script`, a mode that does NOT process
## project.godot's [autoload] section, and -- confirmed directly --
## does not reliably pick up a brand-new `class_name` global without a
## prior full project scan/cache rebuild either (the global class cache
## is only written by a normal editor/project run, not a bare --script
## invocation). Every consumer therefore reaches this file via
## `const GameSettings = preload("res://scripts/station/game_settings.gd")`
## instead, which resolves at parse time regardless of global class
## registration and works identically in-game and in every test. Plain
## `static var`s need no node in the tree, so this still behaves as one
## process-wide singleton either way.
##
## PERSISTENCE: no save/load system exists anywhere in this project yet,
## and this milestone explicitly says not to add one as a side effect of
## this feature. This is a small, ISOLATED mechanism scoped to this one
## value only: a single ConfigFile key, lazily read back the first time
## any script asks for the difficulty, and written again immediately on
## every change. A brand-new game/launch with no existing settings file
## defaults to NORMAL. This means difficulty persists ACROSS LAUNCHES
## (not just within one play session) on this one setting alone -- see
## MILESTONE1_DESIGN.md's Round 10 section for the documented policy.
##
## MID-REPAIR POLICY: changing this value takes effect immediately for
## any task not yet started. electrical_panel.gd snapshots the current
## value the first time its door is opened and holds that snapshot
## fixed for the rest of that one (non-repeatable) repair, so an
## in-progress repair's screw/hint requirements never appear or
## disappear mid-task -- see that script's `_active_difficulty`.
enum Difficulty { EASY, NORMAL, HARD }

const _DEFAULT_SETTINGS_PATH := "user://game_settings.cfg"
## Round 36: tests/run_tests.sh points this at a scratch file (environment
## variable SMH_SETTINGS_PATH) so the regression suite never writes the
## player's real settings. Unset in normal play.
static var _SETTINGS_PATH: String = OS.get_environment("SMH_SETTINGS_PATH") if OS.get_environment("SMH_SETTINGS_PATH") != "" else _DEFAULT_SETTINGS_PATH


static func settings_path() -> String:
	return _SETTINGS_PATH
const _SECTION := "gameplay"
const _KEY := "difficulty"

static var _difficulty: Difficulty = Difficulty.NORMAL
static var _loaded: bool = false


## The one sanctioned read accessor -- guarantees the persisted value
## has been loaded (lazily, once per process) before returning it.
static func get_difficulty() -> Difficulty:
	_ensure_loaded()
	return _difficulty


static func difficulty_name() -> StringName:
	match get_difficulty():
		Difficulty.EASY: return &"easy"
		Difficulty.HARD: return &"hard"
	return &"normal"


## Cycles EASY -> NORMAL -> HARD -> EASY and persists immediately.
static func cycle_difficulty() -> void:
	_ensure_loaded()
	_difficulty = ((_difficulty + 1) % 3) as Difficulty
	_save()


## Round 33: restored from a save game (persists like cycle_difficulty()).
static func set_difficulty(value: int) -> void:
	_ensure_loaded()
	if value >= Difficulty.EASY and value <= Difficulty.HARD:
		_difficulty = value as Difficulty
		_save()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return
	var value: int = cfg.get_value(_SECTION, _KEY, Difficulty.NORMAL)
	if value >= Difficulty.EASY and value <= Difficulty.HARD:
		_difficulty = value as Difficulty


static func _save() -> void:
	var cfg := ConfigFile.new()
	# Round 36 fix: keep the other sections (player settings). This used to
	# write a fresh file holding only the difficulty, silently discarding
	# every saved player setting the next time difficulty changed.
	cfg.load(_SETTINGS_PATH)
	cfg.set_value(_SECTION, _KEY, _difficulty)
	cfg.save(_SETTINGS_PATH)


# ======================================================================
# Round 34 Priority 9: PLAYER SETTINGS -- persisted in the same
# user://game_settings.cfg, independent of any game save. Every value is
# APPLIED for real: audio bus volumes, window mode/size, mouse look
# sensitivity/inversion (look_controller.gd reads them), and the locale.
# ======================================================================
const AUDIO_BUSES := ["Master", "Ambient", "SFX", "UI", "Voice"]
const WINDOW_SIZES := [Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const LANGUAGES := ["en", "zh_CN"]
const DEFAULTS := {
	"vol_Master": 1.0, "vol_Ambient": 1.0, "vol_SFX": 1.0, "vol_UI": 1.0, "vol_Voice": 1.0,
	"fullscreen": false, "window_size": 0, "mouse_sensitivity": 1.0, "invert_y": false, "language": "en",
	"reduce_effects": false,
	# Round 36: the station operations assistant (see station_ai.gd).
	"ai_guidance": true, "ai_voice": true, "ai_captions": true,
	# Round 37: interface scale on top of the automatic resolution scaling,
	# and steady (non-flashing) warning lights.
	"ui_scale": 1.0, "steady_warnings": false,
	# Round 44: the technician's inner voice + display brightness.
	"thought_voice": true, "thought_captions": true, "brightness": 1.0,
	# Round 48: the inner voice's own volume (its InnerVoice bus).
	"thought_volume": 1.0,
}
const UI_SCALES := [0.8, 0.9, 1.0, 1.15, 1.3, 1.5]
static var _values: Dictionary = {}
static var _values_loaded: bool = false


static func _ensure_values() -> void:
	if _values_loaded:
		return
	_values_loaded = true
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return
	for k in DEFAULTS:
		var v: Variant = cfg.get_value("player", k, DEFAULTS[k])
		if typeof(v) == typeof(DEFAULTS[k]) or (DEFAULTS[k] is float and v is int):
			_values[k] = v


static func get_value(key: String) -> Variant:
	_ensure_values()
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_ensure_values()
	_values[key] = value
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)   # keep other sections (difficulty)
	cfg.set_value("player", key, value)
	cfg.save(_SETTINGS_PATH)
	apply_one(key)


static func apply_all() -> void:
	_ensure_values()
	for k in DEFAULTS:
		apply_one(k)


static func apply_one(key: String) -> void:
	if key.begins_with("vol_"):
		_ensure_buses()
		var idx: int = AudioServer.get_bus_index(key.substr(4))
		if idx != -1:
			var lin: float = clampf(float(get_value(key)), 0.0, 1.0)
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(lin, 0.0001)))
			AudioServer.set_bus_mute(idx, lin <= 0.001)
	elif key == "thought_volume":
		var ti: int = AudioServer.get_bus_index("InnerVoice")
		if ti != -1:
			var tl: float = clampf(float(get_value(key)), 0.0, 1.0)
			AudioServer.set_bus_volume_db(ti, linear_to_db(maxf(tl, 0.0001)))
			AudioServer.set_bus_mute(ti, tl <= 0.001)
	elif key == "fullscreen" or key == "window_size":
		if DisplayServer.get_name() == "headless":
			return
		if bool(get_value("fullscreen")):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(WINDOW_SIZES[clampi(int(get_value("window_size")), 0, WINDOW_SIZES.size() - 1)])
	elif key == "ui_scale":
		# Round 37: the project stretches the 2D UI with the window
		# (canvas_items, 1152x648 base); this multiplies that factor.
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			tree.root.content_scale_factor = clampf(float(get_value("ui_scale")), 0.6, 2.0)
	elif key == "brightness":
		# Round 44: overall brightness = the world environment's exposure
		# (tonemap), applied wherever a WorldEnvironment exists.
		var tree2: SceneTree = Engine.get_main_loop() as SceneTree
		if tree2 != null and tree2.current_scene != null:
			for we in tree2.current_scene.find_children("*", "WorldEnvironment", true, false):
				var env: Environment = (we as WorldEnvironment).environment
				if env != null:
					env.tonemap_exposure = clampf(float(get_value("brightness")), 0.6, 1.5)
	elif key == "language":
		preload("res://scripts/ui/localization.gd").setup()
		TranslationServer.set_locale(String(get_value("language")))


## Buses come from res://default_bus_layout.tres; created here as a fallback.
static func _ensure_buses() -> void:
	for b in AUDIO_BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


static func mouse_sensitivity_scale() -> float:
	return clampf(float(get_value("mouse_sensitivity")), 0.2, 3.0)


static func invert_y() -> bool:
	return bool(get_value("invert_y"))
