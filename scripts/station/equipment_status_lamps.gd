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
const _TAG := preload("res://scripts/interactables/inspection_tag.gd")
const _INSPECT_IDS := {
	"FilterHousingStation": [&"filter", "filter housing status"],
	"EngineeringCabinet1": [&"power", "power panel status"],
	"SensorCalibrationStation": [&"sensors", "sensor array status"],
	"ValveRoutingStation": [&"coolant", "coolant manifold status"],
}
var _tags: Array = []
@export var audit_cabinet_path: NodePath = ^"../Geometry/StorageCabinet1"
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
	# Round 33 ROOT-CAUSE FIX: placed two frames after ready -- during
	# _ready the stations' own visuals are not yet at their final transforms
	# (the filter/coolant lamps were computed at ~6 m, above the Life Support
	# ceiling, invisible since Round 31).
	await get_tree().process_frame
	await get_tree().process_frame
	_build_lamps()


func _build_lamps() -> void:
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
		# Round 33: the tag is a physical inspection point.
		var tag := StaticBody3D.new()
		tag.set_script(_TAG)
		add_child(tag)
		tag.global_position = top + Vector3(0, 0.09, 0)
		var lamp_index: int = _lamps.size() - 1
		var key: Array = _INSPECT_IDS.get(String(target.name), [&"", "status"])
		tag.name = "InspectionTag_%s" % key[0]
		tag.setup(key[0], key[1], Vector3(0.22, 0.12, 0.22), func(): return lamp_reading(lamp_index))
		tag.day_plan = _dp
		_tags.append(tag)
		if _dp != null and _dp.has_method("register_reading_source"):
			_dp.register_reading_source(key[0], func(): return lamp_reading(lamp_index))
	_add_audit_tag()


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


## The reading the player actually sees on the tag (its live condition).
func lamp_reading(index: int) -> String:
	if index >= _lamps.size() or not is_instance_valid(_lamps[index]["target"]):
		return "?"
	return String(STYLES.get(_lamps[index]["target"].condition(), STYLES[&"nominal"])[1])


func tags() -> Array:
	return _tags


## Round 33 SUPPLY AUDIT point: the electrical cabinet's stock placard. Only
## readable with the door open (you count the parts on the shelf); the
## reading is the physical count per type.
func _add_audit_tag() -> void:
	var cab: Node3D = get_node_or_null(audit_cabinet_path)
	if cab == null or not cab.has_method("stock_count"):
		return
	var tag := StaticBody3D.new()
	tag.set_script(_TAG)
	tag.name = "InspectionTag_storage_audit"
	cab.add_child(tag)
	# On top of the cabinet, by its front edge (never in front of the open
	# door, where it would intercept clicks on the parts inside).
	var top_n: Node3D = cab.get_node_or_null("Top")
	tag.global_position = (top_n.global_position if top_n != null else cab.global_position + Vector3(0, 0.5, 0)) + Vector3(0.2, 0.06, 0.0)
	tag.setup(&"storage_audit", "electrical spares count", Vector3(0.2, 0.1, 0.5),
		func():
			var bits: Array = []
			for t in cab.stock_types():
				bits.append("%s %d/%d" % [preload("res://scripts/station/part_names.gd").short(t), cab.stock_count(t), cab.capacity(t)])
			return " · ".join(bits),
		func(): return "" if cab.is_open() else "Open the cabinet to count the parts.")
	tag.day_plan = _dp
	_tags.append(tag)
	if _dp != null and _dp.has_method("register_reading_source"):
		_dp.register_reading_source(&"storage_audit", tag.reader)


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
		# Round 33 ROOT-CAUSE FIX: stations also own their focused-view
		# DIORAMA sets, built far away (filter/coolant ~4 m up, above the
		# Life Support ceiling) -- including them put the lamp, its tag and
		# now the inspection point out of the player's sight. Only the
		# station's own nearby geometry counts.
		if b.get_center().distance_to(n.global_position) > 1.0:
			continue
		box = b if first else box.merge(b)
		first = false
	if first:
		return n.global_position + Vector3(0, 0.4, 0)
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)
