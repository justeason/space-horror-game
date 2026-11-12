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
var meal_day: int = -1              # MEAL 1 (breakfast) eaten on this day
## Round 43 Priorities 14-16 / 23A: the daily ROUTINE.
var dinner_day: int = -1            # MEAL 2 (dinner) eaten on this day
var brush_day: int = -1             # morning teeth brushed on this day
var brush_pm_day: int = -1          # optional evening brush
var basil_day: int = -1             # basil watered on this day
var basil_dry_days: int = 0         # CONDITION: 0 healthy, 1 dry, 2 wilting, 3 dead
## Round 46: long-term care. Three station days in a row without water kill
## the plant (deterministic). Watering a living plant improves it ONE step
## the next morning (never an instant undo). A dead plant stays dead under
## ordinary play -- water is refused. The TRUE history (died on day N, seen
## dead, no watering since) is kept even if a Phase 3 story event later
## PRESENTS it alive again (basil_return: presentation only).
const BASIL_NAMES := ["HEALTHY", "DRY", "WILTING", "DEAD"]
var basil_dead: bool = false
var basil_dead_day: int = -1
var basil_seen_dead: bool = false
var basil_return_day: int = -1       # story presentation: alive again since
var basil_return_seen: bool = false
var basil_return_dev: bool = false   # developer preview (never counted)
signal basil_return_noticed
var missed_dinner: bool = false     # yesterday ended without dinner (mild)
const DINNER_FROM_MIN := 18 * 60    # dinner from 18:00 (or once work is done); Round 45 15 h day
const BRUSH_S := 4.0
var _leaves: Array = []
var _brush_holder: Node3D
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
	_build_hygiene()
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
	var bp: Vector3 = BASIL_LOCAL
	box(Vector3(0.1, 0.09, 0.1), Vector3(bp.x, 0.825, bp.z), Color(0.6, 0.35, 0.22), d, 0.0)
	for k in 5:
		var leaf := CSGSphere3D.new()
		leaf.radius = 0.035
		leaf.position = Vector3(bp.x + cos(k * 1.3) * 0.03, 0.9 + (k % 2) * 0.03, bp.z + sin(k * 1.3) * 0.03)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.25, 0.55, 0.22)
		leaf.material = lm
		d.add_child(leaf)
		_leaves.append(leaf)
	part(&"basil", Vector3(0.16, 0.2, 0.16), Vector3(bp.x, 0.88, bp.z), d)
	label("BASIL", Vector3(bp.x, 0.79, bp.z - 0.07), 8, Color(0.95, 0.9, 0.8), d).rotation_degrees.y = 180.0
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


func breakfast_today() -> bool:
	return meal_day == _today()


func dinner_today() -> bool:
	return dinner_day == _today()


func brushed_today() -> bool:
	return brush_day == _today()


func basil_watered_today() -> bool:
	return basil_day == _today()


## Dinner is the LATER meal: after breakfast, from 15:00 or once the day's
## work is done / the shift is over. "" = may eat dinner now.
func dinner_refusal() -> String:
	if not breakfast_today():
		return "breakfast"
	if dinner_today():
		return "Dinner's done. Nothing more until tomorrow."
	if _dp == null:
		return ""
	var late: bool = (_dp.has_method("clock_minutes") and _dp.clock_minutes() >= DINNER_FROM_MIN) or bool(_dp.get("shift_ended")) or float(_dp.get("work_done_at_s")) >= 0.0
	return "" if late else "Not hungry yet. Dinner is after the shift."


## Today's routine for the daily note / tests.
func routine_status() -> Dictionary:
	return {"breakfast": breakfast_today(), "drink": drank_today(), "brush": brushed_today(), "dinner": dinner_today(), "basil": basil_watered_today(), "basil_dead": basil_dead and basil_return_day < 0, "missed_dinner": missed_dinner}


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


signal consumed(kind: String)     # Round 46: everyday thoughts listen

