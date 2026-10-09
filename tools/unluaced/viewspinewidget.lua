local Lplus = require("Lplus")
local ECViewBase = require("Core.GUI.ECViewBase")
local SpineCacheMan = require("Core.GUI.SpineCacheMan")
local CMaterialResCfg = require("bny.gen.drc.gsp.common.confbean.CMaterialResCfg")
local ViewSpineWidget = Lplus.Extend(ECViewBase, "ViewSpineWidget")
local def = ViewSpineWidget.define
local PLAY_MODE = {SINGLE = 1, QUEUE = 2}
def.field("boolean")._cache = false
def.field("boolean")._unload_when_hidden = false
def.field("number")._spine_id = -1
def.field("number")._trace_index = 0
def.field("string")._animation = ""
def.field("function")._animation_selector = nil
def.field("table")._animation_queue = nil
def.field("boolean")._animation_auto_play = true
def.field("number")._play_mode = PLAY_MODE.SINGLE
def.field("boolean")._loop = true
def.field("boolean")._loaded = false
def.field("number")._tick_timer = 0
def.field("number")._animation_timer = 0
def.field("boolean")._auto_tick = true
def.field("table")._callback_init_finished = nil
def.field("table")._callback_animation_start = nil
def.field("table")._callback_animation_stop = nil
def.field("table")._callback_animation_event = nil
def.field("table")._callback_ref_map = nil
def.field("number")._panel_type = 0
def.field("number")._customized_offset_x = 0
def.field("number")._customized_offset_y = 0
def.field("number")._customized_scale_x = 1
def.field("number")._customized_scale_y = 1
def.field("boolean")._load_use_cfg_scale = false
def.field("userdata")._defaultMat = nil
def.override("=>", "boolean").CanTriggerEvent = function(self)
  return false
end
def.override().OnCreate = function(self)
  local widget = self:GetWidget()
  if not _G.Object.IsA(widget, _G.SpineWidget.Class()) then
    error("[ViewSpineWidget] This view can only be used for SpineWidget !")
  end
  _G.ECGUITools.setVisibility(widget, _G.ESlateVisibility.SelfHitTestInvisible)
  self:_CheckCallback(_G.SpineEventType.EventType_Start, true, _G.WrapOne(self._OnSpineAnimationStart, self))
  self:_CheckCallback(_G.SpineEventType.EventType_End, true, _G.WrapOne(self._OnSpineAnimationStop, self))
  self:_CheckCallback(_G.SpineEventType.EventType_Event, true, _G.WrapOne(self._OnSpineAnimationEvent, self))
end
def.override().OnDestroy = function(self)
  local widget = self:GetWidget()
  if widget and self._defaultMat then
    widget:SetNormalBlendMaterial(self._defaultMat)
  end
  self:StopTick()
  for _, type in pairs(_G.SpineEventType) do
    self:_CheckCallback(type, false, nil)
  end
  self._spine_id = -1
  self._loaded = false
end
def.override("boolean").OnShow = function(self, show)
  if show then
    if not self._loaded then
      self:_Load()
    end
  elseif self._unload_when_hidden then
    self:_Unload()
  end
end
def.method("number", "boolean", "function")._CheckCallback = function(self, type, register, callback)
  if not self:IsValid() then
    return
  end
  if register then
    if callback == nil then
      return
    end
    if self._callback_ref_map == nil then
      self._callback_ref_map = {}
    end
    if self._callback_ref_map[type] == nil then
      self._callback_ref_map[type] = _G.SpineStatics.AddLuaCallback(self:GetWidget(), type, callback)
    end
  elseif self._callback_ref_map ~= nil and self._callback_ref_map[type] ~= nil then
    _G.SpineStatics.RemoveLuaCallback(self:GetWidget(), type, self._callback_ref_map[type])
    self._callback_ref_map[type] = nil
    if next(self._callback_ref_map) == nil then
      self._callback_ref_map = nil
    end
  end
