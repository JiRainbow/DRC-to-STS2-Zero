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
	v1.xyzw = in_COLOR0;
	float h2;
	h2 = texture(ps0,in_TEXCOORD1.xy).x;
	v1.w = (in_COLOR0.w*h2);
	v0.xyzw = v1;
	vec4 v3;
	v3.xyzw = v1;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v4;
		v4.xyz = v1.xyz;
		highp float f5;
		f5 = pu_m[0].w;
		vec3 v6;
		v6.xyz = clamp((((v4+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f5))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v3.xyz = v6;
	}
	v0.xyzw = v3;
	vec3 v7;
	v7.xyz = v3.xyz;
	vec3 v8;
	v8.xyz = v3.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v9;
		v9.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v7,pu_m[0].xxx));
		v8.xyz = min((v9*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v9,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v0.xyz = v8;
	v0.w = mix(v1.w,(1.000000e+00+(-v1.w)),pu_m[0].z);
	out_Target0.xyzw = v0;
}

