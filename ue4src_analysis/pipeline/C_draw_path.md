---
agent: C-segment (Spine mesh CPU fill → GLES draw call full path)
range: part_000003/000008/000012/000015 (0x661-0x662, 0x70b-0x70c) + part_000050/000055 (0x8ec-0x8f7) + part_000067/000075/000079/000081/000082 (0xa09-0xab8)
topic: SpineSkeletonFastRenderer 网格从 UpdateMesh 顶点填充到 OpenGL ES draw 的完整绘制路径（含四混合模式分批点）
---

# C 段：Spine 网格 CPU 填充 → GLES draw call 完整绘制路径

所有地址均实读 `part_*.c` 反编译体确认（标注 § 为证据所在文件/函数）。

## 0. 总链路图（CPU → GPU）

```
[GameThread] SpineSkeletonFastRenderer::UpdateMesh 0x70bc048 (§part_000003)
  ├─ UProceduralMeshComponent::ClearAllMeshSections 0x661e3a8
  ├─ 遍历 slots：spine-cpp 附件分类（region/mesh）
  │    ├─ 调度 0x70c0d30 →（裁剪路径 0x70b2424 / 非裁剪 0x70b25f0）ParallelFor 顶点累积
  │    │    → 组件 scratch（+0x730 / +0x750，6 数组：pos/uv/color/dark/aux/index）
  │    ├─ 按 FUN_07124b70() 返回的混合模式 switch(0..3)
  │    │    → 组件内 4 组"附件去重表"（+0x590 / +0x5f0 / +0x650 / +0x6b0，hash 查重跳过已入批附件）
  │    └─ 批次 flush FUN_070bd350（调度后 commit）
  │         ├─ vtable+0x5d0(this, sectionIdx, batchTag)  — 该 section 绑定对应混合模式 MID
  │         ├─ UProceduralMeshComponent::CreateMeshSection 0x661cf34（调用点 0x70bd460）
  │         │    参数 = sectionIdx, Vertices, Triangles(u32), Normals, UV0..UV3, Colors, Tangents, bCollision
  │         │    （本 build 扩展为 4 UV 通道：UV1=暗色RG、UV2=暗色BA(α=1)、UV3 空；UV0=贴图 uv）
  │         ├─ MarkRenderStateDirty 0x9d70eb8（CreateMeshSection callee，callgraph 实证）
  │         └─ sectionIdx++（每混合批一个 section）
  └─ scratch 清空 FUN_0710721c / FUN_071071e4

[渲染状态重建] CreateSceneProxy 0x661e858 → FProceduralMeshSceneProxy ctor 0x661e88c (§part_000008)
  ├─ 每 section：拷贝 FProcMeshVertex(0x34/顶点) → FDynamicMeshVertex(0x58/顶点) 临时数组
  ├─ FStaticMeshVertexBuffers::InitFromDynamicVertex 0xa4d1524（CPU 打包：位置12B/切线8B-packed或16B-RGBA16N/UV4B-half或8B-float/颜色4B）
  └─ BeginInitResource ×5：FPositionVertexBuffer(+0x90) / FStaticMeshVertexBuffers(+0x08)
      / FColorVertexBuffer(+0xd0) / 索引缓冲(+0x110) / FLocalVertexFactory(+0x138)
      → RHI 创建：OGL RHICreateVertexBuffer 0xab80b70（→TOpenGLBuffer 0xab80d00）
                  OGL RHICreateIndexBuffer  0xab1dd84
      （InitRHI 链：FPositionVertexBuffer::InitRHI 0xa312cd8→CreateRHIBuffer_Internal<true> 0xa312978
        → GDynamicRHI vtable+0x140；FLocalVertexFactory::InitRHI 0xa09cc20→InitDeclaration 0x84dccf0
        → OGL RHICreateVertexDeclaration 0xab82114，声明元素入 GOpenGLVertexDeclarationCache）

[可见性收集] GetDynamicMeshElements 0x66226d0 (§part_000008)
  遍历 sections（可见标志 section+0x348）→ 每 section 一个 FMeshBatch：
    MeshBatch.MaterialRenderProxy = section->Material(→GetMaterialRenderProxy vtable+0x2f8)（= 每槽 MID）
    MeshBatch.VertexFactory = section 的 FLocalVertexFactory(+0x138)
    Element.NumPrimitives = 索引数/3；MaxVertexIndex；FDynamicPrimitiveUniformBuffer::Set（MemStack 一帧分配）

[MeshPass 处理] FMobileBasePassMeshProcessor（mobile 前向）
  TryAddMeshBatch 0x8eced60 → Process 0x8ecf448 (§part_000050)
    ├─ MobileBasePass::GetShaders(lightmapPolicy, ...)（TMobileBasePass VS/PS 模板族 0x8d1dbac BuildMeshDrawCommands）
    ├─ 不透明/蒙版 → BasePass 命令列表
    └─ 半透明 → CalculateTranslucentMeshStaticSortKey 0x8c46be0 生成排序键（priority +0x1000000000000 打包）
       → BuildMeshDrawCommands<TMobileBasePass...> 0x8d1dbac 写入 TranslucentMeshDrawCommands

[Pass 执行] FMobileSceneRenderer::Render 0x8f7321c (§part_000048)
  → RenderForward 0x8f75d44
      ├─ RenderMobileBasePass 0x8efb6a4（不透明/蒙版 → FParallelMeshDrawCommandPass::DispatchDraw 0x8ec52f0）
      ├─ RenderAzureUsingPPRPass 0x8efbeec / RenderAzureOutlinePass 0x8efc07c（祖龙定制 pass，本链旁路）
      └─ RenderTranslucency 0x8f77f20 (§part_000039)
           ShouldRenderTranslucency 0x922e1f0 → GetTranslucencyView(s)
           → TranslucencyPassToMeshPass 0x922d210：ETranslucencyPass→MeshPassId = pass+9（Standard→10）
           → 逐 pass DispatchDraw 0x8ec52f0（半透明 MeshDrawCommand 按 DrawCommandSortKey 已序）
           → RenderTranslucencyBlur 0x8f77d40

[RHI 提交] DispatchDraw 0x8ec52f0 → SubmitMeshDrawCommandsRange → FRHICommandList 执行
  → FOpenGLDynamicRHI::RHIDrawIndexedPrimitive 0xab142c4 (§part_000067)
      ├─ BindPendingFramebuffer/SetPendingBlendState/UpdateRasterizerState/UpdateDepthStencilState/BindPendingShaderState
      ├─ SetupTexturesForDraw / CommitPackedGlobals（uniform 提交）
      ├─ glBindBuffer(GL_ELEMENT_ARRAY_BUFFER=0x8893, IndexBuffer+0x20)
      ├─ SetupVertexArrays 0xab11ed4 (§part_000075)
      │    逐 FVertexElement(0x1c/项，来自 0xab82114 的声明缓存)：
      │    glVertexAttribFormat / glVertexAttribIFormat（integer 属性）
      │    glVertexAttribBinding + glEnableVertexAttribArray
      │    glBindVertexBuffer(binding, bufferName=stream+0x1c, offset)（stride 来自 OGL 流表，由 RHISetStreamSource 0xab0e5a0 维护）
      ├─ 图元类型：CurrentPrimitiveType(this+0x8d4)：PT_TriangleList=0 → GL_TRIANGLES(4)（tess 时 GL_PATCHES 0xe）；PT_TriangleStrip=1 → GL_TRIANGLE_STRIP(5)
      ├─ 索引类型：IndexBuffer+0x14==4 → GL_UNSIGNED_INT(0x1405)，否则 GL_UNSIGNED_SHORT(0x1403)
      └─ glDrawElements(mode, Count, Type, StartIndex*IndexSize)  [thunk 0xb9aa4c0]
          （NumInstances≥2 → glDrawElementsInstanced；非索引路径 RHIDrawPrimitive 0xab13648 → glDrawArrays 0xb9aa470）
```

