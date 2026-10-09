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
uniform highp vec4 pc4_h[1];
uniform highp vec4 pc3_h[3];
uniform highp vec4 pc5_h[1];
uniform highp vec4 pc6_h[1];
uniform highp vec4 pc2_h[2];
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
	highp float f0;
	f0 = pc2_h[0].x;
	highp float f1;
	f1 = pc1_h[1].x;
	highp float f2;
	f2 = pc0_h[12].x;
	highp vec3 v3;
	v3.xyz = pc0_h[11].xyz;
	highp float f4;
	f4 = pc0_h[10].x;
	highp vec3 v5;
	v5.xyz = pc0_h[8].xyz;
	highp float f6;
	f6 = pc0_h[7].x;
	highp float f7;
	f7 = pc0_h[6].x;
	highp vec3 v8;
	v8.xyz = pc0_h[5].xyz;
	highp vec3 v9;
	v9.xyz = pc0_h[4].xyz;
	bool b10;
	b10 = compiler_internal_AdjustIsFrontFacing(gl_FrontFacing);
	vec4 v11;
	highp float f12;
	vec4 v13;
	vec3 v14;
	vec3 v15;
	v15.xyz = in_TEXCOORD10.xyz;
	v14.xyz = v15;
	vec4 v16;
	vec4 v17;
	v17.xyzw = in_TEXCOORD11;
	v16.xyzw = v17;
	v13.xyzw = in_COLOR0;
	vec3 v18;
	v18.xyz = (cross(v16.xyz,v14)*v16.www);
	vec3 v19;
	float h20;
	highp vec3 v21;
	v21.xyz = (in_TEXCOORD8.xyz+(-v8));
	vec3 v22;
	v22.xyz = normalize((-in_TEXCOORD8.xyz));
	v19.xyz = v22;
	float h23;
	h23 = (f6*pc1_h[0].w);
	h20 = h23;
	int i24;
	i24 = (b10)?(1):(-1);
	float h25;
	h25 = float(i24);
	h20 = (h20*h25);
	vec3 v26;
	vec3 v27;
	v27.xyz = vec3(0.000000e+00,0.000000e+00,1.000000e+00);
	highp vec3 v28;
	v28.xyz = ((v16.xyz*v27.zzz)+((v18*v27.yyy)+(v14*v27.xxx)));
	vec3 v29;
	v29.xyz = normalize(v28);
	v26.xyz = v29;
	v26.xyz = (v26*vec3(h20));
	vec3 v30;
	v30.xyz = ((-v19)+((v26*vec3(dot(v26,v19)))*vec3(2.000000e+00,2.000000e+00,2.000000e+00)));
	vec4 v31;
	v31.xyzw = texture(ps0,in_TEXCOORD0.xy);
	vec4 v32;
	vec4 v33;
	v33.xyzw = pc5_h[0];
	v32.xyzw = v33;
	float h34;
	vec3 v35;
	v35.xyz = pc0_h[2].xyz;
	vec3 v36;
	v36.xyz = (v21+(-v9));
	h34 = (dot(v35,v36)+(-v32.x));
	vec3 v37;
	highp float f38;
	f38 = v32.z;
	float h39;
	h39 = (pc6_h[0].y*f38);
	v37.xyz = mix((vec3(1.000000e+00,1.000000e+00,1.000000e+00)+(-v31.xyz)),vec3(0.000000e+00,0.000000e+00,0.000000e+00),vec3(min(max(((v32.z/(v32.y+(-v32.x)))*min(max(h34,0.000000e+00),h34)),0.000000e+00),h39)));
	highp float f40;
	f40 = 5.000000e-01;
	f12 = f40;
	float h41;
	h41 = clamp((v31.w*v13.w),0.000000e+00,1.000000e+00);
	vec3 v42;
	v42.xyz = vec3(0.000000e+00,0.000000e+00,0.000000e+00);
	float h43;
	vec2 v44;
	float h45;
	h45 = f12;
	v44.xy = ((vec2(h45)*vec2(-1.000000e+00,-2.750000e-02))+vec2(1.000000e+00,4.250000e-02));
	highp vec3 v46;
	v46.xyz = v26;
	highp vec3 v47;
	v47.xyz = v19;
	float h48;
	h48 = max(dot(v46,v47),0.000000e+00);
	h43 = ((min((v44.x*v44.x),exp2((-9.280000e+00*h48)))*v44.x)+v44.y);
	float h49;
	if (((f1>0.000000e+00)&&(f2>0.000000e+00)))
	{
		float h50;
		h50 = f0;
		h49 = h50;
	}
	else
	{
		h49 = 1.000000e+00;
	}
	vec3 v51;
	vec3 v52;
	v52.xyz = pc2_h[1].xyz;
	v51.xyz = v52;
	float h53;
	vec3 v54;
	v54.xyz = v5;
	h53 = (dot(v51,vec3(3.000000e-01,5.900000e-01,1.100000e-01))*dot(v54,vec3(3.000000e-01,5.900000e-01,1.100000e-01)));
	float h55;
	highp vec3 v56;
	v56.xyz = v26;
	float h57;
	h57 = max(0.000000e+00,dot(v56,pc3_h[1].xyz));
	h55 = h57;
	float h58;
	float h59;
	h59 = f12;
	h58 = h59;
	highp float f60;
	highp vec3 v61;
	v61.xyz = v19;
	highp vec3 v62;
	v62.xyz = v26;
	f60 = max(0.000000e+00,dot(v62,normalize((v61+pc3_h[1].xyz))));
	float h63;
	h63 = (h58*h58);
	float h64;
	highp float f65;
	f65 = h63;
	float h66;
	h66 = (f60*f65);
	h64 = h66;
	float h67;
	highp float f68;
	f68 = (h64*h64);
	highp float f69;
	f69 = h63;
	float h70;
	h70 = (f69/((1.000000e+00+(-(f60*f60)))+f68));
	h67 = h70;
	vec3 v71;
	highp vec3 v72;
	v72.xyz = (v42*v51);
	highp float f73;
	f73 = (1.000000e+00+(-h49));
	highp float f74;
	f74 = h49;
	highp vec3 v75;
	v75.xyz = vec3((h43*(h55*(((h58*2.500000e-01)+2.500000e-01)*min((h67*h67),2.048000e+03)))));
	highp vec3 v76;
	v76.xyz = (vec3(h55)*v42);
	vec3 v77;
	v77.xyz = (v72*v5);
	vec3 v78;
	v78.xyz = ((vec3((f74+(f73*in_TEXCOORD5.x)))*pc3_h[0].xyz)*(v76+(v75*pc3_h[2].zzz)));
	v71.xyz = (v77+v78);
	float h79;
	float h80;
	h80 = f12;
	h79 = h80;
	float h81;
	float h82;
	h82 = pc4_h[0].z;
	h81 = h82;
	vec4 v83;
	v83.xyzw = vec4(0.000000e+00,0.000000e+00,0.000000e+00,1.000000e+00);
	float h84;
	float h85;
	h85 = float((pc4_h[0].y>0.000000e+00));
	h84 = h85;
	if (bool(h84))
	{
		float h86;
		h86 = pc4_h[0].y;
		highp float f87;
		f87 = ((h86+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h79,1.000000e-03)))))));
		highp vec3 v88;
		v88.xyz = textureLod(ps1,v30,f87).xyz;
		highp float f89;
		f89 = 1.000000e+00;
		vec3 v90;
		v90.xyz = ((v88*pc0_h[9].xyz)*vec3(f89));
		v83.xyz = v90;
	}
	else
	{
		vec4 v91;
		float h92;
		h92 = f4;
		highp float f93;
		f93 = ((h92+-1.000000e+00)+(-(1.000000e+00+(-(1.200000e+00*log2(max(h79,1.000000e-03)))))));
		v91.xyzw = textureLod(ps1,v30,f93);
		vec3 v94;
		v94.xyz = (v91.xyz*vec3((v91.w*h81)));
		vec3 v95;
		v95.xyz = (v94*v94);
		v83.xyz = v95;
		float h96;
		h96 = pc4_h[0].x;
		highp float f97;
		f97 = (h53/max(h96,1.000000e-04));
		highp float f98;
		f98 = h79;
		float h99;
		h99 = min(f97,v3.z);
		float h100;
		h100 = smoothstep(0.000000e+00,1.000000e+00,clamp(((f98*v3.x)+v3.y),0.000000e+00,1.000000e+00));
		v83.xyz = (v95*vec3(mix(1.000000e+00,h99,h100)));
		vec3 v101;
		v101.xyz = v5;
		v83.xyz = (v83.xyz*v101);
	}
	vec4 v102;
	v102.xyz = ((((v71+(v83.xyz*vec3(h43)))+max(v37,vec3(0.000000e+00,0.000000e+00,0.000000e+00)))*in_TEXCOORD7.www)+in_TEXCOORD7.xyz);
	v102.w = h41;
	v11.xyzw = v102;
	float h103;
	h103 = f7;
	v11.xyz = (v102.xyz*vec3(h103));
	out_Target0.xyzw = v11;
}

