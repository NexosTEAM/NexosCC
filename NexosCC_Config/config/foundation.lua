local _, UI = ...
local Core = _G.NexosCC
if not Core then return end

UI.PADDING = 10
UI.SPACING = 8
UI.selectedStyle = UI.selectedStyle or "default"
UI.L = { Profile = "Profile", StyleStudio = "Style Studio" }

local STYLE_NAMES = {
    default = "Action Bars",
    nameplates = "Nameplates",
    auras = "Buffs / Debuffs",
    nexos_autofit = "Auto-Fit",
}
local STYLE_ORDER = { "default", "nameplates", "auras", "nexos_autofit" }

local function profile() return Core.db and Core.db.profile end
local function styles() local p = profile(); return p and p.themes end

function UI:Refresh() Core:Refresh() end
function UI:GetStyle(id) local t = styles(); return t and t[id] end
function UI:GetStyleName(id)
    local s = self:GetStyle(id)
    return (s and s.displayName) or STYLE_NAMES[id] or id
end

local function forceFeatureRefresh(id)
    Core:Refresh()
    if id == "nameplates" or id == "nexos_autofit" then
        for _, key in ipairs({"MidnightNameplates", "ForeverNameplates"}) do
            local m = Core[key]; if m and m.Refresh then pcall(m.Refresh, m) end
        end
    end
    if id == "auras" or id == "nexos_autofit" then
        for _, key in ipairs({"MidnightAuraTextControls", "ForeverAuraTextControls", "MidnightSelfCooldowns", "ForeverSelfCooldowns"}) do
            local m = Core[key]; if m and m.Refresh then pcall(m.Refresh, m) end
        end
        -- The compact SELF/TARGET aura rows own their FontStrings separately
        -- from the generic cooldown renderer. Repaint existing strings now.
        -- Avoid rebuilding secure aura containers for typography changes.
        for _, key in ipairs({"MidnightPlayerFrameAuras", "ForeverPlayerFrameAuras", "MidnightNativeTargetAuras", "ForeverTargetAuraTimers"}) do
            local m = Core[key]
            if m then
                local fn = m.RefreshTextAppearance or m.RefreshThemeAppearance
                if fn then pcall(fn, m)
                elseif key == "ForeverTargetAuraTimers" and m.RequestApply then
                    pcall(m.RequestApply, m)
                end
            end
        end
    end
end

function UI:SetStyleProperty(id, key, value)
    local s = self:GetStyle(id)
    if not s or s[key] == value then return false end
    s[key] = value
    forceFeatureRefresh(id)
    if self._refreshStyleStudio then self._refreshStyleStudio() end
    return true
end

function UI:SelectAndRefreshStyle(id)
    if self:GetStyle(id) then UI.selectedStyle = id end
    if self._refreshStyleStudio then self._refreshStyleStudio() end
end

local function makeDropdown(parent, width, getText, buildMenu)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(width or 180)
    dd:SetupMenu(function(_, root)
        buildMenu(root)
    end)
    dd:HookScript("OnShow", function(self)
        if self.Text and getText then self.Text:SetText(getText() or "") end
    end)
    function dd:RefreshLabel()
        if self.Text and getText then self.Text:SetText(getText() or "") end
        if self.GenerateMenu then pcall(self.GenerateMenu, self) end
    end
    return dd
end

