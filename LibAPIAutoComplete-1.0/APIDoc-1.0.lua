local MAJOR, MINOR = "APIDoc-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local config = {}

local function LoadBlizzard_APIDocumentation()
  local apiAddonName = "Blizzard_APIDocumentation"
  local _, loaded = C_AddOns.IsAddOnLoaded(apiAddonName)
  if not loaded then
    C_AddOns.LoadAddOn(apiAddonName)
  end
  if #APIDocumentation.systems == 0 then
    APIDocumentation_LoadUI()
  end
end

---Create APIDoc widget and ensure Blizzard_APIDocumentation is loaded
local isInit = false
local function Init()
  if isInit then
    return
  end
  isInit = true

  -- load Blizzard_APIDocumentation
  LoadBlizzard_APIDocumentation()

  local scrollBox = CreateFrame("Frame", nil, UIParent, "WowScrollBoxList")
  scrollBox:SetSize(400, 150)
  scrollBox:Hide()

  local background = scrollBox:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  scrollBox.background = background

  local scrollBar = CreateFrame("EventFrame", nil, UIParent, "WowTrimScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT")
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT")
  scrollBar:Hide()

  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("APILineTemplate", function(frame, elementData)
    frame:Init(elementData)
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  lib.data = CreateDataProvider()
  scrollBox:SetDataProvider(lib.data)

  lib.scrollBar = scrollBar
  lib.scrollBox = scrollBox
end

---@private
---@param editbox EditBox
---@param x number
---@param y number
---@param w number
---@param h number
local function OnCursorChanged(editbox, x, y, w, h)
  lib.scrollBox:Hide()
  lib.scrollBar:Hide()
  lib.scrollBox:ClearAllPoints()
  lib.scrollBox:SetPoint("TOPLEFT", editbox, "TOPLEFT", x, y - h)
  local currentWord = lib:GetWord(editbox)
  if #currentWord > 4 then
    lib:Search(currentWord)
    lib:UpdateWidget(editbox)
  end
end

---@class Color
---@field r integer
---@field g integer
---@field b integer
---@field a integer?

---@class Params
---@field backgroundColor Color?
---@field maxLinesShown integer?

---Enable APIDoc widget on editbox
---ForAllIndentsAndPurpose replace GetText, APIDoc must be enabled before FAIAP
---@param editbox EditBox
---@param params Params
function lib:enable(editbox, params)
  if config[editbox] then
    return
  end
  config[editbox] = {
    backgroundColor = params and params.backgroundColor or {.3, .3, .3, .9},
    maxLinesShown = params and params.maxLinesShown or 7,
  }
  Init()
  editbox.APIDoc_oldOnCursorChanged = editbox:GetScript("OnCursorChanged")
  -- hack for WeakAuras
  editbox.APIDoc_originalGetText = editbox.GetText
  -- hack for WowLua
  if editbox == WowLuaFrameEditBox then
    editbox.APIDoc_originalGetText = function()
      return WowLua.indent.coloredGetText(editbox)
    end
  end
  editbox:SetScript("OnCursorChanged", function(...)
    editbox.APIDoc_oldOnCursorChanged(...)
    OnCursorChanged(...)
  end)
  editbox.APIDoc_hiddenString = editbox:CreateFontString()
end

---Disable APIDoc widget on editbox
---@param editbox EditBox
function lib:disable(editbox)
  if not config[editbox] then
    return
  end
  config[editbox] = nil
  editbox:SetScript("OnCursorChanged", editbox.APIDoc_oldOnCursorChanged)
  editbox.APIDoc_oldOnCursorChanged = nil
end

---Search a word in documentation, set results in lib.data
---@param word string
function lib:Search(word)
  self.data:Flush()
  if word and #word > 3 then
    local results = {}

    -- if search field is set to the name of namespace, show all functions
    local foundSystem = false
    local lowerWord = word:lower();
    for _, systemInfo in ipairs(APIDocumentation.systems) do
      -- search for namespaceName or namespaceName.functionName
      local nsName, rest = lowerWord:match("^([%w%_]+)(.*)")
      if nsName and systemInfo.Namespace and systemInfo.Namespace:lower():match(nsName) then
        foundSystem = true
        local funcName = rest and rest:match("^%.([%w%_]+)")
        for _, apiInfo in ipairs(systemInfo.Functions) do
          if funcName then
            if apiInfo:MatchesSearchString(funcName) then
              tinsert(results, apiInfo)
            end
          else
            tinsert(results, apiInfo)
          end
        end
        if rest == "" then
          for _, apiInfo in ipairs(systemInfo.Events) do
            tinsert(results, apiInfo)
          end
        end
      end
    end

    -- otherwise show a list of functions matching search field
    if not foundSystem then
      APIDocumentation:AddAllMatches(APIDocumentation.functions, results, lowerWord)
      APIDocumentation:AddAllMatches(APIDocumentation.events, results, lowerWord)
    end

    for i, apiInfo in ipairs(results) do
      local name
      if apiInfo.Type == "Function" then
        name = apiInfo:GetFullName()
      elseif apiInfo.Type == "Event" then
        name = apiInfo.LiteralName
      end
      self.data:Insert({ name = name, apiInfo = apiInfo })
    end
  end
end

---set in lib.data the list of systems
function lib:ListSystems()
  self.data:Flush()
  for i, systemInfo in ipairs(APIDocumentation.systems) do
    if systemInfo.Namespace and #systemInfo.Functions > 0 then
      self.data:Insert({ name = name, apiInfo = systemInfo })
    end
  end
end

---Hide, or Show and fill APIDoc widget, using lib.data data
---@param editbox EditBox
function lib:UpdateWidget(editbox)
  if self.data:IsEmpty() then
    self.scrollBox:Hide()
    self.scrollBar:Hide()
  else
    -- fix size
    local maxLinesShown = config[editbox].maxLinesShown
    local lines = self.data:GetSize()
    local height = math.min(lines, maxLinesShown) * 20
    local width = 0
    local hiddenString = editbox.APIDoc_hiddenString
    hiddenString:SetFontObject(editbox:GetFontObject())
    for _, elementData in self.data:Enumerate() do
      hiddenString:SetText(elementData.name)
      width = math.max(width, hiddenString:GetStringWidth())
    end
    self.scrollBox:SetSize(width, height)

    -- fix look
    local backgroundColor = config[editbox].backgroundColor
    self.scrollBox.background:SetColorTexture(unpack(backgroundColor))

    -- show
    self.scrollBox:SetParent(editbox)
    self.scrollBar:SetParent(editbox)
    self.scrollBox:Show()
    self.scrollBar:SetShown(lines > maxLinesShown)
  end
end

local function OnClickCallback(self)
  local editbox = self:GetParent():GetParent():GetParent():GetParent()
  local name = IndentationLib.stripWowColors(self:GetParent().name)
  lib:SetWord(editbox, name)
end

---@param editbox EditBox
---@return currentWord string
---@return startPosition integer
---@return endPosition integer
function lib:GetWord(editbox)
  -- get cursor position
  local cursorPosition = editbox:GetCursorPosition()
  local text = editbox:APIDoc_originalGetText()
  if IndentationLib then
    text, cursorPosition = IndentationLib.stripWowColorsWithPos(text, cursorPosition)
  end

  -- get start position of current word
  local startPosition = cursorPosition
  while startPosition - 1 > 0 and text:sub(startPosition - 1, startPosition - 1):find("[%w%.%_]") do
    startPosition = startPosition - 1
  end

  -- get end position of current word
  local endPosition = cursorPosition
  while endPosition + 1 < #text and text:sub(endPosition + 1, endPosition + 1):find("[%w%.%_]") do
    endPosition = endPosition + 1
  end

  local currentWord = text:sub(startPosition, endPosition)
  return currentWord, startPosition, endPosition
end

---@param editbox EditBox
---@param word string
function lib:SetWord(editbox, word)
  -- get cursor position
  local cursorPosition = editbox:GetCursorPosition()
  local text = editbox:APIDoc_originalGetText()
  if IndentationLib then
    text, cursorPosition = IndentationLib.stripWowColorsWithPos(text, cursorPosition)
  end

  -- get start position of current word
  local startPosition = cursorPosition
  while startPosition > 0 and text:sub(startPosition - 1, startPosition - 1):find("[%w%.%_]") do
    startPosition = startPosition - 1
  end

  -- get end position of current word
  local endPosition = cursorPosition
  while endPosition < #text and text:sub(endPosition + 1, endPosition + 1):find("[%w%.%_]") do
    endPosition = endPosition + 1
  end

  -- check if replacement word looks like a function and has args
  local funcName, argsString = word:match("([%w%.%_]+)%(([%w%.%_,\"%s]*)%)")
  local funcArgs = {}
  if funcName and argsString then
    for arg in argsString:gmatch("([%w%.%_\"]+),?") do
      table.insert(funcArgs, arg)
    end
  end

  -- check if current word has parentheses and args
  local oldFuncArgs = {}
  if funcName then
    local currentWordArgs = text:sub(endPosition + 1, #text):match("^%(([%w%.%_,\"%s]*)%)")
    if currentWordArgs then
      for arg in currentWordArgs:gmatch("([%w%.%_\"]+),?") do
        table.insert(oldFuncArgs, arg)
      end
      -- move endPosition
      endPosition = endPosition + #currentWordArgs + 3
    end
  end

  -- replace replacement word's args with args from current word
  if funcName then
    local newWord = funcName .. "("
    local concatArgs = {}
    for i = 1, math.max(#funcArgs, #oldFuncArgs) do
      concatArgs[i] = oldFuncArgs[i] or funcArgs[i]
    end
    word = funcName .. "(" .. table.concat(concatArgs, ", ") .. ")"
  end

  -- replace word
  text = text:sub(1, startPosition - 1) .. word .. text:sub(endPosition, #text)
  editbox:SetText(text)

  -- move cursor at end of word or start of parenthese
  local parenthesePosition = word:find("%(")
  editbox:SetCursorPosition(startPosition - 1 + (parenthesePosition or #word))
end

local function showTooltip(self)
  local apiInfo = self:GetParent().apiInfo
  if apiInfo then
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 20, 20)
    GameTooltip:ClearLines()
    for _, line in ipairs(apiInfo:GetDetailedOutputLines()) do
      GameTooltip:AddLine(line)
    end
    GameTooltip:Show()
  end
end

local function hideTooltip(self)
  GameTooltip:Hide()
  GameTooltip:ClearLines()
end

APILineMixin = {}
function APILineMixin:Init(elementData)
  self.name = elementData.name
  self.editor = elementData.editor
  self.apiInfo = elementData.apiInfo
  self.button:SetText(elementData.name)
  self.button:SetScript("OnClick", OnClickCallback)
  self.button:SetScript("OnEnter", showTooltip)
  self.button:SetScript("OnLeave", hideTooltip)
end
