extends "res://scripts/station/equipment_base.gd"
## Round 35 Priority 9: a DATA PORT. role "capture" (Engineering): seat the
## module (Space while holding it, facing the port), click CAPTURE -> the
## module records the REAL current readings (power bus, channel states,
## breakers, wiring fault, sensor drift, airflow/pressure/O2) plus the
## station-state signature. role "upload" (Control Room): seat the module
## -> it is validated: empty -> rejected; captured before the station
## changed (signature differs) -> STALE, recapture; otherwise uploaded into
## the diagnostics record. The upload port owns the DATA work order.

@export_enum("capture", "upload") var role: String = "capture"
@export var power_path: NodePath = ^"../PowerDistribution"
@export var breaker_path: NodePath = ^"../BreakerPanel"
@export var panel_path: NodePath = ^"../../Geometry/EngineeringCabinet1"
@export var calib_path: NodePath = ^"../../Interactables/SensorCalibrationStation"
@export var env_path: NodePath = ^"../../EnvironmentModel"
@export var carry_system_path: NodePath = ^"../../Player/CarrySystem"

const CAPTURE_S := 2.0
const UPLOAD_S := 2.5
var busy_t: float = -1.0
var request_day: int = -1          # upload: the open request's day (-1 none)
var uploaded_day: int = -1
var last_result: String = ""
var history: Array = []            # upload: [{day, values}]
var _slot: Node3D
var _screen: Label3D
var _lamp: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"data_port")
	add_to_group(&"item_dock")   # Round 36: SaveGame owner kind "dataport"
	_base_ready(&"data" if role == "upload" else &"")
	box(Vector3(0.3, 0.34, 0.06), Vector3(0, 0, -0.03), Color(0.2, 0.22, 0.25))
	box(Vector3(0.32, 0.04, 0.08), Vector3(0, 0.18, -0.02), Color(0.85, 0.55, 0.1))
	label("DIAG CAPTURE" if role == "capture" else "DIAG UPLOAD", Vector3(0, 0.13, 0.005), 15)
	box(Vector3(0.12, 0.08, 0.05), Vector3(0, 0.0, 0.01), Color(0.05, 0.06, 0.07))
	_slot = Node3D.new()
	_slot.position = Vector3(0, 0.0, 0.07)
	_slot.rotation_degrees.x = 90.0
	add_child(_slot)
	# Round 36: the SOCKET is a real target. Looking at an empty port with
	# the module in hand now resolves to it (Space or click seats the
	# module); before, an empty port had nothing hoverable at all, so the
	# carry system had no stow target and an unused module could not be put
	# back into its Control Room dock. A seated module (in front of it)
	# still wins the ray, so "take" is unchanged.
	part(&"slot", Vector3(0.16, 0.12, 0.05), Vector3(0, 0.0, 0.035))
	_lamp = lamp(Vector3(0.1, 0.07, 0.01))
	_screen = label("", Vector3(0, -0.1, 0.006), 12, Color(0.55, 0.95, 0.75))
	if role == "capture":
		box(Vector3(0.08, 0.04, 0.025), Vector3(0, -0.06, 0.012), Color(0.2, 0.55, 0.3))
		label("CAPTURE", Vector3(0, -0.06, 0.026), 10, Color(0.95, 0.95, 0.9))
		part(&"capture", Vector3(0.1, 0.06, 0.05), Vector3(0, -0.06, 0.02))
		_screen.position.y = -0.13
	else:
		# The one data module starts seated (empty) in the Control Room port.
		var m := StaticBody3D.new()
		m.set_script(preload("res://scripts/interactables/data_module.gd"))
		m.name = "DataModule"
		var cs: Node = get_node_or_null(carry_system_path)
		var ml: Node = get_node_or_null(message_label_path)
		m.carry_system_path = cs.get_path() if cs != null else NodePath()
		m.message_label_path = ml.get_path() if ml != null else NodePath()
		_slot.add_child(m)
		seat(m)
	_refresh()