function UI:BuildProfileDropdown(parent)
    local dd
    dd = makeDropdown(parent, 150,
        function() return Core.db:GetCurrentProfile() end,
        function(root)
            local names = Core.db:GetProfiles({})
            table.sort(names)
            for i = 1, #names do
                local name = names[i]
                root:CreateRadio(name,
                    function() return Core.db:GetCurrentProfile() == name end,
                    function() Core.db:SetProfile(name); if dd then dd:RefreshLabel() end end)
            end
            root:CreateDivider()
            root:CreateButton("New Profile", function()
                local base = "Profile"
                local n, used = 1, {}
                for _, v in ipairs(Core.db:GetProfiles({})) do used[v] = true end
                while used[base .. " " .. n] do n = n + 1 end
                Core.db:SetProfile(base .. " " .. n)
                if dd then dd:RefreshLabel() end
            end)
            root:CreateButton("Duplicate Current", function()
                local source = Core.db:GetCurrentProfile()
                local n, used = 1, {}
                for _, v in ipairs(Core.db:GetProfiles({})) do used[v] = true end
                local name
                repeat name = source .. " Copy " .. n; n = n + 1 until not used[name]
                Core.db:SetProfile(name)
                Core.db:CopyProfile(source)
                if dd then dd:RefreshLabel() end
            end)
            root:CreateButton("Reset Current", function() Core.db:ResetProfile(); if dd then dd:RefreshLabel() end end)
            root:CreateDivider()
            root:CreateButton("Delete Another Profile...", function()
                local current = Core.db:GetCurrentProfile()
                local names = Core.db:GetProfiles({})
                table.sort(names)
                if not StaticPopupDialogs["NEXOSCC_DELETE_PROFILE"] then
                    StaticPopupDialogs["NEXOSCC_DELETE_PROFILE"] = {
                        text = "Delete profile '%s'? This cannot be undone.",
                        button1 = YES, button2 = NO,
                        OnAccept = function(_, name)
                            if type(name) == "string" and name ~= Core.db:GetCurrentProfile() then
                                Core.db:DeleteProfile(name)
                                if dd then dd:RefreshLabel() end
                            end
                        end,
                        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
                    }
                end
                -- The menu lists inactive profiles for safe deletion.
                local menu = MenuUtil and MenuUtil.CreateContextMenu
                if menu then
                    MenuUtil.CreateContextMenu(dd, function(_, submenu)
                        for _, name in ipairs(names) do
                            if name ~= current then
                                submenu:CreateButton(name, function() StaticPopup_Show("NEXOSCC_DELETE_PROFILE", name, nil, name) end)
                            end
                        end
                    end)
                end
            end)
        end)
    return dd
end

local function card(parent, title)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=10, insets={left=2,right=2,top=2,bottom=2} })
    f:SetBackdropColor(0.055, 0.075, 0.10, 0.92)
    f:SetBackdropBorderColor(0.22, 0.52, 0.72, 0.9)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 12, -10); t:SetText(title)
    f.Title = t
    return f
end

local function label(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y); fs:SetText(text); fs:SetJustifyH("LEFT")
    return fs
end

