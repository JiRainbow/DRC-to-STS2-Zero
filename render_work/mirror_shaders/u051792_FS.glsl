#version 310 es
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
uniform highp vec4 pc0_h[12];
uniform highp vec4 pc1_h[1];
uniform highp vec4 pc3_h[1];
uniform highp vec4 pc2_h[3];
uniform highp vec4 pc4_h[1];
uniform highp vec4 pc5_h[1];
uniform highp sampler2D ps0;
uniform highp samplerCube ps1;
layout(location=0) in highp vec4 in_TEXCOORD10;
layout(location=1) in highp vec4 in_TEXCOORD11;
layout(location=2) in vec4 in_COLOR0;
layout(location=3) in highp vec4 in_TEXCOORD0;
layout(location=4) in highp vec2 in_TEXCOORD5;
layout(location=5) in vec4 in_TEXCOORD7;
layout(location=6) in highp vec4 in_TEXCOORD8;
layout(location=0) out vec4 out_Target0;
void main()
{
	highp vec3 v0;
	v0.xyz = pc0_h[11].xyz;
	highp float f1;
	f1 = pc0_h[10].x;
	highp vec3 v2;
	v2.xyz = pc0_h[8].xyz;
	highp float f3;
	f3 = pc0_h[7].x;
	highp float f4;
	f4 = pc0_h[6].x;
	highp vec3 v5;
	v5.xyz = pc0_h[5].xyz;
	highp vec3 v6;
	v6.xyz = pc0_h[4].xyz;
	bool b7;
	b7 = compiler_internal_AdjustIsFrontFacing(gl_FrontFacing);
	vec4 v8;
	highp float f9;
	vec4 v10;
	vec3 v11;
	vec3 v12;
	v12.xyz = in_TEXCOORD10.xyz;
	v11.xyz = v12;
	vec4 v13;
	vec4 v14;
	v14.xyzw = in_TEXCOORD11;
	v13.xyzw = v14;
	v10.xyzw = in_COLOR0;
	vec3 v15;
	v15.xyz = (cross(v13.xyz,v11)*v13.www);
	vec3 v16;
	float h17;
	highp vec3 v18;
	v18.xyz = (in_TEXCOORD8.xyz+(-v5));
	vec3 v19;
	v19.xyz = normalize((-in_TEXCOORD8.xyz));
	v16.xyz = v19;
	float h20;
	h20 = (f3*pc1_h[0].w);
	h17 = h20;
	int i21;
	i21 = (b7)?(1):(-1);
	float h22;
	h22 = float(i21);
	h17 = (h17*h22);
	vec3 v23;
	vec3 v24;
	v24.xyz = vec3(0.000000e+00,0.000000e+00,1.000000e+00);
	highp vec3 v25;
	v25.xyz = ((v13.xyz*v24.zzz)+((v15*v24.yyy)+(v11*v24.xxx)));
	vec3 v26;
	v26.xyz = normalize(v25);
	v23.xyz = v26;
	v23.xyz = (v23*vec3(h17));
	vec3 v27;
	v27.xyz = ((-v16)+((v23*vec3(dot(v23,v16)))*vec3(2.000000e+00,2.000000e+00,2.000000e+00)));
	vec4 v28;
	v28.xyzw = texture(ps0,in_TEXCOORD0.xy);
	vec4 v29;
	vec4 v30;
	v30.xyzw = pc4_h[0];
	v29.xyzw = v30;
	float h31;
	vec3 v32;
	v32.xyz = pc0_h[2].xyz;
	vec3 v33;
	v33.xyz = (v18+(-v6));
	h31 = (dot(v32,v33)+(-v29.x));
	vec3 v34;
	highp float f35;
	f35 = v29.z;
	float h36;
	h36 = (pc5_h[0].y*f35);
	v34.xyz = mix((vec3(1.000000e+00,1.000000e+00,1.000000e+00)+(-v28.xyz)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(min(max(((v29.z/(v29.y+(-v29.x)))*min(max(h31,0.000000e+00),h31)),0.000000e+00),h36)));
	highp float f37;
	f37 = 5.000000e-01;
	f9 = f37;
	float h38;
	h38 = clamp((v28.w*v10.w),0.000000e+00,1.000000e+00);
	float h39;
	vec2 v40;
	float h41;
	h41 = f9;
	v40.xy = ((vec2(h41)*vec2(-1.000000e+00,-2.750000e-02))+vec2(1.000000e+00,4.250000e-02));
	highp vec3 v42;
	v42.xyz = v23;
	highp vec3 v43;
	v43.xyz = v16;
	float h44;
	h44 = max(dot(v42,v43),0.000000e+00);
	h39 = ((min((v40.x*v40.x),exp2((-9.280000e+00*h44)))*v40.x)+v40.y);
	float h45;
	highp vec3 v46;
	v46.xyz = v23;
	float h47;
	h47 = max(0.000000e+00,dot(v46,pc2_h[1].xyz));
	h45 = h47;
	float h48;
	float h49;
	h49 = f9;
	h48 = h49;
	highp float f50;
	highp vec3 v51;
	v51.xyz = v16;
	highp vec3 v52;
	v52.xyz = v23;
	f50 = max(0.000000e+00,dot(v52,normalize((v51+pc2_h[1].xyz))));
	float h53;
	h53 = (h48*h48);
	float h54;
	highp float f55;
	f55 = h53;
	float h56;
	h56 = (f50*f55);
	h54 = h56;
	float h57;
	highp float f58;
	f58 = (h54*h54);
	highp float f59;
	f59 = h53;
	float h60;
	h60 = (f59/((1.000000e+00+(-(f50*f50)))+f58));
	h57 = h60;
	vec3 v61;
	highp vec3 v62;
	v62.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	highp float f63;
	f63 = 0.000000e+00;
	highp float f64;
	f64 = 1.000000e+00;
	highp vec3 v65;
	v65.xyz = vec3((h39*(h45*(((h48*2.500000e-01)+2.500000e-01)*min((h57*h57),2.048000e+03)))));
	highp vec3 v66;
	v66.xyz = (vec3(h45)*vec3(0.000000e+00,0.000000e+00,0.000000e+00));
	vec3 v67;
	v67.xyz = (v62*v2);
	vec3 v68;
	v68.xyz = ((vec3((f64+(f63*in_TEXCOORD5.x)))*pc2_h[0].xyz)*(v66+(v65*pc2_h[2].zzz)));
	v61.xyz = (v67+v68);
	float h69;
	float h70;
	h70 = f9;
	h69 = h70;
	float h71;
	float h72;
	h72 = pc3_h[0].z;
	h71 = h72;
	vec4 v73;
	v73.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h74;
	float h75;
	h75 = float((pc3_h[0].y>0.000000e+00));
	h74 = h75;
	if (bool(h74))
	{
		float h76;
		h76 = pc3_h[0].y;
		highp float f77;
		f77 = ((h76+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h69,1.000000e-03)))))));
		highp vec3 v78;
		v78.xyz = textureLod(ps1,v27,f77).xyz;
		highp float f79;
		f79 = 1.000000e+00;
		vec3 v80;
		v80.xyz = ((v78*pc0_h[9].xyz)*vec3(f79));
		v73.xyz = v80;
	}
	else
	{
		vec4 v81;
		float h82;
		h82 = f1;
		highp float f83;
		f83 = ((h82+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h69,1.000000e-03)))))));
		v81.xyzw = textureLod(ps1,v27,f83);
		vec3 v84;
		v84.xyz = (v81.xyz*vec3((v81.w*h71)));
		vec3 v85;
		v85.xyz = (v84*v84);
		v73.xyz = v85;
		float h86;
		h86 = pc3_h[0].x;
		highp float f87;
		f87 = (0.000000e+00/max(h86,1.000000e-04));
		highp float f88;
		f88 = h69;
		float h89;
		h89 = min(f87,v0.z);
		float h90;
		h90 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f88*v0.x)+v0.y),0.000000e+00,1.000000e+00));
		v73.xyz = (v85*vec3(mix(1.000000e+00,h89,h90)));
		vec3 v91;
		v91.xyz = v2;
		v73.xyz = (v73.xyz*v91);
	}
	vec4 v92;
	v92.xyz = ((((v61+(v73.xyz*vec3(h39)))+max(v34,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v92.w = h38;
	v8.xyzw = v92;
	float h93;
	h93 = f4;
	v8.xyz = (v92.xyz*vec3(h93));
	out_Target0.xyzw = v8;
}

