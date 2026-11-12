extends Node
## Round 33 Priority 1: single-slot, versioned, ATOMIC save/load.
##
## SCHEMA (version 1), one JSON document:
##   schema, game, day          header (validated first)
##   day_plan                   DayPlan's own fields (DayPlan stays the
##                              single authority for work orders/schedule)
##   difficulty                 GameSettings' global difficulty
##   equipment {stable_id: {}}  per-station state fields (see EQUIPMENT)
##   items [ {id, type, cable, owner} ]
##                              every physical part, by STABLE ID (its node
##                              name: authored names like "FilterCartridge2",
##                              "ReserveSignal1", delivered "CargoCS0002_5",
##                              ejected "UsedFilterCartridge3"), with exactly
##                              ONE owner: cabinet slot / reserve slot / cargo
##                              port slot / installed (filter housing or
##                              electrical panel) / seated (the used cartridge
##                              still inside the housing) / loose (world
##                              transform) / held (in the hand)
##   station_used               which used cartridge the housing tracks
##   player {pos, yaw, pitch}   standing body position and facing
##   laptop {entry}             the personal session-log entry
## Values are tagged ({"$i"}, {"$sn"}, {"$v3"}, {"$xf"}, {"$d"}) so ints,
## StringNames, vectors and int-keyed dictionaries round-trip exactly.
##
## SAFE SAVE BOUNDARY (deterministic, explained to the player): saving is
## refused while a reach/place/physics settle is in progress, while a
## focused minigame is open, while sleeping/lying, or while the cargo hatch
## is moving. A part held in the hand IS saved (restored to the hand).
## Calibration minigame progress is not mid-saved: the station's recorded
## drift is, so the minigame reopens at the day's drifted setpoints.
##
## ATOMIC WRITE: serialise -> write <save>.tmp -> read it back and validate
## -> keep the previous save as <save>.bak -> rename tmp over save. A failed
## or interrupted write never replaces a good save; loading falls back to
## the backup if the main file is missing or invalid.
##
## LOADING: the station is rebuilt from the fresh scene: items absent from
## the save are removed (consumed), missing ones (delivered/ejected) are
## created, every part is first parked out of all containers and then put
## into exactly its saved owner, stations get their fields and their visuals
## snapped (no animation, no sounds, no physics impulses), DayPlan gets its
## fields WITHOUT re-running any re-arm (faults are restored, not re-rolled).

const SCHEMA_VERSION := 2   # v2 (Round 34): items carry a stable "pid"; v1 still loads
const GameFlow = preload("res://scripts/station/game_flow.gd")
## Round 34: renamed items map old persistent ids to new ones here, so an
## existing save keeps working after a scene rename (never lose inventory).
const PID_ALIASES := {}
const GAME_ID := "satellite_maintenance_horror"
const GameSettings = preload("res://scripts/station/game_settings.gd")
const _FILTER_SCENE := preload("res://scenes/interactables/filter_cartridge.tscn")
const _WIRE_SCENE := preload("res://scenes/interactables/wire_component.tscn")
const _USED_SCENE := preload("res://scenes/interactables/used_filter_cartridge.tscn")
const KNOWN_TYPES := [&"filter_cartridge", &"wire_control_16ga", &"wire_signal_22ga", &"used_filter_cartridge", &"cargo_carrier", &"data_module", &"thermal_probe", &"airflow_meter", &"leak_detector"]
const OWNER_KINDS := ["cabinet", "reserve", "port", "installed", "seated", "loose", "held", "carrier", "docked", "dataport"]

## stable id -> [node name (unique in main.tscn), saved fields]
const EQUIPMENT := {
	"filter_housing": ["FilterHousingStation", ["_stage", "_latch_open", "_cartridge_angle_deg", "_active_difficulty", "_service_count", "_variant", "_last_variant", "_variant_day", "_old_angle_deg", "_seize_left"]],
	"electrical_panel": ["EngineeringCabinet1", ["_repair_stage", "_door_open", "_screw_progress", "_screws_done_for_open", "_screws_reinstalled", "_procedure", "_isolated", "_disconnected", "_reconnected", "_recorded_disconnect_order", "_wire_replaced", "_config_index", "_last_repaired_config", "_active_difficulty"]],
	"calibration_station": ["SensorCalibrationStation", ["_drift_day", "_drift_required", "_drift_seed"]],
	"valve_station": ["ValveRoutingStation", ["_open", "_open_order", "_config_index", "_pending_sequence_warning", "_v3_opened_with_v2_open"]],
	"cargo_port": ["CargoPort", ["state", "shipment_id", "manifest", "received_shipments", "_shipment_seq"]],
	"supply_crate": ["SupplyCrate", ["reserve_received"]],
}
const DAYPLAN_FIELDS := ["day_number", "workday", "_facts", "_serviced", "service_history", "blocked_services",
	"next_cargo_day", "cargo_history", "_day_log", "assignment_task_id", "fault_target", "required_component_id",
	"c01_status", "e06_status", "c05_status", "c02_status", "e01_status", "e02_status", "e05_status",
	"l07_status", "l08_status", "l02_status", "e09_status", "m02_status"]
