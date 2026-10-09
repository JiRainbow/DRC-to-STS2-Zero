# C 代码解析战役状态

共 103 个 part_*.c。**并发上限：5 个代理**。每文件一个代理，产物写到 ue4src_analysis/<模块>/。

## 运行中（5）
| 文件 | 焦点 | 状态 |
|---|---|---|
| part_000063 | engine_core（Sequencer 求值核心+Azure 轨道） | **done** |
| part_000081 | engine_core（CharacterVirtualLightDirection@0xe80） | **done** |
| part_000062 | engine_core（Sequencer→MPC 颜色写入 0x95ba2e4） | **done** |
| part_000082 | engine_core（Azure 后处理属性+Lua VM 簇） | **done** |
| part_000047 | engine_core（**Azure 光照替换消费端** 0x9130678/0x8efb15c/0x8f74ec8） | **done** |
| part_000010 | engine_core（spine-cpp 运行时库+wLua 颜色 thunk 群） | **done** |
| part_000054 | engine_core（**FAzureMaterialParamSet::ApplyParams=0x97ee7cc**） | **done** |
| part_000051 | engine_core（0x70b25f0 本体排查） | running |
| part_000055 | engine_core（0x70b25f0 本体排查） | running |
| part_000046 | engine_core（**ReplaceDirectionalLight UFunction 名排查**） | running |
| part_000044 | engine_core（同上） | running |
| part_000039 | engine_core（**AzureReplaceDirectionalLight=0x8eface8**） | **done** |
| part_000078 | engine_core（UPointLightComponent SetAzureIntensityScale=0xa8f7b28） | **done** |
| part_000050 | engine_core（**渲染任务 Execute=0x8f59be8 写全局 0x0c6196b0/b8/c0/c8**） | **done** |
| part_000050 以外补位 | —— | —— |

（实际运行中=051/055/046/044 共 4 个 + 已收线待重派 0 个；表内 done 行保留供查阅）

## 已完成（26 文件）
详见各 part_*.md。核心地址速查：
- MID 参数写入底座 0xa0e5800/0xa0e5a78/0xa0e5d2c、Internal=0xa0e0ffc/0xa0e0c18、Create=0xa0e55ac、ByInfo=0xa0e5ad8
- MID 颜色渲染线程落点 0xa10e24c、向量参数下发 0xa10de88/0xa10f328
- uniform 求值 0xa0fe0a4、表达式求值 0xa127bc0、Uniform 覆盖 0xa122df0/0xa123078、MPC 0xa12dffc/0xa12ec84/0xa12f364
- **Azure 颜色链（完整闭合）**：蓝图 UFUNCTION 0x6e2b57c（bool+FLinearColor+FVector，wLua/VM 可调）→ AzureReplaceDirectionalLight 0x8eface8 → 渲染任务 0x8f59be8 → 全局 0x0c6196b0/b8/c0/c8 → 消费端 0x8efb15c（方向光替换）/0x9130678（视图 uniform 0x9e0）；灯组件双颜色→SetAzureCharColor 0x9dbadd4（写点 0x9110a64）；CharacterLightParams(4×f4@0xe60)/Ex(0xa3e9658)/VirtualLightDirection(@0xe80)/ILCScale/OutlineColor；**FAzureMaterialParamSet::ApplyParams=0x97ee7cc**（自动建 MID 写 FLinearColor/标量/纹理，Azure 事件轨道触发）
- Sequencer：材质轨道执行端 0x958daa0、颜色写入 MPC 0x95ba2e4、UAzureMovieSceneEventTrack、FAzureMaterialParamSet=0x98319cc
- spine：顶点色生产端 0x70b25f0（tint×slot×attachment）、SkeletonJson=0x710a3b8、运行时库区 0x709000-0x711800、wLua 颜色 thunk 群（SetColorAndOpacity=0x6f47848、AzureOutlineColor_WidthInA 读端=0x6fccf9c、AzureLuaActorComponent 注册）
- 其它：内嵌 Lua VM=0xabd1bb0、Matinee 材质轨道=0xa022424

## 脉冲驱动源追踪（架构已闭合，数值待资产提取）
- **Sequencer 材质/颜色轨道**：FAzureMaterialParamSet→ApplyParams(0x97ee7cc) 写 MID；FMaterialParameterCollectionExecutionToken::Execute(0x95ba2e4) 写 MPC；执行端 0x958daa0——数值在战斗 LevelSequence 资产（ue4_dump 可提取）
- darkenactionhandler（DarkenMPC）：技能期临时压暗
- K2 插值节点：排除（未用）

