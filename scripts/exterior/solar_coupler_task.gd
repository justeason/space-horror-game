extends "res://scripts/exterior/solar_task_base.gd"
## Round 41 Priority 6, TASK A -- SOLAR POWER COUPLER SERVICE (wing root).
## Each wing root carries a power coupler housing on the truss (by ring
## L1 / R1): inspection window, ISOLATE lever (string disconnect), a
## retaining LATCH over the connector, the connector PLUG, a TEST button
## with a continuity lamp.
## Faults (from the work order's seed, saved, never re-rolled):
##   "loose"    -- the connector has backed off: output 35 % of the wing;
##   "degraded" -- scorched contacts: output 55 %; needs a new insert.
## Procedure (all at the coupler worksite: tether on L1/R1, stabilised):
##   inspect window -> ISOLATE (wing output 0: the string is safe) -> open
##   LATCH -> pull PLUG -> (degraded: fit new insert) -> seat PLUG -> close
##   LATCH -> re-energise (ISOLATE off) -> TEST (continuity) -> back in ->
##   VERIFY OUTPUT on the Engineering power panel (SOLAR button).
## SAFETY: the latch / plug refuse while the string is LIVE; re-energising
## refuses with the latch open or the plug out.

const POS := {"L": Vector3(-7.3, 1.37, -5.2), "R": Vector3(1.85, 1.37, -5.2)}
const RING := {"L": "L1", "R": "R1"}

var fault: String = "ok"          # ok | loose | degraded
var inspected: bool = false
var isolated: bool = false
var latch_open: bool = false
var plug_out: bool = false
var insert_new: bool = false
var tested: bool = true
var _parts: Dictionary = {}       # wing -> {window, iso, latch, plug, test lamps/nodes}


func _ready() -> void:
	_solar_ready(&"solar_coupler")
	for w in ["L", "R"]:
		_build(w)
	_refresh()


func _build(w: String) -> void:
	var root := Node3D.new()
	root.name = "Coupler" + w
	root.position = POS[w]
	add_child(root)
	box(Vector3(0.52, 0.14, 0.32), Vector3(0, 0.07, 0), Color(0.82, 0.82, 0.8), root)
	box(Vector3(0.54, 0.02, 0.34), Vector3(0, 0.145, 0), Color(0.9, 0.6, 0.12), root)
	label("SOLAR PWR COUPLER %s" % w, Vector3(0, 0.158, 0.12), 26, Color(0.12, 0.12, 0.12), root).rotation_degrees.x = -90.0
	var win := lamp(Vector3(-0.17, 0.16, 0.05), root, 0.022)
	part(&"window", Vector3(0.08, 0.06, 0.08), Vector3(-0.17, 0.17, 0.05), root)
	# Isolation lever (pivot) + label.
	var iso := Node3D.new()
	iso.position = Vector3(0.18, 0.16, 0.06)
	root.add_child(iso)
	box(Vector3(0.025, 0.1, 0.025), Vector3(0, 0.05, 0), Color(0.9, 0.2, 0.15), iso)
	label("ISOLATE", Vector3(0.18, 0.158, 0.13), 18, Color(0.12, 0.12, 0.12), root).rotation_degrees.x = -90.0
	part(&"isolate", Vector3(0.08, 0.14, 0.08), Vector3(0.18, 0.2, 0.06), root)
	var iso_lamp := lamp(Vector3(0.18, 0.16, -0.06), root, 0.014)
	# Connector plug + retaining latch.
	var plug := Node3D.new()
	plug.position = Vector3(0.0, 0.15, -0.02)
	root.add_child(plug)
	var pc := CSGCylinder3D.new()
	pc.radius = 0.045
	pc.height = 0.09
	pc.position.y = 0.045
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.25, 0.26, 0.28)
	pm.metallic = 0.5
	pc.material = pm
	plug.add_child(pc)
	var ring := CSGCylinder3D.new()
	ring.radius = 0.05
	ring.height = 0.015
	ring.position.y = 0.02
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.75, 0.55, 0.25)
	rm.metallic = 0.8
	ring.material = rm
	plug.add_child(ring)
	part(&"plug", Vector3(0.1, 0.12, 0.1), Vector3(0, 0.2, -0.02), root)
	var latch := Node3D.new()
	latch.position = Vector3(-0.08, 0.25, -0.02)
	root.add_child(latch)
	box(Vector3(0.16, 0.02, 0.03), Vector3(0.08, 0, 0), Color(0.75, 0.77, 0.8), latch, 0.7)
	part(&"latch", Vector3(0.2, 0.06, 0.08), Vector3(0, 0.26, -0.02), root)
	label("LATCH", Vector3(0.0, 0.158, -0.13), 18, Color(0.12, 0.12, 0.12), root).rotation_degrees.x = -90.0
	# Test button + continuity lamp.
	box(Vector3(0.05, 0.02, 0.05), Vector3(-0.17, 0.16, -0.08), Color(0.2, 0.55, 0.3), root)
	part(&"test", Vector3(0.08, 0.06, 0.08), Vector3(-0.17, 0.17, -0.08), root)
	var test_lamp := lamp(Vector3(-0.1, 0.16, -0.08), root, 0.014)
	label("TEST", Vector3(-0.17, 0.158, -0.13), 18, Color(0.12, 0.12, 0.12), root).rotation_degrees.x = -90.0
	_ext_layers(root)
	_hw[w] = root
	_parts[w] = {"win": win, "iso": iso, "iso_lamp": iso_lamp, "plug": plug, "latch": latch, "test_lamp": test_lamp}
	var x: float = POS[w].x
	_worksite.call_deferred("coupler_" + w, self, Vector3(x + 0.35, Graph.RAIL_Y, Graph.RAIL_Z + 0.06), Vector3(x, 2.15, -4.5), POS[w] + Vector3(0, 0.15, 0), RING[w], "COUPLER " + w)


