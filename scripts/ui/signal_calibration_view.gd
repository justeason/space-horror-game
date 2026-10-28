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


func _refresh() -> void:
	if _done:
		_status_label.text = "SIGNAL LOCKED"
		_controls_label.text = "[Enter] Close"
		return

	_status_label.text = "Tune the signal clean, then hold it steady."
	_controls_label.text = "[←/→] Frequency   [↑/↓] Gain   (or click a dial's left/right half)"
	var quality: float = _station.signal_quality()
	var threshold: float = _station.quality_threshold()
	if quality >= threshold:
		var progress: float = _station.sustain_progress()
		_status_label.text = "SIGNAL ACQUIRED — holding %d%%" % int(progress * 100.0)
	elif _station.noise_level() > 0.5:
		_status_label.text = "Strong static — lower GAIN or re-tune FREQUENCY."
