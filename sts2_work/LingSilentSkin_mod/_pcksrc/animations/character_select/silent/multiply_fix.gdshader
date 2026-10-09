shader_type canvas_item;
// Spine multiply 修正(Forward+/D3D12, AMD/Vulkan 实测)。本管线 canvas_item
// blend_mul 实际行为 = dst*src.rgb,src.alpha 被无视——透明纹素(rgb=0)整块
// 四边形渲染成实心黑矩形。
// 解法:把 spine multiply(PMA) 的每像素保留系数编码进 src.rgb:
//   spine PMA multiply: out = dst*(rgb_pma + 1 - a), rgb_pma = rgb*a
//   令 src.rgb = 1 - a*(1 - rgb) (= 保留系数 m), blend_mul: out = dst*m
// 逐像素一致,且与 alpha 无关。通过 SpineSprite.multiply_material 挂载。
render_mode blend_mul;

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float ka = clamp(tex.a * v_color.a, 0.0, 1.0);
	vec3 sr = clamp(tex.rgb * v_color.rgb, vec3(0.0), vec3(1.0));
	COLOR = vec4(1.0 - ka * (1.0 - sr), 1.0);
}
