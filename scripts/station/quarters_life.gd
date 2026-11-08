extends "res://scripts/station/equipment_base.gd"
## Round 38 Priority 9 / Round 39 Priorities 4-5: daily life in the Living
## Quarters.
##
## GALLEY (Round 39: moved to the SOUTH wall, between the doorway and the
## bunk -- in Round 38 it stood in front of the closet's doors):
##   WATER   dispenser: a water pouch, drunk on the spot.
##   HOT WATER: brew tea (3 s) -> a red mug on the counter -> drink it.
##   MEAL PACKS: a meal pouch, eaten on the spot.
## Round 39 Priority 5: EATING and DRINKING are part of every day -- the
## DayPlan shows a MEAL routine row (Quarters) that counts toward the
## shift, and a day without both leaves the technician underfed the next
## morning (DayPlan.underfed: slower movement until they eat). Eating and
## drinking play a visible hand-to-mouth gesture with the actual pouch /
## mug (player_body.gd begin_consume()).
## PHOTO FRAME, a basil plant, a wall calendar and a rug make the room
## lived in. The day's activities are saved.

const Files = preload("res://scripts/ui/laptop_files.gd")
const GALLEY := Vector3(3.1, 0.0, -1.18)
const FRAME := Vector3(5.62, 1.55, 1.3)
const DRINK_S := 2.2
const EAT_S := 3.2

var tea_day: int = -1
var drank_day: int = -1
var meal_day: int = -1
var brewing: float = -1.0
var _mug: Node3D
var _steam: CSGCylinder3D
var _pending: String = ""        # consume in progress: "water" | "tea" | "meal"
signal routine_changed()


func _ready() -> void:
	_base_ready(&"")
	add_to_group(&"quarters_life")
	var g := Node3D.new()
	g.name = "Galley"
	g.position = GALLEY
	add_child(g)                     # local +Z faces into the room (north)
	box(Vector3(0.74, 0.9, 0.4), Vector3(0, 0.45, 0.0), Color(0.32, 0.33, 0.36), g)
	box(Vector3(0.78, 0.04, 0.44), Vector3(0, 0.92, 0.0), Color(0.6, 0.62, 0.64), g)
	box(Vector3(0.7, 0.06, 0.02), Vector3(0, 0.06, 0.205), Color(0.15, 0.15, 0.16), g)   # kick
	var solid := StaticBody3D.new()
	solid.name = "GalleySolid"
	solid.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.78, 0.94, 0.44)
	cs.shape = bs
	solid.add_child(cs)
	solid.position = Vector3(0, 0.47, 0)
	g.add_child(solid)
	box(Vector3(0.74, 0.5, 0.26), Vector3(0, 1.62, -0.07), Color(0.3, 0.31, 0.34), g)    # wall cupboard
	box(Vector3(0.7, 0.02, 0.02), Vector3(0, 1.36, 0.07), Color(1.0, 0.7, 0.4) * 0.6, g)  # under-cupboard light
	label("GALLEY", Vector3(0, 1.8, 0.065), 18, Color(0.95, 0.85, 0.7), g)
	# Water dispenser (left), hot-water/tea unit (right), meal drawer.
	box(Vector3(0.16, 0.3, 0.16), Vector3(-0.26, 1.09, -0.08), Color(0.55, 0.7, 0.85), g)
	box(Vector3(0.05, 0.03, 0.06), Vector3(-0.26, 1.0, 0.02), Color(0.2, 0.22, 0.25), g)
	label("WATER", Vector3(-0.26, 1.27, 0.005), 9, Color(0.1, 0.15, 0.2), g)
	part(&"water", Vector3(0.2, 0.34, 0.22), Vector3(-0.26, 1.09, -0.04), g)
	box(Vector3(0.2, 0.28, 0.2), Vector3(0.2, 1.08, -0.05), Color(0.75, 0.75, 0.73), g)
	label("HOT WATER", Vector3(0.2, 1.26, 0.055), 9, Color(0.2, 0.2, 0.2), g)
	part(&"tea", Vector3(0.24, 0.32, 0.24), Vector3(0.2, 1.08, -0.02), g)
	box(Vector3(0.32, 0.12, 0.04), Vector3(0.0, 0.7, 0.21), Color(0.55, 0.42, 0.25), g)
	label("MEAL PACKS", Vector3(0.0, 0.7, 0.235), 9, Color(0.95, 0.9, 0.8), g)
	part(&"meal", Vector3(0.36, 0.16, 0.08), Vector3(0.0, 0.7, 0.23), g)
	_mug = Node3D.new()
	_mug.position = Vector3(-0.02, 0.94, 0.1)
	g.add_child(_mug)
	var cup := CSGCylinder3D.new()
	cup.radius = 0.04
	cup.height = 0.09
	cup.position.y = 0.045
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.85, 0.3, 0.25)
	cup.material = cm
	_mug.add_child(cup)
	_steam = CSGCylinder3D.new()
	_steam.radius = 0.02
	_steam.height = 0.12
	_steam.position.y = 0.16
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1, 1, 1, 0.25)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_steam.material = sm
	_mug.add_child(_steam)
	part(&"mug", Vector3(0.12, 0.16, 0.12), Vector3(-0.02, 1.0, 0.1), g)
	_build_photo_frame()
	_build_lived_in()
	_refresh()


