# 实验报告：Spine 官方运行时基准渲染与 STS2 转换三处缺陷的定位与修复

- **日期**：2026-09-26（第四轮会话）
- **对象**：零「都市龙语」Chr_ling005（Spine 4.1.19 二进制骨骼，提取自 iguf 热更包）→ STS2（Godot 4.5.1 + spine-godot 4.2.43）皮肤 mod
- **起因**：用户在 STS2 内观察到三个问题——①手部网格扭曲（疑似还有进一步染色）；②头部大小异常；③要求"渲染一帧龙卡手游端的实际预览图"作为对照基准
- **结果**：三个问题全部根因定位并修复（两处在转换管线、一处在调校参数）；基准渲染器沉淀为可复用工具；期间产生过的两个错误结论已用对照实验推翻并撤回

---

## 1. 结论速览

| # | 问题 | 根因 | 修复 |
|---|---|---|---|
| 1 | 动画中段手部/武器剧烈撕裂 | `tune_for_sts2` 调速时**只缩放关键帧时间，没缩放贝塞尔控制点里的绝对时间**，控制点飘出段外 → 插值过冲 | walk 时同步缩放 `curve` 数组的第 0/2 分量（与 `delay`） |
| 2 | 头部/手部/枪比例异常（缩放越大越明显） | 骨架里有 **5 根 `noScale` 骨骼**（bone6=头、bone9=拇指+枪链、bone12=左手、bone43/46），不继承父级缩放；root×N 时它们保持原大小 | tune 时对这些骨骼的 setup scale 及其 scale 时间轴值同乘 N |
| 3 | 拇指/眉/眼/袖口的顶点雕型（deform）全部失效 | 解析模型里 deform 的附件引用是**字符串表引用**（官方 `readStringRef`），发射器误当"槽内附件索引"，越界后静默丢弃 | 按 `strings[ref-1]` 解析附件名 |
| — | 放大到 t=1.0 等相位仍见锯齿 | **原始数据本身的瞬态网格分离**（挥臂段刚性件间隙），官方 4.1.19 运行时渲染原版二进制同样如此 | 无需修；1:1 对照已证明与原版逐像素一致 |

**染色定论**：chr_ling005 骨骼数据所有 slot/attachment color 均为 (1,1,1,1)，数据层无任何染色参数。贴图观感以解码管线通道序修复后的解码为准（早期解包 PNG 红蓝反转，见 iguf热更包解包实验记录.md §6）。

---

## 2. 基准渲染器（可复用工具，render_work/）

用与骨骼**完全同版本**的官方 spine-ts 运行时（spine-webgl@4.1.19，STS2 侧用 4.2.43）在浏览器 WebGL 里直接渲染提取产物：

- `spine-webgl.js` / `spine-webgl-42.js`：npm IIFE 产物。注意 4.1 包是**扁平导出**（`spine.SceneRenderer`，无 `spine.webgl` 命名空间）；4.2 有 `spine.Physics` 枚举。
- `view2.html`（4.1 二进制）/ `view42.html`（4.1 二进制 + 4.2 JSON 双支持）：
  `python -m http.server 8477 --bind 127.0.0.1 --directory <项目根>`，浏览器开
  `/render_work/view42.html?atlas=<res://路径>.atlas&skel=<路径>.skel|.json[&anim=idle&t=1.0][&cx=&cy=&cz=][&w=&h=&log=0]`
  相机语义：可见世界宽度 = viewportWidth × zoom（zoom 应设为 目标世界宽/画布宽）。
- `probe.html`：骨骼/权重/附件诊断（FakeTexture 免贴图加载）；`dump41/42.html`：整骨架世界变换数值导出（对拍用）。
- 踩过的 API 坑（复现时必看）：
  - `TextureAtlas` 构造器不收 loader，须 `page.setTexture(new spine.GLTexture(gl, img))`；
  - 4.1 `skeleton.updateWorldTransform()` 无参，4.2 需传 `spine.Physics.update`；
  - 本自动化环境 `img.decode()` 会永久挂起，必须用 `onload/onerror`；
  - spine-ts 字段名：骨骼名在 `bone.data.name`，世界变换用矩阵 `a,b,c,d` 推导（`worldRotationX` 等属性在部分版本不存在）。

