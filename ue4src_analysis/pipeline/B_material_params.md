---
agent: B（材质参数求值链）
range: ue4src part_000018/62/63/64/65/70/71/72/74 + res_parentmaterials 资产 + render_work/v2_shadermap GLSL
topic: MySpineLitNormalMaterialV2 资产默认值/MPC/MID 覆盖 → pc4_h uniform 数值 全链路溯源
---

# B 段：材质参数求值链（资产 → uniform 数值）

## 1. 求值器精读

### 1.1 FMaterialRenderProxy::EvaluateUniformExpressions = 0xa0fe0a4（part_000071.c:50392）

- 输入：`FMaterialRenderContext`（内含 MaterialRenderProxy+Material）；从 `Material+0x28` 取 FMaterialResource，再 `+0x70` 取 **FUniformExpressionSet**（即 cook 进 uexp 的 CachedExpressionSet 运行时形态）。
- 过程：为 VT 栈分配（+0x130 区）→ 在 MemStack 上分配 `UniformPreshaderBufferSize`（set+0xe0，即 abs+0x150）字节缓冲 → 调 `FUniformExpressionSet::FillUniformBuffer(0xa129b5c)` 逐表达式求值写入 → 用 RHI `CreateUniformBuffer`（layout=该 set）建 **FRHIUniformBuffer**，存入 `FUniformExpressionCache.UniformBuffer`（param_1+0x10）；**同一函数把 set+0xd0 的 `ParameterCollectionGuids`（每项 16B FGuid）拷入 `FUniformExpressionCache.ParameterCollectionGuids`（param_1+0x38）**（part_000071.c:50642-50656）——这是 MPC 独立缓冲的挂接点。
- FUniformExpressionSet 布局由 `GetSummaryString`(0xa123e54, part_000072.c:28363) 直接给出：`(%u vectors @+0x08, %u scalars @+0x18, 2dtex@+0x48, cube@+0x58, 2darray@+0x68, 3d@+0x78, VT@+0x88, ext@+0x98, stacks@+0xc8, collections@+0xd8)`。

### 1.2 FUniformExpressionSet::FillUniformBuffer = 0xa129b5c（part_000063.c:190568）

写入顺序（=uniform buffer 内存顺序，与 GLSL 块内 slot 顺序一致）：
1. **向量输出**：count=set+0x08，每项 16B（FVector4），从 set+0x00 的 {offset,size} 头表读字节码区间（part_000063.c:190682-190700）；
2. **标量输出**：count=set+0x18，每项 4B，从 set+0x10 头表读（part_000063.c:190701-190730），尾部对齐 16B；
3. 纹理/外部纹理/VT 由其余数组走 GWhiteTexture/VT producer（略）。
每项求值统一调 **FUN_0a127bc0**（传入：字节码 {start,end}、set+0xa0 处参数名/默认值表指针、FMaterialRenderContext、输出 FVector4*）。

### 1.3 preshader VM = FUN_0a127bc0 = 0xa127bc0（part_000074.c:47918，栈式解释器，操作数栈=TArray<FLinearColor> 内联 64）

opcode 全目录（switch@47986 起逐 case 实读）：

| op | 语义 | op | 语义 |
|---|---|---|---|
| 0x01 | push0（VT 缺省） | 0x14 | dot（掩码字节） |
| 0x02 | push 常量 FLinearColor（16B 立即数） | 0x15 | cross |
| **0x03** | **标量参数**：u16 索引 → set+0xa0 表[stride 0x18：+0x10 类型字节、+0x14 默认值]；先问 `MaterialRenderProxy->vt+0x68`（MID 覆盖），再 Material 侧默认，最后取表内默认 | 0x16 | sqrt |
| **0x04** | **向量参数**：u16 索引 → 表[stride 0x24：+0x14 默认 FVector4]；先问 `MaterialRenderProxy->vt+0x60`（MID 覆盖） | 0x18 | saturate |
| 0x05-0x09 | add/sub/mul/div/fmod（sub=次顶-顶） | 0x19-0x1e | abs/trunc/floor/round/floor2/sign |
| 0x0a/0x0b | min/max | 0x1f/0x20 | frac |
| 0x0c | clamp（3 操作数） | 0x21/0x22 | log2/loge |
| 0x0d-0x13 | sin/cos/tan/asin/acos/atan/atan2 | **0x23/0x24** | swizzle（6B）/append（2B） |
| | | 0x25/0x26 | time/period（解析 World 引用取 GameTime/RealTime/DeltaTime，0x26 输出 1/周期） |
| | | 0x27/0x28 | 外部纹理 ScaleRot/Offset（FExternalTextureRegistry） |
| | | 0x29 | RuntimeVirtualTexture uniform 参数 |

