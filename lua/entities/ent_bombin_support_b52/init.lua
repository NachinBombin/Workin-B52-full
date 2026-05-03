AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- B-52G mesh faces forward with standard orientation (no flip needed).
local MODEL_YAW_OFFSET = 0

-- ============================================================
-- ROLL CONSTANTS
-- B-52 is a heavy bomber -- slow, stable, gentle banks.
-- ============================================================
local ROLL_SUSTAINED_GAIN = 1.6
local ROLL_TRANSIENT_GAIN = 40.0
local ROLL_MAX            = 15.0
local ROLL_LERP_IN        = 0.05
local ROLL_LERP_OUT       = 0.008

-- ============================================================
-- GRED GUARD
-- ============================================================

local function HasGred()
    return gred and gred.CreateShell
end

-- ============================================================
-- ENGINE SOUND
-- ============================================================

local ENGINE_LOOP_SOUND = "b52/b52.wav"

-- ============================================================
-- WEAPON SOUNDS
-- ============================================================

local SOUNDS_ATGM_IGNITE = {
    "ATGM.wav",
    "ATGM2.wav",
    "ATGM3.wav",
    "ATGM4.wav"
}

local SOUNDS_LAUNCH = {
    "launch1.wav",
    "launch2.wav"
}

local SOUND_ROCKET_IDLE = "rocket_idle.wav"

-- ============================================================
-- WEAPON TUNING
-- ============================================================

local CFG_WeaponWindow = 10

local CFG_S8_Delay        = 0.4
local CFG_S8_Count        = 4
local CFG_S8_Scatter      = 800
local CFG_S8_MuzzlePoints = {
    Vector(60, -70, -5),
    Vector(60,  70, -5),
}

local CFG_VIKHR_Delay        = 4.0
local CFG_VIKHR_Count        = 2
local CFG_VIKHR_Scatter      = 60
local CFG_VIKHR_MuzzlePoints = {
    Vector(60, -70, -5),
    Vector(60,  70, -5),
}

local CFG_FadeDuration = 3.0
local CFG_MaxHP        = 400

-- ============================================================
-- NET STRING
-- ============================================================
util.AddNetworkString("bombin_plane_damage_tier_b52")

-- ============================================================
-- DAMAGE TIER HELPERS
-- ============================================================

local function CalcTier(hp, maxHP)
    local frac = hp / maxHP
    if frac > 0.66 then return 0
    elseif frac > 0.33 then return 1
    elseif frac > 0 then return 2
    else return 3
    end
end

local function BroadcastTier(ent, tier)
    net.Start("bombin_plane_damage_tier_b52")
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
    self.Lifetime     = self:GetVar("Lifetime",     90)
    self.Speed        = self:GetVar("Speed",        280)
    self.OrbitRadius  = self:GetVar("OrbitRadius",  4000)
    -- B-52 flies at near-maximum altitude: 7500 HU above ground by default.
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 7500)

    self.MaxHP        = CFG_MaxHP
    self.WeaponWindow = CFG_WeaponWindow
    self.FadeDuration = CFG_FadeDuration

    self.S8_Delay        = CFG_S8_Delay
    self.S8_Count        = CFG_S8_Count
    self.S8_Scatter      = CFG_S8_Scatter
    self.S8_MuzzlePoints = CFG_S8_MuzzlePoints

    self.VIKHR_Delay        = CFG_VIKHR_Delay
    self.VIKHR_Count        = CFG_VIKHR_Count
    self.VIKHR_Scatter      = CFG_VIKHR_Scatter
    self.VIKHR_MuzzlePoints = CFG_VIKHR_MuzzlePoints

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    -- ---- Orbit setup ----
    self.OrbitDirection = (math.random(2) == 1) and 1 or -1
    self.OrbitTangent   = self.CallDir:Angle():Right() * self.OrbitDirection

    self.RadialGain   = 0.42
    -- Strong sky-wall avoidance: keeps the B-52 near max altitude.
    self.SkyAvoidGain = 0.80
    -- Heavy bomber turns slowly.
    self.MaxTurnRate  = 18

    -- Roll state
    self.PrevTurnRate = 0

    local spawnOffset = self.OrbitTangent * (-self.OrbitRadius * math.Rand(0.55, 0.95))
    local spawnPos    = self.CenterPos + spawnOffset
    spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)
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

    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))

    self:SetNWInt("HP",    self.MaxHP)
    self:SetNWInt("MaxHP", self.MaxHP)

    self.flightYaw = self.OrbitTangent:Angle().y
    self.ang       = Angle(0, self.flightYaw + MODEL_YAW_OFFSET, 0)
    self:SetAngles(self.ang)

    self.JitterPhase     = math.Rand(0, math.pi * 2)
    -- B-52 is stable; minimal jitter.
    self.JitterAmplitude = 4

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(20, 40)
    -- Very small drift: locks near max altitude.
    self.AltDriftRange    = 150
    self.AltDriftLerp     = 0.001

    self.SmoothedRoll  = 0
    self.SmoothedPitch = 0

    -- Tumble state
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
    end

    self.EngineLoop = CreateSound(game.GetWorld(), ENGINE_LOOP_SOUND)
    if self.EngineLoop then
        self.EngineLoop:SetSoundLevel(90)
        self.EngineLoop:ChangePitch(100, 0)
        self.EngineLoop:ChangeVolume(0.6, 0)
        self.EngineLoop:Play()
    end

    self.CurrentWeapon   = nil
    self.WeaponWindowEnd = 0

    self.S8_ShotsFired  = 0
    self.S8_NextShot    = 0
    self.S8_MuzzleIndex = 1

    self.VIKHR_ShotsFired  = 0
    self.VIKHR_NextShot    = 0
    self.VIKHR_MuzzleIndex = 1

    if not HasGred() then
        self:Debug("WARNING: Gredwitch Base not detected - weapons disabled")
    end

    self:Debug("B-52 spawned at " .. tostring(spawnPos) .. " OrbitDirection=" .. self.OrbitDirection)
