extends SceneTree
## Round 23/24 Priority 2 regression coverage: "a floating decorative
## duplicate cartridge" during the L02 filter swap.
##
## Round 23 hid the world-embedded diorama twin's own cartridge props
## (world_display_mode=true), which was real but NOT the whole story --
## the duplicate kept appearing. Round 24 found the remaining causes:
##  1. filter_housing_station.gd seated the REAL cartridge at a hard-coded
##     Vector3(0, -0.6, 0) under the station -- 0.6m below the anchor, in
##     open air -- and filter_cartridge.gd's mark_installed() left it
##     VISIBLE there. That was the floating cartridge.
##  2. storage_cabinet.gd re-applied its open/closed visibility gating to
##     every listed item on every door swing, wherever the item now was
##     -- so toggling StorageCabinet2 after the swap re-showed an
##     installed (hidden) cartridge, and closing it while carrying the
##     new cartridge hid the one in the player's hand.
##
## This test walks the full physical sequence (open storage -> retrieve
## -> carry -> install -> old comes out -> carry old -> dispose) and at
## EVERY step enumerates every visible cartridge representation in the
## main world (the real new cartridge, the real used cartridge, and the
## world twin's two decorative props), asserting the exact expected set.
var _ok := true
var _main: Node

func _init() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)
	current_scene = _main
	for i in 5: await process_frame

	var station := _main.get_node("Interactables/FilterHousingStation")
	var world_diorama: Node3D = station.get_node("WorldDiorama")
	var housing: Node3D = world_diorama.get_node("Housing")
	var housing_tube: CSGCylinder3D = housing.get_node("Tube")
	var cartridge: Node3D = _main.get_node("Interactables/FilterCartridge")
	var used: Node3D = _main.get_node("Interactables/UsedFilterCartridge")
	var cabinet2 := _main.get_node("Geometry/StorageCabinet2")
	var carry := _main.get_node("Player/CarrySystem")
	var trash := _main.get_node("Interactables/TrashDisposal")
	var carry_anchor: Node = carry.get_node(carry.carry_anchor_path)

	_expect_visible("start: nothing visible (new one behind a closed door, old one inside the housing)", [])

	cabinet2.interact()
	await create_timer(0.7).timeout
	_expect_visible("storage opened: only the new cartridge, on its shelf", ["new"])
	_check("new cartridge is physically inside cabinet2's cavity (between door plane and back wall)", _inside_cabinet(cartridge, cabinet2))

	cartridge.interact()
	_check("new cartridge picked up", carry.is_carrying() and carry.carried_item_id() == &"filter_cartridge")
	_check("carried cartridge is parented to the carry anchor (in hand)", cartridge.get_parent() == carry_anchor)
	_expect_visible("carrying: only the new cartridge, in hand", ["new"])

	# Gating regression: closing the storage cabinet must NOT reach out
	# and hide/disable the cartridge that has already left it.
	cabinet2.interact()
	await create_timer(0.7).timeout
	_check("closing storage while carrying leaves the held cartridge visible", cartridge.visible)
	_check("closing storage while carrying leaves the held cartridge collidable", not cartridge.get_node("Collision").disabled)
	_check("storage stock reads 0 once the part has been taken", cabinet2.stock_count() == 0)

	station.toggle_isolate()
	station.toggle_latch(1)
	station.toggle_latch(2)
	station.remove_old_cartridge()
	_check("used cartridge actually ejected into the world", used.is_ejected())
	_expect_visible("old removed: new in hand + old on the floor, nothing else", ["new", "used"])

	for i in 3:
		station.rotate_cartridge(1)
	var result: Dictionary = station.attempt_insert()
	_check("insert succeeds at the correct rotation", result.get("seated", false))
	_check("the real cartridge left the player's hands on install", not carry.is_carrying())
	_check("installed cartridge is parented to the station", cartridge.get_parent() == station)
	_check("installed cartridge is hidden (enclosed by the housing, like the installed wire)", not cartridge.visible)
	_check("installed cartridge is non-collidable", cartridge.get_node("Collision").disabled)
	var tube_center: Vector3 = housing_tube.global_position
	var tube_radius: float = housing_tube.radius * housing.global_transform.basis.get_scale().x
	_check("installed cartridge sits INSIDE the housing tube (dist %.3f), not floating in open air" % cartridge.global_position.distance_to(tube_center), cartridge.global_position.distance_to(tube_center) < 0.01)
	_check("installed cartridge keeps its real size (scale not inherited from the scaled twin)", cartridge.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE))
	_check("housing tube is physically big enough to contain the real cartridge (tube r=%.3f >= cartridge r=0.074)" % tube_radius, tube_radius >= 0.074)
	_expect_visible("installed: ONLY the ejected old cartridge remains visible", ["used"])

	station.toggle_latch(1)
	station.toggle_latch(2)
	station.toggle_isolate()
	_check("procedure completes", station.is_complete())
	_expect_visible("complete: still only the ejected old cartridge", ["used"])

	# Gating regression: re-opening/closing storage after the install must
	# not resurrect the installed cartridge.
	cabinet2.interact()
	await create_timer(0.7).timeout
	_expect_visible("storage re-opened after install: installed cartridge stays hidden", ["used"])
	cabinet2.interact()
	await create_timer(0.7).timeout
	_check("installed cartridge still hidden after storage re-closed", not cartridge.visible)
	_check("installed cartridge still non-collidable after storage toggles", cartridge.get_node("Collision").disabled)

	used.interact()
	_check("used cartridge picked up", carry.is_carrying() and carry.carried_item_id() == &"used_filter_cartridge")
	_expect_visible("carrying old: only the old cartridge, in hand", ["used"])

	trash.interact()
	_check("used cartridge disposed", not carry.is_carrying() and trash.disposed_count() == 1)
	await process_frame
	_expect_visible("disposed: no cartridge visible anywhere", [])

	# Same gating bug, electrical side: an installed (hidden) wire must not
	# be re-shown by toggling its storage cabinet.
	var wire: Node3D = _main.get_node("Interactables/WireComponent")
	var cabinet1 := _main.get_node("Geometry/StorageCabinet1")
	cabinet1.interact()
	await create_timer(0.7).timeout
	wire.mark_installed(_main.get_node("Interactables"), Transform3D(Basis(), Vector3(0, 5, 0)))
	cabinet1.interact()
	await create_timer(0.7).timeout
	cabinet1.interact()
	await create_timer(0.7).timeout
	_check("installed wire stays hidden through storage toggles", not wire.visible)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


