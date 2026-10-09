// DRC spine battle v2.0 — verbatim port of p215 (runtime_prog215_sh214.glsl),
// the pixel shader the live capture shows drawing the character in battle AND
// in the fitting-room preview (one shared formula).
//
// Formula (source):
//   w    = mosaic(TEXCOORD1.zw, cell = 256 - 128*pc1_h[0].x)
//          wx = mod(z,cell)/cell ; wy = (trunc(z/cell)*16 + trunc(w/cell))/256
//          wz = mod(w,cell)/cell
//   v16  = max((A - base) * w + base * COLOR0, 0)
//   a    = clamp(A * COLOR0.a * Opacity)
//   out  = encode_srgb(v16)      [pu_m: encode ON, contrast OFF, desat OFF]
//
// Original-space math (texture is NOT hardware-decoded on this path),
// COLOR0 = white (vertex colour = slot x attachment x skeleton tint, all
// white in the skeleton data). With the texture decode fixed (iguf 12.48:
// texture2ddecoder outputs BGRA and the old PNGs were red/blue inverted -
// the artifact the whole "dye formula" chase was compensating) the shipped
// texture IS the mobile look, and p215's inversion term is numerically
// negligible in battle (w ~ 0): the shader degenerates to a direct draw.
// w_scale=0 keeps that; raise it only to re-create the flowing tint.
shader_type canvas_item;
render_mode blend_mix;

uniform float grid_c = 1.0;            // pc1_h[0].x (battle capture: 1.0 -> cell 128)
uniform float w_scale = 0.0;           // inversion-term weight: 0 = the mobile
                                       // look (the shipped texture is ALREADY the
                                       // final dye - captured tex827 == target);
                                       // raise only to re-create the flowing tint
uniform float c0_r = 1.0;              // COLOR0.rgb = white (source-derived)
uniform float c0_g = 1.0;
uniform float c0_b = 1.0;
uniform float c0_a = 1.0;
uniform float render_opacity = 1.0;    // pc1_h[0].x
uniform float brightness = 1.0;
uniform float alpha_scale = 1.0;

// --- lighting layer (iguf 12.7 scene channels; every gain defaults 0 =
// direct draw, identical output to the passthrough baseline) ---
uniform vec3 point_color = vec3(1.0, 0.42, 0.12); // skill orange (PointLight MPC)
uniform vec2 point_pos = vec2(0.5, 0.7);          // light centre in sprite UV
uniform float point_radius_uv = 0.7;              // radius in UV units
uniform float point_gain = 0.0;                   // 0 = off
uniform vec3 ambient_color = vec3(0.25, 0.24, 0.25); // TEXCOORD7 ambient add
uniform float ambient_gain = 0.0;
uniform vec3 fog_color = vec3(0.0);
uniform float fog_gain = 0.0;                     // exponential height fog approx
uniform float darken_alpha = 0.0;                 // DarkenMPC / SetAllUnitDarker
uniform vec3 flash_color = vec3(0.92, 0.03, 0.08); // hit-flash red (uniform loc7)
uniform float flash_gain = 0.0;
uniform float pipeline_encode = 0.0;    // 0 = raw texture out (accepted look); 1 = mobile sRGB presentation

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

	// mosaic weights from screen position (cell = 256 - 128*grid_c)
	float cell = 256.0 - 128.0 * grid_c;
	float wx = mod(FRAGCOORD.x, cell) / cell;
	float wy = (floor(FRAGCOORD.x / cell) * 16.0 + floor(FRAGCOORD.y / cell)) / 256.0;
	float wz = mod(FRAGCOORD.y, cell) / cell;
	vec3 w = vec3(wx, wy, wz) * w_scale;

	// inversion affine (source L78)
	vec3 v16 = max((base.a - base.rgb) * w + base.rgb * C0, vec3(0.0));

	// encode branch ON (pu_m[0].y = 0.4545 != 1)
	vec3 out_rgb = mix(base.rgb, encode_srgb(v16), pipeline_encode);

	// lighting layer (source-true channels, all neutral by default)
	float att = pow(max(1.0 - distance(UV, point_pos) / max(point_radius_uv, 1e-4), 0.0), 2.0);
	out_rgb = out_rgb * (vec3(1.0) + point_color * att * point_gain);
	out_rgb += ambient_color * (ambient_gain * base.a);
	out_rgb = mix(out_rgb, fog_color, fog_gain);
	out_rgb = mix(out_rgb, vec3(0.0), darken_alpha);
	out_rgb = mix(out_rgb, flash_color, flash_gain);
	float a = clamp(base.a * c0_a * mcol.a * render_opacity * alpha_scale, 0.0, 1.0);
	COLOR = vec4(out_rgb * brightness, a);
}
