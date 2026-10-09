# 龙卡战斗场景 UE4 特效 → 杀戮尖塔2 (Godot) 移植分析

> 生成：2026-10-10 ｜ 依据：项目状态交接.md + 光影层移植计划.md（条目 1-29）+ dragonraja2 研究库属性转储实测复核
> 铁律不变：渲染参数只从 源码 / 资产(uasset·uexp·GLSL) / 运行时 hook 三链路取值，禁止截图反解。

## 0. 结论先行

龙卡战斗场景的特效栈共 **9 大类**。截至本日：**6 类已移植生效，1 类已实现但被用户关闭，2 类未移植**。

| # | 特效 | UE4 侧载体 | STS2 侧现状 |
|---|---|---|---|
| 1 | 角色本体渲染 | Spine 广告牌 + UE4 移动端 lit 半透明管线 | ✅ p215 移植直出（w_scale=0），四族 ling_holo 材质 |
| 2 | RT 实时影子 | RTGlobalShadowActor + SceneCapture2D 投影 | ✅ ShadowSilhouette 骨骼剪影 + 斜二测仿射（条目 19 源码全解定案） |
| 3 | 死亡溶解 | MySpineLitDissolutionMaterial，Rongjie 1.2→0 @0.5s | ✅ ling_dissolve_mix.gdshader（噪声阈值 discard+边缘亮带，公式已逐行解码） |
| 4 | 死亡粒子 | fx_die（Zhu 发射器，峰值 51 粒） | ⚠️ CPUParticles2D 近似已实现，**用户不满意已关**（config fx.enabled=false，代码保留） |
| 5 | 受击闪红 | 组件 Color 驱动，loc7 实测 (0.9216,0.0319,0.0762) | ✅ flash_gain 事件驱动（Creature.CurrentHpChanged→PlayerHit） |
| 6 | 攻击粒子 | fx_ling_attack_01 / _01_hit | ✅ CPUParticles2D 双爆发 + SlashImpactWatcher 命中归因（斩击节点释放即爆） |
| 7 | 镜像材质 | MySpineUnlitHitMaterial darkenParam=0 → 全程反相负片 | ✅ ling_mirror_*.gdshader 严格公式（条目 26 定案） |
| 8 | **技能期光照编排** | 双点光 MPC + DarkenMPC 压暗 + 高度雾 | ❌ **uniform 层就位但事件驱动未做**（路线图明确待办） |
| 9 | **技能特效家族** | fx_ling_skill01_{front,backimage,buff_eye,buff_tongjing,hit} | ❌ **完全未移植**（本次复核确认的缺口） |

## 1. 逐类证据与移植映射

### 1.1 角色本体（已定案）
- UE4：Spine 骨骼作 3D 场景中的广告牌；移动端 lit 半透明管线（u066941 逐行解码，`render_work/mirror_shaders/` 19 份 GLSL）。
- STS2：`ling_holo_material_{mix,add,mul,sub}.tres`，直出模式（pipeline_encode 默认 0=维持用户已认可的原始直出观感）。

### 1.2 RT 影子（已定版）
- UE4 源码链路：battlefield.lua:203-283 `InitMapRTShadowSettings`；`RTGlobalShadowMat` 编译 FS（tools/extract_rtshadow_shader.py 挖出 4 唯一 shader）：`uv=世界坐标·投影矩阵4行→透视除法→采样RT`，`alpha=clamp(ceil(r+g+b))×ShadowOpacity` = **二值硬边纯黑剪影**。
- STS2：共享 SkeletonDataResource 第二 SpineSprite 实例 + 斜二测仿射（oblique_deg=45/len_scale=0.35/opacity=0.6），地面=节点 Y+ground_offset_y（DRC"地面是场景几何"哲学的 2D 直译）。长跑 OOM 教训已入档：高频循环禁调返回非平凡 Variant 的原生方法。

### 1.3 死亡溶解（已定版）
- UE4：`myspinelitdissolutionmaterial.uexp` shader map=22 哈希双拷贝（uexp@0x3d98），移动端 lit 变体 68642e51 逐行解码：世界坐标投影噪声（pc5_h[1] 缩放）、阈值 pc5_h[2].z、`ceil((noise+off−T)·(noise+off−1))` 双门+discard、边缘=mix(→liangbian_color)；常量 DieDuration=0.5/DieRongJieStart=1.2（fightconsts.lua:131-133）。
- STS2：ling_dissolve_mix.gdshader + DeathWatcher（Creature.Died→die 开播检测→换材质→tween 2.05s→影子同步渐隐）。

### 1.4 死亡粒子（近似实现，用户关闭中）
- UE4 真值：`res_effects/particles/scene_fx/common/fx_die`（发射器 Zhu：球域生成、峰值 51 粒、辉光/烟雾/丝带 6 材质、SubUV）。
- STS2：CPUParticles2D 全域慢飘版已迭代 10+ 轮（body_size 骨架边界锚定、60fps 尺寸跟随、飞行时间模型），观感仍不合意 → config fx.enabled=false。**全参数发射器级移植列为可选精修**。

