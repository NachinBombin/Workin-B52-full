AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_trailsystem.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
-- MODEL / FLIGHT ORIENTATION NOTES
-- The B-52 model nose points along LOCAL +X.
-- MODEL_YAW_OFFSET = -90 aligns the visual nose with flightYaw.
-- bank  (wing tilt)   = GMod Angle.p   (negative sign: right turn -> right wing down)
-- pitch (nose up/dn)  = GMod Angle.r
-- Final angle: Angle( -SmoothedRoll, flightYaw+OFFSET, -SmoothedPitch )
-- ============================================================
local MODEL_YAW_OFFSET = -90

local ROLL_SUSTAINED_GAIN = 2.2
local ROLL_TRANSIENT_GAIN = 55.0
local ROLL_MAX            = 22.0
local ROLL_LERP_IN        = 0.08
local ROLL_LERP_OUT       = 0.012

local ENGINE_LOOP_SOUND = "sound/b52/b52.wav"

local MODEL_SCALE = 1.8

-- ============================================================
-- SW MUNITIONS CATALOGUE
-- ============================================================
local CFG_MaxHP        = 450
local CFG_FadeDuration = 3.0
local CFG_PeacefulMin  = 6
local CFG_PeacefulMax  = 14

local CFG_BombBayLocal = Vector(0, 0, -35)
local GRAVITY_EST      = 580
local BALLISTIC_MIN_H  = 150
local BALLISTIC_MAX_H  = 3200

-- ============================================================
-- SAFETY CONSTANTS
-- ============================================================
-- How long (seconds) after drop before collisions are enabled and
-- the bomb is allowed to arm/explode. Must be >= 1.0.
local BOMB_ARM_DELAY     = 1.0
-- Margin below self.sky where we silently kill a bomb that is
-- still rising toward the skybox (prevents skybox detonations).
local SKYBOX_KILL_MARGIN = 200

-- ---------- W6 retarded ----------
local CFG_W6_FwdMult = 3.5

-- ---------- W1 ----------
local CFG_W1_Count   = 4
local CFG_W1_Delay   = 3.0
local CFG_W1_Scatter = 300
local CFG_W1_Pool    = {
    "sw_bomb_gbu31_v3","sw_bomb_gbu32_v3","sw_bomb_gbu38_v3","sw_bomb_gbu39_v3",
    "sw_bomb_gbu12_v3","sw_bomb_gbu16_v3","sw_bomb_gbu10_v3","sw_bomb_gbu24_v3",
    "sw_bomb_gbu27_v3","sw_bomb_gbu28_v3","sw_bomb_gbu48_v3","sw_bomb_gbu49_v3",
    "sw_bomb_gbu53_v3","sw_bomb_gbu8_v3", "sw_bomb_agm154_v3","sw_bomb_agm62a_v3",
    "sw_bomb_gbu15_v3",
}

-- ---------- W2 ----------
local CFG_W2_Count   = 2
local CFG_W2_Delay   = 4.0
local CFG_W2_Scatter = 1800
local CFG_W2_Pool    = {
    "sw_bomb_gbu43_v3","sw_bomb_gbu57_v3","sw_bomb_m118_v3","sw_bomb_anm56_v3",
    "sw_bomb_anm66_v3","sw_bomb_mk84_v3", "sw_bomb_mk84_air_v3","sw_bomb_anmk1_v3",
}

-- ---------- W3 ----------
local CFG_W3_Count   = 8
local CFG_W3_Delay   = 0.4
local CFG_W3_Scatter = 1200
local CFG_W3_Pool    = {
    "sw_bomb_mk82_v3","sw_bomb_mk83_v3","sw_bomb_mk83_air_v3","sw_bomb_m117_v3",
    "sw_bomb_hem32_v3","sw_bomb_hem31_v3","sw_bomb_anm64_v3","sw_bomb_anm65_v3",
    "sw_bomb_anm65_m129_v3","sw_bomb_anmk33_v3","sw_bomb_anm57_v3","sw_bomb_mk9_v3",
    "sw_bomb_m62_v3","sw_bomb_m63_v3",
}

