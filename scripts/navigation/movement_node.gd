extends Node3D
## A single physical position the player can occupy.
##
## The movement graph is formed purely by these nodes pointing at their
## neighbors. There is no separate graph manager: a junction is simply a
## MovementNode with more than two entries in `neighbors`.

## Human-readable id, used only for debugging/printing.
@export var node_id: String = ""

## Other MovementNodes directly reachable from this one.
@export var neighbors: Array[NodePath] = []

## Optional named region. Nodes sharing a non-empty region are treated as
## mutually, directly reachable from one another for directional movement
## selection — a small "free movement" area — in addition to whatever is
## listed in `neighbors`. Leave empty for ordinary point-to-point nodes
## (e.g. a corridor step), which are completely unaffected.
@export var region: StringName = &""

## Round 49: the deck this node is on ("A" = the operational upper deck,
## "B" = the Lower Service Deck). Points on different decks are NEVER
## adjacent through `neighbors` (a walk); only LADDER links connect them.
@export var deck: StringName = &"A"

## Round 49: links that are CLIMBED through the vertical access shaft
## (vertical_shaft.gd), not walked. Kept separate from `neighbors` so
## walking validation (capsule sweeps) never treats a vertical tube as a
## floor route; route-finding (station_graph.gd) includes them.
@export var ladder_neighbors: Array[NodePath] = []


func get_neighbor_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for path in neighbors:
		var node := get_node_or_null(path)
		if node is Node3D:
			result.append(node)
	return result


## Other MovementNodes sharing this node's `region` (siblings under the
## same parent), excluding this node itself. Empty if `region` is unset.
func get_region_mates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if region == &"":
		return result
	var parent := get_parent()
	if parent == null:
		return result
	for sibling in parent.get_children():
		if sibling == self:
			continue
		if sibling.has_method("get_region_mates") and sibling.region == region:
			result.append(sibling)
	return result


func get_ladder_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for path in ladder_neighbors:
		var node := get_node_or_null(path)
		if node is Node3D:
			result.append(node)
	return result


## The full set of nodes directly reachable from here for movement
## purposes: explicit neighbors plus region mates, de-duplicated. This is
## the one place "where can I walk from here" is decided — callers never
## need to know about regions.
func get_movement_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = get_neighbor_nodes()
	for mate in get_region_mates():
		if not result.has(mate):
			result.append(mate)
	return result
