extends SceneTree
## Round 24 Priority 1/5 regression coverage: the two Storage-room
## cabinets must be genuinely recessed storage with real depth, not
## shallow cut-outs whose "back" is really the room wall.
##
## Root cause found this round: both cabinet shells extended ~0.35m
## BEHIND the room's inner wall face, but the Storage west/east walls
## were single solid CSGBox3D slabs spanning the whole wall, so the wall
## filled the back of each cabinet. The visible back of each cabinet
## was the wall face only ~0.2m in, and the wire/filter (placed near
## that face) clipped into it. Fixed by splitting each wall around a
## real opening and deepening the shells into the hull space behind.
##
## Also covers the Priority 5 additions on the same cabinets: the
## interior lamp (on while open, off once closed) and the live stock
## placard (QTY 1 -> QTY 0 - RESTOCK once the part is taken).
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var geo: Node = main.get_node("Geometry")
	var specs := [
		{"cab": geo.get_node("StorageCabinet1"), "item": main.get_node("Interactables/WireComponent"), "walls": ["StorageWestWall", "StorageWestWallNorth", "StorageWestWallBelowCabinet", "StorageWestWallAboveCabinet", "StorageRack1Upper", "StorageRack1Lower"]},
		{"cab": geo.get_node("StorageCabinet2"), "item": main.get_node("Interactables/FilterCartridge"), "walls": ["StorageEastWall", "StorageEastWallNorth", "StorageEastWallBelowCabinet", "StorageEastWallAboveCabinet", "StorageRack2Upper", "StorageRack2Lower"]},
	]
	for spec in specs:
		var cab: Node3D = spec["cab"]
		var item: Node3D = spec["item"]
		var tag: String = cab.name
		var back: CSGBox3D = cab.get_node("Back")
		var hinge: Node3D = cab.get_node("DoorHinge")
		var depth: float = absf(hinge.global_position.x - back.global_position.x)
		_check("%s: interior depth door->back is a real locker depth (%.2fm >= 0.55m)" % [tag, depth], depth >= 0.55)

		# No solid wall/rack volume may occupy the cabinet's interior.
		var interior := AABB(Vector3(minf(back.global_position.x, hinge.global_position.x) + 0.015, 1.065, 7.715), Vector3(depth - 0.03, 0.47, 0.57))
		for wall_name in spec["walls"]:
			var wall: CSGBox3D = geo.get_node(wall_name)
			var wall_box := AABB(wall.global_position - wall.size * 0.5, wall.size)
			_check("%s: %s does not intrude into the cabinet interior" % [tag, wall_name], not wall_box.intersects(interior))

		# The stored item's own geometry must not clip any wall/rack, and
		# must sit fully inside the interior volume.
		var item_box := _visual_aabb(item)
		_check("%s: stored item fully inside the cabinet interior (item=%s)" % [tag, str(item_box)], interior.grow(0.005).encloses(item_box))
		for wall_name in spec["walls"]:
			var wall: CSGBox3D = geo.get_node(wall_name)
			var wall_box := AABB(wall.global_position - wall.size * 0.5, wall.size)
			_check("%s: stored item does not clip %s" % [tag, wall_name], not wall_box.intersects(item_box))
		var shelf: CSGBox3D = cab.get_node("Shelf")
		var shelf_top: float = shelf.global_position.y + shelf.size.y * 0.5
		_check("%s: stored item rests ON the shelf (bottom %.3f vs shelf top %.3f)" % [tag, item_box.position.y, shelf_top], absf(item_box.position.y - shelf_top) < 0.012)

		# Priority 5: interior lamp + stock placard.
		var lamp: Light3D = cab.get_node("InteriorLight")
		var label: Label3D = cab.get_node("DoorHinge/StockLabel")
		_check("%s: interior lamp off while closed" % tag, lamp.light_energy == 0.0)
		_check("%s: stock placard reads QTY 1 initially" % tag, label.text.ends_with("QTY 1") and cab.stock_count() == 1)
		cab.interact()
		await create_timer(0.7).timeout
		_check("%s: interior lamp on once opened" % tag, lamp.light_energy > 0.0)
		_check("%s: stored item revealed once opened" % tag, item.visible)
		item.interact()
		await process_frame
		await process_frame
		_check("%s: stock placard reads RESTOCK once the part is taken" % tag, cab.stock_count() == 0 and label.text.find("QTY 0") != -1)
		cab.interact()
		await create_timer(0.7).timeout
		_check("%s: interior lamp off again once closed" % tag, lamp.light_energy == 0.0)
		_check("%s: closing the cabinet did not hide the part being carried" % tag, item.visible)
		# Return the part to its shelf with the door SHUT: it must be
		# re-gated (hidden, non-collidable) like any stowed item.
		main.get_node("Player/CarrySystem").drop()
		await process_frame
		await process_frame
		_check("%s: part returned to the shelf counts as stocked again" % tag, cab.stock_count() == 1)
		_check("%s: part returned behind a shut door is hidden" % tag, not item.visible)
		_check("%s: part returned behind a shut door is not collidable" % tag, item.get_node("Collision").disabled)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _visual_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var b: AABB = (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children(): stack.append(c)
	return box


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