## Optional DayPlan fields added by later rounds (absent in older saves is fine).
const DAYPLAN_OPTIONAL := ["shift_stats", "shift_reported", "carried_over_from", "inspections_done", "shift_history", "readings", "shift_elapsed_s", "shift_ended", "cargo_duty", "cargo_duty_id", "orders", "day_type", "_order_seq", "emergency_plan", "proficiency", "_credited", "underfed", "work_done_at_s", "awake_after_shift_s", "laptop_clock_s"]

@export var save_path: String = "user://savegame.json"
## Round 34 Priority 10: the protected AUTOSAVE slot (written only at a
## completed sleep -> new-day wake; never the manual slot).
@export var autosave_path: String = "user://autosave.json"

## Loading reloads the scene; the parsed save waits here for the new
## SaveGame node to apply once the fresh station is ready.
static var _pending_load: Dictionary = {}
static var _pending_message: String = ""

var last_message: String = ""
signal saved(ok: bool, message: String)
signal loaded(ok: bool, message: String)


func _ready() -> void:
	add_to_group(&"save_game")
	if not _pending_load.is_empty():
		var data: Dictionary = _pending_load
		_pending_load = {}
		if data.has("_save_path"):
			save_path = data["_save_path"]
		if data.has("_autosave_path"):
			autosave_path = data["_autosave_path"]
		_apply_after_ready.call_deferred(data)
	else:
		if _pending_message != "":
			last_message = _pending_message
			_pending_message = ""
		if GameFlow.start_mode == "new_game":
			GameFlow.start_mode = ""
			_start_in_bed.call_deferred()
	var ss: Node = _main().get_node_or_null("SleepState")
	if ss != null and ss.has_signal(&"woke_into_new_day"):
		ss.woke_into_new_day.connect(_on_new_day_wake)


func _start_in_bed() -> void:
	await get_tree().process_frame
	var ss: Node = _main().get_node_or_null("SleepState")
	if ss != null and ss.has_method("start_day_in_bed"):
		ss.start_day_in_bed()


## Autosave after a completed sleep -> new day, once the player is awake in
## the bunk and the new day's state is coherent.
## Only the real game flow (entered through the main menu) autosaves; a
## station scene opened directly (tests, tools, editor F6) never writes the
## player's autosave slot unless a caller enables it explicitly.
var autosave_enabled: bool = GameFlow.from_main_menu


func _on_new_day_wake() -> void:
	if autosave_enabled:
		autosave_new_day()


var autosaves_written: int = 0


func autosave_new_day() -> Dictionary:
	if _busy:
		return {"ok": false, "message": "busy"}
	var data: Dictionary = collect_state()
	data["start_in_bed"] = true
	data["slot"] = "autosave"
	var r: Dictionary = _write_atomic(autosave_path, data)
	if r["ok"]:
		autosaves_written += 1
	return r


func _apply_after_ready(data: Dictionary) -> void:
	for i in 3:
		await get_tree().process_frame
	var r: Dictionary = apply_state(data)
	last_message = r["message"]
	_show(last_message)
	loaded.emit(r["ok"], r["message"])


# ====================================================================== API
var _busy: bool = false


## Atomic slot write: tmp -> read back + validate -> previous -> .bak ->
## rename. A failed write never replaces a good file.
func _write_atomic(path: String, data: Dictionary) -> Dictionary:
	_busy = true
	data["saved_at"] = Time.get_unix_time_from_system()
	var text: String = JSON.stringify(data, "\t")
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_busy = false
		return {"ok": false, "message": "Save failed: cannot write (%s)." % error_string(FileAccess.get_open_error())}
	f.store_string(text)
	f.flush()
	f.close()
	var check: Dictionary = _parse_file(tmp)
	if not check["ok"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		_busy = false
		return {"ok": false, "message": "Save failed: written data did not validate (%s). Previous save kept." % check["message"]}
	var g_save: String = ProjectSettings.globalize_path(path)
	var g_bak: String = ProjectSettings.globalize_path(path + ".bak")
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(g_bak)
		DirAccess.rename_absolute(g_save, g_bak)
	var err: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), g_save)
	_busy = false
	if err != OK:
		return {"ok": false, "message": "Save failed while replacing the file (%s). Backup kept." % error_string(err)}
	return {"ok": true, "message": ""}
