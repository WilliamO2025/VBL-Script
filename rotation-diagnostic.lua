-- VBL rotation diagnostic: reads only; never writes game memory or properties.
-- Saves its report to vbl_rotation_diagnostic.txt when writefile is available.
local lines={"VBL ROTATION DIAGNOSTIC 1", "Read-only checks; no rotation or input injection."}
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
    -- Historical source candidates ONLY. A plausible result is not a verified write address.
    -- No scanning and no pointer values are included in the report.
    local readOK,primitive=pcall(memory_read,"uintptr_t",root.Address+328)
    if not readOK then report("Historical pointer read blocked/unavailable"); return end
    if not finite(primitive) or primitive<65536 or primitive>=2^47 or primitive%8~=0 then
        report("Historical pointer candidate invalid; no further reads"); return
    end
    for _,offset in ipairs({192,264}) do
        local success,result=pcall(function()
            local m={}
            for i=1,9 do
                m[i]=memory_read("float",primitive+offset+(i-1)*4)
                assert(finite(m[i]) and math.abs(m[i])<=1.01,"not a rotation matrix")
            end
            for row=0,2 do
                local n=0
                for k=1,3 do n=n+m[row*3+k]^2 end
                assert(math.abs(n-1)<0.03,"row length invalid")
                for other=row+1,2 do
                    local d=0
                    for k=1,3 do d=d+m[row*3+k]*m[other*3+k] end
                    assert(math.abs(d)<0.03,"rows not orthogonal")
                end
            end
            local determinant=m[1]*(m[5]*m[9]-m[6]*m[8])-m[2]*(m[4]*m[9]-m[6]*m[7])+m[3]*(m[4]*m[8]-m[5]*m[7])
            assert(math.abs(determinant-1)<0.05,"determinant invalid")
            local description="matrix plausible"
            local compareOK,difference=pcall(function()
                assert(vector(look))
                return math.max(math.abs(m[3]+look.X),math.abs(m[6]+look.Y),math.abs(m[9]+look.Z))
            end)
            if compareOK then description=description..string.format("; look difference %.4f",difference) end
            -- Test, do not assume, whether the following floats represent position.
            local positionOK,distance=pcall(function()
                assert(vector(position))
                local px=memory_read("float",primitive+offset+36)
                local py=memory_read("float",primitive+offset+40)
                local pz=memory_read("float",primitive+offset+44)
                assert(finite(px) and finite(py) and finite(pz))
                return math.sqrt((px-position.X)^2+(py-position.Y)^2+(pz-position.Z)^2)
            end)
            if positionOK then description=description..string.format("; adjacent position difference %.3f",distance) end
            return description
        end)
        report("Historical matrix "..offset..": "..(success and result or "not validated"))
    end
end)
if not ok then report("Check stopped: "..tostring(err)) end
report("END. Readability does not prove writability. No game state changed.")
if type(writefile)=="function" then
    local saved=pcall(writefile,"vbl_rotation_diagnostic.txt",table.concat(lines,"\n"))
    print(saved and "[VBL diagnostic] Report saved: vbl_rotation_diagnostic.txt" or "[VBL diagnostic] Could not save; use console output")
end