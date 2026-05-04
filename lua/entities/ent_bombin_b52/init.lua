AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_trailsystem.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- The B-52 model's nose points along its LOCAL +X axis.
-- GMod's Angle(p,y,r):Forward() is the LOCAL +X direction when r=0,p=0.
-- With MODEL_YAW_OFFSET = -90, the visual nose aligns with flightYaw.
-- Because the model is rotated 90 degrees relative to GMod's angle convention:
--   - "bank"  (wing tilt)    maps to GMod Angle.p  (pitch channel)
--   - "pitch" (nose up/down) maps to GMod Angle.r  (roll channel)
-- Roll sign is NEGATIVE: turning right -> positive turnRate -> positive SmoothedRoll -> negative p -> right wing down. Correct.
-- So final angle: Angle( -SmoothedRoll, flightYaw+OFFSET, -SmoothedPitch )
local MODEL_YAW_OFFSET = -90

local ROLL_SUSTAINED_GAIN = 2.2
local ROLL_TRANSIENT_GAIN = 55.0
local ROLL_MAX            = 22.0
local ROLL_LERP_IN        = 0.08
local ROLL_LERP_OUT       = 0.012

local ENGINE_LOOP_SOUND  = "sound/b52/b52.wav"
local SOUNDS_ATGM_IGNITE = { "ATGM.wav", "ATGM2.wav", "ATGM3.wav", "ATGM4.wav" }
local SOUNDS_LAUNCH      = { "launch1.wav", "launch2.wav" }
local SOUND_ROCKET_IDLE  = "rocket_idle.wav"

-- ============================================================
-- WEAPON CATALOGUE
-- ============================================================
-- Each weapon entry drives a completely self-contained fire function.
-- Window system:
--   PEACEFUL (idle) window:   5-12 seconds  (no shooting)
--   ACTIVE   (weapon) window: driven per-weapon by its own shot sequence
--
-- Weapon IDs (string keys used in self.CurrentWeapon):
--   "massive"   -> W1: single huge bomb, terrible aim
--   "medium"    -> W2: 6 bombs from a random pool, per-shot scatter
--   "carpet"    -> W3: line of 8 x gb_bomb_250gp along flight path
--   "cluster"   -> W4: 10 cluster munitions scattered wide
--   "vikhr"     -> W5: ATGM (unchanged from original)

local CFG_MaxHP          = 450
local CFG_FadeDuration   = 3.0
local CFG_WeaponWindow   = 10   -- seconds per active weapon window
local CFG_PeacefulMin    = 5    -- minimum peaceful gap between windows
local CFG_PeacefulMax    = 12   -- maximum peaceful gap between windows

-- W1 - Massive ordnance
local CFG_MASSIVE_Bombs  = { "gb_bomb_1000gp", "gb_bomb_2000gp" }
local CFG_MASSIVE_Scatter = 2400   -- huge cone radius (units on ground)

-- W2 - Medium ordnance (6 bombs, each gets its own scatter)
local CFG_MEDIUM_Bombs   = { "gb_bomb_500gp", "gb_bomb_mk82", "gb_bomb_mk77" }
local CFG_MEDIUM_Count   = 6
local CFG_MEDIUM_Delay   = 0.55   -- seconds between each of the 6 drops
local CFG_MEDIUM_Scatter = 1400

-- W3 - Small ordnance: carpet line of gb_bomb_250gp
local CFG_CARPET_Count   = 8     -- bombs in the line
local CFG_CARPET_Delay   = 0.3   -- seconds between each bomb
local CFG_CARPET_Spacing = 900   -- distance between footprints along flight vector

-- W4 - Cluster
local CFG_CLUSTER_Bombs  = { "gb_bomb_cbu", "gb_bomb_cbubomblet" }
local CFG_CLUSTER_Count  = 10
local CFG_CLUSTER_Delay  = 0.25
local CFG_CLUSTER_Scatter = 1600

-- W5 - VIKHR ATGM (original, unchanged)
local CFG_VIKHR_Delay        = 4.0
local CFG_VIKHR_Count        = 2
local CFG_VIKHR_Scatter      = 60
local CFG_VIKHR_MuzzlePoints = { Vector(60,-70,-5), Vector(60,70,-5) }

