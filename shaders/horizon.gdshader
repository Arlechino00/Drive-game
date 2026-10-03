shader_type sky;
uniform float secret_amount : hint_range(0.0, 1.0) = 0.0;
uniform float effects_amount : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float soft_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), blend.x), blend.y);
}

void sky() {
	float elevation = EYEDIR.y;
	float effects = clamp(effects_amount, 0.0, 1.0);
	float secret = clamp(secret_amount, 0.0, 1.0);
	vec3 night = vec3(0.018, 0.020, 0.068);
	vec3 violet = vec3(0.120, 0.063, 0.225);
	vec3 rose = vec3(0.355, 0.105, 0.220);
	vec3 atmosphere = mix(rose, violet, smoothstep(0.015, 0.29, elevation));
	atmosphere = mix(atmosphere, night, smoothstep(0.22, 0.79, elevation));
	float sunset = pow(max(dot(EYEDIR, normalize(vec3(0.0, 0.15, -1.0))), 0.0), 8.0);
	float warm_haze = sunset * exp(-abs(elevation - 0.07) * 8.0);
	atmosphere = mix(atmosphere, vec3(0.59, 0.245, 0.160), warm_haze * (0.48 + effects * 0.12));
	// Direction-space coordinates stay continuous across the sky UV seam.
	// Three stationary low-frequency samples form stretched, irregular wisps.
	vec2 cloud_uv = vec2(EYEDIR.x * 7.0 + EYEDIR.z * 4.1, elevation * 25.0 + EYEDIR.z * 2.8);
	float broad = soft_noise(cloud_uv * 0.48 + vec2(7.2, 13.8));
	float cloud = soft_noise(cloud_uv + vec2(broad * 1.8, broad * 0.65));
	cloud = cloud * 0.76 + soft_noise(cloud_uv * 2.17 + vec2(18.4, 5.7)) * 0.24;
	float cloud_height = smoothstep(0.025, 0.09, elevation) * (1.0 - smoothstep(0.40, 0.67, elevation));
	float wisps = smoothstep(0.49, 0.76, cloud) * cloud_height;
	vec3 cloud_light = mix(vec3(0.038, 0.029, 0.065), vec3(0.105, 0.050, 0.052), sunset);
	atmosphere += cloud_light * wisps * (0.48 + effects * 0.32);
	// Sparse stationary stars vary in position, radius and brightness.
	vec2 star_uv = SKY_COORDS * vec2(440.0, 220.0);
	vec2 cell = floor(star_uv);
	float seed = hash21(cell);
	vec2 star_center = vec2(hash21(cell + 17.3), hash21(cell + 61.9)) * 0.64 + 0.18;
	float radius = mix(0.07, 0.18, hash21(cell + 4.7));
	float star = (1.0 - smoothstep(0.0, radius, length(fract(star_uv) - star_center))) * step(0.993, seed);
	star *= smoothstep(0.23, 0.53, elevation) * mix(0.38, 0.85, hash21(cell + 9.2));
	atmosphere += vec3(0.58, 0.67, 0.88) * star * (0.65 + effects * 0.35);
	float upper_band = exp(-pow((elevation - 0.66 - EYEDIR.x * 0.12) * 11.0, 2.0));
	atmosphere += vec3(0.018, 0.016, 0.033) * upper_band * broad * effects;
	vec3 cool_haze = vec3(0.070, 0.205, 0.340) * exp(-abs(elevation - 0.04) * 7.0);
	COLOR = mix(atmosphere, atmosphere * vec3(0.32, 0.52, 0.95) + cool_haze, secret);
}
