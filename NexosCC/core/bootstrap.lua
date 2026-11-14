local addonName, Addon = ...
_G.NexosCC = Addon
Addon.name = addonName

local interface = select(4, GetBuildInfo()) or 0
_G.NexosCC_ClientBackend = (interface == 16001) and "Forever" or "Midnight"
Addon.client = _G.NexosCC_ClientBackend

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[clone(k, seen)] = clone(v, seen) end
    return out
end

local function fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = clone(v)
        elseif type(dst[k]) == "table" and type(v) == "table" then
            fill(dst[k], v)
        end
    end
    return dst
end

local function baseStyle()
    return {
        enabled = true,
        themeText = true,
        themeCooldown = true,
        drawBling = "default",
        drawEdge = "default",
        drawSwipe = "default",
        drawText = "always",
        reverse = "default",
        font = "Friz Quadrata TT",
        fontFlags = "OUTLINE",
        fontSize = 18,
        point = "CENTER",
        offsetX = (interface == 16001) and 3 or 0,
        offsetY = 0,
        shadowColor = "FFFFFF00",
        shadowX = 0,
        shadowY = 0,
        scaleText = true,
        minScale = 0.5,
        minDuration = 2,
        tenthsThreshold = 0,
        minutesThreshold = 60,
        abbrevThreshold = 90,
        hoursThreshold = 3600,
        daysThreshold = 86400,
        weeksThreshold = 604800,
        roundingMode = "Nearest",
        showZero = false,
        textColors = {
                    { threshold = 5, color = "FF6347FF" },
                    { threshold = 60, color = "40E0D0FF" },
                    { threshold = 3600, color = "32CD32FF" },
                },
        defaultTextColor = "FFFFFFFF",
        themeSwipeColor = false,
        swipeColor = "000000CC",
    }
end

local function style(overrides)
    local s = baseStyle()
    if overrides then
        for k, v in pairs(overrides) do s[k] = clone(v) end
    end
    return s
end

local function defaultProfile()
    return {
        themes = {
            default = style(),
            nameplates = style({
                drawSwipe = "never", drawEdge = "always", drawBling = "always", reverse = "never",
                fontSize = 15, minDuration = 0, abbrevThreshold = 0, scaleText = false, minScale = 0,
                textColors = {
                    { threshold = 5, color = "FF6347FF" },
                    { threshold = 60, color = "32CD32FF" },
                    { threshold = 3600, color = "40E0D0FF" },
                },
                defaultTextColor = "FFFFFFFF",
            }),
            auras = style({
                fontSize = 10, minDuration = 0, abbrevThreshold = 0, scaleText = false, minScale = 0,
                point = "BOTTOM", offsetX = 0, offsetY = 0,
                textColors = {
                    { threshold = 5, color = "FF6347FF" },
                    { threshold = 60, color = "40E0D0FF" },
                    { threshold = 3600, color = "32CD32FF" },
                },
                defaultTextColor = "FFFFFFFF",
            }),
            nexos_autofit = style({
                displayName = "Auto-Fit",
                autoFitText = true,
                fontSize = 13,
                abbrevThreshold = (interface == 16001) and 0 or 60,
                scaleText = false,
                minScale = 0,
                textColors = {
                    { threshold = 5, color = "FF6347FF" },
                    { threshold = 60, color = "40E0D0FF" },
                    { threshold = 3600, color = "32CD32FF" },
                },
                defaultTextColor = "FFFFFFFF",
            }),
            none = style({ enabled = false, themeText = false, themeCooldown = false, drawText = "never" }),
        },
        rules = {
            ["*"] = { enabled = true, theme = "default" },
            everything = { enabled = true, theme = "default" },
            blizzard_nameplates = { enabled = true, theme = "nameplates" },
            nexos_nameplate_aura = { enabled = true, theme = "nameplates" },
            nexos_player_frame = { enabled = true, theme = "auras" },
        },
        nexosAutoFitEnabled = false,
        nexosDefaultsVersion = 1,
    }
end

_G.NexosCCDB = type(_G.NexosCCDB) == "table" and _G.NexosCCDB or {}
local root = _G.NexosCCDB
root.global = type(root.global) == "table" and root.global or {}
-- Keep a secondary profile snapshot inside the same SavedVariables database.
-- This is NOT a migration from another addon. It protects against an accidentally
-- empty profiles table when the NexosCCDB file itself is still present.
local previousProfiles = root.profiles
if type(previousProfiles) ~= "table" or next(previousProfiles) == nil then
    if type(root.profileSafetyCopy) == "table" and next(root.profileSafetyCopy) ~= nil then
        root.profiles = clone(root.profileSafetyCopy)
    else
        root.profiles = {}
    end
