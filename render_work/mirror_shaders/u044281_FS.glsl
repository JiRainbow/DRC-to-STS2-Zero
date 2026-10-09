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
uniform highp vec4 pc0_h[15];
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
	v0.xyz = pc0_h[14].xyz;
	highp float f1;
	f1 = pc0_h[13].x;
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
	vec3 v39;
	v39.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	float h40;
	vec2 v41;
	float h42;
	h42 = f9;
	v41.xy = ((vec2(h42)*vec2(-1.000000e+00,-2.750000e-02))+vec2(1.000000e+00,4.250000e-02));
	highp vec3 v43;
	v43.xyz = v23;
	highp vec3 v44;
	v44.xyz = v16;
	float h45;
	h45 = max(dot(v43,v44),0.000000e+00);
	h40 = ((min((v41.x*v41.x),exp2((-9.280000e+00*h45)))*v41.x)+v41.y);
	highp vec3 v46;
	highp vec4 v47;
	v47.w = 1.000000e+00;
	highp vec3 v48;
	v48.xyz = v23;
	v47.xyz = v48;
	v46.x = dot(pc0_h[10],v47);
	v46.y = dot(pc0_h[11],v47);
	v46.z = dot(pc0_h[12],v47);
	vec3 v49;
	vec3 v50;
	v50.xyz = max(vec3(0.000000e+00,0.000000e+00,0.000000e+00),v46);
	v49.xyz = v50;
	float h51;
	highp vec3 v52;
	v52.xyz = v49;
	vec3 v53;
	v53.xyz = (v52*pc0_h[9].xyz);
	h51 = dot(v53,vec3(3.000000e-01,5.900000e-01,1.100000e-01));
	float h54;
	highp vec3 v55;
	v55.xyz = v23;
	float h56;
	h56 = max(0.000000e+00,dot(v55,pc2_h[1].xyz));
	h54 = h56;
	float h57;
	float h58;
	h58 = f9;
	h57 = h58;
	highp float f59;
	highp vec3 v60;
	v60.xyz = v16;
	highp vec3 v61;
	v61.xyz = v23;
	f59 = max(0.000000e+00,dot(v61,normalize((v60+pc2_h[1].xyz))));
	float h62;
	h62 = (h57*h57);
	float h63;
	highp float f64;
	f64 = h62;
	float h65;
	h65 = (f59*f64);
	h63 = h65;
	float h66;
	highp float f67;
	f67 = (h63*h63);
	highp float f68;
	f68 = h62;
	float h69;
	h69 = (f68/((1.000000e+00+(-(f59*f59)))+f67));
	h66 = h69;
	vec3 v70;
	highp vec3 v71;
	v71.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	highp float f72;
	f72 = 0.000000e+00;
	highp float f73;
	f73 = 1.000000e+00;
	highp vec3 v74;
	v74.xyz = vec3((h40*(h54*(((h57*2.500000e-01)+2.500000e-01)*min((h66*h66),2.048000e+03)))));
	highp vec3 v75;
	v75.xyz = (vec3(h54)*v39);
	vec3 v76;
	v76.xyz = (v71*v2);
	vec3 v77;
	v77.xyz = ((vec3((f73+(f72*in_TEXCOORD5.x)))*pc2_h[0].xyz)*(v75+(v74*pc2_h[2].zzz)));
	v70.xyz = (v76+v77);
	float h78;
	float h79;
	h79 = f9;
	h78 = h79;
	float h80;
	float h81;
	h81 = pc3_h[0].z;
	h80 = h81;
	vec4 v82;
	v82.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h83;
	float h84;
	h84 = float((pc3_h[0].y>0.000000e+00));
	h83 = h84;
	if (bool(h83))
	{
		float h85;
		h85 = pc3_h[0].y;
		highp float f86;
		f86 = ((h85+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h78,1.000000e-03)))))));
		highp vec3 v87;
		v87.xyz = textureLod(ps1,v27,f86).xyz;
		highp float f88;
		f88 = 1.000000e+00;
		vec3 v89;
		v89.xyz = ((v87*pc0_h[9].xyz)*vec3(f88));
		v82.xyz = v89;
	}
	else
	{
		vec4 v90;
		float h91;
		h91 = f1;
		highp float f92;
		f92 = ((h91+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h78,1.000000e-03)))))));
		v90.xyzw = textureLod(ps1,v27,f92);
		vec3 v93;
		v93.xyz = (v90.xyz*vec3((v90.w*h80)));
		vec3 v94;
		v94.xyz = (v93*v93);
		v82.xyz = v94;
		float h95;
		h95 = pc3_h[0].x;
		highp float f96;
		f96 = (h51/max(h95,1.000000e-04));
		highp float f97;
		f97 = h78;
		float h98;
		h98 = min(f96,v0.z);
		float h99;
		h99 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f97*v0.x)+v0.y),0.000000e+00,1.000000e+00));
		v82.xyz = (v94*vec3(mix(1.000000e+00,h98,h99)));
		vec3 v100;
		v100.xyz = v2;
		v82.xyz = (v82.xyz*v100);
	}
	vec4 v101;
	vec3 v102;
	v102.xyz = pc0_h[9].xyz;
	v101.xyz = (((((v70+(v82.xyz*vec3(h40)))+((v49*v102)*v39))+max(v34,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v101.w = h38;
	v8.xyzw = v101;
	float h103;
	h103 = f4;
	v8.xyz = (v101.xyz*vec3(h103));
	out_Target0.xyzw = v8;
}

