extends Node
## Round 42 Priority 19: SHARP focused-equipment views on high-DPI /
## fullscreen windows.
##
## ROOT CAUSE (electrical repair "looks low-resolution"): the project
## stretches the UI with display/window/stretch/mode = "canvas_items" (base
## 1152 x 648). A SubViewportContainer with stretch = true sizes its 3D
## SubViewport in CANVAS units, so on a 2304-wide (fullscreen / Retina)
## window the diorama rendered at half the pixels it covers and was
## magnified -- stair-stepped wires, soft terminals and Label3D text. The
## 2D HUD text was sharp because canvas text is rasterised at final scale.
## (A first attempt that only enlarged the SubViewport failed: the
## stretching container resets its viewport to its own canvas size.)
##
## FIX (node paths, layout and the procedure logic unchanged): when the
## canvas -> screen scale k > 1, this driver
##   - puts a PLACEHOLDER Control into the container's slot in the VBox
##     (same minimum size / flags), so the layout is identical;
##   - sets the container TOP-LEVEL (containers skip top-level children),
##     stretch off, sized k x the slot, scaled by 1/k and positioned on the
##     slot -- so it covers exactly the same screen rect;
##   - sizes the SubViewport k x the slot: the 3D view renders 1:1 with
##     screen pixels.
## Mouse input needs no remapping: the container's own (scaled) transform
## converts screen positions straight into SubViewport pixels. At k = 1
## (headless tests, a window at the base size) nothing is touched.

const MAX_SCALE := 3.0
var container: SubViewportContainer
var _slot: Control
var scale_k: float = 1.0
var active: bool = false


## Adds a driver to `view` if it has the standard Panel/VBox/DioramaContainer.
static func attach(view: Node) -> Node:
	var c: SubViewportContainer = view.get_node_or_null("Panel/VBox/DioramaContainer") as SubViewportContainer
	if c == null:
		return null
	var d: Node = load("res://scripts/ui/hidpi_viewport.gd").new()
	d.name = "HiDpiDriver"
	d.container = c
	view.add_child(d)
	return d


func _viewport() -> SubViewport:
	for ch in container.get_children():
		if ch is SubViewport:
			return ch
	return null


func screen_scale() -> float:
	var ref: CanvasItem = _slot if _slot != null else container
	var k: float = ref.get_viewport().get_final_transform().get_scale().x * (ref.get_global_transform_with_canvas().get_scale().x if ref != container else 1.0)
	return clampf(k, 1.0, MAX_SCALE)


func _process(_d: float) -> void:
	if container == null:
		return
	var vis: bool = container.get_parent() is CanvasItem and (container.get_parent() as CanvasItem).is_visible_in_tree()
	if not vis:
		return
	scale_k = screen_scale()
	if scale_k <= 1.01:
		if active:
			_deactivate()
		return
	if not active:
		_activate()
	var vp: SubViewport = _viewport()
	if vp == null or _slot.size.x < 2.0:
		return
	container.global_position = _slot.global_position
	container.scale = Vector2.ONE / scale_k
	var px := Vector2i(roundi(_slot.size.x * scale_k), roundi(_slot.size.y * scale_k))
	if container.size != Vector2(px):
		container.size = Vector2(px)
	if vp.size != px:
		vp.size = px


func _activate() -> void:
	var parent: Node = container.get_parent()
	_slot = Control.new()
	_slot.name = "DioramaSlot"
	_slot.custom_minimum_size = container.custom_minimum_size
	_slot.size_flags_horizontal = container.size_flags_horizontal
	_slot.size_flags_vertical = container.size_flags_vertical
	_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_slot)
	parent.move_child(_slot, container.get_index())
	container.stretch = false
	container.top_level = true
	active = true


func _deactivate() -> void:
	container.top_level = false
	container.scale = Vector2.ONE
	container.stretch = true
	if _slot != null:
		_slot.queue_free()
		_slot = null
	active = false