-- ---------- W4 ----------
local CFG_W4_Count   = 12
local CFG_W4_Delay   = 0.25
local CFG_W4_Scatter = 1600
local CFG_W4_Pool    = {
    "sw_bomb_mk81_v3","sw_bomb_anm30_v3","sw_bomb_anm57_v3",
    "sw_bomb_gbu39_v3","sw_bomb_gbu53_v3",
}

-- ---------- W5 Hellfire ----------
local CFG_W5_Entity  = "sw_missile_agm114_v3"
local CFG_W5_Count   = 4
local CFG_W5_Delay   = 2.5
local CFG_W5_Scatter = 80
local CFG_W5_Muzzles = { Vector(60,-70,-8), Vector(60,70,-8) }

-- ---------- W6 Retarded ----------
local CFG_W6_Count   = 6
local CFG_W6_Delay   = 0.55
local CFG_W6_Scatter = 600
local CFG_W6_Pool    = {
    "sw_bomb_mk81_snakeye_v3","sw_bomb_mk82_snakeye_v3",
    "sw_bomb_mk82_air_v3",    "sw_bomb_mk84_air_v3",
}

-- ============================================================
-- NETWORK STRING
-- ============================================================
util.AddNetworkString("bombin_b52_damage_tier")

local function CalcTier(hp, maxHP)
    local f = hp / maxHP
    if f > 0.66 then return 0 elseif f > 0.33 then return 1 elseif f > 0 then return 2 else return 3 end
end
local function BroadcastTier(ent, tier)
    net.Start("bombin_b52_damage_tier")
    net.WriteUInt(ent:EntIndex(), 16)
    net.WriteUInt(tier, 2)
    net.Broadcast()
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
    self:SetModelScale(MODEL_SCALE)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
    self:SetPos(spawnPos)
    self:SetBodygroup(1, 1)
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))

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
    self.TumbleVelocity    = Vector(0, 0, 0)
    self.TumbleAngVelocity = Vector(0, 0, 0)

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

    self.CurrentWeapon   = nil
    self.IsPeaceful      = false
    self.PeacefulUntil   = 0
    self.WPN_ShotsFired  = 0
    self.WPN_NextShot    = 0
    self.WPN_MuzzleIndex = 1

    self:Debug("B-52 (SW-munitions, scale=" .. MODEL_SCALE .. ") spawned. sky=" .. self.sky)
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
    if tier ~= self.DamageTier then
        self.DamageTier = tier
        BroadcastTier(self, tier)
    end
    if hp <= 0 then self:DestroyUAV() end
end

function ENT:StartTumble()
    self.IsTumbling      = true
    self.TumbleStartTime = CurTime()
    self.TumbleCrashed   = false
    local gnd = self:FindGround(self:GetPos())
    if gnd ~= -1 then self.TumbleGroundZ = gnd end
    local fwd = Angle(0, self.flightYaw, 0):Forward()
    self.TumbleVelocity    = Vector(fwd.x*(self.Speed or 260), fwd.y*(self.Speed or 260), -200)
    local function sign() return (math.random(2)==1) and 1 or -1 end
    self.TumbleAngVelocity = Vector(
        math.Rand(80,200)*sign(),
        math.Rand(20,80)*sign(),
        math.Rand(150,400)*sign()
    )
    local pos = self:GetPos()
    local ed  = EffectData() ed:SetOrigin(pos) ed:SetScale(4) ed:SetMagnitude(4) ed:SetRadius(400)
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
        timer.Simple(0.4, function()
            if self.EngineLoop then self.EngineLoop:Stop() end
        end)
    end
    self:StartTumble()
    timer.Simple(12, function()
        if IsValid(self) then self:CrashExplode() end
    end)
