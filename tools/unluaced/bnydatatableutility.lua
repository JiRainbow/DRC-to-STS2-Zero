local LRUCache = require("Core.Utility.LRUCache")
local BnyDataTableUtility = {}
local DefaultBnyDataTableConfig = {LRU_CACHE_CAPACITY = 1600, missTraceBack = false}
local BnyDataTableConfig
if _G.BnyDataTableConfig then
  BnyDataTableConfig = _G.BnyDataTableConfig
  for k, v in pairs(DefaultBnyDataTableConfig) do
    if BnyDataTableConfig[k] == nil then
      BnyDataTableConfig[k] = v
    end
  end
else
  BnyDataTableConfig = DefaultBnyDataTableConfig
end
local clsTobnytable = {}

local function getFixedBnyTable(cls)
  local bnytable = clsTobnytable[cls]
  if bnytable == nil then
    bnytable = BnyDataTable.GetFixedTable(cls.BNY_FILE_PATH)
    clsTobnytable[cls] = bnytable
  end
  return bnytable
end

local function getDynamicBnyTable(cls)
  local bnytable = clsTobnytable[cls]
  if bnytable == nil then
    bnytable = BnyDataTable.GetDynamicTable(cls.BNY_FILE_PATH)
    clsTobnytable[cls] = bnytable
  end
  return bnytable
end

local function getFixedRecord(cls, key, isTry)
  local bnytable = getFixedBnyTable(cls)
  if bnytable == nil then
    return nil, nil
  end
  local record, boundCls = BnyDataTable.GetFixedRecord(bnytable, key, isTry)
  if record == nil and not isTry and BnyDataTableConfig.missTraceBack then
    warn(debug.traceback("call from"))
  end
  return record, boundCls
end

local function getDynamicRecord(cls, key, isTry)
  local bnytable = getDynamicBnyTable(cls)
  if bnytable == nil then
    return nil, nil
  end
  local record, boundCls = BnyDataTable.GetDynamicRecord(bnytable, key, isTry)
  if record == nil and not isTry and BnyDataTableConfig.missTraceBack then
    warn(debug.traceback("call from"))
  end
  return record, boundCls
end

local function getAllFixedRecords(cls)
  local bnytable = getFixedBnyTable(cls)
  if bnytable == nil then
    return nil
  end
  return BnyDataTable.GetAllFixedRecords(bnytable)
end

local function getAllDynamicRecords(cls)
  local bnytable = getDynamicBnyTable(cls)
  if bnytable == nil then
    return nil
  end
  return BnyDataTable.GetAllDynamicRecords(bnytable)
end

local function getFixedRecordsCount(cls)
  local bnytable = getFixedBnyTable(cls)
  if bnytable == nil then
    return nil
  end
  return BnyDataTable.GetFixedRecordsCount(bnytable)
end

local function getDynamicRecordsCount(cls)
  local bnytable = getDynamicBnyTable(cls)
  if bnytable == nil then
    return nil
  end
  return BnyDataTable.GetDynamicRecordsCount(bnytable)
end

local _recordLRUCache
if BnyDataTableConfig.LRU_CACHE_CAPACITY > 0 then
  warn("Bny DataTable Use LRU Cache")
  _recordLRUCache = LRUCache("BnyDataRecordLRUCache", BnyDataTableConfig.LRU_CACHE_CAPACITY)
else
  warn("Bny DataTable Use All Cache")
  _recordLRUCache = {
    data = {}
  }
  
  function _recordLRUCache:Get(key)
    return self.data[key]
  end
  
  function _recordLRUCache:Set(key, value)
    self.data[key] = value
  end
  
  function _recordLRUCache:PrintStatistic()
    for k, v in pairs(self.data) do
      warn(k, v)
    end
  end
end
local _clsToLRUInfo = {}
local _lruKeyToClsInfo = {}
local _lruUniqueId = 1
local _clsAllRecords = setmetatable({}, {__mode = "v"})

