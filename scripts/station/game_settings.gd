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

const _SETTINGS_PATH := "user://game_settings.cfg"
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
	cfg.set_value(_SECTION, _KEY, _difficulty)
	cfg.save(_SETTINGS_PATH)
