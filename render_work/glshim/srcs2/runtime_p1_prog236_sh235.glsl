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
uniform vec4 pu_m[2];
uniform highp sampler2D ps0;
layout(location=0) in vec4 in_COLOR0;
layout(location=2) in highp vec4 in_TEXCOORD0;
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=0) out vec4 out_Target0;
void main()
{
	vec4 v0;
	vec4 v1;
	vec2 v2;
	highp vec2 v3;
	v3.xy = vec2(5.000000e-01,5.000000e-01);
	vec2 v4;
	v4.xy = (in_TEXCOORD0.xy+(-v3));
	v2.xy = v4;
	float h5;
	h5 = abs(v2.x);
	float h6;
	h6 = pow(h5,2.000000e+00);
	float h7;
	h7 = ((h5<=0.000000e+00))?(0.000000e+00):(h6);
	float h8;
	h8 = abs(v2.y);
	float h9;
	h9 = pow(h8,2.000000e+00);
	float h10;
	h10 = ((h8<=0.000000e+00))?(0.000000e+00):(h9);
	vec4 v11;
	v11.xyz = max(in_COLOR0.www,vec3(0.000000e+00,0.000000e+00,0.000000e+00));
	v11.w = clamp(((4.000000e-01+(-sqrt((h7+h10))))*2.000000e+00),0.000000e+00,1.000000e+00);
	vec4 v12;
	v12.xyzw = (v11*in_COLOR0);
	v1.xyzw = v12;
	float h13;
	h13 = texture(ps0,in_TEXCOORD1.xy).x;
	v1.w = (v12.w*h13);
	v0.xyzw = v1;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h14;
		h14 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v1.xyz);
		highp vec3 v15;
		highp float f16;
		f16 = h14;
		v15.x = f16;
		highp float f17;
		f17 = h14;
		v15.y = f17;
		highp float f18;
		f18 = h14;
		v15.z = f18;
		highp vec3 v19;
		v19.xyz = v1.xyz;
		vec3 v20;
		v20.xyz = mix(v19,v15,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v0.xyz = v20;
		float h21;
		h21 = distance(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v0.xyz = mix(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h21,0.000000e+00,8.000000e-01)));
	}
	vec4 v22;
	v22.xyzw = v0;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v23;
		v23.xyz = v0.xyz;
		highp float f24;
		f24 = pu_m[0].w;
		vec3 v25;
		v25.xyz = clamp((((v23+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f24))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v22.xyz = v25;
	}
	v0.xyzw = v22;
	vec3 v26;
	v26.xyz = v22.xyz;
	vec3 v27;
	v27.xyz = v22.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v28;
		v28.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v26,pu_m[0].xxx));
		v27.xyz = min((v28*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v28,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v0.xyz = v27;
	out_Target0.xyzw = v0;
}

