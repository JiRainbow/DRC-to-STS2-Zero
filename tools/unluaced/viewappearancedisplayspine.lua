local Lplus = require("Lplus")
local ViewAppearanceBase = require("Modules.Common.UI.Appearance.ViewAppearanceBase")
local ViewSpineWidget = require("Modules.Common.UI.ViewSpineWidget")
local ViewAppearanceDisplaySpine = Lplus.Extend(ViewAppearanceBase, "ViewAppearanceDisplaySpine")
local def = ViewAppearanceDisplaySpine.define
local FADE_ORIENTATION = {LEFT = -1, RIGHT = 1}
def.const("table").FADE_ORIENTATION = FADE_ORIENTATION
def.field(ViewSpineWidget)._view_spine_widget = nil
def.field("number")._offset_x = 0
def.field("number")._offset_y = 0
def.field("number")._scale_x = 1
def.field("number")._scale_y = 1
def.field("number")._fade_distance_x = 0
def.field("number")._fade_distance_y = 0
def.field("number")._fade_scale_delta_x = 0
def.field("number")._fade_scale_delta_y = 0
def.field("boolean")._fade_scale_balance = false
def.field("number")._fade_percent = 0
def.field("number")._fade_timer = 0
def.constructor().ViewPartnerSpine = function(self)
  self._view_spine_widget = ViewSpineWidget()
end
def.override().InitSubViews = function(self)
  self:RegisterSubView("SpineWidget", self._view_spine_widget)
end
def.override().OnCreate = function(self)
  self:OnUpdate()
end
def.override().OnDestroy = function(self)
  ViewAppearanceBase.OnDestroy(self)
  self._fade_percent = 0
  if self._fade_timer ~= 0 then
    GameUtil.RemoveGlobalTimer(self._fade_timer)
    self._fade_timer = 0
  end
end
def.override("boolean").OnShow = function(self, show)
  if show then
    self._view_spine_widget:StartTick()
  else
    self._view_spine_widget:StopTick()
  end
end
def.override().OnUpdate = function(self)
  if not self:IsValid() then
    return
  end
  if self:GetAppearanceID() < 1 then
    self:Show(false)
    return
  end
  local appearance_cfg = self:GetAppearanceConfig()
  if appearance_cfg == nil then
    self:Show(false)
    return
  end
  self._view_spine_widget:SetSpineID(appearance_cfg.displaySpineId)
  self:UpdateTransform()
  self:Show(true)
end
def.method().UpdateTransform = function(self)
  if not self:IsValid() then
    return
  end
  local absolute_fade_percent = self:GetAbsoluteFadePercent()
  self._view_spine_widget:SetRenderTranslation(self._offset_x + self._fade_percent * self._fade_distance_x, self._offset_y + self._fade_percent * self._fade_distance_y)
  self._view_spine_widget:SetRenderScale(self._scale_x * (1 + self._fade_scale_delta_x * (self._fade_scale_balance and absolute_fade_percent or self._fade_percent)), self._scale_y * (1 + self._fade_scale_delta_y * (self._fade_scale_balance and absolute_fade_percent or self._fade_percent)))
  self._view_spine_widget:SetRenderOpacity(1 - absolute_fade_percent)
end
def.method("=>", ViewSpineWidget).GetSpine = function(self)
  return self._view_spine_widget
end
def.method("=>", "number").GetOffsetX = function(self)
  return self._offset_x
end
def.method("number", "varlist").SetOffsetX = function(self, offset_x, no_update)
  self._offset_x = offset_x
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "number").GetOffsetY = function(self)
  return self._offset_y
end
def.method("number", "varlist").SetOffsetY = function(self, offset_y, no_update)
  self._offset_y = offset_y
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "number").GetScaleX = function(self)
  return self._scale_x
end
def.method("number", "varlist").SetScaleX = function(self, scale_x, no_update)
  self._scale_x = scale_x
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "number").GetScaleY = function(self)
  return self._scale_y
end
def.method("number", "varlist").SetScaleY = function(self, scale_y, no_update)
  self._scale_y = scale_y
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "number").GetFadeDistanceX = function(self)
  return self._fade_distance_x
end
def.method("number", "varlist").SetFadeDistanceX = function(self, fade_distance_x, no_update)
  self._fade_distance_x = math.max(fade_distance_x, 0)
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "number").GetFadeDistanceY = function(self)
  return self._fade_distance_y
end
def.method("number", "varlist").SetFadeDistanceY = function(self, fade_distance_y, no_update)
  self._fade_distance_y = math.max(fade_distance_y, 0)
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "number").GetFadeScaleDeltaX = function(self)
  return self._fade_scale_delta_x