## 已完成（追加）
| 文件 | 要点（地址） |
|---|---|
| 063 | Sequencer 材质轨道执行端 0x958daa0、UAzureMovieSceneEventTrack、FAzureMaterialParamSet=0x98319cc、K2 插值=0xa0e6ba8（impl 在本文件） |
| 052 | LevelSequence 求值底座（材质轨道 token 汇入 0x958daa0） |
| 062 | Sequencer→MPC 颜色写入 FMaterialParameterCollectionExecutionToken::Execute=0x95ba2e4、UMovieSceneColorSection=0x959db80、GameThread_UpdateMIParameter<FVector>=0xa0e0cc4 |
| 082 | AzureCharacterVirtualLightColorWhite/ILCShadownessScale 后处理属性；Lua VM 簇 TrySet=0xaba548c |
| 047 | Azure 光照替换消费端：视图 uniform 0x9e0 写点=0x9130678、方向光替换=0x8efb15c、RenderAzureOutlinePass 调用=0x8f74ec8、全局色 0x0c6196b0/b8 |
| 010 | spine-cpp 运行时库区 0x709000-0x711800（SkeletonJson=0x7114cd8）；wLua 颜色 thunk 群（SetColorAndOpacity=0x6f47848）；AzureLuaActorComponent 注册；AzureOutlineColor_WidthInA 读端=0x6fccf9c |
| 054 | FAzureMaterialParamSet::ApplyParams=0x97ee7cc（自动建 MID 写三数组）；RenderAzureOutlinePass 插入点；UAzureMovieSceneEventTrack 簇 |
| 002 | **0x6f6784c=K2_InterpolateMaterialInstanceParams 的 Lua thunk**（MID+双 MaterialInstance+权重，Lua 可驱动参数插值）；UpdateMesh 编译区 0x70b8000-0x70c0000；粒子灯 |
| 039 | **AzureReplaceDirectionalLight=0x8eface8**（bool+FLinearColor+方向，渲染线程直写全局 0xc6196b0/b8）；Azure 钩子簇 0x8ec1000-0x8f19000 |
| 078 | UPointLightComponent::SetAzureIntensityScale 注册=0xa8f7b28；无脉冲本体 |
| 050 | **渲染任务 Execute=0x8f59be8 写全局 0x0c6196b0/b8/c0/c8**（闭合 06e2b57c→0x8eface8→全局→消费端全链）；BasePass PS 绑定 FMobileDirectionalLightShaderParameters |

## 替换灯色驱动链（完整闭合）
wLua/蓝图 → 0x6e2b57c（bool, FLinearColor, FVector）→ AzureReplaceDirectionalLight 0x8eface8 → 任务 0x8f59be8 → 全局 0x0c6196b0/b8 → 消费 0x8efb15c/0x9130678（角色材质被场景灯色染色=蓝白观感）
另：0x6f6784c = InterpolateMaterialInstanceParams Lua thunk（MID 参数在双材质间按权重插值——脉冲的另一候选实现）

## 队列
part_000033, 018, 049, ……按 _index.csv。

## 追加完成（044/046/049 派出前）
| 文件 | 要点 |
|---|---|
| 044 | CreateAzureOutlinePassProcessor=0x8c2ec04（描边处理器工厂）；链上 12 地址 0 命中（地址域交错，需换文件检索） |
| 046 | 移动渲染底座；AzureSetSingleLightingCacheDirty=0x8e5dbf4（角色灯间接光缓存定点置脏）；链上地址落断层→需覆盖断层分片 |
| 018 | running |
| 033 | running |
| 049 | running |

队列更新：part_000046, 044, 008, 004 已派；下一批 part_000033 已派、续接 _index.csv 余序。

## 追加完成/运行（049 收线、060/019/015 已派）
| 文件 | 要点 |
|---|---|
| 049 | **全局块发布点=0x9e1b1d8**（渲染任务回调把暂存 0x0c619e40-a8 整拷到消费区 0x0c619668-c8，补全 0x8eface8→消费端之间的搬运环节）；Azure 描边 VS/PS 绑定=0x8c2cf8c/0x8c2d220；SetAzureCharColor 紧邻 ULightComponent 簇（SetLightColor=0x9dbba38 颜色管线）；无正弦调制——脉冲不在本卷 |
| 060/019/015 | running（0x70b25f0 本体+darkColor RGB787+0x6e2b57c 调用方+AzureCharColor 值来源重点） |

chr_ling001 骨架 50 槽 dark 全=-1（无暗色数据）——darkColor 染色源排除（RGB787 通道用于其它用途或运行时填充）。

