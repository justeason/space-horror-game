extends StaticBody3D
## Communications' signal tuning console -- implements M02 Signal
## Calibration (GAME_DESIGN.md Section 30: "Tune signal using a
## physical dial/control and observe the result"). Round 16 Priority 7's
## "one meaningful new gameplay feature": continuous TWO-PARAMETER
## tuning (frequency + gain) toward a fixed, hidden target, with
## completion requiring signal quality to stay above threshold for a
## SUSTAINED period, not just an instant -- genuinely different in kind
## from every other maintenance mechanic in this project (not a
## discrete sequence, not a single toggle, not alignment/insertion, not
## evidence-based point-and-diagnose).
##
## Round 17 Priority 3 (supersedes the "fixed puzzle instance" note this
## comment used to make): which of a few authored _PROFILES is live --
## target frequency/gain, how forgiving each dimension is, the starting
## dial positions, how much static the receiver shows, and how long a
## good tune must hold -- varies per attempt, picked once (locked the
## first time anything reads profile-dependent state, via
## _ensure_profile()) and held fixed for the rest of that attempt, same
## "locked once, survives reentry" contract as electrical_panel.gd's
## _REPAIR_CONFIGS. Every profile is still a fair, equally-solvable
## receiver tuning problem -- what varies is WHERE on the dial the
## answer sits, never the rules of the puzzle.

const GameSettings = preload("res://scripts/station/game_settings.gd")

@export var day_plan_path: NodePath
@export var signal_view_path: NodePath

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _signal_view: Node = get_node_or_null(signal_view_path)
@onready var _world_diorama: Node = get_node_or_null("WorldDiorama")

const _FREQ_MIN: float = 0.0
const _FREQ_MAX: float = 100.0
const _FREQ_STEP: float = 2.0
const _GAIN_MIN: float = 0.0
const _GAIN_MAX: float = 1.0
const _GAIN_STEP: float = 0.05

## Round 17 Priority 3: a small set of fair, equally-solvable receiver
## profiles. "default" is byte-for-byte the Round 16 fixed instance
## (same target/falloff/start values), kept first and selectable by
## label so every pre-Round-17 test stays deterministic via
## debug_force_profile(&"default") -- the same "config 0 preserves the
## old behavior exactly" contract electrical_panel.gd's _REPAIR_CONFIGS
## already established. The other two profiles move the target to a
## different, still fairly-reachable part of the dial range, start from
## a correspondingly different (never already-close) position, and
## mildly vary noise_scale/sustain duration -- "drift pattern"/"noise
## behavior"/"stability condition" varying per attempt without ever
## making the puzzle actually harder to reason about.
const _PROFILES: Array[Dictionary] = [
	{"label": "default", "target_freq": 63.0, "target_gain": 0.7, "freq_falloff": 15.0, "gain_falloff": 0.4, "start_freq": 12.0, "start_gain": 0.2, "sustain_seconds": 2.0, "noise_scale": 1.0},
	{"label": "low_band", "target_freq": 28.0, "target_gain": 0.45, "freq_falloff": 14.0, "gain_falloff": 0.35, "start_freq": 82.0, "start_gain": 0.85, "sustain_seconds": 2.2, "noise_scale": 1.15},
	{"label": "high_band", "target_freq": 86.0, "target_gain": 0.58, "freq_falloff": 16.0, "gain_falloff": 0.42, "start_freq": 20.0, "start_gain": 0.1, "sustain_seconds": 1.8, "noise_scale": 0.9},
]

const _QUALITY_THRESHOLD_BY_DIFFICULTY := {
	GameSettings.Difficulty.EASY: 0.6,
	GameSettings.Difficulty.NORMAL: 0.72,
	GameSettings.Difficulty.HARD: 0.82,
}

## Starting position deliberately far from the solution in both
## dimensions -- same "real work required" policy as every other
## minigame's fixed starting state. Matches _PROFILES[0] ("default") so
## the world diorama's very first _ready()-time sync (before any
## profile is actually selected -- see _ensure_profile()) looks
## identical no matter which profile this attempt eventually locks to.
const _START_FREQ: float = 12.0
const _START_GAIN: float = 0.2

var _frequency: float = _START_FREQ
var _gain: float = _START_GAIN
var _sustained_time: float = 0.0
var _active_difficulty: int = -1

## -1 = not yet chosen. See _ensure_profile().
var _profile_index: int = -1
var _target_freq: float = 63.0
var _target_gain: float = 0.7
var _freq_falloff: float = 15.0
var _gain_falloff: float = 0.4
var _sustain_seconds_value: float = 2.0
var _noise_scale: float = 1.0


## Deliberately does NOT call _sync_world_diorama() here: that reads
## signal_quality()/noise_level(), both of which call _ensure_profile()
## -- doing that from _ready() (which fires the instant the scene
## loads) would lock a random profile before debug_force_profile() ever
## gets a chance to run. The world twin instead starts at its own
## authored rest pose/_frequency/_gain var defaults (which already
## match _PROFILES[0]) and gets a real sync on first interact()/nudge.
func _ready() -> void:
	if _world_diorama != null:
		_world_diorama.sync_full_state(_frequency, _gain, 0.0, 0.0, false)


## Locks in a random profile the first time anything actually needs
## one -- deliberately NOT in _ready() itself: _ready() fires the
## instant the scene loads, before a test (or any other code) gets a
## chance to call debug_force_profile() first, which would make that
## hook permanently useless. Every real entry point below (interact(),
## the frequency/gain/target readouts, nudging, sustain) calls this
## first, so no matter which one happens first in practice, the choice
## is made exactly once and never revisited.
func _ensure_profile() -> void:
	if _profile_index != -1:
		return
	_apply_profile(randi() % _PROFILES.size())


