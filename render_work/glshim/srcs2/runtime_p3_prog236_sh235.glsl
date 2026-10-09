#version 310 es

#define INTERFACE_BLOCK(Pos, Interp, Modifiers, Semantic, PreType, PostType) layout(location=Pos) Modifiers Semantic { PreType PostType; }
#define HLSLCC_DX11ClipSpace 1 


// end extensions
precision mediump float;
precision highp int;

void compiler_internal_AdjustInputSemantic(inout vec4 TempVariable)
{
#if HLSLCC_DX11ClipSpace
	TempVariable.y = -TempVariable.y;
	TempVariable.z = ( TempVariable.z + TempVariable.w ) / 2.0;
#endif
}

void compiler_internal_AdjustOutputSemantic(inout vec4 Src)
{
#if HLSLCC_DX11ClipSpace
	Src.y = -Src.y;
	Src.z = ( 2.0 * Src.z ) - Src.w;
#endif
}

bool compiler_internal_AdjustIsFrontFacing(bool isFrontFacing)
{
#if HLSLCC_DX11ClipSpace
	return !isFrontFacing;
#else
	return isFrontFacing;
#endif
}
uniform highp vec4 pc0_h[1];
uniform highp vec4 pc1_h[6];
uniform vec4 pu_m[2];
uniform highp sampler2D ps0;
layout(location=0) in vec4 in_COLOR0;
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=0) out vec4 out_Target0;
void main()
{
	highp float f0;
	f0 = pc0_h[0].x;
	vec4 v1;
	highp vec2 v2;
	v2.xy = (in_TEXCOORD1.xy*in_TEXCOORD1.zw);
	vec2 v3;
	highp vec2 v4;
	v4.xy = vec2(1.000000e+00,1.000000e+00);
	vec2 v5;
	v5.xy = (v4/pc1_h[0].xy);
	v3.xy = v5;
	highp float f6;
	f6 = (f0+(-(1.000000e+03*trunc((f0/1.000000e+03)))));
	float h7;
	float h8;
	h8 = (pc1_h[4].z+((f6+(-(pc1_h[4].y*trunc((f6/pc1_h[4].y)))))*pc1_h[3].w));
	h7 = h8;
	float h9;
	h9 = fract(h7);
	float h10;
	h10 = (h7+(-h9));
	highp float f11;
	highp float f12;
	f12 = h10;
	f11 = f12;
	highp float f13;
	highp float f14;
	f14 = floor((h10*v3.x));
	f13 = f14;
	float h15;
	h15 = (1.000000e+00+h10);
	highp float f16;
	highp float f17;
	f17 = h15;
	f16 = f17;
	highp float f18;
	highp float f19;
	f19 = floor((h15*v3.x));
	f18 = f19;
	vec2 v20;
	float h21;
	h21 = (f11+(-(pc1_h[0].x*trunc((f11/pc1_h[0].x)))));
	v20.x = h21;
	float h22;
	h22 = (f13+(-(pc1_h[0].y*trunc((f13/pc1_h[0].y)))));
	v20.y = h22;
	vec2 v23;
	float h24;
	h24 = (f16+(-(pc1_h[0].x*trunc((f16/pc1_h[0].x)))));
	v23.x = h24;
	float h25;
	h25 = (f18+(-(pc1_h[0].y*trunc((f18/pc1_h[0].y)))));
	v23.y = h25;
	vec4 v26;
	highp vec2 v27;
	v27.xy = v20;
	highp vec2 v28;
	v28.xy = v3;
	highp vec2 v29;
	v29.xy = v23;
	highp vec2 v30;
	v30.xy = v3;
	v26.xyzw = mix(texture(ps0,((v2+v27)*v28)),texture(ps0,((v2+v29)*v30)),vec4(h9));
	float h31;
	h31 = dot(v26.xyz,vec3(3.000000e-01,5.900000e-01,1.100000e-01));
	vec4 v32;
	v32.w = 0.000000e+00;
	highp float f33;
	f33 = h31;
	highp float f34;
	f34 = h31;
	vec3 v35;
	v35.xyz = (vec3(((min(max(f33,pc1_h[4].w),1.000000e+00)+(-pc1_h[4].w))*pc1_h[5].x))*pc1_h[1].xyz);
	vec3 v36;
	v36.xyz = (vec3(f34)*pc1_h[2].xyz);
	highp float f37;
	f37 = v26.w;
	float h38;
	h38 = (f37*pc1_h[5].y);
	v32.xyz = (max((v35+v36),vec3(0.000000e+00,0.000000e+00,0.000000e+00))*vec3(clamp(h38,0.000000e+00,1.000000e+00)));
	vec4 v39;
	v39.xyzw = ((v32*in_COLOR0)*in_COLOR0.wwww);
	v1.xyzw = v39;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h40;
		h40 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v39.xyz);
		highp vec3 v41;
		highp float f42;
		f42 = h40;
		v41.x = f42;
		highp float f43;
		f43 = h40;
		v41.y = f43;
		highp float f44;
		f44 = h40;
		v41.z = f44;
		highp vec3 v45;
		v45.xyz = v39.xyz;
		vec3 v46;
		v46.xyz = mix(v45,v41,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v1.xyz = v46;
		float h47;
		h47 = distance(v1.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v1.xyz = mix(v1.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h47,0.000000e+00,8.000000e-01)));
	}
	vec4 v48;
	v48.xyzw = v1;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v49;
		v49.xyz = v1.xyz;
		highp float f50;
		f50 = pu_m[0].w;
		vec3 v51;
		v51.xyz = clamp((((v49+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f50))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v48.xyz = v51;
	}
	v1.xyzw = v48;
	vec3 v52;
	v52.xyz = v48.xyz;
	vec3 v53;
	v53.xyz = v48.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v54;
		v54.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v52,pu_m[0].xxx));
		v53.xyz = min((v54*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v54,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v1.xyz = v53;
	out_Target0.xyzw = v1;
}