**关键结论**：本 build 的 preshader **没有 collection(MPC) opcode**——MPC 不进该 VM（见 §3）。参数覆盖链：`case3/4 → FMaterialRenderProxy::GetScalarValue/GetVectorValue(虚表 0x68/0x60)`。MID 侧实现= `FMaterialInstanceResource::GetScalarValue` 0xa0d8900（part_000070.c:59017：查 this+0xb0 的 MID 标量覆盖数组[stride 0x18，值@+0x8]，特判 __SubsurfaceProfile，失败上溯父代理 vtable+0x68）；向量侧 0xa0d2fb0（part_000070.c:58523）；`FDefaultMaterialInstance` 兜底。memimage 侧 `FUniformParameterOverrides`：Set 0xa122df0（TSet<TTuple<FMemoryImageMaterialParameterInfo,FLinearColor>>@+0x50，part_000064.c:64106）、GetVectorOverride 0xa123078、GetScalarOverride 0xa123020（part_000062.c:215301）——同一覆盖语义的内存映像形态。

## 2. 资产侧实证（uexp 解码）

`unpacked/res_parentmaterials/materialmasters/spinematerials/myspinelitnormalmaterialv2.uexp`（32140B）含**两份完全相同的 FMaterialResource**（R1/R2）：

| R1 | R2 | 内容 |
|---|---|---|
| 头表 T6@0x4880（6 项） | @0x72a2 | **向量 preshader 头 {offset,size}** |
| 头表 T19@0x48b0（19 项） | @0x72d2 | **标量 preshader 头** |
| 字节码@0x4a7c（469B） | @0x749e | UniformPreshaderBuffer（R1/R2 逐字节相同） |
| 参数表@0x4948+ | @0x736a+ | 标量条目 stride 0x18（+0x10 类型、+0x14 默认值） |

- **6 个向量输出**（解码自字节码，opcode 表见 §1.3）：
  - v0 = vectorparam#0（整 vec4 直通）
  - v1 = vectorparam#0 的 rgb swizzle
  - v2/v3 = `0−scalar#4`（两次）+append → (−s4,−s4,−s4,−s4)
  - v4 = `scalar#6, 1−scalar#6` append
  - v5 = v4 产物 × scalar#7
- **19 个标量输出**（`|` 分隔栈操作）：`s0 | s1 | max(s1,0) | s2 | s3 | max(s3,0) | −s1 | max(−s1,0) | −s3 | max(−s3,0) | s4 | 0−s4 | s4+1 | s5 | clamp01(s5) | s6 | 1−s6 | s7 | s8`
- 参数表默认值序列（s0..s9）= **1, 0, 1, 0, 0.005, 1, 0.5, 1, 0, 1**（0x4948 起，+0x14 float 逐一读出）。**s4=0.005 唯一命中 Contrast=0.005**；与 22 参数默认值对照：s0/s2∈{ExpR,ExpG,LightScale,darkenParam}(1.0)，s1/s3/s8∈{ValueR,ValueG,Curve Atlas Index}(0.0)，s6∈{Sub Jitter Ratio,Hardness,Scan Line Intensity,CharacterIndirectLightPercent}(0.5)，s5/s7/s9∈1.0 组。
- 桌面 cook 的 uniform 集只引用 10/22 个标量、1/4 个向量；**darkenParam、Period、Tilling、Num Scan Line、Scan Line Color 等不在这份 uniform 表达式集里**（只进像素图，按变体烘焙或进别的块）。
- 桌面这份 6 向量+19 标量=172B 的布局**不等于**任一 GLSL 变体的 pc4_h（运行时 Android shader library 在 cook 时按变体生成了更小的 uniform 集，见 §4）。

## 3. MPC 注入链（DarkenMPC / PointLight）

MPC 值**不走 preshader**，走**独立 uniform buffer**：

