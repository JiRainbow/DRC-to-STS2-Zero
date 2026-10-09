# iguf 热更包解包实验记录

日期：2026-09-26 起
对象：安卓端热更数据 `com.zulong.drc.gw/files/ingameupdate/`（与工作目录内 base.apk 976MB 配套）
背景：排查 STS2 零皮肤与手游端的贴图观感差异（后定案为解码管线通道序问题，见 §6），进而对热更包做完整解包，并沿"资产→代码→运行时"三层完成渲染链逆向。

> 本记录只写技术事实与已验证结论。会话早期关于「partnerId ↔ 皮肤名 ↔ 骨骼」的名称归属推断有误，已全部撤回，正确皮肤清单见 §9。

---

## 1. 热更目录清单

```
com.zulong.drc.gw/files/
├── afile_diff_name.lua                      （小文件，未深究）
├── ingameupdate/
│   ├── iguf_00.dat                2,146,826,183 B
│   ├── iguf_01.dat                1,255,592,449 B
│   ├── preprocessed.dat                  ~1 KB
│   ├── preprocessed_filesize_infos.dat   ~1 KB
│   └── saved_download_entry.dat       8.9 MB
└── UE4Game/Azure/Azure/Saved/Logs/Azure.log
```

`preprocessed*.dat` 头部：`01 00 20 00` + 32 字符 MD5 串（两文件相同，如 `300a40c6...`）。
与 iguf_00.dat 整包 MD5 不符，用途未定（疑似服务端清单校验）。

UE4 日志关键行（Azure.log）：
- `<igupackage_preupdate enable_download="true" enable_apply="true" address="http://autopatch-lzkp-tc.zulong.com/lzkpgame/source/lite_android_astc/dlc_packages" ...>` —— iguf 即从 `dlc_packages` 下载的 IGU 预打包
- `ingame_update_baseurl = .../dlc_files/` —— 另有按单文件的增量下载通道
- `OpenSavedDownloadFileEntryList: Path[...saved_download_entry.dat] Entries: Total[92990]`（两次启动为 92990/92958，与本地文件 104,317 条不同：本地含已消费条目）

## 2. saved_download_entry.dat（下载清单）

记录格式（循环至文件尾，104,317 条恰好耗尽）：

```
[u16 路径长][路径 UTF-8][20B SHA1][u32 size][u8 标志][2B 固定 5d 9a]
```

- size 合计 = 3,402,418,632 B ≈ 两 iguf 总量（3.4GB）→ 清单与 iguf 内容一一对应
- 扩展名分布：uexp 51,482 / uasset 51,303 / ubulk 605 / bnk 412 / wem 304 / umap 179 / mp4 32
- 顶层目录：effects 68,968 / ui 12,952 / models 8,620 / buildings 6,922 / cinematics 2,470 / fight 2,124 / maps 770 / sound 716 / scenes 688 / parentmaterials 77 / miscs 10
- 解析产物：`unpacked/hotupdate_manifest.json`（[path, sha1, size] 三元组）

**注意**：清单中的 SHA1 与解包出的原始文件内容的 SHA1 不一致（全部 miss），size 也≠原始文件大小，因此清单不能直接做「单元→路径」映射（详见 §5 教训②）。全量清单 `unpacked/hotupdate_manifest_full.json`（154,171 条）与单元表 `unpacked/iguf_units_final.json` 按流顺序严格一一对应，任意文件按索引即可定位单元。

## 3. 走不通的路（教训）

1. **CDN 单文件下载**：`http://autopatch-lzkp-tc.zulong.com/lzkpgame/source/lite_android_astc/dlc_files/models/characters/ling002/chr_ling002-data.uexp` → `NoSuchKey`。dlc_files 只保留最新一轮增量，历史文件已被打包进 dlc_packages。
2. **SHA1 匹配**：以清单 SHA1（以及其前 4 字节）在解压数据中查找/反查，命中率 0。
3. **size 匹配**：清单 size ≠ 解压后文件大小（口径不同，疑似为下载/压缩口径）。

结论：iguf 内部必须按**内容特征**识别文件，而非清单映射。

## 4. iguf 容器格式（本次核心成果）

文件本体 = 一串「单元」首尾相接，每单元前缀 `[58 af 5a 00][u32 字段]`。单元分两类：

### 4.1 类型 A：zstd 字典分帧块（普通资源文件，绝大多数）

```
[4D 25 ED BC]                     块 magic
[u16 ver=1]
[u32 total]                       本单元解压后总字节数（=原始文件大小）
[u32 chunk=0x10000]               数据帧解压尺寸 64KiB
[u32 dict_decomp]                 字典帧解压大小（==0 表示无字典）
[u32 dict_comp]                   字典帧压缩大小
[zstd 字典帧 × dict_comp 字节]     解压后即 zstd 字典（逐文件独立字典）
[N × u32]                         N 个数据帧的压缩大小表，N = ceil(total/chunk)
[N 个 zstd 数据帧]                 用上述字典解压，依次拼接 = 原始文件
```

要点：
- **首帧的解压产物就是 zstd 字典**（与当年 AFilePackMan 的套路一致）。解压后续帧需 `ZstdCompressionDict(字典内容)`。
- 解压要用 `decompressobj()`（流式、自终止），不能用一次性 `decompress()`（帧头声明的 content size 语义不同会报错）。
- 末尾不足 64KiB 的尾帧正常存在于帧表中；个别数据帧不可压缩时**裸存**（不以 `28 B5 2F FD` 开头，直接原样拼入）。
- `dict_decomp==0` 分支：无字典、无帧表，payload 为单个自终止 zstd 帧，或整段裸数据（不可压缩小文件），payload 长度即头部 `dict_comp` 字段。
- **一个单元 = 一个原始文件**。已验证：PF_ASTC 纹理 uexp（头部 u64 元数据 + ASTC 载荷 + PF_ 格式串）、图集文本、以及文件尾的 UE4 包 magic `C1 83 2A 9E`。

### 4.2 类型 B：WWise 音频库（.bnk）

前缀后直接跟 `BKHD`，随后为标准 WWise bank 段序列：
`BKHD / DIDX / DATA / HIRC / STID ...`，每段 `[4CC 段名][u32 段长][段体]`。
- DIDX 条目 12 字节：`[u32 wem-id][u32 DATA 内偏移][u32 大小]`
- **整个单元按原始字节存储（未压缩）**，段长即跨度，顺序解析到未知段名即为单元结束
- 音频单元数量约每几百单元一个；早期解析器不认识它导致反复 resync 丢数据

### 4.3 解析器坑位记录

