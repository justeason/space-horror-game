extends Node3D
## Owns a small set of physical controls mounted together, and reflects
## whether their combined state currently matches the configuration
## required for this maintenance task.
##
## The panel never receives clicks itself — it has no collision shape of
## its own — it only listens to its controls' `state_changed` signals and
## updates its own status light. This is intentionally specific to one
## task (`_is_configuration_correct()`), not a generic rules engine: a
## future panel with a different task gets its own small script shaped
## like this one. Extract shared behavior only once that duplication
## actually happens.

@export var switch_a_path: NodePath
@export var switch_b_path: NodePath

@onready var status_light: MeshInstance3D = $StatusLight

const COLOR_NEUTRAL := Color(0.5, 0.42, 0.1)
const COLOR_CORRECT := Color(0.05, 0.55, 0.1)
const STATUS_EMISSION_ENERGY := 0.6

var switch_a: Node
var switch_b: Node

var _status_material: StandardMaterial3D


func _ready() -> void:
	switch_a = get_node(switch_a_path)
	switch_b = get_node(switch_b_path)
	switch_a.state_changed.connect(_on_switch_changed)
	switch_b.state_changed.connect(_on_switch_changed)

	_status_material = StandardMaterial3D.new()
	_status_material.emission_enabled = true
	status_light.material_override = _status_material

	_evaluate()


func _on_switch_changed(_is_on: bool) -> void:
	_evaluate()


func _evaluate() -> void:
	var color := COLOR_CORRECT if _is_configuration_correct() else COLOR_NEUTRAL
	_status_material.albedo_color = color
	_status_material.emission = color
	_status_material.emission_energy_multiplier = STATUS_EMISSION_ENERGY


## The one task this first panel represents: switch A on, switch B off.
func _is_configuration_correct() -> bool:
	return switch_a.is_on and not switch_b.is_on
