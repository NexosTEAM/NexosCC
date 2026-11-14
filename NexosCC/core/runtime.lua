local addonName, Addon = ...

local tracked = setmetatable({}, { __mode = "k" })
local pendingRefresh = false
local styleCache = setmetatable({}, { __mode = "k" })

local function secret(v)
    return issecretvalue and issecretvalue(v)
end

local function blocked(cooldown)
    if not cooldown or secret(cooldown) then return true end
    if cooldown.IsForbidden and cooldown:IsForbidden() then return true end
    return false
end

-- Forever PvP season/rank emblems are not spell cooldowns.  The global
-- Cooldown hook can otherwise put a bogus minute counter on the rank badge.
-- Match only rank-related descendants of the PvP/Honor UI, not combat abilities.
local function isPvpRankEmblem(cooldown)
    if Addon.isForever ~= true and (select(4, GetBuildInfo()) or 0) ~= 16001 then return false end
    local node = cooldown
    local inPvp = false
    local rankRelated = false
    local inInspect = false
    for _ = 1, 22 do
        if not node then break end
        local ok, name = pcall(function() return node.GetName and node:GetName() end)
        if ok and type(name) == "string" then
            local lower = name:lower()
            if lower:find("inspect", 1, true) then inInspect = true end
            if lower:find("pvp", 1, true) or lower:find("honor", 1, true) or lower:find("conquest", 1, true) then
                inPvp = true
            end
            if lower:find("rank", 1, true) or lower:find("season", 1, true) or lower:find("badge", 1, true) or lower:find("emblem", 1, true) then
                rankRelated = true
            end
        end
        local parentOk, parent = pcall(function() return node.GetParent and node:GetParent() end)
        if not parentOk or parent == node then break end
        node = parent
    end
    -- The inspected player rank emblem is under the Inspect UI, not the
    -- local player PvP panel. Its cooldown child may have no rank name.
    -- Restrict this additional exclusion to Inspect PvP/Honor subtrees.
    return (inPvp and rankRelated) or (inInspect and (inPvp or rankRelated))
end

-- Unit-level badges are not cooldowns.  In particular, a high-level target
-- can have an unknown-level/skull indicator beside its portrait.  Do not
-- decorate cooldown-shaped widgets owned by those level badges.
-- Restrict this to named level/badge descendants, never an entire unit frame:
-- real buff, debuff and portrait cooldowns must remain eligible.
local function isUnitLevelBadge(cooldown)
    -- The unit-level decoration is frequently an unnamed Cooldown child.
    -- The previous test required both a unit-frame name and a very specific
    -- level-badge name; this missed older Forever mob portrait layouts.
    local node = cooldown
    local unitContext = false
    local levelContext = false
    for _ = 1, 24 do
        if not node then break end
        local ok, name = pcall(function() return node.GetName and node:GetName() end)
        if ok and type(name) == "string" then
            local lower = name:lower()
            if lower:find("targetframe", 1, true) or lower:find("focusframe", 1, true)
                or lower:find("unitframe", 1, true) or lower:find("nameplate", 1, true)
                or lower:find("bossframe", 1, true) or lower:find("arenaframe", 1, true)
                or lower:find("playerframe", 1, true) or lower:find("levelbadge", 1, true)
                or lower:find("levelindicator", 1, true) then
                unitContext = true
            end
            -- Match Blizzard's ordinary 'Level' children as well as the
            -- named badge variants. Only accept this when a unit frame is
            -- also in the ancestry, so spell/item cooldowns stay eligible.
            if lower:find("level", 1, true) and not lower:find("itemlevel", 1, true)
                and not lower:find("spelllevel", 1, true) then
                levelContext = true
            end
        end
        local parentOk, parent = pcall(function() return node.GetParent and node:GetParent() end)
        if not parentOk or parent == node then break end
        node = parent
    end
    return unitContext and levelContext
end

local function styleFor(cooldown)
    local profile = Addon.db and Addon.db.profile
    if not profile or type(profile.themes) ~= "table" then return nil, nil end
    local id = Addon:GetThemeName(cooldown)
    return profile.themes[id] or profile.themes.default, id
end

local function apply(cooldown)
    if blocked(cooldown) then return end
    if isUnitLevelBadge(cooldown) then
        if cooldown.SetHideCountdownNumbers then pcall(cooldown.SetHideCountdownNumbers, cooldown, true) end
        tracked[cooldown] = nil
        styleCache[cooldown] = nil
        return
    end
    if isPvpRankEmblem(cooldown) then
        -- Do not alter the rank emblem artwork or its native behavior.
        if cooldown.SetHideCountdownNumbers then pcall(cooldown.SetHideCountdownNumbers, cooldown, true) end
        tracked[cooldown] = nil
        styleCache[cooldown] = nil
        return
    end
    if cooldown.noCooldownCount then
        if cooldown.SetHideCountdownNumbers then pcall(cooldown.SetHideCountdownNumbers, cooldown, true) end
        return
    end

    local style, id = styleFor(cooldown)
    if not style then return end

    if _G.NexosCC_CooldownsOnly == true and Addon.IsNexosNameplateCooldown(cooldown) then
        -- In the compatibility preset third-party/nameplate aura visuals retain ownership.
        if cooldown.SetHideCountdownNumbers then pcall(cooldown.SetHideCountdownNumbers, cooldown, true) end
        return
    end

    local cache = styleCache[cooldown]
    if not cache or cache.style ~= style or cache.serial ~= Addon._styleSerial then
        local fn = Addon:CreateThemer(style)
        styleCache[cooldown] = { style = style, fn = fn, serial = Addon._styleSerial, id = id }
        cache = styleCache[cooldown]
    end
    if cache.fn then pcall(cache.fn, cooldown) end
    tracked[cooldown] = true
