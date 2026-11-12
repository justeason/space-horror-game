extends RefCounted
## Round 49: DECK B -- the LOWER SERVICE DECK. Pure data (no nodes): the
## authoritative physical layout every other Deck B system reads (the
## builder, the navigation graph, the workstation map, the hull, the tests).
##
## Coordinate system = the station's: x east, z "north" (map down), y up.
## Deck A (the existing operational level, LOCKED) has its floor top at
## y = 0. Deck B's floor top is at FLOOR_Y; a ~0.6 m structural / utility
## gap separates the two pressure hulls (the upper floor's underside plating
## at y -0.32, Deck B's roof plating at y -0.48). "Up" and "down" are
## OPERATIONAL labels (the magnetic-boot floor plane), not gravity.
##
## SPACES: axis-aligned modules [id, kind, x0, x1, z0, z1, ceiling_y].
## Walls are 0.2 m thick and CENTRED on the rectangle edges (the Deck A
## convention), so a 1.2 m corridor has 1.0 m clear. Where two spaces share
## an edge the wall is built once; a DOOR on a shared edge cuts an opening
## (2.1 m high; the lintel above it runs up to the higher ceiling).

const FLOOR_Y := -3.9
const EYE_Y := FLOOR_Y + 1.6          # standing eye height on Deck B
const ROOM_CEIL := -0.8                # rooms: 3.1 m clear
const CORR_CEIL := -1.3                # service corridors: 2.6 m clear
const SLAB := 0.2
const WALL := 0.2
const DOOR_H := 2.2
## Visual layer of Deck B's interior (so Deck A lights never reach it).
const LAYER := 1 << 13

## The vertical access shaft (B-00): a pressurised tube from a floor hatch
## in the Deck A shaft vestibule (off Engineering's north wall) down into
## the Lower Junction. Centre (x, z), inner radius, hatch opening half-size.
const SHAFT_X := -4.45
const SHAFT_Z := 8.15
const SHAFT_R := 0.5
const HATCH_HALF := 0.5
## Deck A vestibule (new module in the courtyard north of Engineering).
const VESTIBULE := Rect2(-5.2, 6.9, 1.5, 2.0)     # x -5.2..-3.7, z 6.9..8.9
## The service hoist (compact component lift) beside the vestibule door.
const HOIST_X := -3.935
const HOIST_Z := 6.68

## [id, kind, x0, x1, z0, z1, ceiling]. kind: room | corridor | sealed.
const SPACES := [
	["B01", "room", -5.4, -2.2, 6.4, 9.6, -0.9],
	["SPINE", "corridor", -2.2, 2.6, 7.4, 8.6, CORR_CEIL],
	["B03", "room", -1.9, 1.7, 4.0, 7.4, ROOM_CEIL],
	["B02", "room", -1.9, 1.7, 8.6, 11.0, ROOM_CEIL],
	["ARCH_A", "corridor", 2.6, 3.6, 7.4, 10.0, CORR_CEIL],
	["ARCH_B", "corridor", 3.6, 5.2, 9.0, 10.0, CORR_CEIL],
	["B09", "room", 5.2, 8.0, 7.8, 10.8, -1.0],
	["B10", "sealed", 2.6, 4.6, 4.4, 7.4, -1.0],
	["CARGO_C", "corridor", -6.6, -5.4, 6.5, 7.5, CORR_CEIL],
	["B08", "room", -9.6, -6.6, 5.0, 9.0, ROOM_CEIL],
	["B11", "corridor", -8.6, -7.4, 9.0, 10.2, CORR_CEIL],
	["B04", "room", -5.6, -2.2, 3.0, 6.4, ROOM_CEIL],
	["NHALL", "corridor", -4.2, -2.8, 9.6, 11.0, CORR_CEIL],
	["NHALL2", "corridor", -9.0, -0.4, 11.0, 12.2, CORR_CEIL],
	["B05", "room", -6.2, -3.0, 12.2, 15.0, ROOM_CEIL],
	["B06", "room", -3.0, -0.4, 12.2, 14.8, ROOM_CEIL],
	["B07", "room", -11.6, -9.0, 10.2, 13.4, ROOM_CEIL],
]
## Doors on shared edges: [space_a, space_b, centre (along the edge), width,
## kind]. kind: open | hatch (a framed pressure doorway, open) |
## sealed (a closed bulkhead hatch: no opening).
const DOORS := [
	["B01", "SPINE", 8.0, 1.0, "open"],
	["SPINE", "B03", -0.1, 0.9, "hatch"],
	["SPINE", "B02", -0.1, 0.9, "hatch"],
	["SPINE", "ARCH_A", 8.0, 1.0, "open"],
	["ARCH_A", "ARCH_B", 9.5, 0.9, "open"],
	["ARCH_B", "B09", 9.5, 0.8, "hatch"],
	["ARCH_A", "B10", 3.1, 0.8, "sealed"],
	["B01", "CARGO_C", 7.0, 0.9, "open"],
	["CARGO_C", "B08", 7.0, 0.9, "hatch"],
	["B08", "B11", -8.0, 0.9, "open"],
	["B01", "B04", -3.0, 0.9, "hatch"],
	["B01", "NHALL", -3.5, 1.0, "open"],
	["NHALL", "NHALL2", -3.5, 1.2, "open"],
	["NHALL2", "B05", -4.6, 0.9, "hatch"],
	["NHALL2", "B06", -1.8, 0.9, "hatch"],
	["NHALL2", "B07", 11.6, 0.9, "hatch"],
]
## B-11's far end: a sealed pressure bulkhead (future expansion interface).
const STUB_BULKHEAD := Vector3(-8.0, FLOOR_Y, 10.2)

