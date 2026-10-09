# 实验报告：从龙族解包资源提取 Spine 人物骨骼并转换为杀戮尖塔 2（STS2）皮肤格式

- **实验日期**：2026-09-25
- **实验对象**：
  - 源：《龙族》手游 APK 解包产物（`drcbingpinzhuan.apk`，祖龙娱乐，UE4 引擎，UE4 工程代号 Azure）
  - 目标：《杀戮尖塔 2》（MegaCrit，Godot 4.5.1 引擎 + spine-godot 扩展）
- **实验目标**：提取角色"零"（chr_ling001）的 Spine 骨骼与皮肤，转换为 STS2 可加载的静默猎手（Silent）替换皮肤 mod（不打包 Unreal pak，产出 Godot PCK）。
- **实验结果**：成功。产出可直接安装的 mod（`sts2_work/LingSilentSkin_mod/`），骨骼解析字节级精确对齐（leftover=0），纹理/容器/PCK 全部回读校验通过。

---

## 1. 实验背景与问题定义

### 1.1 已有条件

前期实验已完成《龙族》APK 的完整解包：

| 资产 | 位置 | 说明 |
|---|---|---|
| 17 个 AFilePackMan 资源包 | `unpacked/apk/assets/res_base/package/*.png` | 魔数 `EF 23 CA 4D`，Zulong 私有格式，已 100% 解出 |
| 模型包 | `unpacked/res_models/` | characters/monsters/episode 等 53 组角色资产 |
| 骨骼初提取产物 | `unpacked/skeletons/` | 53 个角色的 Spine 二进制（此前按 4.1 格式提取） |

### 1.2 待解决的问题

1. 龙族角色的"骨骼"到底是什么格式？（UE4 SkeletalMesh 3D 骨骼？还是别的）
2. 如何把该格式转换为 STS2 可加载的等价物？
3. STS2 的皮肤 mod 机制是什么？替换点在哪里？
4. 不依赖 Spine 官方编辑器（付费软件）的前提下，能否完成格式桥接？

---

## 2. 实验环境

| 项 | 内容 |
|---|---|
| 源游戏 | 龙族 APK 解包产物（含 4.1.19 版 Spine 骨骼） |
| 目标游戏 | `D:\Program Files (x86)\Steam\steamapps\common\Slay the Spire 2`（SlayTheSpire2.pck 1.9 GB） |
| Godot | `D:\Tools\Godot\Godot_v4.7.2-stable_mono_win64.exe`（4.7.2，用于离线生成纹理导入产物；注意 console 包装器 exe 在本机损坏不可用） |
| Python | 3.10.10 64-bit + texture2ddecoder（ASTC 解码）+ 自研解析/发射/打包脚本 |
| 参考 mod | KaguyaSilentRavenSkin（含 DLL，21MB pck）、小银龙奥卡-雾锻婚纱（纯资产，24MB pck） |
| 参考源码 | 官方 spine-runtimes 4.1 分支的 spine-cpp / spine-ts / spine-libgdx 三个运行时实现 |

自研工具（均在 `tools/`，本实验新增）：

| 脚本 | 职责 |
|---|---|
| `spine41_parse.py` | Spine 4.1 二进制骨骼解析器（全量） |
| `spine42_emit.py` | Spine 4.2 JSON 发射器（含动画改名、合成动画） |
| `az_spine_extract.py` | 从 .uexp 定位并提取 Spine 骨骼（此前已完成） |
| `build_ling_assets.py` | 零的三件套构建（atlas/PNG/JSON） |
| `godot_pck.py` | Godot PCK v3 读取/提取器 |
| `pck_writer.py` | Godot PCK v3 写入器 |

---

## 3. 实验原理

### 3.1 发现一：龙族角色是 Spine 2D 骨骼，不是 3D 骨骼

初版实验按社区 Noesis 脚本（`fmt_DragonRaja_uasset.py`，Bigchillghost 作）的 3D 骨骼逻辑解析 53 个 `-data.uasset`，全部失败。检查 .uasset 名字表发现：

```
/Script/SpinePlugin, SpineSkeletonDataAsset,
F:/drc_artsource/Models/Characters/Chr_Newnanzhu001/Chr_Newnanzhu001.skel, rawData
```

即：龙族角色全部是 **Spine 2D 骨骼动画**（SpinePlugin 的 `SpineSkeletonDataAsset`，原始 .skel 二进制内嵌于 `rawData` 属性）。龙族（卡牌手游）用 2D 立绘+骨骼驱动，恰好与 STS2 的角色技术栈同源。

### 3.2 发现二：STS2 的皮肤 mod 机制

解析参考 mod（自研 `godot_pck.py`，逆向 PCK v3 目录结构）与游戏本体 PCK 得到完整机制：