end

-- ============================================================
-- DAMAGE HANDLING
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end

    local hp = self:GetNWInt("HP", self.MaxHP)
    hp = hp - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)
    self:Debug("Hit! HP remaining: " .. tostring(hp))

    local tier = CalcTier(hp, self.MaxHP)
    if tier ~= self.DamageTier then
        self.DamageTier = tier
        BroadcastTier(self, tier)
    end

    if hp <= 0 then
        self:Debug("Shot down!")
        self:DestroyUAV()
    end
end

-- ============================================================
-- TUMBLE SYSTEM
-- ============================================================

function ENT:StartTumble()
    self.IsTumbling      = true
    self.TumbleStartTime = CurTime()
    self.TumbleCrashed   = false

    local gnd = self:FindGround(self:GetPos())
    if gnd ~= -1 then self.TumbleGroundZ = gnd end

    local travelFwd = Angle(0, self.flightYaw, 0):Forward()
    local speed     = self.Speed or 280

    self.TumbleVelocity = Vector(
        travelFwd.x * speed,
        travelFwd.y * speed,
        -300
    )

    local sign = function() return (math.random(2) == 1) and 1 or -1 end
    self.TumbleAngVelocity = Vector(
        math.Rand(60,  160) * sign(),
        math.Rand(15,  60)  * sign(),
        math.Rand(100, 300) * sign()
    )

    local pos = self:GetPos()
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetScale(6) ed:SetMagnitude(6) ed:SetRadius(600)
    util.Effect("500lb_air", ed, true, true)
    sound.Play("ambient/explosions/explode_4.wav", pos, 140, 85, 1.0)
end