local function checkbox(parent, text, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.Text:SetText(text)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    cb.Refresh = function(self) self:SetChecked(getter() == true) end
    cb:Refresh()
    return cb
end

local function slider(parent, text, x, y, width, minv, maxv, step, getter, setter)
    label(parent, text, x, y)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y - 22); holder:SetSize(width, 28)
    local s = CreateFrame("Slider", nil, holder, "MinimalSliderTemplate")
    s:SetPoint("LEFT", 18, 0); s:SetPoint("RIGHT", -65, 0)
    s:SetMinMaxValues(minv, maxv); s:SetValueStep(step or 1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local minus=CreateFrame("Button",nil,holder); minus:SetSize(11,19); minus:SetPoint("RIGHT",s,"LEFT",-4,0); minus:SetNormalAtlas("Minimal_SliderBar_Button_Left")
    local plus=CreateFrame("Button",nil,holder); plus:SetSize(9,18); plus:SetPoint("LEFT",s,"RIGHT",4,0); plus:SetNormalAtlas("Minimal_SliderBar_Button_Right")
    local value=holder:CreateFontString(nil,"OVERLAY","GameFontNormal"); value:SetPoint("RIGHT",holder,"RIGHT",-2,0); value:SetWidth(43); value:SetJustifyH("RIGHT")
    local function show(v) value:SetText(tostring(math.floor((tonumber(v) or 0)+0.5))) end
    s:SetScript("OnValueChanged", function(_, v)
        show(v)
        if not UI._styleRefreshing then setter(v) end
    end)
    minus:SetScript("OnClick",function() s:SetValue((s:GetValue() or minv)-(step or 1)) end)
    plus:SetScript("OnClick",function() s:SetValue((s:GetValue() or minv)+(step or 1)) end)
    if s.EnableMouseWheel then s:EnableMouseWheel(false) end
    s:SetScript("OnMouseWheel",nil)
    holder.Refresh=function()
        UI._styleRefreshing=true
        local v=getter() or minv; s:SetValue(v); show(v)
        UI._styleRefreshing=false
    end
    holder:Refresh()
    return holder
end

local function stateDropdown(parent, text, x, y, getter, setter)
    label(parent, text, x, y)
    local dd
    dd = makeDropdown(parent, 132,
        function()
            local v = getter() or "default"
            return ({ default="Game default", always="Always", never="Never" })[v] or v
        end,
        function(root)
            for _, v in ipairs({"default","always","never"}) do
                root:CreateRadio(({ default="Game default", always="Always", never="Never" })[v],
                    function() return getter() == v end,
                    function() setter(v); if dd then dd:RefreshLabel() end end)
            end
        end)
    dd:SetPoint("TOPLEFT", x, y - 20)
    return dd
end

local function colorButton(parent, text, x, y, getter, setter)
    label(parent, text, x, y)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(44, 22); b:SetPoint("TOPLEFT", x, y - 22)
    b:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=8 })
    local function refresh()
        local r,g,bv,a = Core.HexToRGBA(getter() or "FFFFFFFF")
        b:SetBackdropColor(r,g,bv,a or 1)
    end
    b:SetScript("OnClick", function()
        if not ColorPickerFrame then return end
        local r,g,bv,a = Core.HexToRGBA(getter() or "FFFFFFFF")
        local info = {
            r=r, g=g, b=bv, opacity=1-(a or 1), hasOpacity=true,
            swatchFunc=function()
                local nr,ng,nb = ColorPickerFrame:GetColorRGB()
                local alphaGetter = ColorPickerFrame.GetColorAlpha
                local na = 1 - (alphaGetter and alphaGetter(ColorPickerFrame) or 0)
                setter(Core.RGBAToHex(nr,ng,nb,na)); refresh()
            end,
            opacityFunc=function()
                local nr,ng,nb = ColorPickerFrame:GetColorRGB()
                local alphaGetter = ColorPickerFrame.GetColorAlpha
                local na = 1 - (alphaGetter and alphaGetter(ColorPickerFrame) or 0)
                setter(Core.RGBAToHex(nr,ng,nb,na)); refresh()
            end,
        }
        if ColorPickerFrame.SetupColorPickerAndShow then ColorPickerFrame:SetupColorPickerAndShow(info)
        else ColorPickerFrame.func=info.swatchFunc; ColorPickerFrame.opacityFunc=info.opacityFunc; ColorPickerFrame:SetColorRGB(r,g,bv); ColorPickerFrame:Show() end
    end)
    b.Refresh = refresh; refresh(); return b
end

