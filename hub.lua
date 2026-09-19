--[[
    ============================================================
    RBLX SCRPT HUB  --  v1.0
    ============================================================
    Universal Roblox script hub GUI powered by the public
    ScriptBlox API.

        API docs : https://docs.scriptblox.com
        Website  : https://scriptblox.com
        Repo     : https://github.com/TheStrongestOfTomorrow/Rblx-SCRPT-HUB

    FEATURES
      - Search / Trending / Latest tabs (live ScriptBlox results)
      - Search filters: sort (updated / views / likes), keyless,
        hide-patched  (uses the official API query parameters)
      - One-tap EXECUTE (loadstring), copy full source, copy key link
      - Detail view with features + owner (fetched per script)
      - VERIFIED / KEY / PAID / UNIVERSAL / PATCHED badges
      - Pagination (Page x / y) for search + latest
      - PC    : RightShift toggles the panel
      - Mobile: draggable floating HUB icon, tap to open/close
      - X button (top-right) closes the panel
      - Panel + icon are fully draggable, fit-to-screen on phones

    ENDPOINTS USED (per docs.scriptblox.com)
      GET /api/script/search?q=&page=&max=&sortBy=&key=&patched=
      GET /api/script/trending
      GET /api/script/fetch?page=&max=
      GET /api/script/raw/:slug     (plain-text source fallback)
      GET /api/script/:slug         (details: features / owner)

    THIS FILE IS 100% CLIENT-SIDE.
      - No remotes, no uploads, no proxies.
      - Scripts are fetched from ScriptBlox and executed locally
        with loadstring. You are responsible for what you run.
    ============================================================
]]

print("[RBLX SCRPT HUB v1.0] loading...")

-- =========================================================
-- SECTION 1: SERVICES & CONFIG
-- =========================================================

local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

local CONFIG = {
    Version       = "1.0",
    ApiBase       = "https://scriptblox.com/api",
    MaxResults    = 10,          -- per page for search / latest (API caps at 20)
    ToggleKey     = Enum.KeyCode.RightShift,
    PanelSize     = Vector2.new(560, 380),
    IconSize      = 52,
    DragThreshold = 6,           -- px of movement before a tap counts as a drag
    PreviewChars  = 4000,        -- source preview cap in the detail view
    FeatureChars  = 240,         -- features line cap in the detail view
}

local THEME = {
    Background = Color3.fromRGB(15, 15, 20),
    Panel      = Color3.fromRGB(24, 24, 32),
    Card       = Color3.fromRGB(32, 32, 44),
    CardHover  = Color3.fromRGB(42, 42, 58),
    Accent     = Color3.fromRGB(0, 170, 255),
    AccentDark = Color3.fromRGB(0, 115, 185),
    Text       = Color3.fromRGB(240, 240, 245),
    SubText    = Color3.fromRGB(150, 150, 165),
    Stroke     = Color3.fromRGB(60, 60, 80),
    Danger     = Color3.fromRGB(235, 70, 90),
    DangerHot  = Color3.fromRGB(255, 95, 115),
    Yellow     = Color3.fromRGB(235, 185, 70),
    White      = Color3.fromRGB(255, 255, 255),
}

local SORT_CYCLE = { "updatedAt", "views", "likeCount" }
local SORT_NAMES = { updatedAt = "UPDATED", views = "MOST VIEWED", likeCount = "TOP LIKED" }

-- =========================================================
-- SECTION 2: HELPERS -- HTTP, JSON, SCRIPTBLOX API
-- =========================================================

local function make(className, props, parent)
    local inst = Instance.new(className)
    for key, value in pairs(props) do
        inst[key] = value
    end
    inst.Parent = parent
    return inst
end

