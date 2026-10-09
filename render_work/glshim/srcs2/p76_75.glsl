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
uniform highp vec4 pc0_h[2];
uniform vec4 pu_m[2];
uniform highp sampler2D ps0;
uniform highp sampler2D ps1;
layout(location=0) in vec4 in_COLOR0;
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=4) in highp vec4 in_TEXCOORD2;
layout(location=5) in highp vec4 in_TEXCOORD3;
layout(location=0) out vec4 out_Target0;
void main()
{
	vec4 v0;
	vec4 v1;
	v1.xyzw = texture(ps1,in_TEXCOORD1.zw);
	vec4 v2;
	v2.xyzw = texture(ps0,in_TEXCOORD2.zw);
	vec4 v3;
	v3.xyz = v2.xyz;
	v3.w = v2.w;
	vec4 v4;
	highp vec3 v5;
	v5.xyz = (v1.xyz*v2.xyz);
	vec3 v6;
	v6.xyz = (pc0_h[0].xyz*v5);
	v4.xyz = max(v6,vec3(0.000000e+00,0.000000e+00,0.000000e+00));
	highp float f7;
	f7 = (v1.w*v3.w);
	vec2 v8;
	v8.xy = (vec2((pc0_h[1].x*f7))*in_TEXCOORD3.xy);
	v4.w = clamp(v8.x,0.000000e+00,1.000000e+00);
	vec4 v9;
	v9.xyzw = (v4*in_COLOR0);
	v0.xyzw = v9;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h10;
		h10 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v9.xyz);
		highp vec3 v11;
		highp float f12;
		f12 = h10;
		v11.x = f12;
		highp float f13;
		f13 = h10;
		v11.y = f13;
		highp float f14;
		f14 = h10;
		v11.z = f14;
		highp vec3 v15;
		v15.xyz = v9.xyz;
		vec3 v16;
		v16.xyz = mix(v15,v11,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v0.xyz = v16;
		float h17;
		h17 = distance(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v0.xyz = mix(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h17,0.000000e+00,8.000000e-01)));
	}
	vec4 v18;
	v18.xyzw = v0;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v19;
		v19.xyz = v0.xyz;
		highp float f20;
		f20 = pu_m[0].w;
		vec3 v21;
		v21.xyz = clamp((((v19+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f20))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v18.xyz = v21;
	}
	v0.xyzw = v18;
	vec3 v22;
	v22.xyz = v18.xyz;
	vec3 v23;
	v23.xyz = v18.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v24;
		v24.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v22,pu_m[0].xxx));
		v23.xyz = min((v24*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v24,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v0.xyz = v23;
	out_Target0.xyzw = v0;
}

