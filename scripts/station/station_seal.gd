extends Node3D
## Round 39 Priority 3: SEALS the station interior. The blockout geometry
## left open seams wherever two spaces meet with different footprints or
## ceiling heights -- a 0.2 m slot between the Control Room and Quarters
## walls (no floor, no jambs), missing lintels where 2.8 m connectors meet
## 3.2 m rooms, open corner pockets at the Life Support bend and the
## Storage <-> Life Support connectors, open shoulders where the corridor
## meets the wider junction -- and from inside you could see out into
## space. Each entry below closes one seam with a solid, collidable panel
## in the material of the wall / floor next to it. The leak sweep
## (tests/test_r39_hull_seal.gd) proves no line of sight remains.
##
## Panels only fill gaps BEHIND / BETWEEN the existing walls, floors and
## ceilings (or narrow a doorway jamb to the matching door width), so
## walkable space and navigation are unchanged (capsule sweep test).

## [name, min corner, max corner, material source node in Geometry]
const SEALS := [
	# --- Control Room <-> Living Quarters doorway (the open 0.2 m slot) ---
	["CtrlLivingSlotSouth", Vector3(1.40, -0.2, -1.20), Vector3(1.60, 3.2, -0.10), "ControlRoomEastWallSouth"],
	["CtrlLivingSlotNorth", Vector3(1.40, -0.2, 1.10), Vector3(1.60, 3.2, 2.20), "ControlRoomEastWallSouth"],
	["CtrlLivingThreshold", Vector3(1.38, -0.2, -0.10), Vector3(1.72, 0.0, 1.10), "ControlRoomFloor"],
	["CtrlLivingHeader", Vector3(1.38, 2.2, -0.10), Vector3(1.79, 2.8, 1.10), "ControlRoomEastWallSouth"],
	["CtrlLivingHeaderTop", Vector3(1.38, 2.8, -0.10), Vector3(1.62, 3.2, 1.10), "ControlRoomEastWallSouth"],
	# --- Corridor -> Junction A shoulders (junction is wider) ---
	["JunctionShoulderEast", Vector3(0.60, -0.2, 3.45), Vector3(1.10, 2.8, 3.55), "JunctionWestWall"],
	["JunctionShoulderWest", Vector3(-1.10, -0.2, 3.45), Vector3(-0.60, 2.8, 3.55), "JunctionWestWall"],
	# --- Junction -> Life Support tunnel / bend corner ---
	["LsBendCorner", Vector3(-0.20, -0.2, 9.30), Vector3(0.20, 2.8, 9.90), "LifeSupportTunnelEastWall"],
	["LsBendInnerSlit", Vector3(-1.00, -0.2, 8.30), Vector3(-0.84, 2.8, 8.50), "LifeSupportTunnelEastWall"],
	["LsBendLintel", Vector3(-3.30, 2.6, 9.50), Vector3(-2.30, 3.2, 9.70), "LifeSupportSouthWallWest"],
	# --- Life Support <-> Storage connectors C / D ---
	["ConnCDWestClosure", Vector3(-6.60, -0.2, 10.55), Vector3(-6.40, 2.8, 11.25), "StorageConnectorCWestWall"],
	["ConnDFloorStrip", Vector3(-6.60, -0.2, 10.98), Vector3(-4.40, 0.0, 11.07), "StorageConnectorDFloor"],
	["ConnDCeilingStrip", Vector3(-6.60, 2.6, 10.98), Vector3(-4.40, 2.8, 11.07), "StorageConnectorDCeiling"],
	["ConnDPocketFloor", Vector3(-5.50, -0.2, 9.70), Vector3(-4.40, 0.0, 10.12), "StorageConnectorDFloor"],
	["ConnDPocketCeiling", Vector3(-5.50, 2.6, 9.70), Vector3(-4.40, 2.8, 10.12), "StorageConnectorDCeiling"],
	["StorageNorthLintel", Vector3(-6.50, 2.6, 9.00), Vector3(-5.50, 3.2, 9.20), "StorageNorthWallWest"],
	["LsWestLintel", Vector3(-4.60, 2.6, 9.70), Vector3(-4.40, 3.2, 10.50), "LifeSupportWestWallNorth"],
	# --- Engineering / Storage doorways under the taller ceilings ---
	["EngAirlockLintel", Vector3(-5.30, 2.6, 3.00), Vector3(-4.30, 3.2, 3.20), "EngineeringSouthWallEast"],
	["EngWestLintel", Vector3(-5.90, 2.6, 4.30), Vector3(-5.70, 3.2, 5.30), "EngineeringWestWallSouth"],
	["EngEastLintel", Vector3(-2.70, 2.6, 5.56), Vector3(-2.50, 3.2, 6.56), "EngineeringEastWallSouth"],
	["StorageSouthLintel", Vector3(-7.50, 2.6, 6.80), Vector3(-6.50, 3.2, 7.00), "StorageSouthWallEast"],
	# --- Comms: west strip closure, wall raises to the 3.2 m ceiling ---
	["CommsWestClosure", Vector3(0.50, -0.2, 7.30), Vector3(0.70, 3.4, 8.30), "CommsSouthWallEast"],
	["CommsStripRaise", Vector3(0.50, 2.6, 7.20), Vector3(1.50, 3.4, 7.40), "CommsSouthWallEast"],
	["CommsJunctionRaise", Vector3(1.30, 2.6, 5.50), Vector3(1.50, 3.4, 7.40), "CommsSouthWallEast"],
	["CommsDoorLintel", Vector3(1.40, 2.6, 5.80), Vector3(2.60, 3.4, 6.00), "CommsSouthWallEast"],
]

var panels: Array = []


func _ready() -> void:
	var geo: Node = get_parent().get_node_or_null("Geometry")
	for s in SEALS:
		var a: Vector3 = s[1]
		var b: Vector3 = s[2]
		var box := CSGBox3D.new()
		box.name = s[0]
		box.size = b - a
		box.position = (a + b) * 0.5
		box.use_collision = true
		var src: Node = geo.get_node_or_null(String(s[3])) if geo != null else null
		if src is CSGBox3D and (src as CSGBox3D).material != null:
			box.material = (src as CSGBox3D).material
		add_child(box)
		panels.append(box)