local function addCorner(parent, radius)
    return make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function addStroke(parent, color, thickness, transparency)
    return make("UIStroke", {
        Color           = color or THEME.Stroke,
        Thickness       = thickness or 1,
        Transparency    = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function formatCount(n)
    n = tonumber(n) or 0
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(n)
end

local function urlEncode(text)
    return tostring(text):gsub("[^%w%-_%.~]", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end)
end

local function truthy(v)
    return v == true or v == 1 or v == "true"
end

local function httpGet(url)
    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(res) == "string" and #res > 0 then
        return res
    end

    -- Fallback: request APIs exposed by most executors
    local reqFn
    if type(syn) == "table" and type(syn.request) == "function" then
        reqFn = syn.request
    elseif type(http_request) == "function" then
        reqFn = http_request
    elseif type(request) == "function" then
        reqFn = request
    end

    if reqFn then
        local ok2, res2 = pcall(function()
            local response = reqFn({
                Url     = url,
                Method  = "GET",
                Headers = { ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" },
            })
            if type(response) == "table" then
                return response.Body or response.body
            end
            return response
        end)
        if ok2 and type(res2) == "string" and #res2 > 0 then
            return res2
        end
    end

    error("HTTP GET failed: " .. url)
end

local function decodeJson(text)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(text)
    end)
    if not ok or type(data) ~= "table" then
        error("bad JSON from API")
    end
    return data
end

local ScriptBlox = {}

local function apiGet(path)
    local body = httpGet(CONFIG.ApiBase .. path)
    local data = decodeJson(body)
    if type(data.result) ~= "table" then
        error("unexpected API response shape")
    end
    return data.result
end

-- GET /script/search?q={q}&page=&max=&sortBy=&key=&patched=&strict=&order=
function ScriptBlox.search(query, page, filters)
    local url = "/script/search?q=" .. urlEncode(query)
        .. "&max=" .. tostring(CONFIG.MaxResults)
        .. "&page=" .. tostring(page)
        .. "&strict=false&order=desc"
    if type(filters) == "table" then
        url = url .. "&sortBy=" .. tostring(filters.sort or "updatedAt")
        if filters.keyless then
            url = url .. "&key=0"
        end
        if filters.noPatched then
            url = url .. "&patched=0"
        end
    end
    return apiGet(url)
end

-- GET /script/trending   (no parameters, no pagination)
function ScriptBlox.trending()
    return apiGet("/script/trending")
end

-- GET /script/fetch?page=&max=   (latest uploads)
function ScriptBlox.latest(page)
    return apiGet("/script/fetch?page=" .. tostring(page)
        .. "&max=" .. tostring(CONFIG.MaxResults))
end

-- GET /script/raw/:slug   (plain-text source, used when a list omits it)
function ScriptBlox.rawSource(slug)
    return httpGet(CONFIG.ApiBase .. "/script/raw/" .. urlEncode(slug))
end

-- GET /script/:slug   (details: features, owner, ...)
function ScriptBlox.details(slug)
    local data = decodeJson(httpGet(CONFIG.ApiBase .. "/script/" .. urlEncode(slug)))
    if type(data) == "table" and type(data.script) == "table" then
        return data.script
    end
    return nil
end

local function gameName(raw)
    local g = raw.game
    if type(g) == "table" then
        return tostring(g.name or "Unknown game")
    elseif type(g) == "string" then
        return g
    end
    return "Unknown game"
end

local function normalizeScript(raw)
    local universal = truthy(raw.isUniversal)
    return {
        Title     = tostring(raw.title or "Untitled"),
        Game      = universal and "Universal" or gameName(raw),
        Slug      = tostring(raw.slug or ""),
        Source    = tostring(raw.script or ""),
        Key       = truthy(raw.key),
        Keyless   = truthy(raw.keyless),
        KeyLink   = tostring(raw.keyLink or ""),
        Paid      = (raw.scriptType == "paid"),
        Verified  = truthy(raw.verified),
        Universal = universal,
        Patched   = truthy(raw.isPatched),
        Views     = tonumber(raw.views) or 0,
        Likes     = tonumber(raw.likeCount) or 0,
    }
end

local function badgesText(s)
    local parts = {}
    if s.Verified                 then table.insert(parts, "VERIFIED")  end
    if s.Patched                  then table.insert(parts, "PATCHED")   end
    if s.Key and not s.Keyless    then table.insert(parts, "KEY")       end
    if s.Paid                     then table.insert(parts, "PAID")      end
    if s.Universal                then table.insert(parts, "UNIVERSAL") end
    if #parts == 0 then return "" end
    return "[" .. table.concat(parts, "] [") .. "]"
end

-- =========================================================
-- SECTION 3: GUI CONSTRUCTION
-- =========================================================

local function destroyOld()
    pcall(function()
        local old = CoreGui:FindFirstChild("RblxScrptHub")
        if old then old:Destroy() end
    end)
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            local old = playerGui:FindFirstChild("RblxScrptHub")
            if old then old:Destroy() end
        end
    end)
end
destroyOld()

local camera = workspace.CurrentCamera

local gui = Instance.new("ScreenGui")
gui.Name           = "RblxScrptHub"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 9999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if type(syn) == "table" and type(syn.protect_gui) == "function" then
        syn.protect_gui(gui)
    end
end)

local parentedToCore = pcall(function()
    gui.Parent = CoreGui
end)
if not parentedToCore then
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

-- floating HUB icon (always visible, draggable, tap = toggle panel)
local iconSize = CONFIG.IconSize
local floatingIcon = make("TextButton", {
    Name             = "HubIcon",
    Size             = UDim2.fromOffset(iconSize, iconSize),
    Position         = UDim2.new(1, -(iconSize + 20), 0.5, -(iconSize / 2)),
    BackgroundColor3 = THEME.Accent,
    Text             = "HUB",
    Font             = Enum.Font.GothamBlack,
    TextSize         = 14,
    TextColor3       = THEME.White,
    AutoButtonColor  = false,
    BorderSizePixel  = 0,
    ZIndex           = 50,
}, gui)
addCorner(floatingIcon, iconSize / 2)
addStroke(floatingIcon, THEME.AccentDark, 2, 0.3)