function ENT:CrashExplode()
    if self.TumbleCrashed then return end
    self.TumbleCrashed = true

    local pos = self:GetPos()

    -- Big spread of explosions befitting a strategic bomber.
    local offsets = {
        Vector(0,0,0), Vector(200,0,0), Vector(-200,0,0),
        Vector(0,200,0), Vector(0,-200,0)
    }
    for i, off in ipairs(offsets) do
        local ed = EffectData()
        ed:SetOrigin(pos + off)
        ed:SetScale(7-i) ed:SetMagnitude(7-i) ed:SetRadius(700)
        util.Effect("HelicopterMegaBomb", ed, true, true)
    end

    local ed2 = EffectData() ed2:SetOrigin(pos)
    ed2:SetScale(6) ed2:SetMagnitude(6) ed2:SetRadius(600)
    util.Effect("500lb_air", ed2, true, true)

    local ed3 = EffectData() ed3:SetOrigin(pos + Vector(0,0,100))
    ed3:SetScale(5) ed3:SetMagnitude(5) ed3:SetRadius(500)
    util.Effect("500lb_air", ed3, true, true)

    sound.Play("ambient/explosions/explode_8.wav", pos, 145, 80, 1.0)
    sound.Play("weapon_AWP.Single",               pos, 148, 55, 1.0)

    util.BlastDamage(self, self, pos, 700, 400)
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

    timer.Simple(18, function()
        if IsValid(self) then self:CrashExplode() end
    end)
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug(msg)
    print("[Bombin B-52] " .. tostring(msg))
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink(CurTime() + 0.1)
        return true
    end

    local ct = CurTime()

    if self.IsTumbling and not self.TumbleCrashed then
        local pos     = self:GetPos()
        local groundZ = self.TumbleGroundZ or -16384

        if pos.z <= groundZ + 150 then
            self:CrashExplode()
            return
        end

        local tr = util.TraceLine({
            start  = pos,
            endpos = pos + Vector(0, 0, -200),
            filter = self,
        })
        if tr.HitWorld then self:CrashExplode() return end

        self:NextThink(ct + 0.05)
        return true
    end

    if ct >= self.DieTime then self:Remove() return end

    if not IsValid(self.PhysObj) then
        self.PhysObj = self:GetPhysicsObject()
    end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then
        self.PhysObj:Wake()
    end

    local age  = ct - self.SpawnTime
    local left = self.DieTime - ct
    local alpha = 255
    if age < self.FadeDuration then
        alpha = math.Clamp(255 * (age / self.FadeDuration), 0, 255)
    elseif left < self.FadeDuration then
        alpha = math.Clamp(255 * (left / self.FadeDuration), 0, 255)
    end
    self:SetColor(Color(255, 255, 255, math.Round(alpha)))

    self:HandleWeaponWindow(ct)

    self:NextThink(ct)
    return true
end

-- ============================================================
-- FLIGHT / TUMBLE PHYSICS
-- ============================================================

