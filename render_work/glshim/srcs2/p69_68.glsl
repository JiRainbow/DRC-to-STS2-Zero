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
uniform highp vec4 pu_h[3];
uniform highp sampler2D ps0;
layout(location=0) in vec4 in_COLOR0;
layout(location=1) in highp vec4 in_ORIGINAL_POSITION;
layout(location=3) in highp vec4 in_TEXCOORD1;
layout(location=0) out vec4 out_Target0;
void main()
{
	highp vec2 v0;
	v0.xy = pu_h[2].xy;
	vec4 v1;
	vec4 v2;
	v2.xyzw = texture(ps0,in_TEXCOORD1.xy);
	float h3;
	vec4 v4;
	v4.xyzw = pc0_h[0];
	h3 = (2.560000e+02+(-(v4.x*1.280000e+02)));
	highp float f5;
	highp float f6;
	f6 = h3;
	f5 = f6;
	highp float f7;
	highp float f8;
	f8 = h3;
	f7 = f8;
	vec2 v9;
	float h10;
	h10 = (in_TEXCOORD1.z+(-(f5*trunc((in_TEXCOORD1.z/f5)))));
	v9.x = (h10/h3);
	highp float f11;
	f11 = h3;
	float h12;
	h12 = (in_TEXCOORD1.z/f11);
	highp float f13;
	f13 = h3;
	float h14;
	h14 = (in_TEXCOORD1.w/f13);
	v9.y = (((trunc(h12)*1.600000e+01)+trunc(h14))/2.560000e+02);
	vec3 v15;
	v15.xy = v9;
	float h16;
	h16 = (in_TEXCOORD1.w+(-(f7*trunc((in_TEXCOORD1.w/f7)))));
	v15.z = (h16/h3);
	vec4 v17;
	v17.xyz = max((((v2.www+(-v2.xyz))*v15)+(v2.xyz*in_COLOR0.xyz)),vec3(0.000000e+00,0.000000e+00,0.000000e+00));
	highp float f18;
	f18 = (v2.w*in_COLOR0.w);
	float h19;
	h19 = (f18*pc1_h[0].x);
	v17.w = clamp(h19,0.000000e+00,1.000000e+00);
	v1.xyzw = v17;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h20;
		h20 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v17.xyz);
		highp vec3 v21;
		highp float f22;
		f22 = h20;
		v21.x = f22;
		highp float f23;
		f23 = h20;
		v21.y = f23;
		highp float f24;
		f24 = h20;
		v21.z = f24;
		highp vec3 v25;
		v25.xyz = v17.xyz;
		vec3 v26;
		v26.xyz = mix(v25,v21,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v1.xyz = v26;
		float h27;
		h27 = distance(v1.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v1.xyz = mix(v1.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h27,0.000000e+00,8.000000e-01)));
	}
	vec4 v28;
	v28.xyzw = v1;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v29;
		v29.xyz = v1.xyz;
		highp float f30;
		f30 = pu_m[0].w;
		vec3 v31;
		v31.xyz = clamp((((v29+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f30))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v28.xyz = v31;
	}
	v1.xyzw = v28;
	vec3 v32;
	v32.xyz = v28.xyz;
	vec3 v33;
	v33.xyz = v28.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v34;
		v34.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v32,pu_m[0].xxx));
		v33.xyz = min((v34*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v34,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v1.xyz = v33;
	highp vec2 v35;
	v35.x = ((in_ORIGINAL_POSITION.x*pu_h[0].x)+(in_ORIGINAL_POSITION.y*pu_h[0].z));
	v35.y = ((in_ORIGINAL_POSITION.x*pu_h[0].y)+(in_ORIGINAL_POSITION.y*pu_h[0].w));
	highp vec2 v36;
	v36.xy = ((vec2(1.000000e+00,1.000000e+00)+(-abs(((v35*pu_h[1].xy)+pu_h[1].zw))))*v0);
	float h37;
	h37 = (clamp(v36.x,0.000000e+00,1.000000e+00)*clamp(v36.y,0.000000e+00,1.000000e+00));
	v1.w = (v28.w*h37);
	out_Target0.xyzw = v1;
}

