local ADDON_NAME = "BigBreak"
local BB = {}
BB.activeTimer = nil
BB.timerFrame = nil
BB.locked = false
BB.lastReceived = {}
BB.settingsCategory = nil
BB.wasInGroup = false
BB.initialized = false
BB.syncPending = false

local CHAT_PREFIX = "|cff00ccff[BigBreak]|r "
local HasRestrictionStateEvent = C_ChatInfo.InChatMessagingLockdown ~= nil
local InChatMessagingLockdown = C_ChatInfo.InChatMessagingLockdown or function() return false end
local CHAT_RESTRICTION_TYPE = HasRestrictionStateEvent
    and Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat
local RESTRICTION_INACTIVE = HasRestrictionStateEvent
    and Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive
local VALID_ADDON_CHANNELS = {
    PARTY = true,
    RAID = true,
    INSTANCE_CHAT = true,
}

local BAR_SIZES = {
    [1] = { key = "Big",    width = 440, height = 44, font = "GameFontHighlightLarge" },
    [2] = { key = "Medium", width = 280, height = 28, font = "GameFontHighlight" },
    [3] = { key = "Small",  width = 180, height = 18, font = "GameFontHighlightSmall" },
}

local DEFAULT_SETTINGS = { sound = true, flash = true, locked = false, barSize = "Big", frequentUpdates = false }

-- ============================================================================
-- Utilities
-- ============================================================================

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. msg)
end

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return format("%d:%02d", m, s)
end

local function StripRealm(name)
    if not name then return name end
    local dash = name:find("-")
    if dash then return name:sub(1, dash - 1) end
    return name
end

local function GetPlayerFullName()
    local name, realm = UnitFullName("player")
    if not name then return "Unknown" end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function SenderIsMe(sender)
    return sender == GetPlayerFullName()
end

local function GetChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "PARTY"
    end
    return nil
end

local function HasPermission()
    if not IsInGroup() then return true end -- solo
    if UnitIsGroupLeader("player") then return true end
    if UnitIsGroupAssistant("player") then return true end
    return false
end

local function GetCommunicationRestriction(action)
    if IsEncounterInProgress() then
        return true, "Cannot " .. action .. " a break timer during an encounter."
    end
    if InChatMessagingLockdown() then
        return true, "Cannot " .. action .. " a break timer while addon messaging is restricted."
    end
    return false, nil
end

local function PrintCommunicationFailure(action)
    local _, reason = GetCommunicationRestriction(action)
    if reason then
        Print(reason)
    elseif action == "start" then
        Print("Unable to share the break timer with your group.")
    else
        Print("Unable to cancel the group break timer.")
    end
end

local function IsRestricted()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return true, "Cannot send timers in Mythic+."
    end
    if IsInGroup() then
        local restricted, reason = GetCommunicationRestriction("start")
        if restricted then return true, reason end
    end
    local _, _, difficultyID = GetInstanceInfo()
    if difficultyID == 17 then
        return true, "Cannot send timers in LFR."
    end
    return false, nil
end

local function SenderHasRank(sender)
    if not IsInGroup() then return true end
    local short = StripRealm(sender)
    if IsInRaid() then
        for i = 1, MAX_RAID_MEMBERS do
            local name, rank = GetRaidRosterInfo(i)
            if name and StripRealm(name) == short and rank > 0 then
                return true
            end
        end
        return false
    end
    for i = 1, 4 do
        local unit = "party" .. i
        local unitName = UnitName(unit)
        if unitName and unitName == short then
            return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
        end
    end
    return false
end

local function IsDupe(sender, seconds)
    local key = sender .. "BREAK" .. tostring(math.floor(seconds))
    local now = GetTime()
    if BB.lastReceived[key] and (now - BB.lastReceived[key]) < 2 then
        return true
    end
    -- Prune entries older than 10 seconds
    for k, t in pairs(BB.lastReceived) do
        if now - t > 10 then BB.lastReceived[k] = nil end
    end
    BB.lastReceived[key] = now
    return false
end

