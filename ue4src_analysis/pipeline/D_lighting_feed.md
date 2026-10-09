---
agent: D段-光照与视图uniform馈入链
range: FS_b12f6bb5/FS_6899cbee + VS_*.glsl × ue4src part_000039/042/047/048/050/051/053/059/064/067/073/076/081
topic: 战斗像素着色器各光照项的数值来源（pc0~pc4 槽位→C++ 填充→场景对象）
---

# D 段：光照与视图 uniform 的数值馈入链

## 0. 定性发现（先行结论）：pcN_h 不是 FViewUniformShaderParameters，而是 MaterialParameterCollection uniform buffer

GLSL 侧证据（实读 `render_work\v2_shadermap\`）：FS_b12f6bb5 只引用 5 个小缓冲 pc0[10]/pc1[4]/pc2[4]/pc3[1]/pc4[6]（全功能变体 FS_6899cbee 也只有 pc0[17] 等 7 个 ≤17 向量的缓冲）；而 FViewUniformShaderParameters 反射成员表（part_000081/067/073）覆盖 0x000~0xea8+（65+ 成员，ViewToClip 在 0x0 起），pc0_h[2]=0x20 落在 ViewToClip 矩阵内，不可能是"方向光方向"。两者不是同一缓冲。

引擎侧实证（全部实读）：
- `FMaterialParameterCollectionInstanceResource::GameThread_UpdateContents` = **0xa12dffc**（part_000064.c:11955 起，1716B）：接收 `TArray<FVector4>`（collection 全部向量参数，标量按 4 打包在后），整块经 `GDynamicRHI+0x110`(RHICreateUniformBuffer)/`+0x118`(RHIUpdateUniformBuffer) 上传，布局大小 = count×16 字节。**每个 collection 实例 = 一个 FRHIUniformBuffer = GLSL 里一个扁平 pcN_h 数组**。
- `FScene::UpdateParameterCollections` = 0x90d2310（part_000051.c:13932）：维护 `FScene+0x2470` 的 `TSet<FGuid, FRHIUniformBuffer*>`。
- 运行时旁证：`render_work\hook.js` 就是在游戏进程内 `glGetUniformLocation(prog,"pc0_h"/"pc2_h[0]")` + 钩 `glUniform4fv` 抓这些数组——与上述结论一致。

因此 **pcN_h[i] = 战斗材质引用的第 N 个 MaterialParameterCollection 的第 i 个向量参数**。FS_b12f6bb5 引用 5 个 collection（10/4/4/1/6 向量）。写入端（callgraph 全查）：
- BP/Lua：`0x6e29418`（exec→`UMaterialParameterCollectionInstance::SetVectorParameterValue`=0xa12ec84）、`0x6e2977c`（SetScalar=0xa12e844）；
- Kismet 批量：`0x6d9a960`（part_000012：天气/灯光导演，UKismetMaterialLibrary::SetScalar/SetVectorParameterValue=0xa041730/0xa042098 连发 + ULightComponent::SetLightColor=0x9dbba38/SetTemperature + `GetAzureIntensityScale` + UCurveFloat::GetFloatValue；调用方 0x6d97488）；
- Sequencer：`FMaterialParameterCollectionExecutionToken::Execute`=0x95ba2e4（已有 A 段结论）。
- collection 的名字/参数名在资产侧（ue4_dump），引擎二进制只有 FName 表（0xc366840-0xc366b50，含 CharacterDirectLightScale/CharacterIndirectLightScale 等，part_000006）。

## 1. pc0_h[10] 逐槽语义表（GLSL 实读）与引擎侧 Azure 视图块对照

### 1.1 pc0_h（MPC#0，10 向量）——"视图/角色光照块"

| 槽 | GLSL 消费（FS_b12f6bb5 行号） | 语义 |
|---|---|---|
| [0],[1],[3] | 未引用 | 保留 |
| [2].xyz | v44（L134）；h43=dot(v44, v45) | **伪方向光方向** |
| [4].xyz | v45 = v5 − pc0_h[4]（L136） | 阴影投影参考点（假阴影轴向基点） |
| [5].xyz | v5 = in_TEXCOORD8.xyz − pc0_h[5]（L55） | 相机/视图位置（in_TEXCOORD8=VS 输出的世界位置） |
| [6].x | h82，最终 `out.rgb *= pc0_h[6].x`（L214） | 全画面输出缩放（演出压暗通道） |
| [7].xyz | v0 = pc0_h[7]（L46），乘 v56≡0 | 死代码（预留环境向量） |
| [8].x/.y/.z/.w | h48=min..、h54=max(.y,..)、h62、v63×.zzz、v79=×.x | **光照参数包**：x=直接光总强度（乘 v79）；y=距离淡出下限；z=环境缩放（本变体死）；w=上限 |
| [9].z / .w | h65=mix(.z,1,h51)（L177）、h67=mix(.y,1,.w)（L181）、h58=mix(pc4[1].x,1,.w)（L163） | 环境插值权重 / 高光-遮罩插值权重 |

全功能变体 FS_6899cbee 多出：pc0_h[10].xyz=SH 环境缩放色、**pc0_h[11..13]=SH L1 基组**（`v82.c = dot(pc0_h[11+c], (normal,1))`，L230-232，即 3×float4 的 SH 系数按行排布）、pc0_h[14].x=标量、pc0_h[15]=(x:直接光强度, y:淡出下限, z:环境缩放, w:上限)——与简单变体 pc0_h[8] 同构、pc0_h[16]=(z:环境权重, w:高光权重)——与 pc0_h[9] 同构。即**全功能变体把同一套光照参数块后移，并在 [10..13] 追加 SH**。

### 1.2 引擎侧 FViewUniformShaderParameters 的 Azure 自定义成员（反射 thunk 实名）

`zzAppendMemberGetPrev` 簇逐个实读（part_000076.c:85502 / part_000073.c:104951 / part_000081.c:2470 / part_000067.c:110408 / part_000068.c:177063）：

| 视图 uniform 偏移 | 成员名 | 类型 |
|---|---|---|
| 0x9d0 | IndirectLightingColorScale（stock 槽位被复用） | float3 |
| 0x9e0 | **AzureIndirectCharacterLightingColorScale** | float3 |
| 0xe60 | **CharacterLightParams** | float4 |
| 0xe70 | **CharacterLightParamsEx** | float4 |
| 0xe80 | **CharacterVirtualLightDirection** | float3 |

### 1.3 0x9130678 FViewInfo::SetupUniformBufferParameters 的 Azure 写入逻辑（实读 part_000047.c:193296-193347）

```
门控A：if (GAzureReplaceLightingParams==0 || DAT_0c619662!=0)
    +0x9d0 = (FViewInfo+0x15dc float4) × (FViewInfo+0x15fc)
    +0x9e0 = (FViewInfo+0x15ec float4) × (FViewInfo+0x15fc)
  else  两处强制 (1,1,1,1)          // Azure 替换激活时取消视图级缩放
