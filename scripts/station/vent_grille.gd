extends "res://scripts/station/equipment_base.gd"
## Round 35 Priority 6: the LIFE SUPPORT VENTILATION GRILLE. A hinged
## cover held by two retaining clips over four duct sections. Each section
## has real DIRT (0..1), drawn as a debris layer whose opacity follows it.
## Cleaning is physical: open the cover, then scrub each dirty section
## (each click removes a third of its dirt, with a scrub sound) until it is
## visibly clean; close the cover and secure both clips. Efficiency (fed to
## the EnvironmentModel's airflow) = 1 - 0.4 x mean dirt. An airflow
## streamer + flow gauge beside the grille show it.

const SECTIONS := 4
var dirt: Array = [0.0, 0.0, 0.0, 0.0]
var clips_released: Array = [false, false]
var cover_open: bool = false
var airflow_checked: bool = true
var _dirt_mats: Array = []
var _cover: Node3D
var _clip_nodes: Array = []     # per clip: its pivot (Clip0 upper, Clip1 lower)
var _clip_levers: Array = []
## Round 36: clip pivots on the frame (just outside the cover's top/bottom
## edge, right of centre) and their fixed, generous click volumes.
const CLIP_PIVOTS := [Vector3(0.16, 0.232, 0.02), Vector3(0.16, -0.232, 0.02)]
const CLIP_CLICK_SIZE := Vector3(0.11, 0.1, 0.06)
const COVER_CLICK_H := 0.33
var _streamer: CSGBox3D
var _gauge: Label3D
var _cover_tween: Tween


