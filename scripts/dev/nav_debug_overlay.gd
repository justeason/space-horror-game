extends Node3D
## Development-only navigation diagnostic overlay. Draws, for every
## MovementNode under `movement_nodes_path`:
##   - a small ring at the node's position, sized to the player's
##     documented clearance radius (movement_controller.gd's
##     player_clearance_radius)
##   - a line to every one of its get_movement_candidates(), colored
##     green if a capsule of that same radius/height can sweep the full
##     edge without a collision, red if it cannot (using the exact same
##     PhysicsDirectSpaceState3D.cast_motion() check as the navigation
##     test suite, not a point/line approximation)
##   - the node's node_id as floating text
##
## Entirely inert unless explicitly turned on: `enabled` defaults to
## false, and nothing here runs, draws, or allocates anything when it is
## false. Toggle at runtime with F3 (only while `enabled` is true; this
## does not add or require any project-wide input action).
##
## Purely a read-only inspection tool: it never edits MovementNode data,
## never touches player state, and has zero effect on movement behavior.
##
## Round 12 Workstream C: also owns the big yellow room/tunnel-name
## dev labels (`DevLabels` in main.tscn, each a dev_label.tscn
## instance -- a plain always-on, no_depth_test, billboarded Label3D
## with no visibility gating of its own) -- these used to render
## permanently over normal gameplay (confirmed via an actual rendered
## screenshot, not merely inferred from code: overlapping "CORRIDOR" /
## "MAIN JUNCTION" / "AIRLOCK" text filled a third of the frame).
## `room_labels_path` is optional (get_node_or_null) so this script
## still works in any scene that doesn't have a DevLabels node. Their
## visibility now follows the EXACT same enabled/F3 state as the nav
## ring/edge overlay -- one toggle, not two -- so station-topology
## diagnosis (which room is which) and clearance diagnosis (which
## edges are safe) turn on and off together.

@export var enabled: bool = false
@export var movement_nodes_path: NodePath = ^"../MovementNodes"
@export var player_path: NodePath = ^"../Player"
@export var room_labels_path: NodePath = ^"../DevLabels"
@export var ring_segments: int = 16
@export var safe_color: Color = Color(0.2, 1.0, 0.3, 0.9)
@export var unsafe_color: Color = Color(1.0, 0.15, 0.15, 0.95)
@export var ring_color: Color = Color(0.3, 0.8, 1.0, 0.8)

var _visible: bool = true
var _mesh_instance: MeshInstance3D
var _labels: Array[Label3D] = []
@onready var _room_labels: Node = get_node_or_null(room_labels_path)


func _ready() -> void:
	if _room_labels != null:
		_room_labels.visible = enabled
	if not enabled:
		return
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_visible = not _visible
		if _mesh_instance:
			_mesh_instance.visible = _visible
		for l in _labels:
			l.visible = _visible
		if _room_labels != null:
			_room_labels.visible = _visible


func _build() -> void:
	var mn := get_node_or_null(movement_nodes_path)
	var player := get_node_or_null(player_path)
	if mn == null or player == null:
		push_warning("nav_debug_overlay: MovementNodes or Player not found, skipping.")
		return

	var radius: float = player.player_clearance_radius if "player_clearance_radius" in player else 0.3
	var height: float = player.player_clearance_height if "player_clearance_height" in player else 1.0

	var space_state := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height

	var mesh := ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _unshaded_vertex_color_material()
	add_child(_mesh_instance)

	var nodes := mn.get_children().filter(func(c): return c.has_method("get_movement_candidates"))
	var checked := {}

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for node in nodes:
		_draw_ring(mesh, node.global_position, radius, ring_color)
		for candidate in node.get_movement_candidates():
			var key := _pair_key(node, candidate)
			if checked.has(key):
				continue
			checked[key] = true
			var safe := _is_edge_safe(space_state, shape, node.global_position, candidate.global_position)
			_draw_line(mesh, node.global_position, candidate.global_position, safe_color if safe else unsafe_color)
	mesh.surface_end()

	for node in nodes:
		var label := Label3D.new()
		label.text = node.node_id if String(node.node_id) != "" else node.name
		label.font_size = 24
		label.outline_size = 6
		label.modulate = Color(1, 1, 1, 0.9)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = node.global_position + Vector3(0, 0.35, 0)
		add_child(label)
		_labels.append(label)

	print("nav_debug_overlay: built %d node markers, %d distinct edges (radius=%.2f height=%.2f). Press F3 to toggle." % [nodes.size(), checked.size(), radius, height])


func _is_edge_safe(space_state: PhysicsDirectSpaceState3D, shape: CapsuleShape3D, from_pos: Vector3, to_pos: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collide_with_bodies = true
	params.margin = 0.001
	params.transform = Transform3D(Basis(), from_pos)

	if space_state.intersect_shape(params, 1).size() > 0:
		return false

	params.motion = to_pos - from_pos
	var result: PackedFloat32Array = space_state.cast_motion(params)
	return result[0] >= 0.999


func _draw_ring(mesh: ImmediateMesh, center: Vector3, radius: float, color: Color) -> void:
	for i in ring_segments:
		var a0 := TAU * float(i) / float(ring_segments)
		var a1 := TAU * float(i + 1) / float(ring_segments)
		var p0 := center + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := center + Vector3(cos(a1), 0, sin(a1)) * radius
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(p0)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(p1)


func _draw_line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a + Vector3(0, 0.02, 0))
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b + Vector3(0, 0.02, 0))


func _pair_key(a: Node, b: Node) -> String:
	var ia := a.get_instance_id()
	var ib := b.get_instance_id()
	return "%d|%d" % [min(ia, ib), max(ia, ib)]


func _unshaded_vertex_color_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat
