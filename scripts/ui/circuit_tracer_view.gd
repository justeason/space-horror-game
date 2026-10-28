extends Control
## Round 15 Priority 5: focused view for E09 Diagnose Intermittent
## Electrical Fault. Same "view owns only display + input routing, the
## physical object owns all real state" split as every other focused
## view in this project -- every diorama signal is translated into
## exactly one call to circuit_tracer_station.gd's existing methods.
##
## Interaction model: clicking a TEST POINT moves the probe there and
## reads it (gathering evidence); clicking a WIRE SEGMENT submits it as
## a diagnosis guess for where the fault lies (acting on that
## evidence). Two distinct physical click targets for two distinct
## actions, rather than a menu of segment names to pick from.

const CircuitTracerStation = preload("res://scripts/interactables/circuit_tracer_station.gd")

@export var focused_state_path: NodePath
@export var sfx_path: NodePath

@onready var _focused_state: Node = get_node(focused_state_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)

@onready var _status_label: Label = $Panel/VBox/StatusLabel
@onready var _controls_label: Label = $Panel/VBox/ControlsLabel
@onready var _log_label: Label = $Panel/VBox/LogLabel
@onready var _diorama: Node3D = $Panel/VBox/DioramaContainer/DioramaViewport/CircuitTracerDiorama

const _SEGMENT_LABELS := {
	&"power_tp1": "POWER—TP1",
	&"tp1_tp2": "TP1—TP2",
	&"tp2_tp3": "TP2—TP3",
	&"tp3_tp4": "TP3—TP4",
}

var _station: Node = null


func _ready() -> void:
	visible = false
	_diorama.test_point_clicked.connect(_on_test_point_clicked)
	_diorama.segment_clicked.connect(_on_segment_clicked)


func open_station(station: Node) -> void:
	_station = station
	if not _focused_state.begin(self):
		return
	visible = true
	_diorama.set_active(true)
	_diorama.sync_full_state(_station.probe_at(), _station.tested_points(), _station.is_complete())
	_refresh()


func on_focus_exit() -> void:
	visible = false
	_diorama.set_active(false)
	_station = null


func cancel_requested() -> void:
	pass # Nothing to roll back -- probing and wrong guesses are both
	# harmless, recorded, non-destructive actions; reentering simply
	# resumes from the saved state, same contract as every other
	# focused view here.


func _on_test_point_clicked(tp: StringName) -> void:
	if _station == null or _station.is_complete():
		return
	var result: Dictionary = _station.move_probe(tp)
	if not result.get("ok", false):
		return
	_diorama.animate_probe_to(tp, result.get("reading", ""))
	if _sfx != null:
		_sfx.play_kind(&"click")
	_refresh()


func _on_segment_clicked(segment: StringName) -> void:
	if _station == null or _station.is_complete():
		return
	var result: Dictionary = _station.submit_diagnosis(segment)
	if not result.get("ok", false):
		return
	if result.get("correct", false):
		_diorama.show_fault_found(_SEGMENT_LABELS.get(segment, String(segment)))
		if _sfx != null:
			_sfx.play_kind(&"success")
	else:
		_diorama.flash_wrong_guess(_SEGMENT_LABELS.get(segment, String(segment)))
		if _sfx != null:
			_sfx.play_kind(&"fail")
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _station == null:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and _station.is_complete():
		_focused_state.end()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _station.is_complete():
		_status_label.text = "FAULT ISOLATED — BENCH NOMINAL"
		_controls_label.text = "[Enter] Close"
	else:
		_status_label.text = "Diagnose the intermittent fault."
		_controls_label.text = "Click a test point to probe it. Click the wire segment you believe is faulty to submit your diagnosis."

	var wrong: StringName = _station.consume_last_wrong_guess()
	if wrong != &"":
		_status_label.text = _SEGMENT_LABELS.get(wrong, String(wrong)) + " reads consistent — fault lies elsewhere."

	if _station.log_shown():
		var lines: Array[String] = []
		for tp in _station.tested_points():
			lines.append(String(tp).to_upper() + ": " + _station.reading_text_for(tp))
		_log_label.text = "\n".join(lines)
		_log_label.visible = not lines.is_empty()
	else:
		_log_label.visible = false
