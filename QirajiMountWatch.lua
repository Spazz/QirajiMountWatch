-- Qiraji Mount Watch (Classic Era) - v2.0.3
-- Fix: Classic-safe export/import window (no InputBoxMultiLine). Still taint-safe (no StaticPopupDialogs).

local ADDON_NAME = ...
local QMW = { _VERSION = "2.0.3" }

------------------------------------------------------------
-- Config / constants
------------------------------------------------------------
local Config = {
  ScanIntervalSec = 5,
  NameToItem = {
    ["Summon Blue Qiraji Battle Tank"]   = { id = 21218, color = "Blue"   },
    ["Summon Red Qiraji Battle Tank"]    = { id = 21321, color = "Red"    },
    ["Summon Green Qiraji Battle Tank"]  = { id = 21323, color = "Green"  },
    ["Summon Yellow Qiraji Battle Tank"] = { id = 21324, color = "Yellow" },
    ["Summon Black Qiraji Battle Tank"]  = { id = 21176, color = "Black"  },
  },
  ItemToColor = { [21218]="Blue",[21321]="Red",[21323]="Green",[21324]="Yellow",[21176]="Black" },
  MountItemIDs = { [21218]=true,[21321]=true,[21323]=true,[21324]=true,[21176]=true },
  ColorOrder = { "Black","Blue","Green","Red","Yellow" },
}

------------------------------------------------------------
-- SavedVariables
------------------------------------------------------------
QMW_Saved   = QMW_Saved   or {}
QMW_Backup  = QMW_Backup  or {}
QMW_Saved.owners     = QMW_Saved.owners     or {}   -- ["Name-Realm"] = { [itemId] = true } or true(legacy)
QMW_Saved.firstSeen  = QMW_Saved.firstSeen  or {}
QMW_Backup.snapshots = QMW_Backup.snapshots or {}
QMW_Backup.maxKeep   = QMW_Backup.maxKeep   or 10

------------------------------------------------------------
-- Utils
------------------------------------------------------------
local function Print(msg)
  (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage or print)(DEFAULT_CHAT_FRAME or {}, msg)
end
local function InAQ40() local n=GetInstanceInfo(); return n and n:find("Ahn'Qiraj") end
local function NormName(unitOrRaw)
  if unitOrRaw and UnitExists and UnitExists(unitOrRaw) then
    local n,r=UnitName(unitOrRaw); r=r or GetRealmName(); if n and r then return n.."-"..r end
  elseif type(unitOrRaw)=="string" and unitOrRaw~="" then
    if not unitOrRaw:find("-") then unitOrRaw=unitOrRaw.."-"..GetRealmName() end
    return unitOrRaw
  end
end
local function ShortName(nameRealm) return (nameRealm and nameRealm:gsub("%-"..GetRealmName().."$","")) or nameRealm end
local function ItemIDFromLink(link) local id=link and link:match("item:(%d+)"); return id and tonumber(id) or nil end
local function Snapshot()
  local ser
  do
    local parts={}
    for who,t in pairs(QMW_Saved.owners) do
      if t==true then table.insert(parts, who.."=unknown")
      elseif type(t)=="table" then
        local ids={}; for id in pairs(t) do table.insert(ids,tostring(id)) end
        table.sort(ids,function(a,b) return tonumber(a)<tonumber(b) end)
        table.insert(parts, who.."="..table.concat(ids,","))
      end
    end
    table.sort(parts); ser = table.concat(parts,"|")
  end
  table.insert(QMW_Backup.snapshots, { ts=time(), data=ser })
  local keep = QMW_Backup.maxKeep or 10
  while #QMW_Backup.snapshots > keep do table.remove(QMW_Backup.snapshots,1) end
end
local function OwnerColorList(who)
  local t = QMW_Saved.owners[who]
  if t==true then return "(color unknown yet)" end
  if type(t)~="table" then return nil end
  local out={}
  for id in pairs(t) do table.insert(out, Config.ItemToColor[id] or tostring(id)) end
  table.sort(out); if #out==0 then return "(color unknown yet)" end
  return table.concat(out,", ")
end
local function EnsureOwnerTable(who)
  local cur=QMW_Saved.owners[who]
  if cur==true or type(cur)~="table" then QMW_Saved.owners[who]={} end
  return QMW_Saved.owners[who]
end
local function RecordColor(who, itemId, color)
  if not who or not itemId then return false end
  local t = EnsureOwnerTable(who)
  if not t[itemId] then
    t[itemId]=true
    if not QMW_Saved.firstSeen[who] then QMW_Saved.firstSeen[who]=time() end
    Print(("|cff00ff00[QirajiWatch]|r recorded: %s mounted (%s)."):format(who, color or tostring(itemId)))
    Snapshot()
    return true
  end
  return false
