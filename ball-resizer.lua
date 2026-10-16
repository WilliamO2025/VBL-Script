-- VBL Script v8: readable, standalone Matcha drawing GUI.
-- Feature reference: 0x1cx/random-lua revision a46fe389 (April 3 2026).
-- Resizer behavior also based on Luna7070/585438 v1.2/v2.0. Original hitbox credit: huss.
-- No remote code or executable config. Rotation uses validated, rotation-only memory writes.
-- Layout candidates observed in the user's Matcha diagnostic; checked against live pose before use.
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Http = game:GetService("HttpService")
local Replicated = game:GetService("ReplicatedStorage")
local CONFIG = "vbl_script_config.json"
local defaults = {
    size = 5.5, resize = false, rotation = false, mode = "Snap",
    predictor = false, trajectory = "Line", segments = 12, marker = 16,
    gravity = 17, ground = -5, los = false, localPlayer = true,
    teammates = true, opponents = true, length = 10, thickness = 2,
    autoSet = false, setDistance = 5, setKey = 0x51, cooldown = 0.5,
    menuKey = 0x70, accent = "Violet", predictionColor = "Cyan",
    teamColor = "Green", enemyColor = "Rose",
    receiveHitbox = false, receiveScale = 1.5,
    receiveAction = "Bump", counter = false, counterKey = 0x45,
    counterReach = 4, counterSpeed = 25, counterLead = 40,
    counterMode = "Always", receiveFilter = "Serves / spikes", attackSpeed = 25,
    ballTracker = false, incomingIndicator = false,
}
local limits = {
    size={0.1,30}, segments={3,24}, marker={4,40}, gravity={1,200}, ground={-100,100},
    length={3,30}, thickness={1,6}, setDistance={1,20}, cooldown={0.2,2},
    menuKey={5,255}, setKey={5,255}, receiveScale={1,5},
    counterKey={5,255}, attackSpeed={5,150}, counterReach={1,10}, counterSpeed={5,150}, counterLead={0,150},
}
local palettes = {
    Violet=Color3.fromRGB(167,139,250), Cyan=Color3.fromRGB(65,210,230),
    Green=Color3.fromRGB(79,222,155), Rose=Color3.fromRGB(251,113,133),
}
local options = {mode={"Snap","Free"}, trajectory={"Line","Arrows"}, receiveAction={"Set","Bump"},
    counterMode={"Always","Toggle","Hold"}, receiveFilter={"Serves / spikes","Enemy returns"}}
local cfg = {}
local function valid(key, value)
    if type(value) ~= type(defaults[key]) then return false end
    if type(value) == "number" then
        local range = limits[key]
        if (key=="menuKey" or key=="setKey" or key=="counterKey") and (value==7 or value%1~=0) then return false end
        return value == value and range and value >= range[1] and value <= range[2]
            and ((key ~= "menuKey" and key ~= "setKey" and key ~= "counterKey" and key ~= "segments") or value % 1 == 0)
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
local originals, balls = {}, {}
local draws, seen = {}, {}
local x,y,w,h = 110,100,700,565
local mouseX,mouseY,clicked,held = 0,0,false,false
local previousKeys, dragging, sliderDrag, binding = {}, nil,nil,nil
local lastMouse, lastScan, lastResize = false,-100,-100
local airborne, jumpRoot = false,nil
local lastRotation, rotationDone = 0,false
local previousJumpY = nil
local rotationStatus = "Waiting for a jump; hide the menu to activate"
local resizeStatus = "Disabled"
local receiveOriginals, receiveTargets = {},{}
local groundStatus = "Checking ground contact"
local setHeld, releaseAt, nextSet = false,0,0
local keyHeldCode = nil
local mouseHeld, inputMode = false,nil
local assistBalls, motion = {},{}
local match = {gate="Waiting for ball data"}
local trackedRoot=nil
local serveState={}
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
    return ({[5]="Mouse 4",[6]="Mouse 5",[0x24]="Home",[0x2D]="Insert",[0x2E]="Delete",[0x20]="Space"})[code] or tostring(code)
