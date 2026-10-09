local Lplus = require("Lplus")
local ECPanelBase = require("Core.GUI.ECPanelBase")
local ECWidgetList = require("Core.GUI.ECWidgetList")
local ECCompactScrollList = require("Core.GUI.ECCompactScrollList")
local ViewBackButton = require("Modules.Common.UI.ViewBackButton")
local ViewAppearanceDisplaySpine = require("Modules.Common.UI.Appearance.ViewAppearanceDisplaySpine")
local ViewAppearanceFightSpine = require("Modules.Common.UI.Appearance.ViewAppearanceFightSpine")
local ViewSkinCard = require("Modules.Partner.UI.Skin.ViewSkinCard")
local ViewSkinDot = require("Modules.Partner.UI.Skin.ViewSkinDot")
local PanelSkin = Lplus.Extend(ECPanelBase, "PanelSkin")
local def = PanelSkin.define
def.field(ViewBackButton)._view_back_btn = nil
def.field(ViewAppearanceDisplaySpine)._view_display_spine = nil
def.field(ViewAppearanceFightSpine)._view_fight_spine = nil
def.field(ECWidgetList)._view_appearance_list = nil
def.field(ECCompactScrollList)._view_dot_list = nil
def.field("number")._partner_id = -1
def.field("number")._appearance_id = -1
def.field("boolean")._is_scrolling = false
local instance
def.static("=>", PanelSkin).Instance = function()
  if instance == nil then
    instance = PanelSkin()
  end
  return instance
end
def.constructor().PanelSkin = function(self)
  self._view_back_btn = ViewBackButton(_G.Textres.Partner.Title.Skin)
  self._view_display_spine = ViewAppearanceDisplaySpine()
  self._view_display_spine:GetSpine():SetAnimationSelector(gInterface.Partner.SkinMgr.SingleLoopAnimationSelector)
  self._view_fight_spine = ViewAppearanceFightSpine()
  self._view_fight_spine:GetSpine():SetAnimationSelector(function(view, widget, init)
    return "idle", true
  end)
  self._view_appearance_list = ECWidgetList(function(index, widget, data)
    return ViewSkinCard()
  end)
  self._view_dot_list = ECCompactScrollList(function(index, widget, data)
    return ViewSkinDot()
  end)
  self:RegisterEventHandlerMethod(gEvent.Role.AppearanceChanged, "OnHostAppearanceChanged")
  self:RegisterEventHandlerMethod(gEvent.Partner.SkinChanged, "OnPartnerSkinChanged")
  self:RegisterEventHandlerMethod(gEvent.Partner.SkinUnlocked, "OnPartnerSkinUnlocked")
end
def.override("=>", "string").GetAssetPath = function(self)
  return _G.ResPath.Panel_FashionMain
end
def.override("=>", "boolean").IsFullScreenPanel = function(self)
  return true
end
def.override().InitSubViews = function(self)
  self:RegisterSubView("SafeZone/Content/Group_Common/Panel_BackBtn", self._view_back_btn)
  self:RegisterSubView("SafeZone/Content/View_Appearance_Display_Spine", self._view_display_spine)
  self:RegisterSubView("SafeZone/Content/Group_Left/Group_Spine/View_Appearance_Fight_Spine", self._view_fight_spine)
  self:RegisterSubView("SafeZone/Content/Group_Right/Group_Switch/SL_Fashion", self._view_appearance_list)
  self:RegisterSubView("SafeZone/Content/Group_Right/CompactList_PageDot", self._view_dot_list)
