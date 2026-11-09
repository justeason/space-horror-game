extends "res://scripts/exterior/solar_task_base.gd"
## Round 41 Priority 6, TASK B -- SOLAR ARRAY HINGE / LATCH INSPECTION
## (mid-wing structural attachment, by ring L3 / R3).
## A hinge-latch assembly on the truss holds the mid-wing panel section's
## deployment hinge: a LATCH lever, a retaining FASTENER, a service
## BRACKET and a red/green deployment-lock INDICATOR flag.
## Fault variants (seeded by the order, saved):
##   "latch"    -- partially disengaged latch: open it fully, then seat+lock;
##   "fastener" -- loose retaining fastener: three ratchet turns;
##   "bracket"  -- misaligned bracket: release it, then align+lock.
## Consequence: an unlocked section reports RESTRICTED DEPLOYMENT -- the
## north panel section at the hinge visibly sits 7 deg off-plane (a small,
## static, controlled offset -- never uncontrolled motion) and the wing
## gives 78 % output. Fixing + a final INSPECT of the indicator (mechanical
## state verified) restores the section flat and the full output.
## All work happens STABILISED at the hinge worksite (tether on L3 / R3).

const POS := {"L": Vector3(-15.35, 1.37, -5.2), "R": Vector3(9.95, 1.37, -5.2)}
const RING := {"L": "L3", "R": "R3"}
const TILT_DEG := 7.0

var variant: String = "ok"        # ok | latch | fastener | bracket (what is wrong NOW)
var fault_kind: String = ""       # the fault this order had (for the record)
var stage: int = 0                # progress within the variant's fix
var inspected: bool = false
var mech_verified: bool = true
var _parts: Dictionary = {}
var _tilt: float = 0.0


func _ready() -> void:
	_solar_ready(&"solar_hinge")
	for w in ["L", "R"]:
		_build(w)
	_refresh()


func _build(w: String) -> void:
	var root := Node3D.new()
	root.name = "Hinge" + w
	root.position = POS[w]
	add_child(root)
	box(Vector3(0.46, 0.12, 0.3), Vector3(0, 0.06, 0), Color(0.55, 0.57, 0.6), root, 0.6)
	label("HINGE LATCH H-%s3" % w, Vector3(0, 0.125, 0.12), 24, Color(0.95, 0.85, 0.4), root).rotation_degrees.x = -90.0
	# Latch lever (pivots about z).
	var latch := Node3D.new()
	latch.position = Vector3(-0.14, 0.13, 0.0)
	root.add_child(latch)
	box(Vector3(0.14, 0.025, 0.04), Vector3(0.07, 0, 0), Color(0.85, 0.85, 0.82), latch, 0.6)
	part(&"latch", Vector3(0.18, 0.08, 0.1), Vector3(-0.08, 0.15, 0.0), root)
	# Retaining fastener (bolt head that turns).
	var bolt := Node3D.new()
	bolt.position = Vector3(0.1, 0.13, 0.07)
	root.add_child(bolt)
	var hx := CSGCylinder3D.new()
	hx.radius = 0.025
	hx.height = 0.03
	hx.sides = 6
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.7, 0.72, 0.75)
	bm.metallic = 0.85
	hx.material = bm
	bolt.add_child(hx)
	box(Vector3(0.01, 0.034, 0.03), Vector3.ZERO, Color(0.95, 0.75, 0.15), bolt)   # index mark
	part(&"fastener", Vector3(0.07, 0.07, 0.07), Vector3(0.1, 0.15, 0.07), root)
	# Service bracket (slides / skews when misaligned).
	var bracket := Node3D.new()
	bracket.position = Vector3(0.1, 0.13, -0.07)
	root.add_child(bracket)
	box(Vector3(0.12, 0.02, 0.06), Vector3.ZERO, Color(0.4, 0.42, 0.45), bracket, 0.6)
	part(&"bracket", Vector3(0.14, 0.06, 0.08), Vector3(0.1, 0.15, -0.07), root)
	# Deployment-lock indicator flag.
	var flag := box(Vector3(0.05, 0.08, 0.01), Vector3(0.2, 0.18, 0.0), Color(0.3, 0.9, 0.4), root)
	part(&"flag", Vector3(0.08, 0.12, 0.06), Vector3(0.2, 0.18, 0.0), root)
	label("LOCK", Vector3(0.2, 0.125, 0.06), 16, Color(0.95, 0.95, 0.9), root).rotation_degrees.x = -90.0
	_ext_layers(root)
	_hw[w] = root
	_parts[w] = {"latch": latch, "bolt": bolt, "bracket": bracket, "flag": flag}
	var x: float = POS[w].x
	_worksite.call_deferred("hinge_" + w, self, Vector3(x - 0.35, Graph.RAIL_Y, Graph.RAIL_Z + 0.06), Vector3(x, 2.1, -4.5), POS[w] + Vector3(0, 0.15, 0), RING[w], "HINGE " + w)