1. **字段偏移**：若把 4 字节 kind 单独 read 出来再读头部，后续字段偏移全部要 +4 重排（ver@0/total@2/chunk@6/dict_decomp@10/dict_comp@14）。本次曾因偏移没重排导致解析垃圾、walker 假死。
2. **resync**：任何异常后，从当前位置向前扫描 `[58 af 5a 00]` 且其后第 8 字节为 `[4D25EDBC]` 或 `[BKHD]` 的位置作为下一单元。
3. **bnk 跳过**：顺序累加段长（段名白名单 BKHD/DIDX/DATA/HIRC/STID/ENCS/OBJT/FKFX/ATOM/PLAT），不能盲目按固定长度跳。
4. 一次性 `zstd.decompress()` 对「帧头声明 content size」的帧可用；对字典帧建议统一走 `decompressobj`。

## 5. 提取管线与产出

分类规则（按内容，非清单）：
- **骨架**：内容中 `4.1.19` 出现在前 4KB 且文件 < 300KB（真实的 Spine 4.1.19 uexp；>300KB 的命中多为 .uasset 里的引擎版本串，误报）
- **图集**：前 400B 同时含 `.png` 与 `size:`（Spine atlas 文本，带 UE4 包装头）
- **贴图**：PF_ 头解析出 `(fmt, w, h)` 且尺寸在白名单（1024×512 / 512×512 / 1024×1024），40KB~1.2MB

产出（`unpacked/iguf_final/`，pack 格式 `[u32 unit][u32 len][u8 code][data]`，code: 0=骨架 1=图集 2=贴图）：

| 产物 | 位置 | 说明 |
|---|---|---|
| 图集 ×62（ling 家族） | `rec/a*.atlas.txt` | Chr_/S_Plotdrawing_/fightdrawing_/Plotdrawing_ 系列 |
| 零家族贴图 | `unpacked/iguf_range/png56/` 等 | Chr_ling002 1024×1024 + mask 等 |
| 全量记录 pack | `ling_hits*.pack` | 可再离线细分 |
| 解析日志 | `extract*.log` | 各轮统计 |

零家族图集页尺寸（atlas `size:` 声明）：

| 页 | 尺寸 |
|---|---|
| Chr_ling001 | 1024×512（基础包） |
| Chr_ling002 | 1024×1024 |
| Chr_ling003 | 512×512 |
| Chr_ling006 | 1024×512 |
| Chr_URling001/002/004/005 | 1024×512 |
| Chr_URling003 | 512×512 |
| Chr_URlinghao001/002 | 512×512 |

热更包含 chr_ling002 / 003 / 005 / 006 的完整 骨骼+图集+贴图；基础包只有 chr_ling001 与 chr_yesheng001。

统计（第二轮，最完整）：68,093 单元，命中 1,148，异常跳过 14,116（当时 bnk 未单独处理导致的损耗；加入 bnk 处理后损耗大幅下降）。

流内可见大量**重复尺寸的共享资源**（如 468,210 / 468,266 / 418,466 / 1,871,793 字节的单元反复出现），按内容分类时注意别当新文件。

> 注：早期轮次的 ASTC→PNG 解码产物存在通道序 bug（红蓝反转），根因与修复见 §6；以 §6 修复后的解码为准。

## 6. 贴图解码通道序 bug 与"蓝裙底"根因（已验证 ✓）

1. 手游战斗/试衣间的角色观感（冷白皮肤、灰蓝发、白裙、蓝枪蓝饰）= **贴图本体 + 引擎光照**。游戏内不存在把 chr_ling001 贴图染色的运行时机制（p215 材质的反色项在战斗参数下数值可忽略，见 §12.9）。
2. 早期解包 PNG 显示"黄裙黄枪、冷色头发"，由此触发了长期的"染色公式"排查。根因是**解码管线 bug**：`texture2ddecoder.decode_astc` 输出为 **BGRA 序**，`tools/build_ling_assets.py::decode_astc_texture` 未做 BGR→RGB 重排——**全项目所有 ASTC 解码 PNG 均红蓝反转**。
3. 铁证：实机捕获上传的战斗纹理（tex827）压缩载荷与基础包 `res_models/characters/ling001/textures/chr_ling001.uexp` 载荷**逐字节相同**（0.00% diff，14706 个 ASTC 块 0 变化）；同一数据两路解码结果不同，唯一自由度=通道序，R/B 交换后与实机解码 diff=0.0000。
4. 修复：`decode_astc_texture` 输出前交换 R/B，与实机解码对拍 **maxdiff=0**。v0.2 时代的 HSV+168° 局部烘焙是对该伪象的近似补偿，已废弃。
5. 波及范围：`unpacked/extract_cache/` 与 `resources/` 资源树中的全部 PNG 为反转变体，需要时用修复后的解码器重提（`tools/iguf_extract_asset.py --png`，直接从 iguf 卷按包路径提取+解码）。热更清单中 chr_ling001 零条目——不存在"新版贴图"，实机与解包同源。

## 7. 工具与复现要点

- iguf 单元提取：`tools/iguf_extract_asset.py <包路径> [-o OUT] [--png]`（清单+单元表定位→解压→可选 ASTC 解码）；单元读取模板 `tools/extract_m_ui_test_inst_uexp.py`。
- bny 配置表解析器（大端定长记录 + varint 字符串池）：CSpineResCfg / CAppearanceCfg / CMaterialResCfg / CPartnerFashionCfg，产物 `unpacked/*_dump.json`。
- 贴图解码：`tools/build_ling_assets.py::decode_astc_texture`（Zulong Texture2D uexp → PNG，含通道序修复）。
- 材质实例解析：`tools/parse_mi_final.py`（FPropertyTag 通用解析）、`tools/ue4_dump.py`（16663 资产全量转储）。
- 着色器提取：`tools/dump_all_shaders.py`（86154 个 .ushaderbytecode 全解）、`tools/extract_holo_shaders.py`。
- Lua 反编译：`tools/LuaBatch.java`（unluac 批量驱动）+ `tools/lua_build_index.py`。
- .ctex 生成：GST2 头（原样保留 0..52 字节）+ Pillow `WEBP lossless` + `[52:56]`=载荷长度。
- pck 打包：`tools/pck_writer.py` / `tools/godot_pck.py`；皮肤构建 `tools/build_battle_pck.py`（silent）、`tools/build_urban_pck.py`（urban）、`tools/build_drcspinedye_pck.py`（框架）。

## 8. 已知正确信息与待重梳事项（已重梳完成，见 §9）

**用户提供（下一轮核对基准）**：
- 零（zero）共 **6 个皮肤**：零、极夜绮梦、沉思之歌、永夜终舞、都市龙语、深蓝素誓 ✓（已被数据证实）
- 其中 **零 与 极夜绮梦 的战斗皮肤相同**，仅立绘不同 ✓（已被数据证实）
- 纸醉金迷 = **苏恩熙** 的皮肤 ✗（**已证伪**：纸醉金迷不是皮肤名，只是樱井小暮「奢艳瑰情」的描述文本引言+解锁道具名，见 §9.4）
- 龙骇骨刃 = **酒德麻衣** 的皮肤 ✓（正确写法为「龙骸狂刃」，卡牌=龙刃酒德麻衣，见 §9.5）

