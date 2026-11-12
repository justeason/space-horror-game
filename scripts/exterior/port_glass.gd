extends RefCounted
## Round 47: the shared OBSERVATION-PORT GLASS material.
##
## Root cause of the "hazy" ports: a StandardMaterial3D with alpha
## transparency still adds its full specular / ambient reflection, so each
## faint pane put a 20-40/255 grey veil over everything behind it (measured:
## the figure behind three panes rendered (44,53,61) instead of (3,3,4)).
## Real glass is almost invisible head-on and reflective at grazing angles:
## this unshaded shader does exactly that (Schlick Fresnel), plus a faint
## tint, so a dark silhouette behind it stays dark and the pane still reads
## as glass when seen obliquely.

static var _shader: Shader


static func material(tint: Color = Color(0.6, 0.7, 0.78), head_on: float = 0.0, grazing: float = 0.4) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.6, 0.7, 0.78);
uniform float head_on = 0.0;
uniform float grazing = 0.4;
void fragment() {
	float c = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float f = pow(1.0 - c, 5.0);
	ALBEDO = tint;
	ALPHA = clamp(head_on + grazing * f, 0.0, 1.0);
}"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("head_on", head_on)
	m.set_shader_parameter("grazing", grazing)
	return m