# ------------------------------------------------------------------ model
func wing_factor(w: String) -> float:
	if w != wing:
		return 1.0
	if isolated:
		return 0.0
	match fault:
		"loose": return 0.35
		"degraded": return 0.55
	return 0.0 if plug_out else 1.0


func repaired() -> bool:
	return fault == "ok" and tested and not isolated and not latch_open and not plug_out


# -------------------------------------------------------------- interaction
func on_part(id: StringName) -> void:
	if not at_site("coupler_" + wing):
		if outside():
			say("Grab the coupler handhold first (tether on %s)." % RING[wing])
		else:
			say("The coupler is outside on the truss.")
		return
	match id:
		&"window":
			inspected = true
			sfx(&"click")
			match fault:
				"loose": say("Connector backed off its seat.")
				"degraded": say("Contacts scorched — needs a new insert.")
				_: say("Connector seated, contacts clean.")
		&"isolate":
			if not isolated:
				isolated = true
				sfx(&"clunk")
				say("String %s isolated — coupler safe to service." % wing)
			else:
				if latch_open or plug_out:
					sfx(&"fail")
					say("Close the latch and seat the plug before re-energising.")
					return
				isolated = false
				sfx(&"clunk")
				say("String %s re-energised." % wing)
		&"latch":
			if not isolated:
				sfx(&"fail")
				say("Coupler is LIVE — isolate the string first.")
				ai_event(&"coupler_live")
				return
			if latch_open and plug_out:
				sfx(&"fail")
				say("Seat the plug before closing the latch.")
				return
			latch_open = not latch_open
			sfx(&"latch")
			say("Latch %s." % ("open" if latch_open else "closed and locked"))
		&"plug":
			if not isolated:
				sfx(&"fail")
				say("Coupler is LIVE — isolate the string first.")
				ai_event(&"coupler_live")
				return
			if not latch_open:
				sfx(&"fail")
				say("Open the retaining latch first.")
				return
			if not plug_out:
				plug_out = true
				sfx(&"insert")
				say("Plug out.")
			elif fault == "degraded" and not insert_new:
				insert_new = true
				sfx(&"ratchet")
				say("New contact insert fitted.")
			else:
				plug_out = false
				if fault != "ok":
					fault = "ok"
					tested = false
				sfx(&"insert")
				say("Plug seated.")
		&"test":
			if isolated or latch_open or plug_out:
				sfx(&"fail")
				say("Seat, latch and re-energise before testing.")
				return
			if fault == "ok":
				tested = true
				sfx(&"success")
				say("Continuity OK — coupler %s." % wing)
			else:
				sfx(&"fail")
				say("Continuity LOW — the connector is not making contact.")
	_refresh()


func part_prompt(id: StringName) -> String:
	if not outside():
		return ""
	if not at_site("coupler_" + wing):
		return "Grab the handhold to work"
	match id:
		&"window": return "Click: inspect the coupler"
		&"isolate": return "Click: %s" % ("re-energise string" if isolated else "ISOLATE string")
		&"latch": return "Click: %s latch" % ("close" if latch_open else "open")
		&"plug":
			if not plug_out:
				return "Click: pull the plug"
			return "Click: fit new insert" if fault == "degraded" and not insert_new else "Click: seat the plug"
		&"test": return "Click: continuity test"
	return ""