**撤回**：本会话早先关于 partnerId→卡名、appearanceId→皮肤名、以及「某皮肤→某骨骼」的名称归属推断（含报告 §9.10/§9.11 中的相关表述）不可靠，以本节为准。

## 9. 真实映射表（第二轮重梳，已交叉验证）

### 9.1 解析错误根因：字符串池长度前缀

§8 待办 2 的「疑似行错位」**不成立**——记录布局（stride=69、name@4、fightSpineId@28）一直是对的，错在**字符串池的长度前缀解析**。真实规则：

```
首字节 b0 < 0x80        → 长度 = b0（单字节）
首字节 b0 ≥ 0x80        → 长度 = ((b0 & 0x7F) << 8) | 下一字节（两字节）
```

验证样本：`Y` + 上杉绘梨衣介绍 → 预测 601 字节，实测 601 字节，其后紧随` 审判`、` 出门旅游，结交朋友` 等整齐边界；`B` + 66 字节引文 ✓；单字节 69/82/102 等均直读 ✓。此前误按"连续 7 位组大端 varint"读，多字节长度全部读错，导致 496 条之后的池条目丢失、名称串位。修正后 CAppearanceCfg **529 条记录全名解析正确**（此前记 528 条系漏 1）。

### 9.2 四张关键表（字段偏移来自 confbean 反编译，均为大端）

| 表 | stride | 关键字段 |
|---|---|---|
| CAppearanceCfg | 69 | id@0, name@4(串), desc@8(串), fightSpineId@28, displaySpineId@32, modelAppearanceCfgid@16 |
| CSpineResCfg | 64 | id@0, atlas@4(串), skeleton@8(串), materialId@12, skinName@16(串) |
| CPartnerFashionCfg | 65 | id@0, sortId@4, partnerId@8, appearanceId@12, fashionEnum@16（287 条）|
| CPartnerCfg | 260 | id@0, partnerType@4, name@8(串), nameInEnglish@12(串)（76 条，池 724 串）|
| CPartnerFashionUnlockItemCfg | 76 | 继承 CItemCfg：name@16(串)；自有 partnerFashionCfgid@68 |

完整字段见 `unpacked/res_lua/bny/gen/drc/gsp/*/confbean/*.lua`（unluac 可反编译）。

### 9.3 零的皮肤映射（数据验证）

| 皮肤名 | appearanceId | fightSpineId | 战斗骨骼 |
|---|---|---|---|
| 零（默认） | 102500022 | 101100020 | **Chr_ling001** |
| 极夜绮梦 | 102500079 | 101100020 | **Chr_ling001（与零共用 ✓）** |
| 沉思之歌 | 102500131 | 101100056 | Chr_ling002 |
| 永夜终舞 | 102500200 | 101100106 | Chr_ling003 |
| 都市龙语 | 102500249 | 101100145 | Chr_ling005 |

- **零/极夜绮梦共用战斗骨骼**在数据层面成立：两条 appearance 的 fightSpineId 同为 101100020（CSpineResCfg → `Models/Characters/Ling001/Chr_ling001-atlas/-data`），仅 displaySpineId（立绘，101101029 vs 101102027）不同——与用户权威信息完全一致。
- 解锁道具链佐证：CPartnerFashionUnlockItemCfg「零-沉思之歌」→ fashionId 220703008 → (partnerId 220003014, appearanceId 102500131) ✓。
- 零的卡牌 = CPartnerCfg 220003014（name=零, en=Zero）。
- 另有一条空名记录 102560022 同样指向 101100020（内部/占位行）。

### 9.4 纸醉金迷考证

**纸醉金迷不是皮肤名**。基础包 2330 张 bny 中，"纸醉金迷"仅出现在：
- 樱井小暮皮肤「奢艳瑰情」（appearanceId 102500130）的描述文本："纸醉金迷中，谁又是谁的猎物？"
- 该皮肤的解锁道具名「樱井小暮-奢艳瑰情」

即：奢艳瑰情 = 樱井小暮（CPartnerCfg 220002010, en=Kogure Sakurai）的皮肤，战斗骨骼 `Chr_yingjingxiaomu002`（角色正确写法为苏**曦**，Enxi；其默认皮肤 = Chr_suenxi001）。

### 9.5 龙骸狂刃考证

龙骸狂刃（appearanceId 102500199, fightSpineId 101100103）→ `Chr_EXjiudemayi001`（EX+酒德麻衣拼音）。卡牌 = CPartnerCfg **220003027 = 龙刃酒德麻衣（en=Mai Sakatoku Dragonoid）**——与用户"龙骸狂刃是龙刃酒德麻衣（UR 卡）"的说法完全一致。

### 9.6 深蓝素誓：不在本基础包

"深蓝素誓"在 2330 张基础 bny 中 0 命中（含繁体/子串变体）。基础 CSpineResCfg 无任何 Ling004/Ling006 引用，但热更 iguf 中已含 chr_ling004/006 资产——即这些骨骼是**预留给未上线/新皮肤**的内容，其配置行需更新的配置表（不在本基础包，热更 manifest 中亦无 .bny 路径）。若深蓝素誓已上线，其 appearanceId/fightSpineId 需从线上版本配置获取；按 ling 系列编号推测其骨骼为 Chr_ling004 或 Chr_ling006 之一（待证）。

### 9.7 结论

用户六皮肤清单中 5 个已在数据中定位并建链（深蓝素誓除外，见 9.6）；两条用户权威断言（零/极夜绮梦共用战斗皮、龙骸狂刃属龙刃酒德麻衣）全部与数据吻合。解析产物：
- `unpacked/appearancecfg_full.json`（529 条全字段）
- `unpacked/spinerescfg_full.json`（683 条）
- `unpacked/partner_full.json`（76 卡牌，中英名）
- `unpacked/partnerfashion_full.json`（287 条）
- `unpacked/pool_cappearancecfg.json`（池字符串）

## 10. 资源树导出与 iguf 最终语法（第三轮）

### 10.1 iguf 最终语法（本轮补全，chain-walk 154,171/154,171 零失步）

单元 = `[58af5a00][u32 span][body]`，**span = body 解压后总字节数**（非存储长度！前两轮的两次误读）。
manifest 的 size 字段 = **单元存储总长**（8 前缀 + body），顺序与 manifest 严格一致：

- `4D25EDBC`：`[u16 ver][u32 total][u32 chunk=65536][u32 dd][u32 dc]`
  - dd==0：`[K×u32 帧压缩大小表][帧0(dc 字节)][帧1..K]`，K = ceil(total/chunk)−1，帧为普通 zstd（无字典）
  - dd>0：`[zstd 字典帧 dc 字节][N×u32 表][N 帧]`，数据帧需 `ZstdDecompressor(dict_data=...)`；python-zstandard 0.25 每帧要新建 decompressobj
