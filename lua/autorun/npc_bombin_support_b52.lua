if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("BombinSupportB52_FlareSpawned")

    -- ============================================================
    -- ConVars
    -- ============================================================

    local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

    local cv_enabled  = CreateConVar("npc_bombinb52_enabled",   "1",    SHARED_FLAGS, "Enable/disable B-52 support calls")
    local cv_chance   = CreateConVar("npc_bombinb52_chance",    "0.08", SHARED_FLAGS, "Probability per check")
    local cv_interval = CreateConVar("npc_bombinb52_interval",  "20",   SHARED_FLAGS, "Seconds between NPC checks")
    local cv_cooldown = CreateConVar("npc_bombinb52_cooldown",  "120",  SHARED_FLAGS, "Cooldown per NPC after calling")
    local cv_max_dist = CreateConVar("npc_bombinb52_max_dist",  "4000", SHARED_FLAGS, "Max call distance")
    local cv_min_dist = CreateConVar("npc_bombinb52_min_dist",  "600",  SHARED_FLAGS, "Min call distance")
    local cv_delay    = CreateConVar("npc_bombinb52_delay",     "8",    SHARED_FLAGS, "Flare to B-52 arrival delay")
    local cv_life     = CreateConVar("npc_bombinb52_lifetime",  "90",   SHARED_FLAGS, "B-52 lifetime seconds")
    local cv_speed    = CreateConVar("npc_bombinb52_speed",     "280",  SHARED_FLAGS, "B-52 forward speed HU/s")
    local cv_radius   = CreateConVar("npc_bombinb52_radius",    "4000", SHARED_FLAGS, "Orbit radius HU")
    local cv_height   = CreateConVar("npc_bombinb52_height",    "7500", SHARED_FLAGS, "Altitude above ground HU")
    local cv_announce = CreateConVar("npc_bombinb52_announce",  "0",    SHARED_FLAGS, "Debug prints")

    -- ============================================================
    -- NPC classes that can call the B-52
    -- ============================================================

    local CALLERS = {
        ["npc_combine_s"]     = true,
        ["npc_metropolice"]   = true,
        ["npc_combine_elite"] = true,
    }

    -- ============================================================
    -- HELPERS
    -- ============================================================

    local function BSP_Debug(msg)
        if not cv_announce:GetBool() then return end
        local full = "[Bombin B-52] " .. tostring(msg)
        print(full)
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, full) end
        end
    end

    local function RandomFlatDir()
        local ang = math.Rand(0, 360)
        return Vector(math.cos(math.rad(ang)), math.sin(math.rad(ang)), 0)
    end

    local function CheckSkyAbove(pos)
        local tr = util.TraceLine({
            start  = pos + Vector(0, 0, 50),
            endpos = pos + Vector(0, 0, 1050),
        })
        if tr.Hit and not tr.HitSky then
            tr = util.TraceLine({
                start  = tr.HitPos + Vector(0, 0, 50),
                endpos = tr.HitPos + Vector(0, 0, 1000),
            })
        end
        return not (tr.Hit and not tr.HitSky)
    end

    local function ThrowSupportFlare(npc, targetPos)
        local npcEyePos = npc:EyePos()
        local toTarget  = (targetPos - npcEyePos):GetNormalized()

        local flare = ents.Create("ent_bombin_flare_blue")
        if not IsValid(flare) then
            BSP_Debug("Flare spawn failed")
            return nil
        end

        flare:SetPos(npcEyePos + toTarget * 52)
        flare:SetAngles(npc:GetAngles())
        flare:Spawn()
        flare:Activate()

        local dir  = targetPos - flare:GetPos()
        local dist = dir:Length()
        dir:Normalize()

        timer.Simple(0, function()
            if not IsValid(flare) then return end
            local phys = flare:GetPhysicsObject()
            if not IsValid(phys) then return end
            phys:SetVelocity(dir * 700 + Vector(0, 0, dist * 0.25))
            phys:Wake()
        end)

        net.Start("BombinSupportB52_FlareSpawned")
        net.WriteEntity(flare)
        net.Broadcast()

        BSP_Debug("Flare thrown")
        return flare
    end

    local function SpawnSupportB52AtPos(centerPos)
        if not scripted_ents.GetStored("ent_bombin_support_b52") then
            BSP_Debug("Entity ent_bombin_support_b52 not registered!")
            return false
        end

        local b52 = ents.Create("ent_bombin_support_b52")
        if not IsValid(b52) then
            BSP_Debug("B-52 ents.Create failed")
            return false
        end

        b52:SetPos(centerPos)
        b52:SetVar("CenterPos",    centerPos)
        b52:SetVar("CallDir",      RandomFlatDir())
        b52:SetVar("Lifetime",     cv_life:GetFloat())
        b52:SetVar("Speed",        cv_speed:GetFloat())
        b52:SetVar("OrbitRadius",  cv_radius:GetFloat())
        b52:SetVar("SkyHeightAdd", cv_height:GetFloat())
        b52:Spawn()
        b52:Activate()

        BSP_Debug("B-52 spawned at " .. tostring(centerPos))
        return true
    end

    local NpcCooldowns = {}

    local function TryNPCCall(npc)
        if not IsValid(npc) then return end
        local enemy = npc:GetEnemy()
        if not IsValid(enemy) then return end

        local npcPos   = npc:GetPos()
        local enemyPos = enemy:GetPos()
        local dist     = npcPos:Distance(enemyPos)

        if dist < cv_min_dist:GetFloat() or dist > cv_max_dist:GetFloat() then return end
        if not CheckSkyAbove(npcPos) then return end
        if math.random() > cv_chance:GetFloat() then return end

        local id = npc:EntIndex()
        if NpcCooldowns[id] and CurTime() < NpcCooldowns[id] then return end
        NpcCooldowns[id] = CurTime() + cv_cooldown:GetFloat()

        local centerPos = enemyPos
        ThrowSupportFlare(npc, enemyPos)

        timer.Simple(cv_delay:GetFloat(), function()
            SpawnSupportB52AtPos(centerPos)
        end)

        BSP_Debug(npc:GetClass() .. " called B-52 on " .. enemy:GetClass())
    end

    timer.Create("BombinB52_NPCCheck", cv_interval:GetFloat(), 0, function()
        if not cv_enabled:GetBool() then return end
        for _, npc in ipairs(ents.GetAll()) do
            if IsValid(npc) and npc:IsNPC() and CALLERS[npc:GetClass()] then
                TryNPCCall(npc)
            end
        end
        for id, _ in pairs(NpcCooldowns) do
            if not IsValid(Entity(id)) then NpcCooldowns[id] = nil end
        end
    end)
end
