// DRC spine death dissolve — mobile MySpineLitDissolutionMaterial port.
//
// Source structure (dissolution_shaders/68642e51.glsl, iguf 12.12): a noise
// texture (DRCDissolutionNoiseTexture, 512x512 dark blotches) is compared
// against an animated threshold; failing pixels discard, the erosion front
// picks up liangbian_color (edge band, LBKuandu/RongjieIntensity). The mobile
// animates Rongjie 1.2 -> 0 over 0.5 s (fightconsts.lua DieRongJieStart /
// DieDuration); here the cut rises 0 -> dissolve*1.2 instead - same erosion,
// tween-friendly direction. Noise is sampled in sprite UV (the mobile projects
// world position; the character is static during the 0.5 s dissolve, so the
// two are equivalent for our port).
shader_type canvas_item;
render_mode blend_mix;

uniform float grid_c = 1.0;
uniform float w_scale = 0.0;
uniform float c0_r = 1.0;
uniform float c0_g = 1.0;
uniform float c0_b = 1.0;
uniform float c0_a = 1.0;
uniform float render_opacity = 1.0;
uniform float brightness = 1.0;
uniform float alpha_scale = 1.0;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float dissolve = 0.0;             // 0 intact -> 1 fully gone
uniform float edge_width = 0.14;          // LBKuandu
uniform float edge_gain = 2.2;            // RongjieIntensity
uniform vec3 edge_color = vec3(0.95, 0.82, 0.45); // liangbian_color
uniform float noise_scale = 1.0;          // UScale/VScale
uniform float pipeline_encode = 0.0;      // 0 = raw texture out; 1 = mobile sRGB presentation

varying vec4 v_col;
void vertex() {
	v_col = COLOR;
}

vec3 encode_srgb(vec3 c) {
	return min(c * 12.92,
			pow(max(c, vec3(6.10352e-05)), vec3(1.0 / 2.4)) * 1.055 - 0.055);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec4 mcol = v_col;
	vec3 C0 = vec3(c0_r, c0_g, c0_b) * mcol.rgb;

	float cell = 256.0 - 128.0 * grid_c;
	float wx = mod(FRAGCOORD.x, cell) / cell;
	float wy = (floor(FRAGCOORD.x / cell) * 16.0 + floor(FRAGCOORD.y / cell)) / 256.0;
	float wz = mod(FRAGCOORD.y, cell) / cell;
	vec3 w = vec3(wx, wy, wz) * w_scale;
	vec3 v16 = max((base.a - base.rgb) * w + base.rgb * C0, vec3(0.0));
	vec3 out_rgb = mix(base.rgb, encode_srgb(v16), pipeline_encode) * brightness;

	// dissolve: noise vs rising cut (source: ps1 noise + ceil threshold + discard)
	// noise remap 0.2..1.05: spreads the erosion front evenly across the whole
	// tween (raw noise concentrates at 0.1-0.5, which erased the body within
	// the first quarter of the animation)
	float n = min(0.2 + texture(noise_tex, UV * noise_scale).r * 0.85, 1.2);
	float cut = dissolve * 1.2; // DieRongJieStart headroom
	if (n < cut - 1e-4) {
		discard;
	}
	// erosion front band -> liangbian_color
	float front = 1.0 - clamp((n - cut) / max(edge_width, 1e-4), 0.0, 1.0);
	out_rgb = mix(out_rgb, edge_color * edge_gain, front * min(dissolve * 4.0, 1.0));

	float a = clamp(base.a * c0_a * mcol.a * render_opacity * alpha_scale, 0.0, 1.0);
	COLOR = vec4(out_rgb, a);
}
