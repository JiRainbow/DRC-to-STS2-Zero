// DRC spine silhouette shadow - STS2 equivalent of the mobile RT shadow
// material (RTGlobalShadowMat: units rendered into an RT, projected on the
// ground plane; ShadowOpacity scalar). The shadow node is a second SpineSprite
// sharing the character's SkeletonDataResource with its full pose copied each
// tick; this material flattens it to a solid tint. Shape = the skin's own
// texture alpha (the true silhouette), rgb = tint (black final look, opaque
// red while debugging visibility), alpha = texA x vertex(slot)A x opacity.
shader_type canvas_item;
render_mode blend_mix;

uniform vec4 tint = vec4(0.0, 0.0, 0.0, 1.0); // final look: opaque black
uniform float opacity = 0.55;                  // ShadowOpacity analogue

varying vec4 v_col;
void vertex() {
	v_col = COLOR;
}

void fragment() {
	float a = texture(TEXTURE, UV).a * v_col.a * opacity;
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 1.0));
}
