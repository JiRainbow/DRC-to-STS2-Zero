# 零（Ling）→ 静默猎手（Silent）皮肤替换 Mod

把《龙族》角色"零"的 Spine 骨骼皮肤转换为《杀戮尖塔 2》（Godot 引擎）静默猎手的替换皮肤。

## 安装

1. 把 `LingSilentSkin` 文件夹（内含 `LingSilentSkin.json` + `LingSilentSkin.pck`）放入：
   `Steam\steamapps\common\Slay the Spire 2\Mods\`
2. 启动游戏，在 Mod 列表里启用 LingSilentSkin。

## 替换内容

- 静默猎手战斗场景的 Spine 骨骼数据（`animations/characters/silent/silent_skel_data.tres` 覆盖）
- 零的 Spine 4.2 骨骼：17 个动画（idle_loop / attack / cast / hurt / die 已映射，
  其余原动画 block/entry/jump/onfoot/sit/sitloop/skill01_2/3/stand/tibu/win/winloop 保留）
- 图集 Chr_ling001.png（1024×512，64 区域，从游戏 ASTC 纹理解码还原）

## 原理

游戏本体使用 spine-godot（Spine 4.2.43 运行时）。本 mod 以同路径覆盖
`silent_skel_data.tres`（保留原 uid，场景引用不变），其 ext_resource 指向
mod 自带的零骨骼 JSON（4.2 格式）+ 图集 + 纹理导入产物（.spjson/.spatlas/.ctex）。

三个产物文件有硬性格式要求（源自 spine-godot 4.2 源码）：

- `.spjson`：只能装 JSON 文本骨架；`.spskel` 只能装二进制骨架，两者不可混用
  （`SpineSkeletonFileResource::load_from_file` 按扩展名二分，`.spskel` 走 `checkBinary`）。
- `.spatlas` 必须带 `source_path` 字段：贴图页名是普通文件名，运行时用
  `source_path` 所在目录拼接页名再经 `.import` 重映射找到 `.ctex`；缺了它贴图必挂。
- 骨架的 `skeleton.spine` 版本必须以运行时版本号开头（`checkVersion`），这里是 `4.2.43`。

## 实测记录（2026-09-25）

首次进游戏表现为角色位置整体透明。游戏日志（`%APPDATA%\Roaming\SlayTheSpire2\logs\`）
定位到三个问题，均已修复并重打包：

1. tres 的 ext_resource 路径写成了开发机目录（`res://sts2_work/...`），游戏内不存在
   → 整个 `silent.tscn` 加载失败，角色为空。已改为 mod 内真实路径
   `res://ling/animations/characters/silent/...`，并去掉无效 uid（保留 tres 自身 uid）。
2. `.spatlas` 缺 `source_path` → 即使 tres 修好，贴图页也会加载失败。
3. JSON 骨架误放 `.spskel` 产物（被当作二进制校验，必失败）→ 改名 `.spjson` 并同步 .import。

复测记录（同日晚些时候）：修复上述三项后首次复测**渲染实例时硬崩**（两次，
卸载全部创意工坊 mod 后仍崩）。minidump 取证定位为 spine-godot 原生层 OOB 写：
drawOrder offset 被 4.1 解析器按无符号 varint 写成 `4294967292`（应为 `-4`，
Java int 语义回绕），spine-cpp 构造 DrawOrderTimeline 时下标溢出写穿堆。
已在 `spine41_parse.py` 按 int32 回绕修复并重新生成骨骼 JSON（102 处越界值
全部消除，边界校验通过），已重打包安装。

三测（同日）：不再崩溃但仍透明，日志出现 `Slot not found: Bq_sjzui`——deform
时间轴被发射成两层嵌套（槽名在外层），而 4.2 要求
`attachments.<皮肤名>.<槽名>.<附件名>` 三层。此 bug 此前被 attack 动画的
drawOrder 崩溃掩盖（解析顺序 attack 在 block 之前）。已修 `spine42_emit.py`
并新增全面数据验证（槽名/皮肤名/附件名存在性、drawOrder 有号有界）后重打包。

四测（2026-09-26）：渲染正常。观感调优已实装并随 pck 更新：

- **速度 2x**：全部动画帧时间 ÷2（attack 1.33s→0.67s），贴合 STS2 战斗节奏
  （游戏逻辑攻击延迟仅 0.15s）；
- **尺寸 2x**：root 骨骼 scale 0.45→0.9。

若想再调，`tools/build_ling_assets.py` 的 `tune_for_sts2(speed, root_scale_mult)`
单参数可改后重跑打包。已知差异：攻击结算发生在动画前段（游戏逻辑固定 0.15s），
零的攻击演出比原版 Silent 更长，属正常现象。

## 已知限制

- 仅替换战斗场景；篝火（rest site）、商店、角色选择界面仍显示原版静默猎手
  （对应 rest_site/character_select/merchant 的 skel_data 未覆盖，可按相同方法扩展）。
- 零没有"死亡"动画，已合成一个空的 die 动画（游戏侧的死亡表现流程不受影响）。
- 零的立绘分辨率/比例与原版静默猎手不同，实际观感以游戏内为准。

## 文件说明（本目录）

- `LingSilentSkin.json` — mod 清单
- `LingSilentSkin.pck` — Godot PCK v3 资源包（可再打包/重签名）

生成管线源码见 `D:\项目\dragonraja\tools\`（az_spine_extract.py / spine41_parse.py /
spine42_emit.py / build_ling_assets.py / pck_writer.py）。
