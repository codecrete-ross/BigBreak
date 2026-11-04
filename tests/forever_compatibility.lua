-- Run from the repository root with Lua 5.1: lua tests/forever_compatibility.lua
local secret = {}
local function equal(actual, expected)
    assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function noop() end

local function widget()
    local w = { scripts = {}, events = {} }
    function w:RegisterEvent(event) self.events[event] = true end
    function w:UnregisterEvent(event) self.events[event] = nil end
    function w:SetScript(script, callback) self.scripts[script] = callback end
    function w:SetSize(width) self.width = width end
    function w:GetWidth() return self.width end
    function w:GetID() return 1 end
    function w:CreateTexture() return widget() end
    function w:CreateFontString() return widget() end
    return setmetatable(w, { __index = function() return noop end })
end

local function split(separator, input, limit)
    assert(input ~= secret, "attempted to parse a secret payload")
    local fields, start = {}, 1
    while not limit or #fields < limit - 1 do
        local first, last = input:find(separator, start, true)
        if not first then break end
        fields[#fields + 1] = input:sub(start, first - 1)
        start = last + 1
    end
    fields[#fields + 1] = input:sub(start)
    return unpack(fields)
end

local function loadAddon(saved)
    local h = { now = 0, messages = {}, sounds = {}, flashes = 0, parsed = 0, checkedSecret = 0,
        playerName = "Tester", realm = "Realm", partyName = "Leader", raidName = "Leader-Realm",
        playerLead = true, playerAssist = false, peerLead = true, peerAssist = false, raidRank = 2 }
    local env = setmetatable({ BigBreakDB = saved or {}, BigBreakCharDB = {} }, { __index = _G })
    h.db = env.BigBreakDB
    env.CreateFrame = function(kind, name)
        local frame = widget()
        if not h.eventFrame then h.eventFrame = frame end
        if kind == "CheckButton" then frame.text = widget() end
        if name == "BigBreakTimerBar" then h.bar = frame end
        return frame
    end
    env.C_InstanceEncounter = { IsEncounterInProgress = function() return h.encounter or false end }
    env.issecretvalue = function(value)
        if value ~= secret then return false end
        h.checkedSecret = h.checkedSecret + 1
        return true
    end
    env.Enum = { AddOnRestrictionType = { Chat = 5 }, AddOnRestrictionState = { Inactive = 0 } }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = noop,
        InChatMessagingLockdown = function() return h.lockdown or false end,
        SendAddonMessage = function(prefix, payload, channel)
            h.messages[#h.messages + 1] = table.concat({ prefix, payload, channel }, "|")
            return 0
        end,
    }
    env.GetTime = function() return h.now end
    env.GetServerTime = function() return 1000 + h.now end
    env.IsInGroup = function() return h.group or false end
    env.IsInRaid = function() return h.raid or false end
    env.IsInInstance = function() return h.instance or false end
    env.GetInstanceInfo = function() return nil, nil, 1 end
    env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE, env.MAX_RAID_MEMBERS = 1, 2, 40
    env.UnitFullName = function() return h.playerName, h.realm end
    env.UnitName = function(unit) if unit == "party1" then return h.partyName end end
    env.UnitIsGroupLeader = function(unit)
        if unit == "player" then return h.playerLead end
        return h.peerLead
    end
    env.UnitIsGroupAssistant = function(unit)
        if unit == "player" then return h.playerAssist end
        return h.peerAssist
    end
    env.GetRaidRosterInfo = function(index)
        if index == 1 then return h.raidName, h.raidRank end
    end
    env.PlaySound = function(id) h.sounds[#h.sounds + 1] = id end
    env.FlashClientIcon = function() h.flashes = h.flashes + 1 end
    env.RaidWarningUtil = { AddMessage = function(message) h.warning = message end }
    env.ChatTypeInfo = { RAID_WARNING = {} }
    env.SOUNDKIT = { ALARM_CLOCK_WARNING_2 = 2, ALARM_CLOCK_WARNING_3 = 3, UI_BATTLEGROUND_COUNTDOWN_FINISHED = 4 }
    env.DEFAULT_CHAT_FRAME = { AddMessage = noop }
    env.SlashCmdList = {}
    env.Settings = { RegisterCanvasLayoutCategory = function(frame) return frame end,
        RegisterAddOnCategory = noop, OpenToCategory = function(id) h.category = id end }
    env.MenuUtil = { CreateRadioMenu = noop }
    env.format, env.strlower = string.format, string.lower
    env.strtrim = function(input) return input:match("^%s*(.-)%s*$") end
    env.strsplit = function(separator, ...)
        if separator == "\t" then h.parsed = h.parsed + 1 end
        return split(separator, ...)
    end
    local chunk = assert(loadfile("BigBreak.lua"))
    setfenv(chunk, env)
    chunk()

    function h:event(event, ...)
        assert(self.eventFrame.events[event], "unregistered event " .. event)
        self.eventFrame.scripts.OnEvent(self.eventFrame, event, ...)
    end
    function h:message(prefix, payload, channel, sender)
        self:event("CHAT_MSG_ADDON", prefix, payload, channel or "PARTY", sender or "Leader-Realm")
    end
    h.breakCommand, h.bigBreakCommand = function(args) env.SlashCmdList.BIGBREAKBREAK(args) end,
        function(args) env.SlashCmdList.BIGBREAK(args) end
    h:event("ADDON_LOADED", "BigBreak")
    return h
end

local count = 0
local function test(name, run)
    local ok, failure = pcall(run)
    assert(ok, name .. ": " .. tostring(failure))
    count = count + 1
    print("ok " .. count .. " - " .. name)
end

test("local settings, hidden player name, and completion alerts", function()
    local h = loadAddon()
    h.bigBreakCommand("")
    equal(h.category, 1)
    h.playerName = secret
    h.bigBreakCommand("test")
    equal(h.db.activeTimer.sender, "You")
    equal(h.db.activeTimer.localOnly, true)
    h.now = 15
    h.bar.scripts.OnUpdate(h.bar, 1)
    equal(h.db.activeTimer, nil)
    equal(h.warning, "BREAK IS OVER!")
    equal(table.concat(h.sounds, ","), "3,4")
    equal(h.flashes, 2)
    equal(#h.messages, 0)
    h.breakCommand("2")
    equal(h.db.activeTimer.sender, "You")
    h.breakCommand("0")
    equal(h.db.activeTimer, nil)
end)

test("restores an active timer silently from saved variables", function()
    local h = loadAddon({ activeTimer = { duration = 180, endServerTime = 1060, sender = "Leader" } })
    equal(h.db.activeTimer.duration, 180)
    equal(h.db.activeTimer.endServerTime, 1060)
    equal(h.db.activeTimer.sender, "Leader")
    equal(#h.sounds, 0)
end)

test("party and raid starts and cancels preserve both message formats", function()
    for _, channel in ipairs({ "PARTY", "RAID", "INSTANCE_CHAT" }) do
        local h = loadAddon()
        h.group, h.raid, h.instance = true, channel == "RAID", channel == "INSTANCE_CHAT"
        h.breakCommand("2")
        equal(h.db.activeTimer.localOnly, false)
        equal(h.messages[1], "BigBreak|BREAK\t120\tTester|" .. channel)
        equal(h.messages[2], "D5|Tester-Realm\t1\tBT\t120|" .. channel)
        h.breakCommand("0")
        equal(h.db.activeTimer, nil)
        equal(h.messages[3], "BigBreak|CANCEL\tBREAK\tTester|" .. channel)
        equal(h.messages[4], "D5|Tester-Realm\t1\tBT\t0|" .. channel)
        h:message("D5", "Leader-Realm\t1\tBT\t120", channel)
        equal(h.db.activeTimer.sender, "Leader-Realm")
        h:message("BigBreak", "BREAK\t120\tLeader", channel)
        equal(h.db.activeTimer.sender, "Leader-Realm")
        h:message("D5", "Leader-Realm\t1\tBT\t0", channel)
        equal(h.db.activeTimer, nil)
    end
end)

test("group sync retries when chat lockdown clears", function()
    local h = loadAddon()
    h.group, h.lockdown = true, true
    h:event("GROUP_ROSTER_UPDATE")
    equal(#h.messages, 0)
    h.lockdown = false
    h:event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    equal(h.messages[1], "BigBreak|SYNC_REQ|PARTY")
    h:message("BigBreak", "SYNC_RESP\t75.5\tLeader")
    equal(h.db.activeTimer.endServerTime, 1075.5)
    h:message("BigBreak", "SYNC_REQ")
    equal(h.messages[2], "BigBreak|SYNC_RESP\t75.5\tLeader|PARTY")
end)

test("lockdown and encounters reject incoming messages before parsing", function()
    for _, restriction in ipairs({ "lockdown", "encounter" }) do
        local h = loadAddon()
        h.group, h[restriction] = true, true
        h.breakCommand("2")
        equal(h.db.activeTimer, nil)
        equal(#h.messages, 0)
        h:message("BigBreak", "BREAK\t120\tLeader")
        equal(h.parsed, 0)
        h[restriction] = false
        h:message("BigBreak", "BREAK\t120\tLeader")
        equal(h.db.activeTimer.sender, "Leader")
        h[restriction] = true
        h:message("D5", "Leader-Realm\t1\tBT\t0")
        h:message("BigBreak", "CANCEL\tBREAK\tLeader")
        equal(h.parsed, 1)
        equal(h.db.activeTimer.sender, "Leader")
    end
end)

test("rejects all secret incoming message fields before parsing", function()
    local h = loadAddon()
    h.group = true
    local fields = { "BigBreak", "BREAK\t120\tLeader", "PARTY", "Leader-Realm" }
    for i, field in ipairs(fields) do
        fields[i] = secret
        h:message(unpack(fields))
        equal(h.checkedSecret, i)
        fields[i] = field
    end
    equal(h.parsed, 0)
    equal(h.db.activeTimer, nil)
end)

test("secret identity and rank cannot authorize shared actions", function()
    local h = loadAddon()
    h.group, h.realm = true, secret
    h.breakCommand("2")
    h.breakCommand("0")
    h:message("BigBreak", "BREAK\t120\tLeader")
    equal(h.parsed, 0)
    h.realm, h.playerName = "Realm", ""
    h.breakCommand("2")
    h.playerName = "Tester"
    h:message("BigBreak", "BREAK\t120\tTester", "PARTY", "Tester-Realm")
    equal(h.parsed, 0)
    h.realm, h.playerLead, h.playerAssist = "Realm", secret, secret
    h.breakCommand("2")
    equal(#h.messages, 0)
    equal(h.db.activeTimer, nil)

    h.partyName = secret
    h:message("BigBreak", "BREAK\t120\tLeader")
    h.partyName, h.peerLead, h.peerAssist = "Leader", secret, secret
    h:message("BigBreak", "BREAK\t120\tLeader")
    h.peerLead, h.peerAssist = false, false
    h:message("BigBreak", "BREAK\t120\tLeader")
    h.raid, h.raidRank = true, secret
    h:message("BigBreak", "BREAK\t120\tLeader", "RAID")
    h.raidName, h.raidRank = secret, 2
    h:message("BigBreak", "BREAK\t120\tLeader", "RAID")
    equal(h.db.activeTimer, nil)

    h.playerAssist = true
    h.breakCommand("2")
    equal(#h.messages, 2)
    equal(h.db.activeTimer.sender, "Tester-Realm")
    h.playerAssist = secret
    h.bar.scripts.OnMouseUp(h.bar, "RightButton")
    equal(#h.messages, 2)
    equal(h.db.activeTimer.sender, "Tester-Realm")
end)

print("Passed " .. count .. " Forever compatibility scenarios")
