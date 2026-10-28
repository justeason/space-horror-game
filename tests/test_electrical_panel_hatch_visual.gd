extends SceneTree
## Regression test for the reported "the electrical panel hatch does not
## open when interacted with" bug.
##
## The panel's state machine (electrical_panel.gd) and raycast/click
## routing (interaction_controller.gd) were confirmed correct by direct
## testing -- the actual root cause was that AccessHatchCover (the
## node whose visibility toggles on door-open) sat directly in front of
## DoorPanel, a CSG sibling using the exact same material, whose
## footprint fully contained the hatch's own footprint. Hiding
## AccessHatchCover therefore produced zero visible change: DoorPanel
## filled the gap seamlessly. This can't be caught by calling
## interact() and checking _door_open (that already passed) -- it has
## to check the *visual* geometry/material relationship directly.
##
## This test doesn't render anything (headless rendering is confirmed
## unavailable in this environment); it checks the underlying data that
## determines whether hiding the hatch can possibly be visible: no CSG
## sibling using the hatch's own material may have a local XY footprint
## that fully contains the hatch's footprint.
const GameSettings = preload("res://scripts/station/game_settings.gd")
var _ok := true

func _init() -> void:
	while GameSettings.get_difficulty() != GameSettings.Difficulty.NORMAL: GameSettings.cycle_difficulty() # isolate from any stray persisted difficulty
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 3: await process_frame

	var panel := main.get_node("Geometry/EngineeringCabinet1")
	var hatch: CSGBox3D = panel.get_node("AccessHatchCover")
	var hatch_rect := _footprint(hatch)
	var hatch_material: Material = hatch.material

	var offending: Array[String] = []
	for child in panel.get_children():
		if child == hatch:
			continue
		if not (child is CSGBox3D):
			continue
		if child.material != hatch_material:
			continue
		var rect: Rect2 = _footprint(child)
		if rect.encloses(hatch_rect):
			offending.append(child.name)

	_check(
		"no same-material CSG sibling fully backs AccessHatchCover (would make opening invisible): offending=%s" % [offending],
		offending.is_empty()
	)

	# Also confirm the state machine side still works, so this test
	# would fail loudly if a future edit broke that instead.
	_check("door starts closed", not panel.is_door_open())
	panel.interact()
	_check("door opens after interact()", panel.is_door_open())
	_check("hatch cover hidden while open", not hatch.visible)
	panel.interact()
	_check("door closes again after second interact()", not panel.is_door_open())
	_check("hatch cover visible while closed", hatch.visible)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _footprint(box: CSGBox3D) -> Rect2:
	var half: Vector2 = Vector2(box.size.x, box.size.y) * 0.5
	var center: Vector2 = Vector2(box.position.x, box.position.y)
	return Rect2(center - half, half * 2.0)

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
