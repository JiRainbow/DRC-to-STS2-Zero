# 基于垫片的龙卡UE4运行时捕获

LD_PRELOAD 拦截垫片 → 运行中的龙族手游（MuMu Android 15）→ 提取运行时 uniform 常量、着色器源码、顶点块与纹理上传。所有结论以源码/资产侧交叉验证为准（iguf热更包解包实验记录.md §12）。

---

## 1. 结论速览

| # | 结论 | 证据 |
|---|---|---|
| 1 | 运行时 FS/VS 真身可从日志直接切出：`SRC <prog> <sh> <len>` 行后跟完整 GLSL 源码 | pass1-3 共 500MB+ 日志，132+ shader 源码 |
| 2 | 战斗+试衣间共用 p215 公式：`out = encode_srgb(max((A−base.rgb)·w + base.rgb·COLOR0, 0))`，w=屏幕位置马赛克（战斗 cell=128、试衣间 256） | DRAWE 程序统计 + FV4 统计 + SRC 源码 |
| 3 | COLOR0=白（顶点色三乘积×骨架全白）；VS 做 `srgb2lin(ATTRIBUTE3).zyxw` 解码+通道重排 | VATTR 顶点块 + Ghidra UpdateMesh + VS 源码 |
| 4 | 贴图溯源：捕获上传的战斗纹理载荷与基础包 chr_ling001.uexp **逐字节相同（0.00%）**——手游观感=贴图直出+光照，无染色 | TEX 行 → ASTC 指纹 → 载荷对拍 |
| 5 | RenderDoc 路线在 x86_64 宿主不可行：官方安卓组件仅 arm32/arm64；宿主进程注入钩不到 gfxstream 自载 EGL | §3 |
| 6 | 反篡改（zeus/volcengine）对 `/data/local/tmp` 路径的 preload 在 ~2s 毁栈自杀（rip=0x13 rsp=0 rax=rdi=0x13）；**游戏内部数据目录路径可存活** | §5.3、§5.4 |

## 2. 实验环境

| 项 | 内容 |
|---|---|
| 宿主 | Windows x64，AMD Radeon 880M |
| MuMu 模拟器 | 15.0（MuMuNx 架构），`D:\Program Files\Netease\MuMu`，**Android 15**，ABI = x86_64,arm64-v8a,x86 |
| adb | MuMu 自带 `nx_main/adb.exe`；`adb connect 127.0.0.1:16384` |
| root | **adb root 直接可用**（MuMu 镜像 userdebug/dev-keys）；另装 KernelSU |
| NDK | r26d（仅解 bin + sysroot + lib/clang 三段即可编译） |
| 龙族客户端 | base.apk 976MB（libUE4.so arm64 203MB / x86_64 214MB），版本 2.1.4.30617 |

## 3. 前置失败路线（防止重复踩坑）

### 3.1 RenderDoc 安卓捕获
- 官方安卓组件仅 arm32/arm64 APK；x86_64 模拟器 `INSTALL_FAILED_NO_MATCHING_ABIS`。
- 宿主进程注入（`renderdoccmd inject --PID=<qemu>`）：qemu 启动即退出（CreateProcess-suspended+注入与客户机内存布局冲突）；对已运行 qemu 附着成功但抓不到帧——gfxstream 宿主侧走自载 ANGLE/EGL，opengl32 钩子不适用。
- arm64 系统镜像路线：官方模拟器明确拒绝跨架构。

### 3.2 Android Studio 官方模拟器（google_apis x86_64）
- 游戏可安装、可启动、可自动登录；资源校验通过（种子免下载 ✓）。
- **黑屏根因**：游戏检测 GLES < 3.1 拒绝渲染；goldfish 栈（host/swiftshader）只暴露 ES 3.0。
- 游戏必须在**系统完全启动后**拉起；数据播种**逐顶层条目 push**（整目录 push 会产生 `files/fi/...` 嵌套错误结构）。

### 3.3 静态路线的边界
- 四个 libUE4 变体均无 MixColor/ScanLineColor 等参数名字符串；`.symtab` 已剥除（仅 .dynsym 引擎符号）。
- 材质 uexp 的 uniform 缓冲全零（熟化剥除默认值）。
- 结论：**运行时行为必须动态捕获**；静态侧走 Ghidra 反编译（iguf 记录 §12.4）。

