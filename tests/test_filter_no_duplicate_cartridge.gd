extends SceneTree
## Round 23 Priority 2 regression coverage: player feedback was "when I
## replace the cartridge, I am holding the old cartridge, but another
## cartridge is floating in front of the filter station." Root cause:
## filter_housing_diorama.gd's sync_full_state() unconditionally set
## _new_cartridge.visible = true (and _old_cartridge per-stage) on BOTH
## diorama instances -- the focused procedure view's own diorama (where
## those props are the real interactive target) AND the small
## world_display_mode=true twin that sits permanently in the actual 3D
## world right next to the REAL, full-scale, carryable FilterCartridge/
## UsedFilterCartridge objects. The world twin's own decorative
## cartridge meshes were never meant to double as a second "cartridge"
## -- the real pickups already represent that physically. This asserts
## the world twin's cartridge props stay hidden through every stage of
## a real procedure, while the actual carryable objects behave
## correctly (visible when not carried, hidden while held is NOT the
## contract here -- see carry_system.gd's pick_up(), which never hides
## a carried item; only storage_cabinet.gd's own door-gating does).
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame

	var station := main.get_node("Interactables/FilterHousingStation")
	var world_diorama: Node3D = station.get_node("WorldDiorama")
	var world_old_cartridge: Node3D = world_diorama.get_node("OldCartridge")
	var world_new_cartridge: Node3D = world_diorama.get_node("NewCartridge")
	var cartridge: Node3D = main.get_node("Interactables/FilterCartridge")
	var used: Node3D = main.get_node("Interactables/UsedFilterCartridge")
	var cabinet2 := main.get_node("Geometry/StorageCabinet2")
	var carry := main.get_node("Player/CarrySystem")

	_check("world diorama's own new-cartridge prop starts hidden (not a visible duplicate before any work is done)", not world_new_cartridge.visible)
	_check("world diorama's own old-cartridge prop starts hidden too", not world_old_cartridge.visible)

	cabinet2.interact()
	await create_timer(0.7).timeout
	_check("real filter cartridge becomes visible once its storage cabinet is open", cartridge.visible)

	cartridge.interact()
	_check("real filter cartridge picked up (carried, not hidden)", carry.is_carrying() and carry.carried_item_id() == &"filter_cartridge")
	_check("carried cartridge stays visible while held (carry_system.gd never hides held items)", cartridge.visible)
	_check("world diorama's new-cartridge prop still hidden while carrying the real one", not world_new_cartridge.visible)

	station.toggle_isolate()
	station.toggle_latch(1)
	station.toggle_latch(2)
	station.remove_old_cartridge()
	_check("used cartridge actually ejected into the world", used.is_ejected())
	_check("used cartridge is visible once ejected", used.visible)
	_check("world diorama's old-cartridge prop stays hidden even once the real old cartridge is ejected (no duplicate)", not world_old_cartridge.visible)
	_check("world diorama's new-cartridge prop still hidden mid-procedure", not world_new_cartridge.visible)

	for i in 3:
		station.rotate_cartridge(1)
	var result: Dictionary = station.attempt_insert()
	_check("insert succeeds at the correct rotation", result.get("seated", false))
	_check("the real cartridge is consumed from the player's hands on successful install (not left floating in carry)", not carry.is_carrying())
	_check("the real cartridge is reparented onto the station and stays visible (the ONE physical representation of 'installed')", cartridge.visible)
	_check("world diorama's new-cartridge prop STILL hidden after a real, successful install -- this is the exact bug: it used to stay visible here, reading as a second floating cartridge", not world_new_cartridge.visible)

	station.toggle_latch(1)
	station.toggle_latch(2)
	station.toggle_isolate()
	_check("procedure completes", station.is_complete())
	_check("world diorama's cartridge props remain hidden after completion", not world_new_cartridge.visible and not world_old_cartridge.visible)

	# The player can still pick up the real ejected used cartridge and
	# carry it away -- the two real objects (installed new, carried
	# old) are genuinely independent, distinct physical things, never a
	# single confused duplicate.
	used.interact()
	_check("used cartridge can be picked up and carried away", carry.is_carrying() and carry.carried_item_id() == &"used_filter_cartridge")
	_check("picking up the used cartridge did not affect the already-installed new one", cartridge.visible and cartridge.get("_installed"))

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