end
def.method("number", "varlist").SetFadeScaleDeltaX = function(self, fade_scale_delta_x, no_update)
  self._fade_scale_delta_x = math.max(fade_scale_delta_x, 0)
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "number").GetFadeScaleDeltaY = function(self)
  return self._fade_scale_delta_y
end
def.method("number", "varlist").SetFadeScaleDeltaY = function(self, fade_scale_delta_y, no_update)
  self._fade_scale_delta_y = math.max(fade_scale_delta_y, 0)
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "boolean").GetFadeScaleBalance = function(self)
  return self._fade_scale_balance
end
def.method("boolean", "varlist").SetFadeScaleBalance = function(self, fade_scale_balance, no_update)
  self._fade_scale_balance = fade_scale_balance
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("=>", "number").GetFadePercent = function(self)
  return self._fade_percent
end
def.method("=>", "number").GetAbsoluteFadePercent = function(self)
  return math.abs(self._fade_percent)
end
def.method("number", "varlist").SetFadePercent = function(self, percent, no_update)
  self._fade_percent = math.clamp(percent, -1, 1)
  if not no_update then
    self:UpdateTransform()
  end
end
def.method("number", "varlist").AddFadePercent = function(self, delta, no_update)
  self:SetFadePercent(self._fade_percent + delta, no_update)
end
def.method("varlist").FadeIn = function(self, callback, orientation, duration)
  if self._fade_timer ~= 0 then
    return
  end
  if orientation ~= FADE_ORIENTATION.LEFT and orientation ~= FADE_ORIENTATION.RIGHT then
    orientation = FADE_ORIENTATION.LEFT
  end
  if type(duration) ~= "number" then
    duration = 0.2
  elseif duration <= 0 then
    self:SetFadePercent(0)
    if type(callback) == "function" then
      callback()
    end
    return
  end
  local start = Time.get_realtimeSinceStartup()
  self._fade_percent = orientation * -1
  self._fade_timer = GameUtil.AddGlobalTimer(0, false, function()
    if not self:IsValid() then
      return
    end
    local percent = (1 - (Time.get_realtimeSinceStartup() - start) / duration) * orientation * -1
    if percent * self:GetFadePercent() < 0 then
      self:SetFadePercent(0)
      if self._fade_timer ~= 0 then
        GameUtil.RemoveGlobalTimer(self._fade_timer)
        self._fade_timer = 0
      end
      if type(callback) == "function" then
        callback()
      end
    else
      self:SetFadePercent(percent)
    end
  end)
end
def.method("varlist").FadeOut = function(self, callback, orientation, duration)
  if self._fade_timer ~= 0 then
    return
  end
  if orientation ~= FADE_ORIENTATION.LEFT and orientation ~= FADE_ORIENTATION.RIGHT then
    orientation = FADE_ORIENTATION.LEFT
  end
  if type(duration) ~= "number" then
    duration = 0.2
  elseif duration <= 0 then
    self:SetFadePercent(orientation)
    if type(callback) == "function" then
      callback()
    end
    return
  end
  local start = Time.get_realtimeSinceStartup()
  self._fade_percent = 0
  self._fade_timer = GameUtil.AddGlobalTimer(0, false, function()
    if not self:IsValid() then
      return
    end
    local percent = (Time.get_realtimeSinceStartup() - start) / duration * orientation
    if math.abs(percent) > 1 then
      self:SetFadePercent(orientation)
      if self._fade_timer ~= 0 then
        GameUtil.RemoveGlobalTimer(self._fade_timer)
        self._fade_timer = 0
      end
      if type(callback) == "function" then
        callback()
      end
    else
      self:SetFadePercent(percent)
    end
  end)
end
def.method("number", "varlist").SetAppearanceIDWithFade = function(self, appearance_id, callback, orientation, duration)
  if self._fade_timer ~= 0 then
    if type(callback) == "function" then
      callback(false)
    end
    return
  end
  if self:GetAppearanceID() == appearance_id then
    if type(callback) == "function" then
      callback(true)
    end
    return
  end
  self:FadeOut(function()
    self:SetAppearanceID(appearance_id, true)
    local appearance_cfg = self:GetAppearanceConfig()
    if appearance_cfg == nil then
      if type(callback) == "function" then
        callback(false)
      end
      return
    end
    self._view_spine_widget:SetSpineID(appearance_cfg.displaySpineId, function(success)
      if success then
        self:FadeIn(function()
          if type(callback) == "function" then
            callback(true)
          end
        end, orientation, duration)
      elseif type(callback) == "function" then
        callback(false)
      end
    end)
  end, orientation, duration)
end
def.method("=>", "boolean").IsFading = function(self)
  return self._fade_timer ~= 0
end
return ViewAppearanceDisplaySpine.Commit()