## Room identity: id -> [name, short, tier (clearance), light colour, light
## energy, purpose]. Tier 0 = never accessible (reserved).
const ROOMS := {
	&"b01": ["Lower Junction", "LOWER JCT", 1, Color(0.86, 0.9, 0.95), 1.0, "utility spine: lighting, Bus B distribution, repeater"],
	&"b02": ["Water Recovery", "WATER", 1, Color(0.82, 0.92, 1.0), 1.15, "condensate / hygiene water recovery and storage"],
	&"b03": ["Thermal Control", "THERMAL", 1, Color(1.0, 0.86, 0.7), 0.95, "main coolant loop, pumps, radiator control"],
	&"b04": ["Fabrication Workshop", "WORKSHOP", 2, Color(1.0, 0.97, 0.9), 1.2, "bench repair, test bench, small fabrication"],
	&"b05": ["Payload Laboratory", "LAB", 3, Color(0.95, 0.98, 1.0), 1.25, "glovebox, optics, imaging, incubator"],
	&"b06": ["Hydroponics", "BOTANY", 3, Color(0.95, 0.85, 1.0), 0.9, "controlled growth chamber"],
	&"b07": ["Medical / Exercise", "MEDICAL", 3, Color(0.96, 0.96, 0.92), 1.0, "health monitor, dosimetry, exercise"],
	&"b08": ["Cargo / Docking Support", "CARGO", 2, Color(1.0, 0.92, 0.75), 1.0, "shipment receipt, sorting, berthing port"],
	&"b09": ["Data Archive", "ARCHIVE", 4, Color(0.75, 0.82, 0.95), 0.75, "long-term records, backups"],
	&"b10": ["Restricted Equipment Compartment", "B-10", 0, Color(0.5, 0.5, 0.5), 0.0, "attitude-control electronics (sealed, future)"],
	&"b11": ["Service Access Stub", "B-11", 2, Color(0.8, 0.8, 0.8), 0.6, "future expansion bulkhead (sealed end)"],
}
## Space -> room id (corridors belong to the room they serve for access).
const SPACE_ROOM := {"B01": &"b01", "SPINE": &"b01", "B03": &"b03", "B02": &"b02", "ARCH_A": &"b01", "ARCH_B": &"b09", "B09": &"b09",
	"B10": &"b10", "CARGO_C": &"b08", "B08": &"b08", "B11": &"b11", "B04": &"b04", "NHALL": &"b05", "NHALL2": &"b05", "B05": &"b05",
	"B06": &"b06", "B07": &"b07"}
## Physical access gates: the doorway a technician below the room's tier is
## held at (an invisible barrier + a red door lamp, like Deck A's gates).
## [room, space whose edge holds it, door index in DOORS].
const GATES := [[&"b04", 10], [&"b08", 7], [&"b05", 11], [&"b09", 4]]
## (NHALL leads to the Lab / Botany / Medical wing: one gate at the hall;
## the stub B-11 is reached through Cargo.)

