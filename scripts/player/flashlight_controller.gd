extends Node3D
## Flashlight (Round 14 Priority 4 first pass; Round 15 Priority 3 adds
## HARD's hand-powered generator mechanic). A SpotLight3D fixed to the
## player's own camera, so it always points exactly where the player
## looks -- toggled/pumped with a plain keypress, this project has no
## InputMap actions anywhere (see project.godot; every other control,
## e.g. sensor_calibration_view.gd's KEY_1..6, polls raw keycodes the
## same way), so KEY_L follows that same established convention rather
## than introducing a new input system.
##
## SCOPE: a believable, fairly narrow "technician's worklight" beam --
## meant to help read dim equipment and dark corners, not wash out a
## whole room like a generic horror-shooter flashlight.
##
## EASY/NORMAL: a plain toggle, exactly Round 14's original behavior --
## one L press turns it on, stays on until toggled off or temporarily
## hidden by a focused session.
##
## HARD: a hand-powered squeeze generator instead of a battery. There is
## no on/off switch -- each fresh L KEY-DOWN (not an OS auto-repeat
## event; InputEventKey.echo is exactly Godot's own "this is a repeat,
## not a new press" flag, so filtering it out is what keeps one held key
## from generating unlimited energy, satisfying "use actual key-down
## transitions, not uncontrolled key-repeat") adds a bounded amount of
## stored energy; holding L also trickle-charges, but at a much slower
## rate, so a player who cannot tap rapidly still has a working (if less
## efficient) alternative without making HARD mechanically identical to
## just holding a button. Energy decays steadily; brightness is a smooth
## function of stored energy (never a binary flicker), so the beam fades
## rather than snapping off.
##
## FOCUSED MINIGAME STATES: the beam is hidden while a focused session
## (electrical repair, calibration, screws, ...) is active, since the
## player's attention and hands are occupied with that close-up task,
## exactly mirroring FocusedInteractionState's own "exclusive control"
## contract. Both the EASY/NORMAL on/off flag and HARD's stored energy
## are PRESERVED (not reset) across a focused session and keep decaying
## in HARD's case -- see _process()'s own handling.

const GameSettings = preload("res://scripts/station/game_settings.gd")

@export var focused_state_path: NodePath
@export var sfx_path: NodePath

@onready var _focused_state: Node = get_node_or_null(focused_state_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)
@onready var _light: SpotLight3D = $SpotLight3D

const BASE_LIGHT_ENERGY: float = 3.5
const MAX_CHARGE: float = 1.0
const PUMP_GAIN: float = 0.22 # per genuine key-down tap
const HOLD_GAIN_PER_SEC: float = 0.09 # accessible alternative: just hold L
const DECAY_PER_SEC: float = 0.045
const MIN_VISIBLE_CHARGE: float = 0.02
const PUMP_SOUND_COOLDOWN: float = 0.08 # rate-limits the click SFX, not the charge itself

var _on: bool = false # EASY/NORMAL's plain toggle state
var _charge: float = 0.0 # HARD's stored generator energy, 0..MAX_CHARGE
var _held: bool = false
var _last_pump_sound_time: float = -1.0
var _elapsed: float = 0.0
var _last_difficulty: int = -1


func _ready() -> void:
	_light.visible = false
	_last_difficulty = GameSettings.get_difficulty()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_L:
		if _is_focused():
			return
		if event.echo:
			return # OS auto-repeat carries no new information here --
			# _held was already set true by the real press that started
			# the repeat, and ignoring echoes entirely (rather than
			# merely skipping the pump) keeps this immune to any event
			# sequence, not just genuine OS-generated ones.
		if event.pressed:
			if _current_difficulty() == GameSettings.Difficulty.HARD:
				_pump()
			else:
				_on = not _on
		if _current_difficulty() == GameSettings.Difficulty.HARD:
			_held = event.pressed
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_elapsed += delta
	_handle_difficulty_transition()

	if _current_difficulty() == GameSettings.Difficulty.HARD:
		if _held and not _is_focused():
			_charge = minf(_charge + HOLD_GAIN_PER_SEC * delta, MAX_CHARGE)
		_charge = maxf(_charge - DECAY_PER_SEC * delta, 0.0)
		var visible_now: bool = _charge > MIN_VISIBLE_CHARGE and not _is_focused()
		_light.visible = visible_now
		if visible_now:
			_light.light_energy = BASE_LIGHT_ENERGY * clampf(_charge, 0.0, 1.0)
	else:
		_light.visible = _on and not _is_focused()
		_light.light_energy = BASE_LIGHT_ENERGY


func _pump() -> void:
	_charge = minf(_charge + PUMP_GAIN, MAX_CHARGE)
	if _sfx != null and _elapsed - _last_pump_sound_time >= PUMP_SOUND_COOLDOWN:
		_sfx.play_kind(&"click")
		_last_pump_sound_time = _elapsed


## Keeps state coherent across a live difficulty change (the player can
## cycle Game Difficulty at any time, not just between sessions) without
## losing input, sticking the light on, granting infinite charge, or
## producing an unexpected dark screen -- converts between the two
## state representations in BOTH directions so the beam's apparent
## brightness never jumps discontinuously at the switch itself.
func _handle_difficulty_transition() -> void:
	var current: int = _current_difficulty()
	if current == _last_difficulty:
		return
	var was_hard: bool = _last_difficulty == GameSettings.Difficulty.HARD
	var now_hard: bool = current == GameSettings.Difficulty.HARD
	if now_hard and not was_hard:
		# Entering HARD: a flashlight that was ON starts at a comfortable
		# mid charge (continues lit, then decays normally) rather than
		# snapping to full (free energy) or zero (instant darkness).
		_charge = 0.6 if _on else 0.0
		_held = false
	elif was_hard and not now_hard:
		# Leaving HARD: whatever charge remains becomes a plain on/off --
		# any real remaining charge counts as "on" so the player doesn't
		# lose their light mid-corridor just from a difficulty change.
		_on = _charge > MIN_VISIBLE_CHARGE
		_held = false
	_last_difficulty = current


func is_on() -> bool:
	if _current_difficulty() == GameSettings.Difficulty.HARD:
		return _charge > MIN_VISIBLE_CHARGE
	return _on


func charge() -> float:
	return _charge


func _current_difficulty() -> int:
	return GameSettings.get_difficulty()


func _is_focused() -> bool:
	return _focused_state != null and _focused_state.is_active()
