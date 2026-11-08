extends SceneTree
## Round 36 Priority 2: DIAGNOSTIC DATA MODULE return/undo workflow.
## Player report: picking the (empty) module up in the Control Room and
## changing your mind, it could NOT be put back into its dock.
## Root cause: neither data port had anything hoverable while empty, so the
## carry system's Space "stow" found no receptacle and the module was only
## ever droppable. Everything here goes through the REAL ray + real Space
## key events (Input.parse_input_event), standing at each port.
var _ok := true
var main: Node
var dp: Node
var carry: Node
var cam: Node
var up: Node
var cap: Node
var prompt: Label


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 6: await process_frame
	dp = main.get_node("DayPlan")
	carry = main.get_node("Player/CarrySystem")
	cam = main.get_node("Player/LookPivot/PitchPivot/Camera3D")
	up = main.get_node("Equipment/UploadPort")
	cap = main.get_node("Equipment/CapturePort")
	prompt = main.get_node("Player/HUD/PromptLabel") if main.has_node("Player/HUD/PromptLabel") else null
	if prompt == null:
		prompt = cam._prompt_label
	await _return_unused()
	await _full_transfer()
	await _stale_and_recover()
	await _engineering_return()
	await _save_load_states()
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _module() -> Node3D:
	var all: Array = get_nodes_in_group(&"data_module")
	return all[0] if all.size() > 0 else null


func _count() -> int:
	var n := 0
	for it in main.find_children("*", "", true, false):
		if "item_id" in it and it.item_id == &"data_module" and not it.is_queued_for_deletion():
			n += 1
	return n


func _stand_at(port: Node3D) -> void:
	var fb: Node = main.get_node("FreeMoveBody")
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	var eye: Vector3 = port.global_transform * Vector3(0.0, 1.6 - port.global_position.y, 0.7)
	fb.sync_to_eye_position(eye)
	player.global_position = eye
	for k in 2:
		for i in 3: await physics_frame
		var target: Vector3 = port.global_transform * Vector3(0, 0, 0.05)
		var d: Vector3 = target - cam.global_position
		lp.rotation.y = atan2(-d.x, -d.z) - player.rotation.y
		lp._target_yaw = lp.rotation.y
		var pitch: float = atan2(d.y, Vector2(d.x, d.z).length())
		lp.get_node("PitchPivot").rotation.x = pitch
		lp._target_pitch = pitch
	for i in 3: await physics_frame
	await process_frame


func _space() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := ev.duplicate()
	ev2.pressed = false
	Input.parse_input_event(ev2)
	# Let a reach complete (the hand reaches before it owns the part; real
	# time -- headless frames are uncapped).
	await create_timer(0.9).timeout
	await process_frame


func _return_unused() -> void:
	var m: Node3D = _module()
	_check("module DM-7 starts docked (empty) in the Control Room", up.module() == m and m.payload.is_empty())
	await _stand_at(up)
	_check("looking at the dock targets the module ('%s')" % cam.get_hovered().get_interact_prompt() if cam.get_hovered() != null else "nothing", cam.get_hovered() == m)
	await _space()
	_check("Space picks the empty module up", carry.is_holding(m) and up.module() == null)
	await process_frame
	var st: Node = carry.stow_target()
	_check("still facing the dock: it is a receptacle for the module", st != null)
	cam._update_prompt()
	var ptxt: String = cam._prompt_label.text if cam._prompt_label != null else ""
	_check("prompt reads 'Return empty module to dock' ('%s')" % ptxt, ptxt.find("Return empty module") != -1)
	await _space()
	_check("Space returns the unused module to its Control Room dock", up.module() == m and not carry.is_carrying())
	_check("returning it did NOT complete or advance any transfer (uploaded_day %d, result %s)" % [up.uploaded_day, up.last_result], up.uploaded_day == -1 and up.last_result == "DOCKED")
	_check("exactly one module exists", _count() == 1)
	# The click path works as well (socket click while carrying).
	await _space()
	_check("picked up again", carry.is_holding(m))
	var slot: Node = up.find_child("Click_slot", true, false)
	slot.interact()
	_check("clicking the empty socket while carrying also docks it", up.module() == m and not carry.is_carrying())


func _open_data_order() -> void:
	dp._order_seq += 1
	var o := {"id": "WO-T%d" % dp._order_seq, "type": "data", "category": "D", "priority": 1, "day": dp.day_number, "seed": 5, "status": "open", "carried_from": -1}
	dp.orders.append(o)
	up.order_rearm(5)


