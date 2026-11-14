local _, Addon = ...

local SECOND, MINUTE, HOUR, DAY, WEEK = 1, 60, 3600, 86400, 604800

local function enumRounding(name)
    local e = Enum and Enum.NumericRuleFormatRounding
    if not e then return nil end
    return e[name or "Nearest"] or e.Nearest
end

local function colorAt(style, seconds)
    local list = type(style.textColors) == "table" and style.textColors or nil
    if list then
        local sorted = {}
        for i = 1, #list do
            local row = list[i]
            local threshold = type(row) == "table" and tonumber(row.threshold)
            if threshold then sorted[#sorted + 1] = { threshold = threshold, color = row.color } end
        end
        table.sort(sorted, function(a, b) return a.threshold < b.threshold end)
        for i = 1, #sorted do
            if seconds < sorted[i].threshold then return sorted[i].color end
        end
    end
    return style.defaultTextColor or "FFFFFFFF"
end

local function formatAt(style, seconds, rounding)
    local minDuration = tonumber(style.minDuration) or 0
    -- Showing the terminal zero takes priority over the minimum-duration gate.
    -- Otherwise the default 2-second gate hides the entire final countdown.
    if seconds < minDuration and not (style.showZero == true and seconds >= 0 and seconds < 1) then
        return { format = "", step = 1, rounding = rounding }
    end

    local tenths = tonumber(style.tenthsThreshold) or 0
    if tenths > 0 and seconds < tenths then
        return { format = "%.1f", step = 0.1, rounding = rounding }
    end

    if seconds < MINUTE then
        if style.showZero ~= true then
            local name = style.roundingMode or "Nearest"
            local gate = (name == "Down") and 1 or ((name == "Nearest") and 0.5 or 0)
            if seconds < gate then return { format = "", step = 1, rounding = rounding } end
        end
        return { format = "%d", step = 1, rounding = rounding }
    end

    local h = tonumber(style.hoursThreshold) or HOUR
    local d = tonumber(style.daysThreshold) or DAY
    local w = tonumber(style.weeksThreshold) or WEEK
    if w > 0 and seconds >= w then
        return { format = "%dw", components = { { div = WEEK, rounding = rounding, step = 1 } } }
    elseif d > 0 and seconds >= d then
        return { format = "%dd", components = { { div = DAY, rounding = rounding, step = 1 } } }
    elseif h > 0 and seconds >= h then
        return { format = "%dh", components = { { div = HOUR, rounding = rounding, step = 1 } } }
    end

    local mmssEnd = tonumber(style.abbrevThreshold) or 0
    if mmssEnd >= MINUTE and seconds < mmssEnd then
        return {
            format = "%d:%02d",
            step = 1,
            rounding = rounding,
            components = { { div = MINUTE }, { mod = MINUTE } },
        }
    end

    return { format = "%dm", components = { { div = MINUTE, rounding = rounding, step = 1 } } }
end

local function coloredFormat(style, seconds, pattern)
    local c = Addon.CreateColor(colorAt(style, seconds))
    if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(pattern) end
    return pattern
end

local function thresholds(style)
    local set = { [0] = true, [60] = true }
    local keys = { "minDuration", "tenthsThreshold", "abbrevThreshold", "hoursThreshold", "daysThreshold", "weeksThreshold" }
    for i = 1, #keys do
        local n = tonumber(style[keys[i]])
        if n and n >= 0 then set[n] = true end
    end
    if style.showZero ~= true then
        if style.roundingMode == "Down" then set[1] = true
        elseif style.roundingMode ~= "Up" then set[0.5] = true end
    end
    local colors = style.textColors
    if type(colors) == "table" then
        for i = 1, #colors do
            local n = tonumber(colors[i] and colors[i].threshold)
            if n and n >= 0 then set[n] = true end
        end
    end
    local out = {}
    for n in pairs(set) do out[#out + 1] = n end
    table.sort(out)
    return out
end

function Addon:CreateCountdownTextFormatter(style)
    if type(style) ~= "table" or not C_StringUtil or not C_StringUtil.CreateNumericRuleFormatter then return nil end
    local ok, formatter = pcall(C_StringUtil.CreateNumericRuleFormatter)
    if not ok or not formatter then return nil end

    local rounding = enumRounding(style.roundingMode)
    local points = {}
    local marks = thresholds(style)
    local lastSignature
    for i = 1, #marks do
        local at = marks[i]
        local rule = formatAt(style, at, rounding)
        rule.threshold = at
        rule.format = coloredFormat(style, at, rule.format or "")
        local sig = table.concat({ rule.format or "", tostring(rule.step), tostring(rule.rounding), tostring(rule.components and #rule.components or 0) }, "|")
        if sig ~= lastSignature or i == 1 then
            points[#points + 1] = rule
            lastSignature = sig
        end
    end

    if formatter.SetBreakpoints then
        local setOK = pcall(formatter.SetBreakpoints, formatter, points)
        if setOK then return formatter end
    end
    if formatter.AddBreakpoint then
        for i = 1, #points do
            if not pcall(formatter.AddBreakpoint, formatter, points[i]) then return nil end
        end
        return formatter
    end
    return nil
end

Addon.CreateCountdownFormatter = Addon.CreateCountdownTextFormatter