## 1. 四混合模式的分批点（两级）

| 级别 | 地址 | 机制 |
|---|---|---|
| CPU 分批 | UpdateMesh 0x70bc048 内 `switch(FUN_07124b70())` case 0/1/2/3/default | spine BlendMode(Normal/Multiply/Additive/Screen) → 组件 4 组去重表 +0x590/+0x5f0/+0x650/+0x6b0；同一混合模式的附件累积进同一批次，批次 flush（FUN_070bd350）时占用一个递增的 sectionIdx（`*param_2 += 1`） |
| 材质绑定 | FUN_070bd350 首 vtable+0x5d0(this, sectionIdx, batchTag)；MID 工厂 0x70bbdf8（Create(V2 材质)+SetTexture×2+darkenParam/Rongjie） | 每混合槽一个 MID（Normal/Multiply/Additive/ScreenBlendMaterial），CreateMeshSection 后 section->Material 即该 MID |
| 批次→MeshBatch | GetDynamicMeshElements 0x66226d0 | 每 section 独立 FMeshBatch，材质=该 section 的 MID → 4 混合模式天然拆成 4 类批次 |
| 排序键 | Process 0x8ecf448 半透明分支 → CalculateTranslucentMeshStaticSortKey 0x8c46be0 | proxy 静态排序键（param_4+0x25>>0xf&2 参与优先级），半透明批间按此排序，保证多层叠放顺序 |