## 追加（part_000018 收线 + 数据侧排除）
| 文件 | 要点 |
|---|---|
| 018 | **0x70eeee4（18736B）=spine-cpp readAnimation 内联（含 TwoColorTimeline 双色九值解析）**——运行时能力存在但 chr_ling001 自身 16 动画 0 条颜色时间轴（slot 仅 attachment 轨道，数据侧排除）；USpineWidget 装配链 0x70c6c2c/0x70c8150；FastRenderer 材质槽 BP 暴露层 |
| 数据侧 | chr_ling001 骨架 50 槽 dark 全=-1；动画无 rgba/rgba2 轨道——角色数据侧全部排除 |
| 收口方向 | 蓝染唯一未提取数据源=**战斗 LevelSequence 材质参数轨道数值**（FDefaultMaterialAccessor::Apply=0x958daa0 每帧写入，载体 FAzureMaterialParamSet）——下一步用 ue4_dump 提取战斗序列资产（res_cinematics/fight、res_fight）的 FAzureMaterialParamSet 数值 |

## 追加（060 收线、003 已派）
| 文件 | 要点 |
|---|---|
| 060 | GAzureSetMaterialsQualityLevel=0x9dd8a6c（全局材质质量级切换，遍历组件特判）；FAzureMaterialParamSet::StaticStruct=0x9831918（0xf0B，注册于 /Script/UMG）；Sequencer 颜色路径 FColorToken::ApplyColor=0x95ea354（LightColor→ULightComponent::SetLightColor 特判——与灯组件双颜色同源）；0x97ef090 FAzureSlateMeshData::SetMaterial（仅收 MID） |
| 003 | running |

运行中：062?（done）——当前 running=000/013/007/056/006/003 + 081/079 等；5 并发按滚动维持。

## 追加（006 收线）
| 文件 | 要点 |
|---|---|
| 006 | particles_vfx（Niagara 主导）；0x6e2b57c 无调用者在本卷；**CharacterDirectLightScale=0x0c366b50、CharacterIndirectLightScale=0x0c366b40 参数名出生点**（与替换方向光同族的角色光照缩放，跨卷追读取端新抓手）；构建目录串 F:/DRC_Workspace/src_obt/Azure |

## 追加（056/007/082/062 收线、057/080 已派）
| 文件 | 要点 |
|---|---|
| 056 | **ApplyParams 调用方=FAzureSlateMeshData::OnPlay 0x97ef034**（Slate 网格封装：自动建 MID+应用参数集）；UAzureMovieSceneEventTrack 注册=0x96a8340；Sequencer-MPC 动画旁证=0x95bb588/0x95bb67c |
| 007 | **ReplaceDirectionalLight 属 UAzureSceneImage 类**（Z_Construct 注册=0x6d030ac，bReplace 默认 true，同区 ReplaceMovableIndirectLighting=0x6d03110）；CustomCharacterTexture 类注册=0x7066140；Screen/MultiplyBlendMaterial Lua 出口=0x70ad318/0x71e8310 |
| 082 | UPostProcessSettings.AzureCharacterVirtualLightColorWhite/ILCShadownessScale 属性 stub；内嵌 Lua VM 簇+TrySet=0xaba548c |
| 062 | Sequencer→MPC 颜色写入 Execute=0x95ba2e4、UMovieSceneColorSection=0x959db80、GameThread_UpdateMIParameter<FVector>=0xa0e0cc4 |
| 057/080 | running（UAzureSceneImage 的 ReplaceDirectionalLight 调用方+AzureCharColor/CustomCharacterTexture 值来源重点） |

队列更新：part_000053, 040, 011, 005, 020, 012, ……按 _index.csv。

## 追加（080 收线）
| 文件 | 要点 |
|---|---|
| 080 | engine_core；bOverride_AzureCharacterVirtualLightRotation=0xa922c10（PostProcessSettings 覆盖位，Azure 角色虚拟光系第三属性）；两追查目标 0 命中 |

## 追加（017 收线——推翻内联假设）
| 文件 | 要点 |
|---|---|
| 017 | **0x70b25f0=被显式调用的独立函数（非内联）**，调用方=**顶点色填充调度器 FUN_070c0d30(312B)**：按 slot 标志 bit1 分流 0x70b2424（常规）/0x70b25f0（顶点色生产端），两路输出布局一致=**6 组 RGBA 指针=Color+Dark 二级 tint**；默认材质懒加载 0x70b82a4 缓存 MySpineLitNormalMaterial+SpineUnlit 三件套到全局 0xc37da50-68；0x70a0240 写 __spine-ue3_custom_skin |
| 020 | running（调度器上游+slot 标志来源+Dark tint 值来源重点） |

关键结论：**Spine 双色染色（Color+Dark）经 RGB787 打包进顶点流，Dark 通道即染色二级入口**——slot 标志决定走哪条填充路径；下一步=020 号代理追调度器上游与 Dark 值来源。