func backup_path() -> String:
	return save_path + ".bak"


func tmp_path() -> String:
	return save_path + ".tmp"


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(backup_path())


## A short header for the Save/Load screen ("DAY 5 · saved"), or "".
func save_summary() -> String:
	var r: Dictionary = read_save()
	if not r["ok"]:
		return ""
	return "Day %d%s" % [int(r["data"].get("day", 0)), " (from backup)" if r.get("from_backup", false) else ""]


## Why saving is not possible right now, or "" when it is safe.
func save_blocker() -> String:
	var main: Node = _main()
	var carry: Node = main.get_node_or_null("Player/CarrySystem")
	if carry != null:
		if carry.is_reaching() or carry.is_placing():
			return "Finish handling the part first."
		if not carry._settle_tweens.is_empty():
			return "Wait for the dropped part to settle."
	var focused: Node = main.get_node_or_null("FocusedInteractionState")
	if focused != null and focused.is_active():
		return "Close the open equipment panel first."
	var sleep: Node = main.get_node_or_null("SleepState")
	if sleep != null and (sleep.is_sleeping() or sleep.is_lying_in_bed() or sleep.is_sitting()):
		return "Get up from the bunk first."
	var port: Node = _find("CargoPort")
	if port != null and port.is_animating():
		return "Wait for the cargo hatch to finish moving."
	for dpn in get_tree().get_nodes_in_group(&"data_port"):
		if dpn.busy_t >= 0.0:
			return "Wait for the data transfer to finish."
	var eva: Node = _main().get_node_or_null("EvaSystem")
	if eva != null and eva.is_eva_active():
		return "Return inside through the airlock first."
	var ts: Node = _find("ThermalSurvey")
	if ts != null and ts.measuring >= 0:
		return "Wait for the thermal reading to finish."
	var hs: Node = _find("HatchSeal")
	if hs != null and hs.test_state == "running":
		return "Wait for the pressure test to finish."
	return ""


func save_game() -> Dictionary:
	var why: String = save_blocker()
	if why != "":
		return _done_save(false, "Not saved: " + why)
	var data: Dictionary = collect_state()
	data["slot"] = "manual"
	var w: Dictionary = _write_atomic(save_path, data)
	if not w["ok"]:
		return _done_save(false, w["message"])
	return _done_save(true, "Progress saved — Day %d." % int(data["day"]))


## Reads the save (falling back to the backup). {ok, data, message, from_backup}
func read_save(path: String = "") -> Dictionary:
	if path == "":
		path = save_path
	var main_r: Dictionary = _parse_file(path)
	if main_r["ok"]:
		main_r["from_backup"] = false
		return main_r
	var bak_r: Dictionary = _parse_file(path + ".bak")
	if bak_r["ok"]:
		bak_r["from_backup"] = true
		bak_r["message"] = "Main save unusable (%s); loaded the backup." % main_r["message"]
		return bak_r
	return {"ok": false, "message": main_r["message"] if FileAccess.file_exists(path) else "No saved game found."}


## Round 34: every save slot with its summary, for the main menu / pause
## menu Load screen. [{slot, path, ok, day, saved_at, message}]
func list_slots() -> Array:
	var out: Array = []
	for spec in [["manual", save_path], ["autosave", autosave_path]]:
		var r: Dictionary = read_save(spec[1])
		var e := {"slot": spec[0], "path": spec[1], "ok": r["ok"], "message": r.get("message", "")}
		if r["ok"]:
			e["day"] = int(r["data"].get("day", 0))
			e["saved_at"] = float(r["data"].get("saved_at", 0.0))
			e["from_backup"] = r.get("from_backup", false)
		out.append(e)
	return out


## The newest valid slot (Continue), or {}.
func latest_slot() -> Dictionary:
	var best := {}
	for e in list_slots():
		if e["ok"] and (best.is_empty() or e["saved_at"] > best["saved_at"]):
			best = e
	return best


## Queue a validated save for the NEXT station scene (main menu path).
static func queue_load(data: Dictionary) -> void:
	_pending_load = data