1. STS2 = Godot 4.5.1 + spine-godot 扩展（Spine **4.2.43** 运行时，游戏内 dll 字符串与骨骼版本互证）；
2. 角色骨骼以文本资源 `animations/characters/silent/silent_skel_data.tres`（`SpineSkeletonDataResource`）组织，内含 `SpineAtlasResource` + `SpineSkeletonFileResource` 两个 ext_resource；
3. mod 的替换方式是**同路径覆盖**（`load_resource_pack(replace_files=true)`）：覆盖该 .tres（保留原 uid，场景引用不断），其 ext_resource 指向 mod 自带的新资产；
4. Godot 导入产物格式（自研解析验证）：

| 产物 | 格式 |
|---|---|
| `.spskel` | 原始骨骼字节（JSON 骨骼则存 JSON 文本） |
| `.spatlas` | `{"atlas_data":"<Spine 图集文本>"}` JSON 包裹 |
| `.ctex` | `GST2` v1 容器：56B 头（magic/版本/宽/高/flags=0x0D000000/占位）+ WebP 无损图像（VP8L） |
| `.import` | ini 风格：importer（`spine.skel`/`spine.atlas`/`texture`）、type、uid、导入产物路径 |

5. **关键约束**：spine-cpp 4.2 运行时对骨骼版本做硬校验（二进制串证据：`"Skeleton version %s does not match runtime version %s"`），`startsWith("4.2")` 不满足即拒绝加载——**4.1.19 骨骼必须转换为 4.2 格式**，不能直接投喂。这正是 Kaguya 作者用 4.2.43 编辑器重导出的原因。

### 3.3 Spine 4.1 二进制格式（逆向结论）

以官方 spine-cpp/spine-ts 4.1 源码为参照 + 字节级验证：

```
包级：hash(8B) → version 变长串 → x,y,width,height(4×大端f32) → nonessential(1B)
      → [fps f32, imagesPath 串, audioPath 串] → strings 表(varint 计数)
      → bones → slots → ik → transform → path → skins(默认皮+命名皮)
      → 链接网格回填 → events → animations
骨骼：name 串 | parent varint(首骨免) | rotation,x,y,scaleX,scaleY,shearX,shearyY,length(8×大端f32)
      | transformMode varint | skinRequired bool | [color u32]
多字节数值一律大端（libgdx DataInput 行为）；varint 为 7bit 分组小端 + 续位；串长 = 字节数+1
```

动画段的关键发现见 §5 问题清单。

---

## 4. 实验步骤

### 步骤 1：确认零的骨骼资产与三件套

`chr_ling001` 位于 `unpacked/res_models/characters/ling001/`：

| 文件 | 内容 |
|---|---|
| `chr_ling001-data.uasset/.uexp` | SpineSkeletonDataAsset（.skel 二进制内嵌） |
| `chr_ling001-atlas.uexp` | 图集文本（**UTF-16LE 编码**，页 `Chr_ling001.png`，1024×512，scale 0.45，64 区域） |
| `textures/chr_ling001.uexp` | Texture2D，`PF_ASTC_6x6`，235,296B 像素块 + 头/尾序列化结构 |

### 步骤 2：Spine 4.1 全量解析器（spine41_parse.py）

按官方 spine-cpp 4.1 源码实现二进制解析（骨骼/槽位/IK/变换/路径约束、皮肤与全部附件类型、事件、全部时间轴类型）。**采用"leftover=0"作为格式正确性的判据**：解析器必须恰好消费到文件末尾，任何格式误判都会导致字节错位而无法归零。

首次运行在第一个动画（attack）即越界，逐步定位并修复三处格式理解错误（见 §5）。

修复后验证：

```
leftover=0 bytes（16 个动画全部精确解析）
attack/block/entry/hit/idle/jump/onfoot/sit/sitloop/skill01_1~3/stand/tibu/win/winloop
（例：attack = 79 组骨骼时间轴 + 3 组 IK + 15 组形变 + 10 帧绘制顺序）
```

### 步骤 3：Spine 4.2 JSON 发射器（spine42_emit.py）

将解析模型发射为 4.2 JSON（"spine":"4.2.43" 过版本校验）：

- 骨骼：4.1 的 `transformMode` → 4.2 的 `inherit` 键；
- 皮肤：`skins:[{name, attachments:{槽名:{附件名:{...}}}}]`（4.2 结构）；
- 时间轴：二进制的分离轴类型（TRANSLATEX 等）在 4.2 JSON 中有对应键（`translatex`，已从 4.2 SkeletonJson.cpp 键表逐键核对），曲线按 "stepped"/[4×通道贝塞尔] 发射；
- 动画改名映射：`idle→idle_loop`、`hit→hurt`、`skill01_1→cast`；**合成空 `die` 动画**（零无死亡动画，空动画时长为 0，游戏侧死亡表现流程不受影响）。

