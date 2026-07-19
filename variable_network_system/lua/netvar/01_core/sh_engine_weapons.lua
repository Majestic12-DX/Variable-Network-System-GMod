-- C++ weapon classes. These do NOT fire OwnerChanged/SetOwner on
-- pickup - only GM:WeaponEquip - so their network vars need re-sending there.
-- Lua/scripted weapons DO fire OwnerChanged, handled by the owner-change wrap.
VAR_NET_SYS_ENGINE_WEAPONS = {
	-- HL2 player
	["weapon_357"]        = true,
	["weapon_ar2"]        = true,
	["weapon_bugbait"]    = true,
	["weapon_crossbow"]   = true,
	["weapon_crowbar"]    = true,
	["weapon_frag"]       = true,
	["weapon_physcannon"] = true,
	["weapon_pistol"]     = true,
	["weapon_rpg"]        = true,
	["weapon_shotgun"]    = true,
	["weapon_slam"]       = true,
	["weapon_smg1"]       = true,
	["weapon_stunstick"]  = true,

	-- HL2 NPC
	["weapon_alyxgun"]        = true,
	["weapon_annabelle"]      = true,
	["weapon_citizensuitcase"] = true,
	["weapon_oldmanharpoon"]  = true,

	-- HL:Source player
	["weapon_357_hl1"]      = true,
	["weapon_crossbow_hl1"] = true,
	["weapon_crowbar_hl1"]  = true,
	["weapon_egon"]         = true,
	["weapon_gauss"]        = true,
	["weapon_glock_hl1"]    = true,
	["weapon_handgrenade"]  = true,
	["weapon_hornetgun"]    = true,
	["weapon_mp5_hl1"]      = true,
	["weapon_rpg_hl1"]      = true,
	["weapon_satchel"]      = true,
	["weapon_shotgun_hl1"]  = true,
	["weapon_snark"]        = true,
	["weapon_tripmine"]     = true,

	-- GMod engine weapon
	["weapon_physgun"]      = true,
}