function ENT:PhysicsUpdate(phys)
    if not self.DieTime or not self.sky then return end

    -- ---- TUMBLE PATH ----
    if self.IsTumbling then
        if self.TumbleCrashed then return end

        local dt      = engine.TickInterval()
        local gravity = physenv.GetGravity().z

        self.TumbleVelocity.z = self.TumbleVelocity.z + gravity * dt

        local pos    = self:GetPos()
        local newPos = pos + self.TumbleVelocity * dt

        local av = self.TumbleAngVelocity
        self.ang = Angle(
            self.ang.p + av.x * dt,
            self.ang.y + av.y * dt,
            self.ang.r + av.z * dt
        )

        self:SetPos(newPos)
        self:SetAngles(self.ang)
        if IsValid(phys) then
            phys:SetPos(newPos)
            phys:SetAngles(self.ang)
        end
        return
    end

    if CurTime() >= self.DieTime then self:Remove() return end

    -- ============================================================
    -- NORMAL FLIGHT
    -- Position integrated here, written once via SetPos/SetAngles.
    -- phys:Set* NOT called during normal flight to prevent
    -- Havok double-move stutter.
    -- ============================================================
    local pos = self:GetPos()
    local dt  = engine.TickInterval()

    -- ---- Altitude drift (near max, tiny range) ----
    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky - math.Rand(0, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(20, 40)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)
    self.JitterPhase     = self.JitterPhase + 0.03
    local liveAlt = math.Clamp(
        self.AltDriftCurrent + math.sin(self.JitterPhase) * self.JitterAmplitude,
        self.sky - self.AltDriftRange,
        self.sky
    )

    -- ---- Orbit steering (cross-product controller) ----
    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local toCenter   = flatCenter - flatPos
    local dist       = toCenter:Length()

    local radialDir  = (dist > 1) and (toCenter / dist) or Vector(0,0,0)
    local tangentDir = Vector(-radialDir.y, radialDir.x, 0) * self.OrbitDirection
    if tangentDir:LengthSqr() <= 0.001 then
        tangentDir = Angle(0, self.flightYaw, 0):Forward()
        tangentDir.z = 0
    end
    tangentDir:Normalize()

    local radialError = 0
    if self.OrbitRadius > 0 then
        radialError = math.Clamp((dist - self.OrbitRadius) / self.OrbitRadius, -1, 1)
    end

    local desiredDir = tangentDir + radialDir * radialError * self.RadialGain

    -- Sky-wall avoidance
    local fwdProbe  = Angle(0, self.flightYaw, 0):Forward()
    local probeDist = math.max(1000, self.Speed * 5)
    local trFwd   = util.QuickTrace(pos, fwdProbe * probeDist, self)
    local trLeft  = util.QuickTrace(pos, fwdProbe:Angle():Right() * -700 + fwdProbe * 500, self)
    local trRight = util.QuickTrace(pos, fwdProbe:Angle():Right() *  700 + fwdProbe * 500, self)

    local skyAvoid = Vector(0,0,0)
    if trFwd.HitSky   then skyAvoid = skyAvoid - fwdProbe end
    if trLeft.HitSky  then skyAvoid = skyAvoid + fwdProbe:Angle():Right() end
    if trRight.HitSky then skyAvoid = skyAvoid - fwdProbe:Angle():Right() end
    skyAvoid.z = 0
    if skyAvoid:LengthSqr() > 0.001 then
        skyAvoid:Normalize()
        desiredDir = desiredDir + skyAvoid * self.SkyAvoidGain
    end

    desiredDir.z = 0
    if desiredDir:LengthSqr() <= 0.001 then desiredDir = tangentDir end
    desiredDir:Normalize()

    -- Yaw step toward desired direction
    local desiredYaw = desiredDir:Angle().y
    local yawDiff    = math.NormalizeAngle(desiredYaw - self.flightYaw)
    local maxStep    = self.MaxTurnRate * dt
    local turnRate   = math.Clamp(yawDiff / dt, -self.MaxTurnRate, self.MaxTurnRate)
    self.flightYaw   = self.flightYaw + math.Clamp(yawDiff, -maxStep, maxStep)

    -- ============================================================
    -- COORDINATED TURN ROLL
    -- B-52: MODEL_YAW_OFFSET=0, mesh not flipped.
    -- Negate both components same as TB-2.
    -- ============================================================
    local turnRateDelta = turnRate - self.PrevTurnRate
    self.PrevTurnRate   = turnRate

    local sustained  = math.Clamp(-turnRate      * ROLL_SUSTAINED_GAIN, -12, 12)
    local transient  = math.Clamp(-turnRateDelta * ROLL_TRANSIENT_GAIN, -8,  8)
    local rollTarget = math.Clamp(sustained + transient, -ROLL_MAX, ROLL_MAX)

    local building = (rollTarget * self.SmoothedRoll >= 0)
                     and (math.abs(rollTarget) > math.abs(self.SmoothedRoll))
    local lerpRate = building and ROLL_LERP_IN or ROLL_LERP_OUT

    self.SmoothedRoll = Lerp(lerpRate, self.SmoothedRoll, rollTarget)

    -- ---- Pitch ----
    local fwdDir       = Angle(0, self.flightYaw, 0):Forward()
    local climbDelta   = math.Clamp((liveAlt - pos.z) / 400, -1, 1)
    self.SmoothedPitch = Lerp(0.03, self.SmoothedPitch, math.Clamp(climbDelta * 5, -6, 6))

    self.ang = Angle(self.SmoothedPitch, self.flightYaw + MODEL_YAW_OFFSET, self.SmoothedRoll)

    -- ---- Position integration ----
    local newPos = pos + fwdDir * self.Speed * dt
    newPos.z = Lerp(0.06, pos.z, liveAlt)

    -- OOB guard
    if not util.IsInWorld(newPos) then
        self:Debug("OOB guard fired - steering to center")
        local toC = flatCenter - Vector(pos.x, pos.y, 0)
        toC.z = 0
        if toC:LengthSqr() < 0.001 then toC = Vector(-fwdProbe.x, -fwdProbe.y, 0) end
        toC:Normalize()
        self.flightYaw = toC:Angle().y
        self.ang = Angle(self.SmoothedPitch, self.flightYaw + MODEL_YAW_OFFSET, self.SmoothedRoll)
        self:SetPos(pos)
        self:SetAngles(self.ang)
        return
    end

    self:SetPos(newPos)
    self:SetAngles(self.ang)

    if not self:IsInWorld() then
        self:Debug("Out of world - center recovery")
        local safePos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
        self:SetPos(safePos)
    end
end

-- ============================================================
-- TARGET / MUZZLE HELPERS
-- ============================================================

function ENT:GetPrimaryTarget()
    local closest, closestDist = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(self.CenterPos)
        if d < closestDist then closestDist = d closest = ply end
    end
    return closest
end

function ENT:GetTargetGroundPos()
    local target = self:GetPrimaryTarget()
    if IsValid(target) then return target:GetPos() end
    local tr = util.QuickTrace(
        Vector(self.CenterPos.x, self.CenterPos.y, self.sky),
        Vector(0, 0, -30000), self
    )
    return tr.HitPos
end

function ENT:GetMuzzleWorldPos(localPoint)
    return self:LocalToWorld(localPoint)
end