- `BKHD`：WWise bnk（段长跳走）；`RIFF`(5249)=wem、`06/07`=路径/视频条目、其余裸存
- 全库 magic 计数 154,172 ≈ manifest 154,171（1 个压缩数据内假魔数），链式按 unit_len 前进可无视

### 10.2 资源树（resources/，按角色卡）

```
resources/<卡名>/卡牌信息.txt           # CPartnerCfg：中英名/稀有度/介绍/背景/言灵/生日
resources/<卡名>/<皮肤名>/皮肤信息.txt   # CAppearanceCfg：描述/画师 + 骨骼路径
resources/<卡名>/<皮肤名>/战斗骨骼/      # fightSpineId → atlas + skel(Spine4.1.19) + png(ASTC解码)
resources/<卡名>/<皮肤名>/立绘/          # displaySpineId（plotdrawing/S_Plotdrawing）
```

- 76 卡 / 287 皮肤，287/287 完整（战斗骨骼三件套 + 立绘 atlas/skel）
- 共 994 PNG + 572 atlas + 572 skel，1.8GB
- 贴图解码：ASTC 双布局——带 .astc 头（13ABA15C）或无头（w/h 在 PF_ 串前 16 字节、数据在 PF_+0x1C）
- 图集文本有 ASCII 与 UTF-16-LE 两种；立绘图集的贴图页可能跨目录引用角色目录的 textures
- 热更缺失的文件走基础包 res_models 兜底（首发 13 角色 + 部分立绘）
- 索引产物：unpacked/iguf_units_final.json（154,171 单元表）、unpacked/needed.json、unpacked/extract_cache/
- 遗留：34-35 个跨目录贴图引用（pd_* 立绘引用别的目录贴图）已由 stem 全局索引+基础包兜底解决

### 10.3 贴图绑定修正（页名 ≠ 实际绑定）

根因：**.atlas 文本里的页名 ≠ 游戏实际绑定的贴图**。SpineAtlasAsset（-atlas.uasset）的 `atlasPages` 数组里的 Texture2D 引用才是权威绑定（如 chr_qzz_aoman002.atlas 文本页名写 `Chr_aoman_mask.png`，但 .uasset 引用的是 `Textures/Chr_Qzz_aoman002` 成色贴图；mask 蒙版是供材质使用的通道图，对该 spine 不生效）。首版导出按页名找贴图，把 570 个页贴图放成了错误内容（染色变体/立绘跨目录引用最集中）。

修正：解析每个 -atlas.uasset 的 `/Game/.../Textures/<名>` 引用，按引用（页序配对）解码，页文件名仍按 .atlas 文本。
结果：fixed=570 / same=338 / fail=0；重摆 996 张 PNG；全树扫描 994 张贴图 0 张残留纯色蒙版。


## 11. 官方运行时基准渲染与 STS2 手部扭曲根因（第四轮，已验证 ✓）

### 11.1 背景
用户把零「都市龙语」(Chr_ling005) 导入 STS2（Godot + spine_godot 扩展）后观察到：手部网格扭曲、疑似还有额外染色。要求用逆向数据渲染一帧"龙卡手游端实际预览"作为对照基准。

### 11.2 基准渲染器（可复用工具）
- `render_work/spine-webgl.js`：npm `@esotericsoftware/spine-webgl@4.1.19` 的 IIFE 产物（与骨骼版本 4.1.19 完全一致），**扁平导出**（`spine.SceneRenderer`，没有 `spine.webgl` 命名空间）。
- `render_work/view2.html`：通用渲染页。用法：
  `python -m http.server 8477 --bind 127.0.0.1 --directory <项目根>`，浏览器开
  `/render_work/view2.html?atlas=/resources/<卡>/<皮肤>/战斗骨骼/xxx.atlas[&anim=idle&t=0.5][&cx=&cy=&cz=相机特写][&w=&h=&log=0]`
  参数：anim+t 播放动画帧；cx/cy/cz 手动相机（此相机可见世界宽度 = viewportWidth × zoom）；log=0 隐藏日志面板。
- `render_work/probe.html`：骨骼诊断页（打印全部骨骼名 / 权重网格清单，用 FakeTexture 免贴图加载）。
- 关键 API 事实：TextureAtlas 构造器不收 loader，必须 `page.setTexture(new spine.GLTexture(gl, image))`；4.1 的 `skeleton.updateWorldTransform()` 无参（无 physics）；图片加载用 onload/onerror（本环境 `img.decode()` 会挂起）。
- 基准产物：`render_work/ling005_fight_setup_gt.png`（setup pose）、`ling005_fight_idle_gt.png`（idle@0.5s 持枪姿势，与 STS2 截图同姿势）、`ling005_fight_idle_hand_gt.png`（持枪手特写）。

### 11.3 基准渲染结论（数据侧全部正常）
- chr_ling005 战斗骨骼（96 骨 / 45 槽 / 4 IK / 16 动画 attack|block|entry|hit|idle|jump|onfoot|sit|sitloop|skill01_1..3|stand|tibu|win|winloop / 单 skin default）在官方 4.1.19 运行时下 setup、stand、idle 姿势全部渲染正确，**持枪手五指、拇指、袖口完全服帖，无任何扭曲**。
- **数据层无染色**：骨骼数据中所有 slot color 与 attachment color 全部是 (1,1,1,1)，龙卡数据层没有任何染色参数。贴图观感以通道序修正后的解码为准（§6）。
- 立绘（s_plotdrawing_ling005）数据存在 base/热更版本错位：基础包的 data 引用区域 `beibao`，而热更版的 atlas（双页 2048x2048）里没有该区域，官方运行时也无法直接加载。这是版本错位，不是提取错误；如需渲染立绘要先找到与 data 匹配的 atlas 版本。

### 11.4 STS2 手部扭曲根因（2026-09-26 当日二次修正；本节早先版本有错误结论，已撤回）

**撤回声明**：本节初版曾断言"mod 转换管线把蒙皮权重全部剥掉（32→0）"——该结论**错误**，原因是测量方法不对（Spine JSON 的蒙皮数据就存在 `vertices` 字段里，加权形态是超长数组，没有独立的 `weights` 键，用 `"weights" in att` 判定必然全 0）。改用 `len(vertices) vs len(uvs)` 重新测量后确认：mod JSON 中 32 个加权网格与原版一一对应完整保留（`zero_zuo_z` vertices=1398 载荷）。同批撤回的还有"让 spine-godot 直接加载 4.1 .skel"的修复建议（checkVersion 要求版本串以 4.2 开头，4.1 二进制会被直接拒绝，见 STS2 报告 §9.2）。

