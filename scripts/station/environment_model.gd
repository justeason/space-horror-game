extends Node
## Round 35 Priority 6/10: the station ENVIRONMENT -- one authoritative,
## coherent model fed ONLY by real equipment state:
##   airflow (0..1)    = filter housing (isolated 0, service due 0.86) x
##                       vent grille efficiency x life-support fan power
##                       (power distribution channel LS-FANS)
##   pressure (kPa)    -> 101.3 minus the hatch seal's leak (drifts slowly)
##   O2 partial (kPa)  -> 21.2 x (0.82 + 0.18 x airflow) (drifts slowly)
## Three different variables, never one number reused. Degradation is slow
## and fully reversible; nothing here is ever fatal.
## Player effects are restrained: MILD -> faint vignette; SIGNIFICANT ->
## stronger vignette + a slight slow sway of the view. GameSettings
## "reduce_effects" disables the visual effects (warnings stay).

@export var filter_path: NodePath = ^"../Interactables/FilterHousingStation"
@export var vent_path: NodePath = ^"../Equipment/VentGrille"
@export var power_path: NodePath = ^"../Equipment/PowerDistribution"
@export var seal_path: NodePath = ^"../Equipment/HatchSeal"
@export var hud_path: NodePath = ^"../Player/HUD"
@export var camera_path: NodePath = ^"../Player/LookPivot/PitchPivot/Camera3D"
const GS = preload("res://scripts/station/game_settings.gd")
const NOMINAL_PRESSURE := 101.3
const NOMINAL_O2 := 21.2
## Time constants (s): how fast pressure / O2 follow their targets.
const PRESSURE_TAU := 40.0
const O2_TAU := 60.0

var pressure_kpa: float = NOMINAL_PRESSURE
var o2_kpa: float = NOMINAL_O2
var severity: int = 0          # 0 normal, 1 mild, 2 significant
var _vignette: ColorRect
var _t := 0.0
var _last_warned: int = 0


func _ready() -> void:
	var hud: Node = get_node_or_null(hud_path)
	if hud != null:
		_vignette = ColorRect.new()
		_vignette.name = "EnvVignette"
		_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float strength = 0.0;\nvoid fragment(){ vec2 d = UV - vec2(0.5); float v = smoothstep(0.35, 0.75, length(d)); COLOR = vec4(0.02, 0.03, 0.05, v * strength); }"
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_vignette.material = mat
		hud.add_child(_vignette)
		hud.move_child(_vignette, 0)


func airflow() -> float:
	var a := 1.0
	var f: Node = get_node_or_null(filter_path)
	if f != null and f.has_method("condition"):
		if f.is_isolated():
			a = 0.0
		elif f.condition() == &"service_due":
			a = 0.86
	var v: Node = get_node_or_null(vent_path)
	if v != null and v.has_method("efficiency"):
		a *= v.efficiency()
	var p: Node = get_node_or_null(power_path)
	if p != null and p.has_method("fan_factor"):
		a *= p.fan_factor()
	return clampf(a, 0.0, 1.0)


func pressure_target() -> float:
	var s: Node = get_node_or_null(seal_path)
	var leak: float = s.leak_kpa() if s != null and s.has_method("leak_kpa") else 0.0
	return NOMINAL_PRESSURE - leak


func o2_target() -> float:
	return NOMINAL_O2 * (0.82 + 0.18 * airflow())


func step(dt: float) -> void:
	pressure_kpa += (pressure_target() - pressure_kpa) * clampf(dt / PRESSURE_TAU, 0.0, 1.0)
	o2_kpa += (o2_target() - o2_kpa) * clampf(dt / O2_TAU, 0.0, 1.0)
	var sev := 0
	if o2_kpa < 18.8 or pressure_kpa < 98.0:
		sev = 2
	elif o2_kpa < 20.2 or pressure_kpa < 100.3:
		sev = 1
	severity = sev


func _process(delta: float) -> void:
	# Round 44: ordinary drift pauses with gameplay time (focused laptop,
	# waking). An abnormal environment (severity > 0) keeps simulating --
	# and laptop focus is refused / ended then (DayPlan.entertainment_allowed).
	var dpn: Node = get_node_or_null(^"../DayPlan")
	if dpn != null and dpn.has_method("gameplay_delta") and severity == 0:
		delta = dpn.gameplay_delta(delta)
	step(delta)
	_t += delta
	_apply_effects()


func _apply_effects() -> void:
	var allow: bool = not bool(GS.get_value("reduce_effects"))
	var strength: float = 0.0
	if allow:
		strength = [0.0, 0.18, 0.38][severity]
	if _vignette != null:
		(_vignette.material as ShaderMaterial).set_shader_parameter("strength", strength)
		_vignette.visible = strength > 0.0
	var cam: Camera3D = get_node_or_null(camera_path) as Camera3D
	if cam != null:
		if allow and severity == 2:
			# A slight, slow drift (no roll, no blur, no flashing).
			cam.h_offset = sin(_t * 0.7) * 0.006
			cam.v_offset = sin(_t * 0.53) * 0.004
		else:
			cam.h_offset = 0.0
			cam.v_offset = 0.0
	if severity > _last_warned:
		var ml: Label = get_node_or_null(^"../Player/HUD/TaskMessageLabel") as Label
		var msg: String = "Air quality falling — check ventilation and filters." if severity == 1 else "Low oxygen — restore airflow (vent, filter, fans)."
		preload("res://scripts/ui/hud_message.gd").show(ml, get_instance_id(), msg, 4.0)
	_last_warned = severity


func state_dict() -> Dictionary:
	return {"pressure_kpa": pressure_kpa, "o2_kpa": o2_kpa}


func load_dict(d: Dictionary) -> void:
	pressure_kpa = float(d.get("pressure_kpa", NOMINAL_PRESSURE))
	o2_kpa = float(d.get("o2_kpa", NOMINAL_O2))
