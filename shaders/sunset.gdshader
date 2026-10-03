shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform float effects_amount : hint_range(0.0, 1.0) = 1.0;
uniform float secret_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 disc = (UV - vec2(0.5)) * 2.0;
	if (dot(disc, disc) > 1.0) { discard; }
	// Slices widen toward the bottom; the crown remains uninterrupted.
	if (UV.y > 0.48) {
		float stripe = mod(UV.y - 0.48, 0.087);
		float gap = mix(0.012, 0.043, smoothstep(0.48, 1.0, UV.y));
		if (stripe < gap) { discard; }
	}
	vec3 amber = vec3(1.0, 0.55, 0.13);
	vec3 pink = vec3(1.0, 0.08, 0.47);
	ALBEDO = mix(amber, pink, smoothstep(0.1, 0.98, UV.y));
	vec3 secret = mix(vec3(0.30, 0.79, 1.0), vec3(0.34, 0.18, 0.88), smoothstep(0.1, 0.98, UV.y));
	ALBEDO = mix(ALBEDO, secret, secret_amount);
	EMISSION = ALBEDO * (0.18 + effects_amount * 0.28);
}