end
def.method("varlist")._Load = function(self, on_finished)
  if not self:IsValid() then
    return
  end
  local spine_id = self._spine_id
  if spine_id < 0 then
    return
  end
  local spine_res_cfg = BnyUtility.GetRecord("common", "CSpineResCfg", spine_id)
  if spine_res_cfg == nil then
    return
  end
  if self._load_use_cfg_scale then
    local scaleX = spine_res_cfg.scaleX
    local scaleY = spine_res_cfg.scaleY
    self:SetRenderScale(scaleX, scaleY)
  end
  self:_Unload()
  print(("[ViewSpineWidget] Load begin (SpineID=%1$d)"):format(spine_id))
  SpineCacheMan.Instance():LoadSpineByPath(spine_res_cfg.atlas, spine_res_cfg.skeleton, spine_res_cfg.materialId, function(atlas, skeleton, material)
    if not self:IsValid() or self._spine_id ~= spine_id then
      return
    end
    local success = atlas ~= nil and skeleton ~= nil
    print(("[ViewSpineWidget] Load end (SpineID=%1$d, Result=%2$s)"):format(spine_id, tostring(success)))
    if success then
      self._loaded = true
      local widget = self:GetWidget()
      widget:Set_Atlas(atlas)
      widget:Set_SkeletonData(skeleton)
      widget:Set_InitialSkin(spine_res_cfg.skinName)
      widget:SynchronizeProperties()
      widget:ForceLayoutPrepass()
      if material then
        self._defaultMat = widget:Get_NormalBlendMaterial()
        widget:SetNormalBlendMaterial(material)
      end
      if self._animation_auto_play then
        self:PlaySpineAnimation(true)
      end
    else
      Error(("Init spine widget failed ! (SpineID=%d)"):format(spine_id))
    end
    if on_finished ~= nil then
      _G.SafeCall(on_finished, success)
    end
    if self._callback_init_finished ~= nil then
      for _, callback in ipairs(self._callback_init_finished) do
        _G.SafeCall(callback, success)
      end
    end
  end, self._cache)
end
def.method()._Unload = function(self)
  print(("[ViewSpineWidget] Unload (SpineID=%1$d)"):format(self._spine_id))
  self._animation = ""
  self._loaded = false
  self:StopTick()
  if self:IsValid() then
    local widget = self:GetWidget()
    widget:Set_Atlas(nil)
    widget:Set_SkeletonData(nil)
    if self._defaultMat then
      widget:SetNormalBlendMaterial(self._defaultMat)
    end
  end
end
def.method()._Play = function(self)
  if not (self:IsValid() and self._loaded) or #self._animation < 1 then
    return
  end
  self._play_mode = PLAY_MODE.SINGLE
  local widget = self:GetWidget()
  if widget:GetAnimationDuration(self._animation) < 0.01 then
    self._loop = true
  end
  widget:SetToSetupPose()
  widget:SetAnimation(self._trace_index, self._animation, self._loop)
  widget:UpdateSize()
  self:OnUpdate()
  if self._tick_timer == 0 then
    self:StartTick()
  end
  print(("[ViewSpineWidget] Set animation (SpineID=%1$d, Animation=%2$s, Loop=%3$s)"):format(self._spine_id, self._animation, tostring(self._loop)))
end
def.method()._PlayQueue = function(self)
  if not (self:IsValid() and self._loaded) or self._animation_queue == nil or #self._animation_queue < 1 then
    return
  end
  self._play_mode = PLAY_MODE.QUEUE
  local widget = self:GetWidget()
  local queue = {}
  for _, info in ipairs(self._animation_queue) do
    if widget:HasAnimation(info.animation) then
      table.insert(queue, info)
    end
  end
  widget:ClearTracks()
  widget:SetToSetupPose()
  for index, info in ipairs(queue) do
    local delay = 0
    if 1 < index then
      delay = widget:GetAnimationDuration(queue[index - 1].animation)
    end
    local loop = info.loop
    if index == #queue and not loop then
      loop = self._loop
    end
    widget:AddAnimation(self._trace_index, info.animation, loop, delay)
    print(("[ViewSpineWidget] Add animation (SpineID=%1$d, Animation=%2$s, Loop=%3$s, Delay=%4$f)"):format(self._spine_id, self._animation, tostring(self._loop), delay))
  end
  widget:UpdateSize()
  self:OnUpdate()
  if self._tick_timer == 0 then
    self:StartTick()
  end