## Round 47: eating / drinking reactions are the technician's own INNER
## THOUGHTS (the same caption / voice path as every other thought), not a
## HUD remark -- short, contextual, rotating so the same line does not come
## back meal after meal. Never the station assistant. Falls back to the
## old HUD line only if no inner voice exists (tools / isolated scenes).
const ROUTINE_THOUGHTS := {
	"meal": [["That's better.", "好多了。"], ["Oats and apricot. Warm enough.", "燕麦配杏干。够热了。"], ["Breakfast. Right. Day's started.", "早饭。好，一天开始了。"], ["Could use something fresh.", "要是有点新鲜的就好了。"]],
	"dinner": [["Could use something fresh.", "要是有点新鲜的就好了。"], ["Lentils. It's... fine.", "扁豆。还……行吧。"], ["Warm, at least.", "至少是热的。"]],
	"tea": [["Still warm.", "还是热的。"], ["That's better.", "好多了。"], ["Tea helps.", "喝茶有用。"]],
	"water": [["Better.", "好些了。"], ["Needed that.", "正需要这个。"], ["Recycled. Tastes of nothing.", "循环水。没什么味道。"]],
}
const ROUTINE_FALLBACK := {"meal": "Breakfast pouch: oats and apricot. Warm enough.", "dinner": "Dinner tray: savoury lentil stew. It's... fine.", "tea": "Hot tea. Better.", "water": "Water. Better."}
var routine_uses: Dictionary = {}     # kind -> times (saved: rotation)


## Round 47: a REAL action's sound from where it happens (station_sounds:
## positional, through the acoustic path). Nothing plays for an action that
## did not happen.
func _snd(kind: StringName, pos: Vector3) -> void:
	var snd: Node = get_tree().get_first_node_in_group(&"station_sounds") if is_inside_tree() else null
	if snd != null:
		snd.play_at(kind, pos, true)


## ...at the technician's own mouth (eating, drinking, brushing).
func _snd_mouth(kind: StringName) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() != null else null
	if cam != null:
		_snd(kind, cam.global_position - cam.global_basis.z * 0.15 - Vector3(0, 0.08, 0))


func _remark(kind: String) -> void:
	var iv: Node = get_tree().get_first_node_in_group(&"inner_voice") if is_inside_tree() else null
	var pool: Array = ROUTINE_THOUGHTS.get(kind, [])
	if iv == null or pool.is_empty():
		say(String(ROUTINE_FALLBACK.get(kind, "")))
		return
	var n: int = int(routine_uses.get(kind, 0))
	routine_uses[kind] = n + 1
	var line: Array = pool[n % pool.size()]
	iv.think("routine:%s:%d" % [kind, n], String(line[0]), String(line[1]), false)


