extends RefCounted
## Round 49: ROUTES on the station's one movement graph (MovementNodes),
## across both decks. Edges:
##   walk    `neighbors` + same-region mates (horizontal, same deck);
##   ladder  `ladder_neighbors` (the B-00 shaft; climbed, cost LADDER_COST).
## Points on different decks are never adjacent except through a ladder
## edge, so a route can never "teleport" through a floor. An optional
## `allowed` predicate (node -> bool) applies access restrictions; routes
## are shortest by metres (Dijkstra). No second navigation controller:
## this only READS the graph the station already has.

const LADDER_COST := 9.0          # metres-equivalent of one shaft climb (~6 s)
const L = preload("res://scripts/deck_b/deck_b_layout.gd")


static func nodes(root: Node) -> Array:
	var mn: Node = root.get_node_or_null("MovementNodes")
	if mn == null:
		return []
	return mn.get_children().filter(func(n): return n.has_method("get_neighbor_nodes"))


## [{to: Node3D, cost: float, kind: "walk" | "ladder"}]
static func links(n: Node) -> Array:
	var out: Array = []
	for m in n.get_movement_candidates():
		if StringName(m.get("deck")) == StringName(n.get("deck")):
			out.append({"to": m, "cost": (n as Node3D).global_position.distance_to((m as Node3D).global_position), "kind": "walk"})
	if n.has_method("get_ladder_nodes"):
		for m in n.get_ladder_nodes():
			out.append({"to": m, "cost": LADDER_COST, "kind": "ladder"})
	return out


static func find(root: Node, node_name: String) -> Node3D:
	var mn: Node = root.get_node_or_null("MovementNodes")
	return mn.get_node_or_null(node_name) as Node3D if mn != null else null


## Shortest route as node NAMES ([] = none). allowed(node) -> bool.
static func route(root: Node, from_name: String, to_name: String, allowed: Callable = Callable()) -> Array:
	var a: Node3D = find(root, from_name)
	var b: Node3D = find(root, to_name)
	if a == null or b == null:
		return []
	var dist := {a: 0.0}
	var prev := {}
	var open: Array = [a]
	var done := {}
	while not open.is_empty():
		var cur: Node3D = open[0]
		for n in open:
			if float(dist[n]) < float(dist[cur]):
				cur = n
		open.erase(cur)
		if cur == b:
			break
		done[cur] = true
		for l in links(cur):
			var to: Node3D = l["to"]
			if done.has(to):
				continue
			if allowed.is_valid() and to != b and not bool(allowed.call(to)):
				continue
			var nd: float = float(dist[cur]) + float(l["cost"])
			if not dist.has(to) or nd < float(dist[to]):
				dist[to] = nd
				prev[to] = cur
				if not open.has(to):
					open.append(to)
	if not dist.has(b):
		return []
	var path: Array = [String(b.name)]
	var c: Node3D = b
	while prev.has(c):
		c = prev[c]
		path.push_front(String(c.name))
	return path


static func route_length(root: Node, path: Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		var a: Node3D = find(root, path[i - 1])
		var b: Node3D = find(root, path[i])
		var ladder: bool = a.get("ladder_neighbors") != null and Array(a.ladder_neighbors).has(NodePath("../" + String(b.name)))
		total += LADDER_COST if ladder else a.global_position.distance_to(b.global_position)
	return total


## The nearest graph node to a world point ON THE SAME DECK.
static func nearest(root: Node, p: Vector3) -> Node3D:
	var deck: StringName = &"B" if L.is_lower(p) else &"A"
	var best: Node3D = null
	var bd := INF
	for n in nodes(root):
		if StringName(n.get("deck")) != deck:
			continue
		var d: float = (n as Node3D).global_position.distance_to(p)
		if d < bd:
			bd = d
			best = n
	return best


## Emergency egress: from anywhere on Deck B, the route up the shaft to
## Deck A's ShaftTop (ignores access gates: an emergency is never locked in).
static func egress(root: Node, from_p: Vector3) -> Array:
	var n: Node3D = nearest(root, from_p)
	if n == null:
		return []
	return route(root, String(n.name), "ShaftTop")
