extends "res://scripts/deck_b/deck_b_room.gd"
## Round 49: Deck A (Engineering) equipment that belongs to the shared
## systems Deck B introduced -- the design-bible gaps E09 / E10 / E11:
##   BUS B TRANSFER panel (Engineering east wall): FEED-1 (from Bus A's
##     ENG-AUX) and FEED-2 (essential bus) status, the FEED-1 contactor's
##     state lamp and a DROPOUT counter (an INTERMITTENT fault shows itself
##     only now and then -- E09), the B2 (lab / archive) SOURCE transfer
##     switch (E10 power rerouting on the real bus model), FEED-2 load vs
##     rating, and the contactor's socket (a relay module is a real part).
##   BATTERY THERMAL MONITOR (on the battery bank housing): battery
##     temperature from the coolant loop's V1 branch, charge current, a
##     CHARGE LIMIT switch (100 % / 50 %) that really lowers the battery's
##     heat load. [e11_battery]: mitigate here, fix the cooling at B-03.

var charge_limit: float = 1.0
var batt_read: bool = false
var limit_used: bool = false
var e11_ok_s: float = 0.0
var bus_read: bool = false
var drops: int = 0
var _was_drop: bool = false

var _bus_lbl: Label3D
var _src_lever: Node3D
var _f1_lamp: StandardMaterial3D
var _batt_lbl: Label3D
var _limit_sw: Node3D


func _ready() -> void:
	room_id = &"engineering"
	_room_ready([&"e11_battery"])
	_build_transfer()
	_build_battery()
	_refresh()


func _layer_a(n: Node) -> void:
	for c in n.get_children():
		if c is VisualInstance3D:
			(c as VisualInstance3D).layers = 1
		_layer_a(c)


func _build_transfer() -> void:
	var p := Node3D.new()
	p.name = "BusBTransfer"
	p.position = Vector3(-2.69, 1.4, 4.75)
	p.rotation_degrees.y = -90.0          # faces -x into Engineering
	add_child(p)
	dbox(Vector3(0.5, 0.5, 0.06), Vector3(0, 0, 0.03), Color(0.22, 0.24, 0.27), p)
	dbox(Vector3(0.52, 0.05, 0.07), Vector3(0, 0.27, 0.03), Color(0.95, 0.72, 0.1), p)
	text("BUS B TRANSFER · LOWER DECK FEEDS", Vector3(0, 0.3, 0.062), 9, Color(0.95, 0.95, 0.9), p)
	_bus_lbl = readout(Vector3(0, 0.08, 0.062), Vector2(0.44, 0.2), p, 8)
	var lm := dbox(Vector3(0.03, 0.03, 0.01), Vector3(-0.18, -0.12, 0.062), Color(0.2, 0.2, 0.2), p)
	_f1_lamp = lm.material_override
	text("FEED-1\nCONTACTOR", Vector3(-0.18, -0.18, 0.062), 7, Color(0.9, 0.9, 0.9), p)
	part(&"contactor", Vector3(0.1, 0.1, 0.06), Vector3(-0.18, -0.13, 0.07), p)
	_src_lever = Node3D.new()
	_src_lever.position = Vector3(0.1, -0.13, 0.065)
	p.add_child(_src_lever)
	dbox(Vector3(0.025, 0.1, 0.025), Vector3(0, 0.045, 0), Color(0.9, 0.3, 0.2), _src_lever)
	part(&"b2_source", Vector3(0.1, 0.14, 0.06), Vector3(0.1, -0.12, 0.08), p)
	text("B2 SOURCE\nFEED-1 ◄ ► FEED-2", Vector3(0.1, -0.21, 0.062), 7, Color(0.9, 0.9, 0.9), p)
	part(&"bus_read", Vector3(0.44, 0.2, 0.05), Vector3(0, 0.08, 0.07), p)
	_layer_a(p)


