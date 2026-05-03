-- Shared: convars must exist before the spawn script reads them
CreateConVar("npc_bombinb52_lifetime", "120",  FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 lifetime (s)",            10, 600)
CreateConVar("npc_bombinb52_speed",    "260",  FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 speed (HU/s)",            50, 800)
CreateConVar("npc_bombinb52_radius",   "4200", FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 orbit radius (HU)",       500, 20000)
CreateConVar("npc_bombinb52_height",   "7000", FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 sky height above ground", 1000, 30000)
CreateConVar("npc_bombinb52_announce", "1",    FCVAR_ARCHIVE+FCVAR_REPLICATED, "B-52 debug messages",          0, 1)