UpdateMesh 中的 COLOR0 合成（字节写入颜色数组，0x70bcf00 附近）：
`color = (R*255)<<0 | (G*255)<<8 | (B*255)<<16 | (A*255)<<24`，其中
R=Skeleton.color.r(FUN_070ce360+8)×Slot.color.r(FUN_07124944+8)×附件色，G/B/A 同理（+0xc/+0x10/+0x14）——与 A/B 段结论一致（tint×slot×attachment）。
暗色 RGB 来自 FUN_0712494c(+8/+0xc/+0x10)，拆入 UV1=(darkR,darkG)、UV2=(darkB,1.0)。

## 2. GLES 侧收尾细节（实读确认）

- `RHIDrawIndexedPrimitive 0xab142c4`：先 `GCurrentNumPrimitivesDrawnRHI/GCurrentNumDrawCallsRHIPtr` 计数，绑定 FBO/混合/视口/剪裁/光栅/深度模板态 → `SetupVertexArrays` → glDrawElements。Spine 索引缓冲为 u32（UpdateMesh 写 uint32）→ 走 **GL_UNSIGNED_INT + GL_TRIANGLES**。
- `SetupVertexArrays 0xab11ed4`：GLES3 VAO 风格——每元素 glVertexAttribFormat(size,type,offset)/glVertexAttribIFormat + glVertexAttribBinding + glEnableVertexAttribArray + glBindVertexBuffer；属性表来自 RHICreateVertexDeclaration 0xab82114 缓存的 FVertexElement 列表（0x1c/项：attribIndex/stream/offset/size/type/normalized/integer）。
- FVertexElement 列表的**生产端** = `FLocalVertexFactory::InitRHI 0xa09cc20`（AccessStreamComponent 0x84dc91c）：
  attr0=Positions(stream0) / attr1=Tangents(stream1) / attr2=TexCoordComponent(stream2) / attr3=Color（+0x1b8，空则 GNullColorVertexBuffer）/ attr4+=TextureCoordinates[i]（多 UV）。
  流 stride 由各缓冲类决定：位置 12B（TStaticMeshVertexData<FVector>，FPositionVertexBuffer::Init 0xa3121d8）、切线 8B(FPackedNormal)/16B(FPackedRGBA16N)（AllocateData 0xa34c94c，stride 存 +0x70）、UV 4B(FVector2DHalf)/8B(FVector2D)（stride +0x74，×NumTexCoords=3）、颜色 4B（FColorVertexBuffer::Init 0xa342714 硬编码 4）。
- **关于实测 stride=44 / attrib0=4f+attrib1=2f+attrib2=3f+attrib3=4×u8 的差异标注**：本 build 反编译中该路径（InitFromDynamicVertex 0xa4d1524 + AllocateData 0xa34c94c + FLocalVertexFactory::InitRHI 0xa09cc20）为**多流分离缓冲**（12/8|16/4|8/4），未发现单条 44B 交错缓冲的写入代码；且 stock 声明映射 attr1=切线、attr2=UV，与实测 attrib1=2f uv、attrib2=3f 不一致。若实测确实出现在 Spine 批次上，则该批次顶点声明必经 0xab82114 缓存（可按 GOpenGLVertexDeclarationCache 键比对），差异源头应在：(a) 游戏 build 对 FLocalVertexFactory::FDataType/InitRHI 的本地化修改（0xa09cc20 内 AccessStreamComponent 的 stream/attr 序号即配置点），或 (b) 该 draw 来自 FProceduralMeshSceneProxy 之外的代理。此点已如实标注，未做臆断；后续可对 0xa09cc20 的 attr 序号写入点做动态验证。

## 3. 完整绘制序列表（每步 addr + 证据）

