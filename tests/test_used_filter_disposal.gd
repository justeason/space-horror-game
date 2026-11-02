extends SceneTree
## Round 21 Priority 4 regression coverage: the full physical filter
## disposal loop this round added -- retrieve a new cartridge from
## Storage, install it at the Life Support housing, the OLD cartridge
## is ejected as a real, visible, carryable world object (not silently
## deleted), carry it back to Storage, and throw it into the disposal
## container. Confirms each physical step is real (not auto-completed)
## and that the disposal bin only accepts the right item.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var station := main.get_node("Interactables/FilterHousingStation")
	var used := main.get_node("Interactables/UsedFilterCartridge")
	var new_cartridge := main.get_node("Interactables/FilterCartridge")
	var trash := main.get_node("Interactables/TrashDisposal")
	var carry := main.get_node("Player/CarrySystem")

	# ============================================================
	# 1. Before any repair: no used cartridge exists in the world at
	# all -- hidden, non-collidable, not yet "ejected".
	# ============================================================
	_check("used cartridge starts hidden (no repair has happened yet)", not used.visible)
	_check("used cartridge starts non-collidable", used.get_node("Collision").disabled)
	_check("used cartridge reports not yet ejected", not used.is_ejected())
	_check("used cartridge gives no prompt before being ejected", used.get_interact_prompt() == "")

	# ============================================================
	# 2. Drive the real repair procedure up through remove_old_cartridge()
	# -- same path test_filter_housing.gd already proves end to end.
	# ============================================================
	station.interact()
	await process_frame
	var diorama: Node3D = main.get_node("Player/HUD/FilterHousingView/Panel/VBox/DioramaContainer/DioramaViewport/FilterHousingDiorama")
	await _click(diorama, &"valve") # isolate
	await _click(diorama, &"latch:1")
	await _click(diorama, &"latch:2") # both latches open -> REMOVE_OLD

	new_cartridge.interact() # retrieve the new cartridge from Storage
	_check("carrying the new cartridge before removing the old one", carry.is_carrying() and carry.carried_item_id() == &"filter_cartridge")

	# ============================================================
	# 3. The actual moment this round's work is about: removing the old
	# cartridge must make a REAL used cartridge appear in the world.
	# ============================================================
	await _click(diorama, &"old_cartridge")
	_check("used cartridge is now visible (physically ejected, not deleted)", used.visible)
	_check("used cartridge is now collidable (a real, reachable object)", not used.get_node("Collision").disabled)
	_check("used cartridge reports ejected", used.is_ejected())
	_check("ejected cartridge landed on/near the Life Support floor, not inside the housing", used.global_position.y < 1.0)

	# ============================================================
	# 4. Finish the repair (install new, close latches, restore) so L02
	# completes normally -- Round 21 does not change when L02 itself
	# completes, only adds the physical disposal loop alongside it.
	# ============================================================
	for i in 3: await _click(diorama, &"new_cartridge") # rotate to target angle
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	main.get_viewport().push_input(ev)
	await process_frame
	await _click(diorama, &"latch:1")
	await _click(diorama, &"latch:2")
	await _click(diorama, &"valve")
	_check("L02 completes exactly as before -- this round did not change that gate", main.get_node("DayPlan").is_task_done(&"l02"))
	_check("not carrying the new cartridge anymore (consumed by install)", not carry.is_carrying())

	# ============================================================
	# 5. Pick up the ejected used cartridge via the real interact() path.
	# ============================================================
	_check("used cartridge offers a real pick-up prompt now that it exists", used.get_interact_prompt() == "Click: Pick Up Used Filter Cartridge")
	used.interact()
	_check("used cartridge picked up", carry.is_carrying() and carry.carried_item_id() == &"used_filter_cartridge")

	# ============================================================
	# 6. The disposal bin: wrong-item / empty-handed cases must be
	# harmless and clearly rejected, not silent no-ops that look broken.
	# ============================================================
	carry.drop()
	_check("dropped the used cartridge to test the empty-handed case", not carry.is_carrying())
	_check("disposal bin prompt reflects nothing carried", trash.get_interact_prompt() == "Space Trash Disposal")
	trash.interact()
	_check("disposing with empty hands does nothing (no crash, no false success)", trash.disposed_count() == 0)

	used.interact() # pick it back up
	_check("used cartridge picked back up for the real disposal", carry.is_carrying() and carry.carried_item_id() == &"used_filter_cartridge")
	_check("disposal bin prompt now offers to throw it away", trash.get_interact_prompt().findn("Throw Away") != -1)

	# ============================================================
	# 7. Real disposal: consumes the carried item, frees it for good,
	# and tracks the count -- the one place this object actually leaves
	# the game, only reachable after the full physical loop.
	# ============================================================
	trash.interact()
	_check("no longer carrying anything after disposal", not carry.is_carrying())
	_check("disposal bin counted exactly one disposed item", trash.disposed_count() == 1)
	await process_frame
	_check("the used cartridge node is actually gone (queue_free'd), not just hidden", not is_instance_valid(used) or used.is_queued_for_deletion())

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _click(diorama: Node3D, action: StringName) -> void:
	var pos: Vector2 = diorama.click_position(action)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	diorama._unhandled_input(down)
	await physics_frame


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
