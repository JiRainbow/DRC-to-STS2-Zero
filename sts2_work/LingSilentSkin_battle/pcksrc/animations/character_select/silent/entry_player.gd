extends Node
## 进场时序(超宽屏定案,无黑幕):SpineSprite 先隐藏,entry(2s 全图染色,
## t=0 即近黑 #1e222d,loop=false)在动画状态就绪的第一帧施加,施加即显示
## ——首帧可见画面就是暗色场景,之后自然亮起;播完由队列接 animation
## (12s 循环)。替换 NSpineAutoPlayer(其要求骨架动画数必须为 1)。
## 原生签名与游戏 C# 包装 MegaAnimationState 严格一致:
##   set_animation(name, loop, trackId) / add_animation(name, delay, loop, trackId)

const ENTRY := "entry"
const IDLE := "animation"
const FAILSAFE_FRAMES := 360

var _fired := false
var _t_enter := 0
var _t_visible := 0

func _enter_tree() -> void:
	# 计时埋点:游戏日志按 [LingSelect] 过滤,可量化选人切换的真实分解
	# (实例化跨度/动画状态就绪/首帧可见)。若仍见卡顿,日志能定位阶段。
	_t_enter = Time.get_ticks_usec()
	print("[LingSelect] enter_tree frame=", Engine.get_process_frames())

func _ready() -> void:
	print("[LingSelect] ready +%dus" % (Time.get_ticks_usec() - _t_enter))
	var spr := get_parent()
	if spr is CanvasItem:
		spr.visible = false

func _process(_delta: float) -> void:
	if _fired:
		if _t_visible == 0:
			_t_visible = Time.get_ticks_usec()
			print("[LingSelect] next_frame_after_fire +%dus" % (_t_visible - _t_enter))
		return
	_frames_guard()
	var spr := get_parent()
	if spr == null or not spr.has_method("get_animation_state"):
		return
	var st = spr.get_animation_state()
	if st == null:
		return
	# set_animation(name, loop, trackId) / add_animation(name, delay, loop, trackId)
	st.set_animation(ENTRY, false, 0)
	var idle_entry = st.add_animation(IDLE, 0.0, true, 0)
	# 衔接 mix:entry 已在 builder 里与 idle 做骨骼对齐,此处 0.25s mix
	# 只吸收 idle 独有轨道(eye/halo/zui 等)从 setup 起播的残余差异,
	# 消除硬切感。原生 TrackEntry API 同 MegaTrackEntry.SetMixDuration。
	if idle_entry != null and idle_entry.has_method("set_mix_duration"):
		idle_entry.set_mix_duration(0.25)
	_fired = true
	print("[LingSelect] entry fired +%dus" % (Time.get_ticks_usec() - _t_enter))
	if spr is CanvasItem:
		spr.visible = true

func _frames_guard() -> void:
	# 失败保险:spine 迟迟未就绪时也要让画面出来(此时是 setup pose 全亮,
	# 但优于永久隐藏)。
	_frames_n = _frames_n + 1
	if _frames_n == FAILSAFE_FRAMES and not _fired:
		_fired = true
		var spr := get_parent()
		if spr is CanvasItem:
			spr.visible = true

var _frames_n := 0
