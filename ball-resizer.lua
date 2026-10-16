-- VBL Script v3: readable, standalone Matcha drawing GUI.
-- Feature reference: 0x1cx/random-lua revision a46fe389 (April 3 2026).
-- Resizer behavior also based on Luna7070/585438 v1.2/v2.0. Original hitbox credit: huss.
-- No remote code, memory offsets, or executable config files.
-- BasePart.CFrame support varies by runtime; unsupported rotation is reported in the GUI.
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Http = game:GetService("HttpService")
local CONFIG = "vbl_script_config.json"
local defaults = {
    size = 5.5, resize = false, rotation = false, mode = "Snap",
    predictor = false, trajectory = "Line", segments = 12, marker = 16,
    gravity = 17, ground = -5, los = false, localPlayer = true,
    teammates = true, opponents = true, length = 10, thickness = 2,
    autoSet = false, setDistance = 5, setKey = 0x51, cooldown = 0.5,
    menuKey = 0x70, accent = "Violet", predictionColor = "Cyan",
    teamColor = "Green", enemyColor = "Rose",
}
local limits = {
    size={0.1,30}, segments={3,24}, marker={4,40}, gravity={1,200}, ground={-100,100},
    length={3,30}, thickness={1,6}, setDistance={1,20}, cooldown={0.2,2},
    menuKey={8,255}, setKey={8,255},
}
local palettes = {
    Violet=Color3.fromRGB(167,139,250), Cyan=Color3.fromRGB(65,210,230),
    Green=Color3.fromRGB(79,222,155), Rose=Color3.fromRGB(251,113,133),
}
local options = {mode={"Snap","Free"}, trajectory={"Line","Arrows"}}
local cfg = {}
local function valid(key, value)
    if type(value) ~= type(defaults[key]) then return false end
    if type(value) == "number" then
        local range = limits[key]
        return value == value and range and value >= range[1] and value <= range[2]
            and ((key ~= "menuKey" and key ~= "setKey" and key ~= "segments") or value % 1 == 0)
    end
    if type(value) == "string" then
        if options[key] then
            for _, item in ipairs(options[key]) do if item == value then return true end end
            return false
        end
        return palettes[value] ~= nil
    end
    return true
end
for k,v in pairs(defaults) do cfg[k]=v end
pcall(function()
    if isfile(CONFIG) then
        local data = Http:JSONDecode(readfile(CONFIG))
        if type(data) == "table" then
            for k in pairs(defaults) do if valid(k,data[k]) then cfg[k]=data[k] end end
        end
    else
        for _,path in ipairs({"hitbox_size_v2.txt","hitbox_size.txt"}) do
            if isfile(path) then
                local n=tonumber(readfile(path))
                if valid("size",n) then cfg.size=n; break end
            end
        end
        if isfile("hitbox_menukey.txt") then
            local n=tonumber(readfile("hitbox_menukey.txt"))
            if valid("menuKey",n) then cfg.menuKey=n end
        end
    end
end)

local running, opened, page = true, true, "Ball"
local status, saveStatus = "Ready | Features start with their saved settings", "Config loaded"
local dirtyAt, savedAt = nil, 0
local originals, samples, balls = {}, {}, {}
local draws, seen = {}, {}
local x,y,w,h = 110,100,700,505
local mouseX,mouseY,clicked,held = 0,0,false,false
local previousKeys, dragging, sliderDrag, binding = {}, nil,nil,nil
local lastMouse, lastScan, lastResize = false,-100,-100
local airborne, jumpY, jumpRoot = false,nil,nil
local setHeld, releaseAt, nextSet = false,0,0
local keyHeldCode = nil
local uiColor = {bg=Color3.fromRGB(15,18,27), panel=Color3.fromRGB(23,28,40),
    line=Color3.fromRGB(41,48,65), text=Color3.fromRGB(235,239,249), muted=Color3.fromRGB(145,156,177)}
local function save()
    local ok,err=pcall(function() writefile(CONFIG,Http:JSONEncode(cfg)) end)
    saveStatus=ok and "Saved locally" or "Save failed (file API unavailable)"
    if not ok then print("[VBL] "..tostring(err)) end
    dirtyAt=nil
    savedAt=os.clock()
end
local function set(key,value)
    if valid(key,value) and cfg[key] ~= value then cfg[key]=value; dirtyAt=os.clock() end
end
local function keyName(code)
    if code>=0x70 and code<=0x7B then return "F"..(code-0x6F) end
    if code>=48 and code<=90 then return string.char(code) end
    return ({[0x24]="Home",[0x2D]="Insert",[0x2E]="Delete",[0x20]="Space"})[code] or tostring(code)
