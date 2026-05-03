AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local MODEL_YAW_OFFSET = 0

local ROLL_SUSTAINED_GAIN = 1.6
local ROLL_TRANSIENT_GAIN = 40.0
local ROLL_MAX            = 15.0
local ROLL_LERP_IN        = 0.05
local ROLL_LERP_OUT       = 0.008

local function HasGred()
    return gred and gred.CreateShell
end

local ENGINE_LOOP_SOUND = "b52/b52.wav"

local SOUNDS_ATGM_IGNITE = { "ATGM.wav", "ATGM2.wav", "ATGM3.wav", "ATGM4.wav" }
local SOUNDS_LAUNCH = { "launch1.wav", "launch2.wav" }
local SOUND_ROCKET_IDLE = "rocket_idle.wav"

local CFG_WeaponWindow = 10
local CFG_S8_Delay        = 0.4
local CFG_S8_Count        = 4
local CFG_S8_Scatter      = 800
local CFG_S8_MuzzlePoints = { Vector(60, -70, -5), Vector(60, 70, -5) }
local CFG_VIKHR_Delay        = 4.0
local CFG_VIKHR_Count        = 2
local CFG_VIKHR_Scatter      = 60
local CFG_VIKHR_MuzzlePoints = { Vector(60, -70, -5), Vector(60, 70, -5) }
local CFG_FadeDuration = 3.0
local CFG_MaxHP        = 400

util.AddNetworkString("bombin_plane_damage_tier_b52")

local function CalcTier(hp, maxHP)
    local frac = hp / maxHP
    if frac > 0.66 then return 0
    elseif frac > 0.33 then return 1
    elseif frac > 0 then return 2
    else return 3 end
end

local function BroadcastTier(ent, tier)
    net.Start("bombin_plane_damage_tier_b52")
        net.WriteUInt(ent:EntIndex(), 16)
        net.WriteUInt(tier, 2)
    net.Broadcast()
end

function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
    self.CallDir      = self:GetVar("CallDir",      Vector(1,0,0))
    self.Lifetime     = self:GetVar("Lifetime",     90)
    self.Speed        = self:GetVar("Speed",        280)
    self.OrbitRadius  = self:GetVar("OrbitRadius",  4000)
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

    self.OrbitDirection = (math.random(2) == 1) and 1 or -1
    self.OrbitTangent   = self.CallDir:Angle():Right() * self.OrbitDirection

    self.RadialGain   = 0.38
    self.SkyAvoidGain = 0.80
    self.MaxTurnRate  = 18
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
    self.JitterAmplitude = 4

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(20, 40)
    self.AltDriftRange    = 150
    self.AltDriftLerp     = 0.001

    self.SmoothedRoll  = 0
    self.SmoothedPitch = 0

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

    self:Debug("B-52 spawned at " .. tostring(spawnPos))
end

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end

    local hp = self:GetNWInt("HP", self.MaxHP)
    hp = hp - dmginfo:GetDamage()
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

    local travelFwd = Angle(0, self.flightYaw, 0):Forward()
    local speed     = self.Speed or 280

    self.TumbleVelocity = Vector(travelFwd.x * speed, travelFwd.y * speed, -300)

    local sign = function() return (math.random(2) == 1) and 1 or -1 end
    self.TumbleAngVelocity = Vector(
        math.Rand(60,180) * sign(),
        math.Rand(15,60)  * sign(),
        math.Rand(100,300) * sign()
    )

    local pos = self:GetPos()
    local ed = EffectData()
    ed:SetOrigin(pos)
    ed:SetScale(6)
    ed:SetMagnitude(6)
    ed:SetRadius(600)
    util.Effect("500lb_air", ed, true, true)
    sound.Play("ambient/explosions/explode_4.wav", pos, 140, 85, 1.0)
end

function ENT:CrashExplode()
    if self.TumbleCrashed then return end
    self.TumbleCrashed = true

    local pos = self:GetPos()
    for i, offset in ipairs({ Vector(0,0,0), Vector(200,0,0), Vector(-200,0,0), Vector(0,200,0), Vector(0,-200,0) }) do
        local ed = EffectData()
        ed:SetOrigin(pos + offset)
        ed:SetScale(6 - i)
        ed:SetMagnitude(6 - i)
        ed:SetRadius(500)
        util.Effect("HelicopterMegaBomb", ed, true, true)
    end

    sound.Play("ambient/explosions/explode_8.wav", pos, 145, 80, 1.0)
    sound.Play("weapon_AWP.Single", pos, 148, 55, 1.0)
    util.BlastDamage(self, self, pos, 700, 400)
    self:Remove()
