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


func get_neighbor_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for path in neighbors:
		var node := get_node_or_null(path)
		if node is Node3D:
			result.append(node)
	return result
