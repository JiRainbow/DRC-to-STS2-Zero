local Lplus = require("Lplus")
local ECPanelBase = require("Core.GUI.ECPanelBase")
local ViewAppearanceDisplaySpine = require("Modules.Common.UI.Appearance.ViewAppearanceDisplaySpine")
local RarityType = require("bny.gen.drc.gsp.common.confbean.RarityType")
local PanelSkinPreview = Lplus.Extend(ECPanelBase, "PanelSkinPreview")
local def = PanelSkinPreview.define
def.field(ViewAppearanceDisplaySpine)._view_display_spine = nil
def.field("number")._skin_id = -1
local instance
def.static("=>", PanelSkinPreview).Instance = function()
  if instance == nil then
    instance = PanelSkinPreview()
  end
  return instance
end
def.constructor().PanelSkinPreview = function(self)
  self._view_display_spine = ViewAppearanceDisplaySpine()
  self._view_display_spine:GetSpine():SetAnimationSelector(gInterface.Partner.SkinMgr.SingleLoopAnimationSelector)
  self:SetTextResource(_G.Textres.UmgFixedText.Panel_Fashion_Preview)
end
def.override("=>", "string").GetAssetPath = function(self)
  return _G.ResPath.Panel_Fashion_Preview
end
def.override("varlist", "=>", "boolean").CheckAsset = function(self, prompt, data_context)
  return gInterface.InGameUpdate.CheckMiniPackThenDo("PanelSkinPreview", {
    {"PartnerUI", 1}
  }, prompt and gInterface.InGameUpdate.NotReadyHandleType.DownloadThenNotice or gInterface.InGameUpdate.NotReadyHandleType.DoNothing, nil) and ECPanelBase.CheckAsset(self, prompt, data_context)
end
def.override("=>", "boolean").IsFullScreenPanel = function(self)
  return true
end
def.override("=>", "number").GetGUILevel = function(self)
  return _G.GUILevel.DEPENDENT
end
def.override("=>", "number").GetGUIDepth = function(self)
  return _G.GUIDepth.TOP
end
def.override("=>", "boolean").ShowLoadingTip = function(self)
  return false
end
def.override("=>", "boolean").CanJumpBack = function(self)
  return false
end
def.override().InitSubViews = function(self)
  self:RegisterSubView("SafeZone_Bg/Content_Bg/View_Appearance_Display_Spine", self._view_display_spine)
end
def.override().OnDestroy = function(self)
  self._skin_id = -1
end
def.override("=>", "dynamic").GetDataContext = function(self)
  return self._skin_id
end
def.override("dynamic").SetDataContext = function(self, data)
  if not self:CanShow(false, data) or self._skin_id == data then
    return
  end
  self._skin_id = data
  self:OnUpdate()
end
def.override("varlist", "=>", "boolean").CanShow = function(self, prompt, data)
  if type(data) ~= "number" then
    return false
  end
  local skin_cfg = gInterface.Partner.Config.GetSkinConfig(data, true)
  if skin_cfg == nil then
    return false
  end
  if gInterface.Partner.GetPartnerCfg(skin_cfg.partnerId, true) == nil then
    return false
  end
  if gInterface.Common.Config.GetAppearanceConfig(skin_cfg.appearanceId, true) == nil then
    return false
  end
  return true
end
def.override("boolean").OnShow = function(self, show)
  if show then
    self:OnUpdate()
  end
  gInterface.Common.SetBubbleVisible(gInterface.Common.BubbleBlockReason.PARTNER_SKIN, not show)
end
def.override().OnGUIChange = function(self)
  self:OnUpdate()
