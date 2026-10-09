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
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=0) out vec4 out_Target0;
void main()
{
	highp float f0;
	f0 = pc0_h[0].x;
	vec4 v1;
	vec2 v2;
	highp vec2 v3;
	v3.xy = vec2(1.000000e+00,1.000000e+00);
	vec2 v4;
	v4.xy = (v3/pc1_h[0].xy);
	v2.xy = v4;
	highp float f5;
	f5 = (f0+(-(1.000000e+03*trunc((f0/1.000000e+03)))));
	float h6;
	float h7;
	h7 = (pc1_h[4].z+((f5+(-(pc1_h[4].y*trunc((f5/pc1_h[4].y)))))*pc1_h[3].w));
	h6 = h7;
	float h8;
	h8 = fract(h6);
	float h9;
	h9 = (h6+(-h8));
	highp float f10;
	highp float f11;
	f11 = h9;
	f10 = f11;
	highp float f12;
	highp float f13;
	f13 = floor((h9*v2.x));
	f12 = f13;
	float h14;
	h14 = (1.000000e+00+h9);
	highp float f15;
	highp float f16;
	f16 = h14;
	f15 = f16;
	highp float f17;
	highp float f18;
	f18 = floor((h14*v2.x));
	f17 = f18;
	vec2 v19;
	float h20;
	h20 = (f10+(-(pc1_h[0].x*trunc((f10/pc1_h[0].x)))));
	v19.x = h20;
	float h21;
	h21 = (f12+(-(pc1_h[0].y*trunc((f12/pc1_h[0].y)))));
	v19.y = h21;
	vec2 v22;
	float h23;
	h23 = (f15+(-(pc1_h[0].x*trunc((f15/pc1_h[0].x)))));
	v22.x = h23;
	float h24;
	h24 = (f17+(-(pc1_h[0].y*trunc((f17/pc1_h[0].y)))));
	v22.y = h24;
	vec4 v25;
	highp vec2 v26;
	v26.xy = v19;
	highp vec2 v27;
	v27.xy = v2;
	highp vec2 v28;
	v28.xy = v22;
	highp vec2 v29;
	v29.xy = v2;
	v25.xyzw = mix(texture(ps0,((in_TEXCOORD1.xy+v26)*v27)),texture(ps0,((in_TEXCOORD1.xy+v28)*v29)),vec4(h8));
	float h30;
	h30 = dot(v25.xyz,vec3(3.000000e-01,5.900000e-01,1.100000e-01));
	vec4 v31;
	v31.w = 0.000000e+00;
	highp float f32;
	f32 = h30;
	highp float f33;
	f33 = h30;
	vec3 v34;
	v34.xyz = (vec3(((min(max(f32,pc1_h[4].w),1.000000e+00)+(-pc1_h[4].w))*pc1_h[5].x))*pc1_h[1].xyz);
	vec3 v35;
	v35.xyz = (vec3(f33)*pc1_h[2].xyz);
	highp float f36;
	f36 = v25.w;
	float h37;
	h37 = (f36*pc1_h[5].y);
	v31.xyz = (max((v34+v35),vec3(0.000000e+00,0.000000e+00,0.000000e+00))*vec3(clamp(h37,0.000000e+00,1.000000e+00)));
	v1.xyzw = v31;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h38;
		h38 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v31.xyz);
		highp vec3 v39;
		highp float f40;
		f40 = h38;
		v39.x = f40;
		highp float f41;
		f41 = h38;
		v39.y = f41;
		highp float f42;
		f42 = h38;
		v39.z = f42;
		highp vec3 v43;
		v43.xyz = v31.xyz;
		vec3 v44;
		v44.xyz = mix(v43,v39,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v1.xyz = v44;
		float h45;
		h45 = distance(v1.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v1.xyz = mix(v1.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h45,0.000000e+00,8.000000e-01)));
	}
	vec4 v46;
	v46.xyzw = v1;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v47;
		v47.xyz = v1.xyz;
		highp float f48;
		f48 = pu_m[0].w;
		vec3 v49;
		v49.xyz = clamp((((v47+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f48))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v46.xyz = v49;
	}
	v1.xyzw = v46;
	vec3 v50;
	v50.xyz = v46.xyz;
	vec3 v51;
	v51.xyz = v46.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v52;
		v52.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v50,pu_m[0].xxx));
		v51.xyz = min((v52*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v52,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v1.xyz = v51;
	out_Target0.xyzw = v1;
}