+0xe60 CharacterLightParams  = { *(p+0x1600..0x1608), *(p+0x1618..0x1620) }   // 两段拼装
+0xe70 CharacterLightParamsEx= { p[0x1614]?1:0, *(p+0x1620..0x1628), GAzureReplaceLightingParams?1:0 }
+0xe80 CharacterVirtualLightDirection = FRotator::RotateVector(FRotator@p+0x1608)
```
即 **.w 位（0xe7c）就是"Azure 替换开启"的 0/1 标志** —— 与 GLSL `mix(..., 1.0, pc0_h[9].w)` 在替换开启时权重=1（取消 ps1 遮罩调制）的行为严格对应：**pc0_h[9].w ≙ CharacterLightParamsEx.w；pc0_h[9].z ≙ .z（环境权重）；pc0_h[8] ≙ CharacterLightParams**。pc0_h[2]（方向）与 0xe80 CharacterVirtualLightDirection / Azure 替换方向（0xc6196c0/c8 取负，见 §4）语义对位。逐字节偏移对不上是正常的：MPC 缓冲与视图缓冲是两条通道，游戏把同一批场景光量（方向/相机/强度/权重）每帧复制进 MPC#0 供战斗材质消费。

## 2. pc1_h[4]：不是 SH，是"点光位置→冷暖遮罩通道"选择矩阵

实读 FS_b12f6bb5 L92-95：
```glsl
v24.xyz = pc1_h[3] + pc1_h[2]*pos.zzz + pc1_h[1]*pos.yyy + pc1_h[0]*pos.xxx;   // pos = 点光位置 pc2_h[0].xyz
sel = clamp(floor(v24.x), 0, 1);   // 只用 .x 通道，取 0/1
v23 += mix(ps1.g, ps1.r, sel) * max((h9*h9)*(pc2_h[1].xyz*pc2_h[1].w), 0);      // 点光贡献
```
即 pc1 = (3×3 矩阵 + 偏置) 对**点光世界位置**做线性分类，结果 floor 到 {0,1}，决定该灯采样 ps1（V2 辅助遮罩图）的 R 通道还是 G 通道。它是**每灯冷暖/类型选择器常量表**，与球谐无关（SH 在 pc0_h[11..13]，见 §1.1）。填充=MPC#1 的 4 个向量（游戏侧常量，随点光表配置）。

## 3. pc2_h 双点光：谁被填入、强度源是谁

### 3.1 槽位语义（实读 L60-95）
`pc2_h[0]=(灯1 pos.xyz, w=radius)`、`pc2_h[2]=(灯2 pos.xyz, w=radius)`；`pc2_h[1]=(灯1 color.xyz, w=intensity)`、`pc2_h[3]=(灯2)`。衰减 `h9=max(1−dist/max(radius,1e-4),0)`，强度 `=(h9²)·(color·w)`——线性衰减平方，非 stock InvRadius/四次衰减 → 再次证明是 MPC 自定义块而非引擎 FMobileDirectionalLight/MovablePointLight 缓冲。

### 3.2 引擎原生"可移动点光 uniform"路径（对照物，实读）
- **0x8f71fa0** `UpdateMovablePointLightUniformBufferAndShadowInfo`（part_000048.c:121112，1200B）：读 CVar `r.MobileNumDynamicPointLights`（默认 1）/`r.Mobile.EnableMovableSpotlights`(1)/`r.Mobile.EnableMovableSpotlightsShadow`(1)；遍历 `FScene` MovablePointLightsBitfield（+0x14b8 数组/+0x14c8 位图/+0x14e0 数量），**从 bit62 向低位扫描**（高索引灯优先占坑）；筛选 `proxy+0x15c`（ELightType：2=Spot，3=Point）且 `proxy+0x148` bit1（可移动标记）；spot 阴影再填 per-view 阴影尺寸/矩阵（FViewInfo+0x5b00 起、stride 0x66c0）。
- **0x8ebd440** `FLightSceneInfo::ConditionalUpdateMobileMovablePointLightUniformBuffer`（part_000039.c:174013，1808B）：位置按每视图淡出（`GMinScreenRadiusForLights`/`GLightMaxDrawDistanceScale`/GetMaxDrawDistance）缩放，色与参数经 `FLightSceneProxy` vtable+0x70（GetLightShaderParameters）取自**灯代理**；结果 `RHIUpdateUniformBuffer` 进引擎点光 uniform。

### 3.3 战斗材质的数值源判定
pc2 是 MPC → 每帧由游戏逻辑 `SetVectorParameterValue` 写入（§0 写入端）。场景侧对象链：
- 位置/半径：`UPointLightComponent`（世界变换 + AttenuationRadius）；
- 颜色：`ULightComponent::SetLightColor`=0x9dbba38（FLinearColor→this+0x25c）+ `GetColoredLightBrightness`=0x9dbac70（色温×亮度）；
- **AzureIntensityScale**：`UPointLightComponent+0x39c`（Set=0x9dca86c、Get=0x9dca8c0、UFunction 注册=0xa8f7b28）。读取端仅两处（callgraph 全查）：天气/灯光导演 **0x6d9a960**（读曲线后连同 SetLightColor/SetTemperature 一起下发——作者侧缩放）与 Lua getter **0x6fb8828**。**结论：shader 的强度数值（pc2_h[1].w）来自 MPC 向量 w；UPointLightComponent 是作者/中间源，不直接绑定 uniform**。战斗场景中"最近 N 盏"的选择逻辑不在引擎 0x8f71fa0（那是 stock 通道，本材质不走），而在游戏侧填 MPC 的逻辑（PointLightManager `/Script/PointLightManager`，Lua 暴露 GiveIntensityToPointLight/GiveVisibilityToPointLight/SetScalarParamForMID→真实现 0x71bd1e4=按 TMap 查 MID 后 SetScalarParameterValue）。

## 4. 伪方向光项 v44/h43 与 pc3_h[0].x 阴影偏移

- GLSL（L130-137, 199-205）：`v45 = 世界位置 − pc0_h[4]`；`h43 = dot(pc0_h[2].xyz, v45) − pc3_h[0].x`；阴影遮罩 `= clamp( (pc3.z/(pc3.y−pc3.x))·min(max(h43,0),h43) 封顶 pc4_h[5].z·pc3.z , 0,1)`——**沿光轴的斜面投影假阴影**（无 shadow map），pc3_h[0]=(x:起始偏移, y:终止偏移, z:强度)。pc3 是 1 向量的 MPC——战斗演出/关卡数据直接给值（与 DarkenMPC 同通道族）。
- 方向来源双通道：
  1) MPC#0 v2（游戏侧写入，演出期可变）；
  2) 引擎对照：`SetupMobileDirectionalLightUniformParameters`=**0x8efb15c**（实读 part_000047.c:137744-137960）在 `GAzureReplaceLightingParams` 开启时用全局方向 `DAT_0c6196c0/c8` **取负**填 `[0x00]` 与 `[0x20]`（w=1.0；stock 路径 w=0.0 且取灯代理方向），颜色 `[0x10]`=全局色 0x0c6196b0/b8×1/π，`[0x30]`=按 FViewInfo+0x1628 去饱和的灰度 Background。
- 全局 Azure 块（0x0c619668-c8；staging 0x0c619e40-a8；发布点 0x9e1b1d8，part_000049.c:212988）：`0x670-a8`=8×float4 SH 环境光、`0x6b0/b8`=替换颜色、`0x6c0/c8`=替换方向。写入链：蓝图/Lua (bool,FLinearColor,FVector)→0x6e2b57c→`AzureReplaceDirectionalLight`=0x8eface8→任务 0x8f59be8→staging→0x9e1b1d8 发布。
- **阴影方向替换**：`FDirectionalLightSceneProxy::GetViewDependentWholeSceneProjectedShadowInitializer`=**0x9ddbdf0**（实读 part_000059.c:8322 起）——门控内直接取 `DAT_0c6196c0/c8` 建 CSM 投影；叠加 `GAzureIsReplaceShadowCenter`/`GAzureReplaceShadowAutoCalcCenter`（0x9db2d50/0x9db34b0 置位）把阴影中心 ×3.0（AutoCalc ×2.0）+`DAT_0c578ae8`（0x8efb15c per-view bias 槽、消费 0x91c47c4 `FProjectedShadowInfo::AddSubjectPrimitive`）——即"阴影跟着角色走"。
- 全功能变体（FS_6899cbee/FS_bdcdce3a，有 `ps2 sampler2DShadow`）真 CSM：pc3_h[1].x=最大距离、pc3_h[2..5]=投影矩阵、pc3_h[0].zw=纹素尺寸，4-tap PCF（实读 6899cbee L243-267）——对应引擎 ScreenToShadowMatrix。
- SH 环境注入：`GetIndirectLightingCacheParameters`=**0x8e6e138**（实读 part_000042.c:178320）把 0x0c619670-a8 的 8×float4 塞进 `FIndirectLightingCacheUniformParameters[0xc..0x13]`（绕过体积光照贴图）——对应 GLSL pc0_h[10..13] 的 SH 项。

## 5. TEXCOORD7：顶点级指数高度雾（VS_4c1cbc62 实读）

4 个 VS 变体分工：
| VS | 内容 |
|---|---|
| **VS_4c1cbc62**（vc0[15],vc1[6],vc2[6],vs0 sampler3D） | 唯一产出 `var_TEXCOORD7`（float4）与 `var_TEXCOORD8`=世界位置；雾+LUT 全功能版 |
| VS_3e56da / VS_ee722254（vc0[1],vc1[5],vc2[10]） | 基础版：L2W+ViewProj+rim（菲涅尔 vc2_h[8].x+y*clamp(cos,0,z)）；ee722254 把 rim 折进 gl_Position.z；无 TEXCOORD7 |
| VS_76c4ab（vc0[5],vc1[5],vu[1]） | 描边展开 VS（法线方向 × sqrt(w)·width/10，裁剪空间外扩） |

TEXCOORD7 组装（VS_4c1cbc62 实读）：标准 UE 指数高度雾解析积分——两层参数 `ratio=(1−exp2(−D·h))/(D·h)`（小量展开 0.693147−0.240227·x），雾量 `h27=max(clamp(exp2(−f56),0,1), vc1_h[2].w)`；输出 `TEXCOORD7.xyz = FogColor·(1−fog) + vc1_h[5].xyz·pow(clamp(dot(viewDir, vc1_h[4].xyz),0,1), vc1_h[5].w)`（方向性散射）、`.w = 雾后透过率`；f1 分支可选 3D LUT（vs0，按视线球面坐标 acos 映射采样，vc0_h[8..14] 为 LUT 参数）。VC 缓冲参数表：`vc1_h[0]=(Density, HeightFalloff, MaxDist, 起始高度)`、`vc1_h[1]=第二层`、`vc1_h[2]=(FogColor.xyz, MaxOpacity)`、`vc1_h[3]=(…, 全雾距离)`、`vc1_h[4]=(散射光方向,…)`、`vc1_h[5]=(散射色, 指数)`。C++ 数值源 = **UExponentialHeightFogComponent**（FogDensity/FogHeightFalloff/FogMaxOpacity/FogInscatteringLuminance/DirectionalInscatteringColor/Exponent/Start）每帧装配（stock 路径经 View.ExponentialFog*，战斗管线经本自定义 cbuffer）。FS 消费（L210）：`out.rgb = (光照和)·TEXCOORD7.w + TEXCOORD7.xyz`——标准雾混合。

## 6. 逐光照项来源总表

| GLSL 项 | uniform 槽 | C++ 填充函数（实证地址） | 场景/游戏对象 |
|---|---|---|---|
| 伪方向光方向 v44 | pc0_h[2].xyz（MPC#0 v2） | MPC：0x6e29418/0x6d9a960/0x95ba2e4；引擎对照：0x8efb15c Azure 路径（−0xc6196c0/c8）、0xe80←0x9130678 RotateVector(FViewInfo+0x1608) | AzureReplaceDirectionalLight 入口 0x6e2b57c→0x8eface8；UAzureSceneImage.ReplaceDirectionalLight（0x6c363e4，bReplace 默认 true） |
| 直接光强度 v79 | pc0_h[8].x（×.y 淡出） | 0x9130678（Azure 门控写 0x9d0/0x9e0，强制 1 时取消） | CharacterLightParams(+Ex)@FViewInfo+0x15dc-0x1628；天气导演 0x6d9a960 |
| 假阴影 h43/遮罩 | pc0_h[2]、pc0_h[4]、pc3_h[0].xyz | MPC#3；引擎对照 0x8efb15c per-view bias（×3/×2+DAT_0c578ae8）、0x9ddbdf0 CSM 方向替换 | 演出/关卡阴影数据；Azure 替换阴影中心（AzureSetReplaceShadowCenterFlag 0x9db2d50） |
| 点光 1/2 位置+半径 | pc2_h[0] / pc2_h[2]（.w=radius） | MPC#2 每帧写入；引擎对照 0x8f71fa0→0x8ebd440（r.MobileNumDynamicPointLights，bit62→0 扫描） | 场景 UPointLightComponent（世界位置、AttenuationRadius） |
| 点光色×强度 | pc2_h[1] / pc2_h[3]（.xyz=色, .w=强度） | 同上 | SetLightColor 0x9dbba38 × Intensity × AzureIntensityScale(+0x39c，Set=0x9dca86c) |
| 点光冷暖通道选择 | pc1_h[0..3] | MPC#1 | 点光分类常量表（美术/配置数据） |
| SH 环境（仅 6899cbee） | pc0_h[10..13] | 0x8e6e138 ← 全局 0x0c619670-a8（发布 0x9e1b1d8） | AzureReplaceMovableIndirectLighting（UAzureSceneImage 0x6c363b4，8 float 写采集组件） |
| ramp 暗端/亮端 | pc4_h[0].xyz / pc4_h[5].x | MID/材质参数（0x70bbdf8 仅写 darkenParam/Rongjie 标量；向量=材质默认或演出写入） | V2 烘焙 ramp 资产 |
| 雾/环境色 TEXCOORD7 | vc0_h[4..6]、vc1_h[0..5] | VS 逐帧装配（stock=View.ExponentialFog*） | UExponentialHeightFogComponent |
| 全画面亮度 | pc0_h[6].x | MPC#0 | 演出压暗（DarkenMPC 同族） |

## 7. 结论：战斗角色观感中哪些明暗/色彩来自场景光照

1. **造型明暗是烘焙 ramp，不是实时 N·L**。v78 = ramp(ps0.rgb×顶点色 在 pc4_h[0]暗端↔pc4_h[5].x亮端 之间) × 假阴影遮罩，再整体乘 pc0_h[8].x——场景"方向光"只以总强度+投影方向参与，角色立体感来自 V2 资产。
2. **场景级染色来自 Azure 替换光照链**：pc0_h[8]/[9] 是 CharacterLightParams/Ex 的材质侧镜像，Azure 替换开启时（.w=1）遮罩调制被取消、颜色/SH 环境取全局块 0x0c6196b0/c619670——战斗的蓝白观感可由一次蓝图/Lua 调用整体改写。
3. **唯一直接随场景变化的位置光是双点光**：颜色/强度/半径全部来自场景 UPointLightComponent（经 MPC 或引擎 uniform），冷暖由 pc1 选择器定；靠近灯时角色被该灯染色、照亮（衰减平方项）。
4. **角色投影阴影是假的**：FS_b12f6bb5 只有 pc3 斜面投影（方向+偏移来自数据），与场景阴影贴图无关；只有全功能变体才采 CSM（且方向/中心已被 Azure 替换到角色处）。
5. **环境/远景色（TEXCOORD7）完全来自雾组件**，材质零参与；SH 环境项在战斗基础变体中是死代码（v56≡0），全功能变体才生效。
6. 方法论修正：本段推翻了"pc0_h=FViewUniformShaderParameters 按字节对位"的预设——pcN_h 是 MaterialParameterCollection uniform buffer（0xa12dffc/0x90d2310/hook.js 三重实证），视图 uniform 的 Azure 成员（0x9d0/0x9e0/0xe60/0xe70/0xe80）是同义量的引擎侧镜像通道。
