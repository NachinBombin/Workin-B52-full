if not SERVER then return end

util.AddNetworkString("BombinB52_ManualSpawn")

net.Receive("BombinB52_ManualSpawn", function(len, ply)
    if not IsValid(ply) then return end

    local tr = util.TraceLine({
        start  = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 3000,
        filter = ply,
    })

    local centerPos = tr.Hit and tr.HitPos or (ply:GetPos() + Vector(0, 0, 100))
    local callDir   = ply:EyeAngles():Forward()
    callDir.z = 0
    if callDir:LengthSqr() <= 1 then callDir = Vector(1, 0, 0) end
    callDir:Normalize()

    if not scripted_ents.GetStored("ent_bombin_b52") then
        ply:PrintMessage(HUD_PRINTCENTER, "[Bombin B-52] Entity not registered!")
        return
    end

    local uav = ents.Create("ent_bombin_b52")
    if not IsValid(uav) then
        ply:PrintMessage(HUD_PRINTCENTER, "[Bombin B-52] Spawn failed!")
        return
    end

    uav:SetPos(centerPos)
    uav:SetAngles(callDir:Angle())
    uav:SetVar("CenterPos",    centerPos)
    uav:SetVar("CallDir",      callDir)
    uav:SetVar("Lifetime",     GetConVar("npc_bombinb52_lifetime"):GetFloat())
    uav:SetVar("Speed",        GetConVar("npc_bombinb52_speed"):GetFloat())
    uav:SetVar("OrbitRadius",  GetConVar("npc_bombinb52_radius"):GetFloat())
    uav:SetVar("SkyHeightAdd", GetConVar("npc_bombinb52_height"):GetFloat())
    uav:Spawn()
    uav:Activate()

    ply:PrintMessage(HUD_PRINTCENTER, "[Bombin B-52] B-52 inbound!")
end)