## Movement graph (eye height EYE_Y): [name, x, z, links..., region].
## Doorway waypoints sit ON the door centre so capsule sweeps follow the
## real openings. The ladder link (ShaftBottom <-> ShaftTop on Deck A) is a
## LADDER edge (climbed, not walked) -- see movement_node.gd.
const NODES := [
	["BShaftBottom", -3.55, 8.15, ["BJunctionC"], ""],
	["BJunctionC", -3.2, 8.0, ["BShaftBottom", "BJunctionE", "BJunctionSW", "BJunctionN"], ""],
	["BJunctionSW", -3.35, 7.3, ["BJunctionC", "BJunctionW", "BJunctionS"], ""],
	["BJunctionE", -2.6, 8.0, ["BJunctionC", "BSpineW"], ""],
	["BJunctionW", -4.6, 7.1, ["BJunctionSW", "BCargoCorr"], ""],
	["BJunctionS", -3.0, 6.9, ["BJunctionSW", "BWorkshopDoor"], ""],
	["BJunctionN", -3.5, 9.2, ["BJunctionC", "BNHall"], ""],
	["BSpineW", -1.6, 8.0, ["BJunctionE", "BSpineMid"], ""],
	["BSpineMid", -0.1, 8.0, ["BSpineW", "BSpineE", "BThermalDoor", "BWaterDoor"], ""],
	["BSpineE", 1.8, 8.0, ["BSpineMid", "BArchA1"], ""],
	["BThermalDoor", -0.1, 7.4, ["BSpineMid", "BThermalA"], ""],
	["BThermalA", -0.1, 6.3, ["BThermalDoor", "BThermalW", "BThermalE"], ""],
	["BThermalW", -0.75, 5.6, ["BThermalA"], ""],
	["BThermalE", 0.9, 5.0, ["BThermalA"], ""],
	["BWaterDoor", -0.1, 8.6, ["BSpineMid", "BWaterA"], ""],
	["BWaterA", -0.1, 9.6, ["BWaterDoor", "BWaterW", "BWaterE"], ""],
	["BWaterW", -1.0, 9.85, ["BWaterA"], ""],
	["BWaterE", 0.85, 9.85, ["BWaterA"], ""],
	["BArchA1", 3.1, 8.0, ["BSpineE", "BArchA2"], ""],
	["BArchA2", 3.1, 9.5, ["BArchA1", "BArchB"], ""],
	["BArchB", 4.4, 9.5, ["BArchA2", "BArchiveDoor"], ""],
	["BArchiveDoor", 5.2, 9.5, ["BArchB", "BArchiveA"], ""],
	["BArchiveA", 6.0, 9.4, ["BArchiveDoor", "BArchiveN", "BArchiveS"], ""],
	["BArchiveN", 6.85, 10.1, ["BArchiveA"], ""],
	["BArchiveS", 6.85, 8.5, ["BArchiveA"], ""],
	["BCargoCorr", -6.0, 7.0, ["BJunctionW", "BCargoDoor"], ""],
	["BCargoDoor", -6.6, 7.0, ["BCargoCorr", "BCargoA"], ""],
	["BCargoA", -7.6, 7.0, ["BCargoDoor", "BCargoN", "BCargoS", "BCargoW"], ""],
	["BCargoN", -8.0, 8.2, ["BCargoA", "BStubDoor"], ""],
	["BCargoS", -8.0, 6.1, ["BCargoA"], ""],
	["BCargoW", -8.8, 7.0, ["BCargoA"], ""],
	["BStubDoor", -8.0, 9.0, ["BCargoN", "BStub"], ""],
	["BStub", -8.0, 9.6, ["BStubDoor"], ""],
	["BWorkshopDoor", -3.0, 6.4, ["BJunctionS", "BWorkshopA"], ""],
	["BWorkshopA", -3.0, 5.5, ["BWorkshopDoor", "BWorkshopW", "BWorkshopSE"], ""],
	["BWorkshopW", -4.35, 4.8, ["BWorkshopA"], ""],
	["BWorkshopSE", -3.0, 3.9, ["BWorkshopA"], ""],
	["BNHall", -3.5, 10.4, ["BJunctionN", "BNHall2C"], ""],
	["BNHall2C", -3.5, 11.6, ["BNHall", "BNHall2W", "BBotanyDoor", "BLabDoor"], ""],
	["BLabDoor", -4.6, 11.6, ["BNHall2C", "BLabEntry", "BNHall2W"], ""],
	["BLabEntry", -4.6, 12.2, ["BLabDoor", "BLabA"], ""],
	["BLabA", -4.6, 13.2, ["BLabEntry", "BLabW", "BLabE"], ""],
	["BLabW", -5.45, 13.75, ["BLabA"], ""],
	["BLabE", -3.8, 13.75, ["BLabA"], ""],
	["BBotanyDoor", -1.8, 11.6, ["BNHall2C", "BBotanyEntry"], ""],
	["BBotanyEntry", -1.8, 12.2, ["BBotanyDoor", "BBotanyA"], ""],
	["BBotanyA", -1.8, 13.2, ["BBotanyEntry", "BBotanyN"], ""],
	["BBotanyN", -1.8, 14.1, ["BBotanyA"], ""],
	["BNHall2W", -7.0, 11.6, ["BLabDoor", "BMedDoor"], ""],
	["BMedDoor", -9.0, 11.6, ["BNHall2W", "BMedA"], ""],
	["BMedA", -10.1, 11.6, ["BMedDoor", "BMedN", "BMedS"], ""],
	["BMedN", -9.75, 12.55, ["BMedA"], ""],
	["BMedS", -10.0, 11.05, ["BMedA"], ""],
]
## Deck A additions (new nodes in main.tscn's MovementNodes graph).
const A_NODES := [
	["ShaftDoorEng", -4.6, 6.45, ["EngineeringB"]],
	["ShaftTop", -4.45, 7.35, ["ShaftDoorEng"]],
]
## Surveillance (Deck B): [id, label, room, node, position, look-at].
const CAMERAS := [
	["INT-09", "LOWER JUNCTION", &"b01", "CamLowerJunction", Vector3(-2.45, -1.15, 9.42), Vector3(-4.3, FLOOR_Y + 0.9, 7.6)],
	["INT-10", "SERVICE SPINE", &"b01", "CamServiceSpine", Vector3(2.4, -1.5, 8.45), Vector3(-1.6, FLOOR_Y + 0.6, 7.7)],
	["INT-11", "CARGO", &"b08", "CamCargo", Vector3(-6.82, -1.05, 8.78), Vector3(-8.8, FLOOR_Y + 0.5, 5.6)],
	["INT-12", "ARCHIVE BRANCH", &"b09", "CamArchiveBranch", Vector3(3.1, -1.45, 7.5), Vector3(3.25, FLOOR_Y + 0.5, 9.95)],
]