func _build_battery() -> void:
	var b := Node3D.new()
	b.name = "BatteryMonitor"
	b.position = Vector3(-5.29, 1.2, 6.05)
	b.rotation_degrees.y = 90.0           # faces +x
	add_child(b)
	dbox(Vector3(0.36, 0.26, 0.04), Vector3(0, 0, 0.02), Color(0.2, 0.22, 0.25), b)
	text("BATTERY BANK B-1 · THERMAL", Vector3(0, 0.16, 0.042), 8, Color(0.95, 0.95, 0.9), b)
	_batt_lbl = readout(Vector3(-0.04, 0.02, 0.042), Vector2(0.26, 0.14), b, 9)
	_limit_sw = Node3D.new()
	_limit_sw.position = Vector3(0.14, 0.0, 0.045)
	b.add_child(_limit_sw)
	dbox(Vector3(0.02, 0.05, 0.02), Vector3(0, 0.02, 0), Color(0.9, 0.9, 0.88), _limit_sw)
	part(&"charge_limit", Vector3(0.06, 0.1, 0.05), Vector3(0.14, 0.0, 0.06), b)
	text("CHARGE\nLIMIT", Vector3(0.14, -0.08, 0.042), 7, Color(0.9, 0.9, 0.9), b)
	part(&"batt_read", Vector3(0.26, 0.14, 0.05), Vector3(-0.04, 0.02, 0.06), b)
	_layer_a(b)


func on_part(id: StringName) -> void:
	var s: Node = sys()
	if s == null:
		return
	match String(id):
		"b2_source":
			s.power["b2_source"] = "F2" if s.power["b2_source"] == "F1" else "F1"
			sfx(&"clunk")
			say("B2 (lab / archive) now on %s. FEED-2 load %.2f / %.1f kW." % ["FEED-2" if s.power["b2_source"] == "F2" else "FEED-1", s.feed2_load(), s.FEED2_RATING])
		"contactor":
			if s.power["feed1_fault"] == "chatter":
				if held_kind() == &"relay_module" and String(held().payload.get("state", "")) != "repair":
					if s.power["b2_source"] == "F1":
						say("Transfer B2 to FEED-2 before replacing the FEED-1 contactor (it carries B2).")
						sfx(&"fail")
						return
					consume_part(held())
					s.power["feed1_fault"] = ""
					sfx(&"ratchet")
					say("FEED-1 contactor replaced. Watch it, then transfer B2 back.")
				else:
					say("FEED-1 contactor chattering (%d dropouts counted). A serviceable relay module RM-2 replaces it." % drops)
			else:
				say("FEED-1 contactor: closed, steady.")
		"bus_read":
			bus_read = true
			say("FEED-1 %s · dropouts %d · FEED-2 %.2f / %.1f kW" % ["DROPOUT" if s.power["dropout"] else "OK", drops, s.feed2_load(), s.FEED2_RATING])
		"charge_limit":
			charge_limit = 0.5 if charge_limit > 0.75 else 1.0
			s.thermal["charge_limit"] = charge_limit
			if charge_limit < 1.0:
				limit_used = true
			sfx(&"click")
			say("Battery charge limit %d %%" % int(charge_limit * 100.0))
		"batt_read":
			batt_read = true
			say("Battery %.1f °C (limit 33 °C) · charge %s" % [float(s.thermal["batt_T"]), "LIMITED 50 %" if charge_limit < 1.0 else "FULL"])
	_refresh()


func part_prompt(id: StringName) -> String:
	var s: Node = sys()
	match String(id):
		"b2_source":
			return "Click: transfer B2 to %s" % ("FEED-2" if s != null and s.power["b2_source"] == "F1" else "FEED-1")
		"contactor":
			return "Click: FEED-1 contactor"
		"bus_read":
			return "Click: read the Bus B feeds"
		"charge_limit":
			return "Click: battery charge limit (%d %%)" % int(charge_limit * 100.0)
		"batt_read":
			return "Click: read the battery temperature"
	return ""


func _process(delta: float) -> void:
	var s: Node = sys()
	if s == null:
		return
	if s.power["dropout"] and not _was_drop:
		drops += 1
	_was_drop = s.power["dropout"]
	if has_open(&"e11_battery") and float(s.thermal["batt_T"]) < 31.0 and charge_limit >= 1.0 and limit_used:
		e11_ok_s += delta
	else:
		e11_ok_s = 0.0
	if Engine.get_process_frames() % 6 == 0:
		_refresh()