end

function ENT:Debug(msg) print("[Bombin B-52] " .. tostring(msg)) end

-- ============================================================
-- THINK / PHYSICS UPDATE
-- ============================================================
function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink(CurTime()+0.1) return true
    end
    local ct = CurTime()

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
        local dt  = engine.TickInterval()
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
    local turnRate = math.Clamp(
        cross * urgency * self.MaxTurnRate * 2,
        -self.MaxTurnRate, self.MaxTurnRate
    )

    self.flightYaw      = self.flightYaw + turnRate * dt
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
-- WEAPON SYSTEM — MASTER SCHEDULER
-- ============================================================
function ENT:HandleWeaponSystem(ct)
    if self.IsPeaceful then
        if ct >= self.PeacefulUntil then
            self.IsPeaceful = false
            self:PickNewWeapon(ct)
        end
        return
    end

    local done = false
    local w = self.CurrentWeapon
    if     w == "precision" then done = self:UpdatePrecision(ct)
    elseif w == "heavy"     then done = self:UpdateHeavy(ct)
    elseif w == "medium"    then done = self:UpdateMedium(ct)
    elseif w == "light"     then done = self:UpdateLight(ct)
    elseif w == "hellfire"  then done = self:UpdateHellfire(ct)
    elseif w == "retarded"  then done = self:UpdateRetarded(ct)
    else   done = true end

    if done then
        self.IsPeaceful    = true
        self.CurrentWeapon = nil
        self.PeacefulUntil = ct + math.Rand(CFG_PeacefulMin, CFG_PeacefulMax)
        self:Debug("Peaceful until " .. string.format("%.1f", self.PeacefulUntil))
    end
end

function ENT:PickNewWeapon(ct)
    local roll = math.random(1, 6)
    if     roll == 1 then self.CurrentWeapon = "precision"
    elseif roll == 2 then self.CurrentWeapon = "heavy"
    elseif roll == 3 then self.CurrentWeapon = "medium"
    elseif roll == 4 then self.CurrentWeapon = "light"
    elseif roll == 5 then self.CurrentWeapon = "hellfire"
    else                   self.CurrentWeapon = "retarded"
    end

    self.WPN_ShotsFired  = 0
    self.WPN_NextShot    = ct + 0.5
    self.WPN_MuzzleIndex = 1

    self:Debug("Selected weapon window: " .. self.CurrentWeapon)
end

-- ============================================================
-- BOMB SAFETY HELPERS
-- ============================================================