function UI:BuildStyleStudio(container)
    local host = container
    local scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -28, 0)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetHeight(700)
    body:SetWidth(math.max(760, (host:GetWidth() or 900) - 34))
    scroll:SetScrollChild(body)
    host:HookScript("OnSizeChanged", function(_, w) body:SetWidth(math.max(760, (w or 900) - 34)) end)
    container = body

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -12); title:SetText("NexosCC Style Studio")
    local sub = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Independent surface styling. Pick a surface first, then tune text, timing and cooldown graphics live.")

    local tabs = CreateFrame("Frame", nil, container)
    tabs:SetPoint("TOPLEFT", 16, -64); tabs:SetPoint("TOPRIGHT", -16, -64); tabs:SetHeight(34)
    local tabButtons = {}
    for i, id in ipairs(STYLE_ORDER) do
        local b = CreateFrame("Button", nil, tabs, "UIPanelButtonTemplate")
        b:SetSize(138, 28); b:SetPoint("LEFT", (i-1)*144, 0); b:SetText(STYLE_NAMES[id])
        b:SetScript("OnClick", function() UI:SelectAndRefreshStyle(id) end)
        tabButtons[id] = b
    end

    local left = card(container, "Typography")
    left:SetPoint("TOPLEFT", 16, -108); left:SetSize(300, 310)
    local right = card(container, "Timer Logic")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0); right:SetSize(300, 310)
    local bottom = card(container, "Cooldown Visuals & Colors")
    bottom:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -12); bottom:SetSize(680, 275)

    local controls = {}
    local function get(k) local s=UI:GetStyle(UI.selectedStyle); return s and s[k] end
    local function set(k,v) UI:SetStyleProperty(UI.selectedStyle,k,v) end

    label(left, "Font", 14, -45)
    local fontDD
    fontDD = makeDropdown(left, 190, function() return get("font") or "Friz Quadrata TT" end, function(root)
        for _, name in ipairs({"Friz Quadrata TT","Arial Narrow","Morpheus","Skurri","2002","2002 Bold","Combat Text","Quest Text","Friends Text","System Text","Chat Text"}) do
            root:CreateRadio(name, function() return get("font") == name end, function() set("font",name); fontDD:RefreshLabel() end)
        end
    end)
    fontDD:SetPoint("TOPLEFT", 14, -64); controls[#controls+1]=fontDD

    controls[#controls+1]=slider(left,"Font size",14,-108,260,5,48,1,function() return get("fontSize") end,function(v) set("fontSize",math.floor(v+.5)) end)
    controls[#controls+1]=slider(left,"Horizontal offset",14,-168,260,-24,24,1,function() return get("offsetX") end,function(v) set("offsetX",math.floor(v+.5)) end)
    controls[#controls+1]=slider(left,"Vertical offset",14,-228,260,-24,24,1,function() return get("offsetY") end,function(v) set("offsetY",math.floor(v+.5)) end)

    controls[#controls+1]=slider(right,"Minimum duration shown",14,-45,260,0,60,1,function() return get("minDuration") end,function(v) set("minDuration",math.floor(v+.5)) end)
    controls[#controls+1]=slider(right,"MM:SS ends at (seconds)",14,-105,260,0,600,5,function() return get("abbrevThreshold") end,function(v) set("abbrevThreshold",math.floor(v+.5)) end)
    controls[#controls+1]=slider(right,"Tenths under (seconds)",14,-165,260,0,30,1,function() return get("tenthsThreshold") end,function(v) set("tenthsThreshold",math.floor(v+.5)) end)
    controls[#controls+1]=checkbox(right,"Show zero",14,-238,function() return get("showZero") end,function(v) set("showZero",v) end)

    local d1=stateDropdown(bottom,"Countdown text",14,-46,function() return get("drawText") end,function(v) set("drawText",v) end); controls[#controls+1]=d1
    local d2=stateDropdown(bottom,"Swipe",160,-46,function() return get("drawSwipe") end,function(v) set("drawSwipe",v) end); controls[#controls+1]=d2
    local d3=stateDropdown(bottom,"Edge",306,-46,function() return get("drawEdge") end,function(v) set("drawEdge",v) end); controls[#controls+1]=d3
    local d4=stateDropdown(bottom,"Finish flash",452,-46,function() return get("drawBling") end,function(v) set("drawBling",v) end); controls[#controls+1]=d4

    label(bottom, "Font outline", 14, -198)
    local outlineDD
    local outlineOptions = {{"None", ""}, {"Thin outline", "OUTLINE"}, {"Thick outline", "THICKOUTLINE"}, {"Monochrome outline", "MONOCHROME,OUTLINE"}}
    local function outlineLabel()
        local current = get("fontFlags") or ""
        for _, entry in ipairs(outlineOptions) do if entry[2] == current then return entry[1] end end
        return "Thin outline"
    end
    outlineDD = makeDropdown(bottom, 190, outlineLabel, function(root)
        for _, entry in ipairs(outlineOptions) do
            local name, value = entry[1], entry[2]
            root:CreateRadio(name, function() return (get("fontFlags") or "") == value end,
                function()
                    set("fontFlags", value)
                    -- Repaint the selected surface immediately, including existing timers.
                    forceFeatureRefresh(UI.selectedStyle)
                    outlineDD:RefreshLabel()
                end)
        end
    end)
    outlineDD:SetPoint("TOPLEFT", 14, -217); controls[#controls+1] = outlineDD

    local colorLabels = {"0–5 sec","5–60 sec","60 sec–1 hr","Long duration"}
    local colorX = {14,146,278,410}
    for i=1,4 do
        local b=colorButton(bottom,colorLabels[i],colorX[i],-128,
            function()
                local s=UI:GetStyle(UI.selectedStyle); local rows=s and s.textColors
                if rows and rows[i] then return rows[i].color end
                return s and s.defaultTextColor or "FFFFFFFF"
            end,
            function(hex)
                local s=UI:GetStyle(UI.selectedStyle); if not s then return end
                s.textColors=s.textColors or {}
                if not s.textColors[i] then
                    local thresholds={5,60,3600,315360000}
                    s.textColors[i]={threshold=thresholds[i],color=hex}
                else s.textColors[i].color=hex end
                forceFeatureRefresh(UI.selectedStyle)
            end)
        controls[#controls+1]=b
    end

    local defaultColor=colorButton(bottom,"Fallback",542,-128,function() return get("defaultTextColor") end,function(v) set("defaultTextColor",v) end)
    controls[#controls+1]=defaultColor

    local function refresh()
        UI._styleRefreshing=true
        for id,b in pairs(tabButtons) do b:SetEnabled(id ~= UI.selectedStyle) end
        for i=1,#controls do
            local c=controls[i]
            if c.Refresh then c:Refresh() elseif c.RefreshLabel then c:RefreshLabel() end
        end
        UI._styleRefreshing=false
    end
    UI._refreshStyleStudio=refresh
    refresh()
end

function UI:BuildRulesPanel(container)
    local title = container:CreateFontString(nil,"OVERLAY","GameFontNormalHuge")
    title:SetPoint("TOPLEFT",16,-14); title:SetText("Cooldown Routing")
    local note = container:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    note:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-4); note:SetText("Choose which surface style handles each cooldown family.")

    local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",16,-62); scroll:SetPoint("BOTTOMRIGHT",-30,16)
    local child=CreateFrame("Frame",nil,scroll); child:SetSize(650,900); scroll:SetScrollChild(child)

    local rows={}
    local function populate()
        for i=1,#rows do rows[i]:Hide() end
        local y=-4; local idx=0
        for _, rule in Core:IterateRules() do
            if rule.id ~= "everything" or true then
                idx=idx+1
                local row=rows[idx]
                if not row then
                    row=CreateFrame("Frame",nil,child,"BackdropTemplate"); row:SetSize(620,34)
                    row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); row:SetBackdropColor(0.05,0.07,0.09,0.55)
                    row.cb=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate"); row.cb:SetPoint("LEFT",6,0)
                    row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlight"); row.name:SetPoint("LEFT",row.cb,"RIGHT",4,0); row.name:SetWidth(270); row.name:SetJustifyH("LEFT")
                    rows[idx]=row
                end
                row:Show(); row:SetPoint("TOPLEFT",0,y); y=y-38
                local settings=Core.db.profile.rules[rule.id]
                if type(settings)~="table" then settings={enabled=rule.enabled~=false,theme=(rule.id:find("nameplate") and "nameplates" or "default")}; Core.db.profile.rules[rule.id]=settings end
                row.name:SetText(rule.displayName or rule.id)
                row.cb:SetChecked(Core:IsRuleEnabled(rule))
                row.cb:SetScript("OnClick",function(self) settings.enabled=self:GetChecked(); Core:Refresh() end)
                if row.dd then row.dd:Hide() end
                local dd
                dd=makeDropdown(row,180,function() return UI:GetStyleName(settings.theme or "default") end,function(root)
                    for _,id in ipairs(STYLE_ORDER) do
                        root:CreateRadio(UI:GetStyleName(id),function() return settings.theme==id end,function() settings.theme=id; Core:Refresh(); dd:RefreshLabel() end)
                    end
                    root:CreateRadio("Disabled style",function() return settings.theme=="none" end,function() settings.theme="none"; Core:Refresh(); dd:RefreshLabel() end)
                end)
                dd:SetPoint("RIGHT",-8,0); row.dd=dd
            end
        end
        child:SetHeight(math.max(300,-y+20))
    end
    UI._refreshRulesPanel=populate
    populate()
end