func _full_transfer() -> void:
	_open_data_order()
	var m: Node3D = _module()
	_check("guidance: take the module to Engineering", up.order_next()["short"] == "TAKE MODULE")
	await _stand_at(up)
	await _space()
	_check("module carried", carry.is_holding(m))
	await _stand_at(cap)
	cam._update_prompt()
	_check("capture port hint: 'Insert module for capture' ('%s')" % cam._prompt_label.text, cam._prompt_label.text.find("Insert module for capture") != -1)
	await _space()
	_check("seated in the Engineering capture port", cap.module() == m)
	cap.on_part(&"capture")
	for i in 150: await process_frame
	await create_timer(2.3).timeout
	_check("data captured (state ready)", m.data_state() == "ready")
	await _stand_at(cap)
	await _space()
	_check("loaded module carried back", carry.is_holding(m))
	await _stand_at(up)
	cam._update_prompt()
	_check("upload dock hint: 'upload diagnostic data' ('%s')" % cam._prompt_label.text, cam._prompt_label.text.find("upload diagnostic data") != -1)
	await _space()
	_check("inserted: uploading", up.module() == m and up.busy_t >= 0.0)
	# Removal mid-transfer is refused (the guard now reaches the port).
	m.interact()
	await process_frame
	_check("cannot pull the module out mid-upload", up.module() == m and not carry.is_holding(m) and not carry.is_reaching())
	await create_timer(2.8).timeout
	_check("upload completed -> order done", up.order_done() and up.last_result == "UPLOADED")
	_check("module shows the data as uploaded", m.data_state() == "uploaded")
	_check("exactly one module exists", _count() == 1)


func _stale_and_recover() -> void:
	# A new request on a later day: yesterday's (uploaded) data is no use.
	dp.day_number += 1
	_open_data_order()
	var m: Node3D = _module()
	_check("new request: the docked module's old data is STALE (%s)" % m.data_state(), m.data_state() == "stale")
	_check("guidance: recapture required", up.order_next()["short"] == "RECAPTURE")
	await _stand_at(up)
	await _space()
	_check("stale module removed from the dock", carry.is_holding(m))
	cam._update_prompt()
	_check("re-inserting it is labelled STALE ('%s')" % cam._prompt_label.text, cam._prompt_label.text.find("STALE") != -1)
	await _space()
	_check("re-inserted stale data is rejected, order not done", up.module() == m and not up.order_done() and up.last_result == "STALE")
	await _space()
	await _stand_at(cap)
	await _space()
	cap.on_part(&"capture")
	await create_timer(2.3).timeout
	# Change the station after capture -> stale by signature.
	var pw: Node = main.get_node("Equipment/PowerDistribution")
	pw.setting[0] = int(pw.setting[0]) + 1
	_check("station changed after capture -> STALE", m.data_state() == "stale")
	pw.setting[0] = int(pw.setting[0]) - 1
	_check("change undone -> data valid again", m.data_state() == "ready")
	await _stand_at(cap)
	await _space()
	await _stand_at(up)
	await _space()
	await create_timer(2.8).timeout
	_check("recaptured data uploads: order done", up.order_done())


func _engineering_return() -> void:
	# A module taken from Engineering WITHOUT data stays recoverable.
	var m: Node3D = _module()
	await _stand_at(up)
	await _space()
	m.payload = {}
	m.refresh()
	await _stand_at(cap)
	await _space()
	_check("empty module seated in Engineering", cap.module() == m)
	await _space()
	_check("...and taken out again unused", carry.is_holding(m))
	await _stand_at(up)
	await _space()
	_check("...and returned to the Control dock", up.module() == m and not carry.is_carrying())


func _save_load_states() -> void:
	var sg: Node = main.get_node("SaveGame")
	sg.save_path = "user://test_data_module_return.json"
	var m: Node3D = _module()
	# Carried, empty.
	await _stand_at(up)
	await _space()
	var r: Dictionary = sg.save_game()
	_check("save while carrying the module: %s" % r["message"], r["ok"])
	sg.apply_state(sg.read_save()["data"])
	await process_frame
	m = _module()
	_check("load: module still in the hand, empty, one module", carry.is_holding(m) and m.payload.is_empty() and _count() == 1)
	await _stand_at(up)
	await _space()
	_check("load: can still be returned to the dock", up.module() == m)
	# Seated in the capture port with captured data.
	await _space()
	await _stand_at(cap)
	await _space()
	cap.on_part(&"capture")
	await create_timer(2.3).timeout
	var pay: Dictionary = m.payload.duplicate(true)
	sg.save_game()
	m.payload = {}
	sg.apply_state(sg.read_save()["data"])
	await process_frame
	m = _module()
	_check("load: captured module back in the capture port with its data", cap.module() == m and m.payload.get("sig", "") == pay.get("sig", "-") and _count() == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_data_module_return.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_data_module_return.json.bak"))


func _check(name: String, cond: bool) -> void:
	print(("PASS: " if cond else "FAIL: ") + name)
	if not cond:
		_ok = false
