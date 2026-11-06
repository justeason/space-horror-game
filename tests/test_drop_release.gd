extends SceneTree
## Round 32 Priority 1 regression: a dropped part FALLS FROM THE HAND.
##
## ROOT CAUSE (traced per physics tick): Rounds 30-31 moved the released
## part from the hand to a solver-chosen spot ~0.6 m ahead with an 0.18 s
## tween at constant height (measured 0.066 m sideways on the very first
## tick, 0.557 m over 10 ticks) and only then started physics. Now physics
## starts from the hand pose with the player's own velocity plus a gentle
## 0.15 m/s let-go; looking at a reachable surface, the ARM visibly carries
## the part out first (a place gesture, still held), then lets go.
##
## Distinguishes scripted repositioning from legitimate motion: before the
## first contact, horizontal travel must match the release velocity
## (free fall), and the part must start descending on the first tick.
var _ok := true
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
	main.get_node("Geometry/StorageCabinet1").interact()
	main.get_node("Geometry/StorageCabinet2").interact()
	var crate: Node = main.get_node("Interactables/SupplyCrate")
	crate.interact()
	await create_timer(0.9).timeout
	var used: Node3D = main.get_node("Interactables/UsedFilterCartridge")
	used.eject_at(Transform3D(Basis(), Vector3(-6.9, 0.1, 7.1)))
	# [tag, item, where to stand to pick it up]
	var items := [
		["clean filter", main.get_node("Interactables/FilterCartridge"), Vector3(-6.0, 1.6, 8.0)],
		["used filter", used, Vector3(-6.5, 1.6, 7.3)],
		["16GA harness", main.get_node("Interactables/WireComponent2"), Vector3(-6.95, 1.6, 7.75)],
		["reserve-crate filter", crate.get_node("ReserveFilter1"), Vector3(-6.75, 1.6, 8.3)],
	]
	for spec in items:
		var tag: String = spec[0]
		var item: Node3D = spec[1]
		# Pick up from wherever it is, then walk to open floor, look level.
		fb.sync_to_eye_position(spec[2])
		for i in 10: await physics_frame
		item.interact()
		await create_timer(1.3).timeout
		_check("%s: carried" % tag, carry.is_holding(item))
		fb.sync_to_eye_position(Vector3(-6.4, 1.6, 7.6))
		lp.rotation.y = -player.rotation.y
		lp._target_yaw = lp.rotation.y
		lp._target_pitch = 0.0
		lp.get_node("PitchPivot").rotation.x = 0.0
		for i in 25: await physics_frame
		var held: Vector3 = item.global_position
		var p0: Vector3 = fb.global_position
		var refused0: int = carry.refused_releases
		carry._attempt_drop_at_feet()
		_check("%s: an unobstructed release is never refused" % tag, carry.refused_releases == refused0)
		var rel: Vector3 = item.global_position
		_check("%s: released where the hand is (release frame moved %.4f m)" % [tag, rel.distance_to(held)], rel.distance_to(held) < 0.002)
		var max_lat_free := 0.0
		var first_dy := 0.0
		var prev: Vector3 = rel
		for t in 12:
			await physics_frame
			var p: Vector3 = item.global_position
			if t == 0:
				first_dy = p.y - rel.y
				_check("%s: no scripted sideways jump on the first tick (%.4f m)" % [tag, Vector2(p.x - rel.x, p.z - rel.z).length()], Vector2(p.x - rel.x, p.z - rel.z).length() < 0.01)
			# While still in free fall (well above the floor), sideways travel
			# can only come from the gentle release velocity.
			if p.y > 0.3:
				max_lat_free = maxf(max_lat_free, Vector2(p.x - rel.x, p.z - rel.z).length() / ((t + 1) / 60.0))
			prev = p
		_check("%s: gravity acts immediately (first tick dy %.4f)" % [tag, first_dy], first_dy < 0.0)
		_check("%s: free-fall sideways speed is just the let-go (%.2f m/s, release 0.15)" % [tag, max_lat_free], max_lat_free < 0.35)
		await create_timer(2.5).timeout
		_check("%s: came to rest on the floor below the hand (%.3f m sideways)" % [tag, Vector2(item.global_position.x - held.x, item.global_position.z - held.z).length()], item.global_position.y < 0.15 and Vector2(item.global_position.x - held.x, item.global_position.z - held.z).length() < 0.25)
		_check("%s: the player was never pushed (%.4f m)" % [tag, fb.global_position.distance_to(p0)], fb.global_position.distance_to(p0) < 0.005)
		_check("%s: exactly one physical item (not carried, in the world)" % tag, not carry.is_carrying() and item.is_inside_tree() and item.get_parent() != player.get_node("PlayerBody/CarryAnchor"))
		# Pick it back up after settling.
		var cam: Node3D = lp.get_node("PitchPivot/Camera3D")
		var d: Vector3 = item.global_position - cam.global_position
		lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
		lp._target_yaw = lp.rotation.y
		var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
		lp._target_pitch = pitch
		lp.get_node("PitchPivot").rotation.x = pitch
		for i in 6: await process_frame
		_check("%s: settled part targetable (hovered %s)" % [tag, str(carry._interaction_controller.get_hovered())], carry._interaction_controller.get_hovered() == item)
		item.interact()
		await create_timer(1.3).timeout
		_check("%s: picked back up" % tag, carry.is_holding(item))
		if tag == "used filter":
			# It has no shelf home and falls where it is let go: put it down
			# out of the test's drop column.
			fb.sync_to_eye_position(Vector3(-7.0, 1.6, 7.2))
			for i in 10: await physics_frame
		carry.drop()
		await create_timer(1.5).timeout

	# ---- Invalid release: hand pose inside solid geometry -> refused. ----
	var filt: Node3D = main.get_node("Interactables/FilterCartridge2")
	fb.sync_to_eye_position(Vector3(-6.0, 1.6, 8.0))
	for i in 10: await physics_frame
	filt.interact()
	await create_timer(1.3).timeout
	var probe: Node3D = Node3D.new()
	main.add_child(probe)
	var wall_box := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(1.2, 1.2, 1.2)
	wcs.shape = wbs
	wall_box.add_child(wcs)
	main.add_child(wall_box)
	wall_box.global_position = filt.global_position
	for i in 3: await physics_frame
	var held2: Vector3 = filt.global_position
	carry._attempt_drop_at_feet()
	await process_frame
	_check("release into solid geometry is refused: still carried, not moved (%.3f m)" % filt.global_position.distance_to(held2), carry.is_holding(filt) and filt.global_position.distance_to(held2) < 0.02)
	wall_box.queue_free()
	probe.queue_free()

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
