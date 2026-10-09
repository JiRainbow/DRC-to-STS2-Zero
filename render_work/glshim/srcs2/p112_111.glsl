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
layout(location=0) in vec4 in_COLOR0;
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=0) out vec4 out_Target0;
void main()
{
	vec4 v0;
	vec4 v1;
	v1.w = 0.000000e+00;
	vec3 v2;
	v2.xyz = pc0_h[0].xyz;
	highp float f3;
	f3 = texture(ps0,in_TEXCOORD1.zw).w;
	float h4;
	h4 = (pc0_h[1].x*f3);
	v1.xyz = (max(v2,vec3(0.000000e+00,0.000000e+00,0.000000e+00))*vec3(clamp(h4,0.000000e+00,1.000000e+00)));
	vec4 v5;
	v5.xyzw = ((v1*in_COLOR0)*in_COLOR0.wwww);
	v0.xyzw = v5;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h6;
		h6 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v5.xyz);
		highp vec3 v7;
		highp float f8;
		f8 = h6;
		v7.x = f8;
		highp float f9;
		f9 = h6;
		v7.y = f9;
		highp float f10;
		f10 = h6;
		v7.z = f10;
		highp vec3 v11;
		v11.xyz = v5.xyz;
		vec3 v12;
		v12.xyz = mix(v11,v7,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v0.xyz = v12;
		float h13;
		h13 = distance(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v0.xyz = mix(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h13,0.000000e+00,8.000000e-01)));
	}
	vec4 v14;
	v14.xyzw = v0;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v15;
		v15.xyz = v0.xyz;
		highp float f16;
		f16 = pu_m[0].w;
		vec3 v17;
		v17.xyz = clamp((((v15+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f16))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v14.xyz = v17;
	}
	v0.xyzw = v14;
	vec3 v18;
	v18.xyz = v14.xyz;
	vec3 v19;
	v19.xyz = v14.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v20;
		v20.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v18,pu_m[0].xxx));
		v19.xyz = min((v20*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v20,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v0.xyz = v19;
	out_Target0.xyzw = v0;
}

