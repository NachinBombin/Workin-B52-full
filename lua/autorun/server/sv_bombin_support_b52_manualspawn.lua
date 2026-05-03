if not SERVER then return end

util.AddNetworkString("BombinSupportB52_ManualSpawn")

net.Receive("BombinSupportB52_ManualSpawn", function(len, ply)
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

    if not scripted_ents.GetStored("ent_bombin_support_b52") then
        ply:PrintMessage(HUD_PRINTCENTER, "[Bombin B-52] Entity not registered!")
        return
    end

    local b52 = ents.Create("ent_bombin_support_b52")
    if not IsValid(b52) then
        ply:PrintMessage(HUD_PRINTCENTER, "[Bombin B-52] Spawn failed!")
        return
    end

    b52:SetPos(centerPos)
    b52:SetAngles(callDir:Angle())
    b52:SetVar("CenterPos",    centerPos)
    b52:SetVar("CallDir",      callDir)
    b52:SetVar("Lifetime",     GetConVar("npc_bombinb52_lifetime"):GetFloat())
    b52:SetVar("Speed",        GetConVar("npc_bombinb52_speed"):GetFloat())
    b52:SetVar("OrbitRadius",  GetConVar("npc_bombinb52_radius"):GetFloat())
    b52:SetVar("SkyHeightAdd", GetConVar("npc_bombinb52_height"):GetFloat())
    b52:Spawn()
    b52:Activate()

    ply:PrintMessage(HUD_PRINTCENTER, "[Bombin B-52] B-52 Stratofortress inbound!")
end)
