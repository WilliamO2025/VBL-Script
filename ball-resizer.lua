-- Bundled UI snapshot; no downloads at runtime.
local GalaxLib = (function()
--[[
    GalaxLib - UI Library for Matcha External
    Made with love by Claude x Galax

    USAGE:
    local Win = GalaxLib:CreateWindow({ Title="Script", Size=Vector2.new(560,420), MenuKey=0x70 })
    local Tab = Win:AddTab("Combat")
    local Sec = Tab:AddSection("Aimbot")

    local t  = Sec:AddToggle("Enable", false, function(v) end)
    local s  = Sec:AddSlider("FOV", {Min=1, Max=360, Default=90, Suffix="°"}, function(v) end)
    local d  = Sec:AddDropdown("Mode", {"A","B","C"}, "A", function(v) end)
    local k  = Sec:AddKeybind("Trigger", 0x46, function() end)
    local tb = Sec:AddTextbox("Name", "default", function(v) end)
    local lb = Sec:AddLabel("v1.0")
    Sec:AddButton("Reset", function() end)

    -- :Get() / :Set(value) available on all widgets except Button

    Win:Notify("msg", "title", 3)
    Win:Unload()   -- kills loop + frees all drawings

    -- Settings tab is added automatically at the end.
    --   It contains:
    --     • Toggle Key  — click to rebind the menu open/close key
    --     • Kill Script — stops the loop and removes all drawings
]]

-- ============================================================
local GalaxLib = {}

-- ── Theme ────────────────────────────────────────────────────
local T = {
    Body       = Color3.fromRGB(10, 10, 14),
    Surface0   = Color3.fromRGB(18, 18, 24),
    Surface1   = Color3.fromRGB(26, 26, 34),
    Border0    = Color3.fromRGB(35, 35, 46),
    Border1    = Color3.fromRGB(50, 50, 65),
    Accent     = Color3.fromRGB(220, 50, 50),    -- red
    AccentDark = Color3.fromRGB(110, 18, 18),    -- dark red
    Text       = Color3.fromRGB(240, 240, 245),
    SubText    = Color3.fromRGB(110, 110, 130),
    Red        = Color3.fromRGB(220, 70, 70),
    RedDark    = Color3.fromRGB(90, 22, 22),
}

-- ── Key names ────────────────────────────────────────────────
local KeyNames = {}
do
    local raw = {
        [0x08]="BACK",[0x09]="TAB",[0x0D]="ENTER",[0x10]="SHIFT",[0x11]="CTRL",
        [0x12]="ALT",[0x14]="CAPS",[0x1B]="ESC",[0x20]="SPACE",[0x21]="PGUP",
        [0x22]="PGDN",[0x23]="END",[0x24]="HOME",[0x25]="LEFT",[0x26]="UP",
        [0x27]="RIGHT",[0x28]="DOWN",[0x2D]="INS",[0x2E]="DEL",
        [0x30]="0",[0x31]="1",[0x32]="2",[0x33]="3",[0x34]="4",
        [0x35]="5",[0x36]="6",[0x37]="7",[0x38]="8",[0x39]="9",
        [0xBA]=";",[0xBB]="=",[0xBC]=",",[0xBD]="-",[0xBE]=".",
        [0xBF]="/",[0xC0]="`",[0xDB]="[",[0xDC]="\\",[0xDD]="]",[0xDE]="'",
    }
    for k,v in pairs(raw) do KeyNames[k] = v end
    for i = 65, 90  do KeyNames[i]        = string.char(i) end
    for i = 1,  12  do KeyNames[0x6F + i] = "F"..i         end
end

local function keyName(kc)
    return KeyNames[kc] or ("0x"..string.format("%X", kc or 0))
end

-- ── Utilities ────────────────────────────────────────────────
local function clamp(x, a, b)
    return x < a and a or (x > b and b or x)
end

local function textW(str, sz)
    return #(str or "") * (sz or 13) * 0.54
end

local function mpos()
    local lp = game:GetService("Players").LocalPlayer
    if lp then
        local m = lp:GetMouse()
        if m then return Vector2.new(m.X, m.Y) end
    end
    return Vector2.new(0, 0)
end

local function over(pos, size)
    local m = mpos()
    return m.X >= pos.X and m.X <= pos.X + size.X
       and m.Y >= pos.Y and m.Y <= pos.Y + size.Y
end

local function newDraw(dtype, props)
    local d = Drawing.new(dtype)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function pointOnRect(t, pos, sz)
    local p = (t % 1) * (sz.X * 2 + sz.Y * 2)
    if     p < sz.X             then return pos + Vector2.new(p, 0)
    elseif p < sz.X + sz.Y      then return pos + Vector2.new(sz.X, p - sz.X)
    elseif p < sz.X*2 + sz.Y   then return pos + Vector2.new(sz.X - (p-(sz.X+sz.Y)), sz.Y)
    else                             return pos + Vector2.new(0, sz.Y-(p-(sz.X*2+sz.Y)))
    end
end

-- ── Drawing Pool ─────────────────────────────────────────────
local function poolNew()
    return { d = {}, seen = {} }
end

local function poolBeginFrame(pool)
    pool.seen = {}
end

local function poolAdd(pool, id, dtype, props)
    pool.seen[id] = true
    local e = pool.d[id]
    if e then
        for k,v in pairs(props) do e[k] = v end
        e.Visible = true
        return e
    end
    local obj = newDraw(dtype, props)
    pool.d[id] = obj
    return obj
end

local function poolFlush(pool)
    for id, obj in pairs(pool.d) do
        if not pool.seen[id] then
            obj.Visible = false
        end
    end
end

local function poolHide(pool, id)
    local o = pool.d[id]; if o then o.Visible = false end
end

local function poolGet(pool, id)
    return pool.d[id]
end

local function poolDestroy(pool)
    for _, o in pairs(pool.d) do o:Remove() end
    pool.d = {}; pool.seen = {}
end

-- ── Input tracker ────────────────────────────────────────────
local Input = { _prev={}, click=false, held=false, rclick=false }

function Input:update()
    local m1 = ismouse1pressed()
    local m2 = ismouse2pressed()
    self.click  = m1 and not (self._prev.m1 or false)
    self.held   = m1
    self.rclick = m2 and not (self._prev.m2 or false)
    self._prev.m1 = m1
    self._prev.m2 = m2
end

function Input:keyClick(kc)
    local cur = iskeypressed(kc)
    local prv = self._prev[kc] or false
    self._prev[kc] = cur
    return cur and not prv
end

function Input:keyHeld(kc) return iskeypressed(kc) end

-- ============================================================
--  CREATE WINDOW
-- ============================================================
function GalaxLib:CreateWindow(opts)
    opts = opts or {}

    local WIN = {
        Title    = opts.Title   or "Galax",
        Size     = opts.Size    or Vector2.new(560, 420),
        MenuKey  = opts.MenuKey or 0x70,
        _pos     = Vector2.new(opts.X or 120, opts.Y or 100),
        _open    = true,
        _running = true,
        _pool    = poolNew(),
        _tabs    = {},
        _openTab = nil,
        _drag          = nil,
        _sliderDrag    = nil,
        _keybindTarget = nil,
        _textboxTarget = nil,
        _dropdownTarget= nil,
        _settingsListen = false,
        _snakeLines = {},
        _snakeCount = 60,  -- 30 per snake, 2 snakes
    }

    for i = 1, WIN._snakeCount do
        WIN._snakeLines[i] = newDraw("Line", {
            Thickness=3, Color=T.Accent, Visible=false, ZIndex=50,
        })
    end

    -- ============================================================
    --  AddTab
    -- ============================================================
    function WIN:AddTab(name)
        local TAB = { _name=name, _sections={}, _win=self }

        function TAB:AddSection(sname)
            local SEC = { _name=sname, _widgets={}, _win=self._win }

            local function reg(item)
                table.insert(SEC._widgets, item)
            end

            function SEC:AddToggle(label, default, cb)
                local item = { type="toggle", label=label, value=default or false, cb=cb or function() end }
                reg(item); item.cb(item.value)
                return { Get=function() return item.value end, Set=function(_,v) item.value=v; item.cb(v) end }
            end

            function SEC:AddSlider(label, o, cb)
                o = o or {}
                local item = {
                    type="slider", label=label,
                    min=o.Min or 0, max=o.Max or 100,
                    value=o.Default or o.Min or 0,
                    suffix=o.Suffix or "", cb=cb or function() end,
                }
                reg(item); item.cb(item.value)
                return {
                    Get=function() return item.value end,
                    Set=function(_,v) item.value=clamp(v,item.min,item.max); item.cb(item.value) end,
                }
            end

            function SEC:AddButton(label, cb)
                local item = { type="button", label=label, cb=cb or function() end }
                reg(item); return {}
            end

            function SEC:AddDropdown(label, options, default, cb)
                local item = {
                    type="dropdown", label=label,
                    options=options or {},
                    value=default or (options and options[1]) or "",
                    cb=cb or function() end,
                }
                reg(item); item.cb(item.value)
                return { Get=function() return item.value end, Set=function(_,v) item.value=v; item.cb(v) end }
            end

            function SEC:AddKeybind(label, default, cb)
                local item = {
                    type="keybind", label=label,
                    value=default or 0,
                    cb=cb or function() end, listening=false,
                }
                reg(item)
                return { Get=function() return item.value end, Set=function(_,v) item.value=v; item.cb(v) end }
            end

            function SEC:AddTextbox(label, default, cb)
                local item = { type="textbox", label=label, value=default or "", cb=cb or function() end }
                reg(item)
                return { Get=function() return item.value end, Set=function(_,v) item.value=v; item.cb(v) end }
            end

            function SEC:AddLabel(text)
                local item = { type="label", label=text or "" }
                reg(item)
                return { Get=function() return item.label end, Set=function(_,v) item.label=v end }
            end

            table.insert(TAB._sections, SEC)
            return SEC
        end

        table.insert(self._tabs, TAB)
        if not self._openTab then self._openTab = TAB end
        return TAB
    end

    -- ============================================================
    --  Settings Tab
    -- ============================================================
    function WIN:_buildSettings()
        local STAB = { _name="Settings", _sections={}, _win=self, _isSettings=true }
        local SSEC = { _name="Menu", _widgets={}, _win=self }

        table.insert(SSEC._widgets, {
            type      = "settings_keybind",
            label     = "Toggle Key",
            listening = false,
        })

        table.insert(SSEC._widgets, {
            type  = "label",
            label = "- - - - - - - - - - - -",
        })

        table.insert(SSEC._widgets, {
            type  = "settings_kill",
            label = "Kill Script",
        })

        table.insert(STAB._sections, SSEC)
        table.insert(self._tabs, STAB)
    end

    -- ============================================================
    --  Notify / Unload
    -- ============================================================
    function WIN:Notify(message, title, duration)
        notify(message, title or self.Title, duration or 7)
    end

    function WIN:Unload()
        self._running = false
    end

    -- ============================================================
    --  _renderWidget
    -- ============================================================
    function WIN:_renderWidget(item, pool, wid, wx, wy, innerW, FONT)
        local wY = 0

        -- ── label ──────────────────────────────────────────────
        if item.type == "label" then
            poolAdd(pool, wid.."_lbl", "Text", {
                Position=Vector2.new(wx,wy+2), Text=item.label,
                Size=13, Font=FONT, Color=T.SubText,
                Outline=false, Visible=true, ZIndex=6,
            })
            wY = 20

        -- ── toggle ─────────────────────────────────────────────
        elseif item.type == "toggle" then
            local bsz  = Vector2.new(14,14)
            local bpos = Vector2.new(wx+innerW-14, wy)
            poolAdd(pool, wid.."_box",  "Square", { Position=bpos, Size=bsz, Filled=true,  Color=item.value and T.Accent or T.Surface1, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_boxb", "Square", { Position=bpos, Size=bsz, Filled=false, Color=T.Border1, Thickness=1, Visible=true, ZIndex=7 })
            poolAdd(pool, wid.."_lbl",  "Text",   { Position=Vector2.new(wx,wy+1), Text=item.label, Size=13, Font=FONT, Color=item.value and T.Text or T.SubText, Outline=false, Visible=true, ZIndex=6 })
            if Input.click and over(Vector2.new(wx,wy), Vector2.new(innerW,16)) then
                item.value = not item.value; item.cb(item.value)
            end
            wY = 22

        -- ── button ─────────────────────────────────────────────
        elseif item.type == "button" then
            local bpos = Vector2.new(wx, wy)
            local bsz  = Vector2.new(innerW, 22)
            local hov  = over(bpos, bsz)
            poolAdd(pool, wid.."_btn",  "Square", { Position=bpos, Size=bsz, Filled=true,  Color=hov and T.AccentDark or T.Surface1, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_btnb", "Square", { Position=bpos, Size=bsz, Filled=false, Color=hov and T.Accent or T.Border0, Thickness=1, Visible=true, ZIndex=7 })
            poolAdd(pool, wid.."_btnt", "Text", {
                Position = Vector2.new(wx + innerW/2, wy + 4),
                Text=item.label, Size=13, Font=FONT,
                Color=T.Text, Center=true, Outline=false, Visible=true, ZIndex=7,
            })
            if Input.click and hov then item.cb() end
            wY = 28

        -- ── slider ─────────────────────────────────────────────
        elseif item.type == "slider" then
            local valStr = tostring(item.value)..item.suffix
            poolAdd(pool, wid.."_lbl",  "Text",   { Position=Vector2.new(wx,wy), Text=item.label, Size=13, Font=FONT, Color=T.Text, Outline=false, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_val",  "Text",   { Position=Vector2.new(wx+innerW-textW(valStr,12),wy), Text=valStr, Size=12, Font=FONT, Color=T.Text, Outline=false, Visible=true, ZIndex=6 })
            local trkPos = Vector2.new(wx, wy+17)
            local trkSz  = Vector2.new(innerW, 5)
            poolAdd(pool, wid.."_trk",  "Square", { Position=trkPos, Size=trkSz, Filled=true, Color=T.Surface1, Visible=true, ZIndex=6 })
            local pct   = clamp((item.value-item.min)/(item.max-item.min),0,1)
            local fillW = math.max(4, trkSz.X*pct)
            poolAdd(pool, wid.."_fill", "Square", { Position=trkPos, Size=Vector2.new(fillW,trkSz.Y), Filled=true, Color=T.Accent, Visible=true, ZIndex=7 })
            poolAdd(pool, wid.."_knob", "Square", { Position=Vector2.new(trkPos.X+fillW-4,trkPos.Y-3), Size=Vector2.new(8,11), Filled=true, Color=T.Text, Visible=true, ZIndex=8 })
            if Input.click and over(trkPos-Vector2.new(0,5), trkSz+Vector2.new(0,12)) then self._sliderDrag=item end
            if self._sliderDrag==item then
                if Input.held then
                    local p = clamp((mpos().X-trkPos.X)/trkSz.X,0,1)
                    item.value = clamp(math.floor(item.min+(item.max-item.min)*p+0.5),item.min,item.max)
                    item.cb(item.value)
                else self._sliderDrag=nil end
            end
            wY = 34

        -- ── dropdown ───────────────────────────────────────────
        elseif item.type == "dropdown" then
            local ddPos  = Vector2.new(wx, wy+14)
            local ddSz   = Vector2.new(innerW, 22)
            local isOpen = (self._dropdownTarget == item)
            poolAdd(pool, wid.."_ddlbl",  "Text",   { Position=Vector2.new(wx,wy), Text=item.label, Size=12, Font=FONT, Color=T.SubText, Outline=false, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_ddbg",   "Square", { Position=ddPos, Size=ddSz, Filled=true,  Color=T.Surface1, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_ddb",    "Square", { Position=ddPos, Size=ddSz, Filled=false, Color=isOpen and T.Accent or T.Border0, Thickness=1, Visible=true, ZIndex=7 })
            poolAdd(pool, wid.."_ddval",  "Text",   { Position=ddPos+Vector2.new(6,4), Text=item.value, Size=13, Font=FONT, Color=T.Text, Outline=false, Visible=true, ZIndex=7 })
            local ax,ay = ddPos.X+ddSz.X-14, ddPos.Y+11
            poolAdd(pool, wid.."_ddarr",  "Triangle", { PointA=Vector2.new(ax,ay-4), PointB=Vector2.new(ax+7,ay-4), PointC=Vector2.new(ax+3.5,ay+3), Filled=true, Color=isOpen and T.Accent or T.SubText, Visible=true, ZIndex=7 })
            if Input.click and over(ddPos,ddSz) then self._dropdownTarget = isOpen and nil or item end
            if isOpen then
                local optH    = 20
                local listPos = ddPos+Vector2.new(0,ddSz.Y+2)
                local listSz  = Vector2.new(innerW, #item.options*optH+4)
                poolAdd(pool, wid.."_ddlist",  "Square", { Position=listPos, Size=listSz, Filled=true,  Color=T.Surface0, Visible=true, ZIndex=9 })
                poolAdd(pool, wid.."_ddlistb", "Square", { Position=listPos, Size=listSz, Filled=false, Color=T.Border1, Thickness=1, Visible=true, ZIndex=10 })
                for oi, opt in ipairs(item.options) do
                    local opPos = listPos+Vector2.new(0,(oi-1)*optH+2)
                    local opSz  = Vector2.new(innerW,optH)
                    local opHov = over(opPos,opSz)
                    local opSel = (opt==item.value)
                    if opHov or opSel then
                        poolAdd(pool, wid.."_ddhi_"..oi, "Square", { Position=opPos, Size=opSz, Filled=true, Color=opSel and T.AccentDark or T.Surface1, Visible=true, ZIndex=10 })
                    else poolHide(pool, wid.."_ddhi_"..oi) end
                    poolAdd(pool, wid.."_ddot_"..oi, "Text", { Position=opPos+Vector2.new(8,3), Text=opt, Size=13, Font=FONT, Color=opSel and T.Accent or T.Text, Outline=false, Visible=true, ZIndex=11 })
                    if Input.click and opHov then item.value=opt; item.cb(opt); self._dropdownTarget=nil end
                end
                wY = #item.options*optH+4+4
            else
                for oi=1,#item.options do poolHide(pool, wid.."_ddhi_"..oi) end
            end
            wY = wY + 42

        -- ── keybind ────────────────────────────────────────────
        elseif item.type == "keybind" then
            local kbStr = item.listening and "[ ... ]" or ("[ "..keyName(item.value).." ]")
            local kbW   = textW(kbStr,12)+10
            local kbPos = Vector2.new(wx+innerW-kbW, wy)
            local kbSz  = Vector2.new(kbW,18)
            poolAdd(pool, wid.."_lbl",   "Text",   { Position=Vector2.new(wx,wy+2), Text=item.label, Size=13, Font=FONT, Color=T.Text, Outline=false, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_kbbg",  "Square", { Position=kbPos, Size=kbSz, Filled=true,  Color=item.listening and T.AccentDark or T.Surface1, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_kbb",   "Square", { Position=kbPos, Size=kbSz, Filled=false, Color=item.listening and T.Accent or T.Border0, Thickness=1, Visible=true, ZIndex=7 })
            poolAdd(pool, wid.."_kbtxt", "Text",   { Position=kbPos+Vector2.new(4,2), Text=kbStr, Size=12, Font=FONT, Color=item.listening and T.Accent or T.SubText, Outline=false, Visible=true, ZIndex=7 })
            if Input.click and over(kbPos,kbSz) then item.listening=true; self._keybindTarget=item end
            if item.listening and self._keybindTarget==item then
                for kc=1,255 do
                    if kc~=0x01 and kc~=0x02 and Input:keyClick(kc) then
                        if kc~=0x1B then item.value=kc; item.cb(kc) end
                        item.listening=false; self._keybindTarget=nil; break
                    end
                end
            end
            wY = 24

        -- ── textbox ────────────────────────────────────────────
        elseif item.type == "textbox" then
            local tbPos   = Vector2.new(wx, wy+15)
            local tbSz    = Vector2.new(innerW,22)
            local focused = (self._textboxTarget==item)
            local cursor  = (focused and (math.floor(tick()*2)%2==0)) and "|" or ""
            local display = item.value..cursor
            if display=="" then display = focused and cursor or item.label end
            poolAdd(pool, wid.."_lbl",  "Text",   { Position=Vector2.new(wx,wy), Text=item.label, Size=12, Font=FONT, Color=T.SubText, Outline=false, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_tbbg", "Square", { Position=tbPos, Size=tbSz, Filled=true,  Color=T.Surface1, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_tbb",  "Square", { Position=tbPos, Size=tbSz, Filled=false, Color=focused and T.Accent or T.Border0, Thickness=1, Visible=true, ZIndex=7 })
            poolAdd(pool, wid.."_tbtxt","Text",   { Position=tbPos+Vector2.new(6,4), Text=display, Size=13, Font=FONT, Color=(item.value~="" or focused) and T.Text or T.SubText, Outline=false, Visible=true, ZIndex=7 })
            if Input.click then
                if over(tbPos,tbSz) then self._textboxTarget=item
                elseif self._textboxTarget==item then self._textboxTarget=nil end
            end
            if focused then
                for kc=8,122 do
                    if Input:keyClick(kc) then
                        if     kc==0x08 then item.value=item.value:sub(1,-2); item.cb(item.value)
                        elseif kc==0x0D then self._textboxTarget=nil
                        elseif kc==0x20 then item.value=item.value.." "; item.cb(item.value)
                        elseif kc>=0x30 and kc<=0x5A then
                            local ch=KeyNames[kc]
                            if ch and #ch==1 then
                                local sh=Input:keyHeld(0x10) or Input:keyHeld(0xA0) or Input:keyHeld(0xA1)
                                item.value=item.value..(sh and ch:upper() or ch:lower()); item.cb(item.value)
                            end
                        end
                    end
                end
            end
            wY = 44

        -- ── settings_keybind ───────────────────────────────────
        elseif item.type == "settings_keybind" then
            local kbStr = item.listening and "[ ... ]" or ("[ "..keyName(self.MenuKey).." ]")
            local kbW   = textW(kbStr,12)+10
            local kbPos = Vector2.new(wx+innerW-kbW, wy)
            local kbSz  = Vector2.new(kbW,18)
            poolAdd(pool, wid.."_lbl",   "Text",   { Position=Vector2.new(wx,wy+2), Text=item.label, Size=13, Font=FONT, Color=T.Text, Outline=false, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_kbbg",  "Square", { Position=kbPos, Size=kbSz, Filled=true,  Color=item.listening and T.AccentDark or T.Surface1, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_kbb",   "Square", { Position=kbPos, Size=kbSz, Filled=false, Color=item.listening and T.Accent or T.Border0, Thickness=1, Visible=true, ZIndex=7 })
            poolAdd(pool, wid.."_kbtxt", "Text",   { Position=kbPos+Vector2.new(4,2), Text=kbStr, Size=12, Font=FONT, Color=item.listening and T.Accent or T.SubText, Outline=false, Visible=true, ZIndex=7 })
            if Input.click and over(kbPos,kbSz) then
                item.listening=true; self._settingsListen=true
            end
            if item.listening and self._settingsListen then
                for kc=1,255 do
                    if kc~=0x01 and kc~=0x02 and Input:keyClick(kc) then
                        if kc~=0x1B then
                            self.MenuKey = kc
                            self:Notify("Toggle key changed to "..keyName(kc), self.Title, 7)
                        end
                        item.listening=false; self._settingsListen=false; break
                    end
                end
            end
            wY = 24

        -- ── settings_kill ──────────────────────────────────────
        elseif item.type == "settings_kill" then
            local bpos = Vector2.new(wx, wy)
            local bsz  = Vector2.new(innerW, 22)
            local hov  = over(bpos, bsz)
            poolAdd(pool, wid.."_btn",  "Square", { Position=bpos, Size=bsz, Filled=true,  Color=hov and T.RedDark or T.Surface1, Visible=true, ZIndex=6 })
            poolAdd(pool, wid.."_btnb", "Square", { Position=bpos, Size=bsz, Filled=false, Color=hov and T.Red or T.Border0, Thickness=1, Visible=true, ZIndex=7 })
            poolAdd(pool, wid.."_btnt", "Text", {
                Position = Vector2.new(wx + innerW/2, wy + 4),
                Text=item.label, Size=13, Font=FONT,
                Color=T.Red, Center=true, Outline=false, Visible=true, ZIndex=7,
            })
            if Input.click and hov then
                self:Notify("Script killed.", self.Title, 2)
                self._running = false
            end
            wY = 28
        end

        return wY
    end

    -- ============================================================
    --  _render
    -- ============================================================
    function WIN:_render()
        local pool = self._pool
        local pos  = self._pos
        local sz   = self.Size
        local t    = tick()
        local FONT = Drawing.Fonts.UI

        if not self._open then
            poolDestroy(pool)
            for i=1,self._snakeCount do self._snakeLines[i].Visible=false end
            return
        end

        poolBeginFrame(pool)

        -- ── Drag ────────────────────────────────────────────
        if Input.click and over(pos, Vector2.new(sz.X,38)) and not self._drag then
            self._drag = mpos()-pos
        end
        if not Input.held then self._drag=nil end
        if self._drag then self._pos=mpos()-self._drag; pos=self._pos end

        -- ── Window ──────────────────────────────────────────
        poolAdd(pool,"win_bg","Square",{ Position=pos, Size=sz, Filled=true,  Color=T.Body,    Visible=true, ZIndex=1 })
        poolAdd(pool,"win_b", "Square",{ Position=pos, Size=sz, Filled=false, Color=T.Border0, Thickness=1, Visible=true, ZIndex=2 })

        -- ── Topbar ──────────────────────────────────────────
        local topH = 38
        poolAdd(pool,"top_bg",   "Square",{ Position=pos, Size=Vector2.new(sz.X,topH), Filled=true, Color=T.Surface0, Visible=true, ZIndex=2 })

        poolAdd(pool,"top_title","Text",  { Position=pos+Vector2.new(12,11), Text=self.Title, Size=16, Font=FONT, Color=T.Accent, Outline=true, Visible=true, ZIndex=3 })

        -- ── Watermark ───────────────────────────────────────
        local wmStr = self.Title.."  |  "..keyName(self.MenuKey).." to toggle"
        poolAdd(pool,"wm_bg", "Square",{ Position=pos-Vector2.new(0,21), Size=Vector2.new(textW(wmStr,12)+14,18), Filled=true, Color=T.Surface0, Visible=true, ZIndex=1 })
        poolAdd(pool,"wm_txt","Text",  { Position=pos-Vector2.new(-5,17), Text=wmStr, Size=12, Font=FONT, Color=T.SubText, Outline=false, Visible=true, ZIndex=2 })

        -- ── Snake ───────────────────────────────────────────
        local snkPos = pos
        local snkSz  = sz
        -- Snake 1: clockwise, starts top-left
        for i=1,30 do
            local ti = (t*0.175)-(i*0.006)
            local sl = self._snakeLines[i]
            sl.From         = pointOnRect(ti,        snkPos, snkSz)
            sl.To           = pointOnRect(ti+0.006,  snkPos, snkSz)
            sl.Color        = Color3.fromHSV((t*0.12+i*0.04)%1, 0.85, 1)
            sl.Transparency = (1-i/30)*0.65
            sl.Visible      = true
            sl.ZIndex       = 50
        end
        -- Snake 2: counter-clockwise, starts opposite side
        for i=1,30 do
            local ti = -(t*0.175)+(0.5)-(i*0.006)
            local sl = self._snakeLines[30+i]
            sl.From         = pointOnRect(ti,        snkPos, snkSz)
            sl.To           = pointOnRect(ti+0.006,  snkPos, snkSz)
            sl.Color        = Color3.fromHSV((t*0.12+i*0.04+0.5)%1, 0.85, 1)
            sl.Transparency = (1-i/30)*0.65
            sl.Visible      = true
            sl.ZIndex       = 50
        end

        -- ── Tabs ────────────────────────────────────────────
        local tabY = topH+4
        local tabH = 26
        local tabX = 10
        for i, tab in ipairs(self._tabs) do
            local tw   = textW(tab._name,13)+24
            local tpos = pos+Vector2.new(tabX,tabY)
            local tsz  = Vector2.new(tw,tabH)
            local open = (self._openTab==tab)
            poolAdd(pool,"tab_bg_"..i,  "Square",{ Position=tpos, Size=tsz, Filled=true, Color=open and T.Surface1 or T.Surface0, Visible=true, ZIndex=3 })
            poolAdd(pool,"tab_txt_"..i, "Text",  { Position=tpos+Vector2.new(tw/2,tabH/2-6), Text=tab._name, Size=13, Font=FONT, Color=open and T.Text or T.SubText, Center=true, Outline=false, Visible=true, ZIndex=4 })
            poolHide(pool,"tab_ul_"..i)
            if Input.click and over(tpos,tsz) then
                self._openTab=tab
                self._dropdownTarget=nil; self._textboxTarget=nil
            end
            tabX = tabX+tw+5
        end

        if not self._openTab then return end

        -- ── Content: 2-column layout ────────────────────────
        local contTop = topH+tabH+10
        local padX    = 10
        local colW    = (sz.X-padX*3)/2
        local colYL   = contTop
        local colYR   = contTop

        for si, sec in ipairs(self._openTab._sections) do
            local isLeft = (si%2==1)
            local sx     = isLeft and padX or (padX*2+colW)
            local sy     = isLeft and colYL or colYR
            local sid    = "s"..si

            poolAdd(pool,sid.."_hdr","Text",{
                Position=pos+Vector2.new(sx+6,sy+4),
                Text=sec._name, Size=11, Font=FONT,
                Color=T.SubText, Outline=false, Visible=true, ZIndex=6,
            })

            local wY     = sy+20
            local innerX = pos.X+sx+8
            local innerW = colW-16

            for wi, item in ipairs(sec._widgets) do
                local wid = sid.."_w"..wi
                local wx  = innerX
                local wy  = pos.Y+wY

                local consumed = self:_renderWidget(item, pool, wid, wx, wy, innerW, FONT)
                wY = wY + consumed + 6
            end

            local secH = wY-sy+8
            poolAdd(pool,sid.."_bg", "Square",{ Position=pos+Vector2.new(sx,sy), Size=Vector2.new(colW,secH), Filled=true,  Color=T.Surface0, Visible=true, ZIndex=4 })
            poolAdd(pool,sid.."_bgb","Square",{ Position=pos+Vector2.new(sx,sy), Size=Vector2.new(colW,secH), Filled=false, Color=T.Border0, Thickness=1,  Visible=true, ZIndex=5 })
            local hdr = poolGet(pool,sid.."_hdr"); if hdr then hdr.ZIndex=6 end

            if isLeft then colYL=colYL+secH+12 else colYR=colYR+secH+12 end
        end

        poolFlush(pool)
    end

    -- ============================================================
    --  Main loop
    -- ============================================================
    task.spawn(function()
        WIN:_buildSettings()

        while WIN._running do
            task.wait()
            if not isrbxactive() then continue end
            Input:update()

            if Input:keyClick(WIN.MenuKey) then
                WIN._open = not WIN._open
                setrobloxinput(not WIN._open)
                if not WIN._open then
                    WIN._dropdownTarget=nil
                    WIN._textboxTarget =nil
                    WIN._keybindTarget =nil
                    WIN._settingsListen=false
                end
            end

            WIN:_render()
        end

        setrobloxinput(true)
        poolDestroy(WIN._pool)
        for i=1,WIN._snakeCount do WIN._snakeLines[i]:Remove() end
    end)

    return WIN
end

return GalaxLib

end)()

-- Merged readable v1/v2 resizer. Requires Matcha-compatible drawing/input APIs.
-- Only the size and menu-key text files are read/written. No remote loaders.
local sizeFile, keyFile = "hitbox_size_v2.txt", "hitbox_menukey.txt"
local function readNumber(path, fallback, minimum, maximum)
    local ok, value = pcall(function()
        if isfile(path) then return tonumber(readfile(path)) end
    end)
    if ok and value and value >= minimum and value <= maximum then return value end
    return fallback
end
local ballSize = readNumber(sizeFile, readNumber("hitbox_size.txt", 5.5, 0.1, 30), 0.1, 30)
local menuKey = math.floor(readNumber(keyFile, 0x70, 1, 255))
local function save(path, value)
    pcall(function() writefile(path, tostring(value)) end)
end
local win = GalaxLib:CreateWindow({
    Title = "Ball Resizer | Luna v1/v2 merge",
    Size = Vector2.new(480, 280), MenuKey = menuKey,
})
win._open = false
function win:Notify(message, title, duration)
    if self.MenuKey ~= menuKey then
        menuKey = self.MenuKey
        save(keyFile, menuKey)
    end
    if type(notify) == "function" then
        pcall(notify, message, title or self.Title, duration or 5)
    end
end
local function resize()
    pcall(function()
        local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
        local balls = assets and assets:FindFirstChild("Ball")
        if not balls then return end
        for _, model in ipairs(balls:GetChildren()) do
            if model:IsA("Model") then
                for _, part in ipairs(model:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.Size = Vector3.new(ballSize, ballSize, ballSize)
                    end
                end
            end
        end
    end)
end
local section = win:AddTab("Main"):AddSection("Ball Settings")
local label = section:AddLabel(string.format("Size: %.1f", ballSize))
section:AddSlider("Size (tenths)", {
    Min = 1, Max = 300, Default = math.floor(ballSize * 10 + 0.5),
}, function(value)
    if type(value) ~= "number" or value ~= value then return end
    ballSize = math.max(1, math.min(300, math.floor(value + 0.5))) / 10
    label:Set(string.format("Size: %.1f", ballSize))
    resize()
    save(sizeFile, string.format("%.1f", ballSize))
end)
task.spawn(function()
    while win._running do
        resize()
        task.wait(1.5)
    end
end)
win:Notify("Use the saved menu key (default F1) to open. Settings > Kill Script stops updates.")
-- Stopping updates does not restore sizes already changed; rejoin to reset.


