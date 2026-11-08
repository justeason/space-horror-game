extends SceneTree
## Round 33 Priority 5: the PARTS CARRIER. A shipment is packed into the
## docked carrier; after the restraint is released the whole delivery is
## carried to Storage as ONE item; Space at the open reserve crate unloads
## every part that fits (stock rises exactly then); the empty carrier is
## docked back for the next shipment. Parts in transit are counted (cargo
## needs, audits) and never duplicated; save/load keeps a loaded carrier.
var _ok := true
const PATH := "user://test_r33_carrier.json"
var main: Node
var carry: Node
var fb: Node
var lp: Node3D
var player: Node3D

func _init() -> void:
	main = await _fresh()
	var dp: Node = main.get_node("DayPlan")
	var port: Node = main.get_node("Interactables/CargoPort")
	var crate: Node = main.get_node("Interactables/SupplyCrate")
	var car: Node = port.carrier
	_check("the parts carrier starts docked in the cargo port", car != null and car.is_docked() and car.part_count() == 0)
	dp.reset_for_new_day()
	dp.mark_done(&"l02")
	dp.reset_for_new_day()   # day 3: shipment
	_check("the shipment is packed into the docked carrier (%d parts)" % car.part_count(), car.part_count() == 3 and port.parts_in_port() == 3)
	_check("packed parts are secured (hidden, not clickable) before the restraint is released", car.parts().all(func(p): return not p.visible and p.get_node("Collision").disabled))
	car.interact()
	_check("the carrier cannot be lifted out before the restraint is released", not carry.is_carrying())
	port.interact(); port.interact()
	await create_timer(1.7).timeout
	port.interact()
	_check("after release, single parts are clickable in the docked carrier", car.parts().all(func(p): return p.visible and not p.get_node("Collision").disabled))
	var needs_before: Dictionary = dp.cargo_needs()
	var res_f: int = crate.reserve_count(&"filter_cartridge")
	carry.pick_up(car)
	if carry.is_reaching():
		carry.complete_grasp()
	_check("the whole delivery lifts out as ONE carried item", carry.is_holding(car) and car.part_count() == 3 and not car.is_docked())
	_check("parts ride along (not individually clickable in the hand)", car.parts().all(func(p): return p.get_node("Collision").disabled))
	await process_frame
	await process_frame
	_check("the port sees its compartment empty", port.state == port.PortState.EMPTY)
	_check("in-transit parts still count: cargo needs unchanged %s" % str(dp.cargo_needs()), JSON.stringify(dp.cargo_needs()) == JSON.stringify(needs_before))
	_check("no stock change while in transit", crate.reserve_count(&"filter_cartridge") == res_f)

	# ---- Real Space press at the open reserve crate. ----
	crate.interact()
	await create_timer(0.8).timeout
	_face(crate.global_position + Vector3(0.75, 1.35, 0.0), crate.global_position + Vector3(0.18, 0.05, 0))
	for i in 8: await physics_frame
	_check("facing the open crate with the carrier offers Stow/unload (target %s)" % str(carry.stow_target()), carry.stow_target() == crate)
	carry._attempt_drop_at_feet()
	_check("Space unloads every fitting part into real reserve slots (filters %d -> %d)" % [res_f, crate.reserve_count(&"filter_cartridge")], crate.reserve_count(&"filter_cartridge") == res_f + 2 and car.part_count() == 0)
	_check("...and the carrier stays in the hand", carry.is_holding(car))
	_check("an empty carrier is no longer an unload target", not crate.accepts_item(car))
	port.interact()
	_check("receipt confirmed once", port.state == port.PortState.RECEIVED and port.received_shipments.size() == 1)
	# ---- Dock it back. ----
	_check("the open port accepts the carrier back", port.accepts_item(car))
	carry._carried_item = null; carry._carried_item_id = &""; carry._release_physics(car)
	port.stow(car)
	_check("carrier docked again", car.is_docked())
	port.interact()
	await create_timer(1.3).timeout
	_check("port secured", port.state == port.PortState.SECURED)
	# Real work consumes stock (a filter installed elsewhere) -> a real shortfall.
	main.get_node("Interactables/FilterCartridge").queue_free()
	await process_frame
	for d in 4:
		dp.reset_for_new_day()
		if port.state == port.PortState.ARRIVED:
			break
	_check("the next shipment (day %d) arrives in the carrier again (%d parts)" % [dp.day_number, car.part_count()], port.state == port.PortState.ARRIVED and car.part_count() == port.parts_in_port() and car.part_count() > 0)

	# ---- Save/load with a loaded carrier in the hand. ----
	port.interact(); port.interact()
	await create_timer(1.7).timeout
	port.interact()
	carry.pick_up(car)
	if carry.is_reaching():
		carry.complete_grasp()
	var n_in: int = car.part_count()
	var names: Array = car.parts().map(func(p): return String(p.name))
	var sg: Node = main.get_node("SaveGame")
	var sr: Dictionary = sg.save_game()
	_check("save with a loaded carrier in hand ('%s')" % sr["message"], sr["ok"])
	main.queue_free()
	await process_frame
	main = await _fresh()
	sg = main.get_node("SaveGame")
	var ar: Dictionary = sg.apply_state(sg.read_save()["data"])
	await process_frame
	var car2: Node = main.get_node("Interactables/CargoPort").carrier
	_check("load ok ('%s')" % ar["message"], ar["ok"])
	_check("the carrier is back in the hand with the same %d parts" % n_in, carry.is_holding(car2) and car2.part_count() == n_in and car2.parts().all(func(p): return names.has(String(p.name))))
	var seen := {}
	var dup := false
	for it in sg._all_items():
		if seen.has(String(it.name)): dup = true
		seen[String(it.name)] = true
	_check("no part duplicated by the round trip", not dup)
	for p in [PATH, PATH + ".bak", PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _fresh() -> Node:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	m.get_node("SaveGame").save_path = PATH
	get_root().add_child(m)
	current_scene = m
	for i in 6: await process_frame
	carry = m.get_node("Player/CarrySystem")
	fb = m.get_node("FreeMoveBody")
	player = m.get_node("Player")
	lp = player.get_node("LookPivot")
	return m


func _face(eye: Vector3, look: Vector3) -> void:
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	var d: Vector3 = look - eye
	lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
	lp._target_pitch = pitch
	lp.get_node("PitchPivot").rotation.x = pitch


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
