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
uniform highp vec4 pc0_h[18];
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
	f3 = pc0_h[17].x;
	highp vec3 v4;
	v4.xyz = pc0_h[16].xyz;
	highp float f5;
	f5 = pc0_h[15].x;
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
	vec3 v63;
	highp vec3 v64;
	v64.xyz = (v48*v61);
	vec3 v65;
	v65.xyz = (v64*v6);
	v63.xyz = v65;
	highp vec3 v66;
	highp vec4 v67;
	v67.w = 1.000000e+00;
	highp vec3 v68;
	v68.xyz = v32;
	v67.xyz = v68;
	v66.x = dot(pc0_h[12],v67);
	v66.y = dot(pc0_h[13],v67);
	v66.z = dot(pc0_h[14],v67);
	vec3 v69;
	vec3 v70;
	v70.xyz = max(vec3(0.000000e+00,0.000000e+00,0.000000e+00),v66);
	v69.xyz = v70;
	v14.xyz = v63;
	float h71;
	vec3 v72;
	v72.xyz = v6;
	highp vec3 v73;
	v73.xyz = v69;
	vec3 v74;
	v74.xyz = (v73*pc0_h[11].xyz);
	h71 = ((dot(v61,vec3(3.000000e-01,5.900000e-01,1.100000e-01))*dot(v72,vec3(3.000000e-01,5.900000e-01,1.100000e-01)))+dot(v74,vec3(3.000000e-01,5.900000e-01,1.100000e-01)));
	float h75;
	h75 = 1.000000e+00;
	highp vec2 v76;
	v76.xy = v22.xy;
	highp float f77;
	f77 = v22.w;
	highp vec4 v78;
	float h79;
	h79 = 1.000000e+00;
	v78.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	if ((v22.w<pc3_h[3].x))
	{
		highp vec4 v80;
		v80.w = 1.000000e+00;
		v80.x = v76.x;
		v80.y = v76.y;
		v80.z = f77;
		v78.xyzw = (pc3_h[7]+((pc3_h[6]*v80.zzzz)+((pc3_h[5]*v80.yyyy)+(pc3_h[4]*v76.xxxx))));
	}
	if ((v78.z>0.000000e+00))
	{
		float h81;
		float h82;
		h82 = float(texture(ps2,vec3(v78.xy,min(v78.z,9.999900e-01))));
		h81 = h82;
		h79 = h81;
		h75 = max(max(1.000000e+00,h81),h57);
	}
	else
	{
		h75 = 1.000000e+00;
	}
	float h83;
	highp vec3 v84;
	v84.xyz = v32;
	float h85;
	h85 = max(0.000000e+00,dot(v84,pc3_h[1].xyz));
	h83 = h85;
	float h86;
	float h87;
	h87 = f15;
	h86 = h87;
	highp float f88;
	highp vec3 v89;
	v89.xyz = v25;
	highp vec3 v90;
	v90.xyz = v32;
	f88 = max(0.000000e+00,dot(v90,normalize((v89+pc3_h[1].xyz))));
	float h91;
	h91 = (h86*h86);
	float h92;
	highp float f93;
	f93 = h91;
	float h94;
	h94 = (f88*f93);
	h92 = h94;
	float h95;
	highp float f96;
	f96 = (h92*h92);
	highp float f97;
	f97 = h91;
	float h98;
	h98 = (f97/((1.000000e+00+(-(f88*f88)))+f96));
	h95 = h98;
	vec3 v99;
	highp float f100;
	f100 = min(h79,h57);
	highp vec3 v101;
	v101.xyz = vec3((h49*(h83*(((h86*2.500000e-01)+2.500000e-01)*min((h95*h95),2.048000e+03)))));
	highp vec3 v102;
	v102.xyz = (vec3(h83)*v48);
	vec3 v103;
	v103.xyz = ((vec3(f100)*pc3_h[0].xyz)*(v102+(v101*pc3_h[2].zzz)));
	v99.xyz = ((v63*vec3(h75))+v103);
	v14.xyz = v99;
	float h104;
	float h105;
	h105 = f15;
	h104 = h105;
	float h106;
	float h107;
	h107 = pc5_h[0].z;
	h106 = h107;
	vec4 v108;
	v108.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h109;
	float h110;
	h110 = float((pc5_h[0].y>0.000000e+00));
	h109 = h110;
	if (bool(h109))
	{
		float h111;
		h111 = pc5_h[0].y;
		highp float f112;
		f112 = ((h111+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h104,1.000000e-03)))))));
		highp vec3 v113;
		v113.xyz = textureLod(ps1,v36,f112).xyz;
		highp float f114;
		f114 = 1.000000e+00;
		vec3 v115;
		v115.xyz = ((v113*pc0_h[11].xyz)*vec3(f114));
		v108.xyz = v115;
	}
	else
	{
		vec4 v116;
		float h117;
		h117 = f5;
		highp float f118;
		f118 = ((h117+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h104,1.000000e-03)))))));
		v116.xyzw = textureLod(ps1,v36,f118);
		vec3 v119;
		v119.xyz = (v116.xyz*vec3((v116.w*h106)));
		vec3 v120;
		v120.xyz = (v119*v119);
		v108.xyz = v120;
		float h121;
		h121 = pc5_h[0].x;
		highp float f122;
		f122 = (h71/max(h121,1.000000e-04));
		highp float f123;
		f123 = h104;
		float h124;
		h124 = min(f122,v4.z);
		float h125;
		h125 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f123*v4.x)+v4.y),0.000000e+00,1.000000e+00));
		v108.xyz = (v120*vec3(mix(1.000000e+00,h124,h125)));
		vec3 v126;
		v126.xyz = v6;
		v108.xyz = (v108.xyz*v126);
	}
	vec3 v127;
	v127.xyz = (v99+(v108.xyz*vec3(h49)));
	v14.xyz = v127;
	if ((i0>0))
	{
		vec3 v128;
		v128.xyz = v127;
		uint u129;
		u129 = uint(pc4_h[3].w);
		if ((((u129&1u)|2u)!=0u))
		{
			highp float f130;
			highp vec3 v131;
			v131.xyz = (pc4_h[0].xyz+(-v27));
			highp float f132;
			f132 = dot(v131,v131);
			vec3 v133;
			vec3 v134;
			v134.xyz = (v131*vec3(inversesqrt(f132)));
			v133.xyz = v134;
			float h135;
			h135 = max(0.000000e+00,dot(v32,v133));
			highp float f136;
			highp vec3 v137;
			v137.xyz = (v25+v133);
			highp vec3 v138;
			v138.xyz = v32;
			f136 = max(0.000000e+00,dot(v138,normalize(v137)));
			if ((pc4_h[1].w==0.000000e+00))
			{
				highp float f139;
				f139 = (f132*(pc4_h[0].w*pc4_h[0].w));
				highp float f140;
				f140 = clamp((1.000000e+00+(-(f139*f139))),0.000000e+00,1.000000e+00);
				f130 = ((1.0/((f132+1.000000e+00)))*(f140*f140));
			}
			else
			{
				highp vec3 v141;
				v141.xyz = (v131*pc4_h[0].www);
				f130 = pow((1.000000e+00+(-clamp(dot(v141,v141),0.000000e+00,1.000000e+00))),pc4_h[1].w);
			}
			float h142;
			float h143;
			h143 = f15;
			h142 = h143;
			highp float f144;
			f144 = f136;
			float h145;
			h145 = (h142*h142);
			float h146;
			highp float f147;
			f147 = h145;
			float h148;
			h148 = (f144*f147);
			h146 = h148;
			float h149;
			highp float f150;
			f150 = (h146*h146);
			highp float f151;
			f151 = h145;
			float h152;
			h152 = (f151/((1.000000e+00+(-(f144*f144)))+f150));
			h149 = h152;
			highp float f153;
			f153 = 3.141593e+00;
			highp vec3 v154;
			v154.xyz = vec3((h49*(h135*(((h142*2.500000e-01)+2.500000e-01)*min((h149*h149),2.048000e+03)))));
			highp vec3 v155;
			v155.xyz = (vec3(h135)*v48);
			vec3 v156;
			v156.xyz = min(vec3(6.500000e+04,6.500000e+04,6.500000e+04),(((vec3(f130)*pc4_h[1].xyz)*vec3((1.0/(f153))))*(v155+(v154*pc4_h[2].www))));
			v128.xyz = (v127+v156);
		}
		v14.xyz = v128;
	}
	vec4 v157;
	vec3 v158;
	v158.xyz = pc0_h[11].xyz;
	v157.xyz = ((((v14+((v69*v158)*v48))+max(v43,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v157.w = h47;
	v13.xyzw = v157;
	float h159;
	h159 = f8;
	v13.xyz = (v157.xyz*vec3(h159));
	out_Target0.xyzw = v13;
}