func module() -> Node3D:
	for c in _slot.get_children():
		if "item_id" in c and c.item_id == &"data_module":
			return c
	return null


## Carry "stow" protocol: Space while holding the module at this port.
func accepts_item(item: Node) -> bool:
	return item != null and "item_id" in item and item.item_id == &"data_module" and module() == null and busy_t < 0.0


func stow(item: Node3D) -> bool:
	if not accepts_item(item):
		return false
	seat(item)
	sfx(&"insert")
	if role == "upload":
		_begin_upload()
	else:
		say("Module seated. Click CAPTURE." if item.payload.is_empty() else "Module seated. CAPTURE overwrites its stored data.")
	_refresh()
	for m in get_tree().get_nodes_in_group(&"data_module"):
		m.refresh()
	return true


# ---- Round 36: the socket click part (receptacle protocol) ------------
func part_accepts_item(id: StringName, item: Node) -> bool:
	return id == &"slot" and accepts_item(item)


func part_stow(id: StringName, item: Node3D) -> bool:
	return id == &"slot" and stow(item)


func part_stow_hint(id: StringName, item: Node) -> String:
	if id != &"slot" or item == null or not ("payload" in item):
		return ""
	if role == "capture":
		return "Insert module for capture" if item.payload.is_empty() else "Insert module (recapture)"
	match payload_state(item.payload):
		"empty": return "Return empty module to dock"
		"ready": return "Insert module: upload diagnostic data"
		"stale": return "Insert module (data STALE - recapture required)"
	return "Dock data module"


## Upload role: how a module payload stands against the open request.
func payload_state(p: Dictionary) -> String:
	if p.is_empty():
		return "empty"
	var requested: bool = transfer_requested()
	if requested and int(p.get("day", -1)) < request_day:
		return "stale"   # captured before today's request
	if bool(p.get("uploaded", false)):
		return "uploaded"
	if String(p.get("sig", "")) != signature():
		return "stale"
	return "ready" if requested else "data"


## Upload role: is a transfer currently requested and not yet done?
func transfer_requested() -> bool:
	return request_day != -1 and uploaded_day < request_day


func seat(item: Node3D) -> void:
	if item.has_method("set_rest_global"):
		item.set_rest_global(_slot.global_transform, _slot)
	item.return_to_rest()
	item.transform = Transform3D()
	item.visible = true
	var c: Node = item.get_node_or_null("Collision")
	if c != null:
		c.disabled = false


func module_removed(_m: Node) -> bool:
	if busy_t >= 0.0:
		say("Wait — transfer in progress.")
		return false
	return true


func on_part(id: StringName) -> void:
	if id == &"slot":
		# Clicking the socket with the module in hand seats it too.
		var cs: Node = get_node_or_null(carry_system_path)
		if cs != null and cs.is_carrying() and cs.carried_item_id() == &"data_module" and accepts_item(cs._carried_item):
			var item: Node3D = cs.take_carried_item_if_matches(&"data_module")
			if item != null:
				stow(item)
		elif module() == null:
			say("Data port %s: no module seated." % ("DIAG CAPTURE" if role == "capture" else "DIAG UPLOAD"))
		return
	if id == &"capture":
		var m: Node3D = module()
		if m == null:
			say("Seat the data module first.")
			sfx(&"fail")
			return
		if busy_t >= 0.0:
			return
		busy_t = 0.0
		sfx(&"relay")
		_refresh()


func part_prompt(id: StringName) -> String:
	if id == &"capture":
		return "Click: Capture diagnostics" if module() != null else "CAPTURE (seat the module first)"
	if id == &"slot":
		var cs: Node = get_node_or_null(carry_system_path)
		if cs != null and cs.is_carrying():
			return ""   # the "Space: ..." receptacle hint says it
		return "" if module() != null else ("Module dock DM-7 (empty)" if role == "upload" else "Capture port (empty)")
	return ""


var _had_module: bool = true