func _on_consumed(kind: String) -> void:
	if _pending != kind:
		return
	_pending = ""
	consumed.emit(kind)
	# Round 47: the action's own sound, at the mouth (eating / drinking).
	match kind:
		"water", "tea":
			_snd_mouth(&"sip")
		"meal", "dinner":
			_snd_mouth(&"chew")
		"pour":
			_snd(&"trickle", _basil_pos())
	match kind:
		"water", "tea":
			drank_day = _today()
			_remark(kind)
			if _dp != null:
				_dp.log_event("Drink break" if kind == "water" else "Tea break")
		"meal":
			meal_day = _today()
			missed_dinner = false
			_remark("meal")
			if _dp != null:
				_dp.log_event("Breakfast")
		"dinner":
			dinner_day = _today()
			_remark("dinner")
			if _dp != null:
				_dp.log_event("Dinner")
		"pour":
			basil_day = _today()
			# Round 46: no instant undo -- the plant recovers a step overnight.
			say("A little water for the basil." if basil_dry_days < 2 else "A lot of droop. It needs a few good days.")
			if _dp != null:
				_dp.log_event("Watered the basil")
		"brush":
			if _hour() >= DINNER_FROM_MIN and brushed_today():
				brush_pm_day = _today()
			else:
				brush_day = _today()
			say("Teeth brushed. Minty, and one less thing.")
			if _brush_holder != null:
				_brush_holder.visible = true
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
				_snd(&"dispense", GALLEY + Vector3(-0.26, 1.0, 0.02))
		&"tea":
			if tea_day == _today():
				say("You've had your tea today.")
				return
			if brewing >= 0.0:
				return
			brewing = 0.0
			_snd(&"kettle", GALLEY + Vector3(0.2, 1.08, -0.02))
			say("Water's heating...")
		&"mug":
			if tea_day == _today() and not _mug_drunk and _consume("tea", DRINK_S):
				_mug_drunk = true
		&"meal":
			if not ate_today():
				if _consume("meal", EAT_S):
					_snd_mouth(&"wrapper")
				return
			var why: String = dinner_refusal()
			if why != "":
				say(why)
				return
			if _consume("dinner", EAT_S + 0.6):
				_snd(&"tray", GALLEY + Vector3(0.0, 0.94, 0.1))
		&"brush":
			if brushed_today() and (brush_pm_day == _today() or _hour() < DINNER_FROM_MIN):
				say("Already brushed. Teeth are fine.")
				return
			if _consume("brush", BRUSH_S):
				if _brush_holder != null:
					_brush_holder.visible = false
				_snd_mouth(&"brush")
		&"basil":
			if basil_dead and basil_return_day < 0:
				basil_seen_dead = true
				say("It's dead. Water won't help it now.")
				return
			if basil_watered_today():
				say("The soil's still damp. That's enough for today.")
				return
			# Round 45: a real watering gesture (reach, tilt, trickle,
			# return); the plant updates when the pour finishes.
			if _pending != "" or _hands_full():
				return
			_pending = "pour"
			_approach_then_pour()
	_refresh()


var _mug_drunk: bool = false


func part_prompt(id: StringName) -> String:
	if _pending != "":
		return ""
	match id:
		&"water": return "" if drank_today() else "Click: Drink water"
		&"tea": return "" if tea_day == _today() else ("Heating..." if brewing >= 0.0 else "Click: Make tea")
		&"meal":
			if not ate_today():
				return "Click: Breakfast pouch"
			return "Click: Dinner tray" if dinner_refusal() == "" else ""
		&"brush": return "" if brushed_today() and (brush_pm_day == _today() or _hour() < DINNER_FROM_MIN) else "Click: Brush teeth"
		&"basil": return "" if basil_watered_today() or (basil_dead and basil_return_day < 0) else "Click: Water the basil"
		&"mug": return "Click: Drink tea" if tea_day == _today() and not _mug_drunk else ""
	return ""


## Round 40 Priority 5: a diegetic end-of-shift cue -- once the shift is
## over, a warm reading glow comes on over the bunk ("go to bed" without
## words); it goes out with the new day.
var _bunk_glow: OmniLight3D


func _update_bunk_glow(delta: float) -> void:
	if _bunk_glow == null:
		_bunk_glow = OmniLight3D.new()
		_bunk_glow.name = "BunkGlow"
		_bunk_glow.light_color = Color(1.0, 0.72, 0.42)
		_bunk_glow.omni_range = 2.2
		_bunk_glow.light_energy = 0.0
		_bunk_glow.position = Vector3(5.0, 1.1, -0.6)
		add_child(_bunk_glow)
	var want: float = 0.9 if _dp != null and _dp.shift_ended else 0.0
	_bunk_glow.light_energy = move_toward(_bunk_glow.light_energy, want, delta * 0.6)


func bunk_glow_energy() -> float:
	return _bunk_glow.light_energy if _bunk_glow != null else 0.0


func _process(delta: float) -> void:
	_update_bunk_glow(delta)
	_watch_basil()
	if brewing < 0.0:
		return
	brewing += delta
	if brewing >= 3.0:
		brewing = -1.0
		tea_day = _today()
		_mug_drunk = false
		_snd(&"kettle_done", GALLEY + Vector3(0.2, 1.08, -0.02))
		say("Tea's ready.")
		_refresh()


