shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;

uniform float effects_amount : hint_range(0.0, 1.0) = 1.0;
uniform float secret_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float radius = length((UV - 0.5) * 2.0);
	vec3 warm = mix(vec3(1.0, 0.12, 0.40), vec3(1.0, 0.48, 0.18), 1.0 - UV.y);
	vec3 cool = mix(vec3(0.32, 0.22, 0.90), vec3(0.24, 0.72, 1.0), 1.0 - UV.y);
	ALBEDO = mix(warm, cool, clamp(secret_amount, 0.0, 1.0));
	ALPHA = pow(max(1.0 - radius, 0.0), 2.8) * 0.22 * clamp(effects_amount, 0.0, 1.0);
}