1. 写入：`UMaterialParameterCollectionInstance::SetVectorParameterValue`=0xa12ec84（part_000071.c:53066；写 this+0x98 TSet<FName,FLinearColor>[stride 0x24] → `UpdateRenderState` → OnParameterUpdateInitialized Broadcast）；标量对应物同理。
2. 下发：`FMaterialParameterCollectionInstanceResource::GameThread_UpdateContents`=0xa12dffc（part_000064.c:64719）——拿 FGuid+`TArray<FVector4>`（每参数 16B），在渲染线程 `RHICreateUniformBuffer(layout=size=N×16B)`，存 this+0x20；bRecreate 时 UpdateUniformBuffer。
3. 读侧：`UMaterialParameterCollectionInstance::GetVectorParameterValue`=0xa12f364（part_000065.c:203553；实例覆盖 @+0xc，缺省回落 FCollectionVectorParameter 默认值 @+0x1c）。
4. 资产实证（`unpacked/res_parentmaterials/mpc/`，非 reversed/properties）：
   - **PointLight**（CollectionVectorParameter×5）：`AmbientColorForUnlit, LightAColorAndIntensity, LightAPosAndRadius, LightBColorAndIntensity, LightBPosAndRadius`。
   - **DarkenMPC**（CollectionScalarParameter×13）：`AbsorbToBlackHoleEndPos/Progress, BgBlurRatio, BlurTransitionAreaDistance/StartDistance, CustomTimeCtrl, CustomTimeValue, CustomTimeValue2, CustomTimeValue2ChangeRate, CustomTimeValueChangeRate, FarDistance, MaxDarkenAlpha, NearDistance`（uexp 内默认浮点 200.0/1024.0/800.0 等）。
5. **GLSL 落点（决定性证据）**：
   - FS_2afa/FS_b12f6bb5：`pc2_h[4]`——`pc2_h[0]=(A.xyz 位置, A.w 半径)→h9=max(1−dist/max(w,1e-4),0)`、`pc2_h[1]=A 颜色(×w 强度)`、`pc2_h[2/3]=B`；贡献项 `max((h9*h9)*(rgb*w),0)`——**pc2_h=PointLight MPC，双点光强度来源成立**（名字与 PointLight.uasset 四向量一一对应；平方衰减×rgb×intensity）。
   - 同两文件：`pc3_h[0]`——`h43=dot(N,像素−相机)−pc3_h[0].x`、暗化系数 `min(max((pc3_h[0].z/(pc3_h[0].y−pc3_h[0].x))*max(h43,0),0), pc4_h[5].z*pc3_h[0].z)`——**= (NearDistance, FarDistance, MaxDarkenAlpha, …)，即 DarkenMPC 标量打包 float4**（1 float4 块；FS_5aacf 变体里 DarkenMPC 全量块=pc3_h[4]，PointLight=pc3_h[4] 处则是单灯版 pc3_h[0..3]，见下表）。
   - 块编号逐变体浮动：FS_5aacf：PointLight=pc3_h[0..3]；FS_6899（深度渐隐变体）：PointLight=pc4_h[4]、DarkenMPC=pc5_h[0]、材质块=pc6_h[7]、马赛克/扫描线 UV 块=pc3_h[6]（`v103=m[5]+m[4]z+m[3]y+m[2]x`，`±0.5*pc3_h[0].zw`，阈值 `pc3_h[1].x`——Tilling/Num Scan Line 族在此）。

## 4. pc4_h 逐槽位映射（GLSL 实读 + 默认值交叉验证）

变体矩阵（render_work/v2_shadermap，9 FS 中 5 个 lit）：

| 变体 | 材质块 | PointLight MPC | DarkenMPC | 说明 |
|---|---|---|---|---|
| FS_b12f6bb5 | **pc4_h[6]** | pc2_h[4] | pc3_h[1] | 协调者所述"6 项"变体 |
| FS_2afa | pc4_h[7] | pc2_h[4] | pc3_h[1] | 同上+OverrideNormal（全体后移 1） |
| FS_6899/FS_bdcdce | pc6_h[7]（另 pc3_h[6]=马赛克块） | pc4_h[4] | pc5_h[1] | 深度渐隐 |
| FS_5aacf/FS_bd3b558d | pc4_h[1] | pc3_h[0..3] | pc5_h[6] | 单灯简化 |
| FS_25c5a158/722063ce/9b21bb65 | 无（discard/纯色） | — | — | 裁剪版 |