end
root.activeProfile = type(root.activeProfile) == "string" and root.activeProfile or "Default"
if root.profiles[root.activeProfile] == nil and type(root.profileSafetyCopy) == "table"
    and type(root.profileSafetyCopy[root.activeProfile]) == "table" then
    root.profiles[root.activeProfile] = clone(root.profileSafetyCopy[root.activeProfile])
end
root.profiles[root.activeProfile] = type(root.profiles[root.activeProfile]) == "table" and root.profiles[root.activeProfile] or defaultProfile()
fill(root.profiles[root.activeProfile], defaultProfile())
-- Snapshot only after the database has been loaded and validated. The snapshot
-- is refreshed on logout, when the client normally writes SavedVariables.
local saveSafety = CreateFrame("Frame")
saveSafety:RegisterEvent("PLAYER_LOGOUT")
saveSafety:SetScript("OnEvent", function()
    if type(root.profiles) == "table" and next(root.profiles) ~= nil then
        root.profileSafetyCopy = clone(root.profiles)
    end
end)

local callbacks = {}
local db = { global = root.global, profile = root.profiles[root.activeProfile] }
Addon.db = db

local function fire(event)
    local list = callbacks[event]
    if not list then return end
    for i = 1, #list do
        local entry = list[i]
        local target, method = entry[1], entry[2]
        if type(method) == "string" then
            if target and type(target[method]) == "function" then pcall(target[method], target, event) end
        elseif type(method) == "function" then
            pcall(method, target, event)
        end
    end
end

function db.RegisterCallback(target, event, method)
    if type(event) ~= "string" or method == nil then return end
    callbacks[event] = callbacks[event] or {}
    callbacks[event][#callbacks[event] + 1] = { target, method }
end

function db:GetProfiles(out)
    out = out or {}
    for name in pairs(root.profiles) do out[#out + 1] = name end
    return out
end

function db:GetCurrentProfile() return root.activeProfile end

function db:SetProfile(name)
    if type(name) ~= "string" or name == "" then return end
    root.profiles[name] = type(root.profiles[name]) == "table" and root.profiles[name] or defaultProfile()
    fill(root.profiles[name], defaultProfile())
    root.activeProfile = name
    self.profile = root.profiles[name]
    fire("OnProfileChanged")
end

function db:CopyProfile(source)
    local sourceTable = root.profiles[source]
    if type(sourceTable) ~= "table" then return end
    root.profiles[root.activeProfile] = clone(sourceTable)
    self.profile = root.profiles[root.activeProfile]
    fire("OnProfileCopied")
end

function db:ResetProfile()
    root.profiles[root.activeProfile] = defaultProfile()
    self.profile = root.profiles[root.activeProfile]
    fire("OnProfileReset")
end

function db:DeleteProfile(name)
    if name == root.activeProfile then return false end
    root.profiles[name] = nil
    return true
end

Addon.CloneTable = clone
Addon.FillDefaults = fill
Addon.GetFreshProfile = defaultProfile

-- Compatibility aliases used by the existing feature modules. These point to the
-- new NexosCC database and do not depend on any external addon framework.
function Addon:GetProfile() return self.db and self.db.profile end
function Addon:GetGlobal() return self.db and self.db.global end

-- Blizzard setting bridge used by the native-options page.  The compatibility
-- names are retained for the project modules, but the implementation is a
-- small direct wrapper around Blizzard's CVar API.
local function readCVar(name)
    if type(name) ~= "string" or name == "" then return nil end
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        local ok, value = pcall(C_CVar.GetCVar, name)
        if ok then return value end
    end
    if type(GetCVar) == "function" then
        local ok, value = pcall(GetCVar, name)
        if ok then return value end
    end
end

function Addon:HasForeverNativeCVar(name)
    return readCVar(name) ~= nil
end

function Addon:GetForeverNativeCVarBool(name)
    local value = readCVar(name)
    if value == nil then return false end
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    value = tostring(value):lower()
    return value == "1" or value == "true" or value == "on" or value == "yes"
end

function Addon:SetForeverNativeCVarBool(name, enabled)
    if not self:HasForeverNativeCVar(name) then return false end
    local value = enabled and "1" or "0"
    if C_CVar and type(C_CVar.SetCVar) == "function" then
        return pcall(C_CVar.SetCVar, name, value)
    end
    if type(SetCVar) == "function" then
        return pcall(SetCVar, name, value)
    end
    return false
end