## 3. 数据侧结论（官方 4.1.19 运行时渲染原始二进制）

- chr_ling005：96 骨/45 槽/4 IK/16 动画（attack|block|entry|hit|idle|jump|onfoot|sit|sitloop|skill01_1..3|stand|tibu|win|winloop）/单 skin default；63 个附件 = 32 蒙皮网格 + 31 刚性；setup、stand、idle 全姿势渲染正确，**持枪手五指、袖口完全服帖**（基准图 `render_work/ling005_fight_{setup,idle,idle_hand}_gt.png`）。
- 数据层无染色（见 §1）；贴图观感以通道序修正后的解码为准（iguf 记录 §6）。
- 立绘 `s_plotdrawing_ling005` 存在 base/热更版本错位：基础包 data 引用区域 `beibao`，热更 atlas（双页 2048²）中没有该区域，官方运行时也无法加载。渲染立绘需先配平版本，暂缓。

## 4. 手部扭曲的定位过程（证据链）

1. **复现**：把已安装 mod 的 `ling.json`（我们的 4.2.43 转换产物）丢进官方 spine-ts 4.2.43 渲染 → **手部撕裂复现**。 → 问题在数据，排除 spine-godot/游戏侧。
2. **排除法**（全部实测）：蒙皮权重完整（mod JSON 中 32 个加权网格与原版一一对应，`zero_zuo_z` vertices=1398）；96 根骨骼顺序与原版完全一致（权重骨骼索引有效）；关键帧**时间×0.5 与数值逐帧零误差**；atlas 与原版除页名外逐字节一致。
3. **1:1 对照**（用户要求排除干扰）：无调校转换（speed=1、root 0.45 不动）→ 官方 4.2 渲染与官方 4.1 渲染原版**逐像素一致**（全身+手部特写）。 → 转换器本体忠实，问题只在调校。
4. **数值对拍锁定**：t=0 干净、t=1.0 撕裂 + 关键帧一致 → 插值段出错。检查 curve 数组发现控制点时间仍是原版刻度（如 bone24 段已缩到 [0,0.333] 但 cx2=0.444）。
5. **正向验证**：仅把 mod JSON 全部 curve 的时间分量 ×0.5（2643 处）→ 同一时刻渲染手部恢复干净。因果链闭环。

## 5. 三处缺陷的机制与修复

### 5.1 Bug A：调速未缩放曲线控制点（手部撕裂主因）

- 4.1 二进制的贝塞尔曲线存的是**绝对 (time, value) 控制点**（官方 `readTimeline1`：1 字节标记 + 4×f32，运行时 `setBezier` 用段端点归一化采样）。4.2 JSON 同样按绝对值解释（`readCurve`→`setBezier`）。
- `tune_for_sts2` 的 walk 只除 `'time'` 键 → 关键帧时间减半而控制点时间不减 → cx 落在段外 → 采样过冲。旋转幅度越大越明显（手指 ±40° 摆动最惨），且**恰在关键帧上时数值正确**（所以 t=0 干净），极具迷惑性。
- 修复：walk 遇到 `curve`（4 元素数值列表）时把第 0/2 分量同除 speed；顺带 `delay` 键也缩放。

### 5.2 Bug B：deform 附件引用解析错误（雕型全丢）