| # | 阶段 | 函数/地址 | 证据 |
|---|---|---|---|
| 1 | 顶点填充（并行） | 0x70c0d30 → 0x70b2424 / 0x70b25f0 | part_000017.c：0x70c0d30 按 bVar1>>1（裁剪开关）分发，5 数组指针 puVar8+6/+10/+0xe/+0x12/+0x16 传入；part_000009.c：0x70b25f0 写 pos/uv/COLOR0/dark 3f/aux |
| 2 | 批次去重 | 0x70bc048 switch(FUN_07124b70()) 0..3 | part_000003.c：4 组 TMap（+0x590/5f0/650/6b0）hash 查附件已存在则跳过 |
| 3 | section 提交 | 0x70bd350（CreateMeshSection 调用点 0x70bd460） | part_000010.c：vtable+0x5d0 → UProceduralMeshComponent::CreateMeshSection(0x661cf34)，参数含 UV0..UV3+Colors；之后 `*sectionIdx += 1` |
| 4 | 渲染状态失效 | CreateMeshSection 0x661cf34 → MarkRenderStateDirty 0x9d70eb8 | callgraph 0x661cf34→0x9d70eb8 |
| 5 | SceneProxy 重建 | CreateSceneProxy 0x661e858 → FProceduralMeshSceneProxy 0x661e88c | part_000015.c/part_000008.c：operator_new(400)，逐 section 建 5 个渲染资源 |
| 6 | 顶点打包 | InitFromDynamicVertex 0xa4d1524（0x34→0x58 转换+分流拷贝） | part_000081.c：位置→+0xb0、切线→+0x60(8/16B)、UV→+0x68(4/8B×3)、颜色→+0xc8 |
| 7 | RHI 缓冲创建 | BeginInitResource×5 → RHICreateVertexBuffer 0xab80b70 / RHICreateIndexBuffer 0xab1dd84 | part_000082/part_000085：→TOpenGLBuffer 0xab80d00；InitRHI 链 0xa312cd8→0xa312978→GDynamicRHI vtable+0x140 |
| 8 | 顶点声明 | FLocalVertexFactory::InitRHI 0xa09cc20 → InitDeclaration 0x84dccf0 → RHICreateVertexDeclaration 0xab82114 | part_000070/part_000038/part_000079：attr0..3+N，GOpenGLVertexDeclarationCache |
| 9 | 批次收集 | GetDynamicMeshElements 0x66226d0 | part_000008.c：每 section→FMeshBatch（材质=section->Material，VF=+0x138，NumPrimitives=idx/3） |
| 10 | MeshPass 处理 | TryAddMeshBatch 0x8eced60 → Process 0x8ecf448 | callgraph；半透明→CalculateTranslucentMeshStaticSortKey 0x8c46be0；BuildMeshDrawCommands 0x8d1dbac |
| 11 | Pass 调度 | FMobileSceneRenderer::Render 0x8f7321c → RenderForward 0x8f75d44 → RenderMobileBasePass 0x8efb6a4（不透明）/ **RenderTranslucency 0x8f77f20（Spine 半透明落点）** | RenderForward callee 表（callgraph）；TranslucencyPassToMeshPass 0x922d210（pass+9） |
| 12 | 命令提交 | DispatchDraw 0x8ec52f0 → SubmitMeshDrawCommandsRange | part_000041.c |
| 13 | GL 绘制 | RHIDrawIndexedPrimitive 0xab142c4 → SetupVertexArrays 0xab11ed4 → glDrawElements(0xb9aa4c0) | part_000067/part_000075：GL_TRIANGLES、GL_UNSIGNED_INT、glVertexAttribFormat/Binding、glBindVertexBuffer |

## 4. 移交提示

1. 复刻绘制序时对齐表 #1-#13 即可；混合模式分批的唯一权威点在 UpdateMesh 的 switch（0x70bc048 内，地址 0x70bc5e0-0x70bc9d0 区）+ CreateMeshSection 的 sectionIdx。
2. stride=44 差异见 §2 末段——需要动态断点验证 GOpenGLVertexDeclarationCache 键（0xab82114 入参）与 0xa09cc20 的 attr 配置；勿按 stock 布局臆写。
3. 半透明 pass 前后顺序：PrePass→BasePass→AzurePPR→AzureOutline→Decals→**Translucency**→TranslucencyBlur→PreTonemapMSAA（RenderForward 0x8f75d44 callee 顺序）。
