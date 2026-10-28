extends StaticBody3D
## Engineering's spare diagnostic bench -- implements E09 Diagnose
## Intermittent Electrical Fault (GAME_DESIGN.md Section 28). Round 15
## Priority 5: evidence-based diagnosis via a probe and test points,
## distinct from every other maintenance mechanic in this project --
## not a click-sequence (electrical repair), a discrete toggle (coolant
## loop), or alignment/insertion (filter housing).
##
## FIXED CIRCUIT (same "one authored, non-randomized puzzle instance"
## policy as every other minigame here): POWER -> TP1 -> TP2 -> TP3 ->
## TP4, a dead power rail, with the ONE break always between TP2 and
## TP3. Readings are internally consistent with that topology (TP1/TP2
## read normal, TP3/TP4 read dead) and never change mid-attempt.

enum Reading { NORMAL, DEAD }

const GameSettings = preload("res://scripts/station/game_settings.gd")

## The one fixed fault location, as the segment id between its two
## endpoints -- segments are named "<a>_<b>" for adjacent test points
## (or "power_tp1" for the first one).
const _FAULT_SEGMENT: StringName = &"tp2_tp3"
const _SEGMENTS: Array[StringName] = [&"power_tp1", &"tp1_tp2", &"tp2_tp3", &"tp3_tp4"]
const _TEST_POINTS: Array[StringName] = [&"tp1", &"tp2", &"tp3", &"tp4"]
## Which test points read NORMAL vs DEAD -- fully determined by the one
## fixed fault segment above (every point upstream of the break is
## normal; every point at or downstream of it reads dead).
const _DEAD_FROM_INDEX: int = 2 # tp3 (index 2 in _TEST_POINTS) is the first dead reading

@export var day_plan_path: NodePath
@export var tracer_view_path: NodePath

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _tracer_view: Node = get_node_or_null(tracer_view_path)
@onready var _world_diorama: Node = get_node_or_null("WorldDiorama")

var _probe_at: StringName = &""
var _tested: Dictionary = {} # StringName -> bool, which test points have been probed at least once
var _last_wrong_guess: StringName = &""


func _ready() -> void:
	_sync_world_diorama()


func interact() -> void:
	if _tracer_view == null:
		return
	_tracer_view.open_station(self)


func get_interact_prompt() -> String:
	if is_complete():
		return "Click: Check Diagnostic Bench (Nominal)"
	return "Click: Diagnose Intermittent Fault"


func is_complete() -> bool:
	return _day_plan.is_task_done(&"e09")


func probe_at() -> StringName:
	return _probe_at


func reading_for(tp: StringName) -> int:
	var idx: int = _TEST_POINTS.find(tp)
	if idx == -1:
		return Reading.DEAD
	return Reading.DEAD if idx >= _DEAD_FROM_INDEX else Reading.NORMAL


## Shows a numeric voltage reading on EASY/NORMAL; HARD only shows a
## qualitative continuity state -- per the brief's own difficulty
## guidance for this task ("the player should infer the faulty segment
## from evidence"), HARD asks for a little more inference from less
## precise evidence, not a different circuit or a stricter tolerance.
func reading_text_for(tp: StringName) -> String:
	var dead: bool = reading_for(tp) == Reading.DEAD
	if GameSettings.get_difficulty() == GameSettings.Difficulty.HARD:
		return "NO SIGNAL" if dead else "CONTINUITY OK"
	return "0.0 V — NO SIGNAL" if dead else "12.0 V — NOMINAL"


## EASY keeps a running log of every point tested so far on screen;
## NORMAL/HARD require the player to remember earlier readings
## themselves.
func log_shown() -> bool:
	return GameSettings.get_difficulty() == GameSettings.Difficulty.EASY


func tested_points() -> Array:
	return _tested.keys()


func move_probe(tp: StringName) -> Dictionary:
	if is_complete() or not (tp in _TEST_POINTS):
		return {"ok": false}
	_probe_at = tp
	_tested[tp] = true
	_sync_world_diorama()
	return {"ok": true, "reading": reading_text_for(tp)}


## Submits a diagnosis guess -- a specific SEGMENT, not a numbered
## answer. Wrong guesses are harmless and informative (never reset
## progress), matching "Incorrect probes are harmless and informative"
## /"do not randomly move the fault during one attempt."
func submit_diagnosis(segment: StringName) -> Dictionary:
	if is_complete() or not (segment in _SEGMENTS):
		return {"ok": false}
	if segment == _FAULT_SEGMENT:
		mark_complete()
		return {"ok": true, "correct": true}
	_last_wrong_guess = segment
	return {"ok": true, "correct": false}


func consume_last_wrong_guess() -> StringName:
	var v: StringName = _last_wrong_guess
	_last_wrong_guess = &""
	return v


func mark_complete() -> void:
	_day_plan.mark_done(&"e09")


func _sync_world_diorama() -> void:
	if _world_diorama == null:
		return
	_world_diorama.sync_full_state(_probe_at, tested_points(), is_complete())