**FS_b12f6bb5 逐槽位（=协调者映射的逐条确认）**：

| 槽 | GLSL 消费 | 语义 | 来源 | 默认值→行为 |
|---|---|---|---|---|
| pc4_h[0].xyz | `v75=mix(pc4_h[0],灰阶,diffuse×顶点色)` → ILC/底色 | **染色 Color 向量参数** | 资产默认 (0,0,1,1)+MID SetVectorValue 覆盖 | 未染色漫反射区=蓝底 |
| pc4_h[1].xy | `h58=mix(v46.x,1,…)`（×v56=0 死支） | 平移/马赛克参数（Pan Speed 族） | 资产 (0.1,0.1,0,1) | 本变体死代码 |
| pc4_h[2].x | `pow(maskR,pc4_h[2].x)` | **Exp R** | 资产默认 1.0 | 默认线性（脉冲形状=mask 本身） |
| pc4_h[2].z | `h29=max(pow×[.z]−1,0)` 进发光 | **Value R** | **资产默认 0.0** | **max(0−1,0)=0 → 脉冲发光默认关闭** ✓ |
| pc4_h[2].w | `pow(maskG,pc4_h[2].w)` | **Exp G** | 1.0 | 线性 |
| pc4_h[3].y | `h81=powG×[.y]` → 发光 max(−1,0) | **Value G** | 0.0 | 默认关闭 ✓ |
| pc4_h[3].w | `h70=powR×[.w]` → `(1−h70−h72)×底色` | R 压暗权重 | 资产（1.0 组） | 染色区被脉冲压暗 |
| pc4_h[4].y | `h72=powG×[.y]` → 同上 | G 压暗权重 | 资产 | 同上 |
| pc4_h[5].x | `v37=vec3(灰阶)`，mix 目标 | 灰阶 | 资产（推定 LightScale=1.0 一类，名字待运行时 uniform 元数据核） | 漫反射区向灰阶收缩 |
| pc4_h[5].z | `h77=[.z]×MaxDarkenAlpha` 封顶 | **遮罩强度** | 资产 | 与 DarkenMPC 相乘封顶暗化 |

FS_2afa 增量：pc4_h[0]=`normalize(pc4_h[0].xyz)`→ILC 查找方向=**OverrideNormal (0,0,1,0)**；其余槽整体 +1。**Scan Line Color (0.35,0.67,1,1) 不在这 5 个 lit 变体的 uniform 槽中**——扫描线消费分支已被该组变体裁剪（扫描线/马赛克特征块在 FS_6899 的 pc3_h[6]，全息特征另见 mi_ui_spinedesaturatematerial 族）；pc4_h[0] 染色槽对应资产 **Color** 参数。

## 5. MID 覆盖链（darkenParam / Rongjie）

1. **创建**：0x70bbdf8（part_000018.c:19422）——spine 挂件 MID 缓存工厂：命中缓存（vt+0x440 两次查找 + 父材质比对）复用；否则 `UMaterialInstanceDynamic::Create(父材质)` → `SetTextureParameterValue×2`（组件 +0x704/+0x710 字段）→ **`SetScalarParameterValue("darkenParam", *(组件+0x920))`、`SetScalarParameterValue("Rongjie", *(组件+0x928))`** → 写缓存（哈希=参数>>4 的 cityhash 变体）。两个标量值来自 spine 组件运行时字段（Lua/蓝图可改）→ 动态。
2. **存储**：UMID→FMaterialInstanceResource 覆盖数组（GetScalarValue 0xa0d8900 读 this+0xb0）；memimage 侧 FUniformParameterOverrides::Set*（0xa122df0）。
3. **消费**：preshader 0xa127bc0 case3/4 每帧经 `MaterialRenderProxy->GetScalarValue/GetVectorValue`（虚表 +0x68/+0x60）优先取 MID 覆盖 → 无覆盖回落 uexp 默认值。
4. **落槽**：darkenParam/Rongjie 是材质标量 → 进**打包标量槽**（每 float4 装 4 个标量输出）。在本次可得的 9 个 FS 里**无任何活性消费点**（5 个 lit 变体的标量槽已被 ExpR/ValueR/ExpG/ValueG/两压暗/灰阶/遮罩强度占满；溶解分支被裁剪——溶解专用母材质是 myspinelitdissolutionmaterial，另属 shader map）。结论：**darkenParam/Rongjie 仅在保留溶解分支的变体中占用打包标量槽**（13 变体中部分出现，与预警一致）；MID 一旦 SetScalar 即通过 §5.3 链路覆盖同名槽。

