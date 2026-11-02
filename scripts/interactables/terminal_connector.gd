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
## The child Collision shape's `disabled` is toggled by the owning
## panel (not this script) to gate reachability by door-open state --
## see electrical_panel.gd's _refresh_interior_visuals(). This node's
## own `visible` is NOT touched by that toggle and stays permanently
## false (set once in main.tscn) -- it is a pure, invisible raycast
## target, never meant to be its own visible object. The panel's
## properly-scaled WorldDiorama twin (shown/hidden by that SAME
## door-open condition, see electrical_panel.gd's own
## _refresh_interior_visuals()) already provides the real terminal
## visual the player sees.
##
## Round 21 Priority 6 fix: set_reachable() used to also set
## `visible = reachable`, which -- confirmed by render, not assumed --
## was the actual cause of "two unexplained cube-like blocks" appearing
## in the cabinet the moment its door opened: this node's own small,
## UNSCALED BoxMesh placeholder became visible right alongside (and
## noticeably larger/cruder than) WorldDiorama's correctly-scaled
## terminal visuals, which are built from the exact same geometry the
## focused minigame itself uses. The minigame's own diorama never
## showed this because it is an entirely separate scene instance that
## never touches this node at all. Removing the `visible` toggle here
## leaves reachability (the collision shape) working exactly as
## before, while the world cabinet now shows only the one correct,
## minigame-matching visual.

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
	_collision.disabled = not reachable