## 追加（053 收线、012 已派）
| 文件 | 要点 |
|---|---|
| 053 | AzureResetILCData=0x90dba6c（→AzureSetSingleLightingCacheDirty=0x8e5dbf4 闭环）；SetAzureIntensityScale 写组件+0x39c=0x9dca86c；**USkinnedMeshComponent::SetVertexColorOverride=0x9e2cb30**（合法顶点色覆盖写入点，本文件无调用方） |
| 012 | running（调度器上游+Dark tint 值来源+AzureCharColor 值来源重点） |

## 追加（066/040/057 收线、001/026 已派）
| 文件 | 要点 |
|---|---|
| 066 | MID 参数查询端基座（GetBasePropertyOverridesHash=0xa0e2a74、GetVectorParameterValue=0xa0e8ba0、FMaterialShaderMap 全局表注册=0xa0e9770） |
| 040 | **AzureOutlineColor=引擎全局着色器框架常规 FShaderParameter**（FAzureOutlinePassVS/PS 类型注册 0x8c2cd94-0x8c2d050）；GAzureFlushShaderCacheFlag 消费=0x83ed2c0 |
| 057 | 0x9110a64/0x97ee7cc/0x97ef034 落本卷"函数间隙"=实体在其它 part（按编译单元切卷地址交错）；UWidgetComponent::UpdateMaterialInstanceParameters=0x97e29b4（TintColorAndOpacity 路径）；FAnimNode_ModifyBones 游戏定制动画节点=0x9515498 |
| 001/026 | running（001 带 0x70b25f0 本体精读专项；026 带调度器上游+Dark tint 值来源重点） |

## 追加（065/005 收线、061 已派）
| 文件 | 要点 |
|---|---|
| 065 | **MID/MPC 颜色参数通路主体**：SetScalarParameterValueInternal=0xa0e1500、K2_GetVectorParameterValue=0xa0e5864、InitializeVectorParameterAndGetIndex=0xa0e5c30、GameThread_UpdateMIParameter=0xa0e1c30、**RenderThread_UpdateParameter 首行=InvalidateUniformExpressionCache（0xa10f12c）**、MPC 向量读端=0xa12f364；**FLightSceneProxy::SetAzureCharColor=0x9dbadd4（游戏定制角色颜色入口）**；UAzureMovieSceneEventTrack/FAzureSlateMeshData 定制类 |
| 005 | **UAzureSceneImage 原生侧全家在本卷**：ctor=0x6c356b8（内嵌 FPostProcessSettings+FSlateBrush）、CaptureEnable=0x6c358c8（建 RT+ASceneCapture2D 并整拷后处理设置）、**ReplaceMovableIndirectLighting=0x6c363b4**（8 float 写进采集组件+0x310/+0x328-0x358=ReplaceDirectionalLight 姊妹实现）；0x6e2b57c 落本卷地址空隙（调用者不在本卷）；颜色参数动画惯例参考=0x6d997d0（天气 MID 连发 SetVectorParameterValue） |
| 061 | running（调度器上游+Dark tint+场景光值来源重点） |

## 追加（011 收线）
| 文件 | 要点 |
|---|---|
| 011 | **UAzureSceneImage::ReplaceDirectionalLight 函数体=0x6c363e4**（60B 纯转发：bool→+0x311、RGBA→+0x360-0x36f、方向→+0x370-0x37b）；调用方两个=execReplaceDirectionalLight(0x6d02438，蓝图/Lua 按名) + **FUN_06e8cf4c(0x6e8cf4c，C++ 原生调用方)**；GetTriCoordColorFallback 的 8+7bit 拼包=tri-coord 索引解码非 darkColor |

## 追加（026/012 收线）
| 文件 | 要点 |
|---|---|
| 026 | engine_core 排除卷（战斗链 12 地址全 0 命中且有据）；FLinearColor 工具/MeshEdit 颜色属性/Niagara GetColor 均与角色 tint 无关 |
| 012 | particles_vfx；**0x6d9a960(2880B)=灯光+材质参数批量下发器**（21×SetScalar+3×SetVector+SetLightColor/Intensity/Temperature+SceneCapture2D 引用，跨片调用）；APointLightManager::SetScalarParamForMID BP 壳→0x71bd1e4（真实现别卷）；UAzureSceneImage natives 注册=0x6d02d64 |

