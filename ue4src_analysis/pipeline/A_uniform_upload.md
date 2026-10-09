---
agent: ZCode (A段 uniform 上传链 RHI 侧)
range: GLES RHI 区 0xab0e000-0xab80000（含引擎侧 0x8e/0x8f/0x90/0x91/0xa0-a1 段交叉）
topic: Spine 角色（MySpineLitNormalMaterialV2）每次绘制前 pc0_h/pc1_h/pc2_h/pc3_h/pc4_h uniform 块的上传链：glUniform 包装核实、调用序列、块→填充函数→数据源结构
---

# A段：uniform 上传链（RHI 侧）—— 实读结论

## 0. 先行纠错（旧记录勘误）

| 旧记录 | 实测 | 说明 |
|---|---|---|
| GLES RHI 区 = 0xaa12070-0xaa1698c | **错**。该区间是 FHttpManager/FSpeedRecorder/FStatsCollectorImpl/FPatchDataCompactifier（part_000078 等，HTTP/补丁系统） | 真正的 OpenGL ES DynamicRHI 区在 **0xab0e000-0xab80000**（FOpenGLDynamicRHI::RHIDraw*、FOpenGLShaderParameterCache、FOpenGLBoundShaderState、RHICreateUniformBuffer） |
| glUniform4fv 包装 = 0xaa42474 / 0xaa427bc | **错**（疑为 aa→ab 抄写错位）。实地址：**0xab42414 = FOpenGLShaderParameterCache::CommitPackedGlobals**（0xab42474 落在其函数体内偏移 +0x60），**0xab4251c = FOpenGLShaderParameterCache::CommitPackedUniformBuffers**（0xab427bc 落在其体内 +0x2a0） | 本函数才是两个 glUniform4fv 调用点的宿主 |

## 1. glUniform 包装函数清单（全部经反编译代码实证）

GL 导入（PLT，来自 callgraph_edges.csv 703792-703797 行）：
- `glUniform4fv` = **0xb9aa7c0**、`glUniform4uiv` = **0xb9aa7d0**、`glUniform4iv` = **0xb9aa7e0**

包装/宿主函数（part_000082.c:65741 起、part_000081.c:187968 起实读）：

