-- NexosCC cooldown-ready alerts. Enabled by default; no polling, no secure-frame mutation.
local addonName, Addon = ...
local Ready = {}
Addon.CooldownReadyAlerts = Ready
local tracked = setmetatable({}, {__mode='k'})
local current, queue = nil, {}
local displaySerial = 0
local holder = CreateFrame('Frame', nil, UIParent)
holder:SetSize(90, 90)
holder:SetPoint('TOP', UIParent, 'TOP', 0, -125)
holder:SetFrameStrata('HIGH')
local texture = holder:CreateTexture(nil, 'ARTWORK')
texture:SetAllPoints()
-- Animated entrance: quick zoom-in, bright flash, and a soft gold pulse.
-- All visuals are native UI textures/animations; no polling or action-bar changes.
local border = holder:CreateTexture(nil, 'OVERLAY')
border:SetTexture('Interface\\Buttons\\UI-ActionButton-Border')
border:SetBlendMode('ADD')
border:SetPoint('CENTER', holder, 'CENTER')
border:SetSize(128, 128)
border:SetVertexColor(1, 0.78, 0.25, 0.95)
local flash = holder:CreateTexture(nil, 'OVERLAY', nil, 1)
flash:SetAllPoints(texture)
flash:SetColorTexture(1, 0.92, 0.65, 1)
flash:SetBlendMode('ADD')
-- Native WoW animation API: SetScale(x, y), not SetScaleFrom/SetScaleTo.
-- Two-stage center-screen expansion and contraction, based on the classic
-- cooldown-finished visual, with NexosCC's independent flash and gold pulse.
local entrance = holder:CreateAnimationGroup()
entrance:SetLooping('NONE')
local zoomOut = entrance:CreateAnimation('Scale')
zoomOut:SetOrder(1)
zoomOut:SetOrigin('CENTER', 0, 0)
zoomOut:SetScale(2.5, 2.5)
zoomOut:SetDuration(0.30)
local fadeIn = entrance:CreateAnimation('Alpha')
fadeIn:SetOrder(1)
fadeIn:SetFromAlpha(0)
fadeIn:SetToAlpha(0.90)
fadeIn:SetDuration(0.30)
local zoomBack = entrance:CreateAnimation('Scale')
zoomBack:SetOrder(2)
zoomBack:SetOrigin('CENTER', 0, 0)
zoomBack:SetScale(-2.5, -2.5)
zoomBack:SetDuration(0.30)
local settle = entrance:CreateAnimation('Alpha')
settle:SetOrder(2)
settle:SetFromAlpha(0.90)
settle:SetToAlpha(1)
settle:SetDuration(0.30)
local flashAnim = flash:CreateAnimationGroup()
local flashFade = flashAnim:CreateAnimation('Alpha')
flashFade:SetFromAlpha(0.95)
flashFade:SetToAlpha(0)
flashFade:SetDuration(0.38)
flashFade:SetSmoothing('OUT')
flashAnim:SetScript('OnFinished', function() flash:SetAlpha(0) end)
local pulse = border:CreateAnimationGroup()
local pulseIn = pulse:CreateAnimation('Alpha')
pulseIn:SetOrder(1)
pulseIn:SetFromAlpha(0.95)
pulseIn:SetToAlpha(0.35)
pulseIn:SetDuration(0.42)
local pulseOut = pulse:CreateAnimation('Alpha')
pulseOut:SetOrder(2)
pulseOut:SetFromAlpha(0.35)
pulseOut:SetToAlpha(0.75)
pulseOut:SetDuration(0.42)
pulse:SetLooping('REPEAT')
local exitAnim = holder:CreateAnimationGroup()
local exitFade = exitAnim:CreateAnimation('Alpha')
exitFade:SetFromAlpha(1)
exitFade:SetToAlpha(0)
exitFade:SetDuration(0.28)
exitAnim:SetScript('OnFinished', function() holder:Hide() holder:SetAlpha(1) end)
holder:Hide()
local function options()
    local p = Addon.db and Addon.db.profile
    if not p then return nil end
    p.cooldownReadyAlerts = p.cooldownReadyAlerts or {enabled=true, minimum=60, size=80, duration=1.8, sound=false}
    return p.cooldownReadyAlerts
