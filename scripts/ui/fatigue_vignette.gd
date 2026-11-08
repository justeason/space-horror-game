extends CanvasLayer
## Round 39 Priority 7: staying up after the shift slowly closes in the
## view (a soft dark vignette) -- a visual, wordless "go to bed" cue that
## pairs with DayPlan.tiredness() (slower walking). Underfed adds a faint
## constant edge. Gone after sleeping / eating.

var _rect: ColorRect
var _mat: ShaderMaterial
var _dp: Node
var strength: float = 0.0


func _ready() -> void:
	layer = 5
	_dp = get_parent()
	_rect = ColorRect.new()
	_rect.name = "Vignette"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d * vec2(1.6, 1.0));
	float a = smoothstep(0.35, 0.95, r) * strength;
	COLOR = vec4(0.0, 0.0, 0.01, a);
}"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)


func _process(_d: float) -> void:
	if _dp == null or not _dp.has_method("tiredness"):
		return
	strength = _dp.tiredness() * 0.85 + (0.18 if _dp.underfed else 0.0)
	_mat.set_shader_parameter("strength", strength)
	_rect.visible = strength > 0.001
