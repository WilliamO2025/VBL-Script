-- VBL rotation diagnostic: reads only; never writes game memory or properties.
-- Saves its report to vbl_rotation_diagnostic.txt when writefile is available.
local lines={"VBL ROTATION DIAGNOSTIC 2", "Read-only checks; no rotation or input injection."}
local function report(s) lines[#lines+1]=s; print("[VBL diagnostic] "..s) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vector(v)
    return v and finite(v.X) and finite(v.Y) and finite(v.Z)
end
local function probe(name,fn)
    local ok,v=pcall(fn)
    if not ok then report(name..": unavailable"); return nil end
    if v==nil then report(name..": nil"); return nil end
    local isVector=pcall(function() assert(vector(v)) end)
    report(name..": "..(isVector and string.format("%.3f, %.3f, %.3f",v.X,v.Y,v.Z) or tostring(v)))
    return v
end
report("VERSION 2")
local ok,err=pcall(function()
    if type(identifyexecutor)=="function" then probe("Runtime",function() return identifyexecutor() end) end
    local player=game:GetService("Players").LocalPlayer
    local character=player and player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    assert(root,"Character root missing; enter a match and run again")
    local humanoid=character:FindFirstChildOfClass("Humanoid")
    local position=probe("Root.Position",function() return root.Position end)
    probe("Root.Velocity",function() return root.Velocity end)
    probe("Root.Rotation",function() return root.Rotation end)
    probe("Root.Orientation",function() return root.Orientation end)
    probe("Root.CFrame.Position",function() return root.CFrame.Position end)
    local look=probe("Root.CFrame.LookVector",function() return root.CFrame.LookVector end)
    probe("Humanoid.FloorMaterial",function() return humanoid.FloorMaterial end)
    probe("Humanoid.AutoRotate",function() return humanoid.AutoRotate end)
    report("memory_read exposed: "..tostring(type(memory_read)=="function"))
    report("memory_write exposed: "..tostring(type(memory_write)=="function").." (NOT called)")
    if type(memory_read)~="function" then return end
    assert(vector(position) and vector(look),"Position/facing unavailable; cannot match a transform")
    local reads,pointers,matches=0,0,0
    local function read(kind,address)
        reads=reads+1
        assert(reads<=20000,"Read budget reached")
        return memory_read(kind,address)
    end
    local function pointer(n)
        return finite(n) and n>=65536 and n<2^47 and n%8==0
    end
    local function matrixAt(address,currentLook)
        local m={}
        for i=1,9 do
            m[i]=read("float",address+(i-1)*4)
            if not finite(m[i]) or math.abs(m[i])>1.01 then return false end
        end
        for row=0,2 do
            local length=0
            for k=1,3 do length=length+m[row*3+k]^2 end
            if math.abs(length-1)>0.03 then return false end
            for other=row+1,2 do
                local dot=0
                for k=1,3 do dot=dot+m[row*3+k]*m[other*3+k] end
                if math.abs(dot)>0.03 then return false end
            end
        end
        local determinant=m[1]*(m[5]*m[9]-m[6]*m[8])-m[2]*(m[4]*m[9]-m[6]*m[7])+m[3]*(m[4]*m[8]-m[5]*m[7])
        return math.abs(determinant-1)<0.05 and
            math.max(math.abs(m[3]+currentLook.X),math.abs(m[6]+currentLook.Y),math.abs(m[9]+currentLook.Z))<0.03
    end
    local oldOK,old=pcall(read,"uintptr_t",root.Address+328)
    report("Old pointer read: "..(not oldOK and "raised error" or
        (pointer(old) and "plausible pointer" or ("invalid (type="..type(old)..", zero="..tostring(old==0)..")"))))
    if not oldOK then report("Memory reads blocked; check Matcha Unsafe Luau setting"); return end
    report("Bounded read-only search starting; remain still until END")
    -- Search only pointer slots near this root and a bounded region behind them.
    -- A matching pose is a candidate, never authorization to write to that address.
    for pointerOffset=128,768,8 do
        local ptrOK,base=pcall(read,"uintptr_t",root.Address+pointerOffset)
        if ptrOK and pointer(base) then
            pointers=pointers+1
            local currentPosition=root.Position
            local currentLook=root.CFrame.LookVector
            if math.max(math.abs(currentPosition.X-position.X),math.abs(currentPosition.Y-position.Y),math.abs(currentPosition.Z-position.Z))>0.1 then
                report("Character moved; restart while standing still"); return
            end
            for positionOffset=36,768,4 do
                local success,matched=pcall(function()
                    local px=read("float",base+positionOffset)
                    if not finite(px) or math.abs(px-currentPosition.X)>0.05 then return false end
                    local py=read("float",base+positionOffset+4)
                    local pz=read("float",base+positionOffset+8)
                    if not finite(py) or not finite(pz) or math.abs(py-currentPosition.Y)>0.05
                        or math.abs(pz-currentPosition.Z)>0.05 then return false end
                    return matrixAt(base+positionOffset-36,currentLook)
                end)
                if success and matched then
                    matches=matches+1
                    report(string.format("Candidate %d: root pointer +0x%X; rotation +0x%X; position +0x%X; pose matches",
                        matches,pointerOffset,positionOffset-36,positionOffset))
                end
                if reads>=20000 then report("Read budget reached; stopping"); return end
            end
        end
        if task and type(task.wait)=="function" then task.wait() end
    end
    report(string.format("Search complete: %d plausible pointers, %d reads, %d pose candidates",pointers,reads,matches))
    if pointers==0 then report("No readable pointers: memory access may be disabled or this layout differs") end
    if matches>0 then report("Pose matches are NOT verified write targets; movement correlation is still needed") end
end)
if not ok then report("Check stopped: "..tostring(err)) end
report("END. Readability does not prove writability. No game state changed.")
if type(writefile)=="function" then
    local saved=pcall(writefile,"vbl_rotation_diagnostic.txt",table.concat(lines,"\n"))
    print(saved and "[VBL diagnostic] Report saved: vbl_rotation_diagnostic.txt" or "[VBL diagnostic] Could not save; use console output")
end