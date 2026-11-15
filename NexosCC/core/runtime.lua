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

-- Unit frame badges may be anonymous children or anchor points, so checking
-- global frame names alone misses cooldowns attached to the level display.
local levelFields = {
    "Level", "level", "LevelFrame", "levelFrame", "LevelText", "levelText",
    "LevelBadge", "levelBadge", "LevelIndicator", "levelIndicator",
    "LevelCircle", "levelCircle", "HighLevelTexture", "highLevelTexture",
    "LevelSkull", "levelSkull", "LevelCooldown", "levelCooldown",
}

local function namedLevelRegion(node)
    local name = node.GetName and node:GetName()
    if secret(name) or type(name) ~= "string" then return false end
    local lower = name:lower()
    if not lower:find("level", 1, true) then return false end
    local unitFrame = lower:find("target", 1, true) or lower:find("focus", 1, true)
        or lower:find("unitframe", 1, true) or lower:find("nameplate", 1, true)
        or lower:find("bossframe", 1, true) or lower:find("arenaframe", 1, true)
        or lower:find("playerframe", 1, true)
    return unitFrame and (lower:match("level$") or lower:match("levelframe$")
        or lower:find("levelbadge", 1, true) or lower:find("levelindicator", 1, true)
        or lower:find("levelcircle", 1, true) or lower:find("leveltext", 1, true)
        or lower:find("levelskull", 1, true) or lower:find("highlevel", 1, true)
        or lower:match("levelcooldown$") or lower:match("levelborder$"))
end

local function isLevelRegion(node, parent)
    if namedLevelRegion(node) then return true end
    if not parent then return false end
    for i = 1, #levelFields do
        local region = parent[levelFields[i]]
        if not secret(region) and region == node then return true end
    end
    return false
end

local function isUnitLevelBadge(cooldown, parent)
    local node = cooldown
    for _ = 1, 24 do
        if not node or node == _G.UIParent or node == _G.WorldFrame then break end
        if isLevelRegion(node, parent) then return true end
        if parent == node then break end
        node = parent
        parent = node and node.GetParent and node:GetParent()
    end
    for i = 1, cooldown.GetNumPoints and cooldown:GetNumPoints() or 0 do
        local _, anchor = cooldown:GetPoint(i)
        if not secret(anchor) and anchor and anchor ~= cooldown
            and isLevelRegion(anchor, anchor.GetParent and anchor:GetParent()) then
            return true
        end
    end
    return false
end

local function needsBadgeExclusion(cooldown)
    -- These cooldowns have explicit owners. Their timers still use the
    -- regular theme routing, including when the user changes a theme.
    if cooldown.NXCNexosNameplateCooldown == true then return false end
    local parent = cooldown.GetParent and cooldown:GetParent()
    if parent and parent.action
        and (parent.cooldown == cooldown or parent.chargeCooldown == cooldown
            or parent.chargeCooldownFrame == cooldown or parent.lossOfControlCooldown == cooldown) then
        return false
    end
    return isUnitLevelBadge(cooldown, parent)
end

-- The native level and skull are separate regions. Mask the number only
-- while the corresponding skull is shown and then restore its original alpha.
local levelBindings = setmetatable({}, { __mode = "k" })

local function syncLevelText(level, state)
    if state.applying then return end
    local shown = state.skull:IsShown()
    if secret(shown) then return end
    local alpha = level:GetAlpha()
    if secret(alpha) then return end
    if shown then
        if state.originalAlpha == nil then state.originalAlpha = alpha end
        if alpha == 0 then return end
        alpha = 0
    elseif state.originalAlpha ~= nil then
        alpha = state.originalAlpha
        state.originalAlpha = nil
    else
        return
    end
    state.applying = true
    pcall(level.SetAlpha, level, alpha)
    state.applying = false
end

local function bindLevelText(level, skull)
    if blocked(level) or blocked(skull) or not level.GetAlpha or not level.SetAlpha
        or not skull.IsShown then return end
    local state = levelBindings[level]
    if not state then
        state = {}
        levelBindings[level] = state
        pcall(hooksecurefunc, level, "SetAlpha", function(_, alpha)
            if state.applying or secret(alpha) or type(alpha) ~= "number" then return end
            if state.originalAlpha ~= nil then state.originalAlpha = alpha end
            syncLevelText(level, state)
        end)
    end
    if state.skull ~= skull then
        state.skull = skull
        local function onSkullVisibility()
            if state.skull == skull then pcall(syncLevelText, level, state) end
        end
        for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
            if skull[method] then pcall(hooksecurefunc, skull, method, onSkullVisibility) end
        end
    end
    syncLevelText(level, state)
end

local function bindContentLevel(content)
    if not content then return end
    local main = content.TargetFrameContentMain
    local contextual = content.TargetFrameContentContextual
    if main then
        local skull = (contextual and contextual.HighLevelTexture) or main.HighLevelTexture
        bindLevelText(main.LevelText, skull)
    end
end