end

local function onStart(cooldown)
    apply(cooldown)
end

local function onDone(cooldown)
    if cooldown then tracked[cooldown] = nil; styleCache[cooldown] = nil end
end

function Addon:Refresh()
    self._styleSerial = (self._styleSerial or 0) + 1
    if pendingRefresh then return end
    pendingRefresh = true
    local function run()
        pendingRefresh = false
        -- On-demand discovery of currently visible action cooldowns. This is only
        -- performed when a user changes a setting, never on an update ticker.
        -- It also styles cooldowns that existed before our hooks were installed.
        local prefixes = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
            "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
        for i = 1, #prefixes do
            for n = 1, 12 do
                local button = _G[prefixes[i] .. n]
                if button then
                    local cd = button.cooldown or _G[(button.GetName and button:GetName() or "") .. "Cooldown"]
                    if cd then apply(cd) end
                    local charge = button.chargeCooldown or button.chargeCooldownFrame
                    if charge then apply(charge) end
                end
            end
        end
        for cooldown in pairs(tracked) do apply(cooldown) end
        -- Feature modules own their own repaint paths. Ask them to refresh only
        -- when they expose an explicit refresh entry point; no frame scanning.
        local names = {
            "MidnightNameplates", "ForeverNameplates", "MidnightSelfCooldowns", "ForeverSelfCooldowns",
            "MidnightTargetPortrait", "ForeverTargetPortrait", "MidnightAuraTextControls", "ForeverAuraTextControls",
            "MidnightPlayerFrameAuras", "ForeverPlayerFrameAuras", "MidnightNativeTargetAuras", "ForeverTargetAuraTimers",
        }
        for i = 1, #names do
            local module = self[names[i]]
            if module then
                local fn = module.RefreshTextAppearance or module.RefreshThemeAppearance or module.Refresh
                if type(fn) == "function" then pcall(fn, module) end
            end
        end
    end
    -- Style Studio needs immediate visual feedback; defer only protected work
    -- inside individual modules rather than the entire cooldown repaint.
    run()
end

local function installHooks()
    local sample = _G.ActionButton1Cooldown or (_G.ActionButton1 and _G.ActionButton1.cooldown)
    if not sample then return false end
    local mt = getmetatable(sample)
    local api = mt and mt.__index
    if type(api) ~= "table" then return false end

    local methods = { "SetCooldown", "SetCooldownDuration", "SetCooldownFromDurationObject", "SetCooldownFromExpirationTime", "SetCooldownUNIX" }
    for i = 1, #methods do
        local method = methods[i]
        if type(api[method]) == "function" then pcall(hooksecurefunc, api, method, onStart) end
    end
    if type(api.Clear) == "function" then pcall(hooksecurefunc, api, "Clear", onDone) end
    return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name ~= addonName then return end
    if installHooks() then
        self:UnregisterEvent("PLAYER_LOGIN")
        self:UnregisterEvent("ADDON_LOADED")
        Addon:Refresh()
    end
end)

local function openConfig()
    local configName = "NexosCC_Config"
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, configName) elseif LoadAddOn then pcall(LoadAddOn, configName) end
    if Addon.OpenOptions then Addon:OpenOptions() return true end
    return false
end
Addon.OpenConfiguration = openConfig

if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
    pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
        text = "NexosCC",
        icon = "Interface/AddOns/NexosCC/media/nexos_icon",
        func = openConfig,
    })
end

SLASH_NexosCCCC1 = "/nexoscc"
SLASH_NexosCCCC2 = "/ncc"
SlashCmdList.NexosCCCC = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        Addon.db:ResetProfile()
        Addon:Refresh()
        print("|cff58c8ffNexosCC|r profile reset.")
    elseif msg == "version" then
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
        print("|cff58c8ffNexosCC|r " .. (version or "unknown"))
    else
        openConfig()
    end
end

-- Optional Game Menu entry. Implemented locally so NexosCC does not depend on
-- another cooldown addon's launcher or menu code.
do
    local button
    local function place()
        local menu = _G.GameMenuFrame
        if not menu or not menu.IsShown or not menu:IsShown() then return end
        if _G.NexosCC_ShowGameMenuButton == false then if button then button:Hide() end return end
        local anchor = _G.GameMenuButtonMacros or _G.GameMenuButtonOptions
        local below = _G.GameMenuButtonLogout or _G.GameMenuButtonQuit
        if not anchor or not below then return end
        if not button then
            button = CreateFrame("Button", "NexosCCGameMenuButton", menu, "GameMenuButtonTemplate")
            button:SetText("NexosCC")
            button:SetScript("OnClick", function()
                if HideUIPanel then HideUIPanel(menu) else menu:Hide() end
                openConfig()
            end)
        end
        local top = anchor:GetBottom()
        local bottom = below:GetTop()
        if not top or not bottom then return end
        local available = top - bottom
        if available < 14 then button:Hide(); return end
        local scale = menu:GetEffectiveScale() or 1
        button:SetSize(anchor:GetWidth(), math.min(28, available - 4) / scale)
        button:ClearAllPoints()
        button:SetPoint("TOP", anchor, "BOTTOM", 0, -2 / scale)
        button:Show()
    end
    if _G.GameMenuFrame then
        _G.GameMenuFrame:HookScript("OnShow", function()
            place()
            if C_Timer and C_Timer.After then C_Timer.After(0, place) end
        end)
    end
    Addon.RefreshGameMenuButton = place
end