func _apply_profile(index: int) -> void:
	_profile_index = index
	var p: Dictionary = _PROFILES[index]
	_target_freq = p["target_freq"]
	_target_gain = p["target_gain"]
	_freq_falloff = p["freq_falloff"]
	_gain_falloff = p["gain_falloff"]
	_sustain_seconds_value = p["sustain_seconds"]
	_noise_scale = p["noise_scale"]
	_frequency = p["start_freq"]
	_gain = p["start_gain"]
	_sync_world_diorama()


## Test-only: forces a specific profile instead of a random pick, for
## deterministic regression coverage -- must be called before anything
## else touches profile-dependent state (see _ensure_profile()'s own
## comment). Mirrors electrical_panel.gd's debug_force_fault_role()/
## debug_force_config_label() contract exactly.
func debug_force_profile(label: String) -> void:
	if _profile_index != -1:
		return
	for i in _PROFILES.size():
		if _PROFILES[i].get("label", "") == label:
			_apply_profile(i)
			return


func active_profile_label() -> String:
	_ensure_profile()
	return _PROFILES[_profile_index].get("label", "")


func _current_difficulty() -> int:
	if _active_difficulty == -1:
		return GameSettings.get_difficulty()
	return _active_difficulty


func interact() -> void:
	_ensure_profile()
	if _signal_view == null:
		return
	if _active_difficulty == -1:
		_active_difficulty = GameSettings.get_difficulty()
	_signal_view.open_station(self)


func get_interact_prompt() -> String:
	if is_complete():
		return "Click: Check Signal Console (Nominal)"
	return "Click: Calibrate Signal"


func is_complete() -> bool:
	return _day_plan.is_task_done(&"m02")


func frequency() -> float:
	_ensure_profile()
	return _frequency


func gain() -> float:
	_ensure_profile()
	return _gain


func show_numeric_readout() -> bool:
	return _current_difficulty() != GameSettings.Difficulty.HARD


func show_target_marker() -> bool:
	return _current_difficulty() == GameSettings.Difficulty.EASY


func target_frequency() -> float:
	_ensure_profile()
	return _target_freq


func quality_threshold() -> float:
	return _QUALITY_THRESHOLD_BY_DIFFICULTY.get(_current_difficulty(), 0.72)


func sustain_seconds() -> float:
	_ensure_profile()
	return _sustain_seconds_value


## Progress toward completion, 0..1, once quality is already above
## threshold -- read by the view for a small "holding..." progress cue.
func sustain_progress() -> float:
	return clampf(_sustained_time / sustain_seconds(), 0.0, 1.0)


## Round 18 Priority 4: PUBLIC (was _base_signal()) so the view can show
## frequency accuracy and gain/strength accuracy as two genuinely
## distinct readouts instead of only the combined signal_quality() --
## the brief's own explicit "clearly distinguish frequency accuracy from
## gain/strength" requirement.
func frequency_accuracy() -> float:
	_ensure_profile()
	var distance: float = absf(_frequency - _target_freq)
	return clampf(1.0 - distance / _freq_falloff, 0.0, 1.0)


func gain_accuracy() -> float:
	_ensure_profile()
	var distance: float = absf(_gain - _target_gain)
	return clampf(1.0 - distance / _gain_falloff, 0.0, 1.0)


## 0..1 -- how clean the received signal reads right now. Requires BOTH
## the frequency AND the gain to be near their respective targets
## (a genuine two-parameter tuning problem, not "turn one knob until a
## number reaches a target").
func signal_quality() -> float:
	return frequency_accuracy() * gain_accuracy()


## 0..1 -- how much visible static/noise the waveform should show.
## Noise is worst when gain is high but frequency is off-target (a
## loud, badly-tuned receiver), and quiet either when gain is low or
## frequency is well-tuned.
func noise_level() -> float:
	_ensure_profile()
	return clampf(_gain * (1.0 - frequency_accuracy()) * _noise_scale, 0.0, 1.0)


func nudge_frequency(direction: int) -> Dictionary:
	_ensure_profile()
	if is_complete():
		return {"ok": false}
	_frequency = clampf(_frequency + direction * _FREQ_STEP, _FREQ_MIN, _FREQ_MAX)
	_sync_world_diorama()
	return {"ok": true, "frequency": _frequency}


func nudge_gain(direction: int) -> Dictionary:
	_ensure_profile()
	if is_complete():
		return {"ok": false}
	_gain = clampf(_gain + direction * _GAIN_STEP, _GAIN_MIN, _GAIN_MAX)
	_sync_world_diorama()
	return {"ok": true, "gain": _gain}


## Advances the sustained-quality timer by `delta` -- called every
## frame the focused view is open, mirroring this task's real-world
## requirement ("establish adequate signal quality for a SUSTAINED
## verification period," not an instant threshold crossing). Dropping
## below threshold resets progress (recoverable, not punitive: the
## player simply re-tunes and holds again), never fails the attempt.
func advance_sustain(delta: float) -> Dictionary:
	if is_complete():
		return {"complete": false}
	if signal_quality() >= quality_threshold():
		_sustained_time += delta
	else:
		_sustained_time = 0.0
	if _sustained_time >= sustain_seconds():
		mark_complete()
		return {"complete": true}
	return {"complete": false}


func mark_complete() -> void:
	_day_plan.mark_done(&"m02")


func _sync_world_diorama() -> void:
	if _world_diorama == null:
		return
	_world_diorama.sync_full_state(_frequency, _gain, signal_quality(), noise_level(), is_complete())