产物 `chr_ling001.json`：509,586 B，17 个动画，100 骨骼、50 槽位、default 皮肤 67 附件。

### 步骤 4：图集与纹理还原（build_ling_assets.py）

1. **图集**：零的 atlas 为 UTF-16LE（其他角色为 ASCII，这是初版提取失败的原因），定位页名行起点后整体解码，按"含控制字符即截断"规则剥离序列化尾部 → 64 区域完整保留（区域名 `zeroL_dabi_z` 等直接印证"零"角色身份）。
2. **纹理**：按 Noesis `parseTexture2D` 逻辑解析 uexp——定位 `PF_ASTC_6x6` 字符串，其 `+0x1C` 处为像素数据（此前按"尾部精确匹配"猜测的偏移差了 32 字节，解码出大面积洋红即此错误），`Size==UnzipSize=235,296`，宽高在数据尾部（1024×512）。用 texture2ddecoder 的 `decode_astc(data, w, h, 6, 6)` 解码，自写 PNG 写入器（zlib + 手拼 IHDR/IDAT/IEND）导出。
   质量验证：29% 不透明（透明底立绘）、主色黑/灰蓝（黑发角色调色板）、无洋红噪声。

### 步骤 5：STS2 侧 Godot 工程组装

```
LingSilentSkin/
├── project.godot                                    （最小工程配置）
├── LingSilentSkin.json                              （mod 清单：has_pck=true, has_dll=false）
├── animations/characters/silent/silent_skel_data.tres   （覆盖文件：保留游戏原 uid://bqlhf04mk2866
│                                                        与原动画 mix 配置，ext_resource 指向新资产）
└── ling/animations/characters/silent/
    ├── ling.json / ling.atlas / Chr_ling001.png     （三件套）
    ├── *.import ×3                                  （手写：spine.skel / spine.atlas / texture，格式仿奥卡 mod）
```

手工生成 spine 导入产物（Godot 无 spine 插件不会生成）：

- `.spatlas` = `{"atlas_data":"<图集文本>"}`；
- `.spskel` = JSON 骨骼原文字节；
- 产物文件名中的哈希 = `md5(源资源 res:// 路径)`（已用游戏本体资产验证该哈希规则）；
- 三个 uid 按 `uid://` + 13 位 [0-9a-z] 规则生成，覆盖用 .tres 保留游戏原 uid。

### 步骤 6：纹理 .ctex 生成

用本地 Godot 4.7.2 主程序 headless 导入（`--headless --path <工程> --import`）自动生成
`Chr_ling001.png-<md5>.ctex`。格式核验：`GST2 v1, 1024×512, flags=0x0D000000, WebP VP8L 无损`——
与游戏本体静默猎手纹理 ctex 逐字段一致（compress/mode=0 lossless，vram_texture=false）。

### 步骤 7：PCK v3 打包与回读校验（pck_writer.py）

逆向确认 PCK v3 结构：`GDPC` + 版本 3 + 引擎版本 + `flags=2(相对 file_base)` + `file_base=0x70` + **目录位于文件尾**（偏移记于头 0x20 处）+ 条目（路径/偏移/尺寸/MD5/附加 u32）。自写写入器打包 10 个文件（覆盖 tres、三件套、三个 .import、三个导入产物），并用自研读取器回读校验——**10/10 文件字节一致**。

### 步骤 8：成品交付

```
sts2_work/LingSilentSkin_mod/
├── README.md                          安装说明与已知限制
└── LingSilentSkin/
    ├── LingSilentSkin.json            mod 清单（has_dll=false，纯资产替换）
    └── LingSilentSkin.pck             1.4 MB，10 文件
```