function ENT:SpawnMuzzleFX(worldPos)
    local ed = EffectData()
    ed:SetOrigin(worldPos)
    ed:SetAngles(self:GetAngles())
    ed:SetEntity(self)
    util.Effect("gred_particle_aircraft_muzzle", ed, true, true)
end

-- ============================================================
-- WEAPON WINDOW CONTROLLER
-- ============================================================

function ENT:HandleWeaponWindow(ct)
    if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
        self:PickNewWeapon(ct)
    end

    if self.CurrentWeapon == "s8_salvo" then
        self:UpdateS8Salvo(ct)
    elseif self.CurrentWeapon == "vikhr" then
        self:UpdateVikhr(ct)
    end
end

function ENT:PickNewWeapon(ct)
    local roll = math.random(1, 2)
    self.CurrentWeapon   = (roll == 1) and "s8_salvo" or "vikhr"
    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug("Weapon: " .. self.CurrentWeapon)

    if self.CurrentWeapon == "s8_salvo" then
        self.S8_ShotsFired  = 0
        self.S8_NextShot    = ct + 0.5
        self.S8_MuzzleIndex = 1
    else
        self.VIKHR_ShotsFired  = 0
        self.VIKHR_NextShot    = ct + 1.0
        self.VIKHR_MuzzleIndex = 1
    end
end

-- ============================================================
-- SLOT 1 - S-8 salvo
-- ============================================================

function ENT:UpdateS8Salvo(ct)
    if self.S8_ShotsFired >= self.S8_Count then return end
    if ct < self.S8_NextShot then return end

    self.S8_NextShot   = ct + self.S8_Delay
    self.S8_ShotsFired = self.S8_ShotsFired + 1

    local muzzleLocal = self.S8_MuzzlePoints[self.S8_MuzzleIndex]
    self.S8_MuzzleIndex = (self.S8_MuzzleIndex % #self.S8_MuzzlePoints) + 1

    local muzzlePos = self:GetMuzzleWorldPos(muzzleLocal)
    local targetPos = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.S8_Scatter, self.S8_Scatter),
        math.Rand(-self.S8_Scatter, self.S8_Scatter),
        0
    )
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local rocket = ents.Create("gb_s8kom_rocket")
    if not IsValid(rocket) then self:Debug("gb_s8kom_rocket failed") return end

    rocket:SetPos(muzzlePos)
    rocket:SetAngles(dir:Angle())
    rocket:SetOwner(self)
    rocket.IsOnPlane = true
    rocket:Spawn() rocket:Activate()
    rocket.Armed = true rocket.ShouldExplode = true
    rocket:Launch()
    rocket:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local rPhys = rocket:GetPhysicsObject()
    local uPhys = self:GetPhysicsObject()
    if IsValid(rPhys) and IsValid(uPhys) then rPhys:AddVelocity(uPhys:GetVelocity()) end

    self:SpawnMuzzleFX(muzzlePos)
    sound.Play(table.Random(SOUNDS_ATGM_IGNITE), muzzlePos, 110, math.random(95,105), 1.0)
    timer.Simple(0.1, function() if IsValid(rocket) then sound.Play(table.Random(SOUNDS_LAUNCH), rocket:GetPos(), 105, math.random(95,105), 1.0) end end)

    rocket.IdleSound = CreateSound(rocket, SOUND_ROCKET_IDLE)
    if rocket.IdleSound then rocket.IdleSound:Play() rocket.IdleSound:ChangePitch(math.random(90,115),0) rocket.IdleSound:ChangeVolume(0.8,0) end

    local oldR = rocket.OnRemove
    rocket.OnRemove = function(s) if oldR then oldR(s) end if s.IdleSound then s.IdleSound:Stop() end end
    local oldE = rocket.OnExplode
    rocket.OnExplode = function(s,p,n) if oldE then oldE(s,p,n) end if s.IdleSound then s.IdleSound:Stop() end end

    constraint.NoCollide(rocket, self, 0, 0)
    local ref = rocket
    timer.Simple(0.5, function() if IsValid(ref) and IsValid(self) then constraint.RemoveConstraints(ref,"NoCollide") end end)
end

-- ============================================================
-- SLOT 2 - Vikhr ATGM
-- ============================================================