end
local function releaseSet()
    if setHeld and keyHeldCode then pcall(keyrelease,keyHeldCode) end
    setHeld=false; keyHeldCode=nil
end
local function restoreSizes()
    for id,item in pairs(originals) do
        pcall(function() item.part.Size=item.size end)
        originals[id]=nil
    end
end
local function stop()
    if not running then return end
    running=false
    releaseSet(); restoreSizes()
    if dirtyAt then save() end
    pcall(function() setrobloxinput(true) end)
    for _,d in pairs(draws) do pcall(function() d:Remove() end) end
    draws={}
end
-- A second run replaces this version cleanly where the runtime shares globals.
if type(_G) == "table" then
    if type(_G.VBL_SCRIPT_STOP) == "function" then pcall(_G.VBL_SCRIPT_STOP) end
    _G.VBL_SCRIPT_STOP=stop
end
local function draw(id,kind,props)
    seen[id]=true
    local d=draws[id]
    if not d then d=Drawing.new(kind); draws[id]=d end
    for k,v in pairs(props) do d[k]=v end
    d.Visible=true
    return d
end
local function box(id,bx,by,bw,bh,color,z)
    return draw(id,"Square",{Position=Vector2.new(bx,by),Size=Vector2.new(bw,bh),
        Color=color,Filled=true,Transparency=1,ZIndex=z or 100})
end
local function text(id,value,tx,ty,size,color,z)
    return draw(id,"Text",{Text=value,Position=Vector2.new(tx,ty),Size=size or 14,
        Color=color or uiColor.text,Font=Drawing.Fonts.UI,Outline=false,Transparency=1,ZIndex=z or 103})
end
local function over(bx,by,bw,bh)
    return mouseX>=bx and mouseX<=bx+bw and mouseY>=by and mouseY<=by+bh
end
local function button(id,label,bx,by,bw,bh,action,active)
    local hover=over(bx,by,bw,bh)
    box(id,bx,by,bw,bh,active and palettes[cfg.accent] or (hover and uiColor.line or uiColor.panel),102)
    text(id.."t",label,bx+12,by+9,13,active and uiColor.bg or uiColor.text,103)
    if clicked and hover and not binding then action() end
end
local row=0
local function rowBase(title,description)
    local ry=y+100+row*59; row=row+1
    box("row"..row,x+174,ry,w-194,53,uiColor.panel,101)
    text("rowtitle"..row,title,x+188,ry+8,14)
    if description then text("rowdesc"..row,description,x+188,ry+29,11,uiColor.muted) end
    return ry
end
local function toggle(key,title,description)
    local ry=rowBase(title,description)
    button("toggle"..key,cfg[key] and "ON" or "OFF",x+w-92,ry+8,60,35,function()
        set(key,not cfg[key])
        if key=="resize" and not cfg.resize then restoreSizes() end
        if key=="autoSet" and not cfg.autoSet then releaseSet() end
    end,cfg[key])
end
local function choice(key,title,values)
    local ry=rowBase(title,cfg[key])
    button("choice"..key,"Change",x+w-114,ry+8,82,35,function()
        local index=1
        for i,v in ipairs(values) do if v==cfg[key] then index=i%#values+1 end end
        set(key,values[index])
    end)
end
local function slider(key,title,minimum,maximum,step,unit)
    local ry=rowBase(title,nil)
    local sx,sy,sw=x+190,ry+36,w-238
    text("value"..key,string.format(step<1 and "%.1f%s" or "%.0f%s",cfg[key],unit or ""),x+w-100,ry+8,13,palettes[cfg.accent])
    box("track"..key,sx,sy,sw,4,uiColor.line,102)
    local fraction=(cfg[key]-minimum)/(maximum-minimum)
    box("fill"..key,sx,sy,math.max(2,sw*fraction),4,palettes[cfg.accent],103)
    box("knob"..key,sx+sw*fraction-4,sy-4,8,12,uiColor.text,104)
    if clicked and over(sx-5,sy-8,sw+10,22) and not binding then sliderDrag=key end
    if sliderDrag==key and held then
        local f=math.max(0,math.min(1,(mouseX-sx)/sw))
        set(key,math.max(minimum,math.min(maximum,math.floor((minimum+(maximum-minimum)*f)/step+0.5)*step)))
    end
end
local function keybind(key,title)
    local ry=rowBase(title,binding==key and "Press a key; Escape cancels" or keyName(cfg[key]))
    button("bind"..key,"Rebind",x+w-114,ry+8,82,35,function() binding=key end)