## Every cartridge representation that can exist in the MAIN world.
func _visible_cartridges() -> Array:
	var out: Array = []
	var cart: Node3D = _main.get_node_or_null("Interactables/FilterCartridge")
	if cart == null:
		cart = _find_named(_main, "FilterCartridge")
	if cart != null and cart.is_visible_in_tree():
		out.append("new")
	var used: Node = _find_named(_main, "UsedFilterCartridge")
	if used != null and is_instance_valid(used) and not used.is_queued_for_deletion() and used.is_visible_in_tree():
		out.append("used")
	var wd: Node = _main.get_node("Interactables/FilterHousingStation/WorldDiorama")
	if (wd.get_node("NewCartridge") as Node3D).is_visible_in_tree():
		out.append("twin_new_prop")
	if (wd.get_node("OldCartridge") as Node3D).is_visible_in_tree():
		out.append("twin_old_prop")
	out.sort()
	return out


func _expect_visible(label: String, expected: Array) -> void:
	var e := expected.duplicate()
	e.sort()
	var got := _visible_cartridges()
	_check("%s -> visible=%s" % [label, str(got)], got == e)


func _find_named(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _find_named(c, name)
		if r != null:
			return r
	return null


func _inside_cabinet(item: Node3D, cabinet: Node) -> bool:
	var back: Node3D = cabinet.get_node("Back")
	var hinge: Node3D = cabinet.get_node("DoorHinge")
	var x: float = item.global_position.x
	return x > minf(back.global_position.x, hinge.global_position.x) and x < maxf(back.global_position.x, hinge.global_position.x)


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
