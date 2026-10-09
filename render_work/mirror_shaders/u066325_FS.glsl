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
	v1.xyz = pc0_h[11].xyz;
	highp float f2;
	f2 = pc0_h[10].x;
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
	float h48;
	highp vec3 v49;
	v49.xyz = v25;
	float h50;
	h50 = max(0.000000e+00,dot(v49,pc2_h[1].xyz));
	h48 = h50;
	float h51;
	float h52;
	h52 = f11;
	h51 = h52;
	highp float f53;
	highp vec3 v54;
	v54.xyz = v18;
	highp vec3 v55;
	v55.xyz = v25;
	f53 = max(0.000000e+00,dot(v55,normalize((v54+pc2_h[1].xyz))));
	float h56;
	h56 = (h51*h51);
	float h57;
	highp float f58;
	f58 = h56;
	float h59;
	h59 = (f53*f58);
	h57 = h59;
	float h60;
	highp float f61;
	f61 = (h57*h57);
	highp float f62;
	f62 = h56;
	float h63;
	h63 = (f62/((1.000000e+00+(-(f53*f53)))+f61));
	h60 = h63;
	vec3 v64;
	highp vec3 v65;
	v65.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	highp float f66;
	f66 = 0.000000e+00;
	highp float f67;
	f67 = 1.000000e+00;
	highp vec3 v68;
	v68.xyz = vec3((h42*(h48*(((h51*2.500000e-01)+2.500000e-01)*min((h60*h60),2.048000e+03)))));
	highp vec3 v69;
	v69.xyz = (vec3(h48)*v41);
	vec3 v70;
	v70.xyz = (v65*v3);
	vec3 v71;
	v71.xyz = ((vec3((f67+(f66*in_TEXCOORD5.x)))*pc2_h[0].xyz)*(v69+(v68*pc2_h[2].zzz)));
	v64.xyz = (v70+v71);
	v10.xyz = v64;
	float h72;
	float h73;
	h73 = f11;
	h72 = h73;
	float h74;
	float h75;
	h75 = pc4_h[0].z;
	h74 = h75;
	vec4 v76;
	v76.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h77;
	float h78;
	h78 = float((pc4_h[0].y>0.000000e+00));
	h77 = h78;
	if (bool(h77))
	{
		float h79;
		h79 = pc4_h[0].y;
		highp float f80;
		f80 = ((h79+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h72,1.000000e-03)))))));
		highp vec3 v81;
		v81.xyz = textureLod(ps1,v29,f80).xyz;
		highp float f82;
		f82 = 1.000000e+00;
		vec3 v83;
		v83.xyz = ((v81*pc0_h[9].xyz)*vec3(f82));
		v76.xyz = v83;
	}
	else
	{
		vec4 v84;
		float h85;
		h85 = f2;
		highp float f86;
		f86 = ((h85+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h72,1.000000e-03)))))));
		v84.xyzw = textureLod(ps1,v29,f86);
		vec3 v87;
		v87.xyz = (v84.xyz*vec3((v84.w*h74)));
		vec3 v88;
		v88.xyz = (v87*v87);
		v76.xyz = v88;
		float h89;
		h89 = pc4_h[0].x;
		highp float f90;
		f90 = (0.000000e+00/max(h89,1.000000e-04));
		highp float f91;
		f91 = h72;
		float h92;
		h92 = min(f90,v1.z);
		float h93;
		h93 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f91*v1.x)+v1.y),0.000000e+00,1.000000e+00));
		v76.xyz = (v88*vec3(mix(1.000000e+00,h92,h93)));
		vec3 v94;
		v94.xyz = v3;
		v76.xyz = (v76.xyz*v94);
	}
	vec3 v95;
	v95.xyz = (v64+(v76.xyz*vec3(h42)));
	v10.xyz = v95;
	if ((i0>0))
	{
		vec3 v96;
		v96.xyz = v95;
		uint u97;
		u97 = uint(pc3_h[3].w);
		if ((((u97&1u)|2u)!=0u))
		{
			highp float f98;
			highp vec3 v99;
			v99.xyz = (pc3_h[0].xyz+(-v20));
			highp float f100;
			f100 = dot(v99,v99);
			vec3 v101;
			vec3 v102;
			v102.xyz = (v99*vec3(inversesqrt(f100)));
			v101.xyz = v102;
			float h103;
			h103 = max(0.000000e+00,dot(v25,v101));
			highp float f104;
			highp vec3 v105;
			v105.xyz = (v18+v101);
			highp vec3 v106;
			v106.xyz = v25;
			f104 = max(0.000000e+00,dot(v106,normalize(v105)));
			if ((pc3_h[1].w==0.000000e+00))
			{
				highp float f107;
				f107 = (f100*(pc3_h[0].w*pc3_h[0].w));
				highp float f108;
				f108 = clamp((1.000000e+00+(-(f107*f107))),0.000000e+00,1.000000e+00);
				f98 = ((1.0/((f100+1.000000e+00)))*(f108*f108));
			}
			else
			{
				highp vec3 v109;
				v109.xyz = (v99*pc3_h[0].www);
				f98 = pow((1.000000e+00+(-clamp(dot(v109,v109),0.000000e+00,1.000000e+00))),pc3_h[1].w);
			}
			float h110;
			float h111;
			h111 = f11;
			h110 = h111;
			highp float f112;
			f112 = f104;
			float h113;
			h113 = (h110*h110);
			float h114;
			highp float f115;
			f115 = h113;
			float h116;
			h116 = (f112*f115);
			h114 = h116;
			float h117;
			highp float f118;
			f118 = (h114*h114);
			highp float f119;
			f119 = h113;
			float h120;
			h120 = (f119/((1.000000e+00+(-(f112*f112)))+f118));
			h117 = h120;
			highp float f121;
			f121 = 3.141593e+00;
			highp vec3 v122;
			v122.xyz = vec3((h42*(h103*(((h110*2.500000e-01)+2.500000e-01)*min((h117*h117),2.048000e+03)))));
			highp vec3 v123;
			v123.xyz = (vec3(h103)*v41);
			vec3 v124;
			v124.xyz = min(vec3(6.500000e+04,6.500000e+04,6.500000e+04),(((vec3(f98)*pc3_h[1].xyz)*vec3((1.0/(f121))))*(v123+(v122*pc3_h[2].www))));
			v96.xyz = (v95+v124);
		}
		v10.xyz = v96;
	}
	vec4 v125;
	v125.xyz = (((v10+max(v36,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v125.w = h40;
	v9.xyzw = v125;
	float h126;
	h126 = f5;
	v9.xyz = (v125.xyz*vec3(h126));
	out_Target0.xyzw = v9;
}