end

------------------------------------------------------------
-- Export / Import window (Classic-safe)
------------------------------------------------------------
local QMWFrame, QMWScroll, QMWEdit

local function EnsureFrame()
  if QMWFrame then return end
  local f = CreateFrame("Frame", "QMWExportImportFrame", UIParent, "BackdropTemplate")
  f:SetSize(520, 260)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({
    bgFile="Interface/Tooltips/UI-Tooltip-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=16,
    insets={ left=4, right=4, top=4, bottom=4 }
  })
  f:SetBackdropColor(0,0,0,0.9)
  f:Hide()

  f.title = f:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT",12,-12)
  f.title:SetText("QirajiMountWatch Export / Import")

  -- ScrollFrame + bare EditBox (no templates)
  local s = CreateFrame("ScrollFrame", "QMWExportScroll", f, "UIPanelScrollFrameTemplate")
  s:SetPoint("TOPLEFT", 12, -40)
  s:SetPoint("BOTTOMRIGHT", -12, 40)

  local e = CreateFrame("EditBox", "QMWExportEditBox", s)
  e:SetMultiLine(true)
  e:SetFontObject(ChatFontNormal)
  e:SetAutoFocus(true)
  e:SetWidth(480) -- will be updated on size change
  e:SetMaxLetters(999999)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnTabPressed", function(self) self:Insert("  ") end)

  s:SetScrollChild(e)

  -- Keep editbox width in sync so text wraps properly
  s:SetScript("OnSizeChanged", function(self, w, h)
    e:SetWidth((w or 480) - 20)
  end)

  local copy = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  copy:SetSize(100, 22); copy:SetPoint("BOTTOMLEFT", 12, 10); copy:SetText("Copy All")
  copy:SetScript("OnClick", function()
    e:HighlightText()
    e:SetFocus()
  end)

  local paste = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  paste:SetSize(100, 22); paste:SetPoint("LEFT", copy, "RIGHT", 6, 0); paste:SetText("Import")
  paste:SetScript("OnClick", function()
    local stext = e:GetText() or ""
    local restored = {}
    for entry in string.gmatch(stext, "([^|]+)") do
      local who, list = entry:match("^([^=]+)=(.+)$")
      if who and list then
        if list == "unknown" then
          restored[who] = {}
        else
          local set = {}
          for idStr in string.gmatch(list, "([^,]+)") do
            local id = tonumber(idStr); if id then set[id]=true end
          end
          restored[who] = set
        end
      end
    end
    local n=0; for who,set in pairs(restored) do QMW_Saved.owners[who]=set; n=n+1 end
    Snapshot()
    Print("|cff00ff00[QirajiWatch]|r Import complete ("..n.." players).")
  end)

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetSize(100, 22); close:SetPoint("RIGHT", -12, 10); close:SetText("Close")
  close:SetScript("OnClick", function() f:Hide() end)

  QMWFrame, QMWScroll, QMWEdit = f, s, e
end

local function BuildExportString()
  local parts={}
  for who,t in pairs(QMW_Saved.owners) do
    if t==true then table.insert(parts, who.."=unknown")
    elseif type(t)=="table" then
      local ids={}; for id in pairs(t) do table.insert(ids, tostring(id)) end
      table.sort(ids,function(a,b) return tonumber(a)<tonumber(b) end)
      table.insert(parts, who.."="..table.concat(ids,","))
    end
  end
  table.sort(parts)
  return table.concat(parts,"|")
end

local function ShowExport()
  EnsureFrame()
  QMWEdit:SetText(BuildExportString())
  QMWFrame:Show()
  QMWEdit:HighlightText()
  QMWEdit:SetFocus()
end

local function ShowImport()
  EnsureFrame()
  QMWEdit:SetText("")
  QMWFrame:Show()
  QMWEdit:SetFocus()
end

------------------------------------------------------------
-- Scanner
------------------------------------------------------------
local scanTicker
local function ScanRaidOnce()
  if not InAQ40() then return end
  local n = GetNumGroupMembers() or 0
  for i=1,n do
    local u="raid"..i
    if UnitExists(u) then
      for b=1,40 do
        local name = UnitBuff(u,b)
        if not name then break end
        local m = Config.NameToItem[name]
        if m then
          local who = NormName(u)
          if who then RecordColor(who, m.id, m.color) end
          break
        end
      end
    end
  end
