extends StaticBody3D
## A small, independent interaction target for one connection point
## inside the electrical panel (scripts/interactables/electrical_panel.gd) --
## a plain StaticBody3D with its own CollisionShape3D, deliberately NOT
## a CSGShape3D nested under the cabinet's own CSG tree. A nested CSG
## child's `use_collision` does not give it an independent raycast
## target -- it merges into the single combined collision shape owned
## by the CSG tree's root (confirmed empirically this round: a raycast
## aimed at such a child was reported as hitting the parent cabinet,
## not the child). A separate StaticBody3D is the same proven pattern
## already used by every other small interactable in this project
## (toggle_switch.gd, rotary_control.gd, wire_component.gd).
##
## `visible` and the child Collision shape's `disabled` are toggled by
## the owning panel (not this script) to gate reachability by
## door-open state -- see electrical_panel.gd's _refresh_interior_visuals().

@export var panel_path: NodePath
## &"damaged" for the one correct connection point; anything else (e.g.
## &"intact") for a deliberately non-functional decoy -- see
## electrical_panel.gd's terminal_interact()/get_terminal_prompt().
@export var terminal_id: StringName = &"damaged"

@onready var _panel: Node = get_node(panel_path)
@onready var _collision: CollisionShape3D = get_node("Collision")


func interact() -> void:
	_panel.terminal_interact(terminal_id)


func get_interact_prompt() -> String:
	return _panel.get_terminal_prompt(terminal_id)


## Called by electrical_panel.gd -- the actual gate that makes this
## terminal reachable (or not) by door-open state.
func set_reachable(reachable: bool) -> void:
	visible = reachable
	_collision.disabled = not reachable
