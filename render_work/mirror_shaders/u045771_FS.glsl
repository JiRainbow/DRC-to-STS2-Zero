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
uniform highp vec4 pc4_h[1];
uniform highp vec4 pc3_h[4];
uniform highp vec4 pc2_h[3];
uniform highp vec4 pc5_h[1];
uniform highp vec4 pc6_h[1];
uniform ivec4 pu_i[1];
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
	int i0;
	i0 = pu_i[0].x;
	highp vec3 v1;
	v1.xyz = pc0_h[14].xyz;
	highp float f2;
	f2 = pc0_h[13].x;
	highp vec3 v3;
	v3.xyz = pc0_h[8].xyz;
	highp float f4;
	f4 = pc0_h[7].x;
	highp float f5;
	f5 = pc0_h[6].x;
	highp vec3 v6;
	v6.xyz = pc0_h[5].xyz;
	highp vec3 v7;
	v7.xyz = pc0_h[4].xyz;
	bool b8;
	b8 = compiler_internal_AdjustIsFrontFacing(gl_FrontFacing);
	vec4 v9;
	vec3 v10;
	highp float f11;
	vec4 v12;
	vec3 v13;
	vec3 v14;
	v14.xyz = in_TEXCOORD10.xyz;
	v13.xyz = v14;
	vec4 v15;
	vec4 v16;
	v16.xyzw = in_TEXCOORD11;
	v15.xyzw = v16;
	v12.xyzw = in_COLOR0;
	vec3 v17;
	v17.xyz = (cross(v15.xyz,v13)*v15.www);
	vec3 v18;
	float h19;
	highp vec3 v20;
	v20.xyz = (in_TEXCOORD8.xyz+(-v6));
	vec3 v21;
	v21.xyz = normalize((-in_TEXCOORD8.xyz));
	v18.xyz = v21;
	float h22;
	h22 = (f4*pc1_h[0].w);
	h19 = h22;
	int i23;
	i23 = (b8)?(1):(-1);
	float h24;
	h24 = float(i23);
	h19 = (h19*h24);
	vec3 v25;
	vec3 v26;
	v26.xyz = vec3(0.000000e+00,0.000000e+00,1.000000e+00);
	highp vec3 v27;
	v27.xyz = ((v15.xyz*v26.zzz)+((v17*v26.yyy)+(v13*v26.xxx)));
	vec3 v28;
	v28.xyz = normalize(v27);
	v25.xyz = v28;
	v25.xyz = (v25*vec3(h19));
	vec3 v29;
	v29.xyz = ((-v18)+((v25*vec3(dot(v25,v18)))*vec3(2.000000e+00,2.000000e+00,2.000000e+00)));
	vec4 v30;
	v30.xyzw = texture(ps0,in_TEXCOORD0.xy);
	vec4 v31;
	vec4 v32;
	v32.xyzw = pc5_h[0];
	v31.xyzw = v32;
	float h33;
	vec3 v34;
	v34.xyz = pc0_h[2].xyz;
	vec3 v35;
	v35.xyz = (v20+(-v7));
	h33 = (dot(v34,v35)+(-v31.x));
	vec3 v36;
	highp float f37;
	f37 = v31.z;
	float h38;
	h38 = (pc6_h[0].y*f37);
	v36.xyz = mix((vec3(1.000000e+00,1.000000e+00,1.000000e+00)+(-v30.xyz)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(min(max(((v31.z/(v31.y+(-v31.x)))*min(max(h33,0.000000e+00),h33)),0.000000e+00),h38)));
	highp float f39;
	f39 = 5.000000e-01;
	f11 = f39;
	float h40;
	h40 = clamp((v30.w*v12.w),0.000000e+00,1.000000e+00);
	vec3 v41;
	v41.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	float h42;
	vec2 v43;
	float h44;
	h44 = f11;
	v43.xy = ((vec2(h44)*vec2(-1.000000e+00,-2.750000e-02))+vec2(1.000000e+00,4.250000e-02));
	highp vec3 v45;
	v45.xyz = v25;
	highp vec3 v46;
	v46.xyz = v18;
	float h47;
	h47 = max(dot(v45,v46),0.000000e+00);
	h42 = ((min((v43.x*v43.x),exp2((-9.280000e+00*h47)))*v43.x)+v43.y);
	highp vec3 v48;
	highp vec4 v49;
	v49.w = 1.000000e+00;
	highp vec3 v50;
	v50.xyz = v25;
	v49.xyz = v50;
	v48.x = dot(pc0_h[10],v49);
	v48.y = dot(pc0_h[11],v49);
	v48.z = dot(pc0_h[12],v49);
	vec3 v51;
	vec3 v52;
	v52.xyz = max(vec3(0.000000e+00,0.000000e+00,0.000000e+00),v48);
	v51.xyz = v52;
	float h53;
	highp vec3 v54;
	v54.xyz = v51;
	vec3 v55;
	v55.xyz = (v54*pc0_h[9].xyz);
	h53 = dot(v55,vec3(3.000000e-01,5.900000e-01,1.100000e-01));
	float h56;
	highp vec3 v57;
	v57.xyz = v25;
	float h58;
	h58 = max(0.000000e+00,dot(v57,pc2_h[1].xyz));
	h56 = h58;
	float h59;
	float h60;
	h60 = f11;
	h59 = h60;
	highp float f61;
	highp vec3 v62;
	v62.xyz = v18;
	highp vec3 v63;
	v63.xyz = v25;
	f61 = max(0.000000e+00,dot(v63,normalize((v62+pc2_h[1].xyz))));
	float h64;
	h64 = (h59*h59);
	float h65;
	highp float f66;
	f66 = h64;
	float h67;
	h67 = (f61*f66);
	h65 = h67;
	float h68;
	highp float f69;
	f69 = (h65*h65);
	highp float f70;
	f70 = h64;
	float h71;
	h71 = (f70/((1.000000e+00+(-(f61*f61)))+f69));
	h68 = h71;
	vec3 v72;
	highp vec3 v73;
	v73.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	highp float f74;
	f74 = 0.000000e+00;
	highp float f75;
	f75 = 1.000000e+00;
	highp vec3 v76;
	v76.xyz = vec3((h42*(h56*(((h59*2.500000e-01)+2.500000e-01)*min((h68*h68),2.048000e+03)))));
	highp vec3 v77;
	v77.xyz = (vec3(h56)*v41);
	vec3 v78;
	v78.xyz = (v73*v3);
	vec3 v79;
	v79.xyz = ((vec3((f75+(f74*in_TEXCOORD5.x)))*pc2_h[0].xyz)*(v77+(v76*pc2_h[2].zzz)));
	v72.xyz = (v78+v79);
	v10.xyz = v72;
	float h80;
	float h81;
	h81 = f11;
	h80 = h81;
	float h82;
	float h83;
	h83 = pc4_h[0].z;
	h82 = h83;
	vec4 v84;
	v84.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h85;
	float h86;
	h86 = float((pc4_h[0].y>0.000000e+00));
	h85 = h86;
	if (bool(h85))
	{
		float h87;
		h87 = pc4_h[0].y;
		highp float f88;
		f88 = ((h87+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h80,1.000000e-03)))))));
		highp vec3 v89;
		v89.xyz = textureLod(ps1,v29,f88).xyz;
		highp float f90;
		f90 = 1.000000e+00;
		vec3 v91;
		v91.xyz = ((v89*pc0_h[9].xyz)*vec3(f90));
		v84.xyz = v91;
	}
	else
	{
		vec4 v92;
		float h93;
		h93 = f2;
		highp float f94;
		f94 = ((h93+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h80,1.000000e-03)))))));
		v92.xyzw = textureLod(ps1,v29,f94);
		vec3 v95;
		v95.xyz = (v92.xyz*vec3((v92.w*h82)));
		vec3 v96;
		v96.xyz = (v95*v95);
		v84.xyz = v96;
		float h97;
		h97 = pc4_h[0].x;
		highp float f98;
		f98 = (h53/max(h97,1.000000e-04));
		highp float f99;
		f99 = h80;
		float h100;
		h100 = min(f98,v1.z);
		float h101;
		h101 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f99*v1.x)+v1.y),0.000000e+00,1.000000e+00));
		v84.xyz = (v96*vec3(mix(1.000000e+00,h100,h101)));
		vec3 v102;
		v102.xyz = v3;
		v84.xyz = (v84.xyz*v102);
	}
	vec3 v103;
	v103.xyz = (v72+(v84.xyz*vec3(h42)));
	v10.xyz = v103;
	if ((i0>0))
	{
		vec3 v104;
		v104.xyz = v103;
		uint u105;
		u105 = uint(pc3_h[3].w);
		if ((((u105&1u)|2u)!=0u))
		{
			highp float f106;
			highp vec3 v107;
			v107.xyz = (pc3_h[0].xyz+(-v20));
			highp float f108;
			f108 = dot(v107,v107);
			vec3 v109;
			vec3 v110;
			v110.xyz = (v107*vec3(inversesqrt(f108)));
			v109.xyz = v110;
			float h111;
			h111 = max(0.000000e+00,dot(v25,v109));
			highp float f112;
			highp vec3 v113;
			v113.xyz = (v18+v109);
			highp vec3 v114;
			v114.xyz = v25;
			f112 = max(0.000000e+00,dot(v114,normalize(v113)));
			if ((pc3_h[1].w==0.000000e+00))
			{
				highp float f115;
				f115 = (f108*(pc3_h[0].w*pc3_h[0].w));
				highp float f116;
				f116 = clamp((1.000000e+00+(-(f115*f115))),0.000000e+00,1.000000e+00);
				f106 = ((1.0/((f108+1.000000e+00)))*(f116*f116));
			}
			else
			{
				highp vec3 v117;
				v117.xyz = (v107*pc3_h[0].www);
				f106 = pow((1.000000e+00+(-clamp(dot(v117,v117),0.000000e+00,1.000000e+00))),pc3_h[1].w);
			}
			float h118;
			float h119;
			h119 = f11;
			h118 = h119;
			highp float f120;
			f120 = f112;
			float h121;
			h121 = (h118*h118);
			float h122;
			highp float f123;
			f123 = h121;
			float h124;
			h124 = (f120*f123);
			h122 = h124;
			float h125;
			highp float f126;
			f126 = (h122*h122);
			highp float f127;
			f127 = h121;
			float h128;
			h128 = (f127/((1.000000e+00+(-(f120*f120)))+f126));
			h125 = h128;
			highp float f129;
			f129 = 3.141593e+00;
			highp vec3 v130;
			v130.xyz = vec3((h42*(h111*(((h118*2.500000e-01)+2.500000e-01)*min((h125*h125),2.048000e+03)))));
			highp vec3 v131;
			v131.xyz = (vec3(h111)*v41);
			vec3 v132;
			v132.xyz = min(vec3(6.500000e+04,6.500000e+04,6.500000e+04),(((vec3(f106)*pc3_h[1].xyz)*vec3((1.0/(f129))))*(v131+(v130*pc3_h[2].www))));
			v104.xyz = (v103+v132);
		}
		v10.xyz = v104;
	}
	vec4 v133;
	vec3 v134;
	v134.xyz = pc0_h[9].xyz;
	v133.xyz = ((((v10+((v51*v134)*v41))+max(v36,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v133.w = h40;
	v9.xyzw = v133;
	float h135;
	h135 = f5;
	v9.xyz = (v133.xyz*vec3(h135));
	out_Target0.xyzw = v9;
}