end
local function rootPart(player)
    local char=player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function collectBalls()
    local found={}
    for _,model in ipairs(workspace:GetChildren()) do
        -- CLIENT_BALL_ is 12 characters. This is the source script's live-ball selector.
        if model:IsA("Model") and model.Name:sub(1,12)=="CLIENT_BALL_" and not model:FindFirstChildOfClass("Humanoid") then
            for _,part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then table.insert(found,part) end
            end
        end
    end
    balls=found
end
local function resizePart(part)
    local id=part.Address
    if not originals[id] then originals[id]={part=part,size=part.Size} end
    part.Size=Vector3.new(cfg.size,cfg.size,cfg.size)
end
local function resizeBalls()
    if not cfg.resize then return end
    for _,part in ipairs(balls) do pcall(resizePart,part) end
    local assets=game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
    local folder=assets and assets:FindFirstChild("Ball")
    if folder then
        for _,model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                for _,part in ipairs(model:GetDescendants()) do
                    if part:IsA("BasePart") then pcall(resizePart,part) end
                end
            end
        end
    end
end
local function project(v)
    local p,visible=WorldToScreen(v)
    if visible then return Vector2.new(p.X,p.Y) end
end
local function line(id,a,b,color,thickness)
    if not a or not b then return end
    draw(id,"Line",{From=a,To=b,Color=color,Thickness=thickness or cfg.thickness,Transparency=1,ZIndex=12})
end
local function arrow(id,a,b,color)
    if not a or not b then return end
    line(id,a,b,color)
    local dx,dy=b.X-a.X,b.Y-a.Y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<2 then return end
    local ux,uy=dx/length,dy/length
    local size=math.min(9,length/2)
    draw(id.."head","Triangle",{PointA=b,
        PointB=Vector2.new(b.X-ux*size-uy*size*0.5,b.Y-uy*size+ux*size*0.5),
        PointC=Vector2.new(b.X-ux*size+uy*size*0.5,b.Y-uy*size-ux*size*0.5),
        Filled=true,Color=color,Transparency=1,ZIndex=13})
end
local function landingTime(height,vy,gravity)
    if height<=0 then return 0 end
    return (vy+math.sqrt(vy*vy+2*gravity*height))/gravity
end
local function prediction(now)
    local active={}
    for _,ball in ipairs(balls) do
        pcall(function()
            local id=ball.Address
            active[id]=true
            local p=ball.Position
            local old=samples[id]
            samples[id]={p=p,t=now}
            if not cfg.predictor or not old then return end
            local dt=now-old.t
            if dt<0.005 or dt>0.3 then return end
            local v=(p-old.p)/dt
            if v.Magnitude<1 or v.Magnitude>350 then return end
            local duration=landingTime(p.Y-cfg.ground,v.Y,cfg.gravity)
            if duration<=0 or duration>15 then return end
            local color=palettes[cfg.predictionColor]
            local function at(t)
                return Vector3.new(p.X+v.X*t,p.Y+v.Y*t-0.5*cfg.gravity*t*t,p.Z+v.Z*t)
            end
            local landing=project(at(duration))
            if landing then
                draw("landing"..id,"Circle",{Position=landing,Radius=cfg.marker,NumSides=32,
                    Filled=false,Thickness=2,Color=color,Transparency=1,ZIndex=15})
                text("landtime"..id,string.format("%.1fs",duration),landing.X+cfg.marker+5,landing.Y,12,color,15)
            end
            for i=1,cfg.segments do
                local a,b=project(at(duration*(i-1)/cfg.segments)),project(at(duration*i/cfg.segments))
                if cfg.trajectory=="Arrows" then arrow("path"..id..":"..i,a,b,color)
                else line("path"..id..":"..i,a,b,color) end
            end
        end)
    end
    for id in pairs(samples) do if not active[id] then samples[id]=nil end end
end
local function facingLines()
    if not cfg.los then return end
    for _,player in ipairs(Players:GetPlayers()) do
        local ok,err=pcall(function()
            local isLocal=player.Address==LocalPlayer.Address
            local sameTeam=player.Team and LocalPlayer.Team and player.Team.Address==LocalPlayer.Team.Address
            if isLocal and not cfg.localPlayer then return end
            if not isLocal and ((sameTeam and not cfg.teammates) or (not sameTeam and not cfg.opponents)) then return end
            local root=rootPart(player)
            local head=player.Character and player.Character:FindFirstChild("Head")
            if not root or not head then return end
            local frame=root.CFrame
            assert(frame and frame.LookVector,"LOS needs BasePart.CFrame support")
            local start=head.Position
            local finish=start+frame.LookVector*cfg.length
            arrow("los"..player.Address,project(start),project(finish),palettes[(isLocal or sameTeam) and cfg.teamColor or cfg.enemyColor])
        end)
        if not ok then status="LOS unavailable: this runtime lacks BasePart.CFrame" end
    end