local function GetBarSizeInfo()
    local sizeKey = BigBreakDB and BigBreakDB.barSize or "Big"
    for _, info in ipairs(BAR_SIZES) do
        if info.key == sizeKey then return info end
    end
    return BAR_SIZES[1]
end

-- ============================================================================
-- Timer Bar UI
-- ============================================================================

function BB:ApplyBarSize()
    if not BB.timerFrame then return end
    local info = GetBarSizeInfo()
    local bar = BB.timerFrame
    bar:SetSize(info.width, info.height)
    bar.text:SetFontObject(info.font)
    bar.time:SetFontObject(info.font)
end

local function CreateTimerBar()
    local bar = CreateFrame("Frame", "BigBreakTimerBar", UIParent, "BackdropTemplate")
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    bar:SetFrameStrata("MEDIUM")

    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    bar:SetBackdropColor(0, 0, 0, 0.7)
    bar:SetBackdropBorderColor(0, 0, 0, 1)

    -- Fill texture — sized directly each frame
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.text:SetPoint("LEFT", bar, "LEFT", 6, 0)

    bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)

    -- Dragging (left-click) and cancel (right-click)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        if not BB.locked then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        BB:SavePosition()
    end)
    bar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and BB.activeTimer then
            local sharedTimer = IsInGroup() and not BB.activeTimer.localOnly
            if sharedTimer and not HasPermission() then
                Print("You need to be the group leader or an assistant to cancel a break timer.")
                return
            end
            if sharedTimer then
                local restricted, reason = GetCommunicationRestriction("cancel")
                if restricted then
                    Print(reason)
                    return
                end
                if not BB:BroadcastCancel() then
                    PrintCommunicationFailure("cancel")
                    return
                end
            end
            BB:CancelTimer()
        end
    end)

    -- OnUpdate
    local updateAccum = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        if not BB.activeTimer then
            self:Hide()
            return
        end

        local remaining = BB.activeTimer.endTime - GetTime()
        if remaining <= 0 then
            BB:TimerComplete()
            return
        end

        -- Warnings always check every frame so they fire on time
        if remaining <= 60 and not BB.activeTimer.warnedOneMin then
            BB.activeTimer.warnedOneMin = true
            if BB.activeTimer.duration > 90 then
                Print("Break ends in 1 minute!")
                if BigBreakDB.sound then PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_2) end
            end
        end

        -- Throttle visual updates to once per second unless smooth animation is on
        if not BigBreakDB.frequentUpdates then
            updateAccum = updateAccum + elapsed
            if updateAccum < 1 then return end
            updateAccum = 0
        end

        local total = BB.activeTimer.duration
        local displayRemaining = BigBreakDB.frequentUpdates and remaining or math.ceil(remaining)
        local pct = displayRemaining / total
        local fillWidth = math.max(0, pct * (self:GetWidth() - 2))
        self.fill:SetWidth(fillWidth)
        self.time:SetText(FormatTime(remaining))

        -- Color by time remaining
        if remaining <= 60 then
            self.fill:SetVertexColor(0.8, 0.2, 0.2)
        elseif remaining <= 180 then
            self.fill:SetVertexColor(0.9, 0.7, 0.0)
        else
            self.fill:SetVertexColor(0.2, 0.6, 0.2)
        end

        -- Fade long break timers: low alpha until last 10 min
        if total > 600 and remaining > 600 then
            self:SetAlpha(0.4)
        else
            self:SetAlpha(1)
        end
    end)

    bar:Hide()
    BB.timerFrame = bar
    BB:ApplyBarSize()
end

-- ============================================================================
-- Position Saving / Restoring
-- ============================================================================

function BB:SavePosition()
    if not BB.timerFrame then return end
    local point, _, relPoint, x, y = BB.timerFrame:GetPoint()
    BigBreakCharDB.position = { point = point, relPoint = relPoint, x = x, y = y }
end

function BB:RestorePosition()
    local pos = BigBreakCharDB.position
    if pos and BB.timerFrame then
        BB.timerFrame:ClearAllPoints()
        BB.timerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