## 6. 结论：逐槽位数值来源总表

| 槽（FS_b12f6bb5 基准） | 默认值资产 | MPC | MID 覆盖 | 动/静 |
|---|---|---|---|---|
| pc4_h[0].xyz 染色 Color | (0,0,1,1) | — | SetVectorValue 可覆盖 | **动态**（按 MID） |
| pc4_h[1].xy Pan Speed 族 | (0.1,0.1,0,1) | — | 可覆盖 | 本变体=常量死支 |
| pc4_h[2].x ExpR=1.0 / .z ValueR=0.0 / .w ExpG=1.0 | uexp s 组默认 | — | SetScalar 可覆盖 | 默认=**常量**（脉冲关）；被 SetScalar 即动态 |
| pc4_h[3].y ValueG=0.0 / .w R压暗 / pc4_h[4].y G压暗 | uexp 默认 | — | 可覆盖 | 同上 |
| pc4_h[5].x 灰阶 / .z 遮罩强度 | uexp 默认 | — | 可覆盖 | 同上 |
| pc2_h[0..3]（或 pc4_h[4]/pc3_h[0..3]）双点光 | —（无资产默认参与） | **PointLight MPC**（渲染线程可每帧变） | — | **动态** |
| pc3_h[0]=(Near,Far,MaxDarken) | darkenmpc.uexp 默认 | **DarkenMPC**（Sequencer 0x95ba2e4 / darkenactionhandler 写） | — | **动态** |
| pc3_h[6] 马赛克/扫描线块（FS_6899） | Tilling=10、Num Scan Line=30 等 | — | — | 变体相关 |

**静态可移植（常量）槽**：默认值下的 ExpR/ValueR/ExpG/ValueG/压暗权重/灰阶/遮罩强度——由 uexp 常量区（0x4900/0x7300 两份逐字节相同）决定，MID 不写即恒定；**动态槽**：pc4_h[0] 染色（MID SetVectorValue）、双点光 pc2_h（PointLight MPC）、暗化 pc3_h（DarkenMPC，战斗技能期 Sequencer/技能处理器驱动）、以及任何被 0x70bbdf8 SetScalar 过的标量（darkenParam/Rongjie 生效变体）。

## 证据索引（addr → 文件:行）

- 0xa0fe0a4 EvaluateUniformExpressions：part_000071.c:50392（Guid 拷贝 :50642）
- 0xa129b5c FillUniformBuffer：part_000063.c:190568（向量环 :190682、标量环 :190701）
- 0xa127bc0 preshader VM：part_000074.c:47918（case3 标量参 :47986 区、case4 向量参、case25/26 time/period、case27/28 外部纹理）
- 0xa123e54 GetSummaryString（set 布局）：part_000072.c:28363
- 0xa122df0 / 0xa123078 / 0xa123020 覆盖 Set/Get：part_000064.c:64106 / part_000072.c:28335 / part_000062.c:215301
- 0xa0d8900 FMaterialInstanceResource::GetScalarValue：part_000070.c:59017；0xa0d2fb0 GetVectorValue：part_000070.c:58523
- 0xa12dffc GameThread_UpdateContents（MPC→FRHIUniformBuffer）：part_000064.c:64719；0xa12ec84 SetVectorParameterValue：part_000071.c:53066；0xa12f364 GetVectorParameterValue：part_000065.c:203553
- 0x70bbdf8 MID 工厂（darkenParam/Rongjie）：part_000018.c:19422
- 资产：myspinelitnormalmaterialv2.uexp（T6@0x4880、T19@0x48b0、bytecode@0x4a7c、dup@0x72a2/0x72d2/0x749e、参数表@0x4948/0x736a）；mpc/pointlight.uasset、mpc/darkenmpc.uasset（strings）
- GLSL：render_work/v2_shadermap/FS_b12f6bb5*.glsl:98-209、FS_2afa*.glsl:58-229、FS_6899*.glsl:84-285、FS_5aacf*.glsl:60-100
