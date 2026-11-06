extends Node
## Round 31 Priority 8B: equipment condition indicators.
##
## One small status lamp (emissive bead + short billboard tag) above each
## serviceable system. Its state is read EVERY frame from the equipment's
## own condition() -- derived from real repair/service state and today's
## work order -- never a decorative always-green light:
##   nominal      green, steady        "NOMINAL"
##   service_due  amber, slow pulse    "SERVICE DUE"
##   fault        red, blinking        "FAULT"
##   in_progress  blue, steady         "IN SERVICE"
##   restored     green, bright        "RESTORED"

@export var equipment_paths: Array[NodePath] = [
	^"../Interactables/FilterHousingStation",
	^"../Geometry/EngineeringCabinet1",
	^"../Interactables/SensorCalibrationStation",
	^"../Interactables/ValveRoutingStation",
]

const STYLES := {
	&"nominal": [Color(0.25, 0.85, 0.35), "NOMINAL", 0.0],
	&"service_due": [Color(1.0, 0.65, 0.1), "SERVICE DUE", 1.2],
	&"fault": [Color(1.0, 0.18, 0.12), "FAULT", 3.0],
	&"in_progress": [Color(0.3, 0.6, 1.0), "IN SERVICE", 0.0],
	&"restored": [Color(0.45, 1.0, 0.55), "RESTORED", 0.0],
}

var _lamps: Array = []   # [{target, bead_mat, label}]
var _t := 0.0
## Round 31 Priority 8D: a quiet confirmation tone when a system's REAL
## condition turns to restored, and when a work order actually closes.
@export var sfx_path: NodePath = ^"../Player/HUD/MechanicalSfx"
@export var day_plan_path: NodePath = ^"../DayPlan"
@onready var _sfx: Node = get_node_or_null(sfx_path)
@onready var _dp: Node = get_node_or_null(day_plan_path)
var _prev: Array = []
var _prev_closed: bool = false
var confirmations: int = 0


func _ready() -> void:
	for p in equipment_paths:
		var target: Node = get_node_or_null(p)
		if target == null or not target.has_method("condition"):
			continue
		var top: Vector3 = _top_of(target as Node3D)
		var bead := CSGSphere3D.new()
		bead.radius = 0.022
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 2.0
		bead.material = mat
		add_child(bead)
		bead.global_position = top + Vector3(0, 0.05, 0)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 22
		label.pixel_size = 0.0012
		label.outline_size = 6
		add_child(label)
		label.global_position = top + Vector3(0, 0.1, 0)
		_lamps.append({"target": target, "mat": mat, "label": label})


func _process(delta: float) -> void:
	_t += delta
	for l in _lamps:
		if not is_instance_valid(l["target"]):
			continue
		var st: StringName = l["target"].condition()
		var style: Array = STYLES.get(st, STYLES[&"nominal"])
		var c: Color = style[0]
		var rate: float = style[2]
		var k: float = 1.0 if rate == 0.0 else 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * TAU * rate * 0.5))
		(l["mat"] as StandardMaterial3D).albedo_color = c * 0.6
		(l["mat"] as StandardMaterial3D).emission = c * k
		(l["label"] as Label3D).text = style[1]
		(l["label"] as Label3D).modulate = c
	for i in _lamps.size():
		var cur: StringName = _lamps[i]["target"].condition() if is_instance_valid(_lamps[i]["target"]) else &""
		if i < _prev.size() and _prev[i] != &"restored" and cur == &"restored":
			_confirm()
		if i < _prev.size():
			_prev[i] = cur
		else:
			_prev.append(cur)
	var closed: bool = _dp != null and _dp.has_method("is_work_order_closed") and _dp.is_workday_active() and _dp.is_work_order_closed()
	if closed and not _prev_closed:
		_confirm()
	_prev_closed = closed


func _confirm() -> void:
	confirmations += 1
	if _sfx != null and _sfx.has_method("play_kind"):
		_sfx.play_kind(&"success")


func condition_of(index: int) -> StringName:
	return _lamps[index]["target"].condition() if index < _lamps.size() else &""


func lamp_text(index: int) -> String:
	return (_lamps[index]["label"] as Label3D).text if index < _lamps.size() else ""


func lamp_count() -> int:
	return _lamps.size()


static func _top_of(n: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	var vis: Array = n.find_children("*", "VisualInstance3D", true, false)
	if n is VisualInstance3D:
		vis.append(n)
	for v in vis:
		if v is Label3D or not (v as Node3D).is_visible_in_tree():
			continue
		var b: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return n.global_position + Vector3(0, 0.4, 0)
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)