func wing_factor(w: String) -> float:
	return 0.78 if (w == wing and variant != "ok") else 1.0


func repaired() -> bool:
	return variant == "ok" and mech_verified


func restricted() -> bool:
	return variant != "ok"


func on_part(id: StringName) -> void:
	if not at_site("hinge_" + wing):
		say("Grab the hinge handhold first (tether on %s)." % RING[wing] if outside() else "The hinge is outside, mid-wing.")
		return
	match id:
		&"flag":
			inspected = true
			sfx(&"click")
			if variant == "ok":
				if not mech_verified:
					mech_verified = true
					sfx(&"success")
					say("Deployment lock GREEN — section %s locked." % wing)
				else:
					say("Deployment lock green.")
			else:
				say({"latch": "Latch only partly engaged.", "fastener": "Retaining fastener loose.", "bracket": "Service bracket out of line."}[variant])
		&"latch":
			if variant != "latch":
				say("Latch secure.")
				return
			stage += 1
			sfx(&"latch")
			if stage >= 2:
				_fixed()
				say("Latch seated and locked.")
			else:
				say("Latch fully open — now seat it.")
		&"fastener":
			if variant != "fastener":
				say("Fastener tight.")
				return
			stage += 1
			sfx(&"ratchet")
			if stage >= 3:
				_fixed()
				say("Fastener torqued.")
			else:
				say("Turn %d/3." % stage)
		&"bracket":
			if variant != "bracket":
				say("Bracket aligned.")
				return
			stage += 1
			sfx(&"clunk")
			if stage >= 2:
				_fixed()
				say("Bracket aligned and locked.")
			else:
				say("Bracket released — align it.")
	_refresh()


func _fixed() -> void:
	variant = "ok"
	stage = 0
	mech_verified = false          # the final indicator check verifies it


func part_prompt(id: StringName) -> String:
	if not outside():
		return ""
	if not at_site("hinge_" + wing):
		return "Grab the handhold to work"
	match id:
		&"flag": return "Click: inspect the lock indicator"
		&"latch": return "Click: work the latch"
		&"fastener": return "Click: turn the fastener"
		&"bracket": return "Click: work the bracket"
	return ""


func _process(delta: float) -> void:
	var goal: float = TILT_DEG if restricted() else 0.0
	if absf(_tilt - goal) > 0.01:
		_tilt = move_toward(_tilt, goal, delta * 4.0)
		_apply_tilt()


func _apply_tilt() -> void:
	if _arrays == null:
		return
	for w in ["L", "R"]:
		var sec: Node3D = _section(w)
		if sec != null:
			sec.rotation_degrees.x = (-_tilt if w == wing else 0.0)