## 4. MuMu 环境搭建（复现命令）

```bash
# 1) MuMu 开启 ADB（设置→其他→USB调试/ADB），或直接：
"/d/Program Files/Netease/MuMu/nx_main/MuMuManager.exe" control -v 0 launch
"/d/Program Files/Netease/MuMu/nx_main/MuMuManager.exe" adb -v 0        # 返回端口 16384
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
"$ADB" connect 127.0.0.1:16384
"$ADB" -s 127.0.0.1:16384 root                                           # MuMu 支持 adb root
# 2) 安装游戏
"$ADB" -s 127.0.0.1:16384 install -r -g base.apk
# 3) 播种数据（免热更下载；逐顶层条目 push）
cd com.zulong.drc.gw/files
for item in *; do "$ADB" -s 127.0.0.1:16384 push "$item" "/storage/emulated/0/Android/data/com.zulong.drc.gw/files/$item"; done
# 4) 授权运行时权限（SDK 初始化需要）
for p in READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE READ_PHONE_STATE CAMERA POST_NOTIFICATIONS; do
  "$ADB" -s 127.0.0.1:16384 shell pm grant com.zulong.drc.gw android.permission.$p; done
# 5) 部署垫片 + 设置 wrap + 启动（每次启动前重设——MuMu 属性会重置）
"$ADB" -s 127.0.0.1:16384 push glshim2.so /data/zh/h.so     # Git Bash 需 MSYS_NO_PATHCONV=1
"$ADB" -s 127.0.0.1:16384 shell setprop wrap.com.zulong.drc.gw 'LD_PRELOAD=/data/zh/h.so'
"$ADB" -s 127.0.0.1:16384 shell monkey -p com.zulong.drc.gw -c android.intent.category.LAUNCHER 1
# 6) 验证垫片已加载
"$ADB" -s 127.0.0.1:16384 shell "su -c 'cat /proc/$(pidof com.zulong.drc.gw)/maps' | grep -c h.so"
```

**关键实证**：种子数据被服务器版本校验直接接受（`DirClient::OnRecvProtocol 7101` → 无下载动作）→ 离线播种方案成立；自动登录成立。

## 5. GLES 拦截垫片（核心工程）

### 5.1 设计
LD_PRELOAD 微型库，只定义需要监视的符号（`glUniform*`、`glShaderSource`、`glAttachShader`、`glUseProgram`、`glDraw*`、`glBufferData/SubData`、`glCompressedTexImage2D/SubImage2D`、`glBindTexture`）；**其余 gl 符号按 ELF 插拔语义自动落回真库**——零转发成本、零遗漏。真库通过 `dlopen` 副本解析（避免符号自指递归）。

三代演进（`render_work/glshim/glshim.c` → `glshim2.c`）：
- v1：uniform/SRC/draw 基础钩子。
- v2：uniform 数组**全量**记录（此前只记首个 vec4 会漏同调用的后续元素）；`glGetVertexAttribiv/Pointerv` 绘制时查属性布局（VATTR 行=完整 44B 顶点块）；TEX 大纹理上传转储（compressed 阈值 ≤128KB，ASTC 1024×512≈233KB）。
- v3：glCompressedTexSubImage2D 钩子；**BINDTEX 记录**（ps0 纹理绑定身份）；**first_dump 无条件预算 96**（修复一次 map 失败导致 map_broken 全局停用、战斗段 VATTR 全缺的问题）。

日志行类型：`SRC`（着色器源码全文）、`FV4`（uniform 数组提交）、`VATTR`（顶点属性/顶点块）、`TEX`（纹理上传，header 后紧跟 hex 载荷，需 m.end() 定位）、`DRAWE`（绘制程序统计）、`BINDTEX`（纹理绑定）。

### 5.2 部署形态（存活条件）
| 形态 | 结果 |
|---|---|
| `wrap` 属性 + `/data/local/tmp/*.so` | 垫片加载成功，但 zeus 反篡改 ~2s 毁栈杀游戏（rip=0x13 rsp=0 rax=rdi=0x13） |
| **`/data/zh/h.so` 或游戏内部数据目录路径** | **存活 + 捕获成功** |