## 追加（047/001/033 收线、021/023/030 已派）
| 文件 | 要点 |
|---|---|
| 047 | **Azure 光照替换消费端全定位**：视图 uniform 0x9e0 写点=0x9130678（门控 GAzureReplaceLightingParams，关→(1,1,1,1)，值取调用方+0x15dc-0x1600）；方向光替换=0x8efb15c（全局色 0x0c6196b0/b8 ×1/π）；RenderAzureOutlinePass 调用=0x8f74ec8 |
| 001 | **顶点缓冲 6 数组实锤**：0x70b2424=ParallelFor 包络（position/uv/Color/DarkColor/辅助/索引），分块回调 0x70c05dc——Color+Dark 二级 tint 各占独立顶点流（RGB787 打包即 Dark 流）；0x70b90b8 逐页 MID 写 darkenParam+Rongjie；**脉冲 gameplay 驱动入口=CoralSkillPlayer 类注册表 0x718e77c（含 DarkenAction 等技能时间轴动作类）**；0x70b25f0 落函数表空洞=内联于更大函数体（part_000009 已精读内容） |
| 033 | FAzureOutlinePassMeshProcessor::AddMeshBatch=0x8c2d5a8；Azure 阴影中心替换消费=0x9207640；两重点地址落反编译空隙 |
| 021/023/030 | running |

## 追加（042 收线）
| 文件 | 要点 |
|---|---|
| 042 | **间接光消费端=GetIndirectLightingCacheParameters 0x8e6e138**：读 GAzureReplaceLightingParams 门控，全局块 0x0c619670-a8（8×float4 SH 环境光）注入每帧间接光 uniform（绕过体积光照贴图）；CreateAzureOutlinePassProcessor=0x8c2ec04 在此卷 |

Azure 替换光照系统三消费端齐备：方向光颜色（0x8efb15c）+ SH 环境光（0x8e6e138）+ 角色光缩放视图 uniform（0x9130678）——全部受 GAzureReplaceLightingParams 门控，战斗场景配置蓝光即整场景蓝染。

## 追加（059 收线）
| 文件 | 要点 |
|---|---|
| 059 | **替换全局块布局全解**：0x0c6196b0/b8=颜色（BasePass 消费 0x8efb15c）、c0/c8=方向（阴影级联消费 0x9ddbdf0）、0x70-a8=SH 环境光（0x8e6e138）；AzureSetReplaceShadowAutoCalcCenter=0x9db34b0；FAzureSlateMeshData 内嵌 FAzureMaterialParamSet（stride 0x108） |

## 追加（058 收线）
| 文件 | 要点 |
|---|---|
| 058 | engine_core 排除卷（UMID 0xa0e5800 区恰在其反编译空洞内）；**FAzureSlateMeshData::GetDynamicMaterial=0x97ee5a4 调 ApplyParams**（参数集第二调用方）；GAzureCheckUpdateFlagsBeforeModify 消费=SObjectWidget::Construct 0x97f05a4 |

## 追加（030 收线）
| 文件 | 要点 |
|---|---|
| 030 | engine 底座排除卷（CoreUObject 序列化/Vulkan RHI/Slate/ICU/音频合成）；战斗链 7 地址 0 命中；azure 10 处全为腾讯基础设施（MallocAzureProtect/FAzureCustomVersion 等） |

## 追加（021/030 收线、025 已派）
| 文件 | 要点 |
|---|---|
| 021 | engine 底座排除卷（战斗链 7 地址 0 命中；color 命中全为 Slate UI/AVG 剧情/CoralAVGRuntime 注册） |
| 030 | engine 底座排除卷（CoreUObject 序列化/Vulkan RHI/Slate/ICU/音频合成）；azure 命中全为腾讯基建 |
| 025 | running |

## 追加（025/084 状态）
| 文件 | 要点 |
|---|---|
| 025 | ui_umg 排除卷（战斗链 10 地址 0 命中）；AzureAtlasInterface/BrushDebuger=同名不同物；Slate AddBorderElement 顶点生产端=UI 路径 |
| 084 | running |

## 追加（038/029 状态）
| 文件 | 要点 |
|---|---|
| 038 | engine 底座排除卷（Chaos 物理+RHI/PSO+Slate 调色板编辑器）；防混淆：0x84b25f0=~FNullColorVertexBuffer 与 0x70b25f0 无关；AzureFlushShaderCacheFlag 写=043/消费=040 已闭环 |
| 029 | running |

## 追加（028 收线、037/035/031 已派）
| 文件 | 要点 |
|---|---|
| 028 | engine 底座排除卷（地址域排除+FAzureCustomVersion "AzureVer" GUID 注册=0x7c0cdbc）；GAzureCheckUpdateFlagsBeforeModify 消费=Slate 失效守卫 |
| 037/035/031 | running |

## 追加（084 收线）
| 文件 | 要点 |
|---|---|
| 084 | engine 底座排除卷（PhysX/Recast/AIModule/ICU；地址域 0xaa-0xb8 不覆盖战斗链）；游戏自有 UI 粒子家族 SParticle/GetUpdatePtr（Slate 顶点缓冲+UIParticleComponent 材质） |

