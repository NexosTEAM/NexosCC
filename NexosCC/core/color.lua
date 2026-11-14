local _, Addon = ...

local cache = setmetatable({}, { __mode = "v" })

local function normalize(hex)
    if type(hex) ~= "string" then return nil end
    hex = hex:gsub("#", "")
    if #hex == 6 then hex = hex .. "FF" end
    if #hex ~= 8 or not hex:match("^[0-9A-Fa-f]+$") then return nil end
    return hex:upper()
end

function Addon.CreateColor(hex)
    hex = normalize(hex)
    if not hex then return nil end
    local existing = cache[hex]
    if existing then return existing end
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    local a = tonumber(hex:sub(7, 8), 16) / 255
    local c = CreateColor and CreateColor(r, g, b, a)
    if c then cache[hex] = c end
    return c
end

function Addon.HexToRGBA(hex)
    local c = Addon.CreateColor(hex)
    if c then return c:GetRGBA() end
    return 1, 1, 1, 1
end

function Addon.RGBAToHex(r, g, b, a)
    local function byte(v)
        v = tonumber(v) or 0
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        return math.floor(v * 255 + 0.5)
    end
    return ("%02X%02X%02X%02X"):format(byte(r), byte(g), byte(b), byte(a == nil and 1 or a))
end

local FONT_MAP = {
    ["Friz Quadrata TT"] = STANDARD_TEXT_FONT,
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
    ["Skurri"] = "Fonts\\SKURRI.TTF",
    ["2002"] = "Fonts\\2002.TTF",
    ["2002 Bold"] = "Fonts\\2002B.TTF",
    ["Combat Text"] = (DAMAGE_TEXT_FONT or "Fonts\\FRIZQT__.TTF"),
    ["Quest Text"] = (QuestFont and select(1, QuestFont:GetFont()) or "Fonts\\MORPHEUS.TTF"),
    ["Friends Text"] = (FriendsFont_Normal and select(1, FriendsFont_Normal:GetFont()) or "Fonts\\ARIALN.TTF"),
    ["System Text"] = (SystemFont_Med1 and select(1, SystemFont_Med1:GetFont()) or "Fonts\\FRIZQT__.TTF"),
    ["Chat Text"] = (ChatFontNormal and select(1, ChatFontNormal:GetFont()) or "Fonts\\ARIALN.TTF"),
}

function Addon:ResolveFont(value)
    if type(value) == "string" and value:find("\\") then return value end
    return FONT_MAP[value] or STANDARD_TEXT_FONT
end
