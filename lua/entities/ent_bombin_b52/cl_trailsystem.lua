-- ============================================================
-- CONTRAIL SYSTEM  --  ent_bombin_b52
-- 5 persistent beam trails simulating the B-52's 8-engine exhausts.
-- 4 engine positions (left outer, left inner, right inner, right outer)
-- + 1 central belly trail.
-- ============================================================

local TRAIL_MATERIAL = Material( "trails/smoke" )
local SAMPLE_RATE    = 0.025   -- 40 fps sampling

-- 5 emission points: outboard left, inboard left, inboard right, outboard right, + belly center.
-- X = forward/back, Y = left/right (positive = right), Z = up/down.
local TRAIL_OFFSETS = {
    Vector( -130,  -180, -8  ),   -- Left outer engines pod
    Vector( -130,   -80, -8  ),   -- Left inner engines pod
    Vector( -130,    80, -8  ),   -- Right inner engines pod
    Vector( -130,   180, -8  ),   -- Right outer engines pod
    Vector( -130,     0, -14 ),   -- Belly / center
}

-- Contrail config: thinner near B-52, widens behind it.
local CONTRAIL_CFG = {
    r         = 255,
    g         = 255,
    b         = 255,
    a         = 120,
    startSize = 5,
    endSize   = 28,
    lifetime  = 8,
}

local B52Trails = {}   -- [entIndex] = { trails = { [1..5] = { nextSample, positions } } }

local function EnsureRegistered( entIndex )
    if B52Trails[entIndex] then return end
    local trails = {}
    for i = 1, 5 do
        trails[i] = { nextSample = 0, positions = {} }
    end
    B52Trails[entIndex] = { trails = trails }
end

local function DrawBeam( positions, cfg )
    local n = #positions
    if n < 2 then return end

    local Time = CurTime()
    local lt   = cfg.lifetime

    for i = n, 1, -1 do
        if Time - positions[i].time > lt then
            table.remove( positions, i )
        end
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

    for entIndex, data in pairs( B52Trails ) do
        local ent = Entity( entIndex )
        if not IsValid( ent ) then
            B52Trails[entIndex] = nil
            continue
        end

        for i, trail in ipairs( data.trails ) do
            if Time < trail.nextSample then continue end
            trail.nextSample = Time + SAMPLE_RATE

            local wpos = LocalToWorld( TRAIL_OFFSETS[i], Angle(0,0,0), ent:GetPos(), ent:GetAngles() )
            table.insert( trail.positions, { time = Time, pos = wpos } )
            table.sort( trail.positions, function( a, b ) return a.time > b.time end )
        end
    end
end )

hook.Add( "PostDrawTranslucentRenderables", "bombin_b52_contrail_draw", function( bDepth, bSkybox )
    if bSkybox then return end
    for _, data in pairs( B52Trails ) do
        for _, trail in ipairs( data.trails ) do
            DrawBeam( trail.positions, CONTRAIL_CFG )
        end
    end
end )