## 追加（029 收线）
| 文件 | 要点 |
|---|---|
| 029 | engine 底座排除卷（内存/字符串/UObject/Slate 输入布局/Vulkan RHI/EditableMesh/合成音频）；战斗链 11 地址 0 引用；EditableMesh 顶点色=编辑器管线非运行时 |

## 追加（029 收线、027/024 已派）
| 文件 | 要点 |
|---|---|
| 029 | engine 底座排除卷（内存/字符串/UObject/Slate 输入布局/Vulkan RHI/EditableMesh/合成音频）；战斗链 11 地址 0 引用；EditableMesh 顶点色=编辑器管线非运行时 |
| 027/024 | running |

## 追加（035/024/056 收线）
| 文件 | 要点 |
|---|---|
| 035 | engine 底座排除卷（SlateCore 主体+RenderCore+Chaos；10 地址 0 命中）；Azure 命中全为 Slate UI/字体改造（UAzureAtlasInterface/BrushDebuger/InvalidationBox 优化）勿混淆 |
| 024 | engine 底座排除卷（Chaos 切割/Slate/Android/Synth/Online；地址域夹在 0x70 簇与 0x8e/0x9d 消费簇之间无衔接）；Azure 命中=保护分配器/GC 校验/Slate 失效优化 |
| 056 | **ApplyParams 调用方=FAzureSlateMeshData::OnPlay 0x97ef034**（Slate 网格封装：自动建 MID+应用参数集）；UAzureMovieSceneEventTrack 注册=0x96a8340；Sequencer-MPC 动画旁证=0x95bb588/0x95bb67c |

## 追加（037 收线）
| 文件 | 要点 |
|---|---|
| 037 | engine 底座排除卷（Chaos 窄相/Voro++/Slate 框架/RHI 管理；战斗链地址 0 命中）；GAzureInSlateTickApplication=FSlateApplication::Tick 插桩、GAzureCheckUpdateFlagsBeforeModify 6 处=SWidget 标志守卫——均 UI 层与角色颜色无关 |

## 追加（027 收线）
| 文件 | 要点 |
|---|---|
| 027 | engine 底座排除卷（GeometryProcessing/音频合成/VulkanRHI/Slate UI；战斗链与三目标全在域外 0 命中）；"Azure"=UE 内存分配器谱系命名（FMallocAzureOverrun/Protect）与游戏 UAzure* 无关 |

## 追加（092 收线、034 已派）
| 文件 | 要点 |
|---|---|
| 092 | misc 排除卷（纯第三方中间件：PhysX/ICU/Oodle/Opus/OpenSSL/HarfBuzz/FreeType，零游戏层代码；战斗链全部地址超域） |
| 034 | running |

## 追加（036/087/089 状态）
| 文件 | 要点 |
|---|---|
| 036 | engine 底座排除卷（Slate UI 框架+Chaos+PSO 缓存+JPEG；地址域 0x7fcc 起）；GAzureCheckUpdateFlagsBeforeModify 门控 UpdateWidgetFlags 5 处——"Azure" 前缀双用途（UI 失效 vs 战斗场景类）已逐条排除 |
| 087 | running |
| 089 | running |

## 追加（034 收线、032/090 已派）
| 文件 | 要点 |
|---|---|
| 034 | engine 底座排除卷（Chaos 物理+Slate 字体+RHI 基建；战斗链 11 地址 0 命中）；AzureFSlateBrushDebuger::Check=0x7fae4f4 精读排除 |
| 032/090 | running |

## 追加（089 收线、088/094 已派）
| 文件 | 要点 |
|---|---|
| 089 | PhysX/AI 导航/ICU/音频杂合卷排除（战斗链十地址实锤 0 命中）；颜色代码仅引擎底座（导航可视化调试色表等） |
| 088/094 | running |

## 追加（087 收线）
| 文件 | 要点 |
|---|---|
| 087 | engine 底座排除卷（AI/导航/Chaos/音频第三方/PhysX/libcurl/OpenSSL/Oodle/ICU/HarfBuzz/libpng；战斗链 9 地址域外 0 命中）；唯一 MID 写入=Chaos 破坏体 WorldToLocal 矩阵传递与颜色链无关 |

## 追加（090 收线、086/097 已派）
| 文件 | 要点 |
|---|---|
| 090 | AIModule/PhysX/第三方中间件混合卷排除（战斗链低于本卷地址下限 0xadc2b84）；最大函数=libcxxabi Itanium demangler 0xb62aeec(24KB)、swappy 帧步调 JNI 桥=0xb994ca8 |
| 086/097 | running |