local function getLRUKey(cls, key)
  local lruInfo = _clsToLRUInfo[cls]
  local lruKey
  if lruInfo == nil then
    lruKey = _lruUniqueId
    lruInfo = {}
    lruInfo[key] = lruKey
    lruInfo.__size = 1
    _clsToLRUInfo[cls] = lruInfo
    _lruUniqueId = _lruUniqueId + 1
  elseif lruInfo[key] == nil then
    lruKey = _lruUniqueId
    lruInfo[key] = lruKey
    lruInfo.__size = lruInfo.__size + 1
    _lruUniqueId = _lruUniqueId + 1
  else
    lruKey = lruInfo[key]
  end
  local clsInfo = _lruKeyToClsInfo[lruKey]
  if clsInfo == nil then
    clsInfo = {cls = cls, key = key}
    _lruKeyToClsInfo[lruKey] = clsInfo
  end
  return lruKey
end

local function addToLRUCache(lruKey, value)
  local removedKey = _recordLRUCache:Set(lruKey, value)
  if removedKey == nil then
    return
  end
  local removedKeyClsInfo = _lruKeyToClsInfo[removedKey]
  local lruInfo = _clsToLRUInfo[removedKeyClsInfo.cls]
  lruInfo[removedKeyClsInfo.key] = nil
  lruInfo.__size = lruInfo.__size - 1
  if lruInfo.__size == 0 then
    _clsToLRUInfo[removedKeyClsInfo.cls] = nil
  end
  _lruKeyToClsInfo[removedKey] = nil
end

local _getCount = 0

local function getFromLRUCache(lruKey)
  return _recordLRUCache:Get(lruKey)
end

local function getAllRecordsFromCache(cls)
  local records = _clsAllRecords[cls]
  if records then
    local newRecords = {}
    for i, v in ipairs(records) do
      newRecords[i] = v
    end
    return newRecords
  end
end

function BnyDataTableUtility.GetClassFixedRecord(cls, key, isTry)
  local lruKey = getLRUKey(cls, key)
  local record = getFromLRUCache(lruKey)
  if record then
    return record
  end
  local recordUD, boundCls = getFixedRecord(cls, key, isTry)
  if recordUD == nil then
    return nil
  end
  local useCls = boundCls or cls
  record = useCls.NewRecord(recordUD, 0, nil)
  addToLRUCache(lruKey, record)
  return record
end

function BnyDataTableUtility.GetClassAllFixedRecords(cls)
  local records = getAllRecordsFromCache(cls)
  if records then
    return records
  end
  records = {}
  local recordUDs = getAllFixedRecords(cls)
  if recordUDs == nil then
    return records
  end
  for i, recordUD in ipairs(recordUDs) do
    local boundCls = recordUD:GetClassTable()
    local useCls = boundCls or cls
    local record = useCls.NewRecord(recordUD, 0, nil)
    records[i] = record
  end
  _clsAllRecords[cls] = records
  return records
end

function BnyDataTableUtility.GetClassDynamicRecord(cls, key, isTry)
  local lruKey = getLRUKey(cls, key)
  local record = getFromLRUCache(lruKey)
  if record then
    return record
  end
  local recordUD, boundCls = getDynamicRecord(cls, key, isTry)
  if recordUD == nil then
    return nil
  end
  local useCls = boundCls or cls
  record = useCls.NewRecord(recordUD, nil, nil)
  useCls.Unmarshal(recordUD, true)
  addToLRUCache(lruKey, record)
  return record
end

function BnyDataTableUtility.GetClassAllDynamicRecords(cls)
  local records = getAllRecordsFromCache(cls)
  if records then
    return records
  end
  records = {}
  local recordUDs = getAllDynamicRecords(cls)
  if recordUDs == nil then
    return records
  end
  for i, recordUD in ipairs(recordUDs) do
    local boundCls = recordUD:GetClassTable()
    local useCls = boundCls or cls
    local record = useCls.NewRecord(recordUD, nil, nil)
    useCls.Unmarshal(recordUD, true)
    records[i] = record
  end
  _clsAllRecords[cls] = records
  return records