local function updateTargetLevelBadge(frame)
    if blocked(frame) then return end
    local content = frame.TargetFrameContent
    bindContentLevel(content)
    local container = frame.TargetFrameContainer
    local nestedContent = container and container.TargetFrameContent
    if nestedContent ~= content then bindContentLevel(nestedContent) end

    local texture = frame.TextureFrame or _G.TargetFrameTextureFrame
    local level = frame.LevelText or frame.levelText or (texture and (texture.LevelText or texture.levelText))
        or _G.TargetFrameTextureFrameLevelText or _G.TargetLevelText
    local skull = frame.HighLevelTexture or frame.highLevelTexture
        or (texture and (texture.HighLevelTexture or texture.highLevelTexture))
        or _G.TargetFrameTextureFrameHighLevelTexture or _G.TargetHighLevelTexture
    if not blocked(level) and not levelBindings[level] then bindLevelText(level, skull) end
end

local function styleFor(cooldown)
    local profile = Addon.db and Addon.db.profile
    if not profile or type(profile.themes) ~= "table" then return nil, nil end
    local id = Addon:GetThemeName(cooldown)
    return profile.themes[id] or profile.themes.default, id
end

local function apply(cooldown)
    if blocked(cooldown) then return end
    local badgeOK, badge = pcall(needsBadgeExclusion, cooldown)
    if badgeOK and badge then
        -- Only the cooldown timer text is suppressed. Never hide the badge,
        -- level FontString, skull texture, or parent frame.
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

local function onTargetLevelUpdated(frame)
    local target = _G.TargetFrame
    if not frame or frame == target then pcall(updateTargetLevelBadge, target) end
end

if type(_G.TargetFrame_CheckLevel) == "function" then
    hooksecurefunc("TargetFrame_CheckLevel", onTargetLevelUpdated)
end

local levelEvents = CreateFrame("Frame")
levelEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
levelEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
levelEvents:RegisterUnitEvent("UNIT_LEVEL", "target")
levelEvents:SetScript("OnEvent", function()
    onTargetLevelUpdated(_G.TargetFrame)
end)

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

SLASH_NEXOSCC1 = "/nexoscc"
SLASH_NEXOSCC2 = "/ncc"
SLASH_NEXOSCC3 = "/nxc"
SlashCmdList.NEXOSCC = function(msg)
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

-- Place the launcher in the real gap between Macros and Log Out.
do
    local button

    local function findMenuButtons(menu)
        local macros = _G.GameMenuButtonMacros
        local logout = _G.GameMenuButtonLogout
        if macros and logout then return macros, logout end
        for _, child in ipairs({ menu:GetChildren() }) do
            if child.GetText and child ~= button then
                local label = child:GetText()
                if not macros and label == (_G.MACROS or "Macros") then macros = child end
                if not logout and (label == (_G.LOG_OUT or "Log Out") or label == "Log Out") then
                    logout = child
                end
            end
        end
        return macros, logout
    end

    local function place()
        local menu = _G.GameMenuFrame
        if not menu or not menu.IsShown or not menu:IsShown() then return end
        if _G.NexosCC_ShowGameMenuButton == false then
            if button then button:Hide() end
            return
        end

        local macros, logout = findMenuButtons(menu)
        if not macros or not logout then return end
        if not button then
            button = CreateFrame("Button", "NexosCCGameMenuButton", menu, "GameMenuButtonTemplate")
            button:SetText("NexosCC")
            local fontString = button.GetFontString and button:GetFontString()
            if fontString and fontString.SetTextColor then
                fontString:SetTextColor(0.35, 0.78, 1.0, 1)
            end
            button:SetScript("OnClick", function()
                if HideUIPanel then HideUIPanel(menu) else menu:Hide() end
                openConfig()
            end)
        end

        local scale = menu:GetEffectiveScale()
        if not scale or scale <= 0 then scale = 1 end
        local top = macros:GetBottom()
        local bottom = logout:GetTop()
        if not top or not bottom then return end
        local gap = (top - bottom) * scale
        if gap < 13 then button:Hide(); return end

        local buttonHeight = math.min(20, gap - 7)
        button:SetSize(macros:GetWidth(), buttonHeight / scale)
        button:ClearAllPoints()
        button:SetPoint("TOP", macros, "BOTTOM", 0, -2 / scale)
        button:Show()
    end

    local hookedMenu
    local function installMenuHook()
        local menu = _G.GameMenuFrame
        if not menu or hookedMenu == menu then return end
        menu:HookScript("OnShow", function()
            place()
            if C_Timer and C_Timer.After then C_Timer.After(0, place) end
        end)
        hookedMenu = menu
    end
    Addon.RefreshGameMenuButton = function()
        installMenuHook()
        place()
    end
    if _G.GameMenuFrame then
        installMenuHook()
        if _G.GameMenuFrame:IsShown() then place() end
    else
        local menuEvents = CreateFrame("Frame")
        menuEvents:RegisterEvent("ADDON_LOADED")
        menuEvents:RegisterEvent("PLAYER_LOGIN")
        menuEvents:SetScript("OnEvent", function(self)
            if not _G.GameMenuFrame then return end
            installMenuHook()
            self:UnregisterEvent("ADDON_LOADED")
            self:UnregisterEvent("PLAYER_LOGIN")
        end)
    end
end