- 官方 4.1 二进制 deform 段：`skins[i] → slotIndex → readStringRef()` —— 附件引用是**字符串表引用**。
- 我们的解析器把该 varint 存成 `att_ref`，发射器误当"槽内附件列表 1-based 索引"；本骨架槽内附件普遍只有 1 个而 ref 值为 19/35/36/56 → 全部越界 → `continue` 静默丢弃。idle 的 4 条 deform（右袖口、眉、**拇指**、眼）全灭；block 里"侥幸在界内"的还解析到了错误附件名。
- 修复：`att_name = sk['_strings'][att_ref-1]`，并校验名字在槽附件里存在。修复后 16 个动画全部 deform 正确恢复（拇指雕型、眨眼、嘴形等都回来了）。

### 5.3 Bug C：noScale 骨骼未补偿（头/手/枪比例异常）

- 骨架含 5 根 `inherit=noScale` 骨骼：bone6（头皮/头）、bone9（拇指+**枪** qiang02 挂在其下）、bone12（左手）、bone43/46。它们不继承父级缩放，setup scale（0.24~0.31）是美术为配合 root=0.45 手调的。
- root×N 调校时它们保持原大小：×2 构建头身比只有应有值的一半（用户此前"头部大小异常"的直接原因），×3 构建同样。枪挂 bone9 下所以枪也不跟缩放。
- 修复：tune 时对这 5 根骨骼的 setup scale 同乘 N（子骨骼随其世界变换自然跟上）；sit/sitloop 里 bone12 的 2 帧 scale 动画值也乘 N。定量验证：96/96 骨骼世界缩放 = 精确 3×（对拍 dump42）。

### 5.4 原始数据的固有特性（不是 bug）

idle/挥臂动画中段（如 t=1.0），手部各刚性件（袖口、手套、手指）之间出现瞬态分离/重叠，放大单帧看是锯齿碎片。**官方 4.1.19 渲染原版二进制同样如此**（1:1 对照逐像素一致），连续播放时是快速挥动的正常形态。不需要也无法在转换层修复。

## 6. 曾产生并已撤回的错误结论（防再次踩坑）

1. **"转换管线把权重全部剥掉（32→0）"** —— 错误。测量方法错了：Spine JSON 的蒙皮数据就存在 `vertices` 字段里（加权形态=超长数组 [boneCount,(idx,x,y,w)...]），**没有独立的 `weights` 键**；用 `"weights" in att` 判定必然全 0。改用 `len(vertices) vs len(uvs)` 重新测量后确认 32 个加权网格完整保留。教训：**判定字段形态前先看目标格式的真实定义**。
2. **"让 spine-godot 直接加载 4.1 .skel 以保权重"** —— 错误方向。spine-godot 4.2.43 的 checkVersion 要求版本串以 "4.2" 开头（已在 §9.2 用二进制串证据确认），4.1 二进制会被直接拒绝；且权重本来就 retention 完好，无需绕道。
3. 更早会话的"纸醉金迷=苏恩熙皮肤"、"零的皮肤=王之权座/参孙/刀光撕裂…"等名称归属，均已在 `iguf热更包解包实验记录.md` §8-§9 撤回并更正。

## 7. 新构建参数与交付物（2026-09-26 用户定版）

- **调校定版：speed=1.0（时间 1:1 原速）+ root_scale_mult=3.0（root 0.45→1.35，含 noScale 补偿）**。
- 产物：`sts2_work/LingUrbanSkin_mod/_pcksrc/ling/animations/characters/silent/ling.json`（同步更新 `.godot/imported/ling.json-*.spjson` —— **游戏实际加载的是这个导入产物，只改源 json 不改 spjson 等于白改**）→ 重打 `LingUrbanSkin_mod/LingUrbanSkin/LingUrbanSkin.pck`（10 文件，1,595,091 B，MD5 逐条校验 10/10）。
- 安装：把 `LingUrbanSkin_mod/LingUrbanSkin/` 覆盖到 `Slay the Spire 2/Mods/LingUrbanSkin/`，游戏内启用即可。
- 若仍需调速：修好的 `tune_for_sts2(speed, root_scale_mult)` 现在会同步处理曲线时间与 noScale 补偿，可任意组合。

## 8. 立绘与版本错位备忘

