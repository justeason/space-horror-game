extends Label3D
## Round 46: a calibration instrument's own STATUS PLATE -- always the TRUE
## state from DayPlan ("CALIBRATED" green / "CAL DUE" amber). It is what the
## technician compares against when the workstation says otherwise (the
## task-linked wrong-reading anomaly only ever changes the workstation's
## presentation, never this plate or the task).

var task_id: StringName = &"l07"
var _dp: Node


static func attach(host: Node3D, task: StringName, dp: Node, pos: Vector3) -> Label3D:
	var p: Label3D = load("res://scripts/interactables/cal_status_plate.gd").new()
	p.name = "CalStatusPlate"
	p.task_id = task
	p._dp = dp
	p.position = pos
	p.font_size = 30
	p.pixel_size = 0.0011
	p.outline_size = 6
	p.outline_modulate = Color(0, 0, 0, 0.9)
	host.add_child(p)
	return p


func is_calibrated() -> bool:
	return _dp != null and _dp.is_task_done(task_id)


var _was: int = -1


func _process(_d: float) -> void:
	var ok: bool = is_calibrated()
	# Round 46: a REAL completion is confirmed by the instrument itself.
	if _was == 0 and ok and is_inside_tree():
		var snd: Node = get_tree().get_first_node_in_group(&"station_sounds")
		if snd != null and snd.has_method("play_at"):
			snd.play_at(&"cal_confirm", global_position, true)
	_was = 1 if ok else 0
	text = "CALIBRATED ✓" if ok else "CAL DUE"
	modulate = Color(0.45, 1.0, 0.55) if ok else Color(1.0, 0.75, 0.25)
