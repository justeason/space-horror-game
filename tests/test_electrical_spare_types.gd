extends SceneTree
## Round 32 Priority 4: compatible electrical spare TYPES on the fixed
## 10-wire panel. Power circuits (service/return/backup) need the 16GA power
## harness; signal/control circuits (telemetry/relay) need the 22GA shielded
## signal cable. A wrong part is rejected without being consumed and
## without losing procedure progress; every authored fault configuration
## has a valid resolution with stocked parts.
var _ok := true

func _init() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in 5: await process_frame
	var panel: Node = main.get_node("Geometry/EngineeringCabinet1")
	var carry: Node = main.get_node("Player/CarrySystem")
	var cab1: Node = main.get_node("Geometry/StorageCabinet1")
	var dp: Node = main.get_node("DayPlan")
	var P = panel.ProcedureStage

	# ---- Storage: typed slots. ----
	_check("cabinet stocks both types (4 power harness, 2 signal cable)", cab1.stock_count(&"wire_control_16ga") == 4 and cab1.stock_count(&"wire_signal_22ga") == 2)
	var sig: Node3D = main.get_node("Interactables/WireSignal1")
	_check("signal cable is a distinct part (id, type, tag)", sig.item_id == &"wire_signal_22ga" and sig.cable_type == "signal" and sig.get_display_name() == "Signal Cable")
	_check("placard lists both types from real counts", (cab1.get_node("DoorHinge/StockLabel") as Label3D).text.find("22GA SIG  2 AVAILABLE") != -1)

	# ---- Reachable: a standing player's look ray reaches each signal cable
	# (Round 32 fix: they used to sit under the full-depth shelf). ----
	cab1.interact()
	await create_timer(0.9).timeout
	for n in ["WireSignal1", "WireSignal2"]:
		var w: Node3D = main.get_node("Interactables/" + n)
		var eye := Vector3(-6.75, 1.6, w.global_position.z)
		var hit: Dictionary = w.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, w.global_position, 1 | 16))
		_check("%s is visible/clickable from a standing eye in front of the open cabinet (hit %s)" % [n, str(hit.get("collider", null))], hit.get("collider", null) == w)

	# ---- Compatibility for every authored configuration. ----
	var expected := {"standard_service_fault": &"wire_control_16ga", "alternate_return_fault": &"wire_control_16ga", "backup_circuit_fault": &"wire_control_16ga", "telemetry_fault": &"wire_signal_22ga", "relay_fault": &"wire_signal_22ga"}
	var power: Node3D = main.get_node("Interactables/WireComponent3")
	var spares: Array = []
	for n in ["WireComponent", "WireComponent2", "WireComponent3", "WireComponent4", "WireSignal1", "WireSignal2"]:
		spares.append(main.get_node("Interactables/" + n))
	for n in ["ReserveSignal1", "ReserveSignal2", "ReserveWire1"]:
		spares.append(main.get_node("Interactables/SupplyCrate/" + n))
	for i in panel._REPAIR_CONFIGS.size():
		var label: String = panel._REPAIR_CONFIGS[i]["label"]
		panel._config_index = -1
		panel._apply_config(i)
		var need: StringName = panel.required_component_id
		_check("%s requires %s" % [label, need], need == expected[label])
		var right: Node3D = sig if need == &"wire_signal_22ga" else power
		var wrong: Node3D = power if need == &"wire_signal_22ga" else sig
		# Wrong part at the REPLACE step: rejected, kept, progress preserved.
		panel._procedure = P.REPLACE
		carry.pick_up(wrong)
		await create_timer(0.7).timeout
		var r: Dictionary = panel.install_replacement_wire()
		_check("%s: wrong part rejected with clear feedback ('%s')" % [label, r.get("message", "")], not r["ok"] and String(r.get("message", "")).begins_with("Wrong part"))
		_check("%s: wrong part NOT consumed (still in hand), progress kept" % label, carry.is_holding(wrong) and not wrong.is_installed() and panel._procedure == P.REPLACE)
		carry.drop()
		await process_frame
		# The correct part installs.
		carry.pick_up(right)
		await create_timer(0.7).timeout
		var r2: Dictionary = panel.install_replacement_wire()
		_check("%s: compatible part installs" % label, r2["ok"] and right.is_installed())
		_check("%s: an installed part never counts as Storage stock" % label, not cab1.is_item_stowed(right))
		# Fresh spare for the next configuration (installed parts move under
		# the panel's terminal, so keep references, not scene paths).
		for w in spares:
			if not w.is_installed() and w.item_id == need:
				if need == &"wire_signal_22ga":
					sig = w
				else:
					power = w
				break
		panel._procedure = P.NOT_STARTED

	# ---- Guidance names the right TYPE (no hard-coded 16-gauge text). ----
	if carry.is_carrying():
		carry.drop()
		await process_frame
	for i in panel._REPAIR_CONFIGS.size():
		panel._config_index = -1
		panel._apply_config(i)
		panel._procedure = P.NOT_STARTED
		panel._wire_replaced = false
		panel._open_procedure()
		var msg: String = panel._message_label.text
		var want: String = "Signal Cable" if panel.required_component_id == &"wire_signal_22ga" else "Control Wire (16-gauge"
		_check("%s: 'nothing to install' names the compatible part ('%s')" % [panel._REPAIR_CONFIGS[i]["label"], msg], msg.find(want) != -1)
	# The HUD message must actually be ON SCREEN (it was anchored top-centre
	# with negative offsets -- drawn above the viewport -- until Round 32).
	# Shared HUD label: a part's pickup message timer (1.5 s) must not hide a
	# NEWER message another object wrote meanwhile (Round 32 render showed
	# the wrong-part message vanishing this way).
	var sig2: Node3D = null
	for w in spares:
		if is_instance_valid(w) and not w.is_installed():
			sig2 = w
			break
	if carry.is_carrying():
		carry.drop()
		await process_frame
	sig2._show_message("Picked up: Signal Cable (22-gauge shielded).")
	panel._show_message("That isn't the right part for this repair.")
	await create_timer(1.8).timeout
	_check("a newer message survives the older writer's timer", panel._message_label.visible and panel._message_label.text.begins_with("That isn't"))
	await create_timer(1.6).timeout
	_check("...and its own owner still hides it on time", not panel._message_label.visible)
	var ml: Control = panel._message_label
	var win := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	var top: float = ml.anchor_top * win.y + ml.offset_top
	var bottom: float = ml.anchor_bottom * win.y + ml.offset_bottom
	_check("task message label lies inside the %s window (y %.0f..%.0f)" % [str(win), top, bottom], top >= 0.0 and bottom <= win.y and top < bottom)

	# ---- First-time repairs stay on power faults (tutorial unchanged). ----
	var all_power := true
	for k in 30:
		panel._config_index = -1
		panel._select_repair_config()
		all_power = all_power and panel.required_component_id == &"wire_control_16ga"
	_check("first-time repair configs are always power faults (30 draws)", all_power)

	# ---- Recurring repairs only pick configurations with a stocked spare. ----
	for it in main.find_children("*", "", true, false):
		if "item_id" in it and it.item_id == &"wire_control_16ga" and it.has_method("is_installed") and not it.is_installed():
			it.queue_free()
	await process_frame
	await process_frame
	for k in 10:
		panel._rearm_for_service(k * 7919 + 1)
		_check("power spares exhausted: recurring fault #%d picks a signal circuit (%s)" % [k, panel.fault_config_label()], panel.required_component_id == &"wire_signal_22ga")
	print("")
	if _ok: print("ALL TESTS PASSED")
	else: print("SOME TESTS FAILED")
	quit()


func _check(label: String, cond: bool) -> void:
	if cond: print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_ok = false