-- Bomb bay drop origin (roughly center belly of the aircraft)
local CFG_BombBayLocal = Vector(0, 0, -35)

util.AddNetworkString("bombin_b52_damage_tier")

local function CalcTier(hp, maxHP)
    local f = hp / maxHP
    if f > 0.66 then return 0 elseif f > 0.33 then return 1 elseif f > 0 then return 2 else return 3 end
end
local function BroadcastTier(ent, tier)
    net.Start("bombin_b52_damage_tier") net.WriteUInt(ent:EntIndex(),16) net.WriteUInt(tier,2) net.Broadcast()
end

-- ============================================================
-- INITIALIZE
-- ============================================================
function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
    self.CallDir      = self:GetVar("CallDir",      Vector(1,0,0))
    self.Lifetime     = self:GetVar("Lifetime",     120)
    self.Speed        = self:GetVar("Speed",        260)
    self.OrbitRadius  = self:GetVar("OrbitRadius",  4200)
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 7000)

    self.MaxHP        = CFG_MaxHP
    self.FadeDuration = CFG_FadeDuration

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then ground = self.CenterPos.z end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    self.OrbitDirection = (math.random(2) == 1) and 1 or -1

    local right   = Vector(-self.CallDir.y, self.CallDir.x, 0)
    local tangent = Vector(right.x * self.OrbitDirection, right.y * self.OrbitDirection, 0)
    tangent:Normalize()

    local spawnOffset = tangent * (-self.OrbitRadius * math.Rand(0.55, 0.95))
    local spawnPos    = Vector(
        self.CenterPos.x + spawnOffset.x,
        self.CenterPos.y + spawnOffset.y,
        self.sky
    )
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
    end
    if not util.IsInWorld(spawnPos) then
        self:Debug("Spawn position out of world") self:Remove() return
    end

    self:SetModel("models/stuffs/boeingb52g/boeing_b52g_stratofortress.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
    self:SetPos(spawnPos)
    self:SetBodygroup(1, 1)
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255,255,255,0))

    self:SetNWInt("HP",    self.MaxHP)
    self:SetNWInt("MaxHP", self.MaxHP)

    self.flightYaw    = tangent:Angle().y
    self.PrevTurnRate = 0
    self.SmoothedRoll  = 0
    self.SmoothedPitch = 0
    self.ang = Angle(0, self.flightYaw + MODEL_YAW_OFFSET, 0)

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    self.AltDriftRange    = 500
    self.AltDriftLerp     = 0.001
    self.JitterPhase      = math.Rand(0, math.pi * 2)
    self.JitterAmplitude  = 8

    self.RadialGain  = 0.5
    self.MaxTurnRate = 28

    self.IsTumbling        = false
    self.TumbleStartTime   = 0
    self.TumbleGroundZ     = ground
    self.TumbleCrashed     = false
    self.TumbleVelocity    = Vector(0,0,0)
    self.TumbleAngVelocity = Vector(0,0,0)

    self.IsDestroyed = false
    self.DamageTier  = 0

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
        self.PhysObj:SetAngles(self.ang)
    end

    self.EngineLoop = CreateSound(self, ENGINE_LOOP_SOUND)
    if self.EngineLoop then
        self.EngineLoop:SetSoundLevel(80)
        self.EngineLoop:ChangePitch(100, 0)
        self.EngineLoop:ChangeVolume(1.0, 0)
        self.EngineLoop:Play()
    end

    -- Weapon state
    self.CurrentWeapon   = nil
    self.WeaponWindowEnd = 0
    self.IsPeaceful      = false   -- true = we're in a peaceful gap right now
    self.PeacefulUntil   = 0

    -- Per-weapon shot counters (reset by PickNewWeapon)
    self.WPN_ShotsFired  = 0
    self.WPN_NextShot    = 0
    self.WPN_MuzzleIndex = 1   -- used by VIKHR only

    self:Debug("B-52 spawned at "..tostring(spawnPos).." sky="..self.sky.." OrbitDir="..self.OrbitDirection)
end

