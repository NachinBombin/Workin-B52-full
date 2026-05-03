-- Shared autorun: registers convars for B-52 on both client and server
if not ConVarExists("npc_bombinb52_lifetime") then
    CreateConVar("npc_bombinb52_lifetime", "120",   FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 lifetime in seconds", 10, 600)
end
if not ConVarExists("npc_bombinb52_speed") then
    CreateConVar("npc_bombinb52_speed",    "260",   FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 speed (HU/s)",       50, 800)
end
if not ConVarExists("npc_bombinb52_radius") then
    CreateConVar("npc_bombinb52_radius",   "4200",  FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 orbit radius (HU)",  500, 20000)
end
if not ConVarExists("npc_bombinb52_height") then
    CreateConVar("npc_bombinb52_height",   "7000",  FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 sky height above ground (HU)", 1000, 30000)
end
if not ConVarExists("npc_bombinb52_announce") then
    CreateConVar("npc_bombinb52_announce", "1",     FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 debug messages", 0, 1)
end