func _refresh() -> void:
	var s: Node = sys()
	if s == null:
		return
	if _bus_lbl != null:
		_bus_lbl.text = "FEED-1 ENG-AUX  %s\nFEED-2 ESS      %.2f / %.1f kW\nB1 %s  B2 %s (%s)\nB3 %s  B4 %s   DROPOUTS %d" % [
			"DROPOUT" if s.power["dropout"] else ("INTERMITTENT" if s.power["feed1_fault"] == "chatter" and drops > 0 else "OK"), s.feed2_load(), s.FEED2_RATING,
			"ON" if s.powered(0) else "OFF", "ON" if s.powered(1) else "OFF", "F1" if s.power["b2_source"] == "F1" else "F2", "ON" if s.powered(2) else "OFF", "ON" if s.powered(3) else "OFF", drops]
	light(_f1_lamp, Color(1.0, 0.6, 0.1) if s.power["dropout"] else Color(0.3, 0.95, 0.4), true)
	if _src_lever != null:
		_src_lever.rotation_degrees.z = -35.0 if s.power["b2_source"] == "F2" else 35.0
	if _batt_lbl != null:
		var bt: float = float(s.thermal["batt_T"])
		_batt_lbl.text = "TEMP %.1f °C  %s\nCHARGE %s\nCOOLANT V1 RET %.1f °C" % [bt, "HIGH" if bt > 33.0 else "OK", "50 %" if charge_limit < 1.0 else "100 %", float(s.thermal["ret_eng"])]
	if _limit_sw != null:
		_limit_sw.rotation_degrees.x = 30.0 if charge_limit < 1.0 else -30.0


func task_rearm(t: StringName, _seed: int) -> void:
	var s: Node = sys()
	if t == &"e11_battery" and s != null:
		if float(s.thermal["batt_T"]) < 33.0:
			# The developer / a re-raise: V1 left nearly closed after work.
			s.thermal["v1"] = 0.0
			s.thermal["batt_T"] = 34.5
		batt_read = false
		limit_used = false
		e11_ok_s = 0.0


func task_done(t: StringName) -> bool:
	if t != &"e11_battery":
		return true
	var done: bool = batt_read and e11_ok_s >= 5.0
	if done and not outcome.has(t):
		var s: Node = sys()
		close_task(t, "repaired", "battery bank B-1 / coolant V1", "battery over temperature (cooling)", "charge limited, V1 branch restored at B-03, charge restored", "battery %.1f °C" % float(s.thermal["batt_T"]))
	return done


func task_next(t: StringName) -> Dictionary:
	var s: Node = sys()
	if t != &"e11_battery":
		return {}
	if not batt_read:
		return {"action": "Read the battery temperature (Engineering, battery bank)", "short": "READ BATT", "room": &"engineering"}
	if not limit_used:
		return {"action": "Limit the battery charge to 50 %", "short": "LIMIT CHG", "room": &"engineering"}
	if s != null and float(s.thermal["batt_T"]) >= 31.0:
		return {"action": "Restore battery cooling: V1 branch at Thermal Control (B-03)", "short": "FIX V1", "room": &"b03"}
	return {"action": "Restore full charge and confirm the battery stays below 31 °C", "short": "RESTORE", "room": &"engineering"}


func task_severity(_t: StringName) -> int:
	var s: Node = sys()
	return 3 if s != null and float(s.thermal["batt_T"]) > 36.0 else 2


func state_dict() -> Dictionary:
	return {"charge_limit": charge_limit, "batt_read": batt_read, "limit_used": limit_used, "drops": drops, "outcome": outcome.duplicate()}


func load_dict(d: Dictionary) -> void:
	charge_limit = float(d.get("charge_limit", 1.0))
	batt_read = bool(d.get("batt_read", false))
	limit_used = bool(d.get("limit_used", false))
	drops = int(d.get("drops", 0))
	outcome = {}
	for ok in d.get("outcome", {}):
		outcome[StringName(ok)] = d["outcome"][ok]
	var s: Node = sys()
	if s != null:
		s.thermal["charge_limit"] = charge_limit
	_refresh()
