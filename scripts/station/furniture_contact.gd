extends Node
## Round 30 Priority 3: contact surfaces for interior furniture.
##
## ROOT CAUSE of "dropped items fall inside furniture": 107 visible interior
## props were render-only CSG with no collision at all -- the mattress,
## pillow and headboard, the desk slab, the console desk and its kickplate,
## the wash counter and basin, the wall shelf, the locker, both stools, the
## personal container, the disposal hatch housing ... (the bunk PLATFORM and
## the room shells/walls/floors did collide). carry_system.gd's drop ray
## therefore passed straight through them to the floor, so a dropped part
## ended up inside the bed or the counter.
##
## These props collide on a DEDICATED physics layer (FURNITURE_LAYER,
## value 4 = layer 3), never layer 1. The interaction ray (mask 1) ignores
## them; the drop/placement solver (mask 1 | 4) rests parts on them; and
## since Round 31 the player capsule (free_move_body.tscn, mask 1 | 4)
## collides with them too, so the player can no longer walk through a desk,
## the bunk, the wash counter or the locker. (The navigation clearance
## sweeps already query every layer, so the navigation baseline is
## unchanged.)

const FURNITURE_LAYER: int = 4

## Paths relative to the scene root (the node's owner).
@export var furniture_paths: Array[NodePath] = [
	^"Geometry/BunkMattressBase", ^"Geometry/BunkMattressTop", ^"Geometry/BunkPillowBase",
	^"Geometry/BunkPillowTop", ^"Geometry/BunkBlanketFold", ^"Geometry/BunkHeadboardPanel",
	^"Geometry/BunkHeadboardInset", ^"Geometry/BunkFrameTrimWest", ^"Geometry/BunkFrameTrimFoot",
	^"Geometry/ConsoleDesk", ^"Geometry/ConsoleDeskBacking", ^"Geometry/ConsoleDeskEdge",
	^"Geometry/ConsoleDeskKickplate", ^"Geometry/DeskSurfaceSlab", ^"Geometry/DeskFrontPanelInset",
	^"Geometry/DeskNotebook", ^"Geometry/DeskTaskLightHead",
	^"Geometry/LockerDoorPanelLeft", ^"Geometry/LockerDoorPanelRight", ^"Geometry/LockerTopTrim",
	^"Geometry/LockerBaseKick", ^"Geometry/StoolSeatCap",
	^"Geometry/PersonalContainer", ^"Geometry/PersonalContainerStrap", ^"Geometry/ReadingLightBase",
	^"Geometry/WashMirrorCabinet",     # Round 47: the sink in front of the mirror was removed
	^"Geometry/WallShelf", ^"Geometry/ShelfBook",
	^"Interactables/TrashDisposal/Housing", ^"Interactables/TrashDisposal/HazardFrameBottom",
	^"Interactables/TrashDisposal/RecessLiner",
	^"Interactables/SensorCalibrationStation/Body", ^"Interactables/ValveRoutingStation/Housing",
]

var _applied: Array = []


func _ready() -> void:
	var root: Node = owner if owner != null else get_parent()
	for p in furniture_paths:
		var n: Node = root.get_node_or_null(p)
		if n is CSGShape3D:
			var c := n as CSGShape3D
			if c.use_collision:
				continue # already solid on its own layer; never re-layer it
			c.use_collision = true
			c.collision_layer = FURNITURE_LAYER
			c.collision_mask = 0
			_applied.append(c)
		elif n == null:
			push_warning("furniture_contact: missing %s" % str(p))


func contact_props() -> Array:
	return _applied