## 追加（032 收线）
| 文件 | 要点 |
|---|---|
| 032 | engine 底座排除卷（Chaos 物理+CoreUObject+Slate/UMG+CopyTexture/MediaShaders 注册；战斗链地址域外全 0 命中）；GetAzureDestroyStructFlag 控制属性析构链遍历；常量表含 1/255、127.5 字节↔浮点换算形态但无角色脉冲链路证据 |

## 追加（094 收线）
| 文件 | 要点 |
|---|---|
| 094 | misc 排除卷（PhysX 3.4 全栈 Scene 构造=0xb1710bc/Oodle LZB=0xb60d27c/tANS 熵编码/PVD 调试协议/车辆悬挂；战斗链全地址超域） |

## 追加（094 收线、091/095/093 已派）
| 文件 | 要点 |
|---|---|
| 094 | misc 排除卷（PhysX 3.4 全栈 Scene 构造=0xb1710bc/Oodle LZB=0xb60d27c/tANS 熵编码/PVD 调试协议/车辆悬挂；战斗链全地址超域） |
| 091/095/093 | running（尾卷批次） |

队列剩余：part_000096(rel 9)、part_000098-0102(rel 0，纯底座尾卷)。

## 追加（088 收线）
| 文件 | 要点 |
|---|---|
| 088 | engine 底座排除卷（Recast/Detour 导航+AIModule/FieldSystem+PhysX 核心+OpenSSL/FreeType TT_RunIns=0xb884800/SILK/Swappy；战斗链 11 地址 0 命中）；_INIT_1128 写数学常量表非颜色参数表（防混淆排除） |

## 追加（091 收线）
| 文件 | 要点 |
|---|---|
| 091 | engine 底座排除卷（PhysX 接触求解/Oodle 熵编码/布料/Chaos 几何集合上传/ICU；战斗链全地址超域 0 命中；UE 侧纯 AIModule 反射与 exec thunk） |

## 追加（086 收线）
| 文件 | 要点 |
|---|---|
| 086 | engine 底座排除卷（PhysX+Recast/Detour+Opus/Oboe+OpenSSL+Oodle+UE 反射底座；战斗链全地址低于卷下限 0 命中）；最大函数=Oodle Kraken 编码 0xb5cfee8(27.5KB) |

## 追加（097 收线）
| 文件 | 要点 |
|---|---|
| 097 | misc 排除卷（ICU 64 主体 705 函数/FreeType/libpng/HarfBuzz/libvorbis+Opus/CELT/swappy；战斗链全地址超域 0 命中；最大函数=celt_decode_with_ec 0xb954b58） |

## 追加（093 收线）
| 文件 | 要点 |
|---|---|
| 093 | misc 排除卷（PhysX 3.4 主体 738 符号 Dy/IG/Pt/Sc/Gu/GJK/HeightField/RepX/PxVehicle + OpenSSL/libssl TLS1.2/1.3+ECDSA+CMS + libcurl cookie + ICU 数字格式化 + FreeType TrueType 解释器 0xb861768(28.9KB)；战斗链 11 地址不相交 0 命中） |

## 追加（095 收线）
| 文件 | 要点 |
|---|---|
| 095 | misc 排除卷（纯第三方中间件：PhysX+libcurl+OpenSSL 含国密 SM2/SM3+Oodle2+ICU64+FreeType/HarfBuzz+libpng+Opus/SILK+Swappy+libunwind；战斗链全地址超域 0 命中）；最大函数=ICU 正则编译器 0xb7a75a4(16.6KB) |

## ✅ 战役收尾（2026-09-29）：103/103 全部完成
最后 9 个（016/048/083/096/098/099/100/101/102）两波收线，103 份 .md + 103 份 func_index.csv 齐备。

