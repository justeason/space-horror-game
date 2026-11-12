extends SceneTree
## Round 47 Priority 1: TWO-WAY OBSERVATION WINDOWS and the LIFE SUPPORT
## FLOOR.
##  - the Control Room port is a REAL opening: a bore cut through the west
##    wall (CSG) and through its hull plate, transparent panes (no portal
##    SubViewport, no opaque disc), a collision pane that keeps the hull
##    sealed;
##  - lines of sight exist both ways: Control Room -> courtyard / tunnel
##    port, airlock-tunnel port -> Control Room interior, EVA courtyard ->
##    Control Room and -> tunnel port (only the glass panes in between);
##  - the port glass adds no haze (Fresnel material: transparent head-on);
##  - the painted module belt no longer runs across the port;
##  - eye-only / camera-only story layers keep their rules through the
##    real opening (the player's eyes never render CAMERA_ONLY);
##  - Life Support's deck: the walkway's corridor material, a lamp that
##    reaches it, plating seams, real collision under the walk area.
var _ok := true
var main: Node
var cam: Camera3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 12: await process_frame
	await physics_frame
	await physics_frame
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	_port_structure()
	_sight_lines()
	_glass_and_layers()
	_life_support_floor()
	print("")
	print("ALL TESTS PASSED" if _ok else "SOME TESTS FAILED")
	quit()


func _space() -> PhysicsDirectSpaceState3D:
	return (main as Node3D).get_world_3d().direct_space_state


## Solid things (layer 1) on the segment a -> b, ignoring the given bodies.
func _hits(a: Vector3, b: Vector3, ignore: Array = []) -> Array:
	var out: Array = []
	var ex: Array = []
	for n in ignore:
		if n is CollisionObject3D:
			ex.append((n as CollisionObject3D).get_rid())
	var fb: Node = main.get_node_or_null("FreeMoveBody")
	if fb is CollisionObject3D:
		ex.append((fb as CollisionObject3D).get_rid())
	var from: Vector3 = a
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(from, b)
		q.collision_mask = 1
		q.exclude = ex
		var h: Dictionary = _space().intersect_ray(q)
		if h.is_empty():
			break
		out.append(String((h["collider"] as Node).name))
		ex.append(h["rid"])
		from = (h["position"] as Vector3) + (b - a).normalized() * 0.01
	return out


func _port_structure() -> void:
	var win: Node3D = main.get_node("Interactables/WallWatchWindow")
	var wall: Node = main.get_node("Geometry/ControlRoomWestWall")
	_check("the port's bore is cut through the Control Room west wall (CSG subtraction)", wall.get_node_or_null("ObservationPortBore") != null and (wall.get_node("ObservationPortBore") as CSGShape3D).operation == CSGShape3D.OPERATION_SUBTRACTION)
	_check("...and through its hull plate (exterior side)", main.find_child("ObsPortHullPlate", true, false) != null and main.find_child("ObsPortHullPlate", true, false).get_child_count() >= 1)
	_check("a REAL opening: no portal SubViewport, no opaque override disc showing", win.is_real_opening() and win.find_children("*", "SubViewport", true, false).is_empty())
	_check("unchanged locked design: position, no interact(), the feed-override seam kept", win.global_position.is_equal_approx(Vector3(-1.2, 1.5, 1.4)) and not win.has_method("interact") and win.has_method("set_feed_override"))
	# The seam still works (and is reversible).
	win.set_feed_override(ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8)))
	var shown: bool = not win.is_real_opening()
	win.set_feed_override(null)
	_check("set_feed_override() still overrides the view, and clears", shown and win.is_real_opening())
	# Hull stays sealed: straight out through the port, the first solid thing is the port's pane.
	var h: Array = _hits(Vector3(-0.6, 1.5, 1.4), Vector3(-2.6, 1.5, 1.4))
	_check("hull sealed: a ray out through the port stops at the window's pane (%s)" % str(h), not h.is_empty() and h[0] == "WallWatchWindow")
	# ...and the wall itself is open there: ignoring the pane, nothing else.
	var h2: Array = _hits(Vector3(-0.6, 1.5, 1.4), Vector3(-2.6, 1.5, 1.4), [win])
	_check("the wall is genuinely open at the port (beyond the pane: %s)" % str(h2), h2.is_empty())
	var h3: Array = _hits(Vector3(-0.6, 1.5, 0.6), Vector3(-2.6, 1.5, 0.6))
	_check("...but solid next to it (control: %s)" % str(h3), h3.has("ControlRoomWestWall"))


