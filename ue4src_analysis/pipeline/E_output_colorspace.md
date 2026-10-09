---
agent: GLM-5.3-Flash (ZCode subagent)
range: E段（FS 输出之后：混合、渲染目标、色调映射、最终呈现）
topic: FMobileSceneRenderer 半透明混合→SceneColor→MobileTonemapper→呈现 全链路颜色空间溯源
date: 2026-09-29
---

# E 段：FS 输出之后 —— 混合、渲染目标、色调映射与最终呈现

语料：`D:\项目\dragonraja\unpacked\reversed\ue4src\part_*.c`（全部结论均实读反编译代码，标注 addr+分片行号）。
关联已有分析：`engine_core/part_000047.md`（RenderDeferred 0x8f74ec8）、`engine_core/part_000048.md`（Render 0x8f7321c）。

---

## 1. Translucency pass 的位置与 bEnableMobileSeparateTranslucency 行为

### 1.1 主序列（实读）

`FMobileSceneRenderer::Render` = **0x8f7321c**（part_000048.c:121643）：

- `param_1[0x42a]==0 → RenderForward()，否则 RenderDeferred()`（part_000048.c:122352）
- 之后 `FRendererModule::RenderPostOpaqueExtensions`
- 每个 view 调 **`AddMobilePostProcessingPasses`（RDG）= 0x8fc76d8**（part_000048.c:122648 附近，callgraph_edges.csv 有 0x8fc76d8→0x9022b6c/0x9020fa0 边）
- 最后 `FSceneRenderer::RenderFinish` + `FRDGBuilder::Execute`

`FMobileSceneRenderer::RenderDeferred` = **0x8f74ec8**（part_000047.c:149061），单一大 RenderPass 内顺序：

```
BeginRenderPass(SceneColor + MRT/Depth, "BasePassRendering")
  → RenderPrePass            (param_1[0x43a]==0 时)
  → RenderMobileBasePass     ← 不透明+部分半透明
  → RenderAzureOutlinePass   ← 龙族游戏层角色描边（紧跟 BasePass，见 part_000047.md）
  → RenderOcclusion
  → RenderDecals             (bit13 of *(param_1+0x38))
  → MobileDeferredShadingPass（延迟路径）
  → RenderTranslucency       ← 【半透明在此】stat "RenderTranslucency"，bit8 of *(param_1+0x40) 门控
EndRenderPass
（此后才是 AddMobilePostProcessingPasses：Bloom/DOF/Sun/EyeAdaptation/SeparateTranslucency 合成 → Tonemap）
```

`FMobileSceneRenderer::RenderTranslucency` = **0x8f77f20**（part_000039.c:198639）：直接把半透明 MeshDrawCommand 画进**当前缓存渲染目标（SceneColor+Depth）**（FSceneRenderTargets::Get + ApplyCachedRenderTargets，行 198930/198952）。

**结论（Q1 前半）**：Translucency 在 opaque（BasePass）之后、**在色调映射之前**——它发生在场景色 RenderPass 内部，tonemap 是之后的独立后处理 pass。

### 1.2 bEnableMobileSeparateTranslucency 分支

- 材质级开关：`FMaterialResource::IsMobileSeparateTranslucencyEnabled` = **0xa0f997c**（part_000063.c:185292）：检查 FMaterialResource 标志字节 `(*(this+0x38)+0x227) bit0`（即材质 bEnableMobileSeparateTranslucency）+ 混合模式/TranslucencyAfterDOF 条件。战斗 Spine 材质 =True 时启用。
- 视图级判定：`IsMobileSeparateTranslucencyActive` = **0x8f6fbac**（part_000047.c:148147）：view 内单独半透明 pass 的 draw command 数（FViewInfo+0x403c）>0 即激活。
- 激活时：半透明先画进**独立 RT（SceneSeparateTranslucency）**，后处理阶段再合成：
  - `AddMobileSeparateTranslucencyPass` = **0x8f6fc28**（part_000047.c:148177）
  - `AddSeparateTranslucencyCompositionPass` = **0x8fc12ac**（part_000055.c:33295）：新建 "SceneColor" RDG 纹理，用 `FComposeSeparateTranslucencyPS` 把单独 RT 合成回场景色（含 SeparateTranslucencyUpscaling 分辨率缩放）
  - 合成 PS 参数名（part_000048.c:123321/123393）：`SceneSeparateTranslucencyModulateColor`、`SceneDepthTexture`、`SeparateTranslucencyUpscaling`