end
local function releaseSet()
    if setHeld and keyHeldCode then pcall(keyrelease,keyHeldCode) end
    if mouseHeld then pcall(mouse1release) end
    mouseHeld=false; inputMode=nil
    setHeld=false; keyHeldCode=nil
end
local function restoreSizes()
    for id,item in pairs(originals) do
        pcall(function() item.part.Size=item.size end)
        originals[id]=nil
    end
end
local function restoreReceiveHitbox()
    for id,item in pairs(receiveOriginals) do
        pcall(function() item.part.Size=item.size end)
        receiveOriginals[id]=nil
    end
end
local function stop()
    if not running then return end
    running=false
    releaseSet(); restoreSizes(); restoreReceiveHitbox()
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
        if key=="receiveHitbox" and not cfg.receiveHitbox then restoreReceiveHitbox() end
        if (key=="autoSet" or key=="counter") and not cfg[key] then releaseSet() end
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
    local ry=rowBase(title,binding==key and "Press key or side button; Escape cancels" or keyName(cfg[key]))
    button("bind"..key,"Rebind",x+w-114,ry+8,82,35,function() binding=key end)
end
local function rootPart(player)
    local char=player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function humanoid()
    local char=LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end
local function isGrounded(root)
    if not root then groundStatus="No character"; return nil end
    local human=humanoid()
    local ok,contact=pcall(function()
        if not human then return nil end
        local material=human.FloorMaterial
        if material==nil then return nil end
        local name=tostring(material)
        if name=="Air" or name=="Enum.Material.Air" or material==0 then return false end
        -- Accept known enum/numeric material values, not arbitrary unsupported return values.
        if type(material)=="number" then return material>0 end
        if name:match("^Enum%.Material%.") then return true end
        return nil
    end)
    if ok and contact~=nil then
        groundStatus=contact and "Grounded" or "Airborne"
        return contact
    end
    -- A filtered ray is the fallback; zero vertical speed alone is never ground evidence.
    ok,contact=pcall(function()
        assert(RaycastParams and Enum,"Ground detection APIs unavailable")
        local char=LocalPlayer.Character
        local bottom=nil
        for _,name in ipairs({"LeftFoot","RightFoot","Left Leg","Right Leg"}) do
            local foot=char:FindFirstChild(name)
            if foot then
                local footBottom=foot.Position.Y-foot.Size.Y/2
                bottom=bottom and math.min(bottom,footBottom) or footBottom
            end
        end
        assert(bottom,"No feet found for ground detection")
        local p=root.Position
        local distance=p.Y-bottom+0.15
        assert(distance>0 and distance<15,"Invalid ground probe distance")
        local filter={char}
        for _,player in ipairs(Players:GetPlayers()) do
            if player.Character then table.insert(filter,player.Character) end
        end
        for _,ball in ipairs(balls) do table.insert(filter,ball) end
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances=filter
        params.RespectCanCollide=true
        local hit=workspace:Raycast(p,Vector3.new(0,-distance,0),params)
        return hit~=nil and hit.Normal.Y>0.5
    end)
    if ok then groundStatus=contact and "Grounded (floor probe)" or "Airborne"; return contact end
    groundStatus="Ground detection unavailable; auto receive paused"
    return nil
end
local function canReceive(root,grounded)
    if grounded~=true or not root or iskeypressed(0x20) then return false end
    local ok,ready=pcall(function()
        local h=humanoid()
        if h then
            local jumpOK,jumping=pcall(function() return h.Jump end)
            if jumpOK and jumping==true then return false end
        end
        return math.abs(root.Velocity.Y)<2
    end)
    return ok and ready
