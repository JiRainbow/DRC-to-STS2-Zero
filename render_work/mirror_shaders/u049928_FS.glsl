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
uniform highp vec4 pc0_h[16];
uniform highp vec4 pc1_h[2];
uniform highp vec4 pc5_h[1];
uniform highp vec4 pc4_h[4];
uniform highp vec4 pc3_h[3];
uniform highp vec4 pc6_h[1];
uniform highp vec4 pc7_h[1];
uniform highp vec4 pc2_h[2];
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
	highp float f1;
	f1 = pc2_h[0].x;
	highp float f2;
	f2 = pc1_h[1].x;
	highp float f3;
	f3 = pc0_h[15].x;
	highp vec3 v4;
	v4.xyz = pc0_h[14].xyz;
	highp float f5;
	f5 = pc0_h[13].x;
	highp vec3 v6;
	v6.xyz = pc0_h[8].xyz;
	highp float f7;
	f7 = pc0_h[7].x;
	highp float f8;
	f8 = pc0_h[6].x;
	highp vec3 v9;
	v9.xyz = pc0_h[5].xyz;
	highp vec3 v10;
	v10.xyz = pc0_h[4].xyz;
	bool b11;
	b11 = compiler_internal_AdjustIsFrontFacing(gl_FrontFacing);
	vec4 v12;
	vec3 v13;
	highp float f14;
	vec4 v15;
	vec3 v16;
	vec3 v17;
	v17.xyz = in_TEXCOORD10.xyz;
	v16.xyz = v17;
	vec4 v18;
	vec4 v19;
	v19.xyzw = in_TEXCOORD11;
	v18.xyzw = v19;
	v15.xyzw = in_COLOR0;
	vec3 v20;
	v20.xyz = (cross(v18.xyz,v16)*v18.www);
	vec3 v21;
	float h22;
	highp vec3 v23;
	v23.xyz = (in_TEXCOORD8.xyz+(-v9));
	vec3 v24;
	v24.xyz = normalize((-in_TEXCOORD8.xyz));
	v21.xyz = v24;
	float h25;
	h25 = (f7*pc1_h[0].w);
	h22 = h25;
	int i26;
	i26 = (b11)?(1):(-1);
	float h27;
	h27 = float(i26);
	h22 = (h22*h27);
	vec3 v28;
	vec3 v29;
	v29.xyz = vec3(0.000000e+00,0.000000e+00,1.000000e+00);
	highp vec3 v30;
	v30.xyz = ((v18.xyz*v29.zzz)+((v20*v29.yyy)+(v16*v29.xxx)));
	vec3 v31;
	v31.xyz = normalize(v30);
	v28.xyz = v31;
	v28.xyz = (v28*vec3(h22));
	vec3 v32;
	v32.xyz = ((-v21)+((v28*vec3(dot(v28,v21)))*vec3(2.000000e+00,2.000000e+00,2.000000e+00)));
	vec4 v33;
	v33.xyzw = texture(ps0,in_TEXCOORD0.xy);
	vec4 v34;
	vec4 v35;
	v35.xyzw = pc6_h[0];
	v34.xyzw = v35;
	float h36;
	vec3 v37;
	v37.xyz = pc0_h[2].xyz;
	vec3 v38;
	v38.xyz = (v23+(-v10));
	h36 = (dot(v37,v38)+(-v34.x));
	vec3 v39;
	highp float f40;
	f40 = v34.z;
	float h41;
	h41 = (pc7_h[0].y*f40);
	v39.xyz = mix((vec3(1.000000e+00,1.000000e+00,1.000000e+00)+(-v33.xyz)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(min(max(((v34.z/(v34.y+(-v34.x)))*min(max(h36,0.000000e+00),h36)),0.000000e+00),h41)));
	highp float f42;
	f42 = 5.000000e-01;
	f14 = f42;
	float h43;
	h43 = clamp((v33.w*v15.w),0.000000e+00,1.000000e+00);
	v13.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	vec3 v44;
	v44.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	float h45;
	vec2 v46;
	float h47;
	h47 = f14;
	v46.xy = ((vec2(h47)*vec2(-1.000000e+00,-2.750000e-02))+vec2(1.000000e+00,4.250000e-02));
	highp vec3 v48;
	v48.xyz = v28;
	highp vec3 v49;
	v49.xyz = v21;
	float h50;
	h50 = max(dot(v48,v49),0.000000e+00);
	h45 = ((min((v46.x*v46.x),exp2((-9.280000e+00*h50)))*v46.x)+v46.y);
	float h51;
	if (((f2>0.000000e+00)&&(f3>0.000000e+00)))
	{
		float h52;
		h52 = f1;
		h51 = h52;
	}
	else
	{
		h51 = 1.000000e+00;
	}
	vec3 v53;
	vec3 v54;
	v54.xyz = pc2_h[1].xyz;
	v53.xyz = v54;
	highp vec3 v55;
	highp vec4 v56;
	v56.w = 1.000000e+00;
	highp vec3 v57;
	v57.xyz = v28;
	v56.xyz = v57;
	v55.x = dot(pc0_h[10],v56);
	v55.y = dot(pc0_h[11],v56);
	v55.z = dot(pc0_h[12],v56);
	vec3 v58;
	vec3 v59;
	v59.xyz = max(vec3(0.000000e+00,0.000000e+00,0.000000e+00),v55);
	v58.xyz = v59;
	float h60;
	vec3 v61;
	v61.xyz = v6;
	highp vec3 v62;
	v62.xyz = v58;
	vec3 v63;
	v63.xyz = (v62*pc0_h[9].xyz);
	h60 = ((dot(v53,vec3(3.000000e-01,5.900000e-01,1.100000e-01))*dot(v61,vec3(3.000000e-01,5.900000e-01,1.100000e-01)))+dot(v63,vec3(3.000000e-01,5.900000e-01,1.100000e-01)));
	float h64;
	highp vec3 v65;
	v65.xyz = v28;
	float h66;
	h66 = max(0.000000e+00,dot(v65,pc3_h[1].xyz));
	h64 = h66;
	float h67;
	float h68;
	h68 = f14;
	h67 = h68;
	highp float f69;
	highp vec3 v70;
	v70.xyz = v21;
	highp vec3 v71;
	v71.xyz = v28;
	f69 = max(0.000000e+00,dot(v71,normalize((v70+pc3_h[1].xyz))));
	float h72;
	h72 = (h67*h67);
	float h73;
	highp float f74;
	f74 = h72;
	float h75;
	h75 = (f69*f74);
	h73 = h75;
	float h76;
	highp float f77;
	f77 = (h73*h73);
	highp float f78;
	f78 = h72;
	float h79;
	h79 = (f78/((1.000000e+00+(-(f69*f69)))+f77));
	h76 = h79;
	vec3 v80;
	highp vec3 v81;
	v81.xyz = (v44*v53);
	highp float f82;
	f82 = (1.000000e+00+(-h51));
	highp float f83;
	f83 = h51;
	highp vec3 v84;
	v84.xyz = vec3((h45*(h64*(((h67*2.500000e-01)+2.500000e-01)*min((h76*h76),2.048000e+03)))));
	highp vec3 v85;
	v85.xyz = (vec3(h64)*v44);
	vec3 v86;
	v86.xyz = (v81*v6);
	vec3 v87;
	v87.xyz = ((vec3((f83+(f82*in_TEXCOORD5.x)))*pc3_h[0].xyz)*(v85+(v84*pc3_h[2].zzz)));
	v80.xyz = (v86+v87);
	v13.xyz = v80;
	float h88;
	float h89;
	h89 = f14;
	h88 = h89;
	float h90;
	float h91;
	h91 = pc5_h[0].z;
	h90 = h91;
	vec4 v92;
	v92.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h93;
	float h94;
	h94 = float((pc5_h[0].y>0.000000e+00));
	h93 = h94;
	if (bool(h93))
	{
		float h95;
		h95 = pc5_h[0].y;
		highp float f96;
		f96 = ((h95+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h88,1.000000e-03)))))));
		highp vec3 v97;
		v97.xyz = textureLod(ps1,v32,f96).xyz;
		highp float f98;
		f98 = 1.000000e+00;
		vec3 v99;
		v99.xyz = ((v97*pc0_h[9].xyz)*vec3(f98));
		v92.xyz = v99;
	}
	else
	{
		vec4 v100;
		float h101;
		h101 = f5;
		highp float f102;
		f102 = ((h101+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h88,1.000000e-03)))))));
		v100.xyzw = textureLod(ps1,v32,f102);
		vec3 v103;
		v103.xyz = (v100.xyz*vec3((v100.w*h90)));
		vec3 v104;
		v104.xyz = (v103*v103);
		v92.xyz = v104;
		float h105;
		h105 = pc5_h[0].x;
		highp float f106;
		f106 = (h60/max(h105,1.000000e-04));
		highp float f107;
		f107 = h88;
		float h108;
		h108 = min(f106,v4.z);
		float h109;
		h109 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f107*v4.x)+v4.y),0.000000e+00,1.000000e+00));
		v92.xyz = (v104*vec3(mix(1.000000e+00,h108,h109)));
		vec3 v110;
		v110.xyz = v6;
		v92.xyz = (v92.xyz*v110);
	}
	vec3 v111;
	v111.xyz = (v80+(v92.xyz*vec3(h45)));
	v13.xyz = v111;
	if ((i0>0))
	{
		vec3 v112;
		v112.xyz = v111;
		uint u113;
		u113 = uint(pc4_h[3].w);
		if ((((u113&1u)|2u)!=0u))
		{
			highp float f114;
			highp vec3 v115;
			v115.xyz = (pc4_h[0].xyz+(-v23));
			highp float f116;
			f116 = dot(v115,v115);
			vec3 v117;
			vec3 v118;
			v118.xyz = (v115*vec3(inversesqrt(f116)));
			v117.xyz = v118;
			float h119;
			h119 = max(0.000000e+00,dot(v28,v117));
			highp float f120;
			highp vec3 v121;
			v121.xyz = (v21+v117);
			highp vec3 v122;
			v122.xyz = v28;
			f120 = max(0.000000e+00,dot(v122,normalize(v121)));
			if ((pc4_h[1].w==0.000000e+00))
			{
				highp float f123;
				f123 = (f116*(pc4_h[0].w*pc4_h[0].w));
				highp float f124;
				f124 = clamp((1.000000e+00+(-(f123*f123))),0.000000e+00,1.000000e+00);
				f114 = ((1.0/((f116+1.000000e+00)))*(f124*f124));
			}
			else
			{
				highp vec3 v125;
				v125.xyz = (v115*pc4_h[0].www);
				f114 = pow((1.000000e+00+(-clamp(dot(v125,v125),0.000000e+00,1.000000e+00))),pc4_h[1].w);
			}
			float h126;
			float h127;
			h127 = f14;
			h126 = h127;
			highp float f128;
			f128 = f120;
			float h129;
			h129 = (h126*h126);
			float h130;
			highp float f131;
			f131 = h129;
			float h132;
			h132 = (f128*f131);
			h130 = h132;
			float h133;
			highp float f134;
			f134 = (h130*h130);
			highp float f135;
			f135 = h129;
			float h136;
			h136 = (f135/((1.000000e+00+(-(f128*f128)))+f134));
			h133 = h136;
			highp float f137;
			f137 = 3.141593e+00;
			highp vec3 v138;
			v138.xyz = vec3((h45*(h119*(((h126*2.500000e-01)+2.500000e-01)*min((h133*h133),2.048000e+03)))));
			highp vec3 v139;
			v139.xyz = (vec3(h119)*v44);
			vec3 v140;
			v140.xyz = min(vec3(6.500000e+04,6.500000e+04,6.500000e+04),(((vec3(f114)*pc4_h[1].xyz)*vec3((1.0/(f137))))*(v139+(v138*pc4_h[2].www))));
			v112.xyz = (v111+v140);
		}
		v13.xyz = v112;
	}
	vec4 v141;
	vec3 v142;
	v142.xyz = pc0_h[9].xyz;
	v141.xyz = ((((v13+((v58*v142)*v44))+max(v39,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v141.w = h43;
	v12.xyzw = v141;
	float h143;
	h143 = f8;
	v12.xyz = (v141.xyz*vec3(h143));
	out_Target0.xyzw = v12;
}

