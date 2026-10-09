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
uniform highp vec4 pc0_h[13];
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
	f3 = pc0_h[12].x;
	highp vec3 v4;
	v4.xyz = pc0_h[11].xyz;
	highp float f5;
	f5 = pc0_h[10].x;
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
	float h55;
	vec3 v56;
	v56.xyz = v6;
	h55 = (dot(v53,vec3(3.000000e-01,5.900000e-01,1.100000e-01))*dot(v56,vec3(3.000000e-01,5.900000e-01,1.100000e-01)));
	float h57;
	highp vec3 v58;
	v58.xyz = v28;
	float h59;
	h59 = max(0.000000e+00,dot(v58,pc3_h[1].xyz));
	h57 = h59;
	float h60;
	float h61;
	h61 = f14;
	h60 = h61;
	highp float f62;
	highp vec3 v63;
	v63.xyz = v21;
	highp vec3 v64;
	v64.xyz = v28;
	f62 = max(0.000000e+00,dot(v64,normalize((v63+pc3_h[1].xyz))));
	float h65;
	h65 = (h60*h60);
	float h66;
	highp float f67;
	f67 = h65;
	float h68;
	h68 = (f62*f67);
	h66 = h68;
	float h69;
	highp float f70;
	f70 = (h66*h66);
	highp float f71;
	f71 = h65;
	float h72;
	h72 = (f71/((1.000000e+00+(-(f62*f62)))+f70));
	h69 = h72;
	vec3 v73;
	highp vec3 v74;
	v74.xyz = (v44*v53);
	highp float f75;
	f75 = (1.000000e+00+(-h51));
	highp float f76;
	f76 = h51;
	highp vec3 v77;
	v77.xyz = vec3((h45*(h57*(((h60*2.500000e-01)+2.500000e-01)*min((h69*h69),2.048000e+03)))));
	highp vec3 v78;
	v78.xyz = (vec3(h57)*v44);
	vec3 v79;
	v79.xyz = (v74*v6);
	vec3 v80;
	v80.xyz = ((vec3((f76+(f75*in_TEXCOORD5.x)))*pc3_h[0].xyz)*(v78+(v77*pc3_h[2].zzz)));
	v73.xyz = (v79+v80);
	v13.xyz = v73;
	float h81;
	float h82;
	h82 = f14;
	h81 = h82;
	float h83;
	float h84;
	h84 = pc5_h[0].z;
	h83 = h84;
	vec4 v85;
	v85.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h86;
	float h87;
	h87 = float((pc5_h[0].y>0.000000e+00));
	h86 = h87;
	if (bool(h86))
	{
		float h88;
		h88 = pc5_h[0].y;
		highp float f89;
		f89 = ((h88+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h81,1.000000e-03)))))));
		highp vec3 v90;
		v90.xyz = textureLod(ps1,v32,f89).xyz;
		highp float f91;
		f91 = 1.000000e+00;
		vec3 v92;
		v92.xyz = ((v90*pc0_h[9].xyz)*vec3(f91));
		v85.xyz = v92;
	}
	else
	{
		vec4 v93;
		float h94;
		h94 = f5;
		highp float f95;
		f95 = ((h94+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h81,1.000000e-03)))))));
		v93.xyzw = textureLod(ps1,v32,f95);
		vec3 v96;
		v96.xyz = (v93.xyz*vec3((v93.w*h83)));
		vec3 v97;
		v97.xyz = (v96*v96);
		v85.xyz = v97;
		float h98;
		h98 = pc5_h[0].x;
		highp float f99;
		f99 = (h55/max(h98,1.000000e-04));
		highp float f100;
		f100 = h81;
		float h101;
		h101 = min(f99,v4.z);
		float h102;
		h102 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f100*v4.x)+v4.y),0.000000e+00,1.000000e+00));
		v85.xyz = (v97*vec3(mix(1.000000e+00,h101,h102)));
		vec3 v103;
		v103.xyz = v6;
		v85.xyz = (v85.xyz*v103);
	}
	vec3 v104;
	v104.xyz = (v73+(v85.xyz*vec3(h45)));
	v13.xyz = v104;
	if ((i0>0))
	{
		vec3 v105;
		v105.xyz = v104;
		uint u106;
		u106 = uint(pc4_h[3].w);
		if ((((u106&1u)|2u)!=0u))
		{
			highp float f107;
			highp vec3 v108;
			v108.xyz = (pc4_h[0].xyz+(-v23));
			highp float f109;
			f109 = dot(v108,v108);
			vec3 v110;
			vec3 v111;
			v111.xyz = (v108*vec3(inversesqrt(f109)));
			v110.xyz = v111;
			float h112;
			h112 = max(0.000000e+00,dot(v28,v110));
			highp float f113;
			highp vec3 v114;
			v114.xyz = (v21+v110);
			highp vec3 v115;
			v115.xyz = v28;
			f113 = max(0.000000e+00,dot(v115,normalize(v114)));
			if ((pc4_h[1].w==0.000000e+00))
			{
				highp float f116;
				f116 = (f109*(pc4_h[0].w*pc4_h[0].w));
				highp float f117;
				f117 = clamp((1.000000e+00+(-(f116*f116))),0.000000e+00,1.000000e+00);
				f107 = ((1.0/((f109+1.000000e+00)))*(f117*f117));
			}
			else
			{
				highp vec3 v118;
				v118.xyz = (v108*pc4_h[0].www);
				f107 = pow((1.000000e+00+(-clamp(dot(v118,v118),0.000000e+00,1.000000e+00))),pc4_h[1].w);
			}
			float h119;
			float h120;
			h120 = f14;
			h119 = h120;
			highp float f121;
			f121 = f113;
			float h122;
			h122 = (h119*h119);
			float h123;
			highp float f124;
			f124 = h122;
			float h125;
			h125 = (f121*f124);
			h123 = h125;
			float h126;
			highp float f127;
			f127 = (h123*h123);
			highp float f128;
			f128 = h122;
			float h129;
			h129 = (f128/((1.000000e+00+(-(f121*f121)))+f127));
			h126 = h129;
			highp float f130;
			f130 = 3.141593e+00;
			highp vec3 v131;
			v131.xyz = vec3((h45*(h112*(((h119*2.500000e-01)+2.500000e-01)*min((h126*h126),2.048000e+03)))));
			highp vec3 v132;
			v132.xyz = (vec3(h112)*v44);
			vec3 v133;
			v133.xyz = min(vec3(6.500000e+04,6.500000e+04,6.500000e+04),(((vec3(f107)*pc4_h[1].xyz)*vec3((1.0/(f130))))*(v132+(v131*pc4_h[2].www))));
			v105.xyz = (v104+v133);
		}
		v13.xyz = v105;
	}
	vec4 v134;
	v134.xyz = (((v13+max(v39,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v134.w = h43;
	v12.xyzw = v134;
	float h135;
	h135 = f8;
	v12.xyz = (v134.xyz*vec3(h135));
	out_Target0.xyzw = v12;
}

