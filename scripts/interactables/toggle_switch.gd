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
##
## `switch_label` is cosmetic identification only (the physical plate's
## engraved name and this switch's contextual-prompt text) — it does NOT
## imply the switch is wired to the system it names. A decorative switch
## mounted standalone on the workstation dressing (e.g. "Comms") still
## only flips its own lever and indicator; it never claims to actually
## toggle ship comms. Only a switch an owning device (ControlPanel)
## actually listens to via `state_changed` has any effect beyond itself.
##
## The scene's Label3D sits on its own small LabelBacking placard,
## mounted flush against the top margin of MountingPlate, with a much
## smaller pixel_size than Label3D's default. The original version used
## the default pixel_size (0.01) at font_size=28, which rendered about
## 0.28m tall on a switch whose whole plate is only 0.2m across, floating
## 0.035m above the switch with nothing supporting it (player feedback:
## "oversized ... appear to float").

signal state_changed(is_on: bool)

const LEVER_ANGLE_OFF := -0.45 # radians, ~-26 degrees
const LEVER_ANGLE_ON := 0.45 # ~+26 degrees

const COLOR_OFF := Color(0.45, 0.04, 0.04)
const COLOR_ON := Color(0.05, 0.55, 0.1)
const INDICATOR_EMISSION_ENERGY := 0.6

@export var is_on: bool = false
## Plate engraving / contextual-prompt text, e.g. "Power", "Comms". See
## the class doc comment above — cosmetic only, not a functional claim.
@export var switch_label: String = "Switch"

@onready var lever_pivot: Node3D = $LeverPivot
@onready var indicator_mesh: MeshInstance3D = $IndicatorLight
@onready var _label: Label3D = get_node_or_null("Label3D")

var _indicator_material: StandardMaterial3D


func _ready() -> void:
	# Created fresh per-instance (not shared via a scene sub-resource) so
	# multiple switches can hold independent ON/OFF colors.
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.emission_enabled = true
	indicator_mesh.material_override = _indicator_material
	if _label != null:
		_label.text = switch_label
	_apply_state()


func interact() -> void:
	is_on = not is_on
	_apply_state()
	state_changed.emit(is_on)


func get_interact_prompt() -> String:
	return "Click: Toggle %s" % switch_label


func _apply_state() -> void:
	lever_pivot.rotation.z = LEVER_ANGLE_ON if is_on else LEVER_ANGLE_OFF

	var color := COLOR_ON if is_on else COLOR_OFF
	_indicator_material.albedo_color = color
	_indicator_material.emission = color
	_indicator_material.emission_energy_multiplier = INDICATOR_EMISSION_ENERGY