end
local function updateReceiveHitbox()
    local char=LocalPlayer.Character
    local found,seenTargets={},{}
    if char then
        for _,part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                local name=part.Name:lower():gsub("[^a-z]","")
                local parent=part.Parent
                local parentName=parent and parent.Name:lower():gsub("[^a-z]","") or ""
                local match=name=="receivehitbox" or name=="receiverhitbox" or name=="receivinghitbox" or name=="bumphitbox"
                    or (name=="hitbox" and (parentName=="receive" or parentName=="receiving" or parentName=="bump"))
                if match then
                    table.insert(found,part)
                    seenTargets[part.Address]=true
                    if cfg.receiveHitbox then
                        pcall(function()
                            local id=part.Address
                            if not receiveOriginals[id] then receiveOriginals[id]={part=part,size=part.Size} end
                            part.Size=receiveOriginals[id].size*cfg.receiveScale
                        end)
                    end
                end
            end
        end
    end
    receiveTargets=found
    for id,item in pairs(receiveOriginals) do
        if not seenTargets[id] or not cfg.receiveHitbox then
            pcall(function() item.part.Size=item.size end)
            receiveOriginals[id]=nil
        end
    end
end
local function collectBalls()
    local found,representatives={},{}
    for _,model in ipairs(workspace:GetChildren()) do
        -- CLIENT_BALL_ is 12 characters. This is the source script's live-ball selector.
        if model:IsA("Model") and model.Name:sub(1,12)=="CLIENT_BALL_" and not model:FindFirstChildOfClass("Humanoid") then
            local first=nil
            for _,part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then table.insert(found,part); if not first or part.Address<first.Address then first=part end end
            end
            if first then table.insert(representatives,first) end
        end
    end
    balls=found
    assistBalls=representatives
end
local function resizePart(part)
    local id=part.Address
    if not originals[id] then originals[id]={part=part,size=part.Size} end
    part.Size=Vector3.new(cfg.size,cfg.size,cfg.size)
    local size=part.Size
    assert(math.abs(size.X-cfg.size)<0.01 and math.abs(size.Y-cfg.size)<0.01 and math.abs(size.Z-cfg.size)<0.01,"Size write not retained")
end
local function resizeBalls()
    if not cfg.resize then resizeStatus="Disabled"; return end
    local applied,failed=0,0
    local function apply(part)
        if pcall(resizePart,part) then applied=applied+1 else failed=failed+1 end
    end
    for _,part in ipairs(balls) do apply(part) end
    local assets=game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
    local folder=assets and assets:FindFirstChild("Ball")
    if folder then
        for _,model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                for _,part in ipairs(model:GetDescendants()) do
                    if part:IsA("BasePart") then apply(part) end
                end
            end
        end
    end
    resizeStatus=string.format("%d size writes verified | %d failed",applied,failed)
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
local function trajectoryAt(p,v,t)
    return p+v*t+Vector3.new(0,-0.5*cfg.gravity*t*t,0)
