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
uniform highp vec4 pc4_h[1];
uniform highp vec4 pc3_h[8];
uniform highp vec4 pc5_h[1];
uniform highp vec4 pc6_h[1];
uniform highp vec4 pc2_h[2];
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
	highp float f0;
	f0 = pc2_h[0].x;
	highp float f1;
	f1 = pc1_h[1].x;
	highp float f2;
	f2 = pc0_h[14].x;
	highp vec3 v3;
	v3.xyz = pc0_h[13].xyz;
	highp float f4;
	f4 = pc0_h[12].x;
	highp vec3 v5;
	v5.xyz = pc0_h[10].xyz;
	highp float f6;
	f6 = pc0_h[9].x;
	highp float f7;
	f7 = pc0_h[8].x;
	highp vec3 v8;
	v8.xyz = pc0_h[5].xyz;
	highp vec3 v9;
	v9.xyz = pc0_h[4].xyz;
	highp vec4 v10;
	v10.xyzw = gl_FragCoord;
	v10.w = (1.0/(gl_FragCoord.w));
	bool b11;
	b11 = compiler_internal_AdjustIsFrontFacing(gl_FrontFacing);
	vec4 v12;
	highp float f13;
	vec4 v14;
	vec3 v15;
	vec3 v16;
	v16.xyz = in_TEXCOORD10.xyz;
	v15.xyz = v16;
	vec4 v17;
	vec4 v18;
	v18.xyzw = in_TEXCOORD11;
	v17.xyzw = v18;
	v14.xyzw = in_COLOR0;
	vec3 v19;
	v19.xyz = (cross(v17.xyz,v15)*v17.www);
	highp vec4 v20;
	highp vec3 v21;
	v21.xy = ((((gl_FragCoord.xy+(-pc0_h[6].xy))*pc0_h[7].zw)+vec2(-5.000000e-01,-5.000000e-01))*vec2(2.000000e+00,-2.000000e+00));
	v21.z = gl_FragCoord.z;
	highp vec4 v22;
	v22.w = 1.000000e+00;
	v22.xyz = v21;
	v20.xyzw = (v22*v10.wwww);
	vec3 v23;
	float h24;
	highp vec3 v25;
	v25.xyz = (in_TEXCOORD8.xyz+(-v8));
	vec3 v26;
	v26.xyz = normalize((-in_TEXCOORD8.xyz));
	v23.xyz = v26;
	float h27;
	h27 = (f6*pc1_h[0].w);
	h24 = h27;
	int i28;
	i28 = (b11)?(1):(-1);
	float h29;
	h29 = float(i28);
	h24 = (h24*h29);
	vec3 v30;
	vec3 v31;
	v31.xyz = vec3(0.000000e+00,0.000000e+00,1.000000e+00);
	highp vec3 v32;
	v32.xyz = ((v17.xyz*v31.zzz)+((v19*v31.yyy)+(v15*v31.xxx)));
	vec3 v33;
	v33.xyz = normalize(v32);
	v30.xyz = v33;
	v30.xyz = (v30*vec3(h24));
	vec3 v34;
	v34.xyz = ((-v23)+((v30*vec3(dot(v30,v23)))*vec3(2.000000e+00,2.000000e+00,2.000000e+00)));
	vec4 v35;
	v35.xyzw = texture(ps0,in_TEXCOORD0.xy);
	vec4 v36;
	vec4 v37;
	v37.xyzw = pc5_h[0];
	v36.xyzw = v37;
	float h38;
	vec3 v39;
	v39.xyz = pc0_h[2].xyz;
	vec3 v40;
	v40.xyz = (v25+(-v9));
	h38 = (dot(v39,v40)+(-v36.x));
	vec3 v41;
	highp float f42;
	f42 = v36.z;
	float h43;
	h43 = (pc6_h[0].y*f42);
	v41.xyz = mix((vec3(1.000000e+00,1.000000e+00,1.000000e+00)+(-v35.xyz)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(min(max(((v36.z/(v36.y+(-v36.x)))*min(max(h38,0.000000e+00),h38)),0.000000e+00),h43)));
	highp float f44;
	f44 = 5.000000e-01;
	f13 = f44;
	float h45;
	h45 = clamp((v35.w*v14.w),0.000000e+00,1.000000e+00);
	vec3 v46;
	v46.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	float h47;
	vec2 v48;
	float h49;
	h49 = f13;
	v48.xy = ((vec2(h49)*vec2(-1.000000e+00,-2.750000e-02))+vec2(1.000000e+00,4.250000e-02));
	highp vec3 v50;
	v50.xyz = v30;
	highp vec3 v51;
	v51.xyz = v23;
	float h52;
	h52 = max(dot(v50,v51),0.000000e+00);
	h47 = ((min((v48.x*v48.x),exp2((-9.280000e+00*h52)))*v48.x)+v48.y);
	float h53;
	if (((f1>0.000000e+00)&&(f2>0.000000e+00)))
	{
		float h54;
		h54 = f0;
		h53 = h54;
	}
	else
	{
		h53 = 1.000000e+00;
	}
	float h55;
	highp float f56;
	f56 = (1.000000e+00+(-h53));
	highp float f57;
	f57 = h53;
	float h58;
	h58 = (f57+(f56*in_TEXCOORD5.x));
	h55 = h58;
	vec3 v59;
	vec3 v60;
	v60.xyz = pc2_h[1].xyz;
	v59.xyz = v60;
	float h61;
	vec3 v62;
	v62.xyz = v5;
	h61 = (dot(v59,vec3(3.000000e-01,5.900000e-01,1.100000e-01))*dot(v62,vec3(3.000000e-01,5.900000e-01,1.100000e-01)));
	vec3 v63;
	highp vec3 v64;
	v64.xyz = (v46*v59);
	vec3 v65;
	v65.xyz = (v64*v5);
	v63.xyz = v65;
	float h66;
	h66 = 1.000000e+00;
	highp vec2 v67;
	v67.xy = v20.xy;
	highp float f68;
	f68 = v20.w;
	highp vec4 v69;
	float h70;
	h70 = 1.000000e+00;
	v69.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	if ((v20.w<pc3_h[3].x))
	{
		highp vec4 v71;
		v71.w = 1.000000e+00;
		v71.x = v67.x;
		v71.y = v67.y;
		v71.z = f68;
		v69.xyzw = (pc3_h[7]+((pc3_h[6]*v71.zzzz)+((pc3_h[5]*v71.yyyy)+(pc3_h[4]*v67.xxxx))));
	}
	if ((v69.z>0.000000e+00))
	{
		float h72;
		float h73;
		h73 = float(texture(ps2,vec3(v69.xy,min(v69.z,9.999900e-01))));
		h72 = h73;
		h70 = h72;
		h66 = max(max(1.000000e+00,h72),h55);
	}
	else
	{
		h66 = 1.000000e+00;
	}
	float h74;
	highp vec3 v75;
	v75.xyz = v30;
	float h76;
	h76 = max(0.000000e+00,dot(v75,pc3_h[1].xyz));
	h74 = h76;
	float h77;
	float h78;
	h78 = f13;
	h77 = h78;
	highp float f79;
	highp vec3 v80;
	v80.xyz = v23;
	highp vec3 v81;
	v81.xyz = v30;
	f79 = max(0.000000e+00,dot(v81,normalize((v80+pc3_h[1].xyz))));
	float h82;
	h82 = (h77*h77);
	float h83;
	highp float f84;
	f84 = h82;
	float h85;
	h85 = (f79*f84);
	h83 = h85;
	float h86;
	highp float f87;
	f87 = (h83*h83);
	highp float f88;
	f88 = h82;
	float h89;
	h89 = (f88/((1.000000e+00+(-(f79*f79)))+f87));
	h86 = h89;
	vec3 v90;
	highp float f91;
	f91 = min(h70,h55);
	highp vec3 v92;
	v92.xyz = vec3((h47*(h74*(((h77*2.500000e-01)+2.500000e-01)*min((h86*h86),2.048000e+03)))));
	highp vec3 v93;
	v93.xyz = (vec3(h74)*v46);
	vec3 v94;
	v94.xyz = ((vec3(f91)*pc3_h[0].xyz)*(v93+(v92*pc3_h[2].zzz)));
	v90.xyz = ((v63*vec3(h66))+v94);
	float h95;
	float h96;
	h96 = f13;
	h95 = h96;
	float h97;
	float h98;
	h98 = pc4_h[0].z;
	h97 = h98;
	vec4 v99;
	v99.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h100;
	float h101;
	h101 = float((pc4_h[0].y>0.000000e+00));
	h100 = h101;
	if (bool(h100))
	{
		float h102;
		h102 = pc4_h[0].y;
		highp float f103;
		f103 = ((h102+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h95,1.000000e-03)))))));
		highp vec3 v104;
		v104.xyz = textureLod(ps1,v34,f103).xyz;
		highp float f105;
		f105 = 1.000000e+00;
		vec3 v106;
		v106.xyz = ((v104*pc0_h[11].xyz)*vec3(f105));
		v99.xyz = v106;
	}
	else
	{
		vec4 v107;
		float h108;
		h108 = f4;
		highp float f109;
		f109 = ((h108+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h95,1.000000e-03)))))));
		v107.xyzw = textureLod(ps1,v34,f109);
		vec3 v110;
		v110.xyz = (v107.xyz*vec3((v107.w*h97)));
		vec3 v111;
		v111.xyz = (v110*v110);
		v99.xyz = v111;
		float h112;
		h112 = pc4_h[0].x;
		highp float f113;
		f113 = (h61/max(h112,1.000000e-04));
		highp float f114;
		f114 = h95;
		float h115;
		h115 = min(f113,v3.z);
		float h116;
		h116 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f114*v3.x)+v3.y),0.000000e+00,1.000000e+00));
		v99.xyz = (v111*vec3(mix(1.000000e+00,h115,h116)));
		vec3 v117;
		v117.xyz = v5;
		v99.xyz = (v99.xyz*v117);
	}
	vec4 v118;
	v118.xyz = ((((v90+(v99.xyz*vec3(h47)))+max(v41,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v118.w = h45;
	v12.xyzw = v118;
	float h119;
	h119 = f7;
	v12.xyz = (v118.xyz*vec3(h119));
	out_Target0.xyzw = v12;
}