end
function Ready:GetOptions() return options() end
local function displayNext()
    if current or #queue == 0 then return end
    local item = table.remove(queue, 1)
    local cfg = options()
    if not cfg or not cfg.enabled then queue={} return end
    current = item
    displaySerial = displaySerial + 1
    local serial = displaySerial
    holder:SetSize(cfg.size or 80, cfg.size or 80)
    texture:SetTexture(item)
    border:SetSize((cfg.size or 80) * 1.55, (cfg.size or 80) * 1.55)
    entrance:Stop()
    flashAnim:Stop()
    pulse:Stop()
    exitAnim:Stop()
    holder:SetAlpha(1)
    flash:SetAlpha(1)
    border:SetAlpha(0.95)
    holder:Show()
    entrance:Play()
    flashAnim:Play()
    pulse:Play()
    if cfg.sound and PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, 'Master') end
    local visibleFor = math.max(0.45, cfg.duration or 1.8)
    C_Timer.After(visibleFor - 0.28, function()
        if displaySerial ~= serial then return end
        pulse:Stop()
        exitAnim:Play()
    end)
    C_Timer.After(visibleFor, function()
        if displaySerial ~= serial then return end
        entrance:Stop()
        flashAnim:Stop()
        pulse:Stop()
        exitAnim:Stop()
        holder:Hide()
        holder:SetAlpha(1)
        current = nil
        displayNext()
    end)
end
local function actionButton(cooldown)
    local parent = cooldown and cooldown.GetParent and cooldown:GetParent()
    if not parent or not parent.GetName then return end
    local ok, name = pcall(parent.GetName, parent)
    if not ok or type(name) ~= 'string' then return end
    if name:match('^ActionButton%d+$') or name:match('^MultiBar[%w_]+Button%d+$')
        or name:match('^OverrideActionBarButton%d+$') then return parent end
end
function Ready:Start(cooldown, startTime, duration)
    local cfg = options()
    if not cfg or not cfg.enabled then tracked[cooldown]=nil return end
    local button = actionButton(cooldown)
    if not button then return end
    -- Protected values must never enter Lua comparisons or arithmetic.
    if type(startTime) ~= 'number' or type(duration) ~= 'number' then return end
    if canaccessvalue and (not canaccessvalue(startTime) or not canaccessvalue(duration)) then return end
    if duration < (cfg.minimum or 60) or startTime <= 0 then
        -- Ignore GCD pulses without erasing a long cooldown already tracked.
        return
    end
    local action = button.action
    if type(action) ~= 'number' or (canaccessvalue and not canaccessvalue(action)) then return end
    local kind, id = GetActionInfo(action)
    if kind ~= 'spell' and kind ~= 'item' then return end
    local icon = GetActionTexture and GetActionTexture(action)
    if not icon then return end
    tracked[cooldown] = {ends=startTime+duration, icon=icon, action=action, id=id}