end
local function prediction(now)
    if not cfg.predictor then return end
    for _,ball in ipairs(assistBalls) do
        pcall(function()
            local id=ball.Address
            local m=motion[id]
            if not m or m.t~=now or not m.v or m.v.Magnitude<1 then return end
            local p,v=m.p,m.v
            local duration=landingTime(p.Y-cfg.ground,v.Y,cfg.gravity)
            if duration<=0 or duration>15 then return end
            local color=palettes[cfg.predictionColor]
            local function at(t) return trajectoryAt(p,v,t) end
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
local function ballOverlay(root,now)
    if not root or not (cfg.ballTracker or cfg.incomingIndicator) then return end
    for _,ball in ipairs(assistBalls) do
        pcall(function()
            local id=ball.Address
            local m=motion[id]
            local p=project(ball.Position)
            if not p then return end
            local relative=ball.Position-root.Position
            local label=string.format("Ball | %.1f studs",relative.Magnitude)
            local color=palettes[cfg.predictionColor]
            if m and m.t==now and m.v then
                label=label..string.format(" | %.0f studs/s",m.v.Magnitude)
                if cfg.incomingIndicator then
                    local v=m.v-root.Velocity
                    local approach=relative.X*v.X+relative.Y*v.Y+relative.Z*v.Z<0
                    label=label..(approach and " | APPROACHING" or " | MOVING AWAY")
                    color=palettes[approach and "Rose" or "Green"]
                end
            end
            draw("ballmarker"..id,"Circle",{Position=p,Radius=9,NumSides=24,Filled=false,
                Thickness=2,Color=color,Transparency=1,ZIndex=16})
            text("ballinfo"..id,label,p.X+14,p.Y-8,13,color,17)
        end)
    end
end
-- Candidate layout from the user's diagnostic, not blindly trusted offsets.
local rotationProbe=nil
local function rotationPose(root)
    assert(type(memory_read)=="function" and type(memory_write)=="function","Matcha memory APIs unavailable")
    local primitive=memory_read("uintptr_t",root.Address+0x180)
    assert(type(primitive)=="number" and primitive>=65536 and primitive<2^47 and primitive%8==0,"Rotation pointer unavailable")
    local p,look=root.Position,root.CFrame.LookVector
    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
    assert(p and look and finite(p.X) and finite(p.Y) and finite(p.Z) and finite(look.X) and finite(look.Y) and finite(look.Z),"Pose unavailable")
    for _,offset in ipairs({0xB0,0xF8}) do
        local m={}
        for i=1,9 do
            m[i]=memory_read("float",primitive+offset+(i-1)*4)
            assert(finite(m[i]) and math.abs(m[i])<=1.01,"Invalid rotation matrix")
        end
        for row=0,2 do
            local length=0
            for k=1,3 do length=length+m[row*3+k]^2 end
            assert(math.abs(length-1)<0.03,"Invalid rotation row")
            for other=row+1,2 do
                local dot=0
                for k=1,3 do dot=dot+m[row*3+k]*m[other*3+k] end
                assert(math.abs(dot)<0.03,"Invalid rotation basis")
            end
        end
        local det=m[1]*(m[5]*m[9]-m[6]*m[8])-m[2]*(m[4]*m[9]-m[6]*m[7])+m[3]*(m[4]*m[8]-m[5]*m[7])
        assert(math.abs(det-1)<0.05,"Invalid rotation determinant")
        assert(math.max(math.abs(m[3]+look.X),math.abs(m[6]+look.Y),math.abs(m[9]+look.Z))<0.08,"Facing data not synchronized")
        for i,axis in ipairs({"X","Y","Z"}) do
            local coordinate=memory_read("float",primitive+offset+36+(i-1)*4)
            assert(finite(coordinate) and math.abs(coordinate-p[axis])<0.15,"Position data not synchronized")
        end
    end
    return {root=root.Address,primitive=primitive,p=Vector3.new(p.X,p.Y,p.Z),look=Vector3.new(look.X,look.Y,look.Z)}
end
local function validateRotation(root)
    local ok,pose=pcall(rotationPose,root)
    if not ok then rotationProbe=nil; rotationStatus="Paused: "..tostring(pose):gsub("^.-:%d+: ",""):sub(1,60); return nil end
    local old=rotationProbe
    if old and old.root==pose.root and old.primitive==pose.primitive then
        pose.ready=old.ready or (pose.p-old.p).Magnitude>0.05 or (pose.look-old.look).Magnitude>0.05
    end
    -- Keep the first sample until enough movement is observed.
    if not old or old.root~=pose.root or old.primitive~=pose.primitive or pose.ready then rotationProbe=pose end
    if not pose.ready then rotationStatus="Validation: move or turn slightly, then jump"; return nil end
    return pose
end
local function jumpRotation(root,allowed,now)
    if not root or root.Address~=jumpRoot then
        airborne=false; rotationDone=false; previousJumpY=nil; rotationProbe=nil
        jumpRoot=root and root.Address or nil
    end
    if not root then rotationStatus="Waiting for character"; return end
    local currentY,vy=root.Position.Y,root.Velocity.Y
    local rising=previousJumpY and currentY-previousJumpY>0.01
    previousJumpY=currentY
    if not cfg.rotation or not allowed then
        airborne=false; rotationDone=false
        rotationStatus=not cfg.rotation and "Disabled" or "Paused: game not focused"
        return
    end
    -- Rotation follows observed ascent, independent of an unreliable ground probe.
    -- Requiring both upward velocity and displacement avoids rotating on a stale impulse.
    if vy<=1 then airborne=false; rotationDone=false
    elseif not airborne and vy>5 and rising then
        airborne=true; rotationDone=false; lastRotation=0
    end
    local pose=validateRotation(root)
    if not pose then return end
    if not airborne then
        rotationStatus=string.format("Validated | waiting for ascent (vertical speed %.1f)",vy)
        return
    end
    if cfg.mode=="Snap" and rotationDone then rotationStatus="Snap complete for this ascent"; return end
    if now-lastRotation<1/30 then return end
    local ok,err=pcall(function()
        -- Re-read and validate immediately before writing; never cache a respawn pointer.
        local checked=rotationPose(root)
        assert(checked.primitive==pose.primitive,"Character primitive changed")
        local liveRoot=rootPart(LocalPlayer)
        assert(liveRoot and liveRoot.Address==root.Address,"Character changed")
        local p=checked.p
        local camera=workspace.CurrentCamera.Position
        local dx,dz=p.X-camera.X,p.Z-camera.Z
        if dx*dx+dz*dz<0.001 then rotationStatus="Paused: camera directly above character"; return end
        local angle=math.atan2(dx,dz)+math.pi
        local heading=math.atan2(-checked.look.X,-checked.look.Z)
        local delta=(angle-heading+math.pi)%(2*math.pi)-math.pi
        if math.abs(delta)<math.rad(2) then rotationDone=true; rotationStatus="Validated | already facing target"; return end
        if cfg.mode=="Free" then
            local maxTurn=math.rad(360)*math.min(now-lastRotation,0.05)
            angle=heading+math.max(-maxTurn,math.min(maxTurn,delta))
        end
        local c,s=math.cos(angle),math.sin(angle)
        local matrix={c,0,s,0,1,0,-s,0,c}
        -- Only these 18 floats are writable. Adjacent positions and velocities are never written.
        for _,offset in ipairs({0xB0,0xF8}) do
            for i=1,9 do memory_write("float",checked.primitive+offset+(i-1)*4,matrix[i]) end
        end
        rotationDone=true
        rotationStatus="Rotation-only write ("..cfg.mode..")"
        lastRotation=now
    end)
    if not ok then
        set("rotation",false)
        rotationStatus=tostring(err):gsub("^.-:%d+: ",""):sub(1,70)
        status="Jump rotation unavailable; see Movement diagnostics"
        print("[VBL] Jump rotation: "..tostring(err))
    end
end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function attribute(object,name)
    local ok,value=pcall(function() return object:GetAttribute(name) end)
    if ok and (type(value)=="string" or type(value)=="number") and tostring(value)~="" and value~=0 then return value end
end
local function playerFor(value)
    if not value then return nil end
    for _,player in ipairs(Players:GetPlayers()) do
        local ok,found=pcall(function()
            local id=tonumber(value)
            return tostring(value)==player.Name or (id~=nil and id==player.UserId)
        end)
        if ok and found then return player end
    end
end
local function teamFor(player)
    if not player then return nil end
    local ok,name=pcall(function() return player.Team and player.Team.Name end)
    if ok and type(name)=="string" and name~="" then return name end
    -- This fallback path is present in the statically inspected older VBL source.
    ok,name=pcall(function()
        local info=Replicated:FindFirstChild("PlayerInfo")
        local record=info and info:FindFirstChild(player.Name)
        local team=record and record:FindFirstChild("Team")
        return team and team.Value
    end)
    if ok and type(name)=="string" and name~="" then return name end
end
local function readMatch()
    local hitter=attribute(Replicated,"LastHitter")
    local server=attribute(Replicated,"ServedByPlayer")
    local player=playerFor(hitter)
    local team=teamFor(player)
    local ownTeam=teamFor(LocalPlayer)
    local ownName=LocalPlayer.Name
    match={hitter=hitter,server=server,player=player,team=team,ownTeam=ownTeam,
        gate="Ready",shot="Unknown",source="ReplicatedStorage attributes"}
    if #assistBalls~=1 then match.gate="Paused: global hit data requires one live ball"
    elseif not hitter or not player then match.gate="Paused: LastHitter unresolved"
    elseif not team or not ownTeam then match.gate="Paused: team data unavailable"
    elseif player.Name==ownName or team==ownTeam then match.gate="Ignored: your team's last touch"
    else match.enemy=true end
    local servingPlayer=playerFor(server)
    local ballID=#assistBalls==1 and assistBalls[1].Address or nil
    local serverName=servingPlayer and servingPlayer.Name or server
    if serveState.server~=serverName or serveState.ball~=ballID then
        serveState={server=serverName,ball=ballID,returned=false}
    end
    if player and servingPlayer and player.Name~=servingPlayer.Name then serveState.returned=true end
    match.serve=match.enemy and not serveState.returned and servingPlayer and player
        and servingPlayer.Name==player.Name or false
end
local function trackApproaches(now,root,active)
    local rootID=root and root.Address
    if trackedRoot~=rootID then motion={}; trackedRoot=rootID end
    readMatch()
    local seenBalls={}
    for _,ball in ipairs(assistBalls) do
        pcall(function()
            local id=ball.Address
            seenBalls[id]=true
            local m=motion[id] or {fired=false}
            local p=ball.Position
            local dt=m.t and now-m.t or 0
            local v=dt>=0.003 and dt<=0.12 and (p-m.p)/dt or nil
            if v and (v.Magnitude~=v.Magnitude or v.Magnitude>600) then v=nil end
            -- A new verified hitter or serve can rearm even during a rapid close rally.
            local token=tostring(match.player and match.player.Name or match.hitter)..":"..tostring(match.server)
            if m.token~=token then m.fired=false end
            m.token=token
            m.ready=active and m.active and v~=nil
            m.active=active; m.v=v; m.p=p; m.t=now; m.dt=dt
            if match.enemy and v then
                match.shot=match.serve and "Likely serve (inferred)" or
                    ((v.Magnitude>=cfg.attackSpeed and v.Y<=3) and "Fast attack (inferred)" or "Other enemy return")
            end
            if root and v and (p-root.Position).Magnitude>math.max(cfg.setDistance,cfg.counterReach)+6
                and dot(p-root.Position,v-root.Velocity)>0 then m.fired=false end
            motion[id]=m
        end)
    end
    for id in pairs(motion) do if not seenBalls[id] then motion[id]=nil end end
end
local function contactTime(r,v,reach,horizon)
    local speed2=dot(v,v)
    if speed2<0.01 or dot(r,v)>=0 then return nil end
    -- Closest point on the same ballistic path used by the visible predictor.
    local t=math.max(0,math.min(horizon,-dot(r,v)/speed2))
    local acceleration=Vector3.new(0,-cfg.gravity,0)
    for _=1,4 do
        local q=trajectoryAt(r,v,t)
        local tangent=v+acceleration*t
        local denominator=dot(tangent,tangent)+dot(q,acceleration)
        if denominator<=0.001 then break end
        t=math.max(0,math.min(horizon,t-dot(q,tangent)/denominator))
    end
    if trajectoryAt(r,v,t).Magnitude>reach*0.85 then return nil end
    if r.Magnitude<=reach then return 0 end
    local lo,hi=0,t
    for _=1,12 do
        local mid=(lo+hi)/2
        if trajectoryAt(r,v,mid).Magnitude<=reach then hi=mid else lo=mid end
    end
    return hi
end
local function autoSet(now,root,active,grounded)
    local receiving=cfg.autoSet and canReceive(root,grounded)
    local countering=cfg.counter and root and grounded==false
        and (cfg.counterMode~="Hold" or iskeypressed(cfg.counterKey))
    if setHeld and (now>=releaseAt or not active or opened or not match.enemy
        or (inputMode=="Receive" and not receiving) or (inputMode=="Counter" and not countering)) then releaseSet() end
    if not active or opened or not root or setHeld then return end
    if not receiving and not countering then return end
    if not match.enemy then return end
    if not countering and now<nextSet then return end
    local reach=countering and cfg.counterReach or cfg.setDistance
    local target=root.Position+Vector3.new(0,countering and 2 or 0,0)
    local lead=countering and cfg.counterLead/1000 or 0
    for _,ball in ipairs(assistBalls) do
        local m=motion[ball.Address]
        if m and m.t==now and m.v and m.ready and not m.fired then
            local r=m.p-target
            local v=m.v-root.Velocity
            local speed=m.v.Magnitude
            local spike=speed>=cfg.attackSpeed and m.v.Y<=3
            local eligible=countering and spike and not match.serve or (not countering and
                (cfg.receiveFilter=="Enemy returns" or match.serve or spike))
            match.shot=match.serve and "Likely serve (inferred)" or (spike and "Fast attack (inferred)" or "Other enemy return")
            local horizon=math.min(0.18,lead+math.min(m.dt,0.04))
            local eta=eligible and contactTime(r,v,reach,horizon) or nil
            local height=m.p.Y-root.Position.Y
            if eta and speed>=(countering and cfg.counterSpeed or 2)
                and (not countering or (height>=0.5 and height<=7)) then
                local useMouse=countering or cfg.receiveAction=="Bump"
                if useMouse then
                    if ismouse1pressed() then return end
                    if type(mouse1press)~="function" or type(mouse1release)~="function" then
                        status="Mouse assist unavailable: mouse input API missing"; return
                    end
                    mouseHeld=true; setHeld=true
                    if not pcall(mouse1press) then releaseSet(); status="Mouse input failed"; return end
                else
                    if iskeypressed(cfg.setKey) then return end
                    if type(keypress)~="function" or type(keyrelease)~="function" then
                        status="Set unavailable: keyboard input API missing"; return
                    end
                    keyHeldCode=cfg.setKey; setHeld=true
                    if not pcall(keypress,keyHeldCode) then releaseSet(); status="Set input failed"; return end
                end
                inputMode=countering and "Counter" or "Receive"
                m.fired=true; releaseAt=now+(countering and 0.016 or 0.04)
                if not countering then nextSet=now+cfg.cooldown end
                status=inputMode.." | "..tostring(match.hitter).." | "..match.shot
                return
            end
        end
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
    text("version","SCRIPT / 08",x+82,y+26,12,uiColor.muted)
    text("subtitle","COURT CONTROL",x+20,y+62,10,uiColor.muted)
    button("hide","Hide",x+w-158,y+17,66,34,function() opened=false; releaseSet(); pcall(setrobloxinput,true) end)
    button("stop","Stop",x+w-82,y+17,62,34,stop)
    if not running then return end
    local pages={"Ball","Character","Movement","Prediction","LOS","Assist","Counter","Match","Settings"}
    for i,name in ipairs(pages) do
        button("nav"..name,name,x+16,y+99+(i-1)*47,140,38,function() page=name; sliderDrag=nil end,page==name)
    end
    text("pagetitle",page,x+183,y+67,20)
    row=0
    if page=="Ball" then
        toggle("resize","Ball hitbox extender","Resizes live ball parts + replicated ball templates")
        slider("size","Ball size",0.1,30,0.1," studs")
        rowBase("Restore on disable","Original sizes restored when disabled or stopped")
        rowBase("Live ball parts",tostring(#balls).." detected in this server")
        rowBase("Size write verification",resizeStatus)
        toggle("ballTracker","Ball tracker","Ball marker, distance and measured speed")
        toggle("incomingIndicator","Incoming indicator","Approaching / moving away relative to your character")
    elseif page=="Character" then
        toggle("receiveHitbox","Receive hitbox resizer","Only identified receive/bump hitbox parts")
        slider("receiveScale","Hitbox scale",1,5,0.1,"x")
        rowBase("Detected receive hitboxes",#receiveTargets>0 and tostring(#receiveTargets).." part(s) found" or "None exposed by this character; resizing unavailable")
        rowBase("Local modification","Server-calculated receive range may remain unchanged")
        rowBase("Restore on disable","Original hitbox sizes restored on disable or Stop")
    elseif page=="Movement" then
        toggle("rotation","Jump rotation","Faces away from camera during a jump")
        choice("mode","Rotation mode",{"Snap","Free"})
        rowBase("Snap / Free","Once per ascent / limited turns while rising")
        rowBase("Runtime compatibility","Validated rotation memory; position / velocity never written")
        rowBase("Rotation diagnostics",rotationStatus)
        rowBase("Ground contact",groundStatus)
        rowBase("Jump detection","Upward velocity + rising position; works with menu open")
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
        toggle("autoSet","Auto receive",groundStatus)
        choice("receiveAction","Action: Set / Bump",{"Set","Bump"})
        slider("setDistance","Trigger distance",1,20,0.5," studs")
        slider("cooldown","Input cooldown",0.2,2,0.1," sec")
        keybind("setKey","Set key (Bump uses left click)")
        choice("receiveFilter","Receive filter",{"Serves / spikes","Enemy returns"})
        rowBase("Defense status",match.gate)
    elseif page=="Counter" then
        toggle("counter","Counter-spike assist", "Airborne + enemy fast attack; aim manually")
        choice("counterMode","Activation",{"Always","Toggle","Hold"})
        keybind("counterKey","Counter toggle / hold key")
        slider("counterReach","Counter reach",1,10,0.5," studs")
        slider("counterSpeed","Minimum incoming speed",5,150,1," studs/s")
        slider("counterLead","Prediction lead",0,150,5," ms")
        rowBase("Defense status",match.gate)
    elseif page=="Match" then
        rowBase("Your team",match.ownTeam or "Unavailable")
        rowBase("Last hitter",tostring(match.hitter or "Unavailable"))
        rowBase("Last hitter team",match.team or "Unavailable")
        rowBase("Server",tostring(match.server or "Unavailable"))
        rowBase("Shot estimate",match.shot)
        slider("attackSpeed","Fast attack minimum speed",5,150,1," studs/s")
        rowBase("Defense status",match.gate)
    else
        keybind("menuKey","Menu toggle key")
        choice("accent","Menu accent",{"Violet","Cyan","Green","Rose"})
        choice("predictionColor","Prediction color",{"Cyan","Violet","Green","Rose"})
        choice("teamColor","Teammate color",{"Green","Cyan","Violet","Rose"})
        choice("enemyColor","Opponent color",{"Rose","Cyan","Violet","Green"})
        local ry=rowBase("Configuration",saveStatus)
        button("save","Save",x+w-180,ry+8,66,35,save)
        button("reset","Reset",x+w-104,ry+8,72,35,function()
            releaseSet(); restoreSizes(); restoreReceiveHitbox()
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
    for code=5,255 do
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
            for code=5,255 do
                if keyEdges[code] then
                    if code~=0x1B then set(binding,code) end
                    binding=nil; break
                end
            end
        elseif keyEdges[cfg.menuKey] then
            opened=not opened; dragging=nil; sliderDrag=nil
            releaseSet(); pcall(setrobloxinput,true)
        end
        if not binding and not opened and cfg.counterMode=="Toggle" and keyEdges[cfg.counterKey]
            and cfg.counterKey~=cfg.menuKey then
            set("counter",not cfg.counter); releaseSet()
        end
        if opened and clicked and over(x,y+3,w-180,52) then dragging={mouseX-x,mouseY-y} end
        if dragging and held then x=math.max(0,mouseX-dragging[1]); y=math.max(0,mouseY-dragging[2]) end
    else
        dragging=nil; sliderDrag=nil; binding=nil
        releaseSet()
    end
    if now-lastScan>=0.1 then collectBalls(); lastScan=now end
    if now-lastResize>=0.2 then resizeBalls(); updateReceiveHitbox(); lastResize=now end
    local root=rootPart(LocalPlayer)
    local grounded=isGrounded(root)
    jumpRotation(root,active,now)
    trackApproaches(now,root,active and not opened)
    if active then
        prediction(now); facingLines(); ballOverlay(root,now)
        renderMenu()
    end
    if not running then return end
    autoSet(now,root,active,grounded)
    for id,d in pairs(draws) do
        if not seen[id] then d:Remove(); draws[id]=nil end
    end
    if dirtyAt and now-dirtyAt>=0.35 and now-savedAt>=0.5 then save() end
end
assert(type(Drawing)=="table" and type(iskeypressed)=="function","VBL requires Matcha drawing and input APIs")
-- The overlay stays interactive without disabling game input.
pcall(setrobloxinput,true)
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
return {Stop=stop,Settings=cfg,Set=set,Frame=frame,LandingTime=landingTime,Grounded=isGrounded,ContactTime=contactTime,Match=function() return match end}