end
local function StartScan()
  if scanTicker then scanTicker:Cancel() end
  scanTicker = C_Timer.NewTicker(Config.ScanIntervalSec, ScanRaidOnce)
end

------------------------------------------------------------
-- Rolls / announce
------------------------------------------------------------
local activeRolls, announced = {}, {}

local function Purge(now)
  for id,exp in pairs(activeRolls) do
    if exp <= now then activeRolls[id]=nil; announced[id]=nil end
  end
end

local function AnnounceIfNeeded(rollID, who, itemLink)
  if not IsInRaid() then return end
  announced[rollID] = announced[rollID] or {}
  if announced[rollID][who] then return end
  local colors = OwnerColorList(who)
  local msg = colors and
    string.format("[QirajiWatch] %s already has a Qiraji mount (%s) — rolling on %s.", ShortName(who), colors, itemLink or "this") or
    string.format("[QirajiWatch] %s already has a Qiraji mount — rolling on %s.",       ShortName(who), itemLink or "this")
  SendChatMessage(msg, "RAID")
  announced[rollID][who] = true
end

local function GetActiveMountRoll()
  local now = GetTime()
  for rollID, exp in pairs(activeRolls) do
    if exp > now then
      local _,_,_,_,_,_,_,_,_,_,_,_,_,_, link = GetLootRollItemInfo(rollID)
      if Config.MountItemIDs[ItemIDFromLink(link)] then
        return rollID, link
      end
    end
  end
end

------------------------------------------------------------
-- Slash
------------------------------------------------------------
SLASH_QIRAJIOWNERS1 = "/qbo"
SlashCmdList.QIRAJIOWNERS = function(msg)
  msg = (msg or ""):gsub("^%s+",""):gsub("%s+$","")
  local lower = msg:lower()
  if lower == "" then
    Print("|cff00ff00[QirajiWatch]|r Known owners:")
    local count=0
    for who in pairs(QMW_Saved.owners) do
      Print(" - "..who.." => "..(OwnerColorList(who) or "(none)"))
      count=count+1
    end
    if count==0 then Print(" (none recorded yet)") end
    return
  elseif lower == "export" then
    ShowExport(); return
  elseif lower == "import" then
    ShowImport(); return
  elseif lower == "clear" then
    QMW_Saved.owners = {}
    Print("|cff00ff00[QirajiWatch]|r Cleared all recorded owners.")
    Snapshot()
    return
  elseif lower == "colors" then
    local counts = { Black=0, Blue=0, Green=0, Red=0, Yellow=0, Unknown=0 }
    for _,t in pairs(QMW_Saved.owners) do
      if t==true or (type(t)=="table" and not next(t)) then counts.Unknown=counts.Unknown+1
      else for id in pairs(t) do local c=Config.ItemToColor[id]; if c then counts[c]=counts[c]+1 end end
      end
    end
    Print("|cff00ff00[QirajiWatch]|r Color counts:")
    for _,c in ipairs(Config.ColorOrder) do Print(("  %s: %d"):format(c, counts[c])) end
    Print(("  Unknown: %d"):format(counts.Unknown))
    return
  else
    Print("|cff00ff00[QirajiWatch]|r Commands: /qbo (list) | export | import | colors | clear")
  end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("START_LOOT_ROLL")
f:RegisterEvent("CHAT_MSG_SYSTEM")

f:SetScript("OnEvent", function(self, event, ...)
  local now = GetTime()

  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON_NAME then
      Print("|cff00ff00[QirajiMountWatch]|r loaded v"..QMW._VERSION.." (Classic-safe UI).")
    end

  elseif event == "PLAYER_ENTERING_WORLD" then
    StartScan()

  elseif event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
    Purge(now)

  elseif event == "START_LOOT_ROLL" then
    local rollID, rollTime = ...
    local _,_,_,_,_,_,_,_,_,_,_,_,_,_, link = GetLootRollItemInfo(rollID)
    local iid = ItemIDFromLink(link)
    if iid and Config.MountItemIDs[iid] then
      local window = math.max(60,(rollTime or 60000)/1000)
      activeRolls[rollID] = now + window
      announced[rollID] = {}
    end
    Purge(now)

  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = ...
    local roller = msg:match("^([^%s]+) rolls %d+ %(%d+%-%d+%)$")
    if not roller then return end
    local activeID, link = GetActiveMountRoll(); if not activeID then return end
    local who = NormName(roller); if not who then return end
    if QMW_Saved.owners[who] then
      AnnounceIfNeeded(activeID, who, link)
    end
    Purge(now)
  end
end)