-- ApplyBombSafety: called immediately after every bomb/missile is spawned.
--
-- Three guarantees:
--   1. SELF-BOMB: CollisionGroup is set to COLLISION_GROUP_DEBRIS for
--      BOMB_ARM_DELAY seconds. This makes the bomb pass through ALL
--      entities (including the B-52 and other freshly-dropped bombs).
--      After the delay it is restored to COLLISION_GROUP_NONE so it can
--      hit the ground normally.
--
--   2. 1-SECOND ARM DELAY: Armed is forced false at spawn. The SW base
--      explodes on PhysicsCollide only when Armed == true, so the bomb
--      cannot detonate during the first second regardless of what it hits.
--      Armed is set to true after BOMB_ARM_DELAY seconds.
--
--   3. SKYBOX GUARD: A lightweight Think hook monitors the bomb's altitude.
--      If the bomb reaches (self.sky - SKYBOX_KILL_MARGIN) before arming,
--      OR if it ever exits the world (util.IsInWorld == false), it is
--      silently removed with no explosion.
--      After the bomb is armed and falling the guard keeps watching: if the
--      entity somehow climbs back toward the skybox (e.g. an explosion
--      impulse) and is not yet on the ground, it is removed cleanly.
--
function ENT:ApplyBombSafety(bomb)
    if not IsValid(bomb) then return end

    local skyKillZ = self.sky - SKYBOX_KILL_MARGIN
    local armAt    = CurTime() + BOMB_ARM_DELAY

    -- Step 1 & 2: disable collisions and block arming for BOMB_ARM_DELAY s
    bomb.Armed = false
    bomb:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    -- Step 3: install a per-tick skybox / OOB guard on the bomb entity
    -- We override OnTick (SW base calls it every Think) if available,
    -- otherwise we hook Think directly.
    local function skyGuard(b)
        if not IsValid(b) then return end
        local bpos = b:GetPos()
        -- Out-of-world or hit skybox ceiling -> silently remove, no boom
        if not util.IsInWorld(bpos) or bpos.z >= skyKillZ then
            b:Remove()
            return
        end
    end

    if bomb.OnTick then
        -- SW base provides OnTick() called each server Think tick
        local origOnTick = bomb.OnTick
        bomb.OnTick = function(b)
            skyGuard(b)
            if IsValid(b) then origOnTick(b) end
        end
    else
        -- Fallback: hook Think directly
        local origThink = bomb.Think
        bomb.Think = function(b)
            skyGuard(b)
            if IsValid(b) and origThink then origThink(b) end
        end
    end

    -- After BOMB_ARM_DELAY: restore normal collision group and arm the bomb
    local ref = bomb
    timer.Simple(BOMB_ARM_DELAY, function()
        if not IsValid(ref) then return end
        ref:SetCollisionGroup(COLLISION_GROUP_NONE)
        ref.Armed = true
    end)
end

-- ============================================================
-- SHARED BOMB SPAWN HELPERS
-- ============================================================

local function CalcBallisticImpulse(dropPos, aimPos, aircraftFwdVel)
    local H        = math.max(dropPos.z - aimPos.z, 100)
    local fallTime = math.sqrt(2 * H / GRAVITY_EST)

    local dx = aimPos.x - dropPos.x
    local dy = aimPos.y - dropPos.y
    local lateralDist = math.sqrt(dx*dx + dy*dy)

    local reqSpeed = math.Clamp(
        lateralDist / fallTime,
        BALLISTIC_MIN_H, BALLISTIC_MAX_H
    )

    local dir
    if lateralDist > 1 then
        dir = Vector(dx / lateralDist, dy / lateralDist, 0)
    else
        local a = math.Rand(0, math.pi * 2)
        dir = Vector(math.cos(a), math.sin(a), 0)
    end

    local vel = dir * reqSpeed
    vel.x = vel.x + aircraftFwdVel.x
    vel.y = vel.y + aircraftFwdVel.y
    vel.z = -60
    return vel
end

function ENT:SpawnSWBomb(entClass, dropPos, aimPos, isRetarded)
    local bomb = ents.Create(entClass)
    if not IsValid(bomb) then
        self:Debug("WARN: failed to create '" .. tostring(entClass) .. "'")
        return nil
    end

    bomb.IsOnPlane = true
    bomb.Launcher  = self
    bomb:SetOwner(self)

    local toTarget = aimPos - dropPos
    local dropAng
    if toTarget:LengthSqr() > 1 then
        toTarget:Normalize()
        dropAng = toTarget:Angle()
    else
        dropAng = Angle(90, 0, 0)
    end

    bomb:SetPos(dropPos)
    bomb:SetAngles(dropAng)
    bomb:Spawn()
    bomb:Activate()

    if isRetarded then
        bomb:SetBodygroup(1, 1)
    end

    -- Apply all three safety guarantees (collision delay, arm delay, skybox guard)
    self:ApplyBombSafety(bomb)

    local bPhys = bomb:GetPhysicsObject()
    if IsValid(bPhys) then
        local aircraftFwd = Angle(0, self.flightYaw, 0):Forward() * self.Speed
        aircraftFwd.z = 0

        if isRetarded then
            bPhys:SetVelocity(Vector(
                aircraftFwd.x * CFG_W6_FwdMult,
                aircraftFwd.y * CFG_W6_FwdMult,
                -80
            ))
        else
            local vel = CalcBallisticImpulse(dropPos, aimPos, aircraftFwd)
            bPhys:SetVelocity(vel)
        end
    end

    return bomb
