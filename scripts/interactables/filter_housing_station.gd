extends StaticBody3D
## Life Support's filter housing -- implements L02 Filter Replacement
## (GAME_DESIGN.md Section 29: "Isolate airflow -> close valves ->
## depressurize -> remove -> match -> install -> restore valves in
## correct order -> verify"). Round 15 Priority 4: a maintenance
## procedure built on ALIGNMENT AND INSERTION rather than wire-sequence
## memory (electrical repair) or discrete valve-open/closed routing
## (coolant loop) -- the new cartridge must be rotated to match the
## housing's keyway before it will seat, not merely clicked in the
## right order.
##
## Same "physical object owns its procedure state; views are
## presentation-only" split as electrical_panel.gd/valve_routing_station.gd.

enum Stage { ISOLATE, OPEN_LATCHES, REMOVE_OLD, ALIGN_INSERT, CLOSE_LATCHES, RESTORE, COMPLETE }

const GameSettings = preload("res://scripts/station/game_settings.gd")

## Fixed puzzle instance (same policy as every other minigame in this
## project): one authored target keyway angle, not randomized.
const _TARGET_ANGLE_DEG: float = 135.0
const _START_ANGLE_DEG: float = 0.0
const _ROTATE_STEP_DEG: float = 45.0

const _TOLERANCE_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: 40.0,
	GameSettings.Difficulty.NORMAL: 20.0,
	GameSettings.Difficulty.HARD: 8.0,
}
## Whether the correct target angle is highlighted for the player, per
## difficulty -- EASY shows it outright, NORMAL/HARD require reading the
## housing's own physical keyway marker instead of a UI hint.
const _SHOW_GUIDE_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: true,
	GameSettings.Difficulty.NORMAL: false,
	GameSettings.Difficulty.HARD: false,
}

@export var day_plan_path: NodePath
@export var filter_view_path: NodePath

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _filter_view: Node = get_node_or_null(filter_view_path)
@onready var _world_diorama: Node = get_node_or_null("WorldDiorama")

var _stage: Stage = Stage.ISOLATE
var _latch_open := {1: false, 2: false}
var _cartridge_angle_deg: float = _START_ANGLE_DEG
var _active_difficulty: int = -1
var _failed_insert_flash: bool = false


func _ready() -> void:
	_sync_world_diorama()


func interact() -> void:
	if _filter_view == null:
		return
	if _active_difficulty == -1:
		_active_difficulty = GameSettings.get_difficulty()
	_filter_view.open_station(self)


func get_interact_prompt() -> String:
	if is_complete():
		return "Click: Check Filter Housing (Nominal)"
	return "Click: Service Filter Housing"


func is_complete() -> bool:
	return _day_plan.is_task_done(&"l02")


func stage() -> Stage:
	return _stage


## True from the moment airflow is isolated (STAGE 1 complete) until
## it's explicitly restored (STAGE 6) -- drives the valve handle's
## open/closed visual independent of the exact stage enum value.
func is_isolated() -> bool:
	return _stage != Stage.ISOLATE and _stage != Stage.COMPLETE


func tolerance_deg() -> float:
	return _TOLERANCE_BY_DIFFICULTY.get(_current_difficulty(), 20.0)


func guide_shown() -> bool:
	return _SHOW_GUIDE_BY_DIFFICULTY.get(_current_difficulty(), false)


func target_angle_deg() -> float:
	return _TARGET_ANGLE_DEG


func cartridge_angle_deg() -> float:
	return _cartridge_angle_deg


func latch_open(index: int) -> bool:
	return _latch_open.get(index, false)


func _current_difficulty() -> int:
	return _active_difficulty if _active_difficulty != -1 else GameSettings.get_difficulty()


## STAGE 1: isolate airflow (the valve lever click) -- must happen
## before the latches can be touched, matching the documented
## "isolate airflow -> close valves" ordering.
func toggle_isolate() -> Dictionary:
	if _stage == Stage.ISOLATE:
		_stage = Stage.OPEN_LATCHES
		_sync_world_diorama()
		return {"ok": true, "stage": _stage}
	if _stage == Stage.RESTORE:
		_stage = Stage.COMPLETE
		mark_complete()
		_sync_world_diorama()
		return {"ok": true, "stage": _stage, "complete": true}
	return {"ok": false}


## STAGES 2/5: the two latches, reused for both opening (before
## removal) and closing (after the new cartridge seats) -- "restore
## valves in correct order" is satisfied by the fixed stage gating
## itself (latches only do something during OPEN_LATCHES/CLOSE_LATCHES).
func toggle_latch(index: int) -> Dictionary:
	if _stage != Stage.OPEN_LATCHES and _stage != Stage.CLOSE_LATCHES:
		return {"ok": false}
	_latch_open[index] = not _latch_open[index]
	var both_open: bool = _latch_open[1] and _latch_open[2]
	var both_closed: bool = not _latch_open[1] and not _latch_open[2]
	if _stage == Stage.OPEN_LATCHES and both_open:
		_stage = Stage.REMOVE_OLD
	elif _stage == Stage.CLOSE_LATCHES and both_closed:
		_stage = Stage.RESTORE
	_sync_world_diorama()
	return {"ok": true, "stage": _stage, "latch_open": _latch_open.duplicate()}


## STAGE 3: pull the old (contaminated) cartridge.
func remove_old_cartridge() -> Dictionary:
	if _stage != Stage.REMOVE_OLD:
		return {"ok": false}
	_stage = Stage.ALIGN_INSERT
	_cartridge_angle_deg = _START_ANGLE_DEG
	_sync_world_diorama()
	return {"ok": true, "stage": _stage}


## STAGE 4a: rotates the new cartridge by one fixed step -- the actual
## "alignment" half of the mechanic.
func rotate_cartridge(direction: int) -> Dictionary:
	if _stage != Stage.ALIGN_INSERT:
		return {"ok": false}
	_cartridge_angle_deg = fmod(_cartridge_angle_deg + direction * _ROTATE_STEP_DEG + 360.0, 360.0)
	_sync_world_diorama()
	return {"ok": true, "angle": _cartridge_angle_deg}


## STAGE 4b: attempts to seat the cartridge at its CURRENT rotation.
## Succeeds only within this difficulty's tolerance of the fixed target
## angle -- an incorrect attempt is harmless and recoverable (per the
## brief's own "incorrect orientation should physically fail to seat,
## with recoverable feedback... do not silently accept"), not a
## progress-losing failure.
func attempt_insert() -> Dictionary:
	if _stage != Stage.ALIGN_INSERT:
		return {"ok": false}
	var diff: float = abs(wrapf(_cartridge_angle_deg - _TARGET_ANGLE_DEG, -180.0, 180.0))
	if diff <= tolerance_deg():
		_stage = Stage.CLOSE_LATCHES
		_sync_world_diorama()
		return {"ok": true, "seated": true, "stage": _stage}
	_failed_insert_flash = true
	return {"ok": true, "seated": false, "angle_off_deg": diff}


func consume_failed_insert_flash() -> bool:
	var v: bool = _failed_insert_flash
	_failed_insert_flash = false
	return v


func mark_complete() -> void:
	_day_plan.mark_done(&"l02")


func _sync_world_diorama() -> void:
	if _world_diorama == null:
		return
	_world_diorama.sync_full_state(_stage, _latch_open, _cartridge_angle_deg)
