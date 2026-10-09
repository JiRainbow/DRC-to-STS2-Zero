local Lplus = require("Lplus")
local ECWidgetListItem = require("Core.GUI.ECWidgetListItem")
local ViewAppearanceBust = require("Modules.Common.UI.Appearance.ViewAppearanceBust")
local ViewSkinCard = Lplus.Extend(ECWidgetListItem, "ViewSkinCard")
local def = ViewSkinCard.define
def.field(ViewAppearanceBust)._view_appearance_bust = nil
def.constructor().ViewSkinCard = function(self)
  self._view_appearance_bust = ViewAppearanceBust()
end
def.override().InitSubViews = function(self)
  self:RegisterSubView("Content/Group_Bust/View_Appearance_Bust", self._view_appearance_bust)
end
def.override().OnCreate = function(self)
  self:OnUpdate()
end
def.override("dynamic").SetDataContext = function(self, data)
  self._view_appearance_bust:SetAppearanceID(data, true)
  self:OnUpdate()
end
def.override().OnUpdate = function(self)
  if not self:IsValid() then
    return
  end
  if self._view_appearance_bust:GetAppearanceID() < 0 then
    self:Show(false)
    return
  end
  self._view_appearance_bust:OnUpdate()
  local owner_panel = self:GetOwnerPanel()
  local index = owner_panel ~= nil and self._view_appearance_bust:GetAppearanceID() == owner_panel:GetAppearanceID() and 1 or 0
  _G.ECGUITools.setActiveWidgetIndex(self:FindDirect("Content/WS_Bg"), index)
  _G.ECGUITools.setActiveWidgetIndex(self:FindDirect("Content/View_Fashion_Tab/Content/WS_Tab"), index)
  self:Show(true)
end
def.method("string").onClick = function(self, id)
  if id == "InteractiveArea" then
    local owner_panel = self:GetOwnerPanel()
    if owner_panel == nil then
      return
    end
    owner_panel:SetAppearanceID(self._view_appearance_bust:GetAppearanceID())
  end
end
return ViewSkinCard.Commit()
