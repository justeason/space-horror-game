extends "res://scripts/station/equipment_base.gd"
## Round 41 Priority 6: shared plumbing for the three SOLAR maintenance
## tasks (solar_coupler_task.gd, solar_hinge_task.gd, solar_clean_task.gd).
## Each task OWNS its fault (saved, generated once by its work order from
## the order's seed, never re-rolled) and exposes wing_factor(wing) to the
## power model (solar_arrays.gd), so a fault genuinely lowers that wing's
## output and its repair restores it.
## Worksites: each task registers a handhold worksite with eva_system.gd;
## its hardware can only be worked while STABILISED there (and the worksite
## itself needs a tether secured on the listed ring).

const Graph = preload("res://scripts/exterior/eva_anchor_graph.gd")
const EXT := 1 << 11

var wing: String = "L"            # which wing the current fault is on
var request_day: int = -1
var verified_day: int = -1
var _arrays: Node
var _hw: Dictionary = {"L": null, "R": null}   # hardware root per wing


func _solar_ready(order_type: StringName) -> void:
	_base_ready(order_type)
	add_to_group(&"solar_task")
	_arrays = get_node_or_null("../SolarArrays")
	if _arrays != null:
		_arrays.register_task(self)


func _eva() -> Node:
	return get_tree().get_first_node_in_group(&"eva_system") if is_inside_tree() else null


func _today() -> int:
	return int(_dp.day_number) if _dp != null else 1


func outside() -> bool:
	var e: Node = _eva()
	return e != null and e.outside


func suited() -> bool:
	var e: Node = _eva()
	return e != null and e.suited


func at_site(id: String) -> bool:
	var e: Node = _eva()
	return e != null and e.at_worksite(id)


func _ext_layers(n: Node3D) -> void:
	for v in [n] + n.find_children("*", "VisualInstance3D", true, false):
		if v is VisualInstance3D:
			(v as VisualInstance3D).layers = 1 | EXT


## A handhold bar on the truss rail + the worksite registration.
func _worksite(id: String, parent: Node3D, hold_pos: Vector3, stance: Vector3, look: Vector3, ring_id: String, label_text: String) -> void:
	var bar := box(Vector3(0.36, 0.035, 0.035), hold_pos, Color(0.95, 0.75, 0.15), parent)
	bar.name = "Handhold_" + id
	box(Vector3(0.03, 0.08, 0.03), hold_pos + Vector3(-0.16, -0.05, 0), Color(0.5, 0.5, 0.52), parent)
	box(Vector3(0.03, 0.08, 0.03), hold_pos + Vector3(0.16, -0.05, 0), Color(0.5, 0.5, 0.52), parent)
	var e: Node = _eva()
	if e != null:
		e.register_worksite(id, stance, look, valid_rings(ring_id, stance), parent, hold_pos, label_text)


## Round 42 Priority 15: the rings a technician may be tethered to while
## working a worksite are DERIVED from the worksite's real position: the
## task's named ring plus any other ring of the SAME wing / truss side
## within WORK_RING_R of the stance (a 5.5 m tether reaches comfortably).
## Never a ring of the other wing.
const WORK_RING_R := 3.5


static func valid_rings(ring_id: String, stance: Vector3) -> Array:
	var out: Array = [ring_id]
	var side: String = ring_id.left(1)
	for a in Graph.ANCHORS:
		var id: String = a[1]
		if id == ring_id or id.left(1) != side:
			continue
		if (a[0] as Vector3).distance_to(stance) <= WORK_RING_R:
			out.append(id)
	return out


## Which wing's `prefix` worksite the technician is holding ("" = none).
func site_wing_here(prefix: String) -> String:
	for w in ["L", "R"]:
		if at_site(prefix + w):
			return w
	return ""


static func wing_word(w: String) -> String:
	return "LEFT (west)" if w == "L" else "RIGHT (east)"


## A small orange SERVICE tag on the faulted wing's hardware (the correct
## worksite is obvious from the truss); hidden while healthy.
func service_tag(parent: Node3D, pos: Vector3) -> Node3D:
	var t := Node3D.new()
	t.name = "ServiceTag"
	t.position = pos
	parent.add_child(t)
	box(Vector3(0.012, 0.18, 0.012), Vector3(0, 0.09, 0), Color(0.6, 0.6, 0.62), t)
	box(Vector3(0.1, 0.06, 0.006), Vector3(0.05, 0.15, 0), Color(1.0, 0.45, 0.05), t)
	label("SERVICE", Vector3(0.05, 0.15, 0.006), 10, Color(0.1, 0.05, 0.0), t)
	return t


## The common "suit up -> airlock -> route -> work -> back -> verify" next
## step once the outside work is described by `work_step`.
func _route_step(work_step: Dictionary, ring: String) -> Dictionary:
	if outside():
		return work_step
	if not suited():
		return {"action": "Put on the EVA suit (airlock)", "short": "SUIT UP", "room": &"airlock"}
	return {"action": "Airlock: press OUT<<, follow the truss to %s" % ring, "short": "AIRLOCK OUT", "room": &"airlock"}


## Power panel SOLAR check (Engineering): the VERIFY OUTPUT step.
func on_output_checked() -> void:
	if request_day == -1 or verified_day >= request_day or outside():
		return
	if repaired():
		verified_day = _today()
		sfx(&"success")
		say("Solar output restored — wing %s %.1f kW." % [wing, _arrays.wing_output(wing) if _arrays != null else 0.0])


## Subclasses: the fault is gone (outside work finished).
func repaired() -> bool:
	return true


func wing_factor(_w: String) -> float:
	return 1.0


func order_severity() -> int:
	return 2 if _arrays != null and _arrays.reserve_low() else 1


func order_feasible() -> bool:
	return _arrays != null and _eva() != null