end

function BB:ResetToDefaults()
    for k, v in pairs(DEFAULT_SETTINGS) do
        BigBreakDB[k] = v
    end
    BB.locked = false

    wipe(BigBreakCharDB)
    if BB.timerFrame then
        BB.timerFrame:ClearAllPoints()
        BB.timerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        BB:ApplyBarSize()
    end

    Print("All settings reset to defaults.")
end

-- ============================================================================
-- Settings Panel
-- ============================================================================

local function MakeCheckbox(parent, x, y, label, dbKey)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb.text:SetText(label)
    cb.text:SetFontObject("GameFontHighlight")
    cb:SetScript("OnClick", function(self)
        BigBreakDB[dbKey] = self:GetChecked()
        if dbKey == "locked" then BB.locked = BigBreakDB.locked end
    end)
    cb.dbKey = dbKey
    return cb
end

local function CreateSettingsPanel()
    local frame = CreateFrame("Frame")
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("BigBreak")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetText("A simple break timer with no external dependencies.")

    local checkboxes = {}
    checkboxes[#checkboxes + 1] = MakeCheckbox(frame, 14, -60, "Sound Alerts", "sound")
    checkboxes[#checkboxes + 1] = MakeCheckbox(frame, 14, -85, "Taskbar Flash", "flash")
    checkboxes[#checkboxes + 1] = MakeCheckbox(frame, 14, -110, "Lock Bar Position", "locked")
    checkboxes[#checkboxes + 1] = MakeCheckbox(frame, 14, -135, "Smoother Animation", "frequentUpdates")

    -- Bar size dropdown
    local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -175)
    sizeLabel:SetText("Bar Size")

    local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", -2, -4)

    local function IsSelected(value) return value == BigBreakDB.barSize end
    local function SetSelected(value)
        BigBreakDB.barSize = value
        BB:ApplyBarSize()
    end
    MenuUtil.CreateRadioMenu(dropdown, IsSelected, SetSelected,
        unpack({{"Small", "Small"}, {"Medium", "Medium"}, {"Big", "Big"}}))

    -- Reset to defaults
    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 26)
    resetBtn:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 2, -20)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        BB:ResetToDefaults()
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(BigBreakDB[cb.dbKey])
        end
    end)

    frame:SetScript("OnShow", function()
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(BigBreakDB[cb.dbKey])
        end
    end)

    local category = Settings.RegisterCanvasLayoutCategory(frame, "BigBreak")
    Settings.RegisterAddOnCategory(category)
    BB.settingsCategory = category
end

-- ============================================================================
-- Timer Logic
-- ============================================================================

function BB:StartTimer(duration, senderName, silent, originalDuration, localOnly)
    if not BB.timerFrame then CreateTimerBar() end

    if BB.activeTimer then
        BB.activeTimer = nil
    end

    local total = originalDuration or duration

    BB.activeTimer = {
        duration = total,       -- original full duration (for bar fill ratio)
        endTime = GetTime() + duration, -- actual countdown
        sender = senderName,
        warnedOneMin = false,
        localOnly = localOnly or false,
    }
    BB.syncPending = false

    -- Pre-set warning flag for short remaining timers
    if duration <= 90 then BB.activeTimer.warnedOneMin = true end

    -- Persist for /reload recovery
    BigBreakDB.activeTimer = {
        duration = total,
        endServerTime = GetServerTime() + duration,
        sender = senderName,
        localOnly = localOnly or false,
    }

    local bar = BB.timerFrame
    bar.fill:SetVertexColor(0.2, 0.6, 0.2)
    bar.fill:SetWidth(bar:GetWidth() - 2)
    bar.text:SetText("Break (" .. (senderName or "") .. ")")
    bar.time:SetText(FormatTime(duration))
    bar:SetAlpha(1)
    bar:Show()

    if not silent then
        local chatName = StripRealm(senderName) or senderName or "Unknown"
        Print(format("Break for %s! (from %s)", FormatTime(duration), chatName))
        if BigBreakDB.sound then PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3) end
        if BigBreakDB.flash then FlashClientIcon() end
    end