end
def.method("=>", "boolean").IsCache = function(self)
  return self._cache
end
def.method("boolean").SetCache = function(self, cache)
  self._cache = cache
end
def.method("=>", "boolean").IsUnloadWhenHidden = function(self)
  return self._unload_when_hidden
end
def.method("boolean").SetUnloadWhenHidden = function(self, unload_when_hidden)
  self._unload_when_hidden = unload_when_hidden
end
def.method("boolean").SetLoadUseCfgScale = function(self, load_use_cfg_scale)
  self._load_use_cfg_scale = load_use_cfg_scale
end
def.method("=>", "number").GetSpineID = function(self)
  return self._spine_id
end
def.method("number", "varlist").SetSpineID = function(self, spine_id, on_finished)
  if self._spine_id ~= spine_id then
    self._spine_id = spine_id
    self:_Load(on_finished)
  elseif self._loaded then
    if on_finished ~= nil then
      on_finished(true)
    end
    if self._callback_init_finished ~= nil then
      for _, callback in ipairs(self._callback_init_finished) do
        _G.SafeCall(callback, true)
      end
    end
  elseif on_finished then
    local function callback(success)
      on_finished(success)
      
      for i, cb in ipairs(self._callback_init_finished) do
        if cb == callback then
          table.remove(self._callback_init_finished, i)
          break
        end
      end
    end
    
    self:OnInitFinished(callback)
  end
end
def.method("=>", "number").GetTraceIndex = function(self)
  return self._trace_index
end
def.method("number").SetTraceIndex = function(self, trace_index)
  self._trace_index = trace_index
  self:_Play()
end
def.method("=>", "boolean").IsSpineAnimationAutoPlay = function(self)
  return self._animation_auto_play
end
def.method("boolean").SetSpineAnimationAutoPlay = function(self, animation_auto_play)
  self._animation_auto_play = animation_auto_play
end
def.method("=>", "string").GetSpineAnimation = function(self)
  return self._animation
end
def.method("string", "boolean").SetSpineAnimation = function(self, animation, loop)
  if self:IsValid() and not self:GetWidget():HasAnimation(animation) then
    return
  end
  self._animation = animation
  self:SetLoop(loop)
end
def.method("varlist").PlaySpineAnimation = function(self, init)
  if self._animation_queue ~= nil and #self._animation_queue > 0 then
    self:_PlayQueue()
  elseif 0 < #self._animation then
    self:_Play()
  elseif self._animation_selector ~= nil then
    self:SelectAndPlaySpineAnimation(init)
  else
    self:OnUpdate()
  end
end
def.method("function", "varlist").SetAnimationSelector = function(self, selector, do_select)
  self._animation_selector = selector
  if do_select then
    self:SelectAndPlaySpineAnimation(false)
  end
end
def.method("varlist").SelectAndPlaySpineAnimation = function(self, init)
  if self._animation_selector == nil or not self:IsValid() then
    return
  end
  local animation, loop = self._animation_selector(self, self:GetWidget(), not not init)
  self:SetSpineAnimation(animation, loop)