func _sight_lines() -> void:
	var win: Node = main.get_node("Interactables/WallWatchWindow")
	var tpane: Node = main.find_child("TunnelPortGlass", true, false)
	var panes: Array = [win, tpane]
	var lines := {
		"Control Room -> tunnel port": [Vector3(-0.45, 1.6, 1.13), Vector3(-4.6, 1.55, 2.6)],
		"airlock-tunnel port -> Control Room interior": [Vector3(-4.75, 1.55, 2.55), Vector3(0.3, 1.45, 0.9)],
		"EVA courtyard -> Control Room interior": [Vector3(-2.6, 1.6, 1.0), Vector3(0.2, 1.4, 1.6)],
		"EVA courtyard -> tunnel port interior": [Vector3(-2.6, 1.6, 2.2), Vector3(-4.9, 1.5, 2.5)],
	}
	for k in lines:
		var a: Vector3 = lines[k][0]
		var b: Vector3 = lines[k][1]
		var only_glass: Array = _hits(a, b, panes)
		_check("line of sight %s: nothing solid but glass (%s)" % [k, str(only_glass)], only_glass.is_empty())


func _glass_and_layers() -> void:
	var win: Node3D = main.get_node("Interactables/WallWatchWindow")
	var pane: GeometryInstance3D = win.get_node("Glass")
	var mat: Material = pane.material_override
	_check("cabin pane is the Fresnel port glass (no full-strength specular veil)", mat is ShaderMaterial and float((mat as ShaderMaterial).get_shader_parameter("head_on")) <= 0.01)
	var ext: Node = main.find_child("ObservationPortExterior", true, false)
	var ext_glass_ok := false
	for g in ext.find_children("*", "MeshInstance3D", true, false):
		if (g as MeshInstance3D).mesh is CylinderMesh and (g as MeshInstance3D).material_override is ShaderMaterial:
			ext_glass_ok = true
	_check("outer pane is transparent glass too (was an opaque emissive disc)", ext_glass_ok)
	var tp: Node = main.find_child("TunnelPort", true, false)
	var tglass := false
	for g in tp.find_children("*", "MeshInstance3D", true, false):
		if (g as MeshInstance3D).mesh is QuadMesh and (g as MeshInstance3D).material_override is ShaderMaterial:
			tglass = true
	_check("tunnel port: the same haze-free glass", tglass)
	_check("tunnel port enlarged so a figure's body reads (0.84 x 0.9, sill above the handrail)", load("res://scripts/exterior/exterior_builder.gd").TUNNEL_PORT_SIZE.y >= 0.85)
	# Belt stripe split around the port: no belt box overlaps the port disc.
	var belt_over := false
	for m in main.find_child("HullFinish", true, false).find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.y > 0.08 and (mi.mesh as BoxMesh).size.y < 0.1 and absf(mi.global_position.x + 1.46) < 0.1:
			var sz: Vector3 = (mi.mesh as BoxMesh).size
			if absf(mi.global_position.y - 1.5) < 0.4 and absf(mi.global_position.z - 1.4) < sz.z * 0.5 + 0.3:
				belt_over = true
	_check("the painted module belt no longer runs across the port", not belt_over)
	_check("the player's eyes never render CAMERA_ONLY (rule unchanged through a real opening)", cam.cull_mask & (1 << 18) == 0)
	_check("...and do render the eye-only layer (window figure, hand)", cam.cull_mask & (1 << 19) != 0)


func _life_support_floor() -> void:
	var f: CSGBox3D = main.get_node("Geometry/LifeSupportFloor")
	var walk: CSGBox3D = main.get_node("Geometry/LifeSupportBendFloor")
	_check("Life Support deck uses the walkway's material (same family)", f.material == walk.material)
	var l: OmniLight3D = main.get_node("Lights/Light_LifeSupport")
	var to_deck: float = l.global_position.y - (f.global_position.y + f.size.y * 0.5)
	_check("its lamp reaches the deck (range %.1f m vs %.1f m to the floor)" % [l.omni_range, to_deck], l.omni_range > to_deck * 1.4)
	var decor: Node = main.get_node("StationDecor")
	_check("deck plating seams + L-3 service stripe are laid", bool(decor.ls_deck_finished))
	var all_floor := true
	for p in [Vector3(-2.0, 1.0, 10.0), Vector3(-3.8, 1.0, 11.5), Vector3(-2.9, 1.0, 10.8)]:
		var q := PhysicsRayQueryParameters3D.create(p, p - Vector3(0, 2.0, 0))
		q.collision_mask = 1
		var h: Dictionary = _space().intersect_ray(q)
		all_floor = all_floor and not h.is_empty() and absf((h["position"] as Vector3).y) < 0.02
	_check("real collision under the deck at deck height 0.0 (not a decorative plane)", all_floor)


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