end

function BnyDataTableUtility.GetClassFixedTableRecordsCount(cls)
  return getFixedRecordsCount(cls)
end

function BnyDataTableUtility.GetClassDynamicTableRecordsCount(cls)
  return getDynamicRecordsCount(cls)
end

function BnyDataTableUtility.CreateFixedTableForClass(cls, record, ...)
  return BnyDataTableUtility.CreateTableForClass(cls, record, ...)
end

function BnyDataTableUtility.CreateDynamicTableForClass(cls, record, ...)
  return BnyDataTableUtility.CreateTableForClass(cls, record, ...)
end

local function tryCacheValue(t, key, value)
  local valueType = type(value)
  if valueType == "table" then
    t[key] = value
    value.__outer = t
  elseif valueType == "string" then
    t[key] = value
  end
end

local classmt = {
  __index = function(t, key)
    local cls = rawget(t, "__cls")
    local record = rawget(t, "__record")
    local extraArg1 = rawget(t, "__extraArg1")
    local method = cls[key]
    if method then
      local value, nocache = method(record, extraArg1, t)
      if not nocache then
        tryCacheValue(t, key, value)
      end
      return value
    else
      error(("field '%s' is not exist!"):format(key), 2)
      return nil
    end
  end
}
local vectormt = {
  __index = function(t, index)
    local length = rawget(t, "__length")
    if index < 1 or index > length then
      return nil
    end
    local value, nocache = rawget(t, "__getValueByIndex")(rawget(t, "__record"), index, t)
    if not nocache then
      tryCacheValue(t, index, value)
    end
    return value
  end,
  __ipairs = function(t)
    local function stateless_iter(t, index)
      index = index + 1
      
      local length = rawget(t, "__length")
      if index > length then
        return
      end
      local v = t[index]
      if v ~= nil then
        return index, v
      end
    end
    
    return stateless_iter, t, 0
  end,
  __len = function(t)
    return rawget(t, "__length")
  end
}
vectormt.__pairs = vectormt.__ipairs
local mapmt = {
  __index = function(t, key)
    local record = rawget(t, "__record")
    local keyId = rawget(t, "__getKeyId")(record, key)
    if keyId == nil then
      return nil
    end
    local value, nocache = rawget(t, "__getValueByKeyId")(record, keyId, t)
    if not nocache then
      tryCacheValue(t, key, value)
    end
    return value
  end,
  __next = function(t, key)
    local record = rawget(t, "__record")
    local keyId = rawget(t, "__getNextKeyId")(record, key)
    if keyId == nil then
      return
    end
    local key = rawget(t, "__getKey")(record, keyId)
    if key == nil then
      return
    end
    local value, nocache = rawget(t, "__getValueByKeyId")(record, keyId, t)
    if not nocache then
      tryCacheValue(t, key, value)
    end
    if value ~= nil then
      return key, value
    end
  end
}

function mapmt.__pairs(t)
  local function stateless_iter(t, key)
    return mapmt.__next(t, key)
  end
  
  return stateless_iter, t, nil
end

local setmt = {
  __index = function(t, key)
    local record = rawget(t, "__record")
    local keyId = rawget(t, "__getKeyId")(record, key)
    if keyId == nil then
      return false
    end
    return true
  end,
  __next = function(t, key)
    local record = rawget(t, "__record")
    local keyId = rawget(t, "__getNextKeyId")(record, key)
    if keyId == nil then
      return
    end
    local key = rawget(t, "__getKey")(record, keyId)
    if key == nil then
      return
    end
    return key
  end
}

function setmt.__pairs(t)
  local function stateless_iter(t, key)
    return setmt.__next(t, key)
  end
  
  return stateless_iter, t, nil
end