end

function BB:CancelTimer(silent)
    if BB.activeTimer then
        if not silent then Print("Break cancelled.") end
        BB.activeTimer = nil
        BigBreakDB.activeTimer = nil
        if BB.timerFrame then BB.timerFrame:Hide() end
    end
end

function BB:TimerComplete()
    if not BB.activeTimer then return end
    BB.activeTimer = nil
    BigBreakDB.activeTimer = nil
    if BB.timerFrame then BB.timerFrame:Hide() end

    RaidNotice_AddMessage(RaidWarningFrame, "BREAK IS OVER!", ChatTypeInfo["RAID_WARNING"])
    Print("|cff00ff00Break is over!|r")
    if BigBreakDB.sound then PlaySound(SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_FINISHED) end
    if BigBreakDB.flash then FlashClientIcon() end
end

-- ============================================================================
-- Communication: Send
-- ============================================================================

local function AddonMessageWasAccepted(result)
    return result == nil or result == true or result == 0
end

function BB:RequestSync()
    if BB.activeTimer or not IsInGroup() then
        BB.syncPending = false
        return false
    end
    if IsEncounterInProgress() or InChatMessagingLockdown() then
        BB.syncPending = true
        return false
    end

    local channel = GetChannel()
    if not channel then
        BB.syncPending = false
        return false
    end

    local result = C_ChatInfo.SendAddonMessage("BigBreak", "SYNC_REQ", channel)
    if AddonMessageWasAccepted(result) then
        BB.syncPending = false
        return true
    end

    BB.syncPending = true
    return false
end

function BB:Broadcast(seconds)
    if IsEncounterInProgress() or InChatMessagingLockdown() then return false end

    local channel = GetChannel()
    if not channel then return false end

    local playerName = UnitName("player")
    local fullName = GetPlayerFullName()

    local bigBreakResult = C_ChatInfo.SendAddonMessage(
        "BigBreak", "BREAK\t" .. seconds .. "\t" .. playerName, channel)
    local dbmResult = C_ChatInfo.SendAddonMessage(
        "D5", fullName .. "\t1\tBT\t" .. seconds, channel)
    return AddonMessageWasAccepted(bigBreakResult) or AddonMessageWasAccepted(dbmResult)
end

function BB:BroadcastCancel()
    if IsEncounterInProgress() or InChatMessagingLockdown() then return false end

    local channel = GetChannel()
    if not channel then return false end

    local playerName = UnitName("player")
    local fullName = GetPlayerFullName()
    local bigBreakResult = C_ChatInfo.SendAddonMessage(
        "BigBreak", "CANCEL\tBREAK\t" .. playerName, channel)
    local dbmResult = C_ChatInfo.SendAddonMessage(
        "D5", fullName .. "\t1\tBT\t0", channel)
    return AddonMessageWasAccepted(bigBreakResult) or AddonMessageWasAccepted(dbmResult)
end

-- ============================================================================
-- Communication: Receive
-- ============================================================================

function BB:OnAddonMessage(prefix, message, channel, sender)
    if not VALID_ADDON_CHANNELS[channel] then return end
    if SenderIsMe(sender) then return end

    if prefix == "BigBreak" then
        BB:ParseBigBreakMessage(message, sender)
    elseif prefix == "D5" then
        BB:ParseDBMMessage(message, sender)
    end
end

