# ue4src_analysis —— libUE4 反编译 C 逐文件解析战役

日期：2026-09-29。目标：103 个 part_*.c（416,695 函数）按文件逐一解析出描述文档，
用于支撑战斗渲染链（贴图原色↔纯黑正弦脉冲）的最终源码定位。

## 结构

- `_profiles/part_NNNNNN.json` —— 剖析器（tools/profile_ue4src.py）自动档案：
  函数数/地址域/Top 符号(::)/字符串字面量/战斗相关关键词计数/最大函数。
- `_index.csv` —— 按战斗相关度排序的总表。
- `<模块>/part_NNNNNN.md` —— 每个代理对一个 C 文件的描述文档，front-matter：
  file/module/relevance。模块分类：spine_render / materials / particles_vfx /
  mesh_geometry / ui_umg / animation / audio / network / engine_core / misc。

## 描述文档最小要求

1. 概况：函数数、地址域、主类/命名空间。
2. 关键函数 10-30 个（按体量/API 密度选取）：addr、size、用途推断（必须实读代码）。
3. 字符串要点。
4. 战斗渲染相关性：Spine/材质/顶点色/颜色参数/脉冲闪光相关函数逐个给 addr+证据。
5. 附 `part_NNNNNN_func_index.csv`：全部函数 addr,size,一句话备注（仅前 30 必填）。

## 任务状态

- 波次与认领见 `_state.md`。
- 每文件一个代理，禁止一个代理吞多个文件。
