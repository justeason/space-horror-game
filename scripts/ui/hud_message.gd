extends RefCounted
## Round 33: shared HUD task-message helper. Shows `text` on the shared
## TaskMessageLabel, stamps the writer as its owner (so an older writer's
## timer never hides a newer message), and hides it after `duration` --
## with a one-shot Timer parented to the LABEL, so a scene reload (loading
## a save) frees the timer with the label instead of leaving a callback
## that fires into a freed scene.

static func show(label: Label, owner_id: int, text: String, duration: float) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.text = text
	label.visible = true
	label.set_meta(&"msg_owner", owner_id)
	if not label.is_inside_tree():
		return
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = duration
	label.add_child(t)
	t.timeout.connect(func():
		if label.get_meta(&"msg_owner", 0) == owner_id and label.text == text:
			label.visible = false
		t.queue_free())
	t.start()