## UI entry point: reload the station and restore the save into it.
## Round 34 ROOT-CAUSE FIX (load crash): the reload used to run
## synchronously INSIDE the workstation's _unhandled_input -- the old scene
## was torn down while its own input callback was still executing
## (get_viewport() == null, out-of-tree transform reads, then a hard crash
## in the renderer). The save is now fully read and validated first (a bad
## save never touches the running game), and the scene change is DEFERRED
## to after input dispatch, guarded against re-entry.
func load_game(path: String = "") -> Dictionary:
	if _scene_change_pending:
		return {"ok": false, "message": "Already loading."}
	var r: Dictionary = read_save(path)
	if not r["ok"]:
		last_message = "Load failed: " + r["message"]
		_show(last_message)
		return {"ok": false, "message": last_message}
	_pending_load = r["data"]
	if r.get("from_backup", false):
		_pending_load["_note"] = r["message"]
	_pending_load["_save_path"] = save_path
	_pending_load["_autosave_path"] = autosave_path
	_scene_change_pending = true
	last_message = "Loading…"
	_change_scene_deferred.call_deferred()
	return {"ok": true, "message": last_message}


var _scene_change_pending: bool = false


func _change_scene_deferred() -> void:
	get_tree().reload_current_scene()


## UI entry point: a fresh station. Never touches the save file -- the
## existing save is only replaced when the player explicitly saves again.
func new_game() -> void:
	if _scene_change_pending:
		return
	_pending_load = {}
	GameFlow.start_mode = "new_game"
	_pending_message = "New game started. Your previous save is untouched until you save again."
	_scene_change_pending = true
	_change_scene_deferred.call_deferred()


# ================================================================ collect
func collect_state() -> Dictionary:
	var main: Node = _main()
	var dp: Node = main.get_node("DayPlan")
	var d := {"schema": SCHEMA_VERSION, "game": GAME_ID, "day": dp.day_number}
	var dpd := {}
	for f in DAYPLAN_FIELDS + DAYPLAN_OPTIONAL:
		if f in dp:
			dpd[f] = _enc(dp.get(f))
	d["day_plan"] = dpd
	d["difficulty"] = int(GameSettings.get_difficulty())
	var eq := {}
	for id in EQUIPMENT:
		var n: Node = _find(EQUIPMENT[id][0])
		if n == null:
			continue
		var e := {}
		for f in EQUIPMENT[id][1]:
			e[f] = _enc(n.get(f))
		eq[id] = e
	d["equipment"] = eq
	var items: Array = []
	for it in _all_items():
		var rec_extra := {}
		if "payload" in it:
			rec_extra["payload"] = _enc(it.payload)
		items.append(rec_extra.merged({"id": String(it.name), "pid": _pid_of(it), "type": String(it.item_id), "cable": String(it.get("cable_type")) if it.get("cable_type") != null else "", "owner": _owner_of(it)}))
	d["items"] = items
	# Round 35: the new equipment (breakers, loads, vent, seal, data ports)
	# and the environment model.
	var eq2 := {}
	for n in get_tree().get_nodes_in_group(&"r35_equipment"):
		if n.has_method("state_dict"):
			eq2[String(n.name)] = _enc(n.state_dict())
	d["equipment2"] = eq2
	var env: Node = main.get_node_or_null("EnvironmentModel")
	if env != null:
		d["environment"] = _enc(env.state_dict())
	# Round 36: station assistant tutorial progress (what has been taught).
	var ai: Node = main.get_node_or_null("StationAI")
	if ai != null:
		d["station_ai"] = _enc(ai.state_dict())
	var housing: Node = _find("FilterHousingStation")
	d["station_used"] = String(housing._used_cartridge.name) if housing != null and is_instance_valid(housing._used_cartridge) and not housing._used_cartridge.is_queued_for_deletion() else ""
	var fb: Node3D = main.get_node("FreeMoveBody")
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	d["player"] = {"pos": _enc(fb.global_position), "yaw": player.rotation.y + lp.rotation.y, "pitch": lp.get_node("PitchPivot").rotation.x}
	var lv: Node = player.get_node_or_null("LaptopView")
	d["laptop"] = {"entry": lv._saved_entry if lv != null else "", "read": lv._log_screen.read_messages.keys() if lv != null and "read_messages" in lv._log_screen else [], "game_best": lv._log_screen.game_best if lv != null and "game_best" in lv._log_screen else 0,
		"cargo_drop": _enc(lv._log_screen._game.state_dict()) if lv != null and lv._log_screen.get("_game") != null else {},
		"holdout": lv._log_screen.holdout.state_dict() if lv != null and lv._log_screen.get("holdout") != null else {},
		"handover_read": lv._log_screen.handover_read.keys() if lv != null and "handover_read" in lv._log_screen else []}
	return d


