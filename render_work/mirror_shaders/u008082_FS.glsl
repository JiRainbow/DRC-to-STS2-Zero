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
uniform highp vec4 pc1_h[2];
uniform highp vec4 pc5_h[1];
uniform highp vec4 pc4_h[4];
uniform highp vec4 pc3_h[8];
uniform highp vec4 pc6_h[1];
uniform highp vec4 pc7_h[1];
uniform highp vec4 pc2_h[2];
uniform ivec4 pu_i[1];
uniform highp sampler2D ps0;
uniform highp samplerCube ps1;
uniform highp sampler2DShadow ps2;
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
	f3 = pc0_h[14].x;
	highp vec3 v4;
	v4.xyz = pc0_h[13].xyz;
	highp float f5;
	f5 = pc0_h[12].x;
	highp vec3 v6;
	v6.xyz = pc0_h[10].xyz;
	highp float f7;
	f7 = pc0_h[9].x;
	highp float f8;
	f8 = pc0_h[8].x;
	highp vec3 v9;
	v9.xyz = pc0_h[5].xyz;
	highp vec3 v10;
	v10.xyz = pc0_h[4].xyz;
	highp vec4 v11;
	v11.xyzw = gl_FragCoord;
	v11.w = (1.0/(gl_FragCoord.w));
	bool b12;
	b12 = compiler_internal_AdjustIsFrontFacing(gl_FrontFacing);
	vec4 v13;
	vec3 v14;
	highp float f15;
	vec4 v16;
	vec3 v17;
	vec3 v18;
	v18.xyz = in_TEXCOORD10.xyz;
	v17.xyz = v18;
	vec4 v19;
	vec4 v20;
	v20.xyzw = in_TEXCOORD11;
	v19.xyzw = v20;
	v16.xyzw = in_COLOR0;
	vec3 v21;
	v21.xyz = (cross(v19.xyz,v17)*v19.www);
	highp vec4 v22;
	highp vec3 v23;
	v23.xy = ((((gl_FragCoord.xy+(-pc0_h[6].xy))*pc0_h[7].zw)+vec2(-5.000000e-01,-5.000000e-01))*vec2(2.000000e+00,-2.000000e+00));
	v23.z = gl_FragCoord.z;
	highp vec4 v24;
	v24.w = 1.000000e+00;
	v24.xyz = v23;
	v22.xyzw = (v24*v11.wwww);
	vec3 v25;
	float h26;
	highp vec3 v27;
	v27.xyz = (in_TEXCOORD8.xyz+(-v9));
	vec3 v28;
	v28.xyz = normalize((-in_TEXCOORD8.xyz));
	v25.xyz = v28;
	float h29;
	h29 = (f7*pc1_h[0].w);
	h26 = h29;
	int i30;
	i30 = (b12)?(1):(-1);
	float h31;
	h31 = float(i30);
	h26 = (h26*h31);
	vec3 v32;
	vec3 v33;
	v33.xyz = vec3(0.000000e+00,0.000000e+00,1.000000e+00);
	highp vec3 v34;
	v34.xyz = ((v19.xyz*v33.zzz)+((v21*v33.yyy)+(v17*v33.xxx)));
	vec3 v35;
	v35.xyz = normalize(v34);
	v32.xyz = v35;
	v32.xyz = (v32*vec3(h26));
	vec3 v36;
	v36.xyz = ((-v25)+((v32*vec3(dot(v32,v25)))*vec3(2.000000e+00,2.000000e+00,2.000000e+00)));
	vec4 v37;
	v37.xyzw = texture(ps0,in_TEXCOORD0.xy);
	vec4 v38;
	vec4 v39;
	v39.xyzw = pc6_h[0];
	v38.xyzw = v39;
	float h40;
	vec3 v41;
	v41.xyz = pc0_h[2].xyz;
	vec3 v42;
	v42.xyz = (v27+(-v10));
	h40 = (dot(v41,v42)+(-v38.x));
	vec3 v43;
	highp float f44;
	f44 = v38.z;
	float h45;
	h45 = (pc7_h[0].y*f44);
	v43.xyz = mix((vec3(1.000000e+00,1.000000e+00,1.000000e+00)+(-v37.xyz)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(min(max(((v38.z/(v38.y+(-v38.x)))*min(max(h40,0.000000e+00),h40)),0.000000e+00),h45)));
	highp float f46;
	f46 = 5.000000e-01;
	f15 = f46;
	float h47;
	h47 = clamp((v37.w*v16.w),0.000000e+00,1.000000e+00);
	v14.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	vec3 v48;
	v48.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	float h49;
	vec2 v50;
	float h51;
	h51 = f15;
	v50.xy = ((vec2(h51)*vec2(-1.000000e+00,-2.750000e-02))+vec2(1.000000e+00,4.250000e-02));
	highp vec3 v52;
	v52.xyz = v32;
	highp vec3 v53;
	v53.xyz = v25;
	float h54;
	h54 = max(dot(v52,v53),0.000000e+00);
	h49 = ((min((v50.x*v50.x),exp2((-9.280000e+00*h54)))*v50.x)+v50.y);
	float h55;
	if (((f2>0.000000e+00)&&(f3>0.000000e+00)))
	{
		float h56;
		h56 = f1;
		h55 = h56;
	}
	else
	{
		h55 = 1.000000e+00;
	}
	float h57;
	highp float f58;
	f58 = (1.000000e+00+(-h55));
	highp float f59;
	f59 = h55;
	float h60;
	h60 = (f59+(f58*in_TEXCOORD5.x));
	h57 = h60;
	vec3 v61;
	vec3 v62;
	v62.xyz = pc2_h[1].xyz;
	v61.xyz = v62;
	float h63;
	vec3 v64;
	v64.xyz = v6;
	h63 = (dot(v61,vec3(3.000000e-01,5.900000e-01,1.100000e-01))*dot(v64,vec3(3.000000e-01,5.900000e-01,1.100000e-01)));
	vec3 v65;
	highp vec3 v66;
	v66.xyz = (v48*v61);
	vec3 v67;
	v67.xyz = (v66*v6);
	v65.xyz = v67;
	v14.xyz = v65;
	float h68;
	h68 = 1.000000e+00;
	highp vec2 v69;
	v69.xy = v22.xy;
	highp float f70;
	f70 = v22.w;
	highp vec4 v71;
	float h72;
	h72 = 1.000000e+00;
	v71.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	if ((v22.w<pc3_h[3].x))
	{
		highp vec4 v73;
		v73.w = 1.000000e+00;
		v73.x = v69.x;
		v73.y = v69.y;
		v73.z = f70;
		v71.xyzw = (pc3_h[7]+((pc3_h[6]*v73.zzzz)+((pc3_h[5]*v73.yyyy)+(pc3_h[4]*v69.xxxx))));
	}
	if ((v71.z>0.000000e+00))
	{
		float h74;
		float h75;
		h75 = float(texture(ps2,vec3(v71.xy,min(v71.z,9.999900e-01))));
		h74 = h75;
		h72 = h74;
		h68 = max(max(1.000000e+00,h74),h57);
	}
	else
	{
		h68 = 1.000000e+00;
	}
	float h76;
	highp vec3 v77;
	v77.xyz = v32;
	float h78;
	h78 = max(0.000000e+00,dot(v77,pc3_h[1].xyz));
	h76 = h78;
	float h79;
	float h80;
	h80 = f15;
	h79 = h80;
	highp float f81;
	highp vec3 v82;
	v82.xyz = v25;
	highp vec3 v83;
	v83.xyz = v32;
	f81 = max(0.000000e+00,dot(v83,normalize((v82+pc3_h[1].xyz))));
	float h84;
	h84 = (h79*h79);
	float h85;
	highp float f86;
	f86 = h84;
	float h87;
	h87 = (f81*f86);
	h85 = h87;
	float h88;
	highp float f89;
	f89 = (h85*h85);
	highp float f90;
	f90 = h84;
	float h91;
	h91 = (f90/((1.000000e+00+(-(f81*f81)))+f89));
	h88 = h91;
	vec3 v92;
	highp float f93;
	f93 = min(h72,h57);
	highp vec3 v94;
	v94.xyz = vec3((h49*(h76*(((h79*2.500000e-01)+2.500000e-01)*min((h88*h88),2.048000e+03)))));
	highp vec3 v95;
	v95.xyz = (vec3(h76)*v48);
	vec3 v96;
	v96.xyz = ((vec3(f93)*pc3_h[0].xyz)*(v95+(v94*pc3_h[2].zzz)));
	v92.xyz = ((v65*vec3(h68))+v96);
	v14.xyz = v92;
	float h97;
	float h98;
	h98 = f15;
	h97 = h98;
	float h99;
	float h100;
	h100 = pc5_h[0].z;
	h99 = h100;
	vec4 v101;
	v101.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h102;
	float h103;
	h103 = float((pc5_h[0].y>0.000000e+00));
	h102 = h103;
	if (bool(h102))
	{
		float h104;
		h104 = pc5_h[0].y;
		highp float f105;
		f105 = ((h104+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h97,1.000000e-03)))))));
		highp vec3 v106;
		v106.xyz = textureLod(ps1,v36,f105).xyz;
		highp float f107;
		f107 = 1.000000e+00;
		vec3 v108;
		v108.xyz = ((v106*pc0_h[11].xyz)*vec3(f107));
		v101.xyz = v108;
	}
	else
	{
		vec4 v109;
		float h110;
		h110 = f5;
		highp float f111;
		f111 = ((h110+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h97,1.000000e-03)))))));
		v109.xyzw = textureLod(ps1,v36,f111);
		vec3 v112;
		v112.xyz = (v109.xyz*vec3((v109.w*h99)));
		vec3 v113;
		v113.xyz = (v112*v112);
		v101.xyz = v113;
		float h114;
		h114 = pc5_h[0].x;
		highp float f115;
		f115 = (h63/max(h114,1.000000e-04));
		highp float f116;
		f116 = h97;
		float h117;
		h117 = min(f115,v4.z);
		float h118;
		h118 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f116*v4.x)+v4.y),0.000000e+00,1.000000e+00));
		v101.xyz = (v113*vec3(mix(1.000000e+00,h117,h118)));
		vec3 v119;
		v119.xyz = v6;
		v101.xyz = (v101.xyz*v119);
	}
	vec3 v120;
	v120.xyz = (v92+(v101.xyz*vec3(h49)));
	v14.xyz = v120;
	if ((i0>0))
	{
		vec3 v121;
		v121.xyz = v120;
		uint u122;
		u122 = uint(pc4_h[3].w);
		if ((((u122&1u)|2u)!=0u))
		{
			highp float f123;
			highp vec3 v124;
			v124.xyz = (pc4_h[0].xyz+(-v27));
			highp float f125;
			f125 = dot(v124,v124);
			vec3 v126;
			vec3 v127;
			v127.xyz = (v124*vec3(inversesqrt(f125)));
			v126.xyz = v127;
			float h128;
			h128 = max(0.000000e+00,dot(v32,v126));
			highp float f129;
			highp vec3 v130;
			v130.xyz = (v25+v126);
			highp vec3 v131;
			v131.xyz = v32;
			f129 = max(0.000000e+00,dot(v131,normalize(v130)));
			if ((pc4_h[1].w==0.000000e+00))
			{
				highp float f132;
				f132 = (f125*(pc4_h[0].w*pc4_h[0].w));
				highp float f133;
				f133 = clamp((1.000000e+00+(-(f132*f132))),0.000000e+00,1.000000e+00);
				f123 = ((1.0/((f125+1.000000e+00)))*(f133*f133));
			}
			else
			{
				highp vec3 v134;
				v134.xyz = (v124*pc4_h[0].www);
				f123 = pow((1.000000e+00+(-clamp(dot(v134,v134),0.000000e+00,1.000000e+00))),pc4_h[1].w);
			}
			float h135;
			float h136;
			h136 = f15;
			h135 = h136;
			highp float f137;
			f137 = f129;
			float h138;
			h138 = (h135*h135);
			float h139;
			highp float f140;
			f140 = h138;
			float h141;
			h141 = (f137*f140);
			h139 = h141;
			float h142;
			highp float f143;
			f143 = (h139*h139);
			highp float f144;
			f144 = h138;
			float h145;
			h145 = (f144/((1.000000e+00+(-(f137*f137)))+f143));
			h142 = h145;
			highp float f146;
			f146 = 3.141593e+00;
			highp vec3 v147;
			v147.xyz = vec3((h49*(h128*(((h135*2.500000e-01)+2.500000e-01)*min((h142*h142),2.048000e+03)))));
			highp vec3 v148;
			v148.xyz = (vec3(h128)*v48);
			vec3 v149;
			v149.xyz = min(vec3(6.500000e+04,6.500000e+04,6.500000e+04),(((vec3(f123)*pc4_h[1].xyz)*vec3((1.0/(f146))))*(v148+(v147*pc4_h[2].www))));
			v121.xyz = (v120+v149);
		}
		v14.xyz = v121;
	}
	vec4 v150;
	v150.xyz = (((v14+max(v43,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v150.w = h47;
	v13.xyzw = v150;
	float h151;
	h151 = f8;
	v13.xyz = (v150.xyz*vec3(h151));
	out_Target0.xyzw = v13;
}

