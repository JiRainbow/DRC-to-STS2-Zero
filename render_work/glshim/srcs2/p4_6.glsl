#version 320 es

precision mediump float;
precision mediump sampler2D;
uniform highp vec4 sk_RTAdjust;
in highp vec2 position;
in mediump vec4 color;
out mediump vec4 vcolor_S0;
void main() {
vcolor_S0 = color;
gl_Position = vec4(position, 0.0, 1.0);
gl_Position = vec4(gl_Position.xy * sk_RTAdjust.xz + gl_Position.ww * sk_RTAdjust.yw, 0.0, gl_Position.w);
}