func _owner_of(it: Node3D) -> Dictionary:
	var main: Node = _main()
	var carry: Node = main.get_node("Player/CarrySystem")
	if carry.is_holding(it):
		return {"kind": "held"}
	if it.has_method("is_installed") and it.is_installed():
		var housing: Node = _find("FilterHousingStation")
		return {"kind": "installed", "at": "filter_housing" if it.get_parent() == housing else "electrical_panel"}
	if it.has_method("is_carrier") and it.is_docked():
		return {"kind": "docked"}
	# Round 35: the data module seated in a capture/upload port.
	# Round 36: any item seated in an item dock (data ports, the thermal
	# probe dock) -- same owner kind, the dock node's name.
	if it.get_parent() != null and it.get_parent().get_parent() != null and it.get_parent().get_parent().is_in_group(&"item_dock"):
		return {"kind": "dataport", "at": String(it.get_parent().get_parent().name)}
	for car in get_tree().get_nodes_in_group(&"supply_carrier"):
		if car.contains(it):
			return {"kind": "carrier", "slot": _enc(car.cradle_index_of(it))}
	for cab in get_tree().get_nodes_in_group(&"storage_cabinet"):
		var i: int = cab.slot_index_of(it)
		if i != -1:
			return {"kind": "cabinet", "at": String(cab.name), "slot": _enc(i)}
	var crate: Node = _find("SupplyCrate")
	if crate != null and crate.slot_index_of(it) != -1:
		return {"kind": "reserve", "slot": _enc(crate.slot_index_of(it))}
	var port: Node = _find("CargoPort")
	if port != null and port.slot_index_of(it) != -1:
		return {"kind": "port", "slot": _enc(port.slot_index_of(it))}
	if it.item_id == &"used_filter_cartridge" and not it.is_ejected():
		return {"kind": "seated"}
	return {"kind": "loose", "xf": _enc(it.global_transform)}