function ENT:UpdateVikhr(ct)
    if self.VIKHR_ShotsFired >= self.VIKHR_Count then return end
    if ct < self.VIKHR_NextShot then return end

    self.VIKHR_NextShot   = ct + self.VIKHR_Delay
    self.VIKHR_ShotsFired = self.VIKHR_ShotsFired + 1

    local muzzleLocal = self.VIKHR_MuzzlePoints[self.VIKHR_MuzzleIndex]
    self.VIKHR_MuzzleIndex = (self.VIKHR_MuzzleIndex % #self.VIKHR_MuzzlePoints) + 1

    local muzzlePos = self:GetMuzzleWorldPos(muzzleLocal)
    local targetPos = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.VIKHR_Scatter, self.VIKHR_Scatter),
        math.Rand(-self.VIKHR_Scatter, self.VIKHR_Scatter),
        0
    )
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local rocket = ents.Create("gb_9k121_rocket")
    if not IsValid(rocket) then self:Debug("gb_9k121_rocket failed") return end

    rocket:SetPos(muzzlePos)
    rocket:SetAngles(dir:Angle())
    rocket:SetOwner(self)
    rocket.IsOnPlane = true
    rocket:Spawn() rocket:Activate()
    rocket.Armed = true rocket.ShouldExplode = true rocket.ShouldExplodeOnImpact = true
    rocket:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local startpos = self:LocalToWorld(self:OBBCenter())
    local tr = util.TraceHull({ start=startpos, endpos=startpos+dir*500000, mins=Vector(-25,-25,-25), maxs=Vector(25,25,25), filter=self })

    local rPhys = rocket:GetPhysicsObject()
    local uPhys = self:GetPhysicsObject()
    if IsValid(rPhys) and IsValid(uPhys) then rPhys:AddVelocity(uPhys:GetVelocity()) end

    constraint.NoCollide(rocket, self, 0, 0)
    local ref = rocket
    timer.Simple(0.25, function()
        if not IsValid(ref) then return end
        if tr.Hit then
            ref.JDAM = true ref.target = tr.Entity
            ref.targetOffset = IsValid(tr.Entity) and tr.Entity:WorldToLocal(tr.HitPos) or tr.HitPos
            ref.dropping = true
        end
        ref.Armed = true ref:Launch() ref:SetCollisionGroup(0)
    end)

    self:SpawnMuzzleFX(muzzlePos)
    sound.Play(table.Random(SOUNDS_ATGM_IGNITE), muzzlePos, 0, 100, 1.0)
    timer.Simple(0.1, function() if IsValid(rocket) then sound.Play(table.Random(SOUNDS_LAUNCH), rocket:GetPos(), 105, math.random(95,105), 1.0) end end)

    rocket.IdleSound = CreateSound(rocket, SOUND_ROCKET_IDLE)
    if rocket.IdleSound then rocket.IdleSound:Play() rocket.IdleSound:ChangePitch(math.random(85,110),0) rocket.IdleSound:ChangeVolume(0.9,0) end

    local oldR = rocket.OnRemove
    rocket.OnRemove = function(s) if oldR then oldR(s) end if s.IdleSound then s.IdleSound:Stop() end end
    local oldE = rocket.OnExplode
    rocket.OnExplode = function(s,p,n)
        if oldE then oldE(s,p,n) end
        if s.IdleSound then s.IdleSound:Stop() end
        local hp = p or s:GetPos()
        local e1=EffectData() e1:SetOrigin(hp) e1:SetScale(4) e1:SetMagnitude(4) e1:SetRadius(400) util.Effect("500lb_air",e1,true,true)
        local e2=EffectData() e2:SetOrigin(hp+Vector(0,0,60)) e2:SetScale(3) e2:SetMagnitude(3) e2:SetRadius(300) util.Effect("500lb_air",e2,true,true)
        local e3=EffectData() e3:SetOrigin(hp) e3:SetScale(4) e3:SetMagnitude(4) e3:SetRadius(400) util.Effect("HelicopterMegaBomb",e3,true,true)
    end
end

-- ============================================================
-- GROUND FINDER
-- ============================================================

function ENT:FindGround(centerPos)
    local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
    local endPos     = Vector(centerPos.x, centerPos.y, -16384)
    local filterList = { self }
    local maxIter    = 0

    while maxIter < 100 do
        local tr = util.TraceLine({ start = startPos, endpos = endPos, filter = filterList })
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then
            table.insert(filterList, tr.Entity)
        else break end
        maxIter = maxIter + 1
    end

    return -1
end

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
    if self.EngineLoop then
        self.EngineLoop:ChangeVolume(0, 0.5)
        timer.Simple(0.6, function()
            if self.EngineLoop then self.EngineLoop:Stop() end
        end)
    end
end