| 文件 | 定性 | 要点 |
|---|---|---|
| 016 | **SpinePlugin 运行时块**（0x7016000-0x7120000）+ Core 支撑层 | SlotColor 属性 thunk=0x701a200、Multiply/AdditiveBlendMaterial 访问器（0x7018df0/0x701b140）、spine SkeletonJson 巨函数=0x711a360（25400B）、UAzureSceneImage 同族 UClass 注册块（ReplaceMovableIndirectLighting 注册、execAddShowOnlyActor=0x6d02844）；0x70b25f0 在本卷地址域但落函数表间隙（本体已在 009 精读解决）；BP thunk→UMaterialParameterCollectionInstance::SetVectorParameterValue=0x6e29418 |
| 048 | **移动渲染底座 + 灯光管理 + Chaos** | **FUN_09110a64：渲染端对灯代理 SetColor + SetAzureCharColor 双颜色槽**（SetAzureCharColor 写点实证）；Azure 定制移动渲染器实锤（CreateMobileAzureReceiveStencilCullingPassProcessor=0x8ed0368、UsingPPR=0x8ed0660、AzureSkipAlphaRender=0x8ed12f4、AzureUpdatePrimitiveLightingAttachmentRoot=0x90da288）；FScene::UpdateLightColorAndBrightness=0x90e53d4；FMobileSceneRenderer::Render=0x8f7321c |
| 083 | 排除：PhysX+ICU+Recast/Detour+行为树+Oodle+OpenSSL | Azure/Spine/染色关键词全 0；Skeleton/particle 命中均为 ICU/Chaos 假阳性；LinearColor 命中全是导航调试绘制 |
| 096 | 排除：PhysX RepX+Oodle2+ICU64+FreeType/HarfBuzz+Opus | G:\RenderPlat 构建路径旁证；无渲染链内容 |
| 098 | 排除：ICU+FreeType CFF+HarfBuzz AAT+libpng+SILK | 全关键词 0 命中；libpng 后 424KB 无标记数据段 |
| 099 | 排除：ICU+FreeType stroker+HarfBuzz+libvorbis+Opus | 全关键词 0 命中；UE 类型 0 |
| 100 | 排除：HarfBuzz+libvorbis+Opus+swappy 帧步进 | Android Frame Pacing 背景；无战斗逻辑 |
| 101 | 排除：FreeType avar+libpng+Opus+swappy+libunwind | 尾部 28 个 size=8 跳板 veneer 指向 0x6c2xxxx/0x6d5xxxx 游戏段（无逻辑） |
| 102 | 排除：Opus/SILK+swappy+libc++ 流桩（全战役最后一分片） | 27 函数全读全表；silk_NSQ=5076B 最大 |

**战役总结**：416,695 函数全量过账。核心渲染链此前已闭合（见上文「替换灯色驱动链」）；本批补充实证 048=SetAzureCharColor 渲染端写点卷、016=SpinePlugin 属性入口簇（SlotColor/混合材质访问器）。其余 7 卷全为第三方中间件，正式从战斗渲染候选集划除。分支间隙（veneer）模式确认：size=8 跳板不承载逻辑。

## 材质变更点总地图（2026-09-29 定向核查，全部源码实证）
**战斗角色（SpineSkeletonFastRenderer=0x70b8640）只有两类材质变更：**
1. **0x70bbdf8 = 唯一 MID 创建点**（按 atlas 页+混合模式缓存，part_000018）：`UMaterialInstanceDynamic::Create(父材质)` → SetTextureParameterValue×2（atlas 页@渲染器+0x704、normal@+0x710）+ SetScalarParameterValue("darkenParam"@+0x920、"Rongjie"@+0x928）。**全函数 0 处颜色参数写入** → 角色颜色=父材质(V2 烘焙 ramp)×顶点色(COLOR0 全白)。
2. **属性访问器层换父材质**（part_000016 双 thunk 簇 0x7016000-0x7022000/0x70a7000-0x70ae000）：NormalBlendMaterial(0x7018df0)/MultiplyBlendMaterial/AdditiveBlendMaterial(0x701b140/0x70a7858)/atlasScreenBlendMaterials(0x70a8680)/SlotColor(0x701a200)/InitialSkin/DepthOffset —— BP 静态指定 + Lua SetBlendMaterial（fightspineobjectbase.lua:89-117 分身复制同款）写渲染器成员 → 下次 UpdateMesh 经 0x70bbdf8 重建。

**全局/非角色变更点（排除或条件触发）：**
- 0x6e29418（016）：BP thunk→UMaterialParameterCollectionInstance::SetVectorParameterValue（全局 MPC）
- 0x97ee7cc FAzureMaterialParamSet::ApplyParams（054）：Sequencer/事件轨道 MID 参数写入——技能演出期触发
- 0x6f6784c：K2_InterpolateMaterialInstanceParams Lua thunk（双 MID 参数插值，演出期）
- 0x70654ac exec→0x6dcd32c：CustomCharacterTexture(AzureFacility)/AAzureStaticMeshActor 通用换材质 helper（MID+SetMaterial(slot)）——静态网格/特殊 Actor
- 0x71bcc4c（017）：Blendable 后处理材质注册器（UBlendableInterface，权重=1.0）——全屏效果
- 0x6d9a1b0（016）：**动态天空每帧材质刷新**（StarsColor/MoonDirection×4/GalaxyScale/AuroraTranslucent MPC 标量；参数名表 0c366840-0c366b50@part_000006:211690）——排除；同块尾有 CharacterIndirectLightScale/CharacterDirectLightScale（角色受光缩放，光影侧）
- 定论：**染色不在任何材质参数里**——换色=换父材质资产（V2+mask 图集）或换 mask/atlas，引擎代码无逐皮肤逻辑（自动化管线判断源码级证实）