end
local function jumpRotation(root)
    if not root then airborne=false; jumpRoot=nil; return end
    if root.Address~=jumpRoot then airborne=false; jumpY=nil; jumpRoot=root.Address end
    if not cfg.rotation then airborne=false; return end
    local p,vy=root.Position,root.Velocity.Y
    local justJumped=false
    if not airborne and vy>5 then airborne=true; jumpY=p.Y; justJumped=true end
    if airborne and jumpY and p.Y<=jumpY+0.5 and math.abs(vy)<2 then airborne=false end
    if not airborne or (cfg.mode=="Snap" and not justJumped) then return end
    local ok=pcall(function()
        assert(root.CFrame,"Jump rotation needs BasePart.CFrame support")
        local camera=workspace.CurrentCamera.Position
        local dx,dz=p.X-camera.X,p.Z-camera.Z
        if dx*dx+dz*dz<0.001 then return end
        local angle=math.atan2(dx,dz)+math.pi
        local c,s=math.cos(angle),math.sin(angle)
        root.CFrame=CFrame.new(p.X,p.Y,p.Z,c,0,s,0,1,0,-s,0,c)
    end)
    if not ok then
        set("rotation",false)
        status="Jump rotation unavailable: this runtime lacks writable BasePart.CFrame"
    end
end
local function autoSet(now,root,active)
    if setHeld and (now>=releaseAt or not active or opened or not cfg.autoSet or not root) then releaseSet() end
    if not active or opened or not root or not cfg.autoSet or setHeld or now<nextSet then return end
    if type(keypress)~="function" or type(keyrelease)~="function" then
        set("autoSet",false); status="Auto set unavailable: input API missing"; return
    end
    local closest=math.huge
    for _,ball in ipairs(balls) do pcall(function() closest=math.min(closest,(ball.Position-root.Position).Magnitude) end) end
    if closest<=cfg.setDistance then
        -- Never release a physical key that the user was already holding.
        if iskeypressed(cfg.setKey) then return end
        keyHeldCode=cfg.setKey; setHeld=true
        local ok=pcall(keypress,keyHeldCode)
        if not ok then releaseSet(); status="Auto set input failed"; return end
        releaseAt=now+0.06; nextSet=now+cfg.cooldown
    end
