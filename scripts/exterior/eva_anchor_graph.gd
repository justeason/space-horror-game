extends RefCounted
## Round 41 Priority 4: the EXTERIOR TETHER NETWORK -- one shared anchor
## graph (stable ids, world positions, links) used by the EVA system (rings,
## clipping, reach), the solar arrays (geometry is built AROUND these rings:
## they sit on the truss's south handrail, never on photovoltaic cells) and
## the tests (route validation).
##
## Rule (dual-tether, eva_system.gd): a transfer A->B is possible while the
## OLD tether stays secured iff some point lies within CLIP_REACH of B's ring
## (harness to ring) AND within TETHER_LEN of A's ring -- i.e. ring spacing
## <= TETHER_LEN + CLIP_REACH (5.5 + 1.8 = 7.3 m). Every link below is
## <= 3.8 m: comfortable overlap, never a stretch at the cable's limit.
##
## Layout: the hatch ring A1, the antenna route (A2, A3), an upper-hull ring
## above the hatch (H1), and the SOLAR TRUSS north of the station (z -5.2):
## T0 at the airlock, west to the left wing (L1 root .. L5 outer service
## edge), east to the right wing (R0 hull, R1 root .. R5 outer).

const TRUSS_Z := -5.2
const TRUSS_Y := 1.2           # truss centreline height
const RAIL_Y := 1.62           # handrail / ring height on the truss
const RAIL_Z := -4.88          # the truss's SOUTH handrail (hatch side)

## [position, id, kind] -- indices 0-2 are the Round 38-40 rings (saved /
## tested by index); new rings are appended.
const ANCHORS := [
	[Vector3(-4.35, 1.05, -2.74), "A1", "hatch"],
	[Vector3(-3.25, 1.0, -0.6), "A2", "hull"],
	[Vector3(-3.3, 1.0, 1.95), "A3", "antenna"],
	[Vector3(-4.32, 2.45, -2.8), "H1", "hull"],
	[Vector3(-4.8, RAIL_Y, RAIL_Z), "T0", "truss"],
	[Vector3(-7.8, RAIL_Y, RAIL_Z), "L1", "wing_root"],
	[Vector3(-11.3, RAIL_Y, RAIL_Z), "L2", "wing"],
	[Vector3(-14.8, RAIL_Y, RAIL_Z), "L3", "wing_mid"],
	[Vector3(-18.3, RAIL_Y, RAIL_Z), "L4", "wing"],
	[Vector3(-21.8, RAIL_Y, RAIL_Z), "L5", "wing_outer"],
	[Vector3(-1.2, RAIL_Y, RAIL_Z), "R0", "truss"],
	[Vector3(2.4, RAIL_Y, RAIL_Z), "R1", "wing_root"],
	[Vector3(5.9, RAIL_Y, RAIL_Z), "R2", "wing"],
	[Vector3(9.4, RAIL_Y, RAIL_Z), "R3", "wing_mid"],
	[Vector3(12.9, RAIL_Y, RAIL_Z), "R4", "wing"],
	[Vector3(16.4, RAIL_Y, RAIL_Z), "R5", "wing_outer"],
	# Round 50 (A06): a hull ring on the LOWER service module's south wall
	# (B-04), below the antenna pad -- the route to the lower hull.
	[Vector3(-4.15, -1.55, 2.78), "D1", "lower_hull"],
]

## Undirected links (by id): the routes a technician follows.
const LINKS := [
	["A1", "A2"], ["A2", "A3"], ["A1", "H1"], ["A1", "T0"], ["H1", "T0"],
	["T0", "L1"], ["L1", "L2"], ["L2", "L3"], ["L3", "L4"], ["L4", "L5"],
	["A3", "D1"],
	["T0", "R0"], ["R0", "R1"], ["R1", "R2"], ["R2", "R3"], ["R3", "R4"], ["R4", "R5"],
]

## Solar wing extents along x (panels never cover the truss rail).
const LEFT_WING := [-8.7, -25.4]
const RIGHT_WING := [3.3, 20.0]


static func index_of(id: String) -> int:
	for i in ANCHORS.size():
		if ANCHORS[i][1] == id:
			return i
	return -1


static func pos(id: String) -> Vector3:
	var i: int = index_of(id)
	return ANCHORS[i][0] if i >= 0 else Vector3.INF


static func neighbours(id: String) -> Array:
	var out: Array = []
	for l in LINKS:
		if l[0] == id:
			out.append(l[1])
		elif l[1] == id:
			out.append(l[0])
	return out


## Shortest hop route between two ring ids (BFS), [] if unreachable.
static func route(from_id: String, to_id: String) -> Array:
	var prev := {from_id: ""}
	var q: Array = [from_id]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == to_id:
			var path: Array = [cur]
			while prev[path[0]] != "":
				path.push_front(prev[path[0]])
			return path
		for n in neighbours(cur):
			if not prev.has(n):
				prev[n] = cur
				q.append(n)
	return []