真实根因（三个，全部已修复，完整证据链见《Spine渲染基准与STS2转换修正实验报告.md》）：
1. **调速未缩放曲线控制点**：4.1 二进制/4.2 JSON 的贝塞尔控制点是绝对 (time,value) 对；`tune_for_sts2` 只缩放关键帧 `time` 不缩放 curve 里的时间分量 → 控制点飘出段外 → 插值过冲 → 手指/武器链（旋转幅度最大）在动画中段剧烈撕裂（恰在关键帧上时数值正确，极具迷惑性）。
2. **deform 附件引用解析错误**：二进制里 deform 的附件引用是字符串表引用（官方 `readStringRef`），发射器误当槽内索引 → 越界静默丢弃，idle 的 4 条雕型（右袖口/眉/拇指/眼）全灭。
3. **noScale 骨骼未补偿**：骨架 5 根 `inherit=noScale` 骨骼（bone6=头、bone9=拇指+枪链、bone12=左手、bone43/46）不继承父级缩放，root×N 调校时保持原大小 → 头/手/枪比例异常（用户所见"头部大小异常"的直接原因）。
- 另经 1:1 对照（无调校转换 vs 原版，官方双运行时渲染）确认：**转换器本体忠实**（逐像素一致）；放大到挥臂中段（如 idle t=1.0）仍可见的锯齿是**原始数据本身的瞬态网格分离**，原版二进制同样如此，非转换问题。

## 12. 材质链路与渲染逆向（2026-09-26 起）

### 12.1 iguf 单元格式勘补

对本机 `com.zulong.drc.gw/files/ingameupdate/iguf_00.dat`（f=0 卷，2,146,826,183 B）实测：

- **前缀 `[58 af 5a 00]` 后的 u32 是小端**，Type-A（zstd 字典块）下该值 = 单元**解压后总大小**（与块头 total 字段相同），**不是跨度**；单元实际跨度 = 8 + 4(magic) + 2+4+4+4+4(头) + payload。
- **头部字段为小端**（ver u16 / total u32 / chunk u32 / dict_decomp u32 / dict_comp u32）；§4.1 的偏移表若把 4 字节 magic 先读掉，全部字段要 +4 重排（§4.3 坑位 1 的另一面）。
- **dd>0 时字典段本身是一层 zstd 帧**，需先解压一次得到字典本体，再 `ZstdCompressionDict(字典本体)` 解数据帧；直接拿压缩帧当字典会报 Dictionary mismatch。
- **存在第三类单元：裸存储**（头既非 `4D25EDBC` 也非 `BKHD`，如 sig `00000020`、`06000000`），前缀 u32 = 裸数据长度，跨度 = 8+total。bnk（BKHD）同理：跨度 = 8+total。
- 全卷遍历器要点：跨度不匹配时在预期位置 ±1~4KB 窗内重同步 `58 af 5a 00`；**禁止**用「下一位置必须紧跟已知 magic」做否决（bnk/裸单元会误杀），也**不要**从压缩载荷里反向找前缀（误匹配会造成原地打转）。

### 12.2 配置与材质实例链路（数据事实）

- `cmaterialrescfg.bny`（3393 B）布局：**41 条 ×16B 定长记录（大端 [id][materialResType][resPath][preCookType]）+ 大端 varint 前缀字符串池（39 条路径）+ 尾部 12B 结尾**。resPath 是字符串池下标。
- CSpineResCfg 101190006（破军形态记录，materialId=104200006）→ CMaterialResCfg 记录 104200006 = (type=2, resPath=strings[4] = `ParentMaterials/MaterialMasters/SpineMaterials/M_UI_TEST_Inst`)。该材质实例不在基础包，在热更 iguf 卷内（已切出 `unpacked/spinemats/M_UI_TEST_Inst.uasset/uexp`）。
- **FPropertyTag 终版布局（字节级全验证，parse_mi_final.py 通用化）**：`[FName name 8B][FName type 8B][i32 size][i32 arridx][type-specific][u8 hasguid][FGuid 16B if 1][payload]`；type-specific：Struct/Array→inner FName 8B、Byte→枚举 FName 8B、Bool→u8 值；**Struct 型 tag 在 hasguid 后恒有 16B GUID 块**（无 guid 时为零）。Array 载荷 = `[i32 count][49B 包络 tag][count × 元素]`，元素=成员 tag 流（ParameterInfo→ParameterValue→ExpressionGUID→None）；**None 终止符 = 8B**。M_UI_TEST_Inst 的 uexp 是 bUnversioned=True 但保留 FPropertyTag 的混合格式，CUE4Parse 全版本解不出，须手拆。
- **M_UI_TEST_Inst 参数真值**（materialId 104200006，`unpacked/spinemats/m_ui_test_inst_constants.json`）：标量 DarkenRatio=0.7、RenderOpacity=1、DistorTime=0、DistorUOffset=0、ScanLineOpacity=0.5、ScanLineScale=134.225、ScanLineSpeed=0.003、ScanLineWidth=0.3、RefractionDepthBias=0；向量 **MixColor=(0.071,0.620,0.766,0.171)**、**ScanLineColor=(0.491,0.739,1.0,0.0)**；纹理 SpriteTexture→导入项；BasePropertyOverrides：TwoSided=true、BLEND_Translucent、MSM_Unlit、OpacityMaskClipValue=0.3333。
- **MI 标量→uniform 直拷实证**：subuv_ui_ui_322_02 的 HighLightArea=0.307937 与运行时实测 uniform 七位有效数字全同、AnimSpeed=2.5 同——MI 标量原样进 uniform，无图变换。
- **使用范围（源码级）**：带材质的 CSpineResCfg 101190001-19（→104200006）只被 102590001-21 无名调试外观引用；**全部正式外观 display/fight 记录 materialId=0**；`view_appearance_fight_spine_hologram` WBP 的 SpineWidget 内置 `NormalBlendMaterial=M_UI_TEST_Inst`（dump 实证，Atlas/SkeletonData=Nuonuo001 占位，运行时被 Lua SetSpineID 替换；非 hologram 变体=UI_SpineUnlitNormalMaterial）——p215 家族的正式用途=试衣间战斗骨架预览的"全息"滤镜，与战斗主公式同族（见 §12.7）。
- **战斗材质 BP**：全部 13 个角色 BP（chr_*_bp.uasset）同一模式——SpineSkeletonFastRenderer.`NormalBlendMaterial=MySpineLitNormalMaterialV2` + AnimationComponent.`NormalAtlas=[chr]_mask-atlas`。链路 appearanceId→CAppearanceCfg.modelAppearanceCfgid→CModelAppearanceCfg.modelCfgid→CModelCfg（tintColor1..6 **全表 473 有效记录全零**）→CModelResCfg.resPath=BP（fightutils.lua:212-227）。
- **V2 材质资产事实**（myspinelitnormalmaterialv2）：BLEND_Translucent+MSM_SQEquip+TwoSided；22 标量+4 向量默认（CachedExpressionData：Background Color Intensity=0.3、Exp R/G=1.0、**Value R/G=0.0**、Sub Jitter Ratio=0.5、Scan Line Speed=0.1、Num Scan Line=30、Tilling=10、Mask Layer=3、LightScale=1.0、darkenParam=1.0、Period=3.0；向量 Pan Speed=(0.1,0.1,0,1)/Scan Line Color=(0.35,0.67,1,1)/Color=(0,0,1,1)/OverrideNormal=(0,0,1,0)）；函数链 MF_Demon4Spine/MF_SpineJitterGlitch/ColorDarkenFunc/MF_LightenOrDarken/MF_SimplePointLight(s)+MPC(DarkenMPC/PointLight)。Value R/G=0 → **静态默认态脉冲关闭**（脉冲=运行时覆盖驱动的演出效果）。
- **V2 uexp 内嵌 13 个 20B 哈希（@0x5262/0x7c84）与 shadercode 文件名精确匹配（9 FS+4 VS）——但该清单不含实际运行的战斗变体**（实机捕获按特征行匹配另锁 u066941，见 §12.7）；材质参数→uniform 槽位映射由运行时 FS 声明决定，不能按离线变体块名想当然。
- **MPC 真值**（res_parentmaterials/mpc 五件）：PointLight 双灯默认关（LightAPosAndRadius=0，橙灯 (12.29,−0.218,0,238) 仅技能期由 pointlightctrlactionhandlerimpl.lua 经 GameUtil.SetVectorParameterCollection 写入）；DarkenMPC MaxDarkenAlpha=0；LightParam 全组（DirectLightColor=(1,1,1)、IndirectLightColor=(0,0,0)、CharacterIndirect/DirectLightScale=1.0）。静止态画面=纯材质公式。