func _hour() -> int:
	return _dp.clock_minutes() if _dp != null and _dp.has_method("clock_minutes") else 8 * 60


func _refresh() -> void:
	if _mug != null:
		_mug.visible = tea_day == _today() and not _mug_drunk
		_steam.visible = _mug.visible
	_refresh_basil()


## Post-Round-45: the pot is watered from arm's length. Clicked from further
## away, the body first takes a short, ordinary step up to the desk (the
## guided walk: real physics, any movement key cancels and abandons the
## pour), then the can is tipped -- the spout, not the wrist, over the pot.
## Post-Round-45: the pot sits near the desk's FRONT edge (slab z 1.92-2.38),
## between the task lamp (x 3.30) and the notebook (x 3.61); the stool
## (x 3.64-3.96) keeps the body in front of x ~3.3. At the back (z 2.25) it
## was out of arm's reach from anywhere a body can stand.
const BASIL_LOCAL := Vector3(3.45, 0.85, 2.03)
const POUR_REACH := 0.55         # horizontal eye -> pot distance an arm covers
const POUR_STAND := 0.45         # where the step stops (short of the pot)
const POUR_STEP_MAX_S := 1.6


func _approach_then_pour() -> void:
	var pot: Vector3 = _basil_pos()
	var fb: Node = get_node_or_null(^"../../FreeMoveBody")
	if fb != null and "guide_target" in fb and bool(fb.get("active")) and fb.guide_target == Vector3.INF and fb.has_method("current_eye_position"):
		var eye: Vector3 = fb.current_eye_position()
		var flat := Vector3(pot.x - eye.x, 0.0, pot.z - eye.z)
		if flat.length() > POUR_REACH:
			var stand: Vector3 = pot - flat.normalized() * POUR_STAND
			fb.guide_cancelled = false
			fb.guide_target = Vector3(stand.x, eye.y, stand.z)
			var waited: float = 0.0
			while fb.guide_target != Vector3.INF and waited < POUR_STEP_MAX_S and _pending == "pour":
				await get_tree().physics_frame
				waited += get_physics_process_delta_time()
			var cancelled: bool = fb.guide_cancelled
			fb.guide_target = Vector3.INF      # blocked by the desk / timed out: pour from here
			if cancelled or _pending != "pour":
				if _pending == "pour":
					_pending = ""              # the player walked off: no water
				return
	var b: Node = _body()
	if b != null and b.has_method("begin_consume") and b.begin_consume("pour", 2.6, pot):
		if not b.consume_finished.is_connected(_on_consumed):
			b.consume_finished.connect(_on_consumed)
	else:
		_on_consumed("pour")


## The basil shows how it has been looked after: green and upright when
## watered, droopier and paler for every dry day (recovers when watered).
func _basil_pos() -> Vector3:
	return to_global(BASIL_LOCAL)


func basil_health() -> float:
	if basil_dead and basil_return_day < 0:
		return 0.0
	return clampf(1.0 - 0.25 * float(basil_condition()), 0.25, 1.0)


## 0 healthy .. 3 dead, as the plant LOOKS (a story return shows healthy).
func basil_condition() -> int:
	if basil_return_day >= 0:
		return 0
	return 3 if basil_dead else clampi(basil_dry_days, 0, 2)


func basil_state_name() -> String:
	return BASIL_NAMES[basil_condition()]