# ================================================================== apply
## Restores `data` into the CURRENT (freshly loaded) station. {ok, message}
func apply_state(data: Dictionary) -> Dictionary:
	var v: Dictionary = validate(data)
	if not v["ok"]:
		return {"ok": false, "message": "Load failed: " + v["message"]}
	var main: Node = _main()
	var dp: Node = main.get_node("DayPlan")
	var carry: Node = main.get_node("Player/CarrySystem")
	var interactables: Node = main.get_node("Interactables")
	if carry.is_carrying():
		carry._carried_item = null
		carry._carried_item_id = &""
	# ---- 1. Items: reconcile the fresh scene's parts with the save. ----
	var by_name := {}
	for it in _all_items():
		by_name[_pid_of(it)] = it
	var wanted := {}
	for rec in data["items"]:
		wanted[_rec_pid(rec)] = rec
	for n in by_name.keys():
		if not wanted.has(n) and by_name[n].item_id != &"cargo_carrier":
			var gone: Node = by_name[n]
			gone.get_parent().remove_child(gone)
			gone.queue_free()          # consumed before the save
			by_name.erase(n)
	for rec in data["items"]:
		if not by_name.has(_rec_pid(rec)):
			by_name[_rec_pid(rec)] = _create_item(rec, interactables)
	# Park every part out of every container (so no stale slot claims).
	var port: Node = _find("CargoPort")
	if port != null:
		port.persist_clear()
	for n in by_name:
		var it: Node3D = by_name[n]
		if it.get_parent() != interactables:
			it.reparent(interactables, false)
		it.global_transform = Transform3D(Basis(), Vector3(0, -50, 0))
		it.visible = false
		var c: Node = it.get_node_or_null("Collision")
		if c != null:
			c.disabled = true
	# ---- 2. Equipment fields (stations), before owners that depend on them.
	for id in data["equipment"]:
		if not EQUIPMENT.has(id):
			continue
		var node: Node = _find(EQUIPMENT[id][0])
		if node == null:
			continue
		var e: Dictionary = data["equipment"][id]
		for f in e:
			if f in EQUIPMENT[id][1] and f in node:
				_set_field(node, f, _dec(e[f]))
	# ---- 3. Owners. ----
	var housing: Node = _find("FilterHousingStation")
	var panel: Node = _find("EngineeringCabinet1")
	var crate: Node = _find("SupplyCrate")
	var held: Node3D = null
	housing._installed_cartridge = null
	var ordered: Array = data["items"].filter(func(r): return r["owner"]["kind"] != "carrier") + data["items"].filter(func(r): return r["owner"]["kind"] == "carrier")
	var car: Node = port.carrier if port != null else null
	for rec in ordered:
		var it: Node3D = by_name[_rec_pid(rec)]
		var o: Dictionary = rec["owner"]
		match o["kind"]:
			"docked":
				it.dock(port, port.dock_global())
				it.visible = true
				var cc: Node = it.get_node_or_null("Collision")
				if cc != null:
					cc.disabled = false
			"dataport":
				var dport: Node = _find(o["at"])
				if dport != null:
					dport.seat(it)
			"carrier":
				it.visible = true
				car.put(it, _dec(o["slot"]))
				if car.is_docked():
					port.persist_track(it)
			"cabinet":
				var cab: Node = _find(o["at"])
				if cab == null or not cab.persist_place(it, _dec(o["slot"])):
					return {"ok": false, "message": "Load failed: %s has no slot %s." % [o["at"], str(_dec(o["slot"]))]}
			"reserve":
				crate.persist_place(it, _dec(o["slot"]))
			"port":
				port.persist_place(it, _dec(o["slot"]))
			"installed":
				if o["at"] == "filter_housing":
					it.mark_installed(housing, housing.installed_cartridge_local_transform())
					housing._installed_cartridge = it
				else:
					it.mark_installed(panel._terminal, panel.installed_wire_local_transform)
			"seated":
				it.reparent(housing._used_parent if housing._used_parent != null else interactables, false)
				it._ejected = false
				it.visible = false
			"loose":
				var xf: Transform3D = _dec(o["xf"])
				if it.item_id == &"used_filter_cartridge":
					it._ejected = true
				it.place_in_world(xf)
				it.global_transform = xf
				it.visible = true
				var c2: Node = it.get_node_or_null("Collision")
				if c2 != null:
					c2.disabled = false
				# Round 34: small loose parts never block the player.
				(it as CollisionObject3D).collision_layer = 1 if it.has_method("is_carrier") else 16
			"held":
				if it.item_id == &"used_filter_cartridge":
					it._ejected = true
				held = it
	if car != null and not wanted.has(String(car.name)):
		# Older save without the carrier: it starts docked, as on a new game.
		car.dock(port, port.dock_global())
		car.visible = true
		car.get_node("Collision").disabled = false
	# Round 35: data module payloads, new equipment, environment.
	for rec in data["items"]:
		if rec.has("payload") and by_name.has(_rec_pid(rec)):
			var dm: Node = by_name[_rec_pid(rec)]
			dm.payload = _dec(rec["payload"])
			dm.refresh()
	var eq2: Dictionary = data.get("equipment2", {})
	for n in get_tree().get_nodes_in_group(&"r35_equipment"):
		if eq2.has(String(n.name)) and n.has_method("load_dict"):
			n.load_dict(_dec(eq2[String(n.name)]))
	var envn: Node = main.get_node_or_null("EnvironmentModel")
	if envn != null and data.has("environment"):
		envn.load_dict(_dec(data["environment"]))
	var ain: Node = main.get_node_or_null("StationAI")
	if ain != null:
		if data.has("station_ai"):
			ain.load_dict(_dec(data["station_ai"]))
		else:
			ain.adopt_legacy_save(int(data["day"]))   # pre-Round-36 save
	var su: String = data.get("station_used", "")
	housing._used_cartridge = by_name.get(su, null) if su != "" else null
	# ---- 4. Visual snaps (no animation / sound). ----
	housing._sync_world_diorama()
	if panel._config_index >= 0:
		panel._apply_config(panel._config_index)
	panel._refresh_interior_visuals()
	var valve: Node = _find("ValveRoutingStation")
	if valve != null:
		valve._sync_world_diorama()
	if port != null:
		port.persist_refresh()
	for cab in get_tree().get_nodes_in_group(&"storage_cabinet"):
		cab.persist_refresh()
	if crate != null:
		crate.persist_refresh()
	# ---- 5. DayPlan (authoritative work orders; no re-arm is re-run). ----
	for f in data["day_plan"]:
		if (f in DAYPLAN_FIELDS or f in DAYPLAN_OPTIONAL) and f in dp:
			_set_field(dp, f, _dec(data["day_plan"][f]))
	GameSettings.set_difficulty(int(data.get("difficulty", 1)))
	# ---- 6. Player, laptop, hand. ----
	var fb: Node = main.get_node("FreeMoveBody")
	var player: Node3D = main.get_node("Player")
	var lp: Node3D = player.get_node("LookPivot")
	var pd: Dictionary = data["player"]
	fb.global_position = _dec(pd["pos"])
	fb.velocity = Vector3.ZERO
	player.global_position = fb.current_eye_position()
	lp.rotation.y = float(pd["yaw"]) - player.rotation.y
	lp._target_yaw = lp.rotation.y
	lp._target_pitch = float(pd["pitch"])
	lp.get_node("PitchPivot").rotation.x = float(pd["pitch"])
	var lv: Node = player.get_node_or_null("LaptopView")
	if lv != null:
		lv._saved_entry = String(data.get("laptop", {}).get("entry", ""))
		lv._log_screen.show_entry(lv._saved_entry)
		if "read_messages" in lv._log_screen:
			lv._log_screen.read_messages = {}
			for k in Array(data.get("laptop", {}).get("read", [])):
				lv._log_screen.read_messages[String(k)] = true
			lv._log_screen._refresh_unread()
		if "game_best" in lv._log_screen:
			lv._log_screen.game_best = int(data.get("laptop", {}).get("game_best", 0))
			lv._log_screen._game.best = lv._log_screen.game_best
			# Round 41: an unfinished Cargo Drop run comes back PAUSED (or a
			# clean restart if the snapshot does not validate).
			var cd: Dictionary = _dec(data.get("laptop", {}).get("cargo_drop", {}))
			if not cd.is_empty() and not lv._log_screen._game.load_state(cd):
				lv._log_screen._game.restart()
		# Round 45: which handover archive notes were read.
		if "handover_read" in lv._log_screen:
			lv._log_screen.handover_read = {}
			for k in Array(data.get("laptop", {}).get("handover_read", [])):
				lv._log_screen.handover_read[int(k)] = true
			lv._log_screen._refresh_unread()
		# Round 42: Holdout's own wallet / upgrades / best (never an active run).
		if lv._log_screen.get("holdout") != null:
			lv._log_screen.holdout.load_state(data.get("laptop", {}).get("holdout", {}))
	if held != null:
		held.visible = true
		carry.pick_up(held)
		if carry.is_reaching():
			carry.complete_grasp()
	dp.day_started.emit(dp.day_number)
	# Round 48: re-evaluate "is the technician up?" from the LOADED state (the
	# first frames before the load may have latched it from the menu scene's
	# standing default); the poll re-arms the clock next frame if up.
	if dp.has_method("begin_waking"):
		dp.begin_waking(false)
	# Round 34: an AUTOSAVE is the start of a day -> wake in the bunk. A
	# manual (mid-day) save restores the saved position exactly.
	if data.get("start_in_bed", false):
		var ss: Node = main.get_node_or_null("SleepState")
		if ss != null and ss.has_method("start_day_in_bed"):
			ss.start_day_in_bed()
	var note: String = data.get("_note", "")
	return {"ok": true, "message": ("%s " % note if note != "" else "") + "Progress loaded — Day %d." % int(data["day"])}