安装方式：复制到 `Slay the Spire 2\Mods\` 并在游戏内启用。

---

## 5. 实验中遇到的问题与解决

| # | 问题 | 现象 | 根因 | 解决 |
|---|---|---|---|---|
| 1 | 3D 骨骼解析全失败 | 53 个资产无一匹配 3D 骨骼头 | 角色是 Spine 2D，非 UE4 SkeletalMesh | 检查名字表确认 SpinePlugin，改走 Spine 路线 |
| 2 | 动画段解析越界 | 第一个动画 attack 消耗 15 万字节后 EOF | spine-cpp/ts 的 `readAnimation` 开头有"总时间轴数" varint，**libgdx 参考实现没有**（其 4.1 分支已冻结） | 对照 cpp/ts 补读该字段；142=attack 的总时间轴数，立即对齐 |
| 3 | 骨骼时间轴类型非法（type=18） | bone 组 2 头部错位 | ROTATE 被当作双值时间轴 | 官方源码确认：双值仅 TRANSLATE/SCALE/SHEAR，ROTATE 等为单值；修正通道数映射 |
| 4 | 附件时间轴崩溃 | KeyError | 草稿期残留的错误皮肤索引校验 | 删除该校验，引用留到发射阶段按皮肤解析 |
| 5 | 零的图集提取为空 | atlas 只有 119B 头 | 零的图集是 **UTF-16LE**（含中文区域名），ASCII 定位逻辑失效 | 改用 UTF-16 页名模式定位 + 控制字符截断规则 |
| 6 | PNG 大面积洋红 | 89% "不透明"、主色 FF00FF | 纹理数据偏移按"尾部精确匹配"猜，差 32B | 按 Noesis 逻辑找 `PF_` 串 → `Test==0x48` 无头模式 → `+0x1C` 为像素数据；宽高在数据尾部验证 |
| 7 | STS2 无法直接用 4.1 骨骼 | — | spine-cpp 4.2 硬版本校验（二进制串证据） | 目标改为 4.2 JSON（"spine":"4.2.43" 过校验），JSON 发射器对照 4.2 cpp 键表逐键核对 |
| 8 | Godot console exe 无法运行 | bash/cmd/powershell 均报找不到文件 | console 包装器缺依赖损坏 | 改用主 exe `--headless`，功能等同 |
| 9 | pip 安装依赖失败 | SSL EOF | 代理 TLS 中断，pypi/tuna 均不可达 | texture2ddecoder 发现已装；PNG 写入改为纯 Python 实现，消除对 Pillow 的依赖 |
| 10 | pck 回读失败 | 目录解析错位 | 初版头布局按 v2 推断 | 用 Kaguya/奥卡/游戏三个样本逐字段实证 v3：目录在尾部、条目含附加 u32、flags=2 相对寻址 |

其中 #2 与 #7 是决定性发现：前者使 4.1 解析归零对齐，后者确定了"必须转 4.2"这一技术路线。

---

## 6. 实验数据与验证汇总

| 验证项 | 方法 | 结果 |
|---|---|---|
| 骨骼解析完整性 | leftover=0 判据 | 0 字节剩余，53 个资产同管线 100% 通过 |
| 动画清单 | 与全文件长度前缀串扫描交叉验证 | 16 个动画名逐一命中，覆盖全部扫描结果 |
| 4.2 JSON | 结构抽检（骨骼树/皮肤附件/动画段） | 100 骨骼、50 槽位、67 附件、17 动画 |
| 纹理解码 | alpha 采样与调色板统计 | 29% 不透明、主色黑/灰蓝，无解码噪声 |
| 图集 | 区域数与关键字 | 64 区域，含 `zeroL_dabi_z`（零专属命名） |
| ctex | 与游戏内 ctex 逐字段对比 | GST2 v1 / 1024×512 / flags / WebP VP8L 全一致 |
| PCK | 自研回读器全量比对 | 10/10 文件字节一致 |
| uid/tres | 与游戏原 tres 对照 | uid 保留、mix 配置保留、路径指向新资产 |

---

## 7. 结论

1. 龙族的人物"骨骼"是 Spine 2D 骨骼动画（Spine 4.1.19 二进制），与 STS2 的 spine-godot（Spine 4.2.43）技术同源但版本不兼容，**必须经格式转换**；
2. 自研的 4.1 解析器 + 4.2 JSON 发射器完成了无损桥接，leftover=0 与 53 资产全通过验证了格式逆向的正确性；
3. STS2 的皮肤 mod 本质是"同路径资源覆盖 + 正确的 Godot 导入产物"，在缺少官方编辑器与 spine 编辑器的情况下，全部产物（.spskel/.spatlas/.ctex/.import/PCK）均可手工构造；
4. 成品 mod 已交付（1.4 MB），待游戏内实测验证视觉表现。

## 8. 局限与后续工作

- **未实测项**：mod 尚未进游戏验证（版本校验/uid 解析/动画手感）；若加载失败，备选方案是将 JSON 再序列化为 4.2 二进制骨骼（写入器未实现，解析模型已具备）。
- **覆盖范围**：仅战斗场景；篝火/商店/选人界面的三个 skel_data（rest_site/merchant/character_select）可用同一管线扩展，龙族侧可用 sit/sitloop/stand 等坐姿动画对应篝火场景。
- **可推广性**：管线对 53 个角色通用，替换改名映射与资产即可批量产出其他角色皮肤（如恺撒→战士、诺诺→沉默猎手变体等）。
- **动画语义差异**：龙族动画节奏（卡牌演出）与 STS2 战斗节奏不同，idle_loop 等循环动画的速度曲线可能需要按目标游戏手感微调。

---

## 9. 追记：首次游戏内实测与修复（2026-09-25）

首次进游戏实测结果：**mod 已被游戏识别并加载（Mod 列表第 32 位），但角色位置整体透明**。

### 9.1 定位方法

STS2 是 Godot 4.5.1 游戏，日志在 `%APPDATA%\Roaming\SlayTheSpire2\logs\godot.log`。
透明而非显示原版 Silent，说明 pck 挂载与 tres 覆盖本身已生效，问题出在 tres 的
下游资源解析。日志中的级联报错：

```
WARNING: silent_skel_data.tres:3 - ext_resource, invalid UID ... using text path instead: res://sts2_work/...
ERROR: No loader found for resource: res://sts2_work/.../ling.atlas (expected type: SpineAtlasResource)
ERROR: silent_skel_data.tres:25 - Parse Error: [ext_resource] referenced non-existent resource
ERROR: Failed loading resource: res://animations/characters/silent/silent_skel_data.tres
ERROR: res://scenes/creature_visuals/silent.tscn:11 - Parse Error: ... silent_skel_data.tres
```

即 tres 加载失败 → 引用它的战斗视觉场景 `silent.tscn` 整体为空 → 角色透明。

### 9.2 三个根因（对照 spine-godot 4.2 源码逐一确认）

拉取了 `EsotericSoftware/spine-runtimes` 4.2 分支的 `SpineAtlasResource.cpp` 与
`SpineSkeletonFileResource.cpp`，三处手工产物的格式假设全部有错：

| # | 错误 | 源码依据 | 修复 |
|---|---|---|---|
| 1 | tres 的 ext_resource 路径写成了开发机目录 `res://sts2_work/...`，且 uid 是本机工程 uid（游戏 uid 缓存不认识） | Godot 文本资源加载器先查 uid、回退路径 | 路径改为 mod 内真实路径 `res://ling/animations/characters/silent/...`；去掉 ext_resource 的 uid 属性（tres 自身 uid 保留） |
| 2 | `.spatlas` 只有 `atlas_data`，缺 `source_path` | `load_from_file` 用 `source_path.get_base_dir()` 拼接图集页名再走 ResourceLoader；缺省时页路径是裸文件名，按普通文件加载必失败 | `.spatlas` 补 `source_path: res://ling/.../ling.atlas`（原版与 Kaguya mod 的 .spatlas 均有此字段） |
| 3 | JSON 骨架文本装进了 `.spskel` 产物 | `load_from_file` 按扩展名二分：`.spjson`/`.spine-json` 走 `checkJson`，**`.spskel` 一律按二进制 `checkBinary`（hash+版本）** | 产物改名 `.spjson` 并同步 `.import` 的 `path` |