### 1.5 光照滤镜（剩余项 A：事件编排）
- UE4 真值（iguf 记录 §12.2/§12.7 已入库）：技能期橙灯 `(12.29,−0.218,0)` 强度 238 由 pointlightctrlactionhandlerimpl.lua 写入；DarkenMPC 运行时 `(Near=1000,Far=10000,MaxDarkenAlpha=0.5)`；TEXCOORD7=指数高度雾+环境加色；全画面压暗 pc0_h[6].x。
- STS2 现状：ling_holo 四变体已带全 uniform（point/ambient/fog/darken/flash，默认全关=直出不变），**缺的只是 C# 事件驱动**：挂 STS2 战斗事件（出牌/技能演出/Boss 出场）→ lerp 过渡喂 uniform。移植哲学=只对齐效果语义不对齐触发时机（手游技能时序≠STS2 出牌时序）。

### 1.6 技能特效家族（剩余项 B，本次复核确认的完整缺口）
属性转储实测（dragonraja2/unpacked/reversed/properties/res_effects/particles/hero/ling/）：

| FX | 发射器数 | 关键资产 |
|---|---|---|
| fx_ling_skill01_front | 3 | Mi_Ling_Skill 材质、fr_glow_903_3x3、T_glow_606_Nomip、ma_412_UV；模块含 Orbit/SubUV/CameraOffset |
| fx_ling_skill01_backimage | 3 | 背景镜像层 |
| fx_ling_skill01_buff_eye | 4 | 眼部 buff 特效 |
| fx_ling_skill01_buff_tongjing | 5 | **瞳镜**（ma_412_UV/ob/tr 三纹理=遮罩+物+拖尾） |
| fx_ling_skill01_hit | **24** | 技能命中大特效（7205 行属性） |

- 触发映射建议：cast 动画（skill01_1@3×+skill01_3@2× 拼接，条目 4 定案）→ 复用 AttackFxWatcher 的轮询模式（anims=["cast"]）；front/backimage 挂角色前后层（ZIndex 前后），buff_tongjing/eye 挂 find_bone 槽位；hit 可走 SlashImpactWatcher 斩击归因。
- 材质链：Mi_Ling_Skill 等 MI 参数走 ue4_dump.py 转储取真值（禁猜）；纹理经 iguf_extract_asset 提取（基础包走 azpack_extract_one）。

## 2. Cascade→Godot 粒子移植语义对照表（已验证方法论）

| UE4 Cascade | Godot CPUParticles2D 等价 | 状态 |
|---|---|---|
| Spawn burst 表 | OneShot+Explosiveness / 分时二次 Fire | ✅ 攻击特效已用 |
| 球面初速 r | 球形 EmissionShape+初速区间 | ✅ |
| AccelerationDrag(指数拖拽) | Damping（×40-60 经验换算已验证） | ✅ |
| SubUV 随机帧 | h_frames/v_frames 原生属性+AnimOffset 0..1 随机；或逐帧裁切纹理（根治全屏爆闪的方案②） | ✅ 两条路都验证过 |
| Velocity aligned 光条 | 程序生成软光束纹理+particle_flag_align_y | ✅ |
| Color/Size over life | ColorRamp/scale_amount_curve | ✅ |
| Orbit / CameraOffset | Godot 无直接等价 → 局部空间发射+切向加速度近似；CameraOffset 在 2D 中无意义可弃 | ⏳ skill01 需要时做 |
| 速度对齐(PSA_Velocity) | 光条纹理沿速度方向拉伸 | ✅ |

## 3. 建议执行顺序

1. **A 光照事件编排**（阶段 2 收尾，工作量最小、复用度最高）：LightState 挂 `CardPlayed`（技能牌→橙灯淡入淡出）/ `TurnStarted`（恢复）/ Boss 出场（压暗 darken_alpha→0.5）。全部 uniform 已在 shader 里，只写 C# 编排 + config 段。
2. **B skill01_front/backimage/tongjing/eye**（技能观感大头，中等工作量）：解码 4 个 FX 属性转储→纹理提取→CPUParticles2D/着色面片移植→cast 挂钩。
3. **C skill01_hit**（24 发射器，工作量最大）：建议按 hit 特效通用近似路线（球爆+闪光面片+冲击环，同 fx_ling_attack_01_hit 已验证的三件套），标注差异，不做逐发射器忠实复刻。
4. **D fx_die 全参数精修**（可选，用户已关）：等用户对死亡观感有新要求再启动。

## 4. 约束提醒（执行时必守）

- 两 mod 去污染：skill01 特效纹理/材质全部进 **LingChar.pck 自有路径**（effects/ling_skill/ 之类），不得与 LingSilentSkin.pck 产生共享路径。
- 改构建脚本后必跑 `python D:\项目\dragonraja\_migration\toolchain_check.py`（FAIL=0）。
- 纹理提取：热更走 `tools/iguf_extract_asset.py`，基础包走 `tools/azpack_extract_one.py`（条目名反斜杠归一）。
- 参数取值：发射器参数从属性转储（ue4_dump.py）与材质 MI 转储读取；本报告未标注"实测/转储"字样的数值一律不许直接写进代码。