local function clampIcon()
    if not camera then return end
    local vp  = camera.ViewportSize
    local abs = floatingIcon.AbsolutePosition
    local x   = math.clamp(abs.X, 8, math.max(8, vp.X - iconSize - 8))
    local y   = math.clamp(abs.Y, 8, math.max(8, vp.Y - iconSize - 8))
    floatingIcon.Position = UDim2.fromOffset(x, y)
end

-- main panel
local panel = make("Frame", {
    Name             = "MainPanel",
    Size             = UDim2.fromOffset(CONFIG.PanelSize.X, CONFIG.PanelSize.Y),
    Position         = UDim2.new(0.5, 0, 0.5, 0),
    AnchorPoint      = Vector2.new(0.5, 0.5),
    BackgroundColor3 = THEME.Panel,
    BorderSizePixel  = 0,
    Visible          = false,
}, gui)
addCorner(panel, 12)
addStroke(panel, THEME.Stroke, 1, 0.2)

-- top bar (drag handle) + title + X close button
local topBar = make("Frame", {
    Size             = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = THEME.Background,
    BorderSizePixel  = 0,
}, panel)
addCorner(topBar, 12)

make("TextLabel", {
    Name                   = "Title",
    BackgroundTransparency = 1,
    Position               = UDim2.fromOffset(12, 0),
    Size                   = UDim2.new(1, -70, 1, 0),
    Font                   = Enum.Font.GothamBold,
    Text                   = "RBLX SCRPT HUB  |  v" .. CONFIG.Version,
    TextSize               = 14,
    TextColor3             = THEME.Text,
    TextXAlignment         = Enum.TextXAlignment.Left,
}, topBar)

local closeBtn = make("TextButton", {
    Size             = UDim2.fromOffset(30, 26),
    Position         = UDim2.new(1, -38, 0, 6),
    BackgroundColor3 = THEME.Danger,
    Text             = "X",
    Font             = Enum.Font.GothamBold,
    TextSize         = 13,
    TextColor3       = THEME.White,
    AutoButtonColor  = false,
    BorderSizePixel  = 0,
}, topBar)
addCorner(closeBtn, 6)

-- tab bar
local tabBar = make("Frame", {
    Size                   = UDim2.new(1, 0, 0, 34),
    Position               = UDim2.fromOffset(0, 38),
    BackgroundTransparency = 1,
}, panel)
make("UIListLayout", {
    FillDirection     = Enum.FillDirection.Horizontal,
    Padding           = UDim.new(0, 6),
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder         = Enum.SortOrder.LayoutOrder,
}, tabBar)
make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, tabBar)

local tabButtons = {}
local function makeTab(name, order)
    local btn = make("TextButton", {
        Size             = UDim2.fromOffset(86, 24),
        BackgroundColor3 = THEME.Card,
        Text             = string.upper(name),
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        TextColor3       = THEME.SubText,
        AutoButtonColor  = false,
        BorderSizePixel  = 0,
        LayoutOrder      = order,
    }, tabBar)
    addCorner(btn, 6)
    tabButtons[name] = btn
    return btn
end
makeTab("search", 1)
makeTab("trending", 2)
makeTab("latest", 3)

local function setTabHighlight(mode)
    for name, btn in pairs(tabButtons) do
        local active = (name == mode)
        btn.BackgroundColor3 = active and THEME.Accent or THEME.Card
        btn.TextColor3       = active and THEME.White or THEME.SubText
    end
end

-- search row
local searchRow = make("Frame", {
    Size                   = UDim2.new(1, 0, 0, 34),
    Position               = UDim2.fromOffset(0, 72),
    BackgroundTransparency = 1,
}, panel)

local searchBox = make("TextBox", {
    Position          = UDim2.fromOffset(10, 4),
    Size              = UDim2.new(1, -96, 0, 26),
    BackgroundColor3  = THEME.Background,
    Text              = "",
    PlaceholderText   = "Search games / scripts...",
    PlaceholderColor3 = THEME.SubText,
    Font              = Enum.Font.Gotham,
    TextSize          = 12,
    TextColor3        = THEME.Text,
    ClearTextOnFocus  = false,
    TextXAlignment    = Enum.TextXAlignment.Left,
    BorderSizePixel   = 0,
}, searchRow)
addCorner(searchBox, 6)
addStroke(searchBox, THEME.Stroke, 1, 0.4)

local searchBtn = make("TextButton", {
    Position         = UDim2.new(1, -86, 0, 4),
    Size             = UDim2.fromOffset(76, 26),
    BackgroundColor3 = THEME.Accent,
    Text             = "SEARCH",
    Font             = Enum.Font.GothamBold,
    TextSize         = 11,
    TextColor3       = THEME.White,
    AutoButtonColor  = false,
    BorderSizePixel  = 0,
}, searchRow)
addCorner(searchBtn, 6)