end
def.override().OnCreate = function(self)
  self._view_appearance_list:GetWidget():SetMiddleItemChangeFunc(function(widget, index)
    if not self._is_scrolling then
      return
    end
    local appearance_id = self._view_appearance_list:GetData(index)
    if type(appearance_id) == "number" and 0 < appearance_id then
      self:SetAppearanceID(appearance_id, true)
      _G.SoundManager:PostEvent("Play_Sound_ui_common_click_02")
    end
  end)
  self:AutoScroll()
  ECGUITools.setVisibility(self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Spacer_Artist"), ESlateVisibility.Hidden)
end
def.override().OnDestroy = function(self)
  self._partner_id = -1
  self._appearance_id = -1
  self._is_scrolling = false
end
def.override("=>", "dynamic").GetDataContext = function(self)
  return self._partner_id
end
def.override("dynamic").SetDataContext = function(self, data)
  if not self:CanShow(false, data) or self._partner_id == data then
    return
  end
  local partner_data = gInterface.Partner.GetPartnerData(data)
  if partner_data == nil then
    return
  end
  self._partner_id = data
  local appearance_id_list = partner_data:GetAllAppearanceID()
  self._view_dot_list:SetDataContext(appearance_id_list)
  appearance_id_list = clone(appearance_id_list)
  table.insert(appearance_id_list, 1, -1)
  table.insert(appearance_id_list, -1)
  self._view_appearance_list:SetDataContext(appearance_id_list)
  self:SetAppearanceID(partner_data:GetAppearanceID())
end
def.method("=>", "number").GetAppearanceID = function(self)
  return self._appearance_id
end
def.method("number", "varlist").SetAppearanceID = function(self, appearance_id, no_auto_scroll)
  if self._appearance_id == appearance_id then
    return
  end
  self._appearance_id = appearance_id
  self._view_display_spine:SetAppearanceID(appearance_id, true)
  self._view_fight_spine:SetAppearanceID(appearance_id, true)
  if not no_auto_scroll then
    self:AutoScroll()
  end
  self:OnUpdate()
end
def.method().AutoScroll = function(self)
  local appearance_id = self._appearance_id
  GameUtil.AddGlobalTimer(0.1, true, function()
    if self._view_appearance_list:IsValid() then
      self._view_appearance_list:GetWidget():SetFirstIndex(self._view_appearance_list:GetDataIndex(appearance_id), true, 0, _G.EDescendantScrollDestination.Center)
    end
  end)
end
def.override("varlist", "=>", "boolean").CanShow = function(self, prompt, data)
  if _G.IsCrossingServer(prompt and _G.Textres.Common.IsCrossingServer or false) then
    return false
  end
  return type(data) == "number" and gInterface.Partner.IsPartnerUnlock(data)
end
def.override().OnGUIChange = function(self)
  self:OnUpdate()
end
def.override().OnUpdate = function(self)
  if not self:IsValid() then
    return
  end
  local partner_data = gInterface.Partner.GetPartnerData(self._partner_id)
  if partner_data == nil then
    self:DestroyPanel(true)
    return
  end
  self._view_display_spine:OnUpdate()
  self._view_fight_spine:OnUpdate()
  local cfg = gInterface.Common.Config.GetAppearanceConfig(self._appearance_id)
  local spineCfg = gInterface.Common.Config.GetSpineResConfig(cfg.fightSpineId)
  self._view_fight_spine:GetSpine():SetRenderTranslation(spineCfg.posX, spineCfg.posY)
  self._view_appearance_list:UpdateViews()
  self._view_dot_list:ForceUpdate()
  ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_Left/Group_Name/Txt_PartnerName"), partner_data:GetName())
  ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_Right/Txt_SkinName/Txt_Name"), partner_data:GetAppearanceName(self._appearance_id))
  local is_unlock = partner_data:IsAppearanceUnlocked(self._appearance_id)
  local unlock_award
  if not partner_data:IsHost() then
    local skin_id = gInterface.Partner.Config.GetSkinIDByAppearanceID(self._appearance_id)
    if 0 < skin_id then
      local skin_cfg = gInterface.Partner.Config.GetSkinConfig(skin_id)
      if skin_cfg ~= nil then
        local list = {}
        local unified_value_str
        for prop_type, prop_value in pairs(skin_cfg.properties) do
          local name, value = gInterface.Property.GetPropShortNameAndValueWithSign(prop_type, prop_value)
          if unified_value_str == nil then
            unified_value_str = value
          elseif 0 < #unified_value_str and unified_value_str ~= value then
            unified_value_str = ""
          end
          table.insert(list, {
            type = prop_type,
            name = name,
            value = value
          })
        end
        table.sort(list, gInterface.Property.DefaultSorter)
        if unified_value_str ~= nil and 0 < #unified_value_str then
          for _, info in ipairs(list) do
            if unlock_award == nil then
              unlock_award = _G.Textres.Partner.AllSquadPartner .. info.name
            else
              unlock_award = unlock_award .. _G.Textres.Partner.SkinPropSeparator .. info.name
            end
          end
          unlock_award = unlock_award .. unified_value_str
        else
          for _, info in ipairs(list) do
            if unlock_award == nil then
              unlock_award = _G.Textres.Partner.AllSquadPartner .. info.name .. info.value
            else
              unlock_award = unlock_award .. _G.Textres.Partner.SkinPropSeparator .. info.name .. info.value
            end
          end
        end
      end
    end
  end
  ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone/Content/Group_Right/Group_Title"), unlock_award ~= nil)
  ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_Right/Text_UnlockReward"), unlock_award or "")
  local is_current = partner_data:GetAppearanceID() == self._appearance_id
  local Btn_Get = self:FindDirect("SafeZone/Content/Group_Right/Btn_Get")
  local Txt_Wearing = self:FindDirect("SafeZone/Content/Group_Right/Txt_Wearing")
  if is_current then
    ECGUITools.setVisible(Btn_Get, false)
    ECGUITools.setVisible_NoClick(Txt_Wearing, true)
  else
    ECGUITools.setVisible(Btn_Get, true)
    ECGUITools.setVisible_NoClick(Txt_Wearing, false)
    if is_unlock then
      ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_Right/Btn_Get/Group_Btn_Get/Txt_Btn_Get"), _G.Textres.Partner.SkinState.Unlocked)
    else
      ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_Right/Btn_Get/Group_Btn_Get/Txt_Btn_Get"), _G.Textres.Partner.SkinState.Get)
    end
  end
  self:UpdatePainterName()
end
def.method("table", "table").OnHostAppearanceChanged = function(self, sender, event)
  if event.Success and gInterface.Partner.IsHost(self._partner_id) then
    self:OnUpdate()
  end
end
def.method("table", "table").OnPartnerSkinChanged = function(self, sender, event)
  if event.Success and event.PartnerID == self._partner_id then
    self:OnUpdate()
  end
end
def.method("table", "table").OnPartnerSkinUnlocked = function(self, sender, event)
  if event.PartnerID == self._partner_id then
    self:OnUpdate()
  end
end
def.method("string").onScrollBegin = function(self, id)
  if id == "SL_Fashion" then
    self._is_scrolling = true
  end
end
def.method("string").onScrollEnd = function(self, id)
  if id == "SL_Fashion" then
    self._is_scrolling = false
    self:AutoScroll()
  end
end
def.method("string").onClick = function(self, id)
  if id == "Btn_Get" then
    local partner_data = gInterface.Partner.GetPartnerData(self._partner_id)
    if partner_data == nil or partner_data:GetAppearanceID() == self._appearance_id then
      return
    end
    if partner_data:IsAppearanceUnlocked(self._appearance_id) then
      if partner_data:IsHost() then
        require("Modules.Role.RoleMgr").Request_RoleChangeAppearance(self._appearance_id)
      else
        local skin_id = gInterface.Partner.Config.GetSkinIDByAppearanceID(self._appearance_id)
        if 0 < skin_id then
          gInterface.Partner.Network.Request_WearFashion(self._partner_id, skin_id)
        end
      end
    elseif not partner_data:IsHost() then
      local skin_id = gInterface.Partner.Config.GetSkinIDByAppearanceID(self._appearance_id)
      if 0 < skin_id then
        local item_id = gInterface.Partner.Config.GetSkinUnlockItemIDBySkinID(skin_id)
        if 0 < item_id then
          gInterface.Item.ShowItemAccessTipsByItemId(item_id)
        end
      end
    end
  elseif id == "Btn_Focus" then
    gInterface.Partner.ShowSkinFocusPanel(self._appearance_id)
  elseif id == "Btn_Artist" then
    local partner_data = gInterface.Partner.GetPartnerData(self._partner_id)
    if partner_data == nil then
      return
    end
    local draft = partner_data:GetAppearanceDraft(self._appearance_id)
    if draft == "" then
      return
    end
    local Group_Artist_Info = self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Group_Artist_Info")
    local show = not Group_Artist_Info:GetActive()
    ECGUITools.setVisible(Group_Artist_Info, show)
    ECGUITools.setVisibility(self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Spacer_Artist"), show and ESlateVisibility.Visible or ESlateVisibility.Hidden)
  elseif id == "Spacer_Artist" then
    local Group_Artist_Info = self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Group_Artist_Info")
    ECGUITools.setVisible(Group_Artist_Info, false)
    ECGUITools.setVisibility(self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Spacer_Artist"), ESlateVisibility.Hidden)
  end
end
def.method().UpdatePainterName = function(self)
  local partner_data = gInterface.Partner.GetPartnerData(self._partner_id)
  if partner_data == nil then
    return
  end
  local painter_name = partner_data:GetAppearancePainterName(self._appearance_id)
  ECGUITools.setVisible(self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist"), true)
  ECGUITools.setActiveWidgetIndex(self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Btn_Artist/WS_Artist"), painter_name == "" and 1 or 0)
  if painter_name == "" then
    painter_name = Textres.Partner.PartnerSkinPainterDefaultName
  end
  ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Txt_ArtistName"), painter_name)
  local draft = partner_data:GetAppearanceDraft(self._appearance_id)
  local Group_Artist_Info = self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Group_Artist_Info")
  if draft ~= "" then
    local draft_list = self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Group_Artist_Info/FixedList_Artist_Info")
    draft_list:SetCount(2)
    local draft_item_1 = draft_list:GetItem(1)
    ECGUITools.setTextAndColor(draft_item_1:FindDirect("Content/HorizontalBox_Text/Text_Artist"), Textres.Partner.PartnerSkinDraft)
    ECGUITools.setTextAndColor(draft_item_1:FindDirect("Content/HorizontalBox_Text/Text_Name"), draft)
    local draft_item_2 = draft_list:GetItem(2)
    ECGUITools.setTextAndColor(draft_item_2:FindDirect("Content/HorizontalBox_Text/Text_Artist"), Textres.Partner.PartnerSkinPainterName)
    ECGUITools.setTextAndColor(draft_item_2:FindDirect("Content/HorizontalBox_Text/Text_Name"), painter_name)
  else
    ECGUITools.setVisible(Group_Artist_Info, false)
    ECGUITools.setVisibility(self:FindDirect("SafeZone/Content/Group_Left/Group_Name_Artist/Spacer_Artist"), ESlateVisibility.Hidden)
  end
end
return PanelSkin.Commit()
