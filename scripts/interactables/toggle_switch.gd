extends StaticBody3D
## A physical toggle switch: look at it, click it, it flips between ON
## and OFF. The lever physically rotates and a small indicator light
## swaps between dim red and dim green. No text, no popup, no abstract UI.
##
## `interact()` is the only contract InteractionController requires —
## any future interactable (buttons, panels, doors) just needs its own
## version of this method. Emits `state_changed` so an owning device
## (e.g. a ControlPanel) can react — but this switch neither knows nor
## cares whether anything is listening, so it works identically standing
## alone or mounted on a panel.

signal state_changed(is_on: bool)

const LEVER_ANGLE_OFF := -0.45 # radians, ~-26 degrees
const LEVER_ANGLE_ON := 0.45 # ~+26 degrees

const COLOR_OFF := Color(0.45, 0.04, 0.04)
const COLOR_ON := Color(0.05, 0.55, 0.1)
const INDICATOR_EMISSION_ENERGY := 0.6

@export var is_on: bool = false

@onready var lever_pivot: Node3D = $LeverPivot
@onready var indicator_mesh: MeshInstance3D = $IndicatorLight

var _indicator_material: StandardMaterial3D


func _ready() -> void:
	# Created fresh per-instance (not shared via a scene sub-resource) so
	# multiple switches can hold independent ON/OFF colors.
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.emission_enabled = true
	indicator_mesh.material_override = _indicator_material
	_apply_state()


func interact() -> void:
	is_on = not is_on
	_apply_state()
	state_changed.emit(is_on)


func _apply_state() -> void:
	lever_pivot.rotation.z = LEVER_ANGLE_ON if is_on else LEVER_ANGLE_OFF

	var color := COLOR_ON if is_on else COLOR_OFF
	_indicator_material.albedo_color = color
	_indicator_material.emission = color
	_indicator_material.emission_energy_multiplier = INDICATOR_EMISSION_ENERGY