func _build_photo_frame() -> void:
	var f := Node3D.new()
	f.name = "PhotoFrame"
	f.position = FRAME
	f.rotation_degrees.y = -90.0
	add_child(f)
	box(Vector3(0.36, 0.27, 0.02), Vector3(0, 0, 0), Color(0.35, 0.25, 0.15), f)
	var pic := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.2)
	pic.mesh = q
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = Files.photo("dinner", 120, 80)
	pm.roughness = 0.35
	pic.material_override = pm
	pic.position.z = 0.012
	f.add_child(pic)


## Small personal touches (visual only, no collision).
func _build_lived_in() -> void:
	var d := Node3D.new()
	d.name = "LivedIn"
	add_child(d)
	# Basil in a pot on the desk (the schedule's "water the basil").
	box(Vector3(0.1, 0.09, 0.1), Vector3(3.45, 0.825, 2.25), Color(0.6, 0.35, 0.22), d, 0.0)
	for k in 5:
		var leaf := CSGSphere3D.new()
		leaf.radius = 0.035
		leaf.position = Vector3(3.45 + cos(k * 1.3) * 0.03, 0.9 + (k % 2) * 0.03, 2.25 + sin(k * 1.3) * 0.03)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.25, 0.55, 0.22)
		leaf.material = lm
		d.add_child(leaf)
	# Wall calendar above the desk, with crossed-off days.
	var cal := Node3D.new()
	cal.position = Vector3(3.62, 1.42, 2.385)
	cal.rotation_degrees.y = 180.0
	d.add_child(cal)
	box(Vector3(0.26, 0.32, 0.005), Vector3.ZERO, Color(0.93, 0.92, 0.88), cal, 0.0)
	box(Vector3(0.26, 0.07, 0.006), Vector3(0, 0.125, 0), Color(0.75, 0.3, 0.25), cal, 0.0)
	for r in 4:
		for c in 7:
			var on: bool = r * 7 + c < 10
			box(Vector3(0.024, 0.024, 0.007), Vector3(-0.105 + c * 0.035, 0.05 - r * 0.045, 0.0), Color(0.55, 0.2, 0.2) if on else Color(0.8, 0.8, 0.78), cal, 0.0)
	# A rug beside the bunk.
	box(Vector3(0.7, 0.008, 1.1), Vector3(3.95, 0.004, -0.55), Color(0.28, 0.33, 0.45), d, 0.0)


func _today() -> int:
	return _dp.day_number if _dp != null else 1


func ate_today() -> bool:
	return meal_day == _today()


func drank_today() -> bool:
	return drank_day == _today()