end
def.override().OnUpdate = function(self)
  if not self:IsValid() then
    return
  end
  local skin_cfg = gInterface.Partner.Config.GetSkinConfig(self._skin_id, true)
  if skin_cfg == nil then
    self:Show(false)
    self:DestroyPanel(true)
    return
  end
  local partner_cfg = gInterface.Partner.GetPartnerCfg(skin_cfg.partnerId)
  if partner_cfg == nil then
    self:Show(false)
    self:DestroyPanel(true)
    return
  end
  local appearance_cfg = gInterface.Common.Config.GetAppearanceConfig(skin_cfg.appearanceId)
  if appearance_cfg == nil then
    self:Show(false)
    self:DestroyPanel(true)
    return
  end
  self._view_display_spine:SetAppearanceID(skin_cfg.appearanceId)
  local is_rare = partner_cfg.rarity > RarityType.SR
  if partner_cfg.rarity == RarityType.R then
    _G.ECGUITools.ActivateParticles(self:FindDirect("SafeZone_Bg/Content_Bg/vx_shine_lizi_R"), true, true)
  elseif partner_cfg.rarity == RarityType.SR then
    _G.ECGUITools.ActivateParticles(self:FindDirect("SafeZone_Bg/Content_Bg/vx_shine_lizi_SR"), true, true)
  else
    _G.ECGUITools.ActivateParticles(self:FindDirect("SafeZone_Bg/Content_Bg/vx_shine_lizi_SSR"), true, true)
  end
  _G.ECGUITools.setActiveWidgetIndex(self:FindDirect("SafeZone_Bg/Content_Bg/ScaleBox_Bg/WS_Bg"), skin_cfg.isDeepColor and 0 or 1)
  _G.ECGUITools.setActiveWidgetIndex(self:FindDirect("SafeZone/Content/WS_Top"), skin_cfg.isDeepColor and 0 or 1)
  _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone_Bg/Content_Bg/Image_CharacterBg"), false)
  _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone_Bg/Content_Bg/vx_CharacterBg_light"), false)
  _G.ECGUITools.SetImageById(self:FindDirect("SafeZone_Bg/Content_Bg/Image_CharacterBg"), skin_cfg.headIconId, nil, function()
    if self:IsValid() then
      local r, g, b, a = 0, 0, 0, 0
      if skin_cfg.accentColor ~= "" then
        r = tonumber("0x" .. skin_cfg.accentColor:sub(1, 2))
        g = tonumber("0x" .. skin_cfg.accentColor:sub(3, 4))
        b = tonumber("0x" .. skin_cfg.accentColor:sub(5, 6))
        a = tonumber("0x" .. skin_cfg.accentColor:sub(7, 8))
      end
      self:TryRunBlueprintFunc("UpdateDisplayParam", r, g, b, a)
      _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone_Bg/Content_Bg/Image_CharacterBg"), true)
      _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone_Bg/Content_Bg/vx_CharacterBg_light"), true)
    end
  end)
  if is_rare then
    _G.ECGUITools.setActiveWidgetIndex(self:FindDirect("SafeZone/Content/Group_CharacterInfo"), 0)
    _G.ECGUITools.SetImageById(self:FindDirect("SafeZone/Content/Group_CharacterInfo/Group_SSRinfo/Image_ChineseName"), skin_cfg.nameMainPicId)
    _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone/Content/Group_CharacterInfo/Group_SSRinfo/vx_EnglishName"), false)
    _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone/Content/Group_CharacterInfo/Group_SSRinfo/vx_EnglishName_light"), false)
    _G.ECGUITools.GetTextureById(skin_cfg.nameSubPicId, function(tex)
      if self:IsValid() then
        local mat_name, mat_name_light = self:TryRunBlueprintFunc("GetNameIconMatInst")
        mat_name:SetTextureParameterValue("Color1_Tex", tex)
        mat_name:SetScalarParameterValue("Dissolve", 1)
        mat_name_light:SetTextureParameterValue("Color1_Tex", tex)
        mat_name_light:SetScalarParameterValue("Dissolve", 1)
        _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone/Content/Group_CharacterInfo/Group_SSRinfo/vx_EnglishName"), true)
        _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone/Content/Group_CharacterInfo/Group_SSRinfo/vx_EnglishName_light"), true)
      end
    end)
  else
    _G.ECGUITools.setActiveWidgetIndex(self:FindDirect("SafeZone/Content/Group_CharacterInfo"), 1)
    _G.ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_CharacterInfo/Group_SRinfo/Text_CharacterName"), partner_cfg.name)
  end
  _G.ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Txt_SkinName"), string.format(_G.Textres.Partner.SkinName, appearance_cfg.name))
  _G.ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_Name/Txt_SkinDescribe"), appearance_cfg.desc)
  local unlock_award
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
  _G.ECGUITools.setVisible_NoClick(self:FindDirect("SafeZone/Content/Group_UnlockReward"), unlock_award ~= nil)
  if unlock_award then
    _G.ECGUITools.setTextAndColor(self:FindDirect("SafeZone/Content/Group_UnlockReward/Text_UnlockAttr"), string.format(Textres.Partner.SkinAttrTitle, unlock_award))
  end
end
def.method("string").onClick = function(self, id)
  if id == "Spacer_Close" then
    self:DestroyPanel()
  end
end
return PanelSkinPreview.Commit()