static func space(id: String) -> Array:
	for s in SPACES:
		if s[0] == id:
			return s
	return []


static func rect(id: String) -> Rect2:
	var s: Array = space(id)
	return Rect2(Vector2(s[2], s[4]), Vector2(s[3] - s[2], s[5] - s[4])) if not s.is_empty() else Rect2()


## Which Deck B space contains (x, z) (inside the walls), "" = none.
static func space_at(x: float, z: float) -> String:
	for s in SPACES:
		if x > float(s[2]) and x < float(s[3]) and z > float(s[4]) and z < float(s[5]):
			return String(s[0])
	return ""


static func room_at(p: Vector3) -> StringName:
	if p.y > FLOOR_Y + 3.2:
		return &""
	var sp: String = space_at(p.x, p.z)
	return SPACE_ROOM.get(sp, &"") if sp != "" else &""


## True when a world point is below Deck A's floor plane (on / in Deck B or
## the lower part of the shaft).
static func is_lower(p: Vector3) -> bool:
	return p.y < -0.5


static func room_name(room: StringName) -> String:
	return String(ROOMS[room][0]) if ROOMS.has(room) else ""


## The shared edge between two spaces: {axis: "x"|"z", at, lo, hi} or {}.
static func shared_edge(a: String, b: String) -> Dictionary:
	var ra: Array = space(a)
	var rb: Array = space(b)
	if ra.is_empty() or rb.is_empty():
		return {}
	for pair in [[3, 2], [2, 3]]:
		if absf(float(ra[pair[0]]) - float(rb[pair[1]])) < 0.001:
			var lo: float = maxf(float(ra[4]), float(rb[4]))
			var hi: float = minf(float(ra[5]), float(rb[5]))
			if hi > lo:
				return {"axis": "x", "at": float(ra[pair[0]]), "lo": lo, "hi": hi}
	for pair in [[5, 4], [4, 5]]:
		if absf(float(ra[pair[0]]) - float(rb[pair[1]])) < 0.001:
			var lo2: float = maxf(float(ra[2]), float(rb[2]))
			var hi2: float = minf(float(ra[3]), float(rb[3]))
			if hi2 > lo2:
				return {"axis": "z", "at": float(ra[pair[0]]), "lo": lo2, "hi": hi2}
	return {}


## World position of a door's centre at floor level.
static func door_point(i: int) -> Vector3:
	var d: Array = DOORS[i]
	var e: Dictionary = shared_edge(d[0], d[1])
	if e.is_empty():
		return Vector3.ZERO
	return Vector3(float(e["at"]), FLOOR_Y, float(d[2])) if e["axis"] == "x" else Vector3(float(d[2]), FLOOR_Y, float(e["at"]))
