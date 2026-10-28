extends StaticBody3D
## A physical rotary dial with a small number of fixed detents: click to
## advance to the next position, the knob visibly rotates. Same
## duck-typed `interact()` contract as toggle_switch.gd, and the same
## "this object owns its own small state, nothing else needs to know
## about it" philosophy (GAME_DESIGN.md Section 48) -- not wired to any
## game system, a purposeful but currently decorative-in-function
## spacecraft control (Control Room Workstation Revamp Section 6).

signal position_changed(index: int)

@export var detent_count: int = 4
@export var detent_span_degrees: float = 180.0

@onready var _knob: Node3D = $Knob

var _index: int = 0


func _ready() -> void:
	_apply_position()


func interact() -> void:
	_index = (_index + 1) % detent_count
	_apply_position()
	position_changed.emit(_index)


func get_interact_prompt() -> String:
	return "Click: Adjust Dial"


func _apply_position() -> void:
	var t: float = float(_index) / float(max(detent_count - 1, 1))
	var angle: float = deg_to_rad(-detent_span_degrees * 0.5 + detent_span_degrees * t)
	_knob.rotation.y = angle
