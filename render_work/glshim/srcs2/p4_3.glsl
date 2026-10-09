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
uniform vec4 pu_m[1];
uniform highp sampler2D ps0;
layout(location=0) in vec4 in_COLOR0;
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=0) out vec4 out_Target0;
void main()
{
	vec4 v0;
	vec4 v1;
	v1.xyzw = (texture(ps0,(in_TEXCOORD1.xy*in_TEXCOORD1.zw))*in_COLOR0);
	v0.xyzw = v1;
	vec4 v2;
	v2.xyzw = v1;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v3;
		v3.xyz = v1.xyz;
		highp float f4;
		f4 = pu_m[0].w;
		vec3 v5;
		v5.xyz = clamp((((v3+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f4))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v2.xyz = v5;
	}
	v0.xyzw = v2;
	vec3 v6;
	v6.xyz = v2.xyz;
	vec3 v7;
	v7.xyz = v2.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v8;
		v8.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v6,pu_m[0].xxx));
		v7.xyz = min((v8*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v8,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v0.xyz = v7;
	v0.w = mix(v1.w,(1.000000e+00+(-v1.w)),pu_m[0].z);
	out_Target0.xyzw = v0;
}