| 地址 | 符号（反编译注释） | 证据 |
|---|---|---|
| **0xab42414** | `FOpenGLShaderParameterCache::CommitPackedGlobals(FOpenGLLinkedProgram*, int stage)` | 体内直接调 `glUniform4fv(uVar2+iVar3, uVar5, cache浮点暂存+dirtyStart*0x10)`；`bVar4<3 → 4fv`，`==3 → glUniform4iv`，`==4 → glUniform4uiv`（bVar4=分量类型索引：0..2=float/half、3=int、4=uint）。遍历 LinkedProgram+stage*0x30+0x468/0x470 的 PackedGlobal 位置表 |
| **0xab4251c** | `FOpenGLShaderParameterCache::CommitPackedUniformBuffers(FOpenGLLinkedProgram*, int stage, TRefCountPtr<FRHIUniformBuffer>* UB数组, TArray<FUniformBufferCopyInfo>&)` | 对每个 UB 槽：先 `memcpy(暂存 + dstOff*4, *(UB+0x50)+0x10 + srcOff*4, size*4)`（FUniformBufferCopyInfo 步长 10 字节：u16 srcOff, u8 srcUBIndex, u16 dstOff(4B单位), u16 size(4B单位), u8 typeIdx@+5），再对每个 UB 常量成员 `glUniform4fv(iVar8, count, 暂存)`（UB 位置表 = LinkedProgram+stage*0x30+0x478+ubIndex*0x10） |
| 0xab12890 | `CommitNonComputeShaderConstantsFastPath` | 只调 CommitPackedGlobals(VS/PS/GS 三级 cache +0x000/+0xb0/+0x160)，不刷 UB —— 用于无脏 UB 的快速路径 |
| 0xab12704 | `CommitNonComputeShaderConstantsSlowPath` | `GUseEmulatedUniformBuffers!=0` 时：stage0(VS)=CommitPackedUniformBuffers(cache+0, UB表 this+0x590, copyInfo=*(shader+0xc0)) + CommitPackedGlobals；stage1(PS)=cache+0xb0、UB表 this+0x6e0；stage2(GS)=cache+0x160、UB表 this+0x750 |
| 0xab40350 | `FOpenGLDynamicRHI::BindPendingShaderState` | glUseProgram + **BindUniformBufferBase(0xab3a028)**（真 UBO 路径）+ GetNumUniformBuffers(0xab405cc) |
| **0xab0fe38** | `FOpenGLDynamicRHI::RHISetShaderUniformBuffer(FRHIGraphicsShader*, uint slot, FRHIUniformBuffer*)` | 把 FRHIUniformBuffer* 存入 `this + slot*8 + stage*0x150 + 0x590`（VS=+0x590, PS=+0x6e0），脏位图 `*(ushort*)(this + stage*2 + 0x832) |= 1<<slot`。这就是**每次绘制前各 pcN 块资源的落位函数** |
| 0xab1002c | `FOpenGLDynamicRHI::RHISetShaderParameter`（thunk） | 调 `FOpenGLShaderParameterCache::Set(0xab42388)` 写 packed globals 暂存（松散 uniform 路径） |
| 0xab3b158 | `ConfigureShaderStage`（size 3012） | 链接期装配采样器/常量位置表；唯一调用 glUniformBlockBinding 缓存包装 0xab3c07c（callgraph 唯一边 703551 行）→ **glUniformBlockBinding 只存在于真 UBO 路径；本作 GLSL 为 `uniform vec4 pcN_h[N]` 独立数组（无 uniform block），运行 GUseEmulatedUniformBuffers 模拟路径，BlockBinding 链路为死路** |
| 0xab7f07c | `FOpenGLDynamicRHI::RHICreateUniformBuffer`（size 3492） | 池化 FOpenGLUniformBuffer；CPU 影子数据挂在 UB+0x50→+0x10（CommitPackedUniformBuffers 的 memcpy 源） |

## 2. Spine 绘制前的上传调用序列（addr 链，全部 callgraph 实证）

```
FMobileSceneRenderer::Render            0x8f7321c   (part_000048)
 └─ InitViews                          0x8f705c8   (part_000052)
     └─ UpdateMovablePointLightUniformBufferAndShadowInfo 0x8f71fa0 (part_000048)
         └─ FLightSceneInfo::ConditionalUpdateMobileMovablePointLightUniformBuffer
                                        0x8ebd440   (part_000039)
             └─ GDynamicRHI 虚表+0x118（以 FLightSceneProxy+0x1b0 的布局/UB，&栈上参数结构 调 RHI 建立点光 uniform buffer）
[引擎侧每 draw 设置]
FMaterialShader::SetParameters<FRHIPixelShader>  0x918fa7c (part_000058)
 ├─ FMaterialRenderProxy::EvaluateUniformExpressions 0xa0fe0a4 (part_000071)
 │   └─ FUniformExpressionSet::FillUniformBuffer     0xa129b5c (part_000063)
 │       └─ 求值结果(字节量 = UniformExpressionSet+0x150 处的 UniformBufferSize)
 │          → GDynamicRHI 虚表+0x110 = RHICreateUniformBuffer(0xab7f07c 入口)
 │          → 存入 FUniformExpressionCache+0x10（TRefCountPtr<FRHIUniformBuffer>）
 ├─ 入队 SetUniformBufferParameter 命令(PTR_ExecuteAndDestruct_0bc6d280)
 │   参数 slot = *(ushort*)(PS shader + 0xe0)，buffer = 材质 uniform 表达式缓存
 └─ ParameterCollection：GetParameterCollectionBuffer 逐 GUID 绑定（shader+0xd0 列表/+0xd8 数量）
FOpenGLDynamicRHI::RHISetShaderUniformBuffer     0xab0fe38   ← 上述命令的执行落点
 └─ this + slot*8 + 0x6e0(PS) = FRHIUniformBuffer*；脏位图 +0x832
[RHI 侧每 draw 提交]
FOpenGLDynamicRHI::RHIDrawIndexedPrimitive       0xab142c4 (part_000067)
 ├─ BindPendingShaderState              0xab40350 → glUseProgram + (真UBO时)BindUniformBufferBase 0xab3a028
 ├─ SetupTexturesForDraw                0xab0f0a0（ps0/ps1 采样器）
 ├─ SetupVertexArrays                   0xab11ed4
 └─ CommitNonComputeShaderConstantsSlowPath 0xab12704（或 FastPath 0xab12890）
     ├─ CommitPackedUniformBuffers      0xab4251c  (PS, cache+0xb0, UB表 this+0x6e0)
     │   ├─ memcpy：每个 FUniformBufferCopyInfo 把 UB 影子数据搬进 cache 暂存（0xa8 区）
     │   └─ glUniform4fv / 4iv / 4uiv   ← 按 pcN_h[...] 各常量成员位置逐段上传
     └─ CommitPackedGlobals             0xab42414  (PS stage1)
         └─ glUniform4fv                ← 松散 packed globals（RHISetShaderParameter→Set 0xab42388 暂存）
glDrawElements(0xb9aa4c0) / glDrawElementsInstanced(0xb9aa4b0)
```

