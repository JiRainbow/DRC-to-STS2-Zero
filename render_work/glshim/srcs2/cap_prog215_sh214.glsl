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
uniform highp vec4 pc1_h[1];
uniform vec4 pu_m[2];
uniform highp sampler2D ps0;
layout(location=0) in vec4 in_COLOR0;
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=0) out vec4 out_Target0;
void main()
{
	vec4 v0;
	vec4 v1;
	v1.xyzw = texture(ps0,in_TEXCOORD1.xy);
	float h2;
	vec4 v3;
	v3.xyzw = pc0_h[0];
	h2 = (2.560000e+02+(-(v3.x*1.280000e+02)));
	highp float f4;
	highp float f5;
	f5 = h2;
	f4 = f5;
	highp float f6;
	highp float f7;
	f7 = h2;
	f6 = f7;
	vec2 v8;
	float h9;
	h9 = (in_TEXCOORD1.z+(-(f4*trunc((in_TEXCOORD1.z/f4)))));
	v8.x = (h9/h2);
	highp float f10;
	f10 = h2;
	float h11;
	h11 = (in_TEXCOORD1.z/f10);
	highp float f12;
	f12 = h2;
	float h13;
	h13 = (in_TEXCOORD1.w/f12);
	v8.y = (((trunc(h11)*1.600000e+01)+trunc(h13))/2.560000e+02);
	vec3 v14;
	v14.xy = v8;
	float h15;
	h15 = (in_TEXCOORD1.w+(-(f6*trunc((in_TEXCOORD1.w/f6)))));
	v14.z = (h15/h2);
	vec4 v16;
	v16.xyz = max((((v1.www+(-v1.xyz))*v14)+(v1.xyz*in_COLOR0.xyz)),vec3(0.000000e+00,0.000000e+00,0.000000e+00));
	highp float f17;
	f17 = (v1.w*in_COLOR0.w);
	float h18;
	h18 = (f17*pc1_h[0].x);
	v16.w = clamp(h18,0.000000e+00,1.000000e+00);
	v0.xyzw = v16;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h19;
		h19 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v16.xyz);
		highp vec3 v20;
		highp float f21;
		f21 = h19;
		v20.x = f21;
		highp float f22;
		f22 = h19;
		v20.y = f22;
		highp float f23;
		f23 = h19;
		v20.z = f23;
		highp vec3 v24;
		v24.xyz = v16.xyz;
		vec3 v25;
		v25.xyz = mix(v24,v20,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v0.xyz = v25;
		float h26;
		h26 = distance(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v0.xyz = mix(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h26,0.000000e+00,8.000000e-01)));
	}
	vec4 v27;
	v27.xyzw = v0;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v28;
		v28.xyz = v0.xyz;
		highp float f29;
		f29 = pu_m[0].w;
		vec3 v30;
		v30.xyz = clamp((((v28+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f29))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v27.xyz = v30;
	}
	v0.xyzw = v27;
	vec3 v31;
	v31.xyz = v27.xyz;
	vec3 v32;
	v32.xyz = v27.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v33;
		v33.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v31,pu_m[0].xxx));
		v32.xyz = min((v33*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v33,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v0.xyz = v32;
	out_Target0.xyzw = v0;
}