### 12.3 shadercode 包与 GLSL/资产全量提取

- **shadercode 全量解包**（tools/dump_all_shaders.py）：86154 个 .ushaderbytecode（SHA1 名，LZ4 块压缩，偏移 9 起解）全部解开（0 失败）→ **LSLGSP 容器**（魔数+顶点输入语义反射元数据+完整 GLSL ES3.1 源码，`}\n\n\0` 收尾）→ **77739 份字节级唯一 GLSL**（FS 62533 / VS 15083 / OTHER 124）+ `unpacked/reversed/shaders_index.csv`。战斗特效的"代码"主体即此。
- **uasset 通用反序列化**（tools/ue4_dump.py）：导出表（TotalHeaderSize@0x18、ExportCount/Offset@0x39/0x3D；导入 28B/条；导出核心字段 Class@0/Name@10/Size@1C/AbsOffset@24=头长+uexp 内偏移，相邻连锁可自动探步长）+ tagged 属性流（布局同 §12.2）+ 8KB 窗口 resync 容错。**16663 资产 0 失败** → properties/ 12 类目录可读文本 + `materials/instances.csv`（16262 行 MI 参数真值）。
- **普查定案：无逻辑蓝图**（无 K2Node/字节码资产；382 个 WidgetBlueprintGeneratedClass=UMG 控件树+MovieScene 动画）→ 战斗逻辑在 wLua；UE4 侧"代码"=GLSL+材质图残留(CachedExpressionData)+Cascade/自研 UIParticle(560)+控件树+LevelSequence；音频 Wwise 10118 事件/Bank 637。

### 12.4 Lua 与 libUE4 全量反编译

- **res_lua 20819 个 Lua5.1 字节码 100% 反编译** → `unpacked/reversed/lua_source/`。工具 tools/LuaBatch.java（unluac.Main.decompile 公有静态方法，单 JVM 批量，3 分钟）+ tools/build_luabatch.py。索引三件套：lua_index.csv / lua_functions.csv（84812 函数定义）/ lua_requires.csv（71929 require 边）。
- **libUE4.so（ARM64）全量反编译** → `unpacked/reversed/ue4src/`（798MB）：Ghidra headless（工程 `D:\dragonraja_cap\ghidra_proj\DRC`，**从工作区 libUE4.so 导入、同源**）分析 416,695 函数后，tools/ghidra/DRCDecompileAll.java 单 JVM 16 线程 24G（GHIDRA_HEADLESS_MAXMEM）414 fn/s、20.5 分钟全量导出 **411,402 份函数 C**（103 分块，RTTI 类名可 grep）+ functions_index.csv + **callgraph_edges.csv（820,535 调用边=调用链主索引）**。25 失败=_INIT_* 静态巨表/libpng/harfbuzz（无游戏逻辑）。查询三轴：地址 grep `FUNC addr=` 分块、名字查 index、调用链 BFS callgraph。
- **Ghidra 工程教训**：反编译里 FName 字面量直接可见（第二 ASCII 表区）；rodata 文件偏移→vaddr delta=+0x10000；capstone ADRP 21 位符号扩展阈值=1<<20；headless 默认堆 8 线程必 OOM（16 线程须 ≥16G）；AARCH64 cspec=default、勿加 -analysisTimeoutPerFile 0。

### 12.5 顶点色与骨架数据事实

- **染色属性=组件 Color**（Ghidra）：FUN_070a8ff0=把 Lua 配置的 Color 属性应用到 SpineSkeletonRendererComponent 的 wLua 反射 thunk（原生侧零调用者）。res_lua 全 LuaJIT 字节码（grep 需 -a）；confbean 全表扫底无 spine 颜色字段；**chr_ling001/ling005 骨架全部 slot color=0xFFFFFFFF、动画无 rgba 时间轴 → COLOR0=白**（恒等项）。
- **顶点色=三乘积**（UpdateMesh 0x70bc048/0x70b25f0）：`COLOR0 = Skeleton.color × Slot.color × 附件色`（saturate 后 u32 打包）；UV1/UV2=darkColor 双色暗通道。渲染器成员 FLinearColor +0x71c（默认白）→ Skeleton.color；Spine 簇（0x70b0000-0x70d0000）内 SetVectorParameterValue=0 处，5 个 MID 创建函数只设纹理+darkenParam/Rongjie 标量。
- **mask 图集结构**（chr_ling001_mask）：与 base 图集 64 region 边界完全一致；R=区域参与度剪影、G/B=逐区域双向梯度场、A=区域选择；mask-atlas 的 .uasset 内嵌 UTF-16 .atlas 原文（region 名=骨架附件名，可离线换算 UV）。ling005 的 mask 包（models/characters/ling005/chr_ling005-mask-atlas）尚未从 UE4 包导出。

### 12.6 GLES 拦截垫片（捕获基建）