end
local function renderMenu()
    if not opened then
        text("watermark","VBL / "..keyName(cfg.menuKey).." menu",18,18,14,palettes[cfg.accent],100)
        return
    end
    box("shadow",x+5,y+6,w,h,Color3.fromRGB(7,9,15),99)
    box("window",x,y,w,h,uiColor.bg,100)
    box("accent",x,y,w,3,palettes[cfg.accent],101)
    text("brand","VBL",x+20,y+18,26,palettes[cfg.accent])
    text("version","SCRIPT / 03",x+82,y+26,12,uiColor.muted)
    text("subtitle","COURT CONTROL",x+20,y+62,10,uiColor.muted)
    button("hide","Hide",x+w-158,y+17,66,34,function() opened=false; releaseSet(); pcall(setrobloxinput,true) end)
    button("stop","Stop",x+w-82,y+17,62,34,stop)
    if not running then return end
    local pages={"Ball","Movement","Prediction","LOS","Assist","Settings"}
    for i,name in ipairs(pages) do
        button("nav"..name,name,x+16,y+99+(i-1)*47,140,38,function() page=name; sliderDrag=nil end,page==name)
    end
    text("pagetitle",page,x+183,y+67,20)
    row=0
    if page=="Ball" then
        toggle("resize","Ball resizer","Live balls + replicated ball templates")
        slider("size","Ball size",0.1,30,0.1," studs")
        rowBase("Restore on disable","Original sizes restored when disabled or stopped")
        rowBase("Live ball parts",tostring(#balls).." detected in this server")
    elseif page=="Movement" then
        toggle("rotation","Jump rotation","Faces away from camera during a jump")
        choice("mode","Rotation mode",{"Snap","Free"})
        rowBase("Snap / Free","Snap once at takeoff / continuously follow camera")
        rowBase("Runtime compatibility","Requires writable BasePart.CFrame; no raw memory writes")
    elseif page=="Prediction" then
        toggle("predictor","Ball landing prediction","Estimated path from measured ball motion")
        choice("trajectory","Trajectory style",{"Line","Arrows"})
        slider("segments","Path segments",3,24,1)
        slider("marker","Landing circle radius",4,40,1," px")
        slider("gravity","Prediction gravity",1,200,1)
        slider("ground","Court floor Y",-100,100,0.5)
    elseif page=="LOS" then
        toggle("los","Player direction indicator","Facing arrows; does not test wall visibility")
        toggle("localPlayer","Show yourself")
        toggle("teammates","Show teammates")
        toggle("opponents","Show opponents")
        slider("length","Direction length",3,30,1," studs")
        slider("thickness","Line thickness",1,6,1," px")
    elseif page=="Assist" then
        toggle("autoSet","Auto set / receive","Presses the set key when a ball is close")
        slider("setDistance","Trigger distance",1,20,0.5," studs")
        slider("cooldown","Input cooldown",0.2,2,0.1," sec")
        keybind("setKey","Set / receive key")
        rowBase("Focus protection","Paused while this menu is open or Roblox is unfocused")
    else
        keybind("menuKey","Menu toggle key")
        choice("accent","Menu accent",{"Violet","Cyan","Green","Rose"})
        choice("predictionColor","Prediction color",{"Cyan","Violet","Green","Rose"})
        choice("teamColor","Teammate color",{"Green","Cyan","Violet","Rose"})
        choice("enemyColor","Opponent color",{"Rose","Cyan","Violet","Green"})
        local ry=rowBase("Configuration",saveStatus)
        button("save","Save",x+w-180,ry+8,66,35,save)
        button("reset","Reset",x+w-104,ry+8,72,35,function()
            releaseSet(); restoreSizes()
            for k,v in pairs(defaults) do cfg[k]=v end
            save(); status="Defaults restored"
        end)
    end
    box("footer",x+16,y+h-33,w-32,1,uiColor.line,102)
    text("status",status:sub(1,96),x+20,y+h-23,11,uiColor.muted)
end
local function frame()
    local now=os.clock()
    local active=isrbxactive()
    seen={}
    local keyEdges={}
    for code=8,255 do
        local pressed=iskeypressed(code)
        keyEdges[code]=pressed and not previousKeys[code]
        previousKeys[code]=pressed
    end
    local mouse=LocalPlayer:GetMouse()
    mouseX,mouseY=mouse.X,mouse.Y
    held=ismouse1pressed()
    clicked=active and held and not lastMouse
    lastMouse=held
    if not held then dragging=nil; sliderDrag=nil end
    if active then
        if binding then
            for code=8,255 do
                if keyEdges[code] then
                    if code~=0x1B then set(binding,code) end
                    binding=nil; break
                end
            end
        elseif keyEdges[cfg.menuKey] then
            opened=not opened; dragging=nil; sliderDrag=nil
            releaseSet(); pcall(setrobloxinput,not opened)
        end
        if opened and clicked and over(x,y+3,w-180,52) then dragging={mouseX-x,mouseY-y} end
        if dragging and held then x=math.max(0,mouseX-dragging[1]); y=math.max(0,mouseY-dragging[2]) end
    else
        dragging=nil; sliderDrag=nil; binding=nil
        releaseSet()
    end
    if now-lastScan>=0.5 then collectBalls(); lastScan=now end
    if now-lastResize>=0.2 then resizeBalls(); lastResize=now end
    local root=rootPart(LocalPlayer)
    if active then
        prediction(now); facingLines()
        if not opened then jumpRotation(root) end
        renderMenu()
    end
    if not running then return end
    autoSet(now,root,active)
    for id,d in pairs(draws) do
        if not seen[id] then d:Remove(); draws[id]=nil end
    end
    if dirtyAt and now-dirtyAt>=0.35 and now-savedAt>=0.5 then save() end
end
assert(type(Drawing)=="table" and type(iskeypressed)=="function","VBL requires Matcha drawing and input APIs")
pcall(setrobloxinput,false)
task.spawn(function()
    while running do
        local ok,err=pcall(frame)
        if not ok then
            print("[VBL] Stopped: "..tostring(err))
            stop()
            break
        end
        task.wait(0.016)
    end
end)
-- Local test seam / useful handle for runtimes that retain loadstring return values.
return {Stop=stop,Settings=cfg,Set=set,Frame=frame,LandingTime=landingTime}

