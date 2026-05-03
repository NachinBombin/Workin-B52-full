if not CLIENT then return end

-- ============================================================
-- SPAWNLIST REGISTRATION
-- Fix: do NOT shadow the hook's `node` arg with a local.
-- tree:AddNode returns a DTree_Node; MakePopulator is only
-- valid when called on that node BEFORE the tree is laid out.
-- Use a simple icon-add pattern instead, which is always safe.
-- ============================================================

hook.Add("PopulateContent", "BombinSupportB52_SpawnMenu", function(pnlContent, tree, node)
    local cat = tree:AddNode("Bombin Support", "icon16/bomb.png")

    cat:MakePopulator(function(panel)
        local b52section = vgui.Create("ContentIcon", panel)
        b52section:SetContentType("entity")
        b52section:SetSpawnName("ent_bombin_support_b52")
        b52section:SetName("Support B-52 Stratofortress")
        b52section:SetMaterial("entities/ent_bombin_support_b52.png")
        b52section:SetToolTip("Autonomous B-52 Stratofortress.\nOrbits at near-maximum altitude with 5 contrails.\nEngages with S-8 rockets and Vikhr ATGMs.")
        panel:Add(b52section)
    end)
end)

-- ============================================================
-- CONSOLE COMMAND - manual test spawn
-- ============================================================

concommand.Add("bombin_spawnb52", function()
    if not IsValid(LocalPlayer()) then return end
    net.Start("BombinSupportB52_ManualSpawn")
    net.SendToServer()
end)

-- ============================================================
-- UTILITIES TAB
-- ============================================================

hook.Add("AddToolMenuTabs", "BombinSupportB52_Tab", function()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
end)

hook.Add("AddToolMenuCategories", "BombinSupportB52_Categories", function()
    spawnmenu.AddToolCategory("Bombin Support", "B-52 Stratofortress", "B-52 Stratofortress")
end)

hook.Add("PopulateToolMenu", "BombinSupportB52_ToolMenu", function()
    spawnmenu.AddToolMenuOption("Bombin Support", "B-52 Stratofortress",
        "bombin_support_b52_settings", "B-52 Stratofortress Settings", "", "",
        function(panel)
            panel:ClearControls()

            panel:Help("NPC Call Settings")
            panel:CheckBox("Enable NPC calls",          "npc_bombinb52_enabled")
            panel:NumSlider("Call chance (per check)",  "npc_bombinb52_chance",   0, 1,     2)
            panel:NumSlider("Check interval (seconds)","npc_bombinb52_interval", 1, 60,    0)
            panel:NumSlider("NPC cooldown (seconds)",  "npc_bombinb52_cooldown", 10, 300,  0)
            panel:NumSlider("Min call distance (HU)",  "npc_bombinb52_min_dist", 100, 1000, 0)
            panel:NumSlider("Max call distance (HU)",  "npc_bombinb52_max_dist", 500, 8000, 0)
            panel:NumSlider("Flare arrival delay (s)", "npc_bombinb52_delay",    1, 30,    0)

            panel:Help("B-52 Behaviour")
            panel:NumSlider("Lifetime (seconds)",          "npc_bombinb52_lifetime", 10, 240,   0)
            panel:NumSlider("Forward speed (HU/s)",        "npc_bombinb52_speed",    100, 800,  0)
            panel:NumSlider("Orbit radius (HU)",           "npc_bombinb52_radius",   1000, 12000, 0)
            panel:NumSlider("Altitude above ground (HU)",  "npc_bombinb52_height",   3000, 12000, 0)

            panel:Help("Debug")
            panel:CheckBox("Enable debug prints", "npc_bombinb52_announce")

            panel:Help("Manual spawn (for testing)")
            panel:Button("Spawn B-52 now", "bombin_spawnb52")
        end
    )
end)