要点：**GLES 上 pc0_h..pc6_h 不是真 UBO**。每块数据流 = 引擎结构体 → RHICreateUniformBuffer 建 FOpenGLUniformBuffer（CPU 影子）→ 每绘制 RHISetShaderUniformBuffer 落位 → glDraw 前一次性 memcpy 进 FOpenGLShaderParameterCache 暂存 → glUniform4fv 刷给 `pcN_h` 数组。

## 3. 块 → 填充函数 → 数据源结构 映射

| GLSL 块（FS_b12f6bb5, 行30-34） | vec4 数 | RHI 槽 | 上传函数 | 填充/生产函数 | 数据源结构（实测证据） |
|---|---|---|---|---|---|
| pc0_h[10] | 10 | PS slot0 | 0xab4251c（经 0xab0fe38 slot0） | `FViewInfo::SetupUniformBufferParameters` **0x9130678**（part_000047.c:193300 起） | FViewUniformShaderParameters。实测写点：+0x9d0/0x9d8/0x9e0=Azure 替换色×缩放（view+0x15dc-0x1600，GAzureReplaceLightingParams 门控否则 (1,1,1,1)）；**+0xe60←view+0x1600、+0xe68←+0x1618、+0xe70 门控标量、+0xe74←+0x1620、+0xe7c=GAzureReplaceLightingParams._1_1_?1.0（4×f4 CharacterLightParams，双点光颜色+强度门）**；+0xe80=FRotator::RotateVector(view+0x1608)（CharacterVirtualLightDirection）。GLSL 用槽 [4],[5],[6],[7],[8],[9]：**[5].xyz 被顶点世界坐标 (in_TEXCOORD8) 减去 → PreViewTranslation**（行55），[8].y/z/w、[9].z/w 为雾/混合系数 |
| pc1_h[4]（全功能变体为 pc1_h[5]，行31） | 4/5 | PS slot1 | 同上 slot1 | 未最终定位（见 §5） | 语义实测：3x4 矩阵 M，`v24 = M×pc2_h[0]`、`v25 = M×pc2_h[2]`（行92-94），`floor(v24.x)` 夹到 [0,1] 后 mix(v6.y,v6.x,·) —— 即把两个点光位置投影成 0/1 选择 MASK.r/MASK.g 通道的门矩阵。应用对象是 pc2 的点光位置 → 与 0x8ebd440 中的 GetWorldToShadowMatrix(0x91bed24)/ComputeTransitionSize(0x91bf110) 簇同源的可能性最高 |
| **pc2_h[4]** | 4（=2 盏灯×[位置xyz+radius, 颜色rgb×强度w]） | PS slot2 | 同上 slot2 | 颜色源实证：`UpdateLightColorAndBrightness` **0x90e53d4** → **0x9110a64**（part_000048.c:137951）→ `FLightSceneProxy::SetColor` + `FLightSceneProxy::SetAzureCharColor` **0x9dbadd4**（写 proxy+0xdc/+0xe0、置脏 +0x19c；FScene+0x14b8 处步长 0x30 的灯数组 +0x10 写入 16B 颜色）。缓冲维持：InitViews→**0x8f71fa0**→`FLightSceneInfo::ConditionalUpdateMobileMovablePointLightUniformBuffer` **0x8ebd440**（80 字节/灯栈结构 + 默认值 0/1.0，经 GDynamicRHI+0x118 建缓冲）；灯数 = `MobileBasePass::CalcNumMovablePointLights` **0x8ecd208**（cvar `r.MobileNumDynamicPointLights`@DAT_0c578478、`r.Mobile.EnableMovableSpotlights[Shadow]`@0x0c578488/498）。Azure 侧开关：`AzureSkipAllDynamicPointLightFlag` 0x8ed0ba8、`AzureSkipPlanarReflectionPointLight` 0x8f7af3c | GLSL 语义实证（行60-95）：`[0]=灯0 位置xyz+radius(w)`（`1-dist/max(w,1e-4)` 平方衰减）、`[1]=灯0 颜色rgb×强度w`（`v13.xyz*v13.www`）、`[2]/[3]=灯1`。坐标与顶点世界坐标同空间（相机相对：v5=TEXCOORD8-pc0_h[5]）。**注意：0x8ebd440 的栈结构每灯 80B（含阴影矩阵），与 pc2 的 64B/2灯 布局不同 → pc2 更可能是游戏侧紧凑化后的自定义填充（见 §5）** |
| pc3_h[1]（变体 pc3_h[6]，行32） | 1/6 | PS slot3 | 同上 slot3 | 未定位 | GLSL 行130：整 vec4 直接消费 |
| **pc4_h[6]（材质参数块）** | 6 | PS slot4（=shader+0xe0 处 ushort 索引） | 0xab4251c（槽位来自 0xab0fe38 的 slot 参数） | **`FUniformExpressionSet::FillUniformBuffer` 0xa129b5c**（size 4944，part_000063），由 **`FMaterialRenderProxy::EvaluateUniformExpressions` 0xa0fe0a4**（part_000071.c:50392）调用：按 UniformExpressionSet+0x150 的 UniformBufferSize 在 FMemStack 分配 → FillUniformBuffer 把每个常量 uniform 表达式求值写入对应偏移 → RHICreateUniformBuffer（GDynamicRHI+0x110，延迟时走 PTR_ExecuteAndDestruct_0bc6efa0 命令）→ 缓存在 FUniformExpressionCache+0x10；**FMaterialRenderProxy+0x10 为渲染线程缓存副本**（0x918fa7c 快路径直接取用） | 数据源 = 该 MID（Spine 每槽一个 MID：0x70ba730/0x70bbdf8 逐槽创建，spine_render/part_000009）的全部向量/标量参数 uniform 表达式。GLSL 槽位实证（行98-209）：`[0].xyz`=染色 rgb（行197 mix(pc4_h[0].xyz,v73,v74)）、`[2].x`=ExpR（pow(v6.x)）、`[2].z`=ValueR、`[2].w`=ExpG、`[3].y`、`[3].w`/`[4].y`=压暗（行187/191）、`[5].x`=灰阶（行120-126）、`[5].z`（行201）。与 _state.md 的 MID 参数写入底座 0xa0e5800/0xa0e5a78/0xa0e5d2c、渲染线程落点 0xa10e24c、向量下发 0xa10de88/0xa10f328 相接：游戏线程 SetVector/SetScalarParameterValue → uniform 表达式缓存失效（InvalidateUniformExpressionCache 0xa0d9a5c / RecacheAllMaterialUniformExpressions 0xa0e8aa0）→ 绘制时 0xa0fe0a4 重算 → pc4 |
| pc5_h[1]/pc6_h[7]（仅 FS_6899cbee 全功能变体，行33/35） | 1/7 | slot5/6 | 同上 | 未定位（pc6_h[7] 推测为光照/附加材质区） | — |

