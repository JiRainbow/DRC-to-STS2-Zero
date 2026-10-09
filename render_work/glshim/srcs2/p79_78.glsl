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
uniform highp vec4 pc0_h[3];
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
	vec3 v3;
	v3.xyz = (v1.xyz*v2.xyz);
	vec4 v4;
	v4.xyz = v2.xyz;
	v4.w = v2.w;
	vec4 v5;
	v5.w = 0.000000e+00;
	highp float f6;
	f6 = v3.x;
	highp float f7;
	f7 = v3.x;
	vec3 v8;
	v8.xyz = (pc0_h[0].xyz*vec3(((min(max(f6,pc0_h[2].x),1.000000e+00)+(-pc0_h[2].x))*pc0_h[2].y)));
	vec3 v9;
	v9.xyz = (vec3(f7)*pc0_h[1].xyz);
	highp float f10;
	f10 = (v1.w*v4.w);
	vec2 v11;
	v11.xy = (vec2((pc0_h[2].z*f10))*in_TEXCOORD3.xy);
	v5.xyz = (max((v8+v9),vec3(0.000000e+00,0.000000e+00,0.000000e+00))*vec3(clamp(v11.x,0.000000e+00,1.000000e+00)));
	vec4 v12;
	v12.xyzw = ((v5*in_COLOR0)*in_COLOR0.wwww);
	v0.xyzw = v12;
	if ((pu_m[1].x!=0.000000e+00))
	{
		float h13;
		h13 = dot(vec3(3.000000e-01,5.900000e-01,1.100000e-01),v12.xyz);
		highp vec3 v14;
		highp float f15;
		f15 = h13;
		v14.x = f15;
		highp float f16;
		f16 = h13;
		v14.y = f16;
		highp float f17;
		f17 = h13;
		v14.z = f17;
		highp vec3 v18;
		v18.xyz = v12.xyz;
		vec3 v19;
		v19.xyz = mix(v18,v14,vec3(8.000000e-01,8.000000e-01,8.000000e-01));
		v0.xyz = v19;
		float h20;
		h20 = distance(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01));
		v0.xyz = mix(v0.xyz,vec3(1.000000e-01,1.000000e-01,1.000000e-01),vec3(clamp(h20,0.000000e+00,8.000000e-01)));
	}
	vec4 v21;
	v21.xyzw = v0;
	if ((pu_m[0].w!=1.000000e+00))
	{
		highp vec3 v22;
		v22.xyz = v0.xyz;
		highp float f23;
		f23 = pu_m[0].w;
		vec3 v24;
		v24.xyz = clamp((((v22+vec3(-2.500000e-01,-2.500000e-01,-2.500000e-01))*vec3(f23))+vec3(2.500000e-01,2.500000e-01,2.500000e-01)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(1.000000e+00,1.000000e+00,1.000000e+00));
		v21.xyz = v24;
	}
	v0.xyzw = v21;
	vec3 v25;
	v25.xyz = v21.xyz;
	vec3 v26;
	v26.xyz = v21.xyz;
	if ((pu_m[0].y!=1.000000e+00))
	{
		vec3 v27;
		v27.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),pow(v25,pu_m[0].xxx));
		v26.xyz = min((v27*vec3(1.292000e+01,1.292000e+01,1.292000e+01)),((pow(max(v27,vec3(3.130670e-03,3.130670e-03,3.130670e-03)),vec3(4.166667e-01,4.166667e-01,4.166667e-01))*vec3(1.055000e+00,1.055000e+00,1.055000e+00))+vec3(-5.500000e-02,-5.500000e-02,-5.500000e-02)));
	}
	v0.xyz = v26;
	out_Target0.xyzw = v0;
}