function BB:ParseBigBreakMessage(message, sender)
    local cmd, val, name, extra = strsplit("\t", message)
    if not cmd then return end

    if cmd == "BREAK" then
        local seconds = tonumber(val)
        if not seconds or seconds <= 0 or seconds > 3600 then return end
        if IsEncounterInProgress() or InChatMessagingLockdown() then return end
        if not SenderHasRank(sender) then return end
        if IsDupe(sender, seconds) then return end
        BB:StartTimer(seconds, name or sender)
    elseif cmd == "CANCEL" then
        if not SenderHasRank(sender) then return end
        BB:CancelTimer()
    elseif cmd == "SYNC_REQ" then
        if BB.activeTimer and not BB.activeTimer.localOnly
            and not IsEncounterInProgress() and not InChatMessagingLockdown() then
            local remaining = BB.activeTimer.endTime - GetTime()
            if remaining > 1 then
                local ch = GetChannel()
                if ch then
                    C_ChatInfo.SendAddonMessage("BigBreak",
                        "SYNC_RESP\t" .. format("%.1f", remaining) .. "\t"
                        .. (BB.activeTimer.sender or ""), ch)
                end
            end
        end
    elseif cmd == "SYNC_RESP" then
        if IsEncounterInProgress() or InChatMessagingLockdown() then return end
        if not BB.activeTimer then
            if not SenderHasRank(sender) then return end
            local seconds, senderName
            if val == "BREAK" then
                seconds = tonumber(name)
                senderName = extra
            else
                seconds = tonumber(val)
                senderName = name
            end
            if seconds and seconds > 1 and seconds <= 3600 then
                BB:StartTimer(seconds, (senderName and senderName ~= "") and senderName or sender, true)
            end
        end
    end
end

function BB:ParseDBMMessage(message, sender)
    local _, _, subPrefix, arg1 = strsplit("\t", message)
    if not subPrefix then return end

    if subPrefix == "BT" then
        local seconds = tonumber(arg1)
        if not seconds then return end
        if seconds == 0 then
            if SenderHasRank(sender) then BB:CancelTimer() end
            return
        end
        if seconds < 0 or seconds > 3600 then return end
        if IsEncounterInProgress() or InChatMessagingLockdown() then return end
        if not SenderHasRank(sender) then return end
        if IsDupe(sender, seconds) then return end
        BB:StartTimer(seconds, sender)
    end
end

-- ============================================================================
-- Slash Commands
-- ============================================================================

local function SlashBreak(msg)
    local minutes = tonumber(strtrim(msg))
    if not minutes then
        Print("Usage: /break <minutes> (1-60) or /break 0 to cancel")
        return
    end

    if minutes == 0 then
        local sharedTimer = IsInGroup() and (not BB.activeTimer or not BB.activeTimer.localOnly)
        if sharedTimer and not HasPermission() then
            Print("You need to be the group leader or an assistant to cancel a break timer.")
            return
        end
        if sharedTimer then
            local restricted, reason = GetCommunicationRestriction("cancel")
            if restricted then
                Print(reason)
                return
            end
            if not BB:BroadcastCancel() then
                PrintCommunicationFailure("cancel")
                return
            end
        end
        BB:CancelTimer()
        return
    end

    if minutes < 1 or minutes > 60 then
        Print("Break timer must be between 1 and 60 minutes.")
        return
    end

    if not HasPermission() then
        Print("You need to be the group leader or an assistant to send a break timer.")
        return
    end

    local restricted, reason = IsRestricted()
    if restricted then
        Print(reason)
        return
    end

    local playerName = GetPlayerFullName()
    local seconds = minutes * 60
    local inGroup = IsInGroup()
    if inGroup and not BB:Broadcast(seconds) then
        PrintCommunicationFailure("start")
        return
    end
    BB:StartTimer(seconds, playerName, false, nil, not inGroup)
end

local function SlashBigBreak(msg)
    local args = strtrim(msg)
    local cmd = strlower(args)

    local subcmd, subarg = strsplit(" ", args, 2)
    subcmd = strlower(subcmd or "")

    if subcmd == "break" then
        SlashBreak(subarg or "")
    elseif cmd == "lock" then
        BB.locked = true
        BigBreakDB.locked = true
        Print("Bar locked.")
    elseif cmd == "unlock" then
        BB.locked = false
        BigBreakDB.locked = false
        Print("Bar unlocked. Drag to reposition.")
    elseif cmd == "sound" then
        BigBreakDB.sound = not BigBreakDB.sound
        Print("Sound " .. (BigBreakDB.sound and "enabled" or "disabled") .. ".")
    elseif cmd == "flash" then
        BigBreakDB.flash = not BigBreakDB.flash
        Print("Flash " .. (BigBreakDB.flash and "enabled" or "disabled") .. ".")
    elseif cmd == "test" then
        BB:StartTimer(15, GetPlayerFullName(), false, nil, true)
    elseif cmd == "reset" then
        BB:ResetToDefaults()
    else
        if BB.settingsCategory then
            Settings.OpenToCategory(BB.settingsCategory:GetID())
        else
            Print("Commands:")
            Print("  /break <minutes> — Start a break timer (1-60)")
            Print("  /break 0 — Cancel active timer")
            Print("  /bb — Open settings panel")
            Print("  /bb test — Show a test break timer")
            Print("  /bb reset — Reset all settings to defaults")
            Print("  Right-click the bar to cancel.")
        end
    end
