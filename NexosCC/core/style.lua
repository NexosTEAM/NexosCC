local _, Addon = ...

local function tri(value)
    if value == "always" then return true end
    if value == "never" then return false end
end

local function safeText(cooldown)
    if not cooldown or not cooldown.GetCountdownFontString then return nil end
    local ok, text = pcall(cooldown.GetCountdownFontString, cooldown)
    if not ok or not text then return nil end
    if text.IsForbidden and text:IsForbidden() then return nil end
    return text
end

local function effectiveFontSize(cooldown, style)
    local size = tonumber(style.fontSize) or 0
    if size <= 0 then return 0 end
    if style.autoFitText and cooldown and cooldown.GetWidth and cooldown.GetHeight then
        local okW, w = pcall(cooldown.GetWidth, cooldown)
        local okH, h = pcall(cooldown.GetHeight, cooldown)
        if okW and okH and type(w) == "number" and type(h) == "number" and w > 1 and h > 1 then
            local cap = math.max(5, math.floor(math.min(w, h) * 0.37 + 0.5))
            size = math.min(size, cap)
        end
    end
    return size
end

function Addon:CreateThemer(style)
    if type(style) ~= "table" or style.enabled == false then return function() end end
    local formatter = self:CreateCountdownTextFormatter(style)
    local drawText = tri(style.drawText)
    local drawBling = tri(style.drawBling)
    local drawEdge = tri(style.drawEdge)
    local drawSwipe = tri(style.drawSwipe)
    local reverse = tri(style.reverse)
    local fontPath = self:ResolveFont(style.font)
    local flags = style.fontFlags
    local shadow = self.CreateColor(style.shadowColor)
    local swipe = self.CreateColor(style.swipeColor)

    return function(cooldown)
        if not cooldown then return end
        if drawText ~= nil and cooldown.SetHideCountdownNumbers then pcall(cooldown.SetHideCountdownNumbers, cooldown, not drawText) end

        local text = safeText(cooldown)
        if style.themeText ~= false and text then
            local size = effectiveFontSize(cooldown, style)
            if size > 0 and text.SetFont then
                local ok = pcall(text.SetFont, text, fontPath, size, flags)
                if not ok then pcall(text.SetFont, text, STANDARD_TEXT_FONT, size, flags) end
            elseif cooldown.SetCountdownFont then
                pcall(cooldown.SetCountdownFont, cooldown, fontPath)
            end
            if style.point and text.ClearAllPoints and text.SetPoint then
                pcall(text.ClearAllPoints, text)
                pcall(text.SetPoint, text, style.point, cooldown, style.point, tonumber(style.offsetX) or 0, tonumber(style.offsetY) or 0)
            end
            if shadow and text.SetShadowColor then pcall(text.SetShadowColor, text, shadow:GetRGBA()) end
            if text.SetShadowOffset then pcall(text.SetShadowOffset, text, tonumber(style.shadowX) or 0, tonumber(style.shadowY) or 0) end
            if formatter and cooldown.SetCountdownFormatter then pcall(cooldown.SetCountdownFormatter, cooldown, formatter) end
            if style.scaleText == true and cooldown.GetWidth and text.SetScale then
                local ok, w = pcall(cooldown.GetWidth, cooldown)
                if ok and type(w) == "number" and w > 0 then
                    local scale = w / 36
                    if scale < (tonumber(style.minScale) or 0) then scale = 0 end
                    pcall(text.SetScale, text, scale)
                end
            elseif text.SetScale then
                pcall(text.SetScale, text, 1)
            end
        end

        if style.themeCooldown ~= false then
            if drawBling ~= nil and cooldown.SetDrawBling then pcall(cooldown.SetDrawBling, cooldown, drawBling) end
            if drawEdge ~= nil and cooldown.SetDrawEdge then pcall(cooldown.SetDrawEdge, cooldown, drawEdge) end
            if drawSwipe ~= nil and cooldown.SetDrawSwipe then pcall(cooldown.SetDrawSwipe, cooldown, drawSwipe) end
            if reverse ~= nil and cooldown.SetReverse then pcall(cooldown.SetReverse, cooldown, reverse) end
            if style.themeSwipeColor and swipe and cooldown.SetSwipeColor then pcall(cooldown.SetSwipeColor, cooldown, swipe:GetRGBA()) end
        end
    end
end

function Addon:ApplyTheme(cooldown, themeID)
    local profile = self.db and self.db.profile
    local themes = profile and profile.themes
    local style = themes and themes[themeID or "default"]
    if not style then return end
    return self:CreateThemer(style)(cooldown)
end

Addon.ApplyStyle = Addon.ApplyTheme

function Addon:FitAutoText(fontString, icon, style)
    if not fontString or not fontString.SetFont or type(style) ~= "table" then return end
    local path, _, oldFlags = fontString:GetFont()
    path = self:ResolveFont(style.font) or path or STANDARD_TEXT_FONT
    local flags = style.fontFlags
    if flags == nil then flags = oldFlags end
    local target = tonumber(style.fontSize) or 13
    if icon and icon.GetWidth and icon.GetHeight then
        local okW,w = pcall(icon.GetWidth,icon); local okH,h = pcall(icon.GetHeight,icon)
        if okW and okH and type(w)=="number" and type(h)=="number" and w>1 and h>1 then
            target = math.min(target, math.max(5, math.floor(math.min(w,h)*0.37+0.5)))
        end
    end
    pcall(fontString.SetFont,fontString,path,target,flags)
end