end

function ENT:DestroyUAV()
    if self.IsDestroyed then return end
    self.IsDestroyed = true

    if self.EngineLoop then
        self.EngineLoop:ChangeVolume(0, 0.5)
        timer.Simple(0.6, function()
            if self.EngineLoop then self.EngineLoop:Stop() end
        end)
    end

    self:StartTumble()

    timer.Simple(18, function()
        if IsValid(self) then self:CrashExplode() end
    end)
end

function ENT:Debug(msg)
    print("[Bombin B-52] " .. tostring(msg))
end

function ENT:FindGround(pos)
    local tr = util.TraceLine({
        start  = pos + Vector(0,0,50),
        endpos = pos - Vector(0,0,65536),
        filter = self,
    })
    if tr.Hit then return tr.HitPos.z end
    return -1
end

function ENT:HandleWeaponWindow(ct)
    if not HasGred() then return end

    if not self.CurrentWeapon then
        local players = player.GetHumans()
        if #players == 0 then return end
        local target = players[math.random(#players)]
        if not IsValid(target) then return end
        local dist = self:GetPos():Distance(target:GetPos())
        if dist > 6000 then return end
        self.CurrentWeapon   = (math.random(2) == 1) and "S8" or "VIKHR"
        self.WeaponWindowEnd = ct + self.WeaponWindow
        self.S8_ShotsFired = 0
        self.S8_MuzzleIndex = 1
        self.VIKHR_ShotsFired = 0
        self.VIKHR_MuzzleIndex = 1
    end

    if ct > self.WeaponWindowEnd then
        self.CurrentWeapon = nil
        return
    end

    if self.CurrentWeapon == "S8" then
        self:FireS8(ct)
    elseif self.CurrentWeapon == "VIKHR" then
        self:FireVIKHR(ct)
    end
end

function ENT:FireS8(ct)
    if self.S8_ShotsFired >= self.S8_Count then self.CurrentWeapon = nil return end
    if ct < self.S8_NextShot then return end
    self.S8_NextShot   = ct + self.S8_Delay
    local muzzleLocal  = self.S8_MuzzlePoints[self.S8_MuzzleIndex]
    self.S8_MuzzleIndex = (self.S8_MuzzleIndex % #self.S8_MuzzlePoints) + 1

    local muzzleWorld = self:LocalToWorld(muzzleLocal)
    local players     = player.GetHumans()
    if #players == 0 then return end
    local target = players[math.random(#players)]
    if not IsValid(target) then return end

    local scatter = Vector(math.Rand(-1,1), math.Rand(-1,1), 0) * self.S8_Scatter
    local targetPos = target:GetPos() + scatter
    local dir = (targetPos - muzzleWorld):GetNormalized()

    local shell = gred.CreateShell("rocket_s8", muzzleWorld, dir:Angle(), self)
    if IsValid(shell) then shell:SetOwner(self) end

    sound.Play(SOUNDS_LAUNCH[math.random(#SOUNDS_LAUNCH)], muzzleWorld, 120, 100, 1)
    self.S8_ShotsFired = self.S8_ShotsFired + 1
end

function ENT:FireVIKHR(ct)
    if self.VIKHR_ShotsFired >= self.VIKHR_Count then self.CurrentWeapon = nil return end
    if ct < self.VIKHR_NextShot then return end
    self.VIKHR_NextShot = ct + self.VIKHR_Delay
    local muzzleLocal   = self.VIKHR_MuzzlePoints[self.VIKHR_MuzzleIndex]
    self.VIKHR_MuzzleIndex = (self.VIKHR_MuzzleIndex % #self.VIKHR_MuzzlePoints) + 1

    local muzzleWorld = self:LocalToWorld(muzzleLocal)
    local players     = player.GetHumans()
    if #players == 0 then return end
    local target = players[math.random(#players)]
    if not IsValid(target) then return end

    local scatter = Vector(math.Rand(-1,1), math.Rand(-1,1), 0) * self.VIKHR_Scatter
    local targetPos = target:GetPos() + scatter
    local dir = (targetPos - muzzleWorld):GetNormalized()

    local shell = gred.CreateShell("missile_vikhr", muzzleWorld, dir:Angle(), self)
    if IsValid(shell) then shell:SetOwner(self) end

    sound.Play(SOUNDS_ATGM_IGNITE[math.random(#SOUNDS_ATGM_IGNITE)], muzzleWorld, 120, 100, 1)
    self.VIKHR_ShotsFired = self.VIKHR_ShotsFired + 1
end

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink(CurTime() + 0.1)
        return true
    end

    local ct = CurTime()

    if self.IsTumbling and not self.TumbleCrashed then
        local pos = self:GetPos()
        if pos.z <= (self.TumbleGroundZ or -16384) + 200 then
            self:CrashExplode()
            return
        end
        local tr = util.TraceLine({ start = pos, endpos = pos + Vector(0,0,-300), filter = self })
        if tr.HitWorld then self:CrashExplode() return end
        self:NextThink(ct + 0.05)
        return true
    end

    if ct >= self.DieTime then self:Remove() return end

    if not IsValid(self.PhysObj) then self.PhysObj = self:GetPhysicsObject() end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then self.PhysObj:Wake() end

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

function ENT:PhysicsUpdate(phys)
    if not self.DieTime or not self.sky then return end

    if self.IsTumbling then
        if self.TumbleCrashed then return end
        local dt      = engine.TickInterval()
        local gravity = physenv.GetGravity().z
        self.TumbleVelocity.z = self.TumbleVelocity.z + gravity * dt
        local newPos = self:GetPos() + self.TumbleVelocity * dt
        local curAng = self:GetAngles()
        local newAng = Angle(
            curAng.p + self.TumbleAngVelocity.x * dt,
            curAng.y + self.TumbleAngVelocity.y * dt,
            curAng.r + self.TumbleAngVelocity.z * dt
        )
        phys:SetPos(newPos)
        phys:SetAngles(newAng)
        phys:SetVelocity(Vector(0,0,0))
        phys:SetAngleVelocity(Vector(0,0,0))
        return
    end

    local ct = CurTime()
    local dt = engine.TickInterval()
    if dt <= 0 then return end

    if ct >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
        self.AltDriftNextPick = ct + math.Rand(20, 40)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)

    local pos = self:GetPos()
    local toCenter = Vector(self.CenterPos.x - pos.x, self.CenterPos.y - pos.y, 0)
    local dist = toCenter:Length()
    local radErr = dist - self.OrbitRadius

    local radialDir = toCenter:GetNormalized()
    local tangentDir = Vector(-radialDir.y, radialDir.x, 0) * self.OrbitDirection
    local radialCorr = radialDir * radErr * self.RadialGain

    local desiredVel2D = (tangentDir * self.Speed + radialCorr)
    local yaw = math.atan2(desiredVel2D.y, desiredVel2D.x)
    local yawDeg = math.deg(yaw)

    local prevYaw  = self.flightYaw or yawDeg
    local turnRate = math.AngleDifference(yawDeg, prevYaw) / dt
    turnRate = math.Clamp(turnRate, -self.MaxTurnRate, self.MaxTurnRate)
    self.flightYaw = yawDeg

    local transient   = (turnRate - self.PrevTurnRate) / dt
    self.PrevTurnRate = turnRate

    local targetRoll  = -(turnRate * ROLL_SUSTAINED_GAIN + transient * ROLL_TRANSIENT_GAIN)
    targetRoll        = math.Clamp(targetRoll, -ROLL_MAX, ROLL_MAX)
    local lerpSpeed   = (math.abs(targetRoll) > math.abs(self.SmoothedRoll)) and ROLL_LERP_IN or ROLL_LERP_OUT
    self.SmoothedRoll = Lerp(lerpSpeed, self.SmoothedRoll, targetRoll)

    local jitter = math.sin(ct * 1.2 + self.JitterPhase) * self.JitterAmplitude
    local altErr = self.AltDriftCurrent - pos.z
    local vz = math.Clamp(altErr * self.SkyAvoidGain, -120, 120)

    local vel = Vector(desiredVel2D.x, desiredVel2D.y, vz)
    phys:SetVelocity(vel)
    phys:SetPos(Vector(pos.x, pos.y, pos.z))

    self.ang = Angle(jitter * 0.05, self.flightYaw + MODEL_YAW_OFFSET, self.SmoothedRoll)
    phys:SetAngles(self.ang)
    phys:SetAngleVelocity(Vector(0,0,0))
end