`SPD_Ling005` 立绘 data（基础包）引用区域 `beibao`，热更 atlas 无此区域，两条数据版本不配平就无法渲染立绘。若需要立绘基准，应从基础包把配套的旧 atlas 一并提取（或从热更把新版 data 找齐）后再渲染。

## 9. 默认皮肤 mod 重制（chr_ling001，2026-09-26 第二次定版）

按用户定版参数重制 `LingSilentSkin_mod`（零默认皮肤 → 静默猎手）：

- **根缩放：绝对值 1.0**（原始 root scaleX=0.45，即等效 ×2.2222；5 个 noScale 骨骼 bone6/9/12/43/46 同步补偿 setup 与 scale 时间线，96/100 关键骨世界缩放验证一致）。
- **动画时间：仅战斗类对齐，待机类保持原速**。对齐基准 = 用户指定的参考 mod「小银龙奥卡-雾锻婚纱」（替换铁甲战士）：
  - 奥卡战斗骨架（`.godot/imported/ironclad.skel-8e96930d….spskel`，源路径 md5 法实证 = 游戏实际加载件）的 **8 条动画全部为 2.6667 s**（作者统一时长，纯资产 mod 游戏内正常）。
  - 据此把零的 attack/cast/skill01_2/skill01_3/hurt 五条拉伸到 2.6667 s（时间因子分别为 ×2、×3.2、×2、×2、×4，含 bezier 控制点时间同步缩放）；idle_loop/stand/win/winloop/entry/sit/sitloop/onfoot/tibu/block/jump 保持原速。block/jump 无奥卡对应项且 Silent 本体无 block 动画，不动。
  - 旧 mod 当年是对**全部**动画统一 ×2（含待机），即 1:1 测量反推的实证（orig/oldmod 时长比 17 条全部 ≈0.500），本次按新指令只对齐战斗类。
- **deform 全量恢复**：chr_ling001 的 16 条动画共 **319 个 deform 帧**（旧 mod 因 strings-ref 解析 bug 为 0）。白裙/长发/袖摆的网格形变这次全部生效。
- **贴图（终局）**：默认皮肤 mod 贴图 = 通道序修复后的 chr_ling001 解码（实机捕获纹理与 chr_ling001.uexp 载荷逐字节相同；手游观感=贴图直出+光照，游戏内无运行时染色）。现行 LingSilentSkin 贴图来自 `render_work/battle_capture/captured_tex827.png`（`tools/build_battle_pck.py`）；早期对 lanse/lanseh/qiang/yanjing/tsdahua 等区域做 HSV +168° 旋转烘焙的方案（v0.2）是对红蓝反转伪象的近似补偿，已废弃。
- **导入产物 md5 命名规律（实证）**：spine 产物（.spjson/.spatlas）用**不带 `res://`** 的源路径 md5，纹理 `.ctex` 用**带 `res://`** 的源路径 md5。
- **UE4 逆向进展（材质本体）**：M_UI_TEST_Inst 的 uasset/uexp 已从 iguf 卷按单元格式切出（免遍历方案：全卷枚举 `[58af5a00]` 前缀→独立试解压）；父材质 UI_SpineHoloDistorMaterial（参数 MixColor/DarkenRatio/ScanLine{Color,Opacity,Scale,Speed,Width}/Distor{Time,UOffset}）；引用它的 WBP=`View_Appearance_Fight_Spine_Hologram`（试衣间战斗 Spine 全息预览滤镜）。参数真值见 iguf 记录 §12.2；该材质仅挂调试外观与试衣间预览，正式战斗路径=BP 的 MySpineLitNormalMaterialV2+贴图直出（iguf 记录 §12.9）。
- **mask 再解释**：chr_ling001_mask 的 r 与 alpha 在全身不透明像素上均近满值（86–91%），并非染色区域选择器；g/b 为效果梯度坐标。mask 通道服务流光/脉冲类效果（iguf 记录 §12.5）。
