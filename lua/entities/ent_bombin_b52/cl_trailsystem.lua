-- ============================================================
-- CONTRAIL SYSTEM  --  ent_bombin_b52
-- 5 emission points spread across the wing span (X axis).
-- Model-local axes: X = right/left (wingspan), Y = fwd/back, Z = up
-- B-52 has 8 engines in 4 paired pods:
--   inner pods ~±120 HU from centerline
--   outer pods ~±230 HU from centerline
-- Plus one center-fuselage trail.
-- ============================================================

local TRAIL_MATERIAL = Material( "trails/smoke" )
local SAMPLE_RATE    = 0.025

-- X = wingspan offset, Y = rear of engine pod (negative = aft), Z = slight up
local TRAIL_OFFSETS = {
    Vector(  230, -60,  0 ),   -- outer-right engine pod pair
    Vector(  120, -60,  0 ),   -- inner-right engine pod pair
    Vector( -120, -60,  0 ),   -- inner-left  engine pod pair
    Vector( -230, -60,  0 ),   -- outer-left  engine pod pair
    Vector(    0, -80,  0 ),   -- fuselage center (faint)
}

local CONTRAIL_CFG = {
    r = 255, g = 255, b = 255, a = 120,
    startSize = 28, endSize = 8, lifetime = 8,
}

local B52Trails = {}

local function EnsureRegistered( entIndex )
    if B52Trails[entIndex] then return end
    local streams = {}
    for i = 1, #TRAIL_OFFSETS do
        streams[i] = { nextSample = 0, positions = {} }
    end
    B52Trails[entIndex] = streams
end

local function DrawBeam( positions, cfg )
    local n = #positions
    if n < 2 then return end
    local Time = CurTime()
    local lt   = cfg.lifetime
    for i = n, 1, -1 do
        if Time - positions[i].time > lt then table.remove( positions, i ) end
    end
    n = #positions
    if n < 2 then return end
    render.SetMaterial( TRAIL_MATERIAL )
    render.StartBeam( n )
    for _, pd in ipairs( positions ) do
        local Scale = math.Clamp( (pd.time + lt - Time) / lt, 0, 1 )
        local size  = cfg.startSize * Scale + cfg.endSize * (1 - Scale)
        render.AddBeam( pd.pos, size, pd.time * 50,
            Color( cfg.r, cfg.g, cfg.b, cfg.a * Scale * Scale ) )
    end
    render.EndBeam()
end

hook.Add( "Think", "bombin_b52_contrail_update", function()
    local Time = CurTime()
    for _, ent in ipairs( ents.FindByClass( "ent_bombin_b52" ) ) do
        EnsureRegistered( ent:EntIndex() )
    end
    for entIndex, streams in pairs( B52Trails ) do
        local ent = Entity( entIndex )
        if not IsValid( ent ) then B52Trails[entIndex] = nil continue end
        local pos = ent:GetPos()
        local ang = ent:GetAngles()
        for i, stream in ipairs( streams ) do
            if Time < stream.nextSample then continue end
            stream.nextSample = Time + SAMPLE_RATE
            local wpos = LocalToWorld( TRAIL_OFFSETS[i], Angle(0,0,0), pos, ang )
            table.insert( stream.positions, { time = Time, pos = wpos } )
            table.sort( stream.positions, function(a,b) return a.time > b.time end )
        end
    end
end )

hook.Add( "PostDrawTranslucentRenderables", "bombin_b52_contrail_draw", function( bDepth, bSkybox )
    if bSkybox then return end
    for _, streams in pairs( B52Trails ) do
        for _, stream in ipairs( streams ) do
            DrawBeam( stream.positions, CONTRAIL_CFG )
        end
    end
end )