func _create_item(rec: Dictionary, parent: Node) -> Node3D:
	var t := StringName(rec["type"])
	var it: Node3D
	if t == &"used_filter_cartridge":
		it = _USED_SCENE.instantiate()
	elif t == &"filter_cartridge":
		it = _FILTER_SCENE.instantiate()
	else:
		it = _WIRE_SCENE.instantiate()
		it.item_id = t
		if rec.get("cable", "") == "signal" or t == &"wire_signal_22ga":
			it.cable_type = "signal"
	it.name = rec["id"]
	var main: Node = _main()
	it.carry_system_path = main.get_node("Player/CarrySystem").get_path()
	var ml: Node = main.get_node_or_null("Player/HUD/TaskMessageLabel")
	if ml != null:
		it.message_label_path = ml.get_path()
	parent.add_child(it)
	return it


# ============================================================= validation
func validate(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {"ok": false, "message": "not a save document"}
	if data.get("game", "") != GAME_ID:
		return {"ok": false, "message": "not a save for this game"}
	var ver: Variant = data.get("schema", null)
	if not (ver is float or ver is int):
		return {"ok": false, "message": "missing schema version"}
	if int(ver) > SCHEMA_VERSION:
		return {"ok": false, "message": "save schema %d is newer than this build supports (%d)" % [int(ver), SCHEMA_VERSION]}
	if int(ver) < 1:
		return {"ok": false, "message": "unsupported save schema %d" % int(ver)}
	for k in ["day", "day_plan", "equipment", "items", "player"]:
		if not data.has(k):
			return {"ok": false, "message": "missing '%s'" % k}
	if not (data["items"] is Array) or not (data["day_plan"] is Dictionary) or not (data["equipment"] is Dictionary):
		return {"ok": false, "message": "malformed sections"}
	var seen := {}
	var held := 0
	var slots := {}
	for rec in data["items"]:
		if not (rec is Dictionary) or not rec.has("id") or not rec.has("type") or not rec.has("owner"):
			return {"ok": false, "message": "malformed item record"}
		if seen.has(rec["id"]):
			return {"ok": false, "message": "item %s appears twice" % rec["id"]}
		seen[rec["id"]] = true
		if not KNOWN_TYPES.has(StringName(rec["type"])):
			return {"ok": false, "message": "unknown part type %s" % rec["type"]}
		var o: Variant = rec["owner"]
		if not (o is Dictionary) or not OWNER_KINDS.has(o.get("kind", "")):
			return {"ok": false, "message": "item %s has no valid owner" % rec["id"]}
		if o["kind"] == "held":
			held += 1
		if o["kind"] in ["cabinet", "reserve", "port"]:
			var key: String = "%s/%s/%s" % [o["kind"], o.get("at", ""), str(_dec(o.get("slot", -1)))]
			if slots.has(key):
				return {"ok": false, "message": "two parts claim %s" % key}
			slots[key] = true
		if o["kind"] == "loose" and not o.has("xf"):
			return {"ok": false, "message": "loose item %s has no position" % rec["id"]}
	if held > 1:
		return {"ok": false, "message": "more than one part in the hand"}
	var su: String = data.get("station_used", "")
	if su != "" and not seen.has(su):
		return {"ok": false, "message": "housing references missing part %s" % su}
	return {"ok": true, "message": ""}


func _parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "No saved game found."}
	var text: String = FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {"ok": false, "message": "save file is empty (incomplete write)"}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "message": "save file is corrupt (line %d: %s)" % [json.get_error_line(), json.get_error_message()]}
	var v: Dictionary = validate(json.data)
	if not v["ok"]:
		return v
	return {"ok": true, "data": json.data, "message": ""}