-- ============================================================
-- DAMAGE
-- ============================================================
function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end
    local hp = self:GetNWInt("HP", self.MaxHP) - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)
    local tier = CalcTier(hp, self.MaxHP)
    if tier ~= self.DamageTier then self.DamageTier = tier BroadcastTier(self, tier) end
    if hp <= 0 then self:DestroyUAV() end
end

function ENT:StartTumble()
    self.IsTumbling = true  self.TumbleStartTime = CurTime()  self.TumbleCrashed = false
    local gnd = self:FindGround(self:GetPos())
    if gnd ~= -1 then self.TumbleGroundZ = gnd end
    local fwd = Angle(0, self.flightYaw, 0):Forward()
    self.TumbleVelocity = Vector(fwd.x*(self.Speed or 260), fwd.y*(self.Speed or 260), -200)
    local sign = function() return (math.random(2)==1) and 1 or -1 end
    self.TumbleAngVelocity = Vector(math.Rand(80,200)*sign(), math.Rand(20,80)*sign(), math.Rand(150,400)*sign())
    local pos = self:GetPos()
    local ed = EffectData() ed:SetOrigin(pos) ed:SetScale(4) ed:SetMagnitude(4) ed:SetRadius(400)
    util.Effect("500lb_air", ed, true, true)
    sound.Play("ambient/explosions/explode_4.wav", pos, 135, 95, 1.0)
end

function ENT:CrashExplode()
    if self.TumbleCrashed then return end
    self.TumbleCrashed = true
    local pos = self:GetPos()
    local e1=EffectData() e1:SetOrigin(pos) e1:SetScale(6) e1:SetMagnitude(6) e1:SetRadius(600) util.Effect("HelicopterMegaBomb",e1,true,true)
    local e2=EffectData() e2:SetOrigin(pos) e2:SetScale(5) e2:SetMagnitude(5) e2:SetRadius(500) util.Effect("500lb_air",e2,true,true)
    local e3=EffectData() e3:SetOrigin(pos+Vector(0,0,80)) e3:SetScale(4) e3:SetMagnitude(4) e3:SetRadius(400) util.Effect("500lb_air",e3,true,true)
    sound.Play("ambient/explosions/explode_8.wav", pos, 140, 90, 1.0)
    sound.Play("weapon_AWP.Single", pos, 145, 60, 1.0)
    util.BlastDamage(self, self, pos, 400, 200)
    self:Remove()
end

function ENT:DestroyUAV()
    if self.IsDestroyed then return end
    self.IsDestroyed = true
    if self.EngineLoop then
        self.EngineLoop:ChangeVolume(0, 0.3)
        timer.Simple(0.4, function() if self.EngineLoop then self.EngineLoop:Stop() end end)
    end
    self:StartTumble()
    timer.Simple(12, function() if IsValid(self) then self:CrashExplode() end end)
end

function ENT:Debug(msg) print("[Bombin B-52] "..tostring(msg)) end

-- ============================================================
-- THINK / PHYSICS UPDATE (flight unchanged)
-- ============================================================
function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink(CurTime()+0.1) return true
    end
    local ct = CurTime()

    -- Tumble: only ground-check, no weapons
    if self.IsTumbling and not self.TumbleCrashed then
        local pos = self:GetPos()
        if pos.z <= (self.TumbleGroundZ or -16384)+150 then self:CrashExplode() return end
        local tr = util.TraceLine({start=pos, endpos=pos+Vector(0,0,-200), filter=self})
        if tr.HitWorld then self:CrashExplode() return end
        self:NextThink(ct+0.05) return true
    end

    if ct >= self.DieTime then self:Remove() return end
    if not IsValid(self.PhysObj) then self.PhysObj = self:GetPhysicsObject() end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then self.PhysObj:Wake() end

    local age  = ct - self.SpawnTime
    local left = self.DieTime - ct
    local alpha = 255
    if age  < self.FadeDuration then alpha = math.Clamp(255*(age /self.FadeDuration),0,255)
    elseif left < self.FadeDuration then alpha = math.Clamp(255*(left/self.FadeDuration),0,255) end
    self:SetColor(Color(255,255,255,math.Round(alpha)))

    -- Weapons only when not destroyed
    if not self.IsDestroyed then
        self:HandleWeaponSystem(ct)
    end

    self:NextThink(ct)
    return true
