#version 310 es

#define INTERFACE_BLOCK(Pos, Interp, Modifiers, Semantic, PreType, PostType) layout(location=Pos) Modifiers Semantic { PreType PostType; }
#define HLSLCC_DX11ClipSpace 1 


// end extensions

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
uniform vec4 vc0_h[1];
uniform vec4 vc1_h[12];
uniform vec4 vu_h[5];
layout(location=0) in vec4 in_ATTRIBUTE0;
layout(location=1) in vec2 in_ATTRIBUTE1;
layout(location=2) in vec3 in_ATTRIBUTE2;
layout(location=3) in mediump vec4 in_ATTRIBUTE3;
layout(location=0) out mediump vec4 var_COLOR0;
layout(location=1) out vec4 var_ORIGINAL_POSITION;
layout(location=2) out vec4 var_TEXCOORD0;
layout(location=3) out vec4 var_TEXCOORD1;
layout(location=4) out vec4 var_TEXCOORD2;
layout(location=5) out vec4 var_TEXCOORD3;
layout(location=6) out vec4 var_TEXCOORD4;
layout(location=7) out vec4 var_TEXCOORD5;
void main()
{
	float f0;
	f0 = vc0_h[0].x;
	vec4 v1;
	mediump vec4 v2;
	vec4 v3;
	vec4 v4;
	vec4 v5;
	vec4 v6;
	vec4 v7;
	vec4 v8;
	vec4 v9;
	mediump vec4 v10;
	v10.xyzw = in_ATTRIBUTE3;
	vec4 v11;
	vec4 v12;
	vec4 v13;
	vec4 t14[5];
	v11.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	v13.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	t14[0].xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	t14[1].xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	t14[2].xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	t14[3].xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	t14[4].xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	vec4 v15;
	v15.zw = vec2(0.000000e+00,1.000000e+00);
	v15.xy = in_ATTRIBUTE2.xy;
	v12.xyzw = v15;
	mediump vec3 v16;
	v16.xyz = max(vec3(6.103520e-05,6.103520e-05,6.103520e-05),in_ATTRIBUTE3.xyz);
	mediump vec3 v17;
	v17.xyz = pow(((v16*vec3(9.478673e-01,9.478673e-01,9.478673e-01))+vec3(5.213270e-02,5.213270e-02,5.213270e-02)),vec3(2.400000e+00,2.400000e+00,2.400000e+00));
	mediump vec3 v18;
	if (greaterThan(v16,vec3(4.045000e-02,4.045000e-02,4.045000e-02)).x)
	{
		v18.x = v17.x;
	}
	else
	{
		v18.x = (v16*vec3(7.739938e-02,7.739938e-02,7.739938e-02)).x;
	}
	if (greaterThan(v16,vec3(4.045000e-02,4.045000e-02,4.045000e-02)).y)
	{
		v18.y = v17.y;
	}
	else
	{
		v18.y = (v16*vec3(7.739938e-02,7.739938e-02,7.739938e-02)).y;
	}
	if (greaterThan(v16,vec3(4.045000e-02,4.045000e-02,4.045000e-02)).z)
	{
		v18.z = v17.z;
	}
	else
	{
		v18.z = (v16*vec3(7.739938e-02,7.739938e-02,7.739938e-02)).z;
	}
	v10.xyz = v18;
	v13.xy = in_ATTRIBUTE1;
	t14[0].xyzw = in_ATTRIBUTE0;
	vec2 v19;
	v19.xy = (in_ATTRIBUTE0.xy+vec2(-5.000000e-01,-5.000000e-01));
	vec2 v20;
	v20.x = dot(vc1_h[0].xy,v19);
	v20.y = dot(vc1_h[1].xy,v19);
	t14[int((0u/2u))].xy = in_ATTRIBUTE0.xy;
	t14[int((1u/2u))].zw = (((vc1_h[2].xy*(vec2(5.000000e-01,5.000000e-01)+v20))+vc1_h[3].xy)+(vc1_h[4].xy*vec2((f0+(-(1.000000e+03*trunc((f0/1.000000e+03))))))));
	t14[int((2u/2u))].xy = (((vc1_h[5].xy*in_ATTRIBUTE0.xy)+vc1_h[6].xy)+(vc1_h[7].xy*vec2((f0+(-(1.000000e+03*trunc((f0/1.000000e+03))))))));
	t14[int((3u/2u))].zw = (((vc1_h[8].xy*in_ATTRIBUTE0.xy)+vc1_h[9].xy)+(vc1_h[10].xy*vec2((f0+(-(1.000000e+03*trunc((f0/1.000000e+03))))))));
	t14[int((4u/2u))].xy = vec2(((1.000000e+00+(-sin((((f0+(-(1.000000e+03*trunc((f0/1.000000e+03)))))*vc1_h[11].x)*6.283185e+00))))+vc1_h[11].y));
	vec4 v21;
	v21.xyzw = (vu_h[3]+((vu_h[1]*in_ATTRIBUTE2.yyyy)+(vu_h[0]*in_ATTRIBUTE2.xxxx)));
	v11.xyzw = v21;
	v11.y = (v21.y*vu_h[4].x);
	v12.w = in_ATTRIBUTE2.z;
	v13.zw = ((v11.xy*vu_h[4].zw)+vec2(5.000000e-01,5.000000e-01));
	v1.xyzw = v11;
	v2.xyzw = v10.zyxw;
	v3.xyzw = v12;
	v4.xyzw = v13;
	v5.xyzw = t14[0];
	v6.xyzw = t14[1];
	v7.xyzw = t14[2];
	v8.xyzw = t14[3];
	v9.xyzw = t14[4];
	compiler_internal_AdjustOutputSemantic(v1);
	gl_Position.xyzw = v1;
	var_COLOR0.xyzw = v2;
	var_ORIGINAL_POSITION.xyzw = v3;
	var_TEXCOORD0.xyzw = v4;
	var_TEXCOORD1.xyzw = v5;
	var_TEXCOORD2.xyzw = v6;
	var_TEXCOORD3.xyzw = v7;
	var_TEXCOORD4.xyzw = v8;
	var_TEXCOORD5.xyzw = v9;
}

