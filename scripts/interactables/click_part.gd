extends StaticBody3D
## Round 35: a small clickable PART of a larger piece of equipment (a
## breaker lever, a grille clip, a knob, a seal section, a button). The
## equipment owns all state; this only routes the click and the prompt.
## Pickable-only layer (16): it never blocks the player or physics.

var owner_node: Node = null
var part_id: StringName = &""


static func make(owner: Node, id: StringName, size: Vector3, parent: Node3D, pos: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_script(load("res://scripts/interactables/click_part.gd"))
	b.name = "Click_%s" % id
	b.owner_node = owner
	b.part_id = id
	b.collision_layer = 16
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	parent.add_child(b)
	b.position = pos
	return b


func interact() -> void:
	if owner_node != null and owner_node.has_method("on_part"):
		owner_node.on_part(part_id)


func get_interact_prompt() -> String:
	if owner_node != null and owner_node.has_method("part_prompt"):
		return owner_node.part_prompt(part_id)
	return ""


## Round 36: a part can also be a RECEPTACLE (e.g. a data port's socket):
## the carry system's Space "stow" protocol is forwarded to the owning
## equipment, which decides what it accepts and how the hint reads.
func accepts_item(item: Node) -> bool:
	return owner_node != null and owner_node.has_method("part_accepts_item") and owner_node.part_accepts_item(part_id, item)


func stow(item: Node3D) -> bool:
	if owner_node != null and owner_node.has_method("part_stow"):
		return owner_node.part_stow(part_id, item)
	return false


## Contextual verb phrase for the "Space: ..." hint ("" = default wording).
func stow_hint(item: Node) -> String:
	if owner_node != null and owner_node.has_method("part_stow_hint"):
		return owner_node.part_stow_hint(part_id, item)
	return ""
