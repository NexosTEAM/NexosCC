local _, Addon = ...
local rules = {}

local function parentName(frame)
    local node = frame
    for _ = 1, 14 do
        if not node then return nil end
        if node.GetName then
            local ok, name = pcall(node.GetName, node)
            if ok and type(name) == "string" and name ~= "" then return name, node end
        end
        if not node.GetParent then return nil end
        local ok, p = pcall(node.GetParent, node)
        if not ok then return nil end
        node = p
    end
end

function Addon.MatchName(patterns)
    if type(patterns) ~= "table" then patterns = { patterns } end
    return function(frame)
        local node = frame
        for _ = 1, 14 do
            if not node then break end
            local name = node.GetName and node:GetName()
            if type(name) == "string" then
                for i = 1, #patterns do if name:match(patterns[i]) then return true end end
            end
            node = node.GetParent and node:GetParent() or nil
        end
        return false
    end
end

function Addon:RegisterRule(def)
    if type(def) ~= "table" or type(def.id) ~= "string" then return false end
    local matcher = def.match
    if type(matcher) == "table" then matcher = self.MatchName(matcher) end
    if type(matcher) ~= "function" then return false end
    for i = #rules, 1, -1 do if rules[i].id == def.id then table.remove(rules, i) end end
    rules[#rules + 1] = {
        id = def.id,
        priority = tonumber(def.priority) or 1000,
        displayName = def.displayName,
        enabled = def.enabled,
        match = matcher,
    }
    table.sort(rules, function(a, b) return a.priority < b.priority end)
    return true
end

function Addon:UnregisterRule(id)
    for i = #rules, 1, -1 do if rules[i].id == id then table.remove(rules, i) return true end end
end
function Addon:IterateRules() return ipairs(rules) end

function Addon:IsRuleEnabled(rule)
    local settings = self.db and self.db.profile and self.db.profile.rules and self.db.profile.rules[rule.id]
    if settings and settings.enabled ~= nil then return settings.enabled == true end
    if rule.enabled ~= nil then return rule.enabled == true end
    return true
end

local function isMarkedNameplate(cd)
    local node = cd
    for _ = 1, 14 do
        if not node then break end
        if node.NXCNameplateAura or node.NexosCCNameplateAura or node.namePlateUnitToken or node.isNamePlate or node._nxcTPAuraCooldown then return true end
        local name = node.GetName and node:GetName()
        if type(name) == "string" and (name:find("NamePlate") or name:find("ThreatPlate")) then return true end
        node = node.GetParent and node:GetParent() or nil
    end
    return false
end
Addon.IsNexosNameplateCooldown = isMarkedNameplate

Addon:RegisterRule({ id = "action", priority = 100, match = function(cd)
    local p = cd and cd.GetParent and cd:GetParent()
    return p and p.action and p.cooldown == cd
end })
Addon:RegisterRule({ id = "action_charge", priority = 110, match = function(cd)
    local p = cd and cd.GetParent and cd:GetParent()
    return p and p.action and p.chargeCooldown == cd
end })
Addon:RegisterRule({ id = "action_loc", priority = 120, match = function(cd)
    local p = cd and cd.GetParent and cd:GetParent()
    return p and p.action and p.lossOfControlCooldown == cd
end })
Addon:RegisterRule({ id = "nexos_nameplate_aura", priority = 300, displayName = "NexosCC Nameplate Auras", match = isMarkedNameplate })
Addon:RegisterRule({ id = "blizzard_nameplates", priority = 310, displayName = "Nameplates", match = Addon.MatchName({ "^NamePlate%d+", "^ThreatPlate" }) })
Addon:RegisterRule({ id = "blizzard_party", priority = 400, displayName = "Party Frames", match = Addon.MatchName({ "^PartyFrame", "^CompactPartyFrame" }) })
Addon:RegisterRule({ id = "blizzard_raid", priority = 410, displayName = "Raid Frames", match = Addon.MatchName({ "^CompactRaidGroup" }) })
Addon:RegisterRule({ id = "blizzard_arena", priority = 420, displayName = "Arena Frames", match = Addon.MatchName({ "^CompactArenaFrame" }) })
Addon:RegisterRule({ id = "nexos_player_frame", priority = 425, displayName = "Player Frame", match = Addon.MatchName({ "^NexosCC_PlayerFrameAura" }) })
Addon:RegisterRule({ id = "blizzard_target", priority = 430, displayName = "Target Frame", match = Addon.MatchName({ "^TargetFrame" }) })
Addon:RegisterRule({ id = "blizzard_focus", priority = 440, displayName = "Focus Frame", match = Addon.MatchName({ "^FocusFrame" }) })
Addon:RegisterRule({ id = "blizzard_pet", priority = 450, displayName = "Pet Frame", match = Addon.MatchName({ "^PetFrame" }) })
Addon:RegisterRule({ id = "blizzard_petbar", priority = 500, displayName = "Pet Action Bar", match = Addon.MatchName({ "^PetActionButton%d+" }) })
Addon:RegisterRule({ id = "blizzard_stancebar", priority = 510, displayName = "Stance Bar", match = Addon.MatchName({ "^StanceButton%d+" }) })
Addon:RegisterRule({ id = "blizzard_possessbar", priority = 520, displayName = "Possess Bar", match = Addon.MatchName({ "^PossessButton%d+" }) })
Addon:RegisterRule({ id = "blizzard_extrabar", priority = 530, displayName = "Extra Action", match = Addon.MatchName({ "^ExtraActionButton%d+" }) })
Addon:RegisterRule({ id = "blizzard_zone", priority = 540, displayName = "Zone Ability", match = Addon.MatchName({ "^ZoneAbilityFrame" }) })
Addon:RegisterRule({ id = "blizzard_container", priority = 600, displayName = "Bags and Character", match = Addon.MatchName({ "^ContainerFrame", "^PaperDoll" }) })
Addon:RegisterRule({ id = "everything", priority = 999999, displayName = "Everything Else", enabled = true, match = function() return true end })

function Addon:GetThemeName(cooldown)
    local profile = self.db and self.db.profile
    if not profile then return "default" end
    local selected = "default"
    for _, rule in ipairs(rules) do
        if self:IsRuleEnabled(rule) then
            local ok, matched = pcall(rule.match, cooldown)
            if ok and matched then
                local setting = profile.rules and profile.rules[rule.id]
                selected = setting and setting.theme or ((rule.id == "nexos_nameplate_aura" or rule.id == "blizzard_nameplates") and "nameplates" or "default")
                break
            end
        end
    end
    if profile.nexosAutoFitEnabled and selected ~= "none" then return "nexos_autofit" end
    return selected or "default"
end

Addon.GetStyleName = Addon.GetThemeName