end

function ENT:PhysicsUpdate(phys)
    if not self.DieTime or not self.sky then return end

    if self.IsTumbling then
        if self.TumbleCrashed then return end
        local dt = engine.TickInterval()
        self.TumbleVelocity.z = self.TumbleVelocity.z + physenv.GetGravity().z * dt
        local pos    = self:GetPos()
        local newPos = pos + self.TumbleVelocity * dt
        local av     = self.TumbleAngVelocity
        self.ang = Angle(self.ang.p+av.x*dt, self.ang.y+av.y*dt, self.ang.r+av.z*dt)
        self:SetPos(newPos) self:SetAngles(self.ang)
        if IsValid(phys) then phys:SetPos(newPos) phys:SetAngles(self.ang) end
        return
    end

    if CurTime() >= self.DieTime then self:Remove() return end

    local pos = self:GetPos()
    local dt  = engine.TickInterval()

    -- Altitude drift
    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky - math.Rand(0, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(12, 30)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)
    self.JitterPhase = self.JitterPhase + 0.02
    local liveAlt = math.Clamp(
        self.AltDriftCurrent + math.sin(self.JitterPhase) * self.JitterAmplitude,
        self.sky - self.AltDriftRange, self.sky
    )

    -- Orbit steering
    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local toCenter   = flatCenter - flatPos
    local dist       = toCenter:Length()

    local radialDir  = (dist > 1) and (toCenter / dist) or Vector(0,0,0)
    local tangentDir = Vector(
        -radialDir.y * self.OrbitDirection,
         radialDir.x * self.OrbitDirection,
        0
    )
    if tangentDir:LengthSqr() < 0.001 then
        local fb = Angle(0, self.flightYaw, 0):Forward()
        tangentDir = Vector(fb.x, fb.y, 0)
    end
    tangentDir:Normalize()

    local radialError = 0
    if self.OrbitRadius > 0 then
        radialError = math.Clamp((dist - self.OrbitRadius) / self.OrbitRadius, -1, 1)
    end

    local desired2 = Vector(
        tangentDir.x + radialDir.x * radialError * self.RadialGain,
        tangentDir.y + radialDir.y * radialError * self.RadialGain,
        0
    )
    if desired2:LengthSqr() < 0.001 then desired2 = tangentDir end
    desired2:Normalize()

    local fwdAngle = Angle(0, self.flightYaw, 0)
    local fwd3     = fwdAngle:Forward()
    local fwd2     = Vector(fwd3.x, fwd3.y, 0)
    fwd2:Normalize()

    local cross    = fwd2.x * desired2.y - fwd2.y * desired2.x
    local dot      = fwd2.x * desired2.x + fwd2.y * desired2.y
    local urgency  = (1 - dot) * 0.5
    local turnRate = math.Clamp(cross * urgency * self.MaxTurnRate * 2,
                                -self.MaxTurnRate, self.MaxTurnRate)

    self.flightYaw = self.flightYaw + turnRate * dt

    local turnRateDelta = turnRate - self.PrevTurnRate
    self.PrevTurnRate   = turnRate

    local sustained  = math.Clamp(turnRate      * ROLL_SUSTAINED_GAIN, -20, 20)
    local transient  = math.Clamp(turnRateDelta * ROLL_TRANSIENT_GAIN, -12, 12)
    local rollTarget = math.Clamp(sustained + transient, -ROLL_MAX, ROLL_MAX)

    local building = (rollTarget * self.SmoothedRoll >= 0)
                     and (math.abs(rollTarget) > math.abs(self.SmoothedRoll))
    self.SmoothedRoll = Lerp(building and ROLL_LERP_IN or ROLL_LERP_OUT, self.SmoothedRoll, rollTarget)

    local climbDelta   = math.Clamp((liveAlt - pos.z) / 400, -1, 1)
    local targetPitch  = math.Clamp(climbDelta * 6, -8, 8)
    self.SmoothedPitch = Lerp(0.03, self.SmoothedPitch, targetPitch)

    self.ang = Angle(
        -self.SmoothedRoll,
        self.flightYaw + MODEL_YAW_OFFSET,
        -self.SmoothedPitch
    )

    local newPos = pos + fwdAngle:Forward() * self.Speed * dt
    newPos.z     = Lerp(0.07, pos.z, liveAlt)

    if not util.IsInWorld(newPos) then
        self:Debug("OOB guard - steering to center")
        local toC = flatCenter - Vector(pos.x, pos.y, 0)  toC.z = 0
        if toC:LengthSqr() < 0.001 then toC = Vector(-fwd2.x, -fwd2.y, 0) end
        toC:Normalize()
        local sCross = fwd2.x*toC.y - fwd2.y*toC.x
        self.flightYaw = self.flightYaw
            + math.Clamp(sCross * self.MaxTurnRate, -self.MaxTurnRate, self.MaxTurnRate) * dt
        self:SetPos(pos)
        self:SetAngles(Angle(-self.SmoothedRoll, self.flightYaw+MODEL_YAW_OFFSET, -self.SmoothedPitch))
        return
    end

    self:SetPos(newPos)
    self:SetAngles(self.ang)