# =============================================================== encoding
func _enc(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return {"$i": str(v)}
		TYPE_STRING_NAME:
			return {"$sn": String(v)}
		TYPE_VECTOR3:
			return {"$v3": [v.x, v.y, v.z]}
		TYPE_TRANSFORM3D:
			var b: Basis = v.basis
			return {"$xf": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, v.origin.x, v.origin.y, v.origin.z]}
		TYPE_DICTIONARY:
			var pairs: Array = []
			for k in v:
				pairs.append([_enc(k), _enc(v[k])])
			return {"$d": pairs}
		TYPE_ARRAY:
			var out: Array = []
			for x in v:
				out.append(_enc(x))
			return out
		TYPE_NIL, TYPE_BOOL, TYPE_FLOAT, TYPE_STRING:
			return v
	return str(v)


func _dec(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("$i"):
			return int(v["$i"])
		if v.has("$sn"):
			return StringName(v["$sn"])
		if v.has("$v3"):
			var a: Array = v["$v3"]
			return Vector3(a[0], a[1], a[2])
		if v.has("$xf"):
			var t: Array = v["$xf"]
			return Transform3D(Basis(Vector3(t[0], t[1], t[2]), Vector3(t[3], t[4], t[5]), Vector3(t[6], t[7], t[8])), Vector3(t[9], t[10], t[11]))
		if v.has("$d"):
			var d := {}
			for p in v["$d"]:
				d[_dec(p[0])] = _dec(p[1])
			return d
		return v
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(_dec(x))
		return out
	return v


# ================================================================ helpers
## Typed arrays (e.g. Array[String]) silently reject set() with an untyped
## Array -- assign() into the existing typed array instead.
func _set_field(node: Object, f: String, value: Variant) -> void:
	var cur: Variant = node.get(f)
	if cur is Array and value is Array and (cur as Array).is_typed():
		(cur as Array).assign(value)
	else:
		node.set(f, value)


## Round 34: the persistent id of a part -- an explicit "persist_id" meta
## when present, else its (stable, deterministic) node name.
func _pid_of(it: Node) -> String:
	return String(it.get_meta(&"persist_id", String(it.name)))


func _rec_pid(rec: Dictionary) -> String:
	var pid: String = String(rec.get("pid", rec["id"]))
	return String(PID_ALIASES.get(pid, pid))


func _main() -> Node:
	return get_parent()


func _find(n: String) -> Node:
	return _main().find_child(n, true, false)


func _all_items() -> Array:
	var out: Array = []
	for it in _main().find_children("*", "", true, false):
		if "item_id" in it and it.has_method("return_to_rest") and not it.is_queued_for_deletion():
			out.append(it)
	return out


func _done_save(ok: bool, msg: String) -> Dictionary:
	last_message = msg
	_show(msg)
	saved.emit(ok, msg)
	return {"ok": ok, "message": msg}


func _show(msg: String) -> void:
	var ml: Label = _main().get_node_or_null("Player/HUD/TaskMessageLabel")
	if ml == null:
		return
	preload("res://scripts/ui/hud_message.gd").show(ml, get_instance_id(), msg, 4.0)