**属性值上限**：`wrap.<pkg>` ≤ 92 字符。**日志路径**：必须用应用内部存储 `/data/data/<pkg>/files/glshim.log`——外部 /storage（FUSE）进程早期不可写，open 静默失败导致整场捕获空转。

### 5.3 ensure_real 三级回退（历史唯一致命 bug 的形态）
```c
static void ensure_real(void) {
    if (!real_lib) {
        real_lib = dlopen("/data/local/tmp/libGLESv2.real.so", RTLD_NOW|RTLD_LOCAL);
        if (!real_lib) real_lib = dlopen("libGLESv2.so", RTLD_NOW|RTLD_LOCAL);          // 系统真库
        if (!real_lib) real_lib = dlopen("/vendor/lib64/egl/libGLESv2_kona.so", ...);   // MuMu 直驱
    }
}
```
首版只有第一级：MuMu 上副本不存在 → `dlsym(NULL,...)` 按 RTLD_DEFAULT 搜索 → 返回垫片自己的函数 → 无限递归栈溢出。

### 5.4 崩溃史定案
| 症状 | 根因 | 修复 |
|---|---|---|
| 大量材质变黑 | glShaderSource 钩子把同一缓冲存入 ring_src[slot] 与 last_src，槽位碰撞 **double free → Scudo abort**（"invalid chunk state"，栈=glShaderSource+409 ← libUE4 Compile*），编译期堆损坏 | 删除从未被读的 last_src 死代码 |
| 登录后自动退出 | 同上（着色器密集阶段碰撞） | 同上 |
| 战斗段 VATTR 全缺 | 一次 glMapBufferRange 失败置 map_broken 后**全局**停用顶点转储 | first_dump 无条件预算；glMapBufferRange 本身禁用（卡死 goldfish GL 前端） |

### 5.5 反篡改对抗记录
| 探测手段 | zeus 反应 |
|---|---|
| `/data/local/tmp` 路径 preload | **~2s 毁栈自杀**（与垫片内容无关——preload 无害系统库副本同样触发） |
| `/data/zh/h.so`、应用内部数据目录 preload | **存活** ✓ |
| 日志文件写入游戏 files 目录 | zeus 创建 `.zeus_i` 完整性监视；内部路径日志未被清除 ✓ |

## 6. 捕获数据的标准用法

1. **着色器真身**：从 `SRC` 行切出源码（`render_work/glshim/srcs2/`、`render_work/battle_capture/*.glsl`），与 shadercode 库（77739 份唯一 GLSL）做归一化/特征行匹配定身份。
2. **程序身份**：DRAWE 行统计每程序绘制次数；p215 家族 FS 每局 handle 复用，按 SRC 字节特征（如 3473B）识别，勿按 handle 跨局比较。
3. **uniform 真值**：FV4 行按程序聚合统计（如 pu_m=(1,0.454545,0,1) encode ON；战斗 pc1_h[0].x=1.0→cell=128）。
4. **顶点块**：VATTR 行=完整 44B 顶点（4f pos + 2f uv + 3f 屏幕px + 4u8 color，COLOR0@[36:40]）。
5. **纹理溯源**：TEX/BINDTEX 行 → ASTC 载荷解码 → 前 48B 指纹全库搜索 → 载荷逐字节对拍（本次即以此定位 chr_ling001.uexp，见 iguf 记录 §12.8）。
6. **解码对拍纪律**：texture2ddecoder 输出 BGRA，任何解码先做通道序处理再比较（iguf 记录 §6）。

## 7. 产物清单

| 文件 | 说明 |
|---|---|
| `render_work/glshim/glshim.c` / `glshim2.c` | 垫片源码（NDK r26d x86_64 编译） |
| `render_work/glshim/srcs2/` | 运行时切出的 FS/VS 源码 |
| `render_work/glshim/uniform_summary.json` | 程序 uniform 提交统计 |
| `render_work/battle_capture/` | v3 全程捕获：日志、切出源码、captured_tex*.png（tex827=ling001 实机纹理）、texdump/ |
| `unpacked/spinemats/` | iguf 切出的材质实例与常量 json |
| `unpacked/reversed/shaders/unique/u066941.glsl` | 演出段 FS（库内归档） |
