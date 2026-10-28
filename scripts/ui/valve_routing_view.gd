extends Control
## Round 15 Priority 2 redesign: the coolant loop valve manifold is now
## a real 3D diorama (scenes/ui/valve_routing_diorama.tscn, rendered
## into a SubViewport exactly like electrical_repair_view.gd's own
## diorama) instead of 2D buttons on a flat schematic. Same "view owns
## only display + input routing, the physical object
## (valve_routing_station.gd) owns all real state" split used
## throughout this project -- every diorama click is translated into
## exactly one call to the station's toggle_valve().
##
## WHY THE PREVIOUS (Round 14) VERSION LOOKED LIKE A DEBUG DIAGRAM: see
## valve_routing_diorama.gd's own class doc comment for the full
## "almost-black box" diagnosis. The flat 2D schematic itself is kept,
## but demoted to optional supporting information (Tab to show/hide,
## same toggle convention sensor_calibration_view.gd already uses for
## its circular/cylindrical gauge switch) -- the manifold itself is now
## the primary interaction surface.

const GameSettings = preload("res://scripts/station/game_settings.gd")

@export var focused_state_path: NodePath

@onready var _focused_state: Node = get_node(focused_state_path)

@onready var _status_label: Label = $Panel/VBox/StatusLabel
@onready var _flow_label: Label = $Panel/VBox/FlowLabel
@onready var _controls_label: Label = $Panel/VBox/ControlsLabel
@onready var _diorama_viewport: SubViewport = $Panel/VBox/DioramaContainer/DioramaViewport
@onready var _diorama: Node3D = $Panel/VBox/DioramaContainer/DioramaViewport/ValveRoutingDiorama

@onready var _schematic: Control = $Schematic
@onready var _schematic_lines := {
	1: $Schematic/Lines/V1,
	2: $Schematic/Lines/V2,
	3: $Schematic/Lines/V3,
}
@onready var _schematic_flow: Label = $Schematic/Lines/Flow

var _station: Node = null
var _done: bool = false
var _showing_schematic: bool = false
var _sequence_warning_text: String = ""


func _ready() -> void:
	visible = false
	_schematic.visible = false
	_diorama.valve_clicked.connect(_on_valve_clicked)


func open_station(station: Node) -> void:
	_station = station
	if not _focused_state.begin(self):
		return
	visible = true
	_diorama.set_active(true)
	_done = station.is_complete()
	_diorama.sync_full_state(station.open_state(), station.branch3_is_leak())
	_diorama.set_drain_label_text(station.drain_label_text())
	_refresh()


func on_focus_exit() -> void:
	visible = false
	_diorama.set_active(false)
	_station = null


func cancel_requested() -> void:
	pass # Nothing to roll back -- identical policy to sensor_calibration_view.gd
	# and the Round 14 version of this file: only commits via the
	# station's own toggle_valve()/mark_complete(), so an abandoned
	# attempt loses no progress, and every valve toggle is itself
	# trivially reversible (click it again).


func _on_valve_clicked(id: int) -> void:
	if _station == null or _done:
		return
	var result: Dictionary = _station.toggle_valve(id)
	if not result.get("ok", false):
		return
	_diorama.animate_valve(id, result["open"])
	var flow: Dictionary = result["flow"]
	_diorama.set_flow_visual(flow["v1_live"], flow["outlet_live"], flow["drain_live"], _station.branch3_is_leak())
	_done = result.get("complete", false)
	if _station.consume_sequence_warning():
		_sequence_warning_text = "PRESSURE LOSS — open the primary outlet (V2) before the secondary (V3). Close V3 and retry in order."
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_1, KEY_2, KEY_3]:
		_on_valve_clicked(event.keycode - KEY_1 + 1)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_showing_schematic = not _showing_schematic
		_schematic.visible = _showing_schematic
		_refresh_schematic()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var dual: bool = _station.is_dual_outlet()
	var branch3_name: String = _station.drain_label_text()
	if _done:
		_status_label.text = ("COOLANT LOOP NOMINAL — flow routed to both outlets, correctly sequenced." if dual
			else "COOLANT LOOP NOMINAL — flow routed to outlet, drain sealed.")
		_controls_label.text = "[Enter] Close"
		_flow_label.text = ""
		_refresh_schematic()
		return

	if dual:
		_status_label.text = "Route coolant to BOTH outlets. Open the primary (V2) before the secondary (%s)." % branch3_name
	else:
		_status_label.text = "Route coolant from INLET to OUTLET. The DRAIN must stay sealed."
	_controls_label.text = "Click a valve handle to turn it (or [1] [2] [3]).   [Tab] Schematic   [Esc] Exit (no progress lost)"
	var flow: Dictionary = _station.flow_state()
	if dual:
		_flow_label.text = "OUTLET A: %s   %s: %s" % [
			"FLOWING" if flow["outlet_live"] else "none",
			branch3_name,
			"FLOWING" if flow["drain_live"] else "none",
		]
	else:
		_flow_label.text = "OUTLET FLOW: %s   DRAIN: %s" % [
			"FLOWING" if flow["outlet_live"] else "none",
			"LEAKING" if flow["drain_live"] else "sealed",
		]
	if _sequence_warning_text != "":
		_flow_label.text += "\n" + _sequence_warning_text
		_sequence_warning_text = ""
	_refresh_schematic()


## The demoted supporting-information schematic -- reads from the SAME
## station state the 3D manifold does, so the two can never disagree
## (see this file's class doc comment).
func _refresh_schematic() -> void:
	if not _showing_schematic or _station == null:
		return
	for id in _schematic_lines:
		var label: Label = _schematic_lines[id]
		label.text = "V%d: %s" % [id, "OPEN" if _station.is_valve_open(id) else "SHUT"]
	var flow: Dictionary = _station.flow_state()
	var branch3_name: String = _station.drain_label_text()
	var branch3_state: String = ("flowing" if flow["drain_live"] else "no flow") if _station.is_dual_outlet() else ("LEAKING" if flow["drain_live"] else "sealed")
	_schematic_flow.text = "INLET -> V1 -> JUNCTION -> V2 -> OUTLET (%s)\n                      \\-> V3 -> %s (%s)" % [
		"flowing" if flow["outlet_live"] else "no flow",
		branch3_name,
		branch3_state,
	]