end

-- ============================================================
-- TARGET ACQUISITION
-- ============================================================
function ENT:GetPrimaryTarget()
    local closest, closestDist = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(self.CenterPos)
        if d < closestDist then closestDist = d  closest = ply end
    end
    return closest
end

-- Returns a ground position aimed at the closest player.
-- scatter: radius of random horizontal error in units.
function ENT:GetAimedGroundPos(scatter)
    scatter = scatter or 0
    local target = self:GetPrimaryTarget()
    local base
    if IsValid(target) then
        base = target:GetPos()
    else
        local tr = util.QuickTrace(
            Vector(self.CenterPos.x, self.CenterPos.y, self.sky),
            Vector(0,0,-30000), self)
        base = tr.HitPos
    end
    if scatter > 0 then
        base = base + Vector(
            math.Rand(-scatter, scatter),
            math.Rand(-scatter, scatter),
            0
        )
    end
    return base
end

-- ============================================================
-- WEAPON SYSTEM - MASTER SCHEDULER
-- ============================================================
-- State machine:
--   IsPeaceful == true  -> wait until PeacefulUntil, then PickNewWeapon
--   IsPeaceful == false -> run the active weapon, when done enter peaceful

function ENT:HandleWeaponSystem(ct)
    if self.IsPeaceful then
        if ct >= self.PeacefulUntil then
            self.IsPeaceful = false
            self:PickNewWeapon(ct)
        end
        return
    end

    -- Active weapon: dispatch to the right update function
    -- Each update function returns true when the weapon run is finished
    local done = false
    if     self.CurrentWeapon == "massive" then done = self:UpdateMassive(ct)
    elseif self.CurrentWeapon == "medium"  then done = self:UpdateMedium(ct)
    elseif self.CurrentWeapon == "carpet"  then done = self:UpdateCarpet(ct)
    elseif self.CurrentWeapon == "cluster" then done = self:UpdateCluster(ct)
    elseif self.CurrentWeapon == "vikhr"   then done = self:UpdateVikhr(ct)
    else   done = true end

    if done then
        -- Weapon run ended - start peaceful window
        self.IsPeaceful    = true
        self.CurrentWeapon = nil
        self.PeacefulUntil = ct + math.Rand(CFG_PeacefulMin, CFG_PeacefulMax)
        self:Debug("Peaceful window until "..string.format("%.1f", self.PeacefulUntil))
    end
end

function ENT:PickNewWeapon(ct)
    -- Equal weight on all 5 weapon types
    local roll = math.random(1, 5)
    if     roll == 1 then self.CurrentWeapon = "massive"
    elseif roll == 2 then self.CurrentWeapon = "medium"
    elseif roll == 3 then self.CurrentWeapon = "carpet"
    elseif roll == 4 then self.CurrentWeapon = "cluster"
    else                   self.CurrentWeapon = "vikhr"
    end

    self.WPN_ShotsFired  = 0
    self.WPN_NextShot    = ct + 0.5   -- small lead-in before first drop
    self.WPN_MuzzleIndex = 1

    -- Carpet needs a pre-baked line direction at selection time
    if self.CurrentWeapon == "carpet" then
        self:BakeCarpetLine()
    end

    self:Debug("Weapon: "..self.CurrentWeapon)
