-- ============================================================
-- CONTRAIL SYSTEM  --  ent_bombin_support_b52
-- 5 persistent beam trails: 4 engine pod trails + 1 tail trail.
-- ============================================================

local TRAIL_MATERIAL = Material("trails/smoke")
local SAMPLE_RATE    = 0.025

local TRAIL_OFFSETS = {
    Vector(-30, -200, -15),
    Vector(-30, -100, -15),
    Vector(-30,  100, -15),
    Vector(-30,  200, -15),
    Vector(-120,   0, -10),
}

local CONTRAIL_CFG = {
    r = 255, g = 255, b = 255,
    a = 140,
    startSize = 6,
    endSize   = 40,
    lifetime  = 8,
}

local B52Trails = {}

local function EnsureRegistered(entIndex)
    if B52Trails[entIndex] then return end
    B52Trails[entIndex] = {}
    for i = 1, #TRAIL_OFFSETS do
        B52Trails[entIndex][i] = { nextSample = 0, positions = {} }
    end
end

local function DrawBeam(positions, cfg)
    local n = #positions
    if n < 2 then return end

    local Time = CurTime()
    local lt   = cfg.lifetime

    for i = n, 1, -1 do
        if Time - positions[i].time > lt then
            table.remove(positions, i)
        end
    end

    n = #positions
    if n < 2 then return end

    render.SetMaterial(TRAIL_MATERIAL)
    render.StartBeam(n)
    for _, pd in ipairs(positions) do
        local Scale = math.Clamp((pd.time + lt - Time) / lt, 0, 1)
        local size  = cfg.startSize * Scale + cfg.endSize * (1 - Scale)
        render.AddBeam(pd.pos, size, pd.time * 50, Color(cfg.r, cfg.g, cfg.b, cfg.a * Scale * Scale))
    end
    render.EndBeam()
end

hook.Add("Think", "bombin_b52_contrail_update", function()
    local Time = CurTime()

    for _, ent in ipairs(ents.FindByClass("ent_bombin_support_b52")) do
        EnsureRegistered(ent:EntIndex())
    end

    for entIndex, streams in pairs(B52Trails) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            B52Trails[entIndex] = nil
            continue
        end

        for i, state in ipairs(streams) do
            if Time < state.nextSample then continue end
            state.nextSample = Time + SAMPLE_RATE
            local wpos = LocalToWorld(TRAIL_OFFSETS[i], Angle(0,0,0), ent:GetPos(), ent:GetAngles())
            table.insert(state.positions, { time = Time, pos = wpos })
            table.sort(state.positions, function(a, b) return a.time > b.time end)
        end
    end
end)

hook.Add("PostDrawTranslucentRenderables", "bombin_b52_contrail_draw", function(bDepth, bSkybox)
    if bSkybox then return end
    for _, streams in pairs(B52Trails) do
        for _, state in ipairs(streams) do
            DrawBeam(state.positions, CONTRAIL_CFG)
        end
    end
end)