func _body() -> Node:
	return get_node_or_null(^"../../Player/PlayerBody")


func _hands_full() -> bool:
	var carry: Node = get_node_or_null(^"../../Player/CarrySystem")
	return carry != null and carry.has_method("is_carrying") and carry.is_carrying()


## Plays the hand-to-mouth gesture; the effect lands when it finishes.
func _consume(kind: String, seconds: float) -> bool:
	if _pending != "":
		return false
	if _hands_full():
		say("Hands full. Put that down first.")
		return false
	_pending = kind
	var b: Node = _body()
	if b != null and b.has_method("begin_consume") and b.begin_consume(kind, seconds):
		if not b.consume_finished.is_connected(_on_consumed):
			b.consume_finished.connect(_on_consumed)
	else:
		_on_consumed(kind)          # no rig (headless edge): apply at once
	return true


func _on_consumed(kind: String) -> void:
	if _pending != kind:
		return
	_pending = ""
	match kind:
		"water", "tea":
			drank_day = _today()
			say("Water. Better." if kind == "water" else "Hot tea. Better.")
			if _dp != null:
				_dp.log_event("Drink break" if kind == "water" else "Tea break")
		"meal":
			meal_day = _today()
			say("Meal pack: 'savoury lentil'. It's... fine.")
			if _dp != null:
				_dp.log_event("Meal break")
	if _dp != null and _dp.has_method("on_routine_changed"):
		_dp.on_routine_changed()
	routine_changed.emit()
	_refresh()


func on_part(id: StringName) -> void:
	match id:
		&"water":
			if drank_today():
				say("You've had a drink today.")
				return
			if _consume("water", DRINK_S):
				sfx(&"click")
		&"tea":
			if tea_day == _today():
				say("You've had your tea today.")
				return
			if brewing >= 0.0:
				return
			brewing = 0.0
			sfx(&"hiss")
			say("Water's heating...")
		&"mug":
			if tea_day == _today() and not _mug_drunk and _consume("tea", DRINK_S):
				_mug_drunk = true
				sfx(&"click")
		&"meal":
			if ate_today():
				say("Already eaten today. The next pack can wait.")
				return
			if _consume("meal", EAT_S):
				sfx(&"insert")
	_refresh()


var _mug_drunk: bool = false


func part_prompt(id: StringName) -> String:
	if _pending != "":
		return ""
	match id:
		&"water": return "" if drank_today() else "Click: Drink water"
		&"tea": return "" if tea_day == _today() else ("Heating..." if brewing >= 0.0 else "Click: Make tea")
		&"meal": return "" if ate_today() else "Click: Eat a meal pack"
		&"mug": return "Click: Drink tea" if tea_day == _today() and not _mug_drunk else ""
	return ""


func _process(delta: float) -> void:
	if brewing < 0.0:
		return
	brewing += delta
	if brewing >= 3.0:
		brewing = -1.0
		tea_day = _today()
		_mug_drunk = false
		sfx(&"success")
		say("Tea's ready.")
		_refresh()


func _refresh() -> void:
	if _mug != null:
		_mug.visible = tea_day == _today() and not _mug_drunk
		_steam.visible = _mug.visible


## Test/tool hook: completes the day's routine without the gesture.
func eat_and_drink_now() -> void:
	meal_day = _today()
	drank_day = _today()
	_pending = ""
	if _dp != null and _dp.has_method("on_routine_changed"):
		_dp.on_routine_changed()
	routine_changed.emit()
	_refresh()


func state_dict() -> Dictionary:
	return {"tea_day": tea_day, "drank_day": drank_day, "meal_day": meal_day, "mug_drunk": _mug_drunk}


func load_dict(d: Dictionary) -> void:
	tea_day = int(d.get("tea_day", -1))
	drank_day = int(d.get("drank_day", -1))
	meal_day = int(d.get("meal_day", -1))
	_mug_drunk = bool(d.get("mug_drunk", drank_day == tea_day and tea_day != -1))
	brewing = -1.0
	_pending = ""
	_refresh()