end

-- ============================================================
-- SHARED BOMB SPAWN HELPER
-- Spawns a gredwitch bomb dropped from the bomb bay.
-- dropPos:   world position the bomb is spawned at
-- aimPos:    world ground point the bomb should land near (used for initial velocity aim)
-- entClass:  string entity classname (e.g. "gb_bomb_1000gp")
-- ============================================================
function ENT:SpawnBomb(entClass, dropPos, aimPos)
    local bomb = ents.Create(entClass)
    if not IsValid(bomb) then
        self:Debug("WARN: failed to create entity '"..tostring(entClass).."'")
        return nil
    end

    -- Mark as aircraft-dropped so base_bomb:Initialize() doesn't block it
    bomb.IsOnPlane = true
    bomb:SetOwner(self)

    -- Orient the bomb nose-down toward the aimed ground point.
    local toTarget = aimPos - dropPos
    local dropAng
    if toTarget:LengthSqr() > 1 then
        toTarget:Normalize()
        dropAng = toTarget:Angle()
    else
        dropAng = Angle(90, 0, 0)   -- straight down
    end

    bomb:SetPos(dropPos)
    bomb:SetAngles(dropAng)
    bomb:Spawn()
    bomb:Activate()

    -- Arm immediately (ArmDelay in shared is 0.1-0.5s on most bombs; ArmInternal will flip Armed)
    bomb.Armed = false
    bomb:Arm()

    -- Give the bomb the aircraft's horizontal velocity so it doesn't drop straight
    -- and continues slightly in the flight direction, plus a slight downward kick.
    local bPhys = bomb:GetPhysicsObject()
    if IsValid(bPhys) then
        local fwdVel = Angle(0, self.flightYaw, 0):Forward() * self.Speed
        fwdVel.z = fwdVel.z - 80   -- downward bias so it actually falls
        bPhys:SetVelocity(fwdVel)
    end

    -- Prevent self-collision for a moment
    constraint.NoCollide(bomb, self, 0, 0)
    local ref = bomb
    timer.Simple(0.6, function()
        if IsValid(ref) and IsValid(self) then
            constraint.RemoveConstraints(ref, "NoCollide")
        end
    end)

    return bomb
end