## The north panel section at this wing's hinge.
func _section(w: String) -> Node3D:
	var best: Node3D = null
	for s in _arrays.sections[w]:
		var n: Node3D = s
		if not String(n.name).ends_with("N"):
			continue
		if best == null or absf(n.position.x - POS[w].x) < absf(best.position.x - POS[w].x):
			best = n
	return best


func section_tilt() -> float:
	var sec: Node3D = _section(wing) if _arrays != null else null
	return absf(sec.rotation_degrees.x) if sec != null else 0.0


func _refresh() -> void:
	for w in ["L", "R"]:
		var p: Dictionary = _parts.get(w, {})
		if p.is_empty():
			continue
		var v: String = variant if w == wing else "ok"
		(p["latch"] as Node3D).rotation_degrees.z = (35.0 if stage == 0 else 80.0) if v == "latch" else 0.0
		(p["bolt"] as Node3D).position.y = 0.13 + (0.025 - 0.008 * stage if v == "fastener" else 0.0)
		(p["bolt"] as Node3D).rotation_degrees.y = 40.0 * stage
		(p["bracket"] as Node3D).rotation_degrees.y = (14.0 if stage == 0 else 6.0) if v == "bracket" else 0.0
		var flag: CSGBox3D = p["flag"]
		(flag.material as StandardMaterial3D).albedo_color = Color(0.3, 0.9, 0.4) if v == "ok" else Color(0.95, 0.25, 0.15)
	_apply_tilt()


func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	wing = ["L", "R"][rng.randi() % 2]
	variant = ["latch", "fastener", "bracket"][rng.randi() % 3]
	fault_kind = variant
	stage = 0
	inspected = false
	mech_verified = false
	request_day = _today()
	verified_day = -1
	_refresh()


func order_done() -> bool:
	return request_day != -1 and repaired()


func order_next() -> Dictionary:
	if repaired():
		return {"action": "Return to the airlock", "short": "AIRLOCK IN", "room": &"airlock"}
	var step: Dictionary
	if not at_site("hinge_" + wing):
		step = {"action": "Clip to %s, grab the hinge handhold" % RING[wing], "short": "TO HINGE %s" % wing, "room": &"airlock"}
	elif not inspected:
		step = {"action": "Inspect the lock indicator", "short": "INSPECT", "room": &"airlock"}
	elif variant != "ok":
		step = {"action": {"latch": "Open the latch fully, then seat it", "fastener": "Torque the fastener (3 turns)", "bracket": "Release, then align the bracket"}[variant], "short": {"latch": "SEAT LATCH", "fastener": "TORQUE", "bracket": "ALIGN BRACKET"}[variant], "room": &"airlock"}
	else:
		step = {"action": "Inspect the lock indicator again", "short": "VERIFY LOCK", "room": &"airlock"}
	return _route_step(step, RING[wing])


func order_progress() -> String:
	return "LOCKED" if repaired() else ("RESTRICTED" if restricted() else "VERIFY")


func order_detail() -> Array:
	return ["Hinge latch H-%s3, mid-wing (truss ring %s)." % [wing, RING[wing]], "Section deployment: %s. Wing %s output %.1f kW." % ["RESTRICTED" if restricted() else "locked", wing, _arrays.wing_output(wing) if _arrays != null else 0.0]]


func state_dict() -> Dictionary:
	return {"wing": wing, "variant": variant, "fault_kind": fault_kind, "stage": stage, "inspected": inspected, "mech_verified": mech_verified, "request_day": request_day, "verified_day": verified_day}


func load_dict(d: Dictionary) -> void:
	wing = String(d.get("wing", "L"))
	variant = String(d.get("variant", "ok"))
	fault_kind = String(d.get("fault_kind", ""))
	stage = int(d.get("stage", 0))
	inspected = bool(d.get("inspected", false))
	mech_verified = bool(d.get("mech_verified", true))
	request_day = int(d.get("request_day", -1))
	verified_day = int(d.get("verified_day", -1))
	_tilt = TILT_DEG if restricted() else 0.0
	_refresh()
