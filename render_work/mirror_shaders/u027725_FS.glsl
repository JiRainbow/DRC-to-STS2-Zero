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
	f2 = pc0_h[17].x;
	highp vec3 v3;
	v3.xyz = pc0_h[16].xyz;
	highp float f4;
	f4 = pc0_h[15].x;
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
	vec3 v61;
	highp vec3 v62;
	v62.xyz = (v46*v59);
	vec3 v63;
	v63.xyz = (v62*v5);
	v61.xyz = v63;
	highp vec3 v64;
	highp vec4 v65;
	v65.w = 1.000000e+00;
	highp vec3 v66;
	v66.xyz = v30;
	v65.xyz = v66;
	v64.x = dot(pc0_h[12],v65);
	v64.y = dot(pc0_h[13],v65);
	v64.z = dot(pc0_h[14],v65);
	vec3 v67;
	vec3 v68;
	v68.xyz = max(vec3(0.000000e+00,0.000000e+00,0.000000e+00),v64);
	v67.xyz = v68;
	float h69;
	vec3 v70;
	v70.xyz = v5;
	highp vec3 v71;
	v71.xyz = v67;
	vec3 v72;
	v72.xyz = (v71*pc0_h[11].xyz);
	h69 = ((dot(v59,vec3(3.000000e-01,5.900000e-01,1.100000e-01))*dot(v70,vec3(3.000000e-01,5.900000e-01,1.100000e-01)))+dot(v72,vec3(3.000000e-01,5.900000e-01,1.100000e-01)));
	float h73;
	h73 = 1.000000e+00;
	highp vec2 v74;
	v74.xy = v20.xy;
	highp float f75;
	f75 = v20.w;
	highp vec4 v76;
	float h77;
	h77 = 1.000000e+00;
	v76.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,0.000000e+00);
	if ((v20.w<pc3_h[3].x))
	{
		highp vec4 v78;
		v78.w = 1.000000e+00;
		v78.x = v74.x;
		v78.y = v74.y;
		v78.z = f75;
		v76.xyzw = (pc3_h[7]+((pc3_h[6]*v78.zzzz)+((pc3_h[5]*v78.yyyy)+(pc3_h[4]*v74.xxxx))));
	}
	if ((v76.z>0.000000e+00))
	{
		float h79;
		float h80;
		h80 = float(texture(ps2,vec3(v76.xy,min(v76.z,9.999900e-01))));
		h79 = h80;
		h77 = h79;
		h73 = max(max(1.000000e+00,h79),h55);
	}
	else
	{
		h73 = 1.000000e+00;
	}
	float h81;
	highp vec3 v82;
	v82.xyz = v30;
	float h83;
	h83 = max(0.000000e+00,dot(v82,pc3_h[1].xyz));
	h81 = h83;
	float h84;
	float h85;
	h85 = f13;
	h84 = h85;
	highp float f86;
	highp vec3 v87;
	v87.xyz = v23;
	highp vec3 v88;
	v88.xyz = v30;
	f86 = max(0.000000e+00,dot(v88,normalize((v87+pc3_h[1].xyz))));
	float h89;
	h89 = (h84*h84);
	float h90;
	highp float f91;
	f91 = h89;
	float h92;
	h92 = (f86*f91);
	h90 = h92;
	float h93;
	highp float f94;
	f94 = (h90*h90);
	highp float f95;
	f95 = h89;
	float h96;
	h96 = (f95/((1.000000e+00+(-(f86*f86)))+f94));
	h93 = h96;
	vec3 v97;
	highp float f98;
	f98 = min(h77,h55);
	highp vec3 v99;
	v99.xyz = vec3((h47*(h81*(((h84*2.500000e-01)+2.500000e-01)*min((h93*h93),2.048000e+03)))));
	highp vec3 v100;
	v100.xyz = (vec3(h81)*v46);
	vec3 v101;
	v101.xyz = ((vec3(f98)*pc3_h[0].xyz)*(v100+(v99*pc3_h[2].zzz)));
	v97.xyz = ((v61*vec3(h73))+v101);
	float h102;
	float h103;
	h103 = f13;
	h102 = h103;
	float h104;
	float h105;
	h105 = pc4_h[0].z;
	h104 = h105;
	vec4 v106;
	v106.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h107;
	float h108;
	h108 = float((pc4_h[0].y>0.000000e+00));
	h107 = h108;
	if (bool(h107))
	{
		float h109;
		h109 = pc4_h[0].y;
		highp float f110;
		f110 = ((h109+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h102,1.000000e-03)))))));
		highp vec3 v111;
		v111.xyz = textureLod(ps1,v34,f110).xyz;
		highp float f112;
		f112 = 1.000000e+00;
		vec3 v113;
		v113.xyz = ((v111*pc0_h[11].xyz)*vec3(f112));
		v106.xyz = v113;
	}
	else
	{
		vec4 v114;
		float h115;
		h115 = f4;
		highp float f116;
		f116 = ((h115+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h102,1.000000e-03)))))));
		v114.xyzw = textureLod(ps1,v34,f116);
		vec3 v117;
		v117.xyz = (v114.xyz*vec3((v114.w*h104)));
		vec3 v118;
		v118.xyz = (v117*v117);
		v106.xyz = v118;
		float h119;
		h119 = pc4_h[0].x;
		highp float f120;
		f120 = (h69/max(h119,1.000000e-04));
		highp float f121;
		f121 = h102;
		float h122;
		h122 = min(f120,v3.z);
		float h123;
		h123 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f121*v3.x)+v3.y),0.000000e+00,1.000000e+00));
		v106.xyz = (v118*vec3(mix(1.000000e+00,h122,h123)));
		vec3 v124;
		v124.xyz = v5;
		v106.xyz = (v106.xyz*v124);
	}
	vec4 v125;
	vec3 v126;
	v126.xyz = pc0_h[11].xyz;
	v125.xyz = (((((v97+(v106.xyz*vec3(h47)))+((v67*v126)*v46))+max(v41,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v125.w = h45;
	v12.xyzw = v125;
	float h127;
	h127 = f7;
	v12.xyz = (v125.xyz*vec3(h127));
	out_Target0.xyzw = v12;
}

