extends StaticBody3D
## Round 33 Priority 4: a physical INSPECTION POINT -- the status tag above
## a maintained system (or a cabinet's stock placard). Looking at it and
## clicking logs a reading into DayPlan's inspection record, which an
## Inspection Round / Comms Check work order requires and the workstation
## cross-checks against the equipment's live condition when filing.
## Layer 16 (pickable-only): clickable, never blocks the player or physics.

var inspect_id: StringName = &""
var title: String = ""
var reader: Callable          # () -> String : the reading actually shown
var available: Callable       # () -> String : "" or why it can't be read now
var day_plan: Node = null


func setup(id: StringName, t: String, size: Vector3, read_fn: Callable, avail_fn: Callable = Callable()) -> void:
	inspect_id = id
	title = t
	reader = read_fn
	available = avail_fn
	collision_layer = 16
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)


func interact() -> void:
	if day_plan == null:
		return
	var why: String = available.call() if available.is_valid() else ""
	var ml: Label = get_tree().current_scene.get_node_or_null("Player/HUD/TaskMessageLabel") if get_tree().current_scene != null else null
	var msg: String
	if why != "":
		msg = why
	else:
		var reading: String = reader.call()
		var owner_before: int = ml.get_meta(&"msg_owner", 0) if ml != null else 0
		var text_before: String = ml.text if ml != null else ""
		msg = day_plan.log_reading(inspect_id, title, reading)
		# Round 34: logging may trigger an automatic cross-check / order
		# completion notification -- that newer, more important message wins.
		if ml != null and (ml.get_meta(&"msg_owner", 0) != owner_before or ml.text != text_before) and ml.get_meta(&"msg_owner", 0) != get_instance_id():
			return
	preload("res://scripts/ui/hud_message.gd").show(ml, get_instance_id(), msg, 3.0)


func get_interact_prompt() -> String:
	if day_plan != null and day_plan.has_reading(inspect_id):
		return "%s — logged (%s)" % [title, day_plan.reading_of(inspect_id)]
	return "Click: Log %s" % title