func _refresh_basil() -> void:
	var c: int = basil_condition()
	var perk: float = 0.004 if basil_watered_today() and c < 3 else 0.0
	var bp: Vector3 = BASIL_LOCAL
	# HEALTHY green + upright; DRY dull, a little lower; WILTING yellowed,
	# drooping outward; DEAD brown, shrivelled and collapsed onto the soil.
	var cols := [Color(0.25, 0.55, 0.22), Color(0.38, 0.5, 0.25), Color(0.55, 0.5, 0.22), Color(0.34, 0.24, 0.13)]
	for i in _leaves.size():
		var leaf: CSGSphere3D = _leaves[i]
		var ang: float = i * 1.3
		var spread: float = [0.03, 0.034, 0.045, 0.05][c]
		leaf.radius = 0.035 * [1.0, 0.92, 0.82, 0.6][c]
		leaf.position = Vector3(bp.x + cos(ang) * spread, [0.9 + (i % 2) * 0.03, 0.895 + (i % 2) * 0.022, 0.878 + (i % 2) * 0.01, 0.862][c] + perk, bp.z + sin(ang) * spread)
		leaf.scale = Vector3(1.0, [1.0, 0.95, 0.75, 0.42][c], 1.0)
		(leaf.material as StandardMaterial3D).albedo_color = cols[c]


## New day: the routine resets; a skipped dinner is remembered (mild, the
## daily note mentions it), the basil dries a little if it was forgotten.
func on_new_day(prev_day: int) -> void:
	missed_dinner = meal_day == prev_day and dinner_day != prev_day
	if not basil_dead:
		if basil_day == prev_day:
			basil_dry_days = maxi(basil_dry_days - 1, 0)      # one step better
		else:
			basil_dry_days += 1
			if basil_dry_days >= 3:
				basil_dry_days = 3
				basil_dead = true
				basil_dead_day = prev_day + 1
				if _dp != null:
					_dp.log_event("The basil has died")
	_refresh()


## Round 46 (Phase 3 foundation): may the story present the plant alive?
## Only after it GENUINELY died and the technician SAW it dead, on a later
## day, with no legitimate explanation (nothing replaces a plant here).
func basil_return_eligible(phase: int) -> bool:
	return phase >= 3 and basil_dead and basil_seen_dead and basil_return_day < 0 and _today() > basil_dead_day


func basil_return(dev: bool = false) -> void:
	basil_return_day = _today()
	basil_return_seen = false
	basil_return_dev = dev
	_refresh()


func basil_return_reset() -> void:
	basil_return_day = -1
	basil_return_seen = false
	basil_return_dev = false
	_refresh()


## Developer: put the plant in a care state (0 healthy .. 3 dead).
func dev_basil_state(c: int) -> void:
	basil_return_reset()
	basil_dead = c >= 3
	basil_dry_days = clampi(c, 0, 3)
	basil_dead_day = _today() if basil_dead else -1
	basil_seen_dead = basil_dead
	_refresh()


## Seeing the plant (close, looking at it) -- dead, or impossibly alive.
func _watch_basil() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or not (basil_dead and (not basil_seen_dead or (basil_return_day >= 0 and not basil_return_seen))):
		return
	var to: Vector3 = _basil_pos() - cam.global_position
	if to.length() > 2.6 or (-cam.global_transform.basis.z).dot(to.normalized()) < 0.9:
		return
	if basil_return_day < 0:
		basil_seen_dead = true
	elif not basil_return_seen:
		basil_return_seen = true
		basil_return_noticed.emit()