end

-- ============================================================
-- W1: PRECISION GUIDED WEAPONS
-- ============================================================
function ENT:UpdatePrecision(ct)
    if self.WPN_ShotsFired >= CFG_W1_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot   = ct + CFG_W1_Delay
    self.WPN_ShotsFired = self.WPN_ShotsFired + 1

    local entClass = CFG_W1_Pool[math.random(#CFG_W1_Pool)]
    local dropPos  = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos   = self:GetAimedGroundPos(CFG_W1_Scatter)

    self:SpawnSWBomb(entClass, dropPos, aimPos, false)
    self:Debug("W1 PRECISION " .. self.WPN_ShotsFired .. "/" .. CFG_W1_Count .. " " .. entClass)
    return (self.WPN_ShotsFired >= CFG_W1_Count)
end

-- ============================================================
-- W2: HEAVY ORDNANCE
-- ============================================================
function ENT:UpdateHeavy(ct)
    if self.WPN_ShotsFired >= CFG_W2_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot   = ct + CFG_W2_Delay
    self.WPN_ShotsFired = self.WPN_ShotsFired + 1

    local entClass   = CFG_W2_Pool[math.random(#CFG_W2_Pool)]
    local dropPos    = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos     = self:GetAimedGroundPos(CFG_W2_Scatter)
    local isRetarded = string.find(entClass, "_air_v3", 1, true) ~= nil

    self:SpawnSWBomb(entClass, dropPos, aimPos, isRetarded)
    self:Debug("W2 HEAVY " .. self.WPN_ShotsFired .. "/" .. CFG_W2_Count .. " " .. entClass)
    return (self.WPN_ShotsFired >= CFG_W2_Count)
end

-- ============================================================
-- W3: MEDIUM CARPET
-- ============================================================
function ENT:UpdateMedium(ct)
    if self.WPN_ShotsFired >= CFG_W3_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot   = ct + CFG_W3_Delay
    self.WPN_ShotsFired = self.WPN_ShotsFired + 1

    local entClass = CFG_W3_Pool[math.random(#CFG_W3_Pool)]
    local dropPos  = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos   = self:GetAimedGroundPos(CFG_W3_Scatter)

    self:SpawnSWBomb(entClass, dropPos, aimPos, false)
    self:Debug("W3 MEDIUM " .. self.WPN_ShotsFired .. "/" .. CFG_W3_Count .. " " .. entClass)
    return (self.WPN_ShotsFired >= CFG_W3_Count)
end

-- ============================================================
-- W4: LIGHT SCATTERED
-- ============================================================
function ENT:UpdateLight(ct)
    if self.WPN_ShotsFired >= CFG_W4_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot   = ct + CFG_W4_Delay
    self.WPN_ShotsFired = self.WPN_ShotsFired + 1

    local entClass = CFG_W4_Pool[math.random(#CFG_W4_Pool)]
    local dropPos  = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos   = self:GetAimedGroundPos(CFG_W4_Scatter)

    self:SpawnSWBomb(entClass, dropPos, aimPos, false)
    self:Debug("W4 LIGHT " .. self.WPN_ShotsFired .. "/" .. CFG_W4_Count .. " " .. entClass)
    return (self.WPN_ShotsFired >= CFG_W4_Count)
end

-- ============================================================
-- W5: SW HELLFIRE MISSILE
-- ============================================================
function ENT:UpdateHellfire(ct)
    if self.WPN_ShotsFired >= CFG_W5_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot   = ct + CFG_W5_Delay
    self.WPN_ShotsFired = self.WPN_ShotsFired + 1

    local muzzleLocal = CFG_W5_Muzzles[self.WPN_MuzzleIndex]
    self.WPN_MuzzleIndex = (self.WPN_MuzzleIndex % #CFG_W5_Muzzles) + 1
    local muzzlePos = self:LocalToWorld(muzzleLocal)

    local aimPos = self:GetAimedGroundPos(CFG_W5_Scatter)
    local aimDir = aimPos - muzzlePos
    if aimDir:LengthSqr() < 1 then
        self:Debug("W5 HELLFIRE: degenerate aim vector, skip")
        return false
    end
    aimDir:Normalize()

    local missile = ents.Create(CFG_W5_Entity)
    if not IsValid(missile) then
        self:Debug("W5 HELLFIRE: entity '" .. CFG_W5_Entity .. "' not found — is SW installed?")
        return true
    end

    missile:SetPos(muzzlePos)
    missile:SetAngles(aimDir:Angle())
    missile:SetOwner(self)
    missile.IsOnPlane = true
    missile.Launcher  = self
    missile:Spawn()
    missile:Activate()

    -- Apply safety (collision delay + arm delay + skybox guard)
    self:ApplyBombSafety(missile)

    local mPhys = missile:GetPhysicsObject()
    if IsValid(mPhys) then
        local fwd = Angle(0, self.flightYaw, 0):Forward() * self.Speed
        mPhys:SetVelocity(fwd)
    end

    -- After arm delay: activate guidance
    local mRef = missile
    timer.Simple(BOMB_ARM_DELAY + 0.05, function()
        if not IsValid(mRef) then return end
        local tr = util.TraceHull({
            start  = muzzlePos,
            endpos = muzzlePos + aimDir * 500000,
            mins   = Vector(-20,-20,-20),
            maxs   = Vector(20,20,20),
            filter = { self, mRef }
        })
        if tr.Hit and IsValid(tr.Entity) then
            mRef.target       = tr.Entity
            mRef.targetOffset = tr.Entity:WorldToLocal(tr.HitPos)
        else
            mRef.target       = game.GetWorld()
            mRef.targetOffset = game.GetWorld():WorldToLocal(aimPos)
        end
        mRef.GuidanceActive = true
        mRef.HaveGuidance   = true
        if mRef.Launch then mRef:Launch() end
        mRef:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
    end)

    local ed = EffectData()
    ed:SetOrigin(muzzlePos)
    ed:SetAngles(self:GetAngles())
    ed:SetEntity(self)
    util.Effect("gred_particle_aircraft_muzzle", ed, true, true)
    sound.Play("sw/rocket/rocket_start_01.wav", muzzlePos, 110, math.random(95,105), 1.0)

    self:Debug("W5 HELLFIRE " .. self.WPN_ShotsFired .. "/" .. CFG_W5_Count)
    return (self.WPN_ShotsFired >= CFG_W5_Count)
end

-- ============================================================
-- W6: RETARDED / PARACHUTE BOMBS
-- ============================================================
function ENT:UpdateRetarded(ct)
    if self.WPN_ShotsFired >= CFG_W6_Count then return true end
    if ct < self.WPN_NextShot then return false end

    self.WPN_NextShot   = ct + CFG_W6_Delay
    self.WPN_ShotsFired = self.WPN_ShotsFired + 1

    local entClass = CFG_W6_Pool[math.random(#CFG_W6_Pool)]
    local dropPos  = self:LocalToWorld(CFG_BombBayLocal)
    local aimPos   = self:GetAimedGroundPos(CFG_W6_Scatter)

    self:SpawnSWBomb(entClass, dropPos, aimPos, true)
    self:Debug("W6 RETARDED " .. self.WPN_ShotsFired .. "/" .. CFG_W6_Count .. " " .. entClass)
    return (self.WPN_ShotsFired >= CFG_W6_Count)
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
        timer.Simple(0.6, function()
            if self.EngineLoop then self.EngineLoop:Stop() end
        end)
    end
end
