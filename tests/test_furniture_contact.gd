extends SceneTree
## Round 30 Priority 3 regression: dropped parts land on real surfaces and
## never clip into interior furniture.
##
## ROOT CAUSES: (1) 107 visible interior props were render-only CSG with no
## collision (mattress, pillow, desk slab, console desk, wash counter/basin,
## stools, locker, hatch housing ...), so the old single drop ray went
## straight through them; (2) that ray placed the item's ORIGIN, at one
## point, with no footprint/clearance/path checks; (3) the bunk's invisible
## hover box (0.40-0.75 m) sat 21 cm above the mattress, so once furniture
## collided, items rested on thin air. Now: furniture_contact.gd puts those
## props on a dedicated contact layer (player capsule / navigation /
## interaction ray unchanged), and carry_system.gd's placement solver sweeps
## the item's visible box out from the hand and down onto the first
## near-level, fully supported surface, ignoring hover-proxy volumes.
var _ok := true
const BED := ["BunkMattressTop", "BunkBlanketFold", "BunkPillowTop", "BunkPillowBase"]
var main: Node
var player: Node3D
var fb: CharacterBody3D
var carry: Node
var lp: Node3D

func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	player = main.get_node("Player")
	fb = main.get_node("FreeMoveBody")
	carry = player.get_node("CarrySystem")
	lp = player.get_node("LookPivot")
	var fc: Node = main.get_node("FurnitureContact")

	# ---- The contact layer itself. ----
	var mattress: CSGShape3D = main.get_node("Geometry/BunkMattressTop")
	_check("furniture props collide on the dedicated contact layer (mattress)", mattress.use_collision and mattress.collision_layer == fc.FURNITURE_LAYER)
	# Round 31: the player capsule now collides with furniture (mask 1|4);
	# furniture itself still never sits on layer 1 (interaction ray).
	_check("...never on layer 1 (interaction ray unaffected); the player capsule collides with it", mattress.collision_layer & 1 == 0 and (fb.collision_mask & fc.FURNITURE_LAYER) != 0)
	# Round 47: stricter than the old ">= 40" count (the removed sink took
	# 8 props off the list): EVERY listed path resolves to a prop.
	_check("every listed furniture prop resolved (%d of %d)" % [fc.contact_props().size(), fc.furniture_paths.size()], fc.contact_props().size() == fc.furniture_paths.size() and fc.contact_props().size() >= 30)

	# Both parts start stowed behind shut doors (hidden, non-collidable):
	# open their cabinets so they are real loose parts once taken.
	main.get_node("Geometry/StorageCabinet1").interact()
	main.get_node("Geometry/StorageCabinet2").interact()
	await create_timer(0.8).timeout
	# [name, eye, facing, the surface it must land on ("" = any floor)]
	# Round 32: parts are released FROM THE HAND (no relocation). Looking at
	# a reachable near-level surface, the arm places the part there first.
	# [name, eye (capsule clear of the furniture), aim point, intended surfaces]
	var scen := [
		["bed (mattress, leaning in)", Vector3(4.17, 1.6, -0.45), Vector3(4.7, 0.54, -0.45), BED],
		["bed (blanket at the foot)", Vector3(5.0, 1.6, 0.76), Vector3(5.0, 0.6, 0.28), BED],
		["desk", Vector3(3.3, 1.6, 1.57), Vector3(3.3, 0.79, 2.08), ["DeskSurfaceSlab", "DeskNotebook"]],
		# Round 47: the wash counter in front of the mirror was removed (redundant sink).
		["console desk", Vector3(-0.5, 1.6, -0.25), Vector3(-0.5, 0.78, -0.78), ["ConsoleDesk"]],
		["counter edge (aim past it: plain release)", Vector3(1.95, 1.6, 1.5), Vector3(1.95, 1.4, 3.0), []],
		["near the locker wall", Vector3(4.3, 1.6, 1.7), Vector3(5.5, 1.4, 1.7), []],
		["waste hatch", Vector3(-6.2, 1.6, 7.55), Vector3(-6.2, 1.2, 6.5), []],
		["storage corner", Vector3(-7.0, 1.6, 7.3), Vector3(-7.6, 1.4, 6.9), []],
		["open floor", Vector3(3.2, 1.6, 0.4), Vector3(3.2, 0.0, -0.3), []],
	]
	# Shut both cabinet doors for the drop scenarios: open (outward-swinging)
	# doors catch the look ray -- Space would then rightly STOW the part, and
	# a door can hide a dropped part from view.
	main.get_node("Geometry/StorageCabinet1").interact()
	main.get_node("Geometry/StorageCabinet2").interact()
	await create_timer(0.8).timeout
	for item_name in ["FilterCartridge", "WireComponent"]:
		var item: Node3D = main.get_node("Interactables/" + item_name)
		for sc in scen:
			await _face_from(sc[1], Vector3(0, 0, -1))
			_aim_at(sc[2])
			for i in 15: await physics_frame
			if carry.is_carrying(): carry.drop()
			item.interact()
			await create_timer(1.2).timeout   # reach + grasp
			carry._attempt_drop_at_feet()
			var tag: String = "%s -> %s" % [item_name, sc[0]]
			if carry.is_carrying() and not carry.is_placing():
				# A refusal is legitimate when the hand pose is inside the
				# furniture (feedback shown, the part stays in the hand).
				_check("%s: drop accepted, or refused with the part kept in hand" % tag, carry.is_holding(item) and sc[0].find("edge") != -1)
				carry.drop()
				continue
			_check("%s: released (placed or let go), settling under physics" % tag, carry.is_settling(item) or carry.is_placing())
			# Round 31: a real physics fall + settle (set out, drop, come to rest).
			var tw0 := Time.get_ticks_msec()
			await process_frame
			while (carry.is_placing() or carry.is_settling(item)) and Time.get_ticks_msec() - tw0 < 4000:
				await process_frame
			# Layer 1 again -- or pickable-only (16) while it rests touching the
			# player's capsule (it must never push the player).
			_check("%s: landed, collidable again" % tag, not carry.is_settling(item) and ((item as CollisionObject3D).collision_layer == 1 or (item as CollisionObject3D).collision_layer == 16))
			var r: Dictionary = _validate(item)
			_check("%s: rests ON '%s' (gap %.4f m), near-level" % [tag, r["surface"], r["gap"]], r["gap"] >= -0.006 and r["gap"] < 0.03 and r["level"])
			_check("%s: no interpenetration with any prop %s" % [tag, str(r["overlaps"])], r["overlaps"].is_empty())
			if not (sc[3] as Array).is_empty():
				_check("%s: on the intended furniture (%s)" % [tag, r["surface"]], (sc[3] as Array).has(r["surface"]))
			var vis: Array = _visual_penetrations(item, fc)
			_check("%s: visible geometry never penetrates furniture %s" % [tag, str(vis)], vis.is_empty())
			# Pick it back up after it settled. A part at the very feet needs a
			# steeper look than the pitch clamp allows -- step back first, as a
			# player would.
			var away: Vector3 = player.global_position - item.global_position
			away.y = 0.0
			if away.length() < 0.6:
				var back: Vector3 = item.global_position + (away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)) * 0.75
				fb.sync_to_eye_position(Vector3(back.x, 1.6, back.z))
				for i in 10: await physics_frame
			_aim_at(item.global_position)
			for i in 6: await process_frame
			var hov: Object = player.get_node("LookPivot/PitchPivot/Camera3D/InteractionRay").get_hovered() if player.has_node("LookPivot/PitchPivot/Camera3D/InteractionRay") else carry._interaction_controller.get_hovered()
			_check("%s: the settled part can be targeted again (hovered %s)" % [tag, str(hov.name) if hov != null else "nothing"], hov == item)
			item.interact()
			await create_timer(0.7).timeout  # Round 31: the hand owns the part only at the grasp
			await process_frame
			_check("%s: ...and picked back up" % tag, carry.is_carrying() and carry.carried_item_id() == item.item_id)
			carry.drop()
			await process_frame

	# Round 47: two items per scenario (the removed wash counter took one).
	_check("every drop came to rest under physics (%d rests)" % carry.physics_rests, carry.physics_rests >= 2 * scen.size())

	main.get_node("Geometry/StorageCabinet1").interact()
	main.get_node("Geometry/StorageCabinet2").interact()
	await create_timer(0.8).timeout
	# ---- Storage logic: Space facing the part's own OPEN cabinet stows it. ----
	var wire: Node3D = main.get_node("Interactables/WireComponent")
	var cab1: Node = main.get_node("Geometry/StorageCabinet1")
	await _face_from(Vector3(-6.95, 1.6, 7.75), Vector3(-1, 0, 0))
	var slot: Vector3 = cab1._rest_positions[wire]
	wire.interact()
	await create_timer(1.2).timeout
	_aim_at(slot)
	for i in 6: await process_frame
	var hv: Object = carry._interaction_controller.get_hovered()
	_check("stow: facing the open cabinet that owns the part offers Stow (hovered %s)" % (str(hv.get_path()) if hv is Node else "nothing"), carry.stow_target() == cab1)
	carry._attempt_drop_at_feet()
	await process_frame
	await process_frame
	_check("stow: the wire is back on its shelf slot (stock restored, %d)" % cab1.stock_count(wire.item_id), not carry.is_carrying() and cab1.stock_count(wire.item_id) == 4)
	var filt: Node3D = main.get_node("Interactables/FilterCartridge")
	await _face_from(Vector3(-6.95, 1.6, 7.75), Vector3(0, 0, -1))
	filt.interact()
	await create_timer(1.2).timeout
	_aim_at(slot)
	for i in 6: await process_frame
	_check("stow: a part never stows into a cabinet it does not belong to", carry.stow_target() == null)
	carry.drop()

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _face_from(eye: Vector3, facing: Vector3) -> void:
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	var f: Vector3 = facing.normalized()
	lp.rotation.y = atan2(-f.x, -f.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	lp._target_pitch = 0.0
	lp.get_node("PitchPivot").rotation.x = 0.0
	for i in 6: await physics_frame


func _aim_at(p: Vector3) -> void:
	var cam: Node3D = lp.get_node("PitchPivot/Camera3D")
	var d: Vector3 = p - cam.global_position
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	lp._target_pitch = pitch
	lp.get_node("PitchPivot").rotation.x = pitch


func _validate(item: Node3D) -> Dictionary:
	# World-space box of the visible part (it may come to rest tilted).
	var wb: AABB = _world_box(item)
	var ss: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var ex: Array[RID] = carry._exclusions(item)
	var box := BoxShape3D.new()
	var ext: AABB = carry.item_local_extent(item)
	box.size = ext.size - Vector3(0.008, 0.008, 0.008)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 1 | 4
	q.exclude = ex
	q.transform = Transform3D(item.global_basis.orthonormalized(), item.global_position + item.global_basis.orthonormalized() * ext.get_center() + Vector3(0, 0.004, 0))
	var names: Array = []
	for h in ss.intersect_shape(q, 4):
		names.append(str(h["collider"].name))
	var c: Vector3 = wb.get_center()
	var dn: Dictionary = ss.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(c.x, wb.position.y + 0.03, c.z), Vector3(c.x, wb.position.y - 0.12, c.z), 1 | 4, ex))
	if dn.is_empty():
		return {"surface": "NONE", "gap": 99.0, "level": false, "overlaps": names}
	return {"surface": str(dn["collider"].name), "gap": wb.position.y - (dn["position"] as Vector3).y, "level": (dn["normal"] as Vector3).y > 0.85, "overlaps": names}


func _world_box(item: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for v in item.find_children("*", "VisualInstance3D", true, false):
		if v is Label3D:
			continue
		var b: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Physics-independent: the item's visible box vs every listed furniture
## prop's visible box (CSG boxes, exact), both shrunk a few mm so touching
## faces (resting ON a surface) do not count.
func _visual_penetrations(item: Node3D, fc: Node) -> Array:
	var ext: AABB = carry.item_local_extent(item)
	var ib: AABB = Transform3D(item.global_basis.orthonormalized(), item.global_position) * ext
	ib = ib.grow(-0.003)
	var out: Array = []
	for p in fc.furniture_paths:
		var c: Node = main.get_node_or_null(p)
		if c is CSGBox3D:
			var cb: AABB = ((c as CSGBox3D).global_transform * (c as CSGBox3D).get_aabb()).grow(-0.003)
			if cb.intersects(ib):
				out.append(str(c.name))
	return out


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