-- filter chips row (search mode)
local filterRow = make("Frame", {
    Size                   = UDim2.new(1, 0, 0, 26),
    Position               = UDim2.fromOffset(0, 106),
    BackgroundTransparency = 1,
}, panel)
make("UIListLayout", {
    FillDirection     = Enum.FillDirection.Horizontal,
    Padding           = UDim.new(0, 6),
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder         = Enum.SortOrder.LayoutOrder,
}, filterRow)
make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, filterRow)

local function makeChip(text, order)
    local chip = make("TextButton", {
        Size             = UDim2.new(1 / 3, -6, 0, 22),
        BackgroundColor3 = THEME.Card,
        Text             = text,
        Font             = Enum.Font.GothamBold,
        TextSize         = 10,
        TextColor3       = THEME.SubText,
        AutoButtonColor  = false,
        BorderSizePixel  = 0,
        TextTruncate     = Enum.TextTruncate.AtEnd,
        LayoutOrder      = order,
    }, filterRow)
    addCorner(chip, 5)
    return chip
end

local chipSort    = makeChip("SORT: UPDATED", 1)
local chipKeyless = makeChip("KEYLESS: OFF", 2)
local chipPatched = makeChip("HIDE PATCHED: ON", 3)

-- results list
local listScroll = make("ScrollingFrame", {
    Position               = UDim2.fromOffset(8, 136),
    Size                   = UDim2.new(1, -16, 1, -196),
    BackgroundTransparency = 1,
    BorderSizePixel        = 0,
    ScrollBarThickness     = 4,
    ScrollBarImageColor3   = THEME.Accent,
    CanvasSize             = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize    = Enum.AutomaticSize.Y,
    ScrollingDirection     = Enum.ScrollingDirection.Y,
}, panel)
make("UIListLayout", {
    Padding   = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, listScroll)

-- pager row
local pagerRow = make("Frame", {
    Size                   = UDim2.new(1, 0, 0, 28),
    Position               = UDim2.new(0, 0, 1, -56),
    BackgroundTransparency = 1,
}, panel)

local prevBtn = make("TextButton", {
    Position         = UDim2.fromOffset(10, 2),
    Size             = UDim2.fromOffset(78, 24),
    BackgroundColor3 = THEME.Card,
    Text             = "< PREV",
    Font             = Enum.Font.GothamBold,
    TextSize         = 11,
    TextColor3       = THEME.Text,
    AutoButtonColor  = false,
    BorderSizePixel  = 0,
}, pagerRow)
addCorner(prevBtn, 6)

local pageLabel = make("TextLabel", {
    Position               = UDim2.new(0.5, -70, 0, 2),
    Size                   = UDim2.fromOffset(140, 24),
    BackgroundTransparency = 1,
    Font                   = Enum.Font.GothamBold,
    Text                   = "Page 1 / 1",
    TextSize               = 11,
    TextColor3             = THEME.SubText,
}, pagerRow)

local nextBtn = make("TextButton", {
    Position         = UDim2.new(1, -88, 0, 2),
    Size             = UDim2.fromOffset(78, 24),
    BackgroundColor3 = THEME.Card,
    Text             = "NEXT >",
    Font             = Enum.Font.GothamBold,
    TextSize         = 11,
    TextColor3       = THEME.Text,
    AutoButtonColor  = false,
    BorderSizePixel  = 0,
}, pagerRow)
addCorner(nextBtn, 6)

-- status line
local statusLabel = make("TextLabel", {
    Position               = UDim2.new(0, 12, 1, -24),
    Size                   = UDim2.new(1, -24, 0, 18),
    BackgroundTransparency = 1,
    Font                   = Enum.Font.Gotham,
    Text                   = "Ready.",
    TextSize               = 11,
    TextColor3             = THEME.SubText,
    TextXAlignment         = Enum.TextXAlignment.Left,
    TextTruncate           = Enum.TextTruncate.AtEnd,
}, panel)

-- detail overlay (covers everything below the tab bar)
local detail = make("Frame", {
    Position         = UDim2.fromOffset(8, 72),
    Size             = UDim2.new(1, -16, 1, -100),
    BackgroundColor3 = THEME.Panel,
    BorderSizePixel  = 0,
    Visible          = false,
    ZIndex           = 10,
}, panel)
addCorner(detail, 10)
addStroke(detail, THEME.Stroke, 1, 0.3)

local detailTitle = make("TextLabel", {
    Position               = UDim2.fromOffset(10, 6),
    Size                   = UDim2.new(1, -20, 0, 20),
    BackgroundTransparency = 1,
    Font                   = Enum.Font.GothamBold,
    Text                   = "",
    TextSize               = 14,
    TextColor3             = THEME.Text,
    TextXAlignment         = Enum.TextXAlignment.Left,
    TextTruncate           = Enum.TextTruncate.AtEnd,
    ZIndex                 = 10,
}, detail)

local detailMeta = make("TextLabel", {
    Position               = UDim2.fromOffset(10, 27),
    Size                   = UDim2.new(1, -20, 0, 16),
    BackgroundTransparency = 1,
    Font                   = Enum.Font.Gotham,
    Text                   = "",
    TextSize               = 10,
    TextColor3             = THEME.SubText,
    TextXAlignment         = Enum.TextXAlignment.Left,
    TextTruncate           = Enum.TextTruncate.AtEnd,
    ZIndex                 = 10,
}, detail)

local sourceScroll = make("ScrollingFrame", {
    Position             = UDim2.fromOffset(10, 50),
    Size                 = UDim2.new(1, -20, 1, -96),
    BackgroundColor3     = THEME.Background,
    BackgroundTransparency = 0.2,
    BorderSizePixel      = 0,
    ScrollBarThickness   = 4,
    ScrollBarImageColor3 = THEME.Accent,
    CanvasSize           = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize  = Enum.AutomaticSize.Y,
    ScrollingDirection   = Enum.ScrollingDirection.Y,
    ZIndex               = 10,
}, detail)
addCorner(sourceScroll, 6)

local sourceLabel = make("TextLabel", {
    Size                   = UDim2.new(1, -12, 0, 0),
    AutomaticSize          = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Font                   = Enum.Font.Code,
    Text                   = "",
    RichText               = false,
    TextWrapped            = true,
    TextSize               = 11,
    TextColor3             = THEME.Text,
    TextXAlignment         = Enum.TextXAlignment.Left,
    TextYAlignment         = Enum.TextYAlignment.Top,
    ZIndex                 = 10,
}, sourceScroll)
make("UIPadding", {
    PaddingLeft   = UDim.new(0, 6),
    PaddingRight  = UDim.new(0, 6),
    PaddingTop    = UDim.new(0, 6),
    PaddingBottom = UDim.new(0, 6),
}, sourceLabel)

local detailBtnRow = make("Frame", {
    Position               = UDim2.new(0, 10, 1, -40),
    Size                   = UDim2.new(1, -20, 0, 32),
    BackgroundTransparency = 1,
    ZIndex                 = 10,
}, detail)
make("UIListLayout", {
    FillDirection     = Enum.FillDirection.Horizontal,
    Padding           = UDim.new(0, 6),
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder         = Enum.SortOrder.LayoutOrder,
}, detailBtnRow)

local function makeDetailBtn(text, color, textColor, order)
    local btn = make("TextButton", {
        Size             = UDim2.new(0.25, -5, 1, 0),
        BackgroundColor3 = color,
        Text             = text,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        TextColor3       = textColor,
        AutoButtonColor  = false,
        BorderSizePixel  = 0,
        LayoutOrder      = order,
        ZIndex           = 10,
    }, detailBtnRow)
    addCorner(btn, 6)
    return btn
end

local executeBtn = makeDetailBtn("EXECUTE", THEME.Accent, THEME.White, 1)
local copyBtn    = makeDetailBtn("COPY SRC", THEME.Card, THEME.Text, 2)
local keyBtn     = makeDetailBtn("KEY LINK", THEME.Yellow, Color3.fromRGB(30, 30, 30), 3)
local backBtn    = makeDetailBtn("BACK", THEME.Card, THEME.Text, 4)

-- =========================================================
-- SECTION 4: BEHAVIOR -- STATUS, SEARCH, RENDER, DETAIL
-- =========================================================

local statusToken = 0
local function setStatus(message, isError)
    statusLabel.Text       = tostring(message)
    statusLabel.TextColor3 = isError and THEME.DangerHot or THEME.SubText
    statusToken = statusToken + 1
    local token = statusToken
    task.delay(6, function()
        if statusToken == token then
            statusLabel.Text       = "Ready."
            statusLabel.TextColor3 = THEME.SubText
        end
    end)
end

local currentScript  = nil
local detailBodyText = nil
local detailFeatures = nil

local execFn = loadstring or load

local function executeSource(source, title)
    if type(source) ~= "string" or source == "" then
        setStatus("Nothing to execute (paid or empty script).", true)
        return
    end
    if type(execFn) ~= "function" then
        setStatus("This executor does not support loadstring.", true)
        return
    end
    local fn, err = execFn(source)
    if type(fn) ~= "function" then
        setStatus("Compile error: " .. tostring(err), true)
        return
    end
    local ok, runErr = pcall(fn)
    if ok then
        setStatus("Executed" .. (title and (": " .. title) or "."))
    else
        setStatus("Runtime error: " .. tostring(runErr), true)
    end
end

local copyFn = setclipboard or toclipboard

local function copyText(text, label)
    if type(copyFn) ~= "function" then
        setStatus("Clipboard is not supported here.", true)
        return
    end
    copyFn(tostring(text))
    setStatus((label or "Copied") .. " -> clipboard")
end

-- Lazy source loader: trending rows have no embedded source,
-- so fall back to GET /script/raw/:slug (cached on the entry).
local function ensureSource(s, done)
    if s.Paid then
        done("", "paid script (source is not public)")
        return
    end
    if s.Source ~= "" then
        done(s.Source, nil)
        return
    end
    if s._sourceTried then
        done("", "no public source")
        return
    end
    s._sourceTried = true
    setStatus("Fetching source...")
    task.spawn(function()
        local ok, body = pcall(function()
            return ScriptBlox.rawSource(s.Slug)
        end)
        if ok and type(body) == "string" and #body > 0 then
            s.Source = body
            done(body, nil)
        else
            done("", tostring(body))
        end
    end)
end

local function executeScript(s)
    ensureSource(s, function(src, err)
        if err then
            setStatus("Could not load source: " .. err, true)
            return
        end
        executeSource(src, s.Title)
    end)
end

local function copyScript(s)
    ensureSource(s, function(src, err)
        if err then
            setStatus("Could not load source: " .. err, true)
            return
        end
        copyText(src, "Source")
    end)
end

local function renderSourceLabel()
    if not detailBodyText then return end
    local parts = {}
    if detailFeatures and detailFeatures ~= "" then
        local f = detailFeatures
        if #f > CONFIG.FeatureChars then
            f = f:sub(1, CONFIG.FeatureChars) .. " ..."
        end
        table.insert(parts, "[FEATURES] " .. f)
        table.insert(parts, string.rep("-", 46))
    end
    table.insert(parts, detailBodyText)
    sourceLabel.Text = table.concat(parts, "\n")
end

local function previewText(source)
    if #source > CONFIG.PreviewChars then
        return source:sub(1, CONFIG.PreviewChars)
            .. "\n\n-- preview truncated -- EXECUTE / COPY use the full source"
    end
    return source
end

local function openDetail(s)
    currentScript  = s
    detailFeatures = nil
    detailTitle.Text = s.Title

    local metaParts = { s.Game }
    local badges = badgesText(s)
    if badges ~= "" then table.insert(metaParts, badges) end
    table.insert(metaParts, formatCount(s.Views) .. " views")
    detailMeta.Text = table.concat(metaParts, "   ")

    if s.Source ~= "" then
        detailBodyText = previewText(s.Source)
    elseif s.Paid then
        detailBodyText = "-- PAID SCRIPT --\n-- The source is not public on ScriptBlox.\n-- Unlock it on scriptblox.com to use it here."
    else
        detailBodyText = "-- loading source..."
        ensureSource(s, function()
            if currentScript == s and s.Source ~= "" then
                detailBodyText = previewText(s.Source)
                renderSourceLabel()
            end
        end)
    end
    renderSourceLabel()

    keyBtn.Visible = (s.Key and s.KeyLink ~= "")

    -- async details enrichment (owner + features)
    if not s._detailsTried and s.Slug ~= "" and not s.Paid then
        s._detailsTried = true
        task.spawn(function()
            local ok, info = pcall(function()
                return ScriptBlox.details(s.Slug)
            end)
            if not ok or type(info) ~= "table" then return end
            local ownerName = ""
            if type(info.owner) == "table" and info.owner.username then
                ownerName = tostring(info.owner.username)
            end
            local features = ""
            if type(info.features) == "string" then
                features = info.features
            end
            if type(info.keyLink) == "string" and info.keyLink ~= "" then
                s.KeyLink = info.keyLink
            end
            if currentScript ~= s then return end
            keyBtn.Visible = (s.Key and s.KeyLink ~= "")
            if ownerName ~= "" or features ~= "" then
                local m = { s.Game }
                if ownerName ~= "" then table.insert(m, "by " .. ownerName) end
                if badges ~= "" then table.insert(m, badges) end
                table.insert(m, formatCount(s.Views) .. " views")
                detailMeta.Text = table.concat(m, "   ")
            end
            detailFeatures = features
            renderSourceLabel()
        end)
    end

    searchRow.Visible  = false
    filterRow.Visible  = false
    listScroll.Visible = false
    pagerRow.Visible   = false
    detail.Visible     = true
    sourceScroll.CanvasPosition = Vector2.new(0, 0)
end

local function closeDetail()
    currentScript  = nil
    detailBodyText = nil
    detail.Visible     = false
    searchRow.Visible  = true
    filterRow.Visible  = true
    listScroll.Visible = true
    pagerRow.Visible   = true
end

local function setPanel(visible)
    if visible then
        closeDetail()
        panel.Visible = true
        clampIcon()
    else
        panel.Visible = false
    end
end

local state = { mode = "search", query = "", page = 1, totalPages = 1 }
state.filters = { keyless = false, noPatched = true, sort = SORT_CYCLE[1] }

local function applyPager()
    pageLabel.Text = "Page " .. tostring(state.page)
        .. " / " .. tostring(math.max(state.totalPages, 1))
end

local function renderResults(rawList)
    for _, child in ipairs(listScroll:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    if type(rawList) ~= "table" or #rawList == 0 then
        setStatus("No scripts found.")
        return
    end

    for index, raw in ipairs(rawList) do
        local s = normalizeScript(raw)

        local metaParts = { s.Game }
        local badges = badgesText(s)
        if badges ~= "" then table.insert(metaParts, badges) end
        table.insert(metaParts, formatCount(s.Views) .. " views")

        local row = make("TextButton", {
            Size             = UDim2.new(1, -6, 0, 54),
            BackgroundColor3 = THEME.Card,
            Text             = "",
            AutoButtonColor  = true,
            BorderSizePixel  = 0,
            LayoutOrder      = index,
        }, listScroll)
        addCorner(row, 8)

        make("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(10, 5),
            Size                   = UDim2.new(1, -76, 0, 20),
            Font                   = Enum.Font.GothamBold,
            Text                   = s.Title,
            TextSize               = 13,
            TextColor3             = THEME.Text,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextTruncate           = Enum.TextTruncate.AtEnd,
        }, row)

        make("TextLabel", {
            BackgroundTransparency = 1,
            Position               = UDim2.fromOffset(10, 29),
            Size                   = UDim2.new(1, -76, 0, 16),
            Font                   = Enum.Font.Gotham,
            Text                   = table.concat(metaParts, "   "),
            TextSize               = 10,
            TextColor3             = THEME.SubText,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextTruncate           = Enum.TextTruncate.AtEnd,
        }, row)

        local quickExec = make("TextButton", {
            Size             = UDim2.fromOffset(54, 24),
            Position         = UDim2.new(1, -62, 0.5, -12),
            BackgroundColor3 = THEME.AccentDark,
            Text             = "EXEC",
            Font             = Enum.Font.GothamBold,
            TextSize         = 10,
            TextColor3       = THEME.White,
            AutoButtonColor  = false,
            BorderSizePixel  = 0,
        }, row)
        addCorner(quickExec, 5)

        quickExec.MouseButton1Click:Connect(function()
            executeScript(s)
        end)
        row.MouseButton1Click:Connect(function()
            openDetail(s)
        end)
    end

    setStatus(#rawList .. " scripts listed.")
end

local loading = false
local function loadCurrent()
    if loading then return end
    loading = true
    setStatus("Loading " .. string.upper(state.mode) .. " ...")
    task.spawn(function()
        local ok, result = pcall(function()
            if state.mode == "search" then
                return ScriptBlox.search(state.query, state.page, state.filters)
            elseif state.mode == "trending" then
                return ScriptBlox.trending()
            else
                return ScriptBlox.latest(state.page)
            end
        end)
        loading = false
        if ok and type(result) == "table" then
            state.totalPages = tonumber(result.totalPages) or 1
            renderResults(result.scripts)
            applyPager()
        else
            setStatus("API error: " .. tostring(result), true)
        end
    end)
end

local function runMode(mode, page)
    if loading then
        setStatus("Still loading the previous request...", true)
        return
    end
    state.mode = mode
    state.page = page or 1
    setTabHighlight(mode)
    closeDetail()
    loadCurrent()
end

local function doSearch()
    local query  = searchBox.Text or ""
    local trimmed = query:gsub("%s", "")
    if #trimmed == 0 then
        setStatus("Type something to search first.", true)
        return
    end
    state.query = query
    runMode("search", 1)
end

-- =========================================================
-- SECTION 5: INPUT -- WIRING, DRAG, TOGGLE, MOBILE ICON
-- =========================================================

closeBtn.MouseButton1Click:Connect(function()
    setPanel(false)
end)
closeBtn.MouseEnter:Connect(function()
    closeBtn.BackgroundColor3 = THEME.DangerHot
end)
closeBtn.MouseLeave:Connect(function()
    closeBtn.BackgroundColor3 = THEME.Danger
end)

tabButtons.search.MouseButton1Click:Connect(function()
    local trimmed = (searchBox.Text or ""):gsub("%s", "")
    if #trimmed == 0 then
        setStatus("Type a search term first.")
        searchBox:CaptureFocus()
    else
        doSearch()
    end
end)
tabButtons.trending.MouseButton1Click:Connect(function()
    runMode("trending", 1)
end)
tabButtons.latest.MouseButton1Click:Connect(function()
    runMode("latest", 1)
end)

searchBtn.MouseButton1Click:Connect(doSearch)
searchBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        doSearch()
    end
end)

prevBtn.MouseButton1Click:Connect(function()
    if state.page > 1 then
        runMode(state.mode, state.page - 1)
    else
        setStatus("Already on the first page.")
    end
end)
nextBtn.MouseButton1Click:Connect(function()
    if state.page < state.totalPages then
        runMode(state.mode, state.page + 1)
    else
        setStatus("No more pages.")
    end
end)

chipSort.MouseButton1Click:Connect(function()
    local nextIndex = 1
    for i, name in ipairs(SORT_CYCLE) do
        if name == state.filters.sort then
            nextIndex = (i % #SORT_CYCLE) + 1
            break
        end
    end
    state.filters.sort = SORT_CYCLE[nextIndex]
    chipSort.Text = "SORT: " .. (SORT_NAMES[state.filters.sort] or string.upper(state.filters.sort))
    if state.mode == "search" and state.query ~= "" then
        runMode("search", 1)
    end
end)
chipKeyless.MouseButton1Click:Connect(function()
    state.filters.keyless = not state.filters.keyless
    chipKeyless.Text = "KEYLESS: " .. (state.filters.keyless and "ON" or "OFF")
    if state.mode == "search" and state.query ~= "" then
        runMode("search", 1)
    end
end)
chipPatched.MouseButton1Click:Connect(function()
    state.filters.noPatched = not state.filters.noPatched
    chipPatched.Text = "HIDE PATCHED: " .. (state.filters.noPatched and "ON" or "OFF")
    if state.mode == "search" and state.query ~= "" then
        runMode("search", 1)
    end
end)

executeBtn.MouseButton1Click:Connect(function()
    if currentScript then
        executeScript(currentScript)
    end
end)
copyBtn.MouseButton1Click:Connect(function()
    if currentScript then
        copyScript(currentScript)
    end
end)
keyBtn.MouseButton1Click:Connect(function()
    if currentScript and currentScript.KeyLink ~= "" then
        copyText(currentScript.KeyLink, "Key link")
    end
end)
backBtn.MouseButton1Click:Connect(closeDetail)

-- panel drag (top bar handle)
local panelDragging  = false
local panelDragStart = nil
local panelStartPos  = nil

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        panelDragging  = true
        panelDragStart = Vector2.new(input.Position.X, input.Position.Y)
        panelStartPos  = panel.Position
    end
end)

topBar.InputChanged:Connect(function(input)
    if not panelDragging or not panelDragStart then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = Vector2.new(input.Position.X, input.Position.Y) - panelDragStart
        panel.Position = UDim2.new(
            panelStartPos.X.Scale, panelStartPos.X.Offset + delta.X,
            panelStartPos.Y.Scale, panelStartPos.Y.Offset + delta.Y
        )
    end
end)

-- floating icon: drag to move, clean tap toggles the panel
local iconDragging  = false
local iconMoved     = false
local iconDragStart = nil
local iconStartAbs  = nil

floatingIcon.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        iconDragging  = true
        iconMoved     = false
        iconDragStart = Vector2.new(input.Position.X, input.Position.Y)
        iconStartAbs  = Vector2.new(floatingIcon.AbsolutePosition.X, floatingIcon.AbsolutePosition.Y)
    end
end)

