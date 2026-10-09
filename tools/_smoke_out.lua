string.format = utility.genformatex(string.format)
_G.g_StoreCode = 0
_G.g_ProgramVersion = 0
_G.g_ResBaseVersion = 0
_G.g_VersionDescriptionName = "1.0.1"

function _G.GetDisplayVersion()
  local localVersiton = Patcher.getLocalVersion()
  local resourceVersion = 0 < localVersiton and localVersiton or g_ResBaseVersion
  return g_VersionDescriptionName .. "." .. resourceVersion
end

function _G.GetClientVersion(bWithResourceVersion)
  if bWithResourceVersion then
    local localVersiton = Patcher.getLocalVersion()
    local resourceVersion = 0 < localVersiton and localVersiton or _G.g_ResBaseVersion
    return string.format("%s.%d.%d.%d", _G.g_VersionDescriptionName, _G.g_StoreCode, _G.g_ProgramVersion, resourceVersion)
  else
    return string.format("%s.%d.%d", _G.g_VersionDescriptionName, _G.g_StoreCode, _G.g_ProgramVersion)
  end
end

function _G.IsEvaluation()
  return false
end

function _G.IsEvaluationUpdate()
  return false
end

require("Launch.initgame")