end
def.method("string", "boolean").EnqueueSpineAnimation = function(self, animation, loop)
  local widget = self:GetWidget()
  if self:IsValid() and not widget:HasAnimation(animation) then
    return
  end
  if self._animation_queue == nil then
    self._animation_queue = {}
  end
  table.insert(self._animation_queue, {animation = animation, loop = loop})
  if self:IsValid() and self._loaded then
    local delay = 0
    if #self._animation_queue > 1 then
      delay = widget:GetAnimationDuration(self._animation_queue[#self._animation_queue - 1].animation)
    end
    widget:AddAnimation(self._trace_index, animation, loop, delay)
  end
end
def.method().ReplaySpineAnimationQueue = function(self)
  self:_PlayQueue()
end
def.method().ClearSpineAnimationQueue = function(self)
  self._animation_queue = nil
end
def.method("=>", "boolean").GetLoop = function(self)
  return self._loop
end
def.method("boolean").SetLoop = function(self, loop)
  self._loop = loop
  self:_Play()
end
def.method().StartTick = function(self)
  if not (self._auto_tick and self._loaded) or self._tick_timer > 0 then
    return
  end
  self._tick_timer = GameUtil.AddGlobalTimer(0.02, false, function()
    if self:IsValid() then
      self:GetWidget():Tick(0.025)
    end
  end)
  if self._play_mode == PLAY_MODE.SINGLE and not self._loop then
    self._animation_timer = GameUtil.AddGlobalTimer(self:GetWidget():GetAnimationDuration(self._animation), true, function()
      self:StopTick()
      if self:IsValid() then
        self:SelectAndPlaySpineAnimation(false)
      end
    end)
  end
end
def.method().StopTick = function(self)
  if self._tick_timer > 0 then
    GameUtil.RemoveGlobalTimer(self._tick_timer)
    self._tick_timer = 0
  end
  if self._animation_timer ~= 0 then
    GameUtil.RemoveGlobalTimer(self._animation_timer)
    self._animation_timer = 0
  end
end
def.method("boolean").SetAutoTick = function(self, auto_tick)
  self._auto_tick = auto_tick
end
def.method("function", "varlist").OnInitFinished = function(self, callback, unregister)
  if callback == nil then
    return
  end
  if not unregister then
    if self._callback_init_finished == nil then
      self._callback_init_finished = {}
    end
    table.insert(self._callback_init_finished, callback)
    if self._loaded then
      _G.SafeCall(callback, true)
    end
  elseif self._callback_init_finished ~= nil then
    local index = table.indexof(self._callback_init_finished, callback)
    if index then
      table.remove(self._callback_init_finished, index)
    end
  end
end
def.method("userdata", "userdata", "userdata")._OnSpineAnimationStart = function(self, widget, _, track_entry)
  if self._callback_animation_start == nil then
    return
  end
  for _, callback in ipairs(self._callback_animation_start) do
    _G.SafeCall(callback, track_entry:getAnimationName(), track_entry:getAnimationDuration(), track_entry:GetLoop())
  end
end
def.method("function", "varlist").OnSpineAnimationStart = function(self, callback, unregister)
  if callback == nil then
    return
  end
  if not unregister then
    if self._callback_animation_start == nil then
      self._callback_animation_start = {}
      self:_CheckCallback(_G.SpineEventType.EventType_Start, true, _G.WrapOne(self._OnSpineAnimationStart, self))
    end
    table.insert(self._callback_animation_start, callback)
  elseif self._callback_animation_start ~= nil then
    local index = table.indexof(self._callback_animation_start, callback)
    if index then
      table.remove(self._callback_animation_start, index)
      if #self._callback_animation_start < 1 then
        self._callback_animation_start = nil
        self:_CheckCallback(_G.SpineEventType.EventType_Start, false, nil)
      end
    end
  end
end
def.method("userdata", "userdata", "userdata")._OnSpineAnimationStop = function(self, widget, _, track_entry)
  if self._callback_animation_stop == nil then
    return
  end
  for _, callback in ipairs(self._callback_animation_stop) do
    _G.SafeCall(callback, track_entry:getAnimationName(), track_entry:getAnimationDuration(), track_entry:GetLoop())
  end
end
def.method("function", "varlist").OnSpineAnimationStop = function(self, callback, unregister)
  if callback == nil then
    return
  end
  if not unregister then
    if self._callback_animation_stop == nil then
      self._callback_animation_stop = {}
      self:_CheckCallback(_G.SpineEventType.EventType_End, true, _G.WrapOne(self._OnSpineAnimationStop, self))
    end
    table.insert(self._callback_animation_stop, callback)
  elseif self._callback_animation_stop ~= nil then
    local index = table.indexof(self._callback_animation_stop, callback)
    if index then
      table.remove(self._callback_animation_stop, index)
      if #self._callback_animation_stop < 1 then
        self._callback_animation_stop = nil
        self:_CheckCallback(_G.SpineEventType.EventType_End, false, nil)
      end
    end
  end
end
def.method().ClearOnSpineAnimationStop = function(self)
  if self._callback_animation_stop ~= nil then
    self._callback_animation_stop = nil
    self:_CheckCallback(_G.SpineEventType.EventType_End, false, nil)
  end
end
def.method("userdata", "userdata", "userdata", "table")._OnSpineAnimationEvent = function(self, widget, _, track_entry, params)
  if self._callback_animation_event == nil then
    return
  end
  local callback_list = self._callback_animation_event[params.name]
  if callback_list == nil then
    return
  end
  for _, callback in ipairs(callback_list) do
    _G.SafeCall(callback, track_entry:getAnimationName(), params.time, params.stringValue, params.intValue, params.floatValue)
  end
end
def.method("string", "function", "varlist").OnSpineAnimationEvent = function(self, name, callback, unregister)
  if #name < 1 or callback == nil then
    return
  end
  if not unregister then
    if self._callback_animation_event == nil then
      self._callback_animation_event = {}
      self:_CheckCallback(_G.SpineEventType.EventType_Event, true, _G.WrapOne(self._OnSpineAnimationEvent, self))
    end
    local callback_list = self._callback_animation_event[name]
    if callback_list == nil then
      callback_list = {}
      self._callback_animation_event[name] = callback_list
    end
    table.insert(callback_list, callback)
  elseif self._callback_animation_event ~= nil then
    local callback_list = self._callback_animation_event[name]
    if callback_list ~= nil then
      local index = table.indexof(callback_list, callback)
      if index then
        table.remove(callback_list, index)
        if #callback_list < 1 then
          self._callback_animation_event[name] = nil
          if next(self._callback_animation_event) == nil then
            self._callback_animation_event = nil
            self:_CheckCallback(_G.SpineEventType.EventType_Event, false, nil)
          end
        end
      end
    end
  end
end
def.method("=>", "number").GetPanelType = function(self)
  return self._panel_type
end
def.method("number").SetPanelType = function(self, panel_type)
  self._panel_type = panel_type
  self:OnUpdate()
end
def.method("=>", "number", "number", "number", "number").GetBounds = function(self)
  if self:IsValid() then
    local widget = self:GetWidget()
    local width, height, min_x, min_y = widget:GetBounds()
    return width, height, min_x, min_y
  else
    return 0, 0, 0, 0
  end
end
def.method("number", "number").SetRenderTranslation = function(self, x, y)
  self._customized_offset_x = x
  self._customized_offset_y = y
  self:OnUpdate()
end
def.method("number", "number").SetRenderTransformPivot = function(self, x, y)
  if not self:IsValid() then
    return
  end
  self:GetWidget():SetRenderTransformPivot({x = x, y = y})
end
def.method("=>", "number", "number").GetRenderScale = function(self)
  if not self:IsValid() then
    return 0, 0
  end
  local widget = self:GetWidget()
  local scale_x, scale_y = widget:GetRenderScale()
  return scale_x, scale_y
end
def.method("number", "number").SetRenderScale = function(self, x, y)
  self._customized_scale_x = x
  self._customized_scale_y = y
  self:OnUpdate()
end
def.override().OnUpdate = function(self)
  if not self:IsValid() then
    return
  end
  local widget = self:GetWidget()
  local width, height, min_x, min_y = widget:GetBounds()
  if 0 < width and 0 < height then
    widget:SetRenderTransformPivot({
      x = -min_x / width,
      y = 1 + min_y / height
    })
  end
  local scale = gInterface.Common.Config.GetPanelSpineScale(self._panel_type) * 1.0E-4
  local spine_adjust_cfg = gInterface.Common.Config.GetSpineAdjustConfig(self._spine_id, true)
  if spine_adjust_cfg ~= nil then
    scale = scale * spine_adjust_cfg.scaleDefault * 1.0E-4
  end
  local align_x, align_y = widget:GetSlotAlignment()
  local offset_x, offset_y = min_x + align_x * width, min_y + (1 - align_y) * height
  local scale_x, scale_y = scale * self._customized_scale_x, scale * self._customized_scale_y
  widget:SetRenderTranslation({
    x = offset_x + self._customized_offset_x,
    y = -1 * offset_y + self._customized_offset_y
  })
  widget:SetRenderScale({x = scale_x, y = scale_y})
end
return ViewSpineWidget.Commit()
