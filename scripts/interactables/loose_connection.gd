extends StaticBody3D
## Slice A's one hands-on repair: E06 Tighten Loose Connection -- the
## simplest task in the whole database (GAME_DESIGN.md Section 28: "a
## good place for a simple repeated-click interaction"). No tool is
## required (Approved Decision A.8) -- this is deliberately the first,
## most approachable maintenance task.

@export var day_plan_path: NodePath
@export var message_label_path: NodePath
@export var clicks_required: int = 6
@export var message_duration: float = 1.2

@onready var _day_plan: Node = get_node(day_plan_path)
@onready var _message_label: Label = get_node_or_null(message_label_path)
@onready var _fitting: Node3D = $Fitting
@onready var _attention_light: CSGBox3D = $AttentionLight

const FITTING_LOOSE_ROTATION := Vector3(0, 0, 0.32)
const FITTING_SEATED_ROTATION := Vector3.ZERO
const ATTENTION_BASE_ENERGY: float = 0.9

var _clicks: int = 0
var _done: bool = false
var _message_timer: float = 0.0
var _pulse_time: float = 0.0


func _ready() -> void:
	_fitting.rotation = FITTING_LOOSE_ROTATION


## This milestone's Phase D: a restrained, state-driven visual cue so
## the player can actually FIND this (easily missed, no-prompt-before-
## this-round) small fitting once E06 is their outstanding assignment,
## without a permanent quest marker -- the light only glows once E06 is
## actually assigned (never spoils it before C01) and goes dark the
## instant it's done, both read straight from DayPlan, no second flag.
func _process(delta: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0 and _message_label != null:
			_message_label.visible = false

	var needs_attention: bool = _day_plan.assignment_task_id == &"e06" and not _day_plan.is_task_done(&"e06")
	_attention_light.visible = needs_attention
	if needs_attention:
		_pulse_time += delta
		var mat: StandardMaterial3D = _attention_light.material
		mat.emission_energy_multiplier = ATTENTION_BASE_ENERGY * (0.55 + 0.45 * (0.5 + 0.5 * sin(_pulse_time * 3.0)))


func interact() -> void:
	if _done:
		_show_message("Connection looks solid.")
		return
	_clicks += 1
	var t: float = clampf(float(_clicks) / float(clicks_required), 0.0, 1.0)
	_fitting.rotation = FITTING_LOOSE_ROTATION.lerp(FITTING_SEATED_ROTATION, t)
	if _clicks >= clicks_required:
		_done = true
		_day_plan.mark_done(&"e06")
		_show_message("Connection tightened.")
	else:
		_show_message("Tightening... (%d/%d)" % [_clicks, clicks_required])


func get_interact_prompt() -> String:
	if _done:
		return "Click: Check Connection (Secure)"
	return "Click: Tighten Loose Connection (%d/%d)" % [_clicks, clicks_required]


func is_done() -> bool:
	return _done


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true
	_message_timer = message_duration
