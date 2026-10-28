extends Control
## Round 15 Priority 4: focused view for L02 Filter Replacement. Same
## "view owns only display + input routing, the physical object owns
## all real state" split as every other focused view in this project --
## every diorama signal is translated into exactly one call to
## filter_housing_station.gd's existing methods.

const FilterHousingStation = preload("res://scripts/interactables/filter_housing_station.gd")

@export var focused_state_path: NodePath
@export var sfx_path: NodePath

@onready var _focused_state: Node = get_node(focused_state_path)
@onready var _sfx: Node = get_node_or_null(sfx_path)

@onready var _stage_label: Label = $Panel/VBox/StageLabel
@onready var _status_label: Label = $Panel/VBox/StatusLabel
@onready var _controls_label: Label = $Panel/VBox/ControlsLabel
@onready var _diorama: Node3D = $Panel/VBox/DioramaContainer/DioramaViewport/FilterHousingDiorama

var _station: Node = null
var _last_stage: int = -1


func _ready() -> void:
	visible = false
	_diorama.valve_clicked.connect(_on_valve_clicked)
	_diorama.latch_clicked.connect(_on_latch_clicked)
	_diorama.old_cartridge_clicked.connect(_on_old_cartridge_clicked)
	_diorama.new_cartridge_clicked.connect(_on_new_cartridge_clicked)


func open_station(station: Node) -> void:
	_station = station
	if not _focused_state.begin(self):
		return
	visible = true
	_diorama.set_active(true)
	_last_stage = -1
	_diorama.sync_full_state(_station.stage(), {1: _station.latch_open(1), 2: _station.latch_open(2)}, _station.cartridge_angle_deg())
	_refresh()


func on_focus_exit() -> void:
	visible = false
	_diorama.set_active(false)
	_station = null


func cancel_requested() -> void:
	pass # Nothing to roll back -- every commit is the station's own
	# explicit call; an abandoned attempt mid-procedure simply resumes
	# from wherever it was left (same "reentering renders the saved
	# state" contract as every other focused view here).


func _on_valve_clicked() -> void:
	if _station == null:
		return
	var result: Dictionary = _station.toggle_isolate()
	if not result.get("ok", false):
		return
	_diorama.animate_valve(not _station.is_isolated())
	if _sfx != null:
		_sfx.play_kind(&"clunk")
	_refresh()


func _on_latch_clicked(index: int) -> void:
	if _station == null:
		return
	var result: Dictionary = _station.toggle_latch(index)
	if not result.get("ok", false):
		return
	_diorama.animate_latch(index, _station.latch_open(index))
	if _sfx != null:
		_sfx.play_kind(&"click")
	_refresh()


func _on_old_cartridge_clicked() -> void:
	if _station == null:
		return
	var result: Dictionary = _station.remove_old_cartridge()
	if not result.get("ok", false):
		return
	_diorama.animate_remove_old_cartridge()
	_diorama.set_cartridge_angle(_station.cartridge_angle_deg())
	if _sfx != null:
		_sfx.play_kind(&"click")
	_refresh()


## The new cartridge itself is the ONE click target for both rotating
## and (once correctly aligned) attempting to seat it -- a second,
## distinct click on the housing's open rim would just be another
## button; the brief explicitly wants interaction to feel like
## manipulating the part itself. Rotating is the default action;
## holding is not required or read, matching this project's plain-
## keypress-equivalent click conventions elsewhere.
func _on_new_cartridge_clicked() -> void:
	if _station == null:
		return
	if _station.stage() != FilterHousingStation.Stage.ALIGN_INSERT:
		return
	_station.rotate_cartridge(1)
	_diorama.set_cartridge_angle(_station.cartridge_angle_deg())
	if _sfx != null:
		_sfx.play_kind(&"click")
	_refresh()


func _attempt_insert() -> void:
	if _station == null or _station.stage() != FilterHousingStation.Stage.ALIGN_INSERT:
		return
	var result: Dictionary = _station.attempt_insert()
	if result.get("seated", false):
		_diorama.animate_insert_success()
		if _sfx != null:
			_sfx.play_kind(&"success")
	else:
		_diorama.animate_insert_fail()
		if _sfx != null:
			_sfx.play_kind(&"fail")
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _station == null:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and _station.stage() == FilterHousingStation.Stage.ALIGN_INSERT:
			_attempt_insert()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER and _station.is_complete():
			_focused_state.end()
			get_viewport().set_input_as_handled()


func _refresh() -> void:
	var stage: int = _station.stage()
	if stage != _last_stage:
		_last_stage = stage
	var Stage = FilterHousingStation.Stage
	match stage:
		Stage.ISOLATE:
			_stage_label.text = "STAGE 1 / 6 — ISOLATE AIRFLOW"
			_controls_label.text = "Click the airflow valve to shut it off."
		Stage.OPEN_LATCHES:
			_stage_label.text = "STAGE 2 / 6 — RELEASE RETAINING LATCHES"
			_controls_label.text = "Click both latches to release the housing cover."
		Stage.REMOVE_OLD:
			_stage_label.text = "STAGE 3 / 6 — REMOVE OLD CARTRIDGE"
			_controls_label.text = "Click the old cartridge to pull it from the housing."
		Stage.ALIGN_INSERT:
			_stage_label.text = "STAGE 4 / 6 — ALIGN AND INSERT SPARE CARTRIDGE"
			var base_text: String = "Click the cartridge to rotate it. [Enter] to insert once its tab lines up with the housing's keyway mark."
			_controls_label.text = base_text + " (Target: the glowing amber mark on the housing rim, upper-right of the opening.)" if _station.guide_shown() else base_text
		Stage.CLOSE_LATCHES:
			_stage_label.text = "STAGE 5 / 6 — RE-ENGAGE LATCHES"
			_controls_label.text = "Click both latches to lock the new cartridge in place."
		Stage.RESTORE:
			_stage_label.text = "STAGE 6 / 6 — RESTORE AIRFLOW"
			_controls_label.text = "Click the airflow valve to restore flow and verify the seal."
		Stage.COMPLETE:
			_stage_label.text = "FILTER SERVICE COMPLETE"
			_controls_label.text = "[Enter] Close"

	if stage == Stage.COMPLETE:
		_status_label.text = "Seal nominal — airflow restored."
	elif _station.consume_failed_insert_flash():
		_status_label.text = "Keyway misaligned — rotate the cartridge to match the housing's mark, then try again."
	else:
		_status_label.text = ""