详见《基于垫片的龙卡UE4运行时捕获.md》。要点：
- **环境**：MuMu 15（Android 15，adb 16384，adb root 可用）；游戏数据播种免热更；Google 官方模拟器黑屏（只暴露 GLES3.0，游戏要 3.1）。
- **部署**：`adb root` + `setprop wrap.com.zulong.drc.gw 'LD_PRELOAD=/data/zh/h.so'`（属性值 ≤92 字符；MuMu 属性会重置，游戏自行重启后需重设并验证 /proc/pid/maps 含 h.so）；库放游戏内部目录（/data/data/<pkg>/…）可存活，/data/local/tmp 会被 zeus 反篡改 ~2s 毁栈自杀（rip=0x13 rsp=0 rax=rdi=0x13）；日志必须写应用内部存储（/storage FUSE 早期不可写）；Git Bash adb push 需 MSYS_NO_PATHCONV=1。
- **垫片三代**（render_work/glshim/glshim.c → glshim2.c）：v1 基础 uniform/SRC/draw 钩子；v2 uniform 数组全量记录+VATTR 顶点转储+TEX 大纹理转储；v3 增 glCompressedTexSubImage2D 钩子、BINDTEX 记录（ps0 绑定）、first_dump 无条件预算 96（修复 map_broken 全局停用）。SRC 行后跟完整源码——运行时 FS/VS 真身可直接从日志切出。
- **垫片崩溃史（定案）**：glShaderSource 钩子把同一缓冲存入 ring_src[slot] 与 last_src，槽位碰撞 double free → Scudo abort（"invalid chunk state"）——**黑材质与登录阶段退出同源**，修复=删除 last_src 死代码。历史"SDK 阶段被杀"记录为此误诊。glMapBufferRange 读顶点缓冲会卡死 goldfish GL 前端，禁用；顶点数据走 glBufferData/glBufferSubData CPU 侧指针或 VATTR。
- **编译**：`/d/dragonraja_cap/android-ndk-r26d/toolchains/llvm/prebuilt/windows-x86_64/bin/x86_64-linux-android21-clang -shared -O2 -fPIC -llog`。
- **RenderDoc 不可行**（x86_64 宿主）：官方安卓组件仅 arm32/arm64；宿主注入钩不到 gfxstream 自载 EGL。

### 12.7 运行时程序与公式（源码事实）

- **程序统计（DRAWE 行）**：战斗段主力=prog 4/32/237（另一局 4/32/258——**p215 家族 FS 每局 handle 复用**，按 SRC 3473B 特征识别）；prog 32=UI_SpineUnlitNormal 直通 FS（rgb=顶点色直通，ps0 只乘 alpha）；**prog 978 仅 584 帧=过场演出段**（其 FS=u066941.glsl，非战斗公式）。
- **p215（战斗+试衣间共用）FS 公式**（runtime_prog215_sh214.glsl）：
  `out = encode_srgb( max((A − base.rgb)·w + base.rgb·COLOR0, 0) )`；`a = clamp(A·COLOR0.a·Opacity)`。
  w=马赛克(TEXCOORD1.zw, cell=256−128·pc1_h[0].x)：wx=mod(z,cell)/cell、wy=(trunc(z/cell)·16+trunc(w/cell))/256、wz=mod(w,cell)/cell。
  运行时真值：pu_m=(1,0.454545,0,1)+(0,0,0,0) → **encode ON、contrast OFF、desat OFF**（双场景一致）；战斗 pc1_h[0].x=1.0→cell=128，试衣间=0→cell=256。
- **VS 事实**（p258_sh67/p292_sh40/p81）：`COLOR0 = srgb2lin(in_ATTRIBUTE3).zyxw`（精确分段解码+BGR 重排）；`TEXCOORD1 = in_ATTRIBUTE0 直通`；TEXCOORD0/ORIGINAL_POSITION=裁剪投影屏幕坐标。顶点布局 44B：4f pos + 2f uv + 3f 屏幕px + 4u8 color（COLOR0@[36:40]）。
- **TEXCOORD1.zw 来源**：顶点填充函数 param_9"辅助数组"（2f/顶点，源=attachment 级 HashMap）——逐顶点数值的生成公式未到叶子（唯一开放项）；TEXCOORD1.zw 为 [0,1] 级 UV 时 w≈0.004，反色项数值可忽略。
- **u066941（演出段 FS）**：`v37=mix((1,1,1)−base.rgb, 0, shadowRamp)`（漫反射体色=贴图反色，COLOR0.rgb 未读）+反射探针（ps1=samplerCube）+镜面/雾；运行时 pc5_h[0]=(1000,10000,0.5,1.0)（DarkenMPC 结构被运行时改写，资产 Near/Far/MaxAlpha=50/1024/0）。源文件 `unpacked/reversed/shaders/unique/u066941.glsl`。
- **渲染管线 13 环**（5 代理 A-E，报告 `ue4src_analysis/pipeline/`）：V2 uasset 默认→preshader 求值（EvaluateUniformExpressions=0xa0fe0a4/VM=0xa127bc0/FillUniformBuffer=0xa129b5c）→MPC 注入（GameThread_UpdateContents=0xa12dffc；pc2_h=PointLight、pc3_h=DarkenMPC；写入端 Lua 0x6e29418/天气 0x6d9a960/Sequencer 0x95ba2e4）→顶点缓冲（CreateMeshSection=0x661cf34）→四混合两级分批→RenderTranslucency=0x8f77f20→上传（CommitPackedUniformBuffers=0xab4251c，GLES 模拟 UBO 逐成员 glUniform4fv）→draw=0xab142c4→混合态（Normal=SrcAlpha/InvSrcAlpha 等）→输出。pc0/pc1 语义表与 Azure 替换光照链见 D 报告。
- **输出色彩路径（实机修正）**：全部捕获 **0 命中 tonemap 程序**——本作移动端 MobileHDR off，场景直接写 sRGB 面（硬件编码），**材质内 sRGB encode 即最终色**；E 报告的 filmic tonemap+眼适应链路适用于 HDR 分支，不在此路径。

### 12.8 纹理溯源与通道序 bug（定案）

- **溯源标准流程**：捕获 TEX 行（v3 钩子覆盖 Compressed/Sub 上传）→ ASTC 解码候选 → 压缩载荷前 48B 指纹全库搜索 → 载荷逐字节对拍。
- **结果**：tex827（1024×512 ASTC6x6，235296B=14706 块）= `res_models/characters/ling001/textures/chr_ling001.uexp` @382；captured 载荷与 uexp 载荷 **0.00% diff**；修复解码器后与 uexp 解码 **maxdiff=0**。实机渲染输入=解包同源。
- **通道序 bug**：texture2ddecoder.decode_astc 输出 BGRA，旧 decode_astc_texture 未重排 → 全项目解包 PNG 红蓝反转（§6）。修复已入 build_ling_assets.py；extract_cache 与 resources/ 的旧 PNG 为反转变体，需要时用 `tools/iguf_extract_asset.py --png` 重提。
- **ling005 重提实证**（2026-10-01）：`models/characters/ling005/textures/chr_ling005.uexp`（vol0 pos=439238788，单元表 [0,439238788,117393,235706]）→ 修复解码 → 1024×512 图集自洽（lanse_z 区域实测 B>R=蓝，与 region 名相符）；旧 extract_cache/resources 版与正确解码差异远超通道序（旧提取管线另有位移类缺陷），以新解码为准。