func _process(delta: float) -> void:
	# Round 36: the screen follows the module leaving/arriving (a module
	# taken out of the upload dock clears the last result).
	var has_m: bool = module() != null
	if has_m != _had_module:
		_had_module = has_m
		if not has_m and role == "upload" and last_result != "UPLOADED":
			last_result = ""
		_refresh()
	if busy_t < 0.0:
		return
	busy_t += delta
	if role == "capture" and busy_t >= CAPTURE_S:
		busy_t = -1.0
		var m: Node3D = module()
		if m != null:
			m.payload = snapshot()
			m.refresh()
			sfx(&"success")
			say("Diagnostics captured to module DM-7.")
			if _dp != null:
				_dp.log_event("Diagnostics captured (Engineering)")
	elif role == "upload" and busy_t >= UPLOAD_S:
		busy_t = -1.0
		var m2: Node3D = module()
		if m2 != null:
			history.append({"day": _dp.day_number if _dp != null else 0, "values": m2.payload.get("values", {})})
			uploaded_day = _dp.day_number if _dp != null else 0
			m2.payload["uploaded"] = true
			m2.refresh()
			last_result = "UPLOADED"
			sfx(&"success")
			say("Diagnostics uploaded and verified.")
			if _dp != null:
				_dp.log_event("Diagnostics uploaded (Control Room)")
	_refresh()


func _begin_upload() -> void:
	var m: Node3D = module()
	if m == null:
		return
	# Round 36: an EMPTY module is simply docked (returned unused) -- not an
	# error, and never progress on the transfer order.
	match payload_state(m.payload):
		"empty":
			last_result = "DOCKED"
			say("Module DM-7 docked (empty)." + (" Capture data in Engineering to upload." if transfer_requested() else ""))
		"stale":
			last_result = "STALE"
			if String(m.payload.get("sig", "")) != signature():
				say("STALE DATA — the station changed since capture. Take the module back to Engineering and recapture.")
			else:
				say("STALE DATA — captured before today's request. Recapture in Engineering.")
			sfx(&"fail")
		"ready":
			busy_t = 0.0
			last_result = "UPLOADING"
		"uploaded":
			last_result = "UPLOADED"
			say("Module DM-7 docked (data already uploaded).")
		_:
			last_result = "DOCKED"
			say("Module DM-7 docked. No diagnostic transfer is requested.")


## The REAL readings at this moment.
func snapshot() -> Dictionary:
	var v := {}
	var pw: Node = get_node_or_null(power_path)
	if pw != null:
		v["bus_v"] = snappedf(pw.bus_voltage(), 0.1)
		v["channels"] = [pw.channel_state(0), pw.channel_state(1), pw.channel_state(2)]
	var br: Node = get_node_or_null(breaker_path)
	if br != null:
		v["breakers_tripped"] = br.tripped_ids()
	var pn: Node = get_node_or_null(panel_path)
	if pn != null:
		v["wiring"] = String(pn.condition())
	var cl: Node = get_node_or_null(calib_path)
	if cl != null:
		v["sensor_drift"] = cl.service_required_count() if cl.has_recorded_drift() else 0
	var env: Node = get_node_or_null(env_path)
	if env != null:
		v["airflow_pct"] = roundi(env.airflow() * 100.0)
	return {"day": _dp.day_number if _dp != null else 0, "values": v, "sig": signature()}


## Signature of the discrete station state a capture describes; any change
## (loads, breakers, wiring, sensors) makes an older capture STALE.
func signature() -> String:
	var parts: Array = []
	var pw: Node = get_node_or_null(power_path)
	if pw != null:
		parts.append(str(pw.setting) + str(pw.demand))
	var br: Node = get_node_or_null(breaker_path)
	if br != null:
		parts.append(str(br.on))
	var pn: Node = get_node_or_null(panel_path)
	if pn != null:
		parts.append(String(pn.condition()))
	var cl: Node = get_node_or_null(calib_path)
	if cl != null:
		parts.append(str(cl.has_recorded_drift()))
	return str(hash("|".join(parts)))