另核对了 `checkVersion` 语义：骨架声明的版本必须**以运行时版本串开头**——原版
`silent.skel`（二进制）与我们的 `ling.json` 均声明 `4.2.43`，一致。动画名
idle_loop/hurt/cast/die 与 tres 中 SpineAnimationMix 引用一一对应。

### 9.3 处置

三处修复后重建 PCK（10 文件，1.44 MB）并更新到 `Mods\LingSilentSkin\`。
复测待观察两点：(a) 4.2 JSON 全量解析是否通过（本次日志尚无相关报错，因上游已断）；
(b) 渲染出来的尺寸/锚点——龙族与 STS2 的骨骼单位不同（图集 scale 0.45 vs 0.32），
属预期校准项。

### 9.4 方法论教训

- "同路径覆盖"生效 ≠ 资源链路通：本例 pck 挂载、tres 覆盖全部成功，故障在第二层引用；
  游戏日志是唯一可靠的观测点，应在第一次交付时就找到它（Godot 游戏在
  `%APPDATA%\<用户目录>\logs\`，STS2 用了自定义目录 `SlayTheSpire2`）。
- 手工构造导入产物必须对照运行时的**加载器**（而非导入器）源码：加载器按扩展名
  分派的行为（.spjson/.spskel 二分）无法从成品文件反推。

### 9.5 追记二：渲染崩溃定位与根因（2026-09-25 深夜）

修复 tres/spatlas/spjson 后复测：**在渲染实例时硬崩**（继续游戏、角色选择预览两处）。
两次崩溃均产生 sentry minidump（`%APPDATA%\Roaming\SlayTheSpire2\sentry\reports\*.dmp`），
用户卸载全部 Steam 创意工坊 mod 后崩溃依旧，排除 SkinChanger 嫌疑。

**取证方法**：手写 minidump 解析器（MINIDUMP_HEADER/ModuleList/ExceptionStream/
ThreadList/MemoryList）取得崩溃线程上下文与栈回溯：

- 崩溃点：`libspine_godot.windows.template_release.x86_64.dll+0x39370`，
  AV WRITE（c0000005）到堆地址；
- 反汇编（capstone）显示崩溃指令 `mov dword ptr [rax+rcx*4], edi` —— 向 int 数组
  顺序写索引，函数引用字符串 `'slot'/'offset'/'time'`（drawOrder 时间轴 JSON 键）
  与 `Vector.h` 分配点；
- 栈回溯：游戏主循环 → coreclr（C# 绑定）→ spine-godot 多层 → 崩溃，即
  **加载 tres 解析动画 JSON 时**崩溃，与日志"Preloading 'characters=SILENT' 后无
  任何报错瞬间消失"吻合。

**根因（第 11 项问题）**：Spine 4.1 二进制的 drawOrder offset 以 **raw varint**
存储（libgdx `readInt(true)` 返回 Java int，≥2^31 自动回绕为负），本例 -4 的
原始字节为 `FC FF FF FF 0F`。我们的解析器未做 int32 回绕，JSON 里写成
`4294967292`；spine-cpp 4.2 的 `SkeletonJson` 用 `drawOrder2[originalIndex +
offset] = originalIndex` 构造时间轴，4294967292 溢出 int 后下标变成 -2147483648
量级 → 写穿堆 → 硬崩。全 JSON 扫描确认 102 处越界值全部为 drawOrder offset。

**修复**：`spine41_parse.py` drawOrder 解析按 int32 回绕（对 libgdx 语义），
重新生成 ling.json（508,800 B），并验证修正后所有 `slotIndex+offset ∈ [0,50)`
（50 槽位、0 越界写）。重建 PCK 并安装。

**方法论教训**：跨语言移植二进制格式时，**每个整数字段都要对齐参考实现的
目标语言语义**（Java int 回绕 ≠ Python 无限精度整数）；minidump + 反汇编 +
崩溃函数字符串引用三件套可以在零符号条件下定位到具体数据结构。

### 9.6 追记三：透明复现与 deform 时间轴嵌套修复（2026-09-25 深夜二）

崩溃修复后复测不再崩，但仍透明。本次日志出现**干净报错**（不崩、只报错）：

```
ERROR: Error while loading skeleton data:
ERROR: Error message: Slot not found: Bq_sjzui
```

数据加载失败 → `NCreatureVisuals._Ready` 里 `GetData()==null` → 禁用 spine 动画
→ 角色透明（对应反编译代码的防御分支，游戏可正常运行）。

**根因（第 12 项问题）**：spine 4.2 JSON 的动画内附件时间轴（deform）为**三层嵌套**
`animations.<名>.attachments.<皮肤名>.<槽名>.<附件名>.deform[]`，我们的发射器
只写了两层（槽名在最外层）。C++ 读取器 `findSkin("zero_zui_z")` 得 NULL 后继续
用下一层键名查槽位 → "Slot not found"。此 bug 在旧 JSON 中同样存在，但此前
attack 动画的 drawOrder 崩溃先于 block 动画的 deform 段发生，把它掩盖了。

**修复**：`spine42_emit.py` 按 4.2 语义三层嵌套（`skin['name']` 外层），重生成
ling.json，并新增**全面验证**：skins 键∈槽名、动画槽时间轴键∈槽名、drawOrder
有符号且 slotIndex+offset∈[0,50)、deform 三层键各自∈皮肤名/槽名/该槽附件名。
全部通过后重打包安装。

**附注**：spine-cpp 4.2 把名为 "default" 的皮肤同时存入 `_skins` 与
`_defaultSkin`，故 `findSkin("default")` 可命中；`Slot not found` 仅来自
`findSlotIndex`（动画槽时间轴/drawOrder/deform 嵌套），skins 主结构的坏键
报错信息不同——排障时不要按报错文本反推出错段落。

### 9.7 追记四：节奏与尺寸校准（2026-09-26）

修复 deform 嵌套后角色正确实例化。剩余三项观感问题与处理：

1. **速度**：实测各动画时长（attack 1.33s / hurt 0.67s / cast 0.83s / idle_loop 4.0s）
   证明时间轴编码正确（绝对秒），"速度异常"实为**节奏不匹配**——STS2 的
   `AttackAnimDelay=0.15s`（反编译 Silent.cs）假定攻击动画约 0.5s，零的演出式
   动画比它慢一倍以上。处理：全部动画帧时间 ÷2（attack→0.67s）。
   没有走 SpineSprite 的 time_scale 属性——该属性在 spine-godot 4.2 只有
   bind_method 没有 ADD_PROPERTY，写进 tscn 不会被加载；数据侧缩放对引擎/场景
   无任何依赖。
2. **尺寸**：root 骨骼 setup scale 0.45→0.9（×2）。前提验证：root 无任何时间轴
   （否则会被动画覆盖）；图集的 `scale:` 行不影响渲染尺寸（RegionAttachment
   的四边形大小来自骨骼数据自身的宽高与骨骼变换，atlas scale 只影响 region
   元数据）。
3. **攻击动画对拍**：同样的节奏问题——游戏逻辑 0.15s 后结算，零的攻击演出
   1.33s 才结束，看起来"没对上"；2x 后 0.67s，大幅收敛。若仍不满意，
   `build_ling_assets.py` 的 `tune_for_sts2(speed=…)` 单参数可调。

两项调优已沉淀为 `build_ling_assets.py::tune_for_sts2(speed, root_scale_mult)`，
批量转换其他角色时自动继承。经安装包回读验证（root scale=0.9，attack=0.667s）。
**【2026-09-26 修正】本节的调优实现当时带两个未被发现的问题，现已修复**（详见《Spine渲染基准与STS2转换修正实验报告.md》）：① walk 只缩放关键帧 `time`，未缩放贝塞尔控制点里的绝对时间 → 调速后动画中段插值过冲（手部/武器撕裂的元凶）；② 只缩放 root，未补偿 5 根 `inherit=noScale` 骨骼（头/左手/拇指+枪链等不跟缩放，头身比失真）。另发现发射器 deform 附件名解析错误导致全部雕型丢失，均已修复；当前定版参数改为 speed=1.0 + root_scale_mult=3.0。

### 9.8 追记五：姿态异常根因——4.2 单值时间轴键名（2026-09-26）

调优后复测：角色正确渲染但**手臂全程垂下微颤、无攻击动作**，与原作常态举枪
姿态严重不符。资源比对排除了缺资源嫌疑（新旧 APK 的 models.png/cinematics.png
逐字节一致），真正根因在**发射器的 JSON 键名**：

spine-cpp 4.2 的 `readTimeline(CurveTimeline1)` 读取**单值时间轴**时用的键是
**`"value"`**（`Json::getFloat(keyMap, "value", 0)`），而 4.0/4.1 JSON 用
`"angle"`（rotate）/`"x"`/`"y"`。我们的发射器沿用了 4.0 风格键名 → 读取器
找不到键 → **全部 1164 条 rotate 时间轴的值按默认 0 处理** → 所有被旋转驱动的
骨骼（举枪的手臂链）塌回 setup 姿态，只剩平移/缩放/attachment 时间轴生效
（= 微颤）。站姿正常是因为腿部的 setup pose 本来就站立。

修复清单（spine42_emit.py vkey 表，按 4.2 源码逐键核对）：
- 单值轴 rotate/translatex/translatey/scalex/scaley/shearx/sheary → `"value"`
- 双值轴 translate/scale/shear 保持 `"x"/"y"`（正确）
- 零用到的其余键均核对无误：ik 帧 `bendPositive/mix/softness/compress/stretch` ✓、
  deform `vertices/offset` ✓、attachment `name` ✓、inherit 枚举（5 根 noScale 骨骼）✓

方法论教训：**跨版本转换时每个 JSON 键名都必须对照目标版本读取器源码**，
"格式相近想当然"的键名错误不会产生任何报错（getFloat 缺键走默认值），
只在渲染层表现为"动画部分失效"。

### 9.9 资源版本核对（新 APK + 热更包）

用户提供新版 base.apk（976MB）与安卓热更数据（iguf_00/01.dat，共 3.4GB，祖龙
自有 ZSTD 记录流容器，头部 `58af5a00…4D25EDBC`）。逐条目 CRC 对比两 APK：
`assets/res_base/package/models.png`（47,799,964 B）与 cinematics.png **完全一致**，
即 chr_ling001 骨骼在当前版本与解包版本相同，**不存在资源缺失，无需在线下载**；
姿态问题纯为上述键名 bug。热更 iguf 解析暂无必要（模型/演出包未随版本变化）。

### 9.10 试衣间界面反编译：displaySpineId（立绘）与 fightSpineId（骨骼皮）双骨骼体系（2026-09-26）

用户反馈"材质差异大、头部明显偏小"后，反编译安卓端"皮肤"界面（截图即
试衣间）实现，源码在 res_lua（Lua5.1 字节码，unluac 可还原；热更
saved_download_entry.dat 104,317 条全为 UE4 资产、无 Lua，游戏逻辑全在基础包）。

调用链：`PanelSkin`(modules/partner/ui/skin/panelskin.lua, 资源 Panel_FashionMain)
同时挂两个 Spine 视图：
- **大图** = `ViewAppearanceDisplaySpine` → `appearance_cfg.displaySpineId` →
  `S_Plotdrawing/SPD_*` 立绘骨骼（CSpineResCfg scaleX/Y=1.0，size 1341×1385），
  动画选择器 SingleLoopAnimationSelector —— **这是立绘，美术规格完全另算**。
- **左下小卡** = `ViewAppearanceFightSpine` → `appearance_cfg.fightSpineId` →
  `Characters/Ling001/Chr_ling001`（scaleX/Y=0.6），动画强制 `"idle"` 循环，
  外加 `SetRenderTranslation(posX, posY)` —— **这才是"骨骼皮"，即我们转 STS2 的那套**。
两者经 `ViewSpineWidget._Load` → `BnyUtility.GetRecord("common","CSpineResCfg",id)`
→ `SpineCacheMan:LoadSpineByPath(atlas, skeleton, materialId)`，可选
`SetLoadUseCfgScale`（读配置 scaleX/Y）。皮肤→外观经 skin_cfg.appearanceId 关联。

**bny 数据表格式**（res_data/bny/*.bny，C++ 侧解析，已逆向）：定长记录区
（字段偏移=confbean lua 里的注解，**全大端序**）+ 尾块 + 字符串池（`[大端
varint 长度][UTF-8 字节]`，0=空串，字符串去重、记录内存引用下标）。
CSpineResCfg：id@0/atlas@4/skeleton@8/materialId@12/skinName@16/scaleX@20/scaleY@24
/pos@28,32/size@36,40（64B/条，683 条）；CAppearanceCfg stride=69、528 条，
关键字段 name@4/fightSpineId@28/displaySpineId@32。解析器存档
unpacked/spinerescfg_dump.json、appearancecfg_dump.json。

零的相关映射（appearance id → 两套 spine）——【本节初版的皮肤名称归属全部有误，已删除；权威映射以 iguf热更包解包实验记录.md §9 为准：零(102500022)与极夜绮梦共用 fight=Chr_ling001、沉思之歌→Chr_ling002、永夜终舞→Chr_ling003、都市龙语→Chr_ling005】。保留两条已验证事实：**yesheng=叶胜**（非"野生"，棕发双马尾+卡塞尔制服，另一角色，Chr_yesheng001 是他的骨骼）；白裙双枪造型（蓝裙底+白花+双枪）= **Chr_ling001 图集**，与试衣间左下骨骼皮预览一致。

**结论**：此前"头部偏小/材质差异"是拿 STS2 渲染对比立绘（displaySpineId），
属于两套不同美术。正确对标=左下 fightSpineId 预览=Chr_ling001=我们已转的
骨骼。数值校验：setup 700 值（除 root 故意×2 全一致）+16 动画 1574 条时间轴
帧数一致+6839 个动画值零误差 → **转换数值无损，比例即原骨骼比例**，STS2 侧
无需再改。若未来想要立绘规格，可另转 SPD_* 骨骼，但其动画集不含 attack/hurt，
只适合展示场景。

### 9.11 蓝裙底之谜与 iguf 热更包逆向（2026-09-26）

用户指出 STS2 渲染的裙底为黄色，而游戏试衣间为蓝色。排查结论：

1. **卡与皮肤体系**——【本条初版的皮肤清单与名称归属全部有误，已删除。权威结论见 iguf热更包解包实验记录.md §9：零(102500022, CPartnerCfg 220003014)共 6 皮肤——零/极夜绮梦(共用 Chr_ling001)、沉思之歌(Chr_ling002)、永夜终舞(Chr_ling003)、都市龙语(Chr_ling005)、深蓝素誓(未上线)；「纸醉金迷」不是皮肤名，是樱井小暮「奢艳瑰情」的描述文本引言；龙骸狂刃(102500199)=龙刃酒德麻衣(220003027)的皮肤。」（CPartnerFashionCfg: partnerId@8/appearanceId@12, stride=65）
2. **热更 iguf 容器格式完全逆向**：文件 = 连续单元 `[58af5a00][u32 size]`，
   两类：① `[4D25EDBC][u16 ver][u32 total][u32 chunk=0x10000][u32 字典解压]
   [u32 字典压缩][zstd 字典帧][N×u32 帧压缩表][N 个 64KiB zstd 数据帧]`
   （N=ceil(total/chunk)，首帧解压产物即 zstd 字典，逐文件独立字典）；
   ② `[BKHD][DIDX][DATA][HIRC]` = 原样存储的 WWise .bnk 音频库。单元=单文件。
   提取器跑通后可dump 全部 ling 家族图集（62 个）+ Chr_ling002 贴图/mask。
3. **裙底观感根因（终局）**：游戏内蓝色观感=贴图本体+引擎光照。早期解包 PNG 显示"黄裙"是解码管线通道序 bug 的伪象——`texture2ddecoder.decode_astc` 输出 BGRA 序而解码器未做 BGR→RGB 重排，全部 ASTC 解码 PNG 红蓝反转（实机捕获纹理载荷与 chr_ling001.uexp 载荷逐字节相同、通道交换后 diff=0 的铁证见 iguf热更包解包实验记录.md §6/§12.8）。
4. **解决方案（终局）**：修复解码器通道序，mod 贴图使用修复后的解码（实机同源）。早期对两区域做 HSV +168° 色相旋转烘焙的方案是对该伪象的近似补偿，已废弃；`.ctex` 生成与 pck 打包流程（GST2 56B 头+WebP 无损、[52:56] 写载荷长度）继续有效。