-- ============================================================
-- W1: MASSIVE ORDNANCE
-- Single bomb, 1000gp or 2000gp, terrible aim.
-- Returns true when the single drop is done.
-- ============================================================
function ENT:UpdateMassive(ct)
    if self.WPN_ShotsFired >= 1 then return true end   -- already dropped
    if ct < self.WPN_NextShot then return false end

    self.WPN_ShotsFired = 1

    local entClass  = CFG_MASSIVE_Bombs[math.random(#CFG_MASSIVE_Bombs)]
    local dropPos   = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos    = self:GetAimedGroundPos(CFG_MASSIVE_Scatter)

    self:SpawnBomb(entClass, dropPos, aimPos)
    self:Debug("W1 MASSIVE: "..entClass)
    return true   -- one-shot, done immediately
end

-- ============================================================
-- W2: MEDIUM ORDNANCE
-- 6 bombs from the pool, each with independent scatter + independent aim point.
-- Returns true once all 6 are dropped.
-- ============================================================
function ENT:UpdateMedium(ct)
    if self.WPN_ShotsFired >= CFG_MEDIUM_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot    = ct + CFG_MEDIUM_Delay
    self.WPN_ShotsFired  = self.WPN_ShotsFired + 1

    -- Each bomb gets its own random class AND its own independent scatter direction
    local entClass  = CFG_MEDIUM_Bombs[math.random(#CFG_MEDIUM_Bombs)]
    local dropPos   = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos    = self:GetAimedGroundPos(CFG_MEDIUM_Scatter)

    self:SpawnBomb(entClass, dropPos, aimPos)
    self:Debug("W2 MEDIUM shot "..self.WPN_ShotsFired.."/"..CFG_MEDIUM_Count.." "..entClass)
    return (self.WPN_ShotsFired >= CFG_MEDIUM_Count)
end

-- ============================================================
-- W3: CARPET BOMBING LINE
-- 8 x gb_bomb_250gp dropped along the aircraft's current flight track.
-- BakeCarpetLine() pre-calculates 8 world ground aim points at PickNewWeapon time.
-- Each subsequent bomb is aimed at the next point in the line.
-- Returns true once all bombs are dropped.
-- ============================================================
function ENT:BakeCarpetLine()
    -- The line is built along the current flight vector on the ground.
    -- Center of the line = player ground position. Each step = CFG_CARPET_Spacing.
    local center  = self:GetAimedGroundPos(0)   -- aimed, no scatter
    local fwdDir  = Angle(0, self.flightYaw, 0):Forward()
    fwdDir.z = 0
    if fwdDir:LengthSqr() < 0.001 then fwdDir = Vector(1,0,0) end
    fwdDir:Normalize()

    local half = math.floor(CFG_CARPET_Count / 2)
    self.CarpetLine = {}
    for i = 1, CFG_CARPET_Count do
        local step   = (i - 1 - half + 0.5)   -- -half+0.5 to half+0.5 gives symmetric spread
        local pt     = center + fwdDir * (step * CFG_CARPET_Spacing)
        self.CarpetLine[i] = pt
    end
end

function ENT:UpdateCarpet(ct)
    if self.WPN_ShotsFired >= CFG_CARPET_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot   = ct + CFG_CARPET_Delay
    self.WPN_ShotsFired = self.WPN_ShotsFired + 1

    local dropPos = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos  = self.CarpetLine and self.CarpetLine[self.WPN_ShotsFired] or self:GetAimedGroundPos(200)

    self:SpawnBomb("gb_bomb_250gp", dropPos, aimPos)
    self:Debug("W3 CARPET bomb "..self.WPN_ShotsFired.."/"..CFG_CARPET_Count)
    return (self.WPN_ShotsFired >= CFG_CARPET_Count)
end

-- ============================================================
-- W4: CLUSTER MUNITIONS
-- 10 bombs scattered widely. Each is independently aimed.
-- Returns true once all 10 are dropped.
-- ============================================================
function ENT:UpdateCluster(ct)
    if self.WPN_ShotsFired >= CFG_CLUSTER_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot    = ct + CFG_CLUSTER_Delay
    self.WPN_ShotsFired  = self.WPN_ShotsFired + 1

    local entClass = CFG_CLUSTER_Bombs[math.random(#CFG_CLUSTER_Bombs)]
    local dropPos  = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos   = self:GetAimedGroundPos(CFG_CLUSTER_Scatter)

    self:SpawnBomb(entClass, dropPos, aimPos)
    self:Debug("W4 CLUSTER shot "..self.WPN_ShotsFired.."/"..CFG_CLUSTER_Count.." "..entClass)
    return (self.WPN_ShotsFired >= CFG_CLUSTER_Count)
end

-- ============================================================
-- W5: VIKHR ATGM (original logic, unchanged except return value)
-- Returns true when both missiles are fired.
-- ============================================================
function ENT:UpdateVikhr(ct)
    if self.WPN_ShotsFired >= CFG_VIKHR_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot    = ct + CFG_VIKHR_Delay
    self.WPN_ShotsFired  = self.WPN_ShotsFired + 1

    local muzzleLocal = CFG_VIKHR_MuzzlePoints[self.WPN_MuzzleIndex]
    self.WPN_MuzzleIndex = (self.WPN_MuzzleIndex % #CFG_VIKHR_MuzzlePoints) + 1
    local muzzlePos = self:LocalToWorld(muzzleLocal)

    local targetPos = self:GetAimedGroundPos(CFG_VIKHR_Scatter)
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return false end
    dir:Normalize()

    local rocket = ents.Create("gb_9k121_rocket")
    if not IsValid(rocket) then self:Debug("gb_9k121_rocket failed") return false end

    rocket:SetPos(muzzlePos)  rocket:SetAngles(dir:Angle())  rocket:SetOwner(self)  rocket.IsOnPlane=true
    rocket:Spawn()  rocket:Activate()
    rocket.Armed=true  rocket.ShouldExplode=true  rocket.ShouldExplodeOnImpact=true
    rocket:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    -- Trace for JDAM guidance
    local startpos = self:LocalToWorld(self:OBBCenter())
    local tr = util.TraceHull({start=startpos, endpos=startpos+dir*500000,
                               mins=Vector(-25,-25,-25), maxs=Vector(25,25,25), filter=self})
    local rPhys = rocket:GetPhysicsObject()
    if IsValid(rPhys) then rPhys:SetVelocity(Angle(0,self.flightYaw,0):Forward() * self.Speed) end

    constraint.NoCollide(rocket, self, 0, 0)
    local ref = rocket
    timer.Simple(0.25, function()
        if not IsValid(ref) then return end
        if tr.Hit then
            ref.JDAM         = true
            ref.target       = tr.Entity
            ref.targetOffset = IsValid(tr.Entity) and tr.Entity:WorldToLocal(tr.HitPos) or tr.HitPos
            ref.dropping     = true
        end
        ref.Armed = true  ref:Launch()  ref:SetCollisionGroup(0)
    end)

    -- Muzzle FX
    local ed = EffectData() ed:SetOrigin(muzzlePos) ed:SetAngles(self:GetAngles()) ed:SetEntity(self)
    util.Effect("gred_particle_aircraft_muzzle", ed, true, true)
    -- NOTE: Sound level fixed to 110 (original had 0 here, a copy-paste bug)
    sound.Play(table.Random(SOUNDS_ATGM_IGNITE), muzzlePos, 110, math.random(95,105), 1.0)
    timer.Simple(0.1, function()
        if IsValid(rocket) then
            sound.Play(table.Random(SOUNDS_LAUNCH), rocket:GetPos(), 105, math.random(95,105), 1.0)
        end
    end)

    rocket.IdleSound = CreateSound(rocket, SOUND_ROCKET_IDLE)
    if rocket.IdleSound then
        rocket.IdleSound:Play()
        rocket.IdleSound:ChangePitch(math.random(85,110),0)
        rocket.IdleSound:ChangeVolume(0.9,0)
    end
    local oldR = rocket.OnRemove
    rocket.OnRemove = function(s)
        if oldR then oldR(s) end
        if s.IdleSound then s.IdleSound:Stop() end
    end
    local oldE = rocket.OnExplode
    rocket.OnExplode = function(s,p,n)
        if oldE then oldE(s,p,n) end
        if s.IdleSound then s.IdleSound:Stop() end
        local hp = p or s:GetPos()
        local e1=EffectData() e1:SetOrigin(hp) e1:SetScale(4) e1:SetMagnitude(4) e1:SetRadius(400) util.Effect("500lb_air",e1,true,true)
        local e2=EffectData() e2:SetOrigin(hp+Vector(0,0,60)) e2:SetScale(3) e2:SetMagnitude(3) e2:SetRadius(300) util.Effect("500lb_air",e2,true,true)
        local e3=EffectData() e3:SetOrigin(hp) e3:SetScale(4) e3:SetMagnitude(4) e3:SetRadius(400) util.Effect("HelicopterMegaBomb",e3,true,true)
    end

    return (self.WPN_ShotsFired >= CFG_VIKHR_Count)
end

-- ============================================================
-- UTILITIES
-- ============================================================
function ENT:FindGround(centerPos)
    local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z+64)
    local endPos     = Vector(centerPos.x, centerPos.y, -16384)
    local filterList = {self}
    local maxIter    = 0
    while maxIter < 100 do
        local tr = util.TraceLine({start=startPos, endpos=endPos, filter=filterList})
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then table.insert(filterList, tr.Entity)
        else break end
        maxIter = maxIter + 1
    end
    return -1
end

function ENT:OnRemove()
    if self.EngineLoop then
        self.EngineLoop:ChangeVolume(0, 0.5)
        timer.Simple(0.6, function() if self.EngineLoop then self.EngineLoop:Stop() end end)
    end
end