func _ready() -> void:
	_base_ready(&"vent")
	box(Vector3(0.56, 0.54, 0.04), Vector3(0, 0, -0.04), Color(0.18, 0.2, 0.22))
	label("VENT LS-2", Vector3(-0.12, 0.29, 0.0), 16)
	for i in SECTIONS:
		var x: float = -0.12 + 0.24 * (i % 2)
		var y: float = 0.09 - 0.18 * (i / 2)
		box(Vector3(0.22, 0.16, 0.01), Vector3(x, y, -0.015), Color(0.08, 0.09, 0.1))
		for k in 4:
			box(Vector3(0.2, 0.012, 0.012), Vector3(x, y - 0.06 + 0.04 * k, -0.008), Color(0.35, 0.37, 0.4))
		var debris := box(Vector3(0.21, 0.15, 0.006), Vector3(x, y, -0.002), Color(0.32, 0.26, 0.18, 0.0))
		var m: StandardMaterial3D = debris.material
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dirt_mats.append(m)
		part(StringName("s%d" % i), Vector3(0.22, 0.16, 0.04), Vector3(x, y, 0.0))
	# Hinged cover (hinge on the left edge).
	_cover = Node3D.new()
	_cover.position = Vector3(-0.26, 0, 0.012)
	_cover.name = "Cover"
	add_child(_cover)
	var plate := box(Vector3(0.52, 0.42, 0.012), Vector3(0.26, 0, 0), Color(0.62, 0.65, 0.68, 0.55), _cover, 0.5)
	(plate.material as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in 6:
		box(Vector3(0.48, 0.014, 0.016), Vector3(0.26, -0.15 + 0.06 * k, 0.006), Color(0.7, 0.72, 0.75), _cover)
	# Round 36: the cover's click volume stops 3.5 cm short of the top and
	# bottom edges, so it can never sit in front of a retaining clip (it used
	# to swallow clicks aimed at the lower clip from a standing eye height --
	# and reopen the grille instead of latching it).
	part(&"cover", Vector3(0.5, COVER_CLICK_H, 0.024), Vector3(0.26, 0, 0.006), _cover)
	# Round 36: two TURN-LATCH retaining clips on the frame, top and bottom
	# (see CLIP_PIVOTS). Secured: the lever stands across the cover's edge,
	# in front of the plate (it physically holds it shut). Released: the
	# lever is turned 90 deg to lie along the frame, clear of the cover.
	# ONE fixed click volume per clip encloses BOTH lever poses, so the
	# target never drifts away from the visible hardware (it used to stay
	# 7 cm left of a released clip).
	for j in 2:
		var pivot := Node3D.new()
		pivot.name = "Clip%d" % j
		pivot.position = CLIP_PIVOTS[j]
		add_child(pivot)
		box(Vector3(0.036, 0.036, 0.02), Vector3(0, 0, -0.004), Color(0.25, 0.27, 0.3), pivot, 0.6)   # boss
		var arm := Node3D.new()
		arm.name = "Arm"
		pivot.add_child(arm)
		# The lever reaches 4.5 cm from the pivot toward the cover centre.
		var lever := box(Vector3(0.026, 0.062, 0.012), Vector3(0, -0.026 * _inward(j), 0.012), Color(0.85, 0.55, 0.1), arm)
		lever.name = "Lever"
		_clip_nodes.append(pivot)
		_clip_levers.append(lever)
		part(StringName("c%d" % j), CLIP_CLICK_SIZE, Vector3(0, -0.012 * _inward(j), 0.03), pivot)
	# Airflow streamer + gauge (right of the grille).
	box(Vector3(0.012, 0.012, 0.06), Vector3(0.34, 0.12, 0.0), Color(0.5, 0.5, 0.5))
	_streamer = box(Vector3(0.012, 0.11, 0.004), Vector3(0.34, 0.06, 0.03), Color(0.95, 0.85, 0.2))
	_gauge = label("", Vector3(0.36, -0.06, 0.0), 14, Color(0.55, 0.95, 0.75))
	part(&"gauge", Vector3(0.1, 0.28, 0.06), Vector3(0.35, 0.03, 0.02))
	_refresh()


## +1 for the upper clip (its lever points DOWN onto the cover), -1 lower.
static func _inward(j: int) -> float:
	return 1.0 if j == 0 else -1.0


## True when the clip's lever visibly overlaps the cover plate's edge
## (secured) -- measured from the real geometry, for tests and renders.
func clip_engaged_visual(j: int) -> bool:
	var lever: Node3D = _clip_levers[j]
	var tip: Vector3 = to_local(lever.global_transform * Vector3(0, -0.031 * _inward(j), 0))
	return absf(tip.y) < 0.21 and tip.z > 0.025 and absf(tip.x) < 0.26


func efficiency() -> float:
	var m := 0.0
	for d in dirt:
		m += float(d)
	return clampf(1.0 - 0.4 * m / SECTIONS, 0.0, 1.0)


func is_clean() -> bool:
	return dirt.all(func(d): return float(d) < 0.05)


func secured() -> bool:
	return not cover_open and not clips_released[0] and not clips_released[1]


func on_part(id: StringName) -> void:
	var s := String(id)
	if s == "gauge":
		airflow_checked = true
		say("Vent LS-2 airflow %d %%%s" % [roundi(efficiency() * 100.0), "" if is_clean() else " — grille blocked"])
		sfx(&"click")
	elif s == "c0" or s == "c1":
		var j: int = int(s.substr(1))
		if cover_open:
			say("Close the grille first — the clip latches over the cover edge.")
			sfx(&"click")
			return
		clips_released[j] = not clips_released[j]
		sfx(&"latch")
		if not clips_released[0] and not clips_released[1] and is_clean() and _dp != null:
			_dp.log_event("Vent LS-2 grille secured")
	elif s == "cover":
		if not cover_open and (not clips_released[0] or not clips_released[1]):
			say("Release both retaining clips first.")
			sfx(&"click")
			return
		cover_open = not cover_open
		sfx(&"latch")
		_swing()
	elif s.begins_with("s"):
		var i: int = int(s.substr(1))
		if not cover_open:
			say("Open the grille to reach the duct.")
			return
		if float(dirt[i]) < 0.05:
			say("Section %d is clean." % (i + 1))
			return
		dirt[i] = maxf(float(dirt[i]) - 0.34, 0.0)
		if float(dirt[i]) < 0.05:
			dirt[i] = 0.0
		sfx(&"scrub")
		if is_clean() and _dp != null:
			_dp.log_event("Vent LS-2 duct cleaned")
	_refresh()


func part_prompt(id: StringName) -> String:
	var s := String(id)
	if s == "gauge":
		return "Click: Check airflow (%d %%)" % roundi(efficiency() * 100.0)
	if s == "cover":
		return "Click: %s grille" % ("Close" if cover_open else "Open")
	if s == "c0" or s == "c1":
		var which: String = "upper" if s == "c0" else "lower"
		if cover_open:
			return "%s clip (close the grille first)" % which.capitalize()
		return "Click: %s %s clip" % ["Secure" if clips_released[int(s.substr(1))] else "Release", which]
	if s.begins_with("s"):
		var i: int = int(s.substr(1))
		if not cover_open:
			return ""
		return "Click: Clean section %d (%d %% dirty)" % [i + 1, roundi(float(dirt[i]) * 100.0)] if float(dirt[i]) >= 0.05 else "Section %d clean" % (i + 1)
	return ""


func _swing() -> void:
	if _cover_tween != null and _cover_tween.is_valid():
		_cover_tween.kill()
	_cover_tween = create_tween()
	_cover_tween.tween_property(_cover, "rotation_degrees:y", -105.0 if cover_open else 0.0, 0.35)


func _refresh() -> void:
	for i in SECTIONS:
		(_dirt_mats[i] as StandardMaterial3D).albedo_color = Color(0.32, 0.26, 0.18, clampf(float(dirt[i]), 0.0, 1.0) * 0.92)
	for j in 2:
		var arm: Node3D = (_clip_nodes[j] as Node3D).get_node("Arm")
		# Released: turned 90 deg (lever lies along the frame, off the cover).
		arm.rotation_degrees.z = (90.0 * _inward(j)) if clips_released[j] else 0.0
		((_clip_levers[j] as CSGBox3D).material as StandardMaterial3D).albedo_color = Color(0.85, 0.55, 0.1) if not clips_released[j] else Color(0.5, 0.52, 0.55)
	var e: float = efficiency()
	_streamer.rotation_degrees.x = -70.0 * e
	if _gauge != null:
		_gauge.text = "FLOW\n%d %%" % roundi(e * 100.0)
		_gauge.modulate = Color(0.55, 0.95, 0.75) if e > 0.95 else Color(1.0, 0.75, 0.3)
	if _cover != null and (_cover_tween == null or not _cover_tween.is_valid()):
		_cover.rotation_degrees.y = -105.0 if cover_open else 0.0


# ------------------------------------------------------------- work order
func order_rearm(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = 1 + rng.randi() % 3
	var idx: Array = [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var t = idx[i]; idx[i] = idx[j]; idx[j] = t
	for k in n:
		dirt[idx[k]] = 0.68 + 0.32 * rng.randf()
	airflow_checked = false
	_refresh()


## Round 37 severity: dirty = routine; airflow below 80 % = warning.
func order_severity() -> int:
	if is_clean() and secured():
		return 0
	return 2 if efficiency() < 0.8 else 1


func order_feasible() -> bool:
	return is_clean() and secured()


func order_done() -> bool:
	return is_clean() and secured() and airflow_checked


func order_next() -> Dictionary:
	var r := &"life_support"
	if not airflow_checked:
		return {"action": "Check vent airflow", "short": "CHECK FLOW", "room": r}
	if not is_clean():
		if not cover_open:
			if clips_released[0] and clips_released[1]:
				return {"action": "Open vent grille", "short": "OPEN GRILLE", "room": r}
			return {"action": "Release grille clips", "short": "RELEASE CLIPS", "room": r}
		for i in SECTIONS:
			if float(dirt[i]) >= 0.05:
				return {"action": "Clean blocked section %d" % (i + 1), "short": "CLEAN SEC %d" % (i + 1), "room": r}
	if cover_open:
		return {"action": "Close vent grille", "short": "CLOSE GRILLE", "room": r}
	return {"action": "Secure grille clips", "short": "SECURE CLIPS", "room": r}


func order_progress() -> String:
	return "%d%%" % roundi(efficiency() * 100.0)


func order_detail() -> Array:
	var lines: Array = ["Vent LS-2 (Life Support, west wall). Flow %d %%." % roundi(efficiency() * 100.0)]
	for i in SECTIONS:
		lines.append("Section %d: %s" % [i + 1, "clean" if float(dirt[i]) < 0.05 else "%d %% blocked" % roundi(float(dirt[i]) * 100.0)])
	lines.append("Cover %s, clips %s." % ["OPEN" if cover_open else "closed", "secured" if not (clips_released[0] or clips_released[1]) else "released"])
	return lines


func state_dict() -> Dictionary:
	return {"dirt": dirt.duplicate(), "clips_released": clips_released.duplicate(), "cover_open": cover_open, "airflow_checked": airflow_checked}


func load_dict(d: Dictionary) -> void:
	dirt = Array(d.get("dirt", dirt)).map(func(v): return float(v))
	clips_released = Array(d.get("clips_released", clips_released)).map(func(v): return bool(v))
	cover_open = bool(d.get("cover_open", cover_open))
	airflow_checked = bool(d.get("airflow_checked", airflow_checked))
	_refresh()