- **在 AddMobilePostProcessingPasses（0x8fc76d8）内的调用序（实读行偏移）**：
  - offset 1327：`AddMobileSeparateTranslucencyPass`（合成进场景色）
  - offset 1592：`AddTonemapPass`（非移动 tonemap 分支）/**offset 1750：`AddMobileTonemapperPass`（移动分支）**

**结论（Q1 后半）**：是的——bEnableMobileSeparateTranslucency=True 时单独 RT 渲染、后处理前期再合成；**无论哪条路，半透明合成都在 MobileTonemapper 之前完成**。

---

## 2. 场景颜色缓冲格式：线性 HDR（半浮点）

### 2.1 格式选择

`FSceneRenderTargets::GetDesiredMobileSceneColorFormat` = **0x908d048**（part_000057.c:3435）：

| 条件 | 格式（枚举值） |
|---|---|
| 默认（无 HMD） | 2 = PF_B8G8R8A8 |
| `IsMobileHDR() && GSupportsRenderTargetFormat_PF_FloatRGBA` | **10 = PF_FloatRGBA** |
| `IsMobileDeferredShadingEnabled(GMaxRHIShaderPlatform)` | 26(0x1a) = PF_FloatR11G11B10 |
| cvar `r.Mobile.SceneColorFormat`=1 / =2 | 10=FloatRGBA / 26=R11G11B10（=3 落回 LDR） |

像素格式枚举值证据：`GetPixelFormatString` = **0x848b7c8**（part_000040.c:56512）+ 名称表（part_000043.c:13244-13348）：2=PF_B8G8R8A8、9=PF_FloatRGB(R11G11B10)、**10=PF_FloatRGBA**、0x1a=PF_FloatR11G11B10、0x25=PF_R8G8B8A8。

### 2.2 MobileHDR 与 sRGB 开关

- `IsMobileHDR` = **0xa3b6fc0**（part_000073.c:102252）：读 cvar **`r.MobileHDR`**（UE4.25 默认 1）。
- `IsMobileColorsRGB` = **0xa3b70b4**（part_000076.c:79467）：`r.Mobile.UseHWsRGBEncoding && !IsMobileHDR()`——MobileHDR=1 时恒为 false。
- `FSceneRenderTargets::AllocSceneColor` = **0x908e1f4**（part_000055.c:54391）：分配 pooled RT **"SceneColorMobile"**；仅当 `isMobilePlatform & IsMobileColorsRGB()` 才给 Desc 加 flag 0x10（sRGB read/write 语义），**默认（MobileHDR=1、UseHWsRGBEncoding=0）不加 → 线性语义的 PF_FloatRGBA 半浮点 RT**。

### 2.3 关键补充：材质 PS 尾部的软件 sRGB 编码

`TMobileBasePassPS::ModifyCompilationEnvironment`（part_000047.c:125960-126005）：

```cpp
// 读 cvar r.Mobile.UseHWsRGBEncoding
SetDefine("OUTPUT_GAMMA_SPACE",  UseHWsRGBEncoding==0 ? true : (value!=1));  // 默认 = true
SetDefine("OUTPUT_MOBILE_HDR",   0);
```

即默认（UseHWsRGBEncoding=0）下 **Mobile BasePass PS（含 Spine 材质 FS 尾部）在着色器里把线性结果编码成 sRGB 后写入 out_Target0**（`OutColor = LinearToSrgb(OutColor)`，引擎 4.25 MobileBasePassPixelShader.usf 行为；宏由本二进制确认）。**这正是用户观测到的材质内部 "sRGB encode 分支 pu_m 门控=ON" 的来源。**
另一佐证：`ShouldCacheShaderByPlatformAndOutputFormat` = **0x8ed2474**（part_000050.c:67796）：`(OutputFormat==0) ^ IsMobileHDR()` —— 移动 BasePass 着色器按输出空间分变体缓存。

**结论（Q2）**：场景色 RT 本身是**线性语义的 PF_FloatRGBA 半浮点 HDR**（无硬件 sRGB）；但**存储的数值在默认配置下是 BasePass PS 软件 sRGB 编码后的值**（gamma 空间混合），即"buffer 线性、数据 gamma"。游戏未开 `r.Mobile.UseHWsRGBEncoding` 时，四槽混合全部发生在 gamma 空间。

---

## 3. 色调映射：FMobileTonemapper

### 3.1 函数地址

| 项 | addr | 位置 |
|---|---|---|
| `AddMobileTonemapperPass`（移动 tonemap pass 入口） | **0x9022b6c** | part_000055.c:39351 |
| `AddTonemapPass`（非移动分支 FTonemapPS） | 0x9020fa0 | part_000041.c:85894 |
| `GetMobileFilmTonemapParameters`（CPU 侧取 FilmSlope/Toe/Shoulder/Clip） | **0x901f4ac** | part_000041.c:85333 |
| `GetTonemapperOutputDeviceParameters` | 0x901f950 | part_000047.c:2880 |
| `FMobileTonemapPS::ModifyCompilationEnvironmentImpl` | — | part_000055.c:39066 |
| `SetShaderParameters<FMobileTonemapPS>` | 0x9078f1c | part_000052.c:93495 |

分支：AddMobilePostProcessingPasses 内按 shader platform 选择 AddTonemapPass（桌面）或 **AddMobileTonemapperPass（移动 SP，Graland/Android 走这条）**（part_000055.c offset 1652-1750，DataDrivenShaderPlatformInfo 位掩码判断）。

### 3.2 参数与公式证据

FMobileTonemapPS::FParameters 成员名（part_000052.c:87575-87800 元数据）：
`SceneColorTexture`(Texture2D@0xf0)、`GrainScaleBiasJitter`(@0xc0)、`ColorMatrixB_ColorCurveCm2`(@0x60)、`ColorScale0/1`(@0x0/@0x4)；VS 侧：`DefaultEyeExposure`(@0x60)、`Color_ScreenPosToViewportScale`(@0x48)。

编译宏（FMobileTonemapPS/VSEnv，part_000055.c:39066-39340）：`USE_DOF / USE_LIGHT_SHAFTS / USE_COLOR_MATRIX / USE_SHADOW_TINT / USE_CONTRAST / NO_EYEADAPTATION_EXPOSURE_FIX=1 / EYEADAPTATION_EXPOSURE_FIX(VS)`。

**Eye adaptation 启用**（0x9022b6c 实读，part_000055.c:39665-39700）：
- 无固定曝光时 `GetEyeAdaptationFixedExposure(view)`，否则 `FViewInfo::GetLastEyeAdaptationBuffer(view, RHICmdList)` 把眼适应 buffer 绑定为 SRV（`puVar19[0x10]`）。→ 移动 tonemap **支持自动曝光（Auto Exposure），龙族若开启 AutoExposure 则场景亮度会被逐帧压/提**。

**Filmic 参数**（GetMobileFilmTonemapParameters 0x901f4ac 实读）：取 FPostProcessSettings 的 `FilmSlope(min≤2.0)/FilmToe/FilmShoulder/FilmBlackClip/FilmWhiteClip/WhiteTemp/WhiteTint/ColorSaturation/ColorContrast/ColorGamma/ColorGain/ColorOffset`，计算 ColorScale、InvGamma(0.18/中间灰 0.0225 下限)、LUT 混合（FilmSlope/FilmBlackClip 也出现在 `FCombineLUTParameters`，part_000045.c:177388-177448 —— LUT 合成路径）。

**编码常量的二进制证据**：AddMobileTonemapperPass 内写入参数 `2.2 / gamma`（part_000055.c:39959 `*(float *)((long)puVar28 + 0xe4) = 2.2 / fVar32`）与 `1.0 - grainIntensity*0.5`、`ABS(vignette)*0.01` —— 即 pow 次幂按 2.2/用户 gamma 缩放。

**公式（引擎 4.25 MobileTonemap.usf 重建，usf 本体不在反编译范围，参数名/宏/常量均为二进制证据）**：

```hlsl
half3 c = SceneColorTexture.Sample(...).rgb;        // BasePass 已 sRGB 编码的值
c = SrgbToLinear(c);                                // 解码回线性（与 BasePass 编码配对）
c *= Exposure(EyeAdaptation buffer / DefaultEyeExposure);
c = ColorMatrix / ColorScale 分级;                   // 饱和度/对比/增益/偏移（USE_COLOR_MATRIX/CONTRAST）
c = FilmToneMap(c);   // FilmSlope/Toe/Shoulder/BlackClip/WhiteClip 的 filmic S 曲线：
                      // x=max(BlackClip,c); 段式有理多项式，肩部压高光、趾部提黑位，中段对比↑
c = Vignette / FilmGrain;                            // GrainScaleBiasJitter、vignette*0.01
输出 = pow(max(c,0), 2.2/Gamma);                     // 编码到显示 gamma（OutColor = LinearToSrgb 等效）
```

输出目标：pass 内建 RDG 纹理 **"Tonemap"**，格式默认 **PF_B8G8R8A8(2)**，HDR 输出标志时 `GRHIHDRDisplayOutputFormat`（part_000055.c:39463-39470）→ 最终写进 ViewFamily 纹理（`TryCreateViewFamilyTexture`，0x8f7321c 内 122619 行附近）→ RHIPresent。

### 3.3 Spine 半透明像素是否被 tonemap

静态链路上两条路径（直接画 SceneColor 或 SeparateTranslucency RT）都在 AddTonemapPass/AddMobileTonemapperPass 之前汇入场景色，tonemap 是全屏后处理——**但实机捕获修正了适用性**：龙族实际运行的移动 LDR 分支全程 0 命中 tonemap 程序（glshim 全程捕获），即 r.MobileHDR off、场景直接写 sRGB 面（硬件编码），**材质内 sRGB encode 即最终色**，本报告的 tonemap 链路分析适用于 HDR 分支（iguf 记录 §12.7）。

---

## 4. 混合态：四种混合模式的 RHI blend 因子

证据 1：`FMobileBasePassMeshProcessor::Process`（0x8ecec9c 构造 + Process，part_000050.c:67434-67830，switch 于 Material 虚表 +0x218 = GetBlendMode()）。
证据 2：`MobileBasePass::SetTranslucentRenderState` = **0x8ecdb18**（part_000055.c:3828 起），同一套 TStaticBlendState。

EBlendFactor：0=Zero,1=One,4=SrcAlpha,5=InvSrcAlpha,8=DestColor；EBlendMode：2=Translucent,3=Additive,4=Modulate,5=ModulateDarken,6=AlphaComposite。

| 材质混合模式（游戏四槽对应） | case | TStaticBlendState（RT0，其余 RT 复制 CW_RGB/Add/One/Zero 版） |
|---|---|---|
| **Normal (BLEND_Translucent=2)** | case 2 | `<CW_RGB(7), BO_Add, **SrcAlpha(4), InvSrcAlpha(5)**, BO_Add, Zero, InvSrcAlpha>`；若 +0x88 变体标志（mobile masked-translucency 合并）则退化为仅写 Alpha 的 `<CW_ALPHA(8), Zero/Zero, One/Zero>` |
| **Additive (BLEND_Additive=3)** | case 3 | `<CW_RGB, BO_Add, **One, One**, BO_Add, Zero, InvSrcAlpha>`（alpha 仍走 Zero/InvSrcAlpha） |
| **Multiply (BLEND_Modulate=4)** | case 4 | `<CW_RGB, BO_Add, **DestColor(8), Zero(0)**, BO_Add, One, Zero>`（dstA=srcA） |
| Screen（游戏自定义槽） | 无原生 case | UE4 EBlendMode 无 Screen；同前 Premultiplied 风格 case5/默认（+0x228 bit10/11 即 ShadingModel 判定）落到 `<CW_RGB, BO_Add, One, InvSrcAlpha, BO_Add, Zero, InvSrcAlpha>`；case6 AlphaComposite=`<CW_RGBA(15), Add, Zero, InvSrcAlpha, Add, One, InvSrcAlpha>`。Screen 槽实际由材质图在 Normal 混合内做 `1-(1-a)(1-b)` 数学实现（同 Part B/D 段材质侧结论） |

附加行为：半透明 case 全部只写 CW_RGB（保留目标 alpha）；深度态为无深度写、LEqual（`TStaticDepthStencilState<false, CF_LessEqual...>`，part_000050.c:67672）；排序键 `CalculateTranslucentMeshStaticSortKey`（part_000050.c:67810 附近）。

---

## 5. 结论：out_Target0 → 屏幕的完整颜色路径

默认 Graland/Android 配置（r.MobileHDR=1、r.Mobile.UseHWsRGBEncoding=0、支持 FloatRGBA）：

```
Spine 材质 FS（线性光照计算）
   └─ 材质尾部 sRGB 软件编码（OUTPUT_GAMMA_SPACE=1，宏由 0x8f? TMobileBasePassPS::ModifyCompilationEnvironment 确认）
      → out_Target0 = LinearToSrgb(线性色)        ← 用户观测的 pu_m 门控即此处
bEnableMobileSeparateTranslucency=True：
   ├─ 硬件混合进独立 SceneSeparateTranslucency RT（PF_FloatRGBA，gamma 空间数值）
   │   blend：Normal=SrcAlpha/InvSrcAlpha（0x8ecdb18 / FMobileBasePassMeshProcessor::Process）
   ├─ AddMobileSeparateTranslucencyPass(0x8f6fc28)/AddSeparateTranslucencyCompositionPass(0x8fc12ac)
   │   FComposeSeparateTranslucencyPS 合成回 SceneColor（PF_FloatRGBA 线性语义半浮点，0x908d048/0x908e1f4）
   └─ AddMobileTonemapperPass(0x9022b6c)：
       读 SceneColor → SrgbToLinear 解码 → ×EyeAdaptation 曝光 → ColorScale/Matrix 分级
       → FilmToneMap(FilmSlope/Toe/Shoulder/BlackClip/WhiteClip filmic S 曲线)
       → Vignette/Grain → pow(c, 2.2/Gamma) 编码
       → ViewFamily 纹理（PF_B8G8R8A8 LDR）→ RHIPresent 呈现
```

**实机判定（捕获修正）**：龙族移动端实际走 LDR 分支——无 tonemap pass，场景写 sRGB 面（硬件编码），材质内 encode 的值就是屏幕值。以下 HDR 分支分析保留作引擎结构参考。

### 对移植观测偏差的分析框架（HDR 分支才适用）

HDR 分支链路相对"裸线性管线"多做的三件事，全部指向"压亮度、提饱和"：

1. **Filmic tonemap 的 S 曲线**：肩部压高光，中段斜率=FilmSlope(默认~1)>1 → 中间调对比↑。
2. **Eye adaptation（自动曝光）**：暗场景提亮、亮场景压暗。
3. **gamma 空间混合**：BasePass 输出先 LinearToSrgb 再做 SrcAlpha/InvSrcAlpha 混合。
4. **双重编码陷阱**：HDR 数据流是"编码→混合→解码→tonemap→再编码"；移植时对已编码值再做一次 gamma 提升会提亮褪饱和。

**龙族实机（LDR）的移植对齐**：贴图采样值经材质内 encode 后即屏幕值——对齐=复现材质公式与 encode，无需 tonemap/眼适应（iguf 记录 §12.7/§12.9）。

### 本报告引用地址速查

| 符号 | addr |
|---|---|
| FMobileSceneRenderer::Render | 0x8f7321c |
| FMobileSceneRenderer::RenderDeferred | 0x8f74ec8 |
| FMobileSceneRenderer::RenderTranslucency | 0x8f77f20 |
| IsMobileSeparateTranslucencyActive | 0x8f6fbac |
| AddMobileSeparateTranslucencyPass | 0x8f6fc28 |
| AddSeparateTranslucencyCompositionPass | 0x8fc12ac |
| AddMobilePostProcessingPasses | 0x8fc76d8 |
| AddMobileTonemapperPass | 0x9022b6c |
| AddTonemapPass | 0x9020fa0 |
| GetMobileFilmTonemapParameters | 0x901f4ac |
| GetTonemapperOutputDeviceParameters | 0x901f950 |
| FSceneRenderTargets::GetDesiredMobileSceneColorFormat | 0x908d048 |
| FSceneRenderTargets::AllocSceneColor | 0x908e1f4 |
| IsMobileHDR | 0xa3b6fc0 |
| IsMobileColorsRGB | 0xa3b70b4 |
| MobileBasePass::SetTranslucentRenderState | 0x8ecdb18 |
| FMobileBasePassMeshProcessor (ctor) | 0x8ecec9c |
| ShouldCacheShaderByPlatformAndOutputFormat | 0x8ed2474 |
| FMaterialResource::IsMobileSeparateTranslucencyEnabled | 0xa0f997c |
| GetPixelFormatString | 0x848b7c8 |
