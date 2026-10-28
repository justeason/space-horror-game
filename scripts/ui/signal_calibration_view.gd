extends Control
## Round 16 Priority 7: focused view for M02 Signal Calibration. Same
## "view owns only display + input routing, the physical object owns
## all real state" split as every other focused view in this project --
## every diorama signal is translated into exactly one call to
## signal_calibration_station.gd's existing methods. The one thing this
## view does that most others don't: it advances the station's
## sustained-quality timer every frame while open (advance_sustain()),
## since this task's whole point is "hold a good tune for a few
## seconds," not a single committed action.

@export var focused_state_path: NodePath
@export var sfx_path: NodePath

@onready var _focused_state: Node = get_node(focused_state_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)

@onready var _status_label: Label = $Panel/VBox/StatusLabel
@onready var _controls_label: Label = $Panel/VBox/ControlsLabel
@onready var _diorama: Node3D = $Panel/VBox/DioramaContainer/DioramaViewport/SignalCalibrationDiorama

var _station: Node = null
var _done: bool = false
var _last_sync_quality: float = -1.0


func _ready() -> void:
	visible = false
	_diorama.freq_nudge.connect(_on_freq_nudge)
	_diorama.gain_nudge.connect(_on_gain_nudge)


func open_station(station: Node) -> void:
	_station = station
	if not _focused_state.begin(self):
		return
	visible = true
	_diorama.set_active(true)
	_done = station.is_complete()
	_sync_diorama()
	_refresh()


func on_focus_exit() -> void:
	visible = false
	_diorama.set_active(false)
	_station = null


func cancel_requested() -> void:
	pass # Nothing to roll back -- every dial nudge is itself trivially
	# reversible (nudge the other way), and the sustain timer simply
	# resets if quality drops; reentering resumes from the saved
	# frequency/gain, same contract as every other focused view here.


func _process(delta: float) -> void:
	if _station == null or _done:
		return
	var result: Dictionary = _station.advance_sustain(delta)
	_sync_diorama()
	if result.get("complete", false):
		_done = true
		if _sfx != null:
			_sfx.play_kind(&"success")
	_refresh()


func _on_freq_nudge(direction: int) -> void:
	if _station == null or _done:
		return
	var result: Dictionary = _station.nudge_frequency(direction)
	if not result.get("ok", false):
		return
	if _sfx != null:
		_sfx.play_kind(&"click")
	_sync_diorama()
	_refresh()


func _on_gain_nudge(direction: int) -> void:
	if _station == null or _done:
		return
	var result: Dictionary = _station.nudge_gain(direction)
	if not result.get("ok", false):
		return
	if _sfx != null:
		_sfx.play_kind(&"click")
	_sync_diorama()
	_refresh()


## Round 17 Priority 3: keyboard is the PRIMARY control scheme for both
## dials (the player's own explicit "prefer keys instead of clicking"
## request) -- Left/Right tune frequency, Up/Down tune gain, mirroring
## the real dial-half convention 1:1 (left = down, right = up) so the
## two input methods never disagree about which direction is which.
## Mouse-click on the diorama's dial halves (signal_calibration_diorama.gd's
## own _unhandled_input()) still works unchanged as a secondary method --
## both funnel into the exact same _on_freq_nudge()/_on_gain_nudge()
## handlers below, so there is only ever one code path per dial no
## matter which input drove it.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or _station == null:
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	if _done:
		if event.keycode == KEY_ENTER:
			_focused_state.end()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_LEFT, KEY_A:
			_on_freq_nudge(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_D:
			_on_freq_nudge(1)
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_S:
			_on_gain_nudge(-1)
			get_viewport().set_input_as_handled()
		KEY_UP, KEY_W:
			_on_gain_nudge(1)
			get_viewport().set_input_as_handled()


func _sync_diorama() -> void:
	_diorama.sync_full_state(_station.frequency(), _station.gain(), _station.signal_quality(), _station.noise_level(), _done)
	if _station.show_numeric_readout():
		_diorama.set_readout_text("F:%.0f  G:%.2f  Q:%.0f%%" % [_station.frequency(), _station.gain(), _station.signal_quality() * 100.0])
	else:
		_diorama.set_readout_text("")


## Round 18 Priority 4: an understandable named progression instead of
## a single "SIGNAL ACQUIRED" label covering everything from "just
## started" to "about to lock" -- the brief's own explicit SEARCHING ->
## SIGNAL ACQUIRED -> FINE TUNING -> STABILIZING -> SIGNAL LOCKED
## stages. Each threshold is phrased in terms of frequency_accuracy()/
## gain_accuracy() specifically (not just the combined signal_quality())
## so the distinction the brief also asks for -- "frequency accuracy
## vs. gain/strength" -- is what actually DRIVES which state shows, not
## merely two numbers printed side by side.
enum _TuneState { SEARCHING, ACQUIRED, FINE_TUNING, STABILIZING, LOCKED }
const _AXIS_OK_THRESHOLD: float = 0.5

const _STATE_COLOR := {
	_TuneState.SEARCHING: Color(0.85, 0.55, 0.3, 1),
	_TuneState.ACQUIRED: Color(0.85, 0.78, 0.35, 1),
	_TuneState.FINE_TUNING: Color(0.7, 0.85, 0.4, 1),
	_TuneState.STABILIZING: Color(0.45, 0.85, 0.95, 1),
	_TuneState.LOCKED: Color(0.4, 0.95, 0.55, 1),
}


func _current_state() -> _TuneState:
	if _done:
		return _TuneState.LOCKED
	var quality: float = _station.signal_quality()
	if quality >= _station.quality_threshold():
		return _TuneState.STABILIZING
	var freq_ok: bool = _station.frequency_accuracy() >= _AXIS_OK_THRESHOLD
	var gain_ok: bool = _station.gain_accuracy() >= _AXIS_OK_THRESHOLD
	if freq_ok and gain_ok:
		return _TuneState.FINE_TUNING
	if freq_ok or gain_ok:
		return _TuneState.ACQUIRED
	return _TuneState.SEARCHING


func _refresh() -> void:
	var state: _TuneState = _current_state()
	_status_label.modulate = _STATE_COLOR[state]

	if state == _TuneState.LOCKED:
		_status_label.text = "SIGNAL LOCKED"
		_controls_label.text = "[Enter] Close"
		return

	_controls_label.text = "[←/→] Frequency   [↑/↓] Gain   (or click a dial's left/right half)"
	var freq_ok: bool = _station.frequency_accuracy() >= _AXIS_OK_THRESHOLD
	var gain_ok: bool = _station.gain_accuracy() >= _AXIS_OK_THRESHOLD
	match state:
		_TuneState.SEARCHING:
			_status_label.text = "SEARCHING — sweep FREQUENCY and GAIN to find the carrier."
		_TuneState.ACQUIRED:
			_status_label.text = (
				"SIGNAL ACQUIRED — frequency is close, now bring GAIN into range."
				if freq_ok else
				"SIGNAL ACQUIRED — gain is close, now sweep FREQUENCY to find the carrier."
			)
		_TuneState.FINE_TUNING:
			_status_label.text = "FINE TUNING — both dials are close. Narrow in until the signal reads clean."
		_TuneState.STABILIZING:
			var progress: float = _station.sustain_progress()
			_status_label.text = "STABILIZING — hold steady… %d%%" % int(progress * 100.0)

	if state != _TuneState.STABILIZING and _station.noise_level() > 0.5:
		_status_label.text += "  (strong static — lower GAIN or re-tune FREQUENCY)"