顶点侧对照（VS_ee722254，行28-30，vcN = 顶点 packed）：`vc2_h[10]` = **FPrimitiveUniformShaderParameters**（实证行81/71：`vc1_h[0..2]·ATTR0 + vc1_h[3] + vc0_h[0]` 与 `vc2_h[3]+vc2_h[2..0]·v2` 两次 3x4 变换；vc2[0..3]=LocalToWorld 行；`vc0_h[0]`=PreViewTranslation 单独一块）；`vc1_h[5]`=4x4 矩阵+附加行（Spine 槽/形变矩阵）；块内槽位按 UB 结构体原偏移保留（数组声明长度=最大用槽+1，空洞保留）。

## 4. 与 GLSL 槽位的交叉验证

- FS_b12f6bb5b7eea4604b1d6ce286db8d704e920af0.glsl：行30-36 声明 pc0_h[10]/pc1_h[4]/pc3_h[1]/pc2_h[4]/pc4_h[6]/ps0/ps1；行46-205 使用点逐条见 §3 表“GLSL 槽位实证”。
- FS_6899cbee9bb828f636a9ccc44527c0c525794113.glsl（全功能变体，316 行）：行30-36 实际声明 pc0_h[17]/pc1_h[5]/pc3_h[6]/pc5_h[1]/pc4_h[4]/pc6_h[7]/pc2_h[2]（此前记录 pc1_h[4] 系 b12f 变体的值）。
- VS_ee7222549881b70414cfb0994a9403b5aa1ef076.glsl：行28-30 vc0_h[1]/vc1_h[5]/vc2_h[10]，vs0=sampler3D（行32，VF 前一变体 VS_4c1cbc62）。
- 统一模拟路径判定依据：三份 GLSL 均为 `uniform vec4 pcN_h[N]` 独立数组（非 `uniform block`），故绘制期只有 glUniform4fv 系（0xab42414/0xab4251c）活跃；glUniformBlockBinding（0xab3c07c）/glBindBufferBase（0xab3a028）为 GLES 不具备 UBO 时的备用真 UBO 路径。
- **GLSL 里的 N 即 RHISetShaderUniformBuffer 的 slot 参数**（同一着色器资源绑定序），块间空洞（如无 pc5）= 该 PS 未引用对应槽；块内下标保留 UB 结构原 vec4 偏移（vc2_h[0..3]=LocalToWorld 连续 4 槽为铁证）。