func _refresh() -> void:
	var m: Node3D = module()
	var txt := ""
	var c := Color(0.4, 0.45, 0.45)
	if busy_t >= 0.0:
		txt = "CAPTURING..." if role == "capture" else "UPLOADING..."
		c = Color(1.0, 0.75, 0.3)
	elif m == null:
		txt = "NO MODULE"
	elif role == "capture":
		txt = "DATA READY" if not m.payload.is_empty() and String(m.payload.get("sig", "")) == signature() else ("STALE DATA" if not m.payload.is_empty() else "READY")
		c = Color(0.3, 0.9, 0.4)
	else:
		txt = last_result if last_result != "" else "MODULE DOCKED"
		c = Color(0.3, 0.9, 0.4) if last_result in ["UPLOADED", "DOCKED", ""] else Color(1.0, 0.4, 0.3)
	if _screen != null:
		_screen.text = txt
	if _lamp != null:
		set_lamp(_lamp, c, true)


# ------------------------------------------------- work order (upload port)
func order_rearm(_seed: int) -> void:
	request_day = _dp.day_number if _dp != null else 0
	last_result = ""
	_refresh()


func order_severity() -> int:
	return 1 if transfer_requested() else 0


func order_feasible() -> bool:
	return request_day == -1 or uploaded_day >= request_day


func order_done() -> bool:
	return request_day != -1 and uploaded_day >= request_day


func _module_anywhere() -> Node3D:
	for n in get_tree().get_nodes_in_group(&"data_module"):
		return n
	return null


func order_next() -> Dictionary:
	var m: Node3D = module()
	var cap: Node = null
	for p in get_tree().get_nodes_in_group(&"data_port"):
		if p.role == "capture":
			cap = p
	var carry: Node = get_node_or_null(carry_system_path)
	var held: bool = carry != null and carry.is_carrying() and carry.carried_item_id() == &"data_module"
	var cr := &"control_room"
	var en := &"engineering"
	if held:
		if payload_state(carry._carried_item.payload) == "ready":
			return {"action": "Insert module (upload port)", "short": "INSERT MODULE", "room": cr}
		return {"action": "Seat module in capture port", "short": "SEAT MODULE", "room": en}
	if cap != null and cap.module() != null:
		if cap.busy_t >= 0.0:
			return {"action": "Capturing data", "short": "CAPTURING", "room": en}
		if payload_state(cap.module().payload) == "ready":
			return {"action": "Take module to Control", "short": "TAKE MODULE", "room": en}
		return {"action": "Capture diagnostic data", "short": "CAPTURE DATA", "room": en}
	if m != null:
		if busy_t >= 0.0:
			return {"action": "Uploading data", "short": "UPLOADING", "room": cr}
		if payload_state(m.payload) == "stale":
			return {"action": "Recapture required: module to Engineering", "short": "RECAPTURE", "room": cr}
		return {"action": "Take module to Engineering", "short": "TAKE MODULE", "room": cr}
	return {"action": "Find data module DM-7", "short": "FIND MODULE", "room": en}


func order_progress() -> String:
	return "uploaded" if order_done() else ""


func order_detail() -> Array:
	return ["Diagnostic transfer: module DM-7.", "Capture in Engineering (north wall), upload here (Control Room, west wall).", "Last upload: %s." % (("day %d" % uploaded_day) if uploaded_day >= 0 else "none"), "Data recorded: power bus, channels, breakers, wiring, sensors, airflow."]


func state_dict() -> Dictionary:
	return {"request_day": request_day, "uploaded_day": uploaded_day, "last_result": last_result, "history": history.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	request_day = int(d.get("request_day", request_day))
	uploaded_day = int(d.get("uploaded_day", uploaded_day))
	last_result = String(d.get("last_result", ""))
	history = Array(d.get("history", []))
	busy_t = -1.0
	_refresh()
