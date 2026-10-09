shader_type canvas_item;
// Spine additive 修正(Forward+/D3D12)。spine-godot 内置 additive 按 (ONE,ONE)
// 预乘约定渲染,直通 alpha 贴图下槽位/时间轴 alpha 完全失效——雪花/光晕把
// 整块 rgb 无视 alpha 全强度叠加(左上青蓝光斑根因)。
// 本 shader 经四象限实测锁定:Godot blend_add=(SRC_ALPHA,ONE),输出直通色,
// out = tex.rgb*slot.rgb*(tex.a*slot.a) + dst——alpha 严格线性生效:
// alpha=0 零贡献(snow/boom 恒隐)、alpha=0.11 恰提亮 11%(windows_light)、
// alpha 渐变线性(halo 淡入淡出)。
// 通过 SpineSprite.additive_material 挂载,替换 spine-godot 内置 additive 材质。
render_mode blend_add;

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb * v_color.rgb, tex.a * v_color.a);
}
