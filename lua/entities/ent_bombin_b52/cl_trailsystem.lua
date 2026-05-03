-- ============================================================
--  B-52 Stratofortress – 5-engine contrail system
--  lua/entities/ent_bombin_b52/cl_trailsystem.lua
--
--  The B-52G has 8 turbojet engines mounted in 4 double-pods
--  under the swept wing.  We represent them with 5 contrail
--  emitters:
--    Left outer pod,  Left inner pod
--    Right inner pod, Right outer pod
--    + one central / fuselage-wash trail
--
--  Offsets are in the entity's local space (forward = +X).
-- ============================================================

-- Local offsets for each contrail emitter
local TRAIL_OFFSETS = {
    Vector( -220,  -210, -12 ),   -- left  outer engine pod
    Vector( -180,  -110, -12 ),   -- left  inner engine pod
    Vector(  0,       0,  -6 ),   -- fuselage center wash
    Vector( -180,   110, -12 ),   -- right inner engine pod
    Vector( -220,   210, -12 ),   -- right outer engine pod
}

-- Per-trail visual variation
local TRAIL_WIDTHS = { 14, 12, 10, 12, 14 }
local TRAIL_LIFE   = { 4.0, 3.6, 3.2, 3.6, 4.0 }

local TRAIL_MAT    = Material( "trails/smoke" )
local TRAIL_COLOR  = Color( 255, 255, 255, 220 )

local activeTrails = {}

-- ============================================================
-- START TRAILS
-- ============================================================
local function StartTrails( ent )
    local entIdx = ent:EntIndex()
    if activeTrails[entIdx] then return end  -- already running

    activeTrails[entIdx] = {}

    for i, localOff in ipairs( TRAIL_OFFSETS ) do
        -- We parent each trail to a tiny invisible helper entity
        -- so the trail follows the exact engine-pod position.
        -- Using util.SpriteTrail on the plane itself with a fixed
        -- attachment would apply only one offset, so we drive the
        -- trail start-pos manually each tick instead.
        activeTrails[entIdx][i] = {
            startPos = ent:LocalToWorld( localOff ),
            width    = TRAIL_WIDTHS[i] or 12,
            life     = TRAIL_LIFE[i]   or 3.5,
            segments = {}, -- { pos, time }
        }
    end
end

-- ============================================================
-- STOP TRAILS
-- ============================================================
local function StopTrails( entIdx )
    activeTrails[entIdx] = nil
end

-- ============================================================
-- HOOK: Think – update segment positions
-- ============================================================
hook.Add( "Think", "BombinB52_TrailThink", function()
    local ct = CurTime()

    for entIdx, trails in pairs( activeTrails ) do
        local ent = Entity( entIdx )
        if not IsValid( ent ) then
            StopTrails( entIdx )
            continue
        end

        for i, trail in ipairs( trails ) do
            local worldPos = ent:LocalToWorld( TRAIL_OFFSETS[i] )

            -- Push new segment
            table.insert( trail.segments, 1, { pos = worldPos, t = ct } )

            -- Prune old segments
            local lifeLimit = trail.life
            while #trail.segments > 0 and ( ct - trail.segments[#trail.segments].t ) > lifeLimit do
                table.remove( trail.segments )
            end
        end
    end
end )

-- ============================================================
-- HOOK: DrawTranslucentRenderables – render each trail
-- ============================================================
hook.Add( "DrawTranslucentRenderables", "BombinB52_TrailDraw", function()
    local ct = CurTime()

    for entIdx, trails in pairs( activeTrails ) do
        local ent = Entity( entIdx )
        if not IsValid( ent ) then continue end

        local entAlpha = ent:GetColor().a / 255  -- respect fade-in / fade-out

        for _, trail in ipairs( trails ) do
            local segs = trail.segments
            if #segs < 2 then continue end

            render.SetMaterial( TRAIL_MAT )
            render.StartBeam( #segs )

            for j, seg in ipairs( segs ) do
                -- Age fraction: 0 = newest, 1 = oldest
                local age      = ct - seg.t
                local ageFrac  = math.Clamp( age / trail.life, 0, 1 )

                -- Width tapers from full at head to 0 at tail
                local w        = trail.width * ( 1 - ageFrac )

                -- Alpha tapers from opaque at head to transparent at tail
                local a        = TRAIL_COLOR.a * ( 1 - ageFrac ) * entAlpha

                render.AddBeam(
                    seg.pos,
                    w,
                    j / #segs,
                    Color( TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, a )
                )
            end

            render.EndBeam()
        end
    end
end )

-- ============================================================
-- ENT hooks – call these from cl_init.lua via ENT:Initialize
-- and ENT:OnRemove
-- ============================================================

function ENT:InitTrails()
    StartTrails( self )
end

function ENT:RemoveTrails()
    StopTrails( self:EntIndex() )
end

-- Auto-hook into entity lifecycle
local _origInit   = ENT.Initialize
local _origRemove = ENT.OnRemove

function ENT:Initialize()
    if _origInit then _origInit( self ) end
    self:InitTrails()
end

function ENT:OnRemove()
    self:RemoveTrails()
    if _origRemove then _origRemove( self ) end
end