end
function Ready:Done(cooldown)
    local data = tracked[cooldown]
    tracked[cooldown] = nil
    local cfg = options()
    if not data or not cfg or not cfg.enabled then return end
    -- OnCooldownDone can fire when a cooldown is reset or a button is recycled.
    if GetTime() + 0.35 < data.ends then return end
    local button = actionButton(cooldown)
    if not button or button.action ~= data.action then return end
    local kind, id = GetActionInfo(data.action)
    if id ~= data.id or (kind ~= 'spell' and kind ~= 'item') then return end
    if #queue >= 5 then table.remove(queue, 1) end
    queue[#queue+1] = data.icon
    displayNext()
end


-- Event-driven action-slot completion watcher. Cooldown frames do not reliably
-- fire an OnCooldownDone event on every supported client. Observe the native
-- action cooldown API instead, schedule only active long cooldowns, and confirm
-- their actual completion before displaying a ready alert. No OnUpdate polling.
local slotTimers = {}
local scanPending = false
local function safeNumber(value)
    if type(value) ~= "number" then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    if canaccessvalue and not canaccessvalue(value) then return nil end
    return value
end
local function slotCooldown(slot)
    if C_ActionBar and C_ActionBar.GetActionCooldown then
        local ok, result = pcall(C_ActionBar.GetActionCooldown, slot)
        if ok and type(result) == "table" then
            return safeNumber(result.startTime), safeNumber(result.duration), result.isEnabled
        end
    end
    if GetActionCooldown then
        local ok, start, duration, enabled = pcall(GetActionCooldown, slot)
        if ok then return safeNumber(start), safeNumber(duration), enabled end
    end
end
local function actionIdentity(slot)
    if not GetActionInfo then return end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or (kind ~= "spell" and kind ~= "item") then return end
    if issecretvalue and (issecretvalue(kind) or issecretvalue(id)) then return end
    local okIcon, icon = pcall(GetActionTexture, slot)
    if not okIcon or not icon or (issecretvalue and issecretvalue(icon)) then return end
    return kind, id, icon
end
local function alertReady(icon)
    if not icon then return end
    if #queue >= 5 then table.remove(queue, 1) end
    queue[#queue+1] = icon
    displayNext()
end
local function checkSlot(slot, generation)
    local item = slotTimers[slot]
    if not item or item.generation ~= generation then return end
    local cfg = options()
    if not cfg or not cfg.enabled then slotTimers[slot] = nil return end
    local kind, id = actionIdentity(slot)
    if kind ~= item.kind or id ~= item.id then slotTimers[slot] = nil return end
    local start, duration = slotCooldown(slot)
    local now = GetTime()
    if start and duration and start > 0 and duration > 1.5 then
        local ends = start + duration
        if ends > now + 0.35 then
            -- A cooldown was extended/restarted. Follow its new finish time.
            if math.abs(ends - item.ends) > 0.5 then
                item.ends = ends
                item.generation = item.generation + 1
                local nextGeneration = item.generation
                C_Timer.After(math.min(math.max(ends - now + 0.12, 0.2), 86400), function() checkSlot(slot, nextGeneration) end)
            else
                C_Timer.After(math.min(math.max(ends - now + 0.12, 0.2), 86400), function() checkSlot(slot, generation) end)
            end
            return
        end
    end
    slotTimers[slot] = nil
    if now + 0.4 >= item.ends then alertReady(item.icon) end
end
local function scanSlots()
    scanPending = false
    local cfg = options()
    if not cfg or not cfg.enabled then return end
    for slot = 1, 180 do
        local kind, id, icon = actionIdentity(slot)
        if kind then
            local start, duration, enabled = slotCooldown(slot)
            local now = GetTime()
            if start and duration and start > 0 and duration >= (cfg.minimum or 60)
                and duration > 1.5 and start + duration > now + 0.4 and enabled ~= 0 then
                local ends = start + duration
                local prior = slotTimers[slot]
                if not prior or prior.kind ~= kind or prior.id ~= id or math.abs(prior.ends - ends) > 0.5 then
                    local generation = prior and (prior.generation + 1) or 1
                    slotTimers[slot] = {kind=kind, id=id, icon=icon, ends=ends, generation=generation}
                    C_Timer.After(math.min(math.max(ends - now + 0.12, 0.2), 86400), function() checkSlot(slot, generation) end)
                end
            end
        end
    end
end
local function requestScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.15, scanSlots)
end
local watcher = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_SLOT_CHANGED", "BAG_UPDATE_COOLDOWN"}) do
    watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent", requestScan)