function BnyDataTableUtility.CreateTableForClass(cls, record, extraArg1, extraArg2)
  local t = {}
  t.__cls = cls
  t.__record = record
  t.__parent = extraArg2
  if extraArg1 == nil or type(extraArg1) == "userdata" then
    local parentRecord = extraArg1
    if parentRecord then
      t.__parentRecord = parentRecord
    end
    extraArg1 = 0
  end
  t.__extraArg1 = extraArg1
  return setmetatable(t, classmt)
end

function BnyDataTableUtility.CreateTableForFixedVector(record, offset, getValue, valueSize, parent)
  local firstValueOffset = offset + 4
  
  local function getValueByIndex(record, index, t)
    local valueOffset = firstValueOffset + (index - 1) * valueSize
    return getValue(record, valueOffset, t)
  end
  
  local vectorLength = record:GetInt32Value(offset)
  return BnyDataTableUtility.CreateTableForVector(record, nil, getValueByIndex, nil, vectorLength, parent)
end

function BnyDataTableUtility.CreateTableForVector(record, parentRecord, getValueByIndex, baseIndex, length, parent)
  local t = {}
  t.__record = record
  if length then
    t.__length = length
  elseif record.GetSize then
    t.__length = record:GetSize()
  end
  t.__length = t.__length or 0
  t.__getValueByIndex = getValueByIndex
  t.__parentRecord = parentRecord
  t.__parent = parent
  return setmetatable(t, vectormt)
end

function BnyDataTableUtility.CreateTableForFixedMap(record, parentRecord, getKey, getKeyId, getNextKeyId, getValue, keySize, valueSize, parent)
  local pairSize = keySize + valueSize
  local firstPairOffset = 4
  
  local function getValueByKeyId(record, keyId, t)
    local valueOffset = firstPairOffset + keySize + (keyId - 1) * pairSize
    return getValue(record, valueOffset, t)
  end
  
  return BnyDataTableUtility.CreateTableForMap(record, parentRecord, getKey, getKeyId, getNextKeyId, getValueByKeyId, parent)
end

function BnyDataTableUtility.CreateTableForMap(record, parentRecord, getKey, getKeyId, getNextKeyId, getValueByKeyId, parent)
  local t = {}
  t.__record = record
  t.__getKey = getKey
  t.__getKeyId = getKeyId
  t.__getNextKeyId = getNextKeyId
  t.__getValueByKeyId = getValueByKeyId
  t.__parentRecord = parentRecord
  t.__parent = parent
  if record.GetSize then
    t.size = record:GetSize()
  end
  t.size = t.size or 0
  t.firstKey = getKey(record, 1)
  t.lastKey = getKey(record, t.size)
  return setmetatable(t, mapmt)
end

function BnyDataTableUtility.CreateTableForFixedSet(record, parentRecord, getKey, getKeyId, getNextKeyId, parent)
  return BnyDataTableUtility.CreateTableForSet(record, parentRecord, getKey, getKeyId, getNextKeyId, parent)
end

function BnyDataTableUtility.CreateTableForSet(record, parentRecord, getKey, getKeyId, getNextKeyId, parent)
  local t = {}
  t.__record = record
  t.__getKey = getKey
  t.__getKeyId = getKeyId
  t.__getNextKeyId = getNextKeyId
  t.__parentRecord = parentRecord
  t.__parent = parent
  if record.GetSize then
    t.size = record:GetSize()
  end
  t.size = t.size or 0
  t.first = getKey(record, 1)
  t.last = getKey(record, t.size)
  return setmetatable(t, setmt)
end

function BnyDataTableUtility.RegisterClass(cls)
  local baseCls = cls
  while baseCls.super do
    baseCls = baseCls.super
  end
  local baseClsBnyPath
  if baseCls ~= cls then
    baseClsBnyPath = baseCls.BNY_FILE_PATH
  end
  if cls.Unmarshal then
    BnyDataTable.RegisterDynamicLuaClass(cls, cls.BNY_FILE_PATH, baseClsBnyPath)
  else
    BnyDataTable.RegisterFixedLuaClass(cls, cls.BNY_FILE_PATH, baseClsBnyPath)
  end
end

