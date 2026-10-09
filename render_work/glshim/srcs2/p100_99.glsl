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
uniform highp vec4 pc0_h[4];
uniform vec4 pu_m[2];
uniform highp sampler2D ps0;
uniform highp sampler2D ps1;
uniform highp sampler2D ps2;
layout(location=0) in vec4 in_COLOR0;
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=4) in highp vec4 in_TEXCOORD2;
layout(location=5) in highp vec4 in_TEXCOORD3;
layout(location=0) out vec4 out_Target0;
void main()
{
	vec4 v0;
	vec4 v1;
	v1.xyzw = texture(ps2,in_TEXCOORD1.zw);
	highp vec2 v2;
	v2.xy = (in_TEXCOORD1.xy+vec2(-5.000000e-01,-5.000000e-01));
	highp float f3;
	f3 = length(v2);
	highp vec2 v4;
	v4.x = fract((atan(v2.x,v2.y)/6.283185e+00));
	v4.y = (f3*2.000000e+00);
	vec4 v5;
	v5.xyzw = texture(ps1,((v4*pc0_h[0].xy)+in_TEXCOORD2.xy));
	vec3 v6;
	v6.xyz = (v1.xyz*v5.xyz);
	highp vec2 v7;
	v7.xy = (in_TEXCOORD1.xy+vec2(-5.000000e-01,-5.000000e-01));
	highp float f8;
	f8 = length(v7);
	highp vec2 v9;
	v9.x = fract((atan(v7.x,v7.y)/6.283185e+00));
	v9.y = (f8*2.000000e+00);
	vec4 v10;
	v10.w = 0.000000e+00;
	highp vec3 v11;
	v11.xyz = (v6*texture(ps0,((v9*pc0_h[1].xy)+in_TEXCOORD2.zw)).xyz);
	vec3 v12;
	v12.xyz = (pc0_h[2].xyz*v11);
	highp float f13;
	f13 = (v1.w*v5.w);
	vec2 v14;
	v14.xy = (vec2((pc0_h[3].x*f13))*in_TEXCOORD3.xy);
	v10.xyz = (max(v12,vec3(0.000000e+00,0.000000e+00,0.000000e+00))*vec3(clamp(v14.x,0.000000e+00,1.000000e+00)));
	vec4 v15;
	v15.xyzw = ((v10*in_COLOR0)*in_COLOR0.wwww);
	v0.xyzw = v15;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h16;
		h16 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v15.xyz);
		highp vec3 v17;
		highp float f18;
		f18 = h16;
		v17.x = f18;
		highp float f19;
		f19 = h16;
		v17.y = f19;
		highp float f20;
		f20 = h16;
		v17.z = f20;
		highp vec3 v21;
		v21.xyz = v15.xyz;
		vec3 v22;
		v22.xyz = mix(v21,v17,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v0.xyz = v22;
		float h23;
		h23 = distance(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v0.xyz = mix(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h23,0.000000e+00,8.000000e-01)));
	}
	vec4 v24;
	v24.xyzw = v0;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v25;
		v25.xyz = v0.xyz;
		highp float f26;
		f26 = pu_m[0].w;
		vec3 v27;
		v27.xyz = clamp((((v25+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f26))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v24.xyz = v27;
	}
	v0.xyzw = v24;
	vec3 v28;
	v28.xyz = v24.xyz;
	vec3 v29;
	v29.xyz = v24.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v30;
		v30.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v28,pu_m[0].xxx));
		v29.xyz = min((v30*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v30,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v0.xyz = v29;
	out_Target0.xyzw = v0;
}