### 12.9 渲染定案与 STS2 终态

- **手游战斗/试衣间观感 = 通道正确的贴图直出 + 光照**。p215 在战斗参数下（C0=白、w≈0.004）数值上退化=直出；公式保留的活性项（镜面/反射探针/雾/扫描线）属光影层，是后续移植方向。
- **正式路径不存在逐皮肤染色逻辑**：materialId 全 0、Lua 零常驻颜色干预、MID 创建 0 颜色参数、CModelCfg tintColor 全零、顶点色三乘积全白。
- **STS2 侧终态**（已装 mods）：
  - `LingSilentSkin.pck`（ling001）：贴图=captured_tex827（实机同源、通道正确），`tools/build_battle_pck.py`。
  - `LingUrbanSkin.pck`（ling005）：贴图=iguf 重提+修复解码（`tools/build_urban_pck.py`；页名沿用 Chr_ling001.png 复用导入链）。
  - `DRCSpineDye`（框架）：pcksrc 只保留 p215 逐行移植的 ling_holo 四变体（w_scale=0=直出，公式结构保留可复现流光）+ config.json；`tools/build_drcspinedye_pck.py`。框架作为后续光影 pass 的挂载点。
- **验收观测点**：`%APPDATA%\Roaming\SlayTheSpire2\logs\godot.log`（[DRCSpineDye] 日志链）；sentry minidump 在 `%APPDATA%\Roaming\SlayTheSpire2\sentry\reports\`。

### 12.10 已排除路径（游戏侧事实，防止重复排查）

- 无逻辑蓝图；战斗逻辑全在 wLua。
- 战斗 Lua 对普通在场单位零常驻颜色干预（SetBlendMaterial 仅死亡/镜像/服务器 override/技能四条件触发且可还原；SetColor/SlotColor/Tint 语料零有效命中）。
- libUE4.so 全文无 MixColor/ScanLineColor 等参数名字符串（参数注入不走名字字面量）；Spine 簇内 SetVectorParameterValue=0 处。
- 全部正式外观 materialId=0；M_UI_TEST_Inst 只挂 102590xxx 调试外观。
- V2 uexp 内嵌 13 哈希清单≠运行时实际变体（材质实例值≠运行时 shader 身份）。
- shadercode 包 StateId 0 命中（包里只有单 shader 无 map）。
- 染色区域选择不依赖权重文件；mask 图集通道服务流光/脉冲类效果，与"哪些区域变色"无关联语义。

### 12.11 光影层机制考证与移植（2026-10-01，计划与首轮实现见 光影层移植计划.md）

- **死亡溶解**：死亡流程=换装 `MySpineLitDissolutionMaterial`（FIGHTER_DEATH_RES_CFGID）→ `PlayFightBuffFx(FIGHTER_DEATH_DISPLAY_EFFECT_CFGID)`（通用死亡特效=`res_effects/particles/scene_fx/common/fx_die`，发射器 Zhu/球域/峰值 51 粒）→ 音效 → `SetEmptyAnimation(0, 0.05)` → 定时器 **0.5s 内 Rongjie 1.2→0 线性**（fightconsts.lua DieDuration/DieRongJieStart/DieAnimBlendTime=0.5/1.2/0.05）→ `_OnDieAnimFinish` 隐藏（fightunitfighter.lua:1518-1565，SetDissolutionParam→FightActor:296→SetDissolutionParamForMIDs）。
- **溶解材质**：`myspinelitdissolutionmaterial(+_inst)`（spinematerials/）参数=LBKuandu/RongjieIntensity/Height/Rongjie/VScale/Width/UScale/darkenParam+向量 liangbian_color；噪声贴图=`ParentMaterials/DefaultTexs/DRCDissolutionNoiseTexture`（512² ASTC6x6 暗色斑块，已解码）；shader map=22 哈希 @uexp 双拷贝（V2 同构，方法复用），源码存 `render_work/dissolution_shaders/`。移动端 lit 变体 68642e51 逐行：**ps1=世界坐标投影噪声**（pc1_h[1..4] 矩阵变换世界位→pc5_h[1] 缩放 UV）、阈值 pc5_h[2].z、双门 ceil+discard（门控 pc5_h[3].y·alpha<1/3）、边缘=mix(→pc5_h[0].xyz=liangbian_color)；ps2=法线页、ps3=反射立方体、漫反射体色×DarkenMPC 坡道（同 u066941 结构）。
- **影子**：战斗地图级 RT 影子（battlefield.lua:70-73 `InitMapRTShadowSettings`/`_RTShadowManInScene`，RTShadowReinitInterval=0.5）+ `scene:EnableShadowReplaceParam(-540,0,0,900)`；texdump 91 张 ASTC 无独立影斑贴图 → 影子=角色渲染目标投影，非贴图斑。
- **STS2 首轮移植（已装）**：ling_holo 四变体追加光照 uniform 层（点光/环境加色/雾/压暗/受击闪红，增益默认全 0=直出不变）；`ling_dissolve_mix`（噪声阈值 discard+liangbian_color 边缘带，cut 0→1 等效 Rongjie 1.2→0 的侵蚀方向）；DyeFramework v2=影子 blob 层（RT 投影的 STS2 近似）+ DeathWatcher（animation_started 监听 die→换溶解材质→0.5s tween→CPUParticles2D 上飘光点→还原）；config.json 全参数化。待游戏内验收（第十六次协议见计划文档）。

### 12.12 方法论与工程教训

1. **渲染输入验证先于公式研究**：贴图/纹理绑定（载荷逐字节对比）一击定位通道序 bug——本应在任何公式假设之前做。
2. **显示管线的误解会伪造"贴图内容"**（通道序、色彩空间、翻转取向）；region 名、文件名、历史叙事都不可作为数据证据——唯字节与逐像素对拍可信。
3. **截图反解数值不可信**：少方程多未知数欠定，且可能抓到已处理的中间态；数值只能从公式/资产/源码推出。
4. 子代理的公式摘要不可直接照搬移植——必须拿原始 GLSL 逐行核对。
5. FV4 数组的 uniform 归属必须以运行时 SRC 声明的 uniform 块为准，不能按离线变体的块名想当然。
6. Godot shader 无 hsv() 内置；新 shader 上游戏前先 Godot headless 解析；canvas_item 的 fragment COLOR 初值=texture×顶点色（双重乘），顶点色需 vertex() varying 捕获。
7. Ghidra headless：GHIDRA_HEADLESS_MAXMEM≥16G（16 线程 24G=414 fn/s）；Mimosa hook 拦截 Bash 直写源码，一律走 Write/Edit。
8. MuMu wrap 属性会重置；每次捕获前 setprop 并验证 maps。