floatingIcon.InputChanged:Connect(function(input)
    if not iconDragging or not iconDragStart then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = Vector2.new(input.Position.X, input.Position.Y) - iconDragStart
        if math.abs(delta.X) > CONFIG.DragThreshold
            or math.abs(delta.Y) > CONFIG.DragThreshold then
            iconMoved = true
        end
        if iconMoved and camera then
            local vp = camera.ViewportSize
            local x  = math.clamp(iconStartAbs.X + delta.X, 8, math.max(8, vp.X - iconSize - 8))
            local y  = math.clamp(iconStartAbs.Y + delta.Y, 8, math.max(8, vp.Y - iconSize - 8))
            floatingIcon.Position = UDim2.fromOffset(x, y)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        panelDragging = false
        if iconDragging then
            iconDragging = false
            if not iconMoved then
                setPanel(not panel.Visible)
            end
        end
    end
end)

-- keyboard toggle (PC)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == CONFIG.ToggleKey then
        setPanel(not panel.Visible)
    end
end)

-- responsive panel + icon clamping
local function fitPanel()
    if not camera then return end
    local vp     = camera.ViewportSize
    local width  = math.min(CONFIG.PanelSize.X, vp.X - 16)
    local height = math.min(CONFIG.PanelSize.Y, vp.Y - 16)
    panel.Size = UDim2.fromOffset(width, height)
end

if camera then
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        clampIcon()
        fitPanel()
    end)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    camera = workspace.CurrentCamera
    clampIcon()
    fitPanel()
end)

-- =========================================================
-- SECTION 6: BOOT
-- =========================================================

fitPanel()
setTabHighlight("search")
applyPager()
setStatus("RightShift or the HUB icon opens this panel. Tap TRENDING / LATEST / SEARCH.")

print("[RBLX SCRPT HUB v" .. CONFIG.Version .. "] ready - RightShift or the floating HUB icon opens the panel")