end

-- ============================================================================
-- Init
-- ============================================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
if CHAT_RESTRICTION_TYPE and RESTRICTION_INACTIVE ~= nil then
    frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON_NAME then return end

        if not BigBreakDB then
            BigBreakDB = {}
        end
        for k, v in pairs(DEFAULT_SETTINGS) do
            if BigBreakDB[k] == nil then BigBreakDB[k] = v end
        end
        if not BigBreakCharDB then
            BigBreakCharDB = {}
        end
        BB.locked = BigBreakDB.locked or false

        C_ChatInfo.RegisterAddonMessagePrefix("BigBreak")
        C_ChatInfo.RegisterAddonMessagePrefix("D5")

        SLASH_BIGBREAKBREAK1 = "/break"
        SlashCmdList["BIGBREAKBREAK"] = SlashBreak

        SLASH_BIGBREAK1 = "/bigbreak"
        SLASH_BIGBREAK2 = "/bb"
        SlashCmdList["BIGBREAK"] = SlashBigBreak

        -- Classic support: Settings API is retail 10.0+. On older clients, /bb shows help text instead.
        if Settings and Settings.RegisterCanvasLayoutCategory then
            CreateSettingsPanel()
        end
        CreateTimerBar()
        BB:RestorePosition()

        -- Restore timer from before /reload
        local saved = BigBreakDB.activeTimer
        if saved and saved.endServerTime then
            local remaining = saved.endServerTime - GetServerTime()
            if remaining > 1 then
                BB:StartTimer(remaining, saved.sender, true, saved.duration, saved.localOnly)
            else
                BigBreakDB.activeTimer = nil
            end
        end

        -- Request timer state when loading into a group without a local timer
        BB.wasInGroup = IsInGroup()
        if BB.wasInGroup then BB:RequestSync() end
        BB.initialized = true

        -- Addon conflict warning
        if C_AddOns then
            if C_AddOns.IsAddOnLoaded("DBM-Core") then
                Print("DBM detected. You may see duplicate break timers.")
            elseif C_AddOns.IsAddOnLoaded("BigWigs") then
                Print("BigWigs detected. You may see duplicate break timers.")
            end
        end

        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        BB:OnAddonMessage(prefix, message, channel, sender)

    elseif event == "GROUP_ROSTER_UPDATE" then
        if not BB.initialized then return end

        local inGroup = IsInGroup()
        if not inGroup then
            BB.syncPending = false
            if BB.activeTimer then BB:CancelTimer(true) end
        elseif not BB.wasInGroup then
            BB:RequestSync()
        end
        BB.wasInGroup = inGroup

    elseif event == "PLAYER_REGEN_ENABLED" then
        if BB.syncPending then BB:RequestSync() end

    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restrictionType, state = ...
        if BB.syncPending and restrictionType == CHAT_RESTRICTION_TYPE
            and state == RESTRICTION_INACTIVE then
            BB:RequestSync()
        end
    end
end)

-- ============================================================================
-- Addon Compartment (minimap dropdown button)
-- ============================================================================

-- Classic support: AddonCompartmentFunc is retail 9.1+. Safe to define globally; just won't be called on older clients.
function BigBreak_OnAddonCompartmentClick()
    if BB.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(BB.settingsCategory:GetID())
    end
end