## Round 43: a compact HYGIENE niche on the quarters wall beside the galley:
## a small recessed basin (water-saving push tap, no running stream), a
## toothbrush in its holder, toothpaste, a cup and a towel bar.
func _build_hygiene() -> void:
	var h := Node3D.new()
	h.name = "HygieneNiche"
	h.position = GALLEY + Vector3(-0.72, 0.0, -0.08)
	add_child(h)
	box(Vector3(0.5, 0.62, 0.16), Vector3(0, 1.22, -0.04), Color(0.78, 0.8, 0.82), h)       # panel
	box(Vector3(0.4, 0.06, 0.2), Vector3(0, 0.98, 0.04), Color(0.88, 0.9, 0.92), h)          # basin rim
	box(Vector3(0.32, 0.03, 0.15), Vector3(0, 0.995, 0.05), Color(0.55, 0.6, 0.65), h)      # basin bowl
	box(Vector3(0.03, 0.06, 0.05), Vector3(0.12, 1.06, -0.03), Color(0.6, 0.62, 0.65), h)   # push tap
	box(Vector3(0.36, 0.16, 0.012), Vector3(0, 1.4, 0.045), Color(0.55, 0.65, 0.7), h)      # small mirror
	label("HYGIENE · WATER SAVER", Vector3(0, 1.52, 0.045), 8, Color(0.15, 0.2, 0.25), h)
	box(Vector3(0.06, 0.06, 0.06), Vector3(-0.16, 1.1, 0.06), Color(0.35, 0.55, 0.65), h)   # holder cup
	_brush_holder = Node3D.new()
	h.add_child(_brush_holder)
	box(Vector3(0.012, 0.15, 0.012), Vector3(-0.16, 1.19, 0.06), Color(0.2, 0.75, 0.75), _brush_holder)
	box(Vector3(0.016, 0.025, 0.02), Vector3(-0.16, 1.27, 0.065), Color(0.95, 0.95, 0.95), _brush_holder)
	box(Vector3(0.03, 0.1, 0.02), Vector3(-0.09, 1.08, 0.06), Color(0.9, 0.35, 0.3), h)     # toothpaste
	box(Vector3(0.34, 0.012, 0.012), Vector3(0, 0.88, 0.06), Color(0.6, 0.62, 0.65), h)     # towel bar
	box(Vector3(0.18, 0.14, 0.01), Vector3(0.06, 0.81, 0.068), Color(0.35, 0.45, 0.6), h)   # towel
	part(&"brush", Vector3(0.44, 0.4, 0.22), Vector3(0, 1.15, 0.06), h)


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
	return {"tea_day": tea_day, "drank_day": drank_day, "meal_day": meal_day, "mug_drunk": _mug_drunk,
		"dinner_day": dinner_day, "brush_day": brush_day, "brush_pm_day": brush_pm_day, "basil_day": basil_day, "basil_dry": basil_dry_days, "missed_dinner": missed_dinner,
		"basil_dead": basil_dead, "basil_dead_day": basil_dead_day, "basil_seen_dead": basil_seen_dead,
		"basil_return_day": basil_return_day if not basil_return_dev else -1, "basil_return_seen": basil_return_seen and not basil_return_dev,
		"routine_uses": routine_uses.duplicate()}


func load_dict(d: Dictionary) -> void:
	routine_uses = (d.get("routine_uses", {}) as Dictionary).duplicate() if d.get("routine_uses", {}) is Dictionary else {}
	tea_day = int(d.get("tea_day", -1))
	drank_day = int(d.get("drank_day", -1))
	meal_day = int(d.get("meal_day", -1))
	_mug_drunk = bool(d.get("mug_drunk", drank_day == tea_day and tea_day != -1))
	dinner_day = int(d.get("dinner_day", -1))
	brush_day = int(d.get("brush_day", -1))
	brush_pm_day = int(d.get("brush_pm_day", -1))
	basil_day = int(d.get("basil_day", -1))
	basil_dry_days = clampi(int(d.get("basil_dry", 0)), 0, 3)
	# Round 46: a save from before plant death existed capped "dry" at 3
	# (droopiest, still alive) -- never kill a plant on load.
	basil_dead = bool(d.get("basil_dead", false))
	if not d.has("basil_dead") and basil_dry_days >= 3:
		basil_dry_days = 2
	basil_dead_day = int(d.get("basil_dead_day", -1))
	basil_seen_dead = bool(d.get("basil_seen_dead", false))
	basil_return_day = int(d.get("basil_return_day", -1))
	basil_return_seen = bool(d.get("basil_return_seen", false))
	basil_return_dev = false
	missed_dinner = bool(d.get("missed_dinner", false))
	if _brush_holder != null:
		_brush_holder.visible = true
	brewing = -1.0
	_pending = ""
	_refresh()