func _refresh() -> void:
	for w in ["L", "R"]:
		var p: Dictionary = _parts.get(w, {})
		if p.is_empty():
			continue
		var mine: bool = w == wing
		var f: String = fault if mine else "ok"
		set_lamp(p["win"], Color(1.0, 0.6, 0.15) if f != "ok" else Color(0.3, 0.9, 0.4), true)
		var iso: bool = mine and isolated
		(p["iso"] as Node3D).rotation_degrees.z = -80.0 if iso else 0.0
		set_lamp(p["iso_lamp"], Color(0.3, 0.6, 1.0) if iso else Color(0.9, 0.4, 0.1), true)
		(p["latch"] as Node3D).rotation_degrees.z = 75.0 if (mine and latch_open) else 0.0
		(p["plug"] as Node3D).position.y = 0.15 + (0.12 if (mine and plug_out) else (0.02 if f == "loose" else 0.0))
		var ok: bool = not mine or (tested and fault == "ok")
		set_lamp(p["test_lamp"], Color(0.3, 0.95, 0.4) if ok else Color(0.5, 0.5, 0.5), ok)


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	wing = ["L", "R"][rng.randi() % 2]
	fault = ["loose", "degraded"][rng.randi() % 2]
	inspected = false
	isolated = false
	latch_open = false
	plug_out = false
	insert_new = false
	tested = false
	request_day = _today()
	verified_day = -1
	_refresh()


func order_done() -> bool:
	return request_day != -1 and repaired() and verified_day >= request_day


func order_next() -> Dictionary:
	if not repaired():
		var site: String = "coupler_" + wing
		var step: Dictionary
		if not at_site(site):
			step = {"action": "Clip to %s, grab the coupler handhold" % RING[wing], "short": "TO COUPLER %s" % wing, "room": &"airlock"}
		elif not inspected:
			step = {"action": "Inspect the coupler window", "short": "INSPECT", "room": &"airlock"}
		elif fault != "ok" and not isolated:
			step = {"action": "Isolate the string", "short": "ISOLATE", "room": &"airlock"}
		elif fault != "ok" and not latch_open:
			step = {"action": "Open the retaining latch", "short": "OPEN LATCH", "room": &"airlock"}
		elif fault != "ok":
			step = {"action": "Pull / fit insert / seat the plug", "short": "RESEAT PLUG", "room": &"airlock"}
		elif plug_out:
			step = {"action": "Seat the plug", "short": "SEAT PLUG", "room": &"airlock"}
		elif latch_open:
			step = {"action": "Close and lock the latch", "short": "CLOSE LATCH", "room": &"airlock"}
		elif isolated:
			step = {"action": "Re-energise the string", "short": "RE-ENERGISE", "room": &"airlock"}
		else:
			step = {"action": "Run the continuity test", "short": "TEST", "room": &"airlock"}
		return _route_step(step, RING[wing])
	if outside():
		return {"action": "Return along the truss, press IN", "short": "AIRLOCK IN", "room": &"airlock"}
	return {"action": "Power panel: press SOLAR to verify output", "short": "VERIFY OUTPUT", "room": &"engineering"}


func order_progress() -> String:
	return "%.1f kW" % (_arrays.wing_output(wing) if _arrays != null else 0.0)


func order_detail() -> Array:
	return ["Solar power coupler, wing %s root (truss ring %s)." % [wing, RING[wing]], "Wing %s output %.1f of %.1f kW." % [wing, _arrays.wing_output(wing) if _arrays != null else 0.0, 6.0], "Isolate before touching the latch."]


func state_dict() -> Dictionary:
	return {"wing": wing, "fault": fault, "inspected": inspected, "isolated": isolated, "latch_open": latch_open, "plug_out": plug_out, "insert_new": insert_new, "tested": tested, "request_day": request_day, "verified_day": verified_day}


func load_dict(d: Dictionary) -> void:
	wing = String(d.get("wing", "L"))
	fault = String(d.get("fault", "ok"))
	inspected = bool(d.get("inspected", false))
	isolated = bool(d.get("isolated", false))
	latch_open = bool(d.get("latch_open", false))
	plug_out = bool(d.get("plug_out", false))
	insert_new = bool(d.get("insert_new", false))
	tested = bool(d.get("tested", true))
	request_day = int(d.get("request_day", -1))
	verified_day = int(d.get("verified_day", -1))
	_refresh()