## 5. 边界与待办（诚实声明）

1. **pc1/pc2/pc3/pc5/pc6 的“哪个游戏函数填这 4/1/1/7 个 vec4”未闭合**：0x8ebd440（stock 移动端可动点光）为 80B/灯 含阴影矩阵，与 pc2 的 64B/2灯 紧凑布局不匹配；pc2 数据的颜色半边已实证到 FLightSceneProxy::SetAzureCharColor（0x9dbadd4），但“位置xyz+radius 与颜色×强度打包成 4 vec4”的生产者需运行期挂钩 glUniform4fv（记录 location→GLSL 槽映射）或对 spine 绘制链（0x70bb2f4→0x70bc048→MeshBatch→FMobileBasePassMeshProcessor 0x8ecf448）做 B 段精读确认。
2. FUniformExpressionSet::FillUniformBuffer 0xa129b5c 内部（4944B）未逐表达式展开——pc4 六个槽位各自对应哪个 MID 参数名，需 B/C 段对该函数与 MID 参数名表（0xa0e5800 族写入的参数名）联查。
3. FOpenGLShaderParameterCache 暂存布局实测：cache 每级 +0xb0；globals 暂存指针 +0x00/0x08/0x10（float/int/uint），脏区 +0x38(start)/+0x3c(len)；UB 暂存 +0x70/0x78/0x80，脏区 +0xa8/+0xac —— 供 B 段做内存断点用。
