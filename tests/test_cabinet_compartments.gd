extends SceneTree
## Round 10 Workstream A regression coverage for the reported "the entire
## cabinet has been lifted off the floor... and looks like a single large
## drawer with most of its body noninteractive" feedback.
##
## Round 9 had fixed an earlier "hatch too low" complaint by moving the
## WHOLE EngineeringCabinet1 root upward as one rigid CSGBox3D, which
## dragged every child (including the floor-contact BaseFrame dressing)
## up with it -- satisfying "hatch at a comfortable height" while
## breaking "housing actually stands on the floor" and leaving one giant
## door-sized panel as the only visually distinct access surface.
##
## This cannot verify the result LOOKS like a believable cabinet (no
## headless rendering in this environment -- see the final report's
## manual playtest checklist), but it can verify the underlying geometry
## facts that a correct redesign requires: the outer housing's own
## bottom face actually touches the floor, the three compartments sit
## at three distinct, reasonably-spaced heights (not all collapsed into
## one band), each has its own non-colliding cover mesh independent of
## the others, and the functional E05 hatch/terminal geometry still
## lines up with itself after the move.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 3: await process_frame

	var panel: CSGBox3D = main.get_node("Geometry/EngineeringCabinet1")
	var floor_node: CSGBox3D = main.get_node("Geometry/EngineeringFloor")
	var ceiling_node: CSGBox3D = main.get_node("Geometry/EngineeringCeiling")

	var floor_top: float = floor_node.position.y + floor_node.size.y * 0.5
	var ceiling_bottom: float = ceiling_node.position.y - ceiling_node.size.y * 0.5
	var housing_bottom: float = panel.position.y - panel.size.y * 0.5
	var housing_top: float = panel.position.y + panel.size.y * 0.5

	# ============================================================
	# 1. The outer housing genuinely rests on the floor -- not merely
	# "somewhere above it," and not clipping through it either.
	# ============================================================
	_check(
		"housing's own bottom face touches the floor (housing_bottom=%.3f floor_top=%.3f)" % [housing_bottom, floor_top],
		is_equal_approx(housing_bottom, floor_top)
	)
	_check(
		"housing top stays clear of the ceiling (housing_top=%.3f ceiling_bottom=%.3f)" % [housing_top, ceiling_bottom],
		housing_top < ceiling_bottom
	)

	# ============================================================
	# 2. Three distinct compartments at three distinct, standing-height-
	# appropriate world heights -- not one collapsed band, and the
	# middle (E05, functional) compartment sits at a comfortable
	# working height a standing player can reach without aiming at the
	# floor or the ceiling.
	# ============================================================
	var upper_cover: CSGBox3D = panel.get_node("UpperCover")
	var hatch: CSGBox3D = panel.get_node("AccessHatchCover")
	var lower_cover: CSGBox3D = panel.get_node("LowerCover")

	var upper_world_y: float = panel.position.y + upper_cover.position.y
	var middle_world_y: float = panel.position.y + hatch.position.y
	var lower_world_y: float = panel.position.y + lower_cover.position.y

	_check(
		"upper compartment sits above the middle (E05) compartment (upper=%.2f middle=%.2f)" % [upper_world_y, middle_world_y],
		upper_world_y > middle_world_y + 0.3
	)
	_check(
		"middle (E05) compartment sits above the lower compartment (middle=%.2f lower=%.2f)" % [middle_world_y, lower_world_y],
		middle_world_y > lower_world_y + 0.3
	)
	_check(
		"middle (E05) compartment sits at a comfortable standing working height (%.2fm)" % middle_world_y,
		middle_world_y > 1.0 and middle_world_y < 1.6
	)

	# ============================================================
	# 3. Each compartment has its own cover mesh, independent of the
	# others (not one shared panel pretending to be three) -- and none
	# of those covers carry their own collider (same convention as the
	# existing hatch-visual regression test: covers are dressing, the
	# panel body itself owns the collision).
	# ============================================================
	var covers: Array[CSGBox3D] = [upper_cover, hatch, lower_cover]
	for cover in covers:
		_check("%s has no collision of its own" % cover.name, not cover.use_collision)
	_check(
		"the three compartment covers are three distinct mesh instances, not one shared node",
		upper_cover != hatch and hatch != lower_cover and upper_cover != lower_cover
	)

	# ============================================================
	# 4. E05's functional geometry still lines up with itself after the
	# move: both terminals and the shared world-diorama equipment twin
	# (Round 13 Workstream B -- replaces the old flat "DamagedWireVisual"
	# placeholder) sit directly behind/at the hatch's own compartment
	# height, not orphaned at the old pre-move height.
	# ============================================================
	var terminal: Node3D = panel.get_node("Terminal")
	var intact_terminal: Node3D = panel.get_node("IntactTerminal")
	var world_diorama: Node3D = panel.get_node("WorldDiorama")
	_check(
		"damaged terminal shares the hatch's compartment height",
		is_equal_approx(terminal.position.y, hatch.position.y)
	)
	_check(
		"intact terminal shares the hatch's compartment height",
		is_equal_approx(intact_terminal.position.y, hatch.position.y)
	)
	_check(
		"world diorama equipment twin sits just behind the hatch's own compartment band",
		absf(world_diorama.position.y - hatch.position.y) < 0.2
	)

	# ============================================================
	# 5. Round 11 Workstream D: the cabinet must be measurably
	# distinguishable from the surrounding wall/environment -- a real
	# luminance/material difference, not merely a subjective "looks
	# fine" claim. Also confirms covers read as a visually distinct
	# "serviced panel" from the outer housing, and the hinge accent
	# trim is a genuinely different color from plain gray hardware.
	# ============================================================
	var wall: CSGBox3D = main.get_node("Geometry/EngineeringNorthWall")
	var housing_mat: StandardMaterial3D = panel.material
	var wall_mat: StandardMaterial3D = wall.material
	var housing_luminance: float = housing_mat.albedo_color.v
	var wall_luminance: float = wall_mat.albedo_color.v
	_check(
		"cabinet housing is measurably different in brightness from the wall (housing=%.2f wall=%.2f)" % [housing_luminance, wall_luminance],
		absf(housing_luminance - wall_luminance) > 0.1
	)

	var cover_mat: StandardMaterial3D = upper_cover.material
	_check(
		"access covers are a visually distinct material from the outer housing (lighter and/or smoother), not identical",
		cover_mat.albedo_color != housing_mat.albedo_color and not is_equal_approx(cover_mat.roughness, housing_mat.roughness)
	)

	var hinge_mat: StandardMaterial3D = panel.get_node("MiddleHingeTop").material
	_check(
		"hinge accent trim is a genuinely different color from the plain gray breaker/hardware material",
		hinge_mat.albedo_color != main.get_node("Geometry/EngineeringCabinet1/UpperSwitch1").material.albedo_color
	)

	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()

func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