local function parseErrorContext(errorContext)
  local errorMsg
  if type(errorContext) == "function" then
    errorMsg = errorContext() or "nil"
  elseif type(errorContext) == "table" then
    if errorContext.parentContext then
      local parentContext = errorContext.parentContext
      errorContext.parentContext = nil
      errorMsg = pretty(errorContext) or "{}"
      errorMsg = errorMsg .. " <-- " .. parseErrorContext(parentContext)
      errorContext.parentContext = parentContext
    else
      errorMsg = pretty(errorContext) or "{}"
    end
  else
    errorMsg = tostring(errorContext) or "nil"
  end
  return errorMsg
end

function BnyDataTableUtility.GetRecordChecked(recordCls, key, errorContext, isErrorAbort, errorLevel)
  local record = recordCls.GetRecord(key)
  if record == nil then
    local extraMsg = parseErrorContext(errorContext)
    local errorMsg = string.format("[%s] record not found for key = %s (%s)", recordCls.__cname, key, extraMsg)
    local finalErrorLevel = errorLevel and errorLevel + 1 or 2
    if isErrorAbort or errorContext == nil then
      error(errorMsg, finalErrorLevel)
    else
      log_error(debug.traceback(errorMsg, finalErrorLevel))
    end
  end
  return record
end

function BnyDataTableUtility.GetRecordClass(record)
  if record == nil then
    return nil
  end
  return rawget(record, "__cls")
end

function BnyDataTableUtility.GetRecordRoot(t)
  if t == nil then
    return nil
  end
  local cur = t
  while true do
    local parent = rawget(cur, "__parent")
    if parent == nil then
      return cur
    end
    cur = parent
  end
end

function BnyDataTableUtility.GetRecordRootKey(t)
  local root = BnyDataTableUtility.GetRecordRoot(t)
  if root == nil then
    return 0, nil
  end
  local cls = rawget(root, "__cls")
  local secretType = cls and cls.secretType
  if secretType == nil or secretType <= 0 then
    return 0, nil
  end
  local rootKey = root.___pml_root_key___
  return secretType, rootKey
end

local magic = "\001SPML\001"
local magicLen = #magic

function BnyDataTableUtility.Decrypt(secretType, rootKey, data)
  if secretType <= 0 then
    return data, false
  end
  if data == nil then
    return data, false
  end
  if not _G.GetSecretKey then
    return data, false
  end
  local needDecrypted, key = _G.GetSecretKey(secretType, rootKey)
  if not needDecrypted then
    return data, false
  end
  if key == nil then
    return "", true
  end
  if #data <= magicLen then
    return data, false
  end
  if magic ~= string.sub(data, 1, magicLen) then
    return data, false
  end
  local decodedData = GameUtil.Base64Decode(string.sub(data, magicLen + 1))
  local decryptedData = Cryption.DesDecrypt(key, decodedData)
  return decryptedData, false
end

function BnyDataTableUtility.ParseErrorContext(errorContext)
  return parseErrorContext(errorContext)
end

function BnyDataTableUtility.PrintStatistic(showDetail)
  _recordLRUCache:PrintStatistic()
  if showDetail then
    local dataList = {}
    for cls, lruInfo in pairs(_clsToLRUInfo) do
      table.insert(dataList, {cls = cls, lruInfo = lruInfo})
    end
    table.sort(dataList, function(lhs, rhs)
      if lhs.lruInfo.__size ~= rhs.lruInfo.__size then
        return lhs.lruInfo.__size > rhs.lruInfo.__size
      else
        return lhs.cls.BNY_FILE_PATH < rhs.cls.BNY_FILE_PATH
      end
    end)
    print("BnyDataRecordLRUCache usage detail:")
    for _, data in ipairs(dataList) do
      local cls, lruInfo = data.cls, data.lruInfo
      print(string.format("BnyDataRecordLRUCache data: %s, record count: %d", cls.BNY_FILE_PATH, lruInfo.__size))
    end
  end
end

return BnyDataTableUtility
