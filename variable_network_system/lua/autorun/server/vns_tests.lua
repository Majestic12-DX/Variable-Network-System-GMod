-- Variable Network System - console tests (SERVER autoload, delete before shipping)
--
-- Run on a listen server (you are a player) or any server with a player present.
-- Each test registers a PUBLIC var on both realms, sets it server-side, and the
-- client prints via an On<Name>Change handler when the value arrives.
--
--   lua_run VNS_Test_Number()
--   lua_run VNS_Test_All()
--
-- Client prints appear in the CLIENT console (prefixed [VNS CL]).

local function GetTestEntity()
	local ent = Entity(1)
	if IsValid(ent) and ent:IsPlayer() then return ent end
	return player.GetAll()[1]
end

-- Register the same var, in the same order, on both realms so varId indices line up.
local function Setup(ent, varType, varName)
	if not ent["Get" .. varName] then
		ent:PublicNetworkVariable(varType, varName)
	end

	local clientCode = ([[
		local ent = Entity(%d)
		if IsValid(ent) then
			if not ent["Get%s"] then ent:PublicNetworkVariable("%s", "%s") end
			ent["On%sChange"] = function(_, old, new)
				print("[VNS CL] %s changed:", old, "->", new)
			end
		end
	]]):format(ent:EntIndex(), varName, varType, varName, varName, varName)

	BroadcastLua(clientCode)
end

local function RunVarTest(varType, varName, value)
	local ent = GetTestEntity()
	if not IsValid(ent) then print("[VNS] no test entity - need a player present") return end

	Setup(ent, varType, varName)

	-- give the client a tick to register before the value packet lands
	timer.Simple(0.1, function()
		if not IsValid(ent) then return end
		local ok = ent["Set" .. varName](ent, value)
		print(("[VNS] server Set%s -> %s (ok=%s)"):format(varName, tostring(value), tostring(ok)))
	end)
end

function VNS_Test_Number() RunVarTest("Number",  "VNSNumber", 1337) end
function VNS_Test_Bool()   RunVarTest("Boolean", "VNSBool",   true) end
function VNS_Test_String() RunVarTest("String",  "VNSString", "hello world") end
function VNS_Test_Vector() RunVarTest("Vector",  "VNSVector", Vector(1, 2, 3)) end
function VNS_Test_Angle()  RunVarTest("Angle",   "VNSAngle",  Angle(11, 22, 33)) end
function VNS_Test_Color()  RunVarTest("Color",   "VNSColor",  Color(10, 20, 30, 40)) end
function VNS_Test_Entity() RunVarTest("Entity",  "VNSEntity", GetTestEntity()) end
function VNS_Test_Table()  RunVarTest("Table",   "VNSTable",  { a = 1, b = "x", t = CurTime() }) end

-- Global var = a var bound to the world entity.
function VNS_Test_Global()
	local world = game.GetWorld()
	if not world.GetVNSGlobal then
		world:PublicNetworkVariable("Number", "VNSGlobal")
	end

	BroadcastLua([[
		local world = game.GetWorld()
		if not world.GetVNSGlobal then world:PublicNetworkVariable("Number", "VNSGlobal") end
		world.OnVNSGlobalChange = function(_, old, new)
			print("[VNS CL] VNSGlobal changed:", old, "->", new)
		end
	]])

	timer.Simple(0.1, function()
		VAR_NET_SYS:SetGlobalNetworkedVariable("VNSGlobal", math.random(1, 9999))
		print("[VNS] set global VNSGlobal, current:", VAR_NET_SYS:GetGlobalNetworkedVariable("VNSGlobal"))
	end)
end

-- KNOWN ISSUE: mutable types (Table) only replicate when the memory reference
-- changes. Mutating in place does NOT trigger a Set - you must Network<Name>() it.
function VNS_Test_TableMutate()
	local ent = GetTestEntity()
	if not IsValid(ent) or not ent.GetVNSTable then
		print("[VNS] run VNS_Test_Table() first")
		return
	end

	local t = ent:GetVNSTable()
	t.mutated = CurTime()               -- same table reference, mutated in place

	local ok = ent:SetVNSTable(t)       -- same ref -> Set sees no change -> false, NOT networked
	print("[VNS] SetVNSTable(same ref) ok =", ok, "(false = known issue: not sent)")

	ent:NetworkVNSTable()               -- manual resend forces it over the wire
	print("[VNS] called NetworkVNSTable() to force the mutated table out")
end

-- TUFF: a table whose KEY is a Player and which holds a sub-table of entity
-- values (the player's weapons). Exercises the full clientside handshake:
-- entity-key swap + recursive resolve of every nested entity before applying.
function VNS_Test_Table_Entities()
	local ent = GetTestEntity()
	if not IsValid(ent) then print("[VNS] no test entity - need a player present") return end

	if not ent.GetVNSTableEnts then
		ent:PublicNetworkVariable("Table", "VNSTableEnts")
	end

	BroadcastLua(([[
		local ent = Entity(%d)
		if IsValid(ent) then
			if not ent["GetVNSTableEnts"] then ent:PublicNetworkVariable("Table", "VNSTableEnts") end
			ent.OnVNSTableEntsChange = function(_, old, new)
				print("[VNS CL] VNSTableEnts arrived (all entities resolved clientside):")
				PrintTable(new)
			end
		end
	]]):format(ent:EntIndex()))

	timer.Simple(0.1, function()
		if not IsValid(ent) then return end

		local value = {
			[ent] = "owner",           -- Player as a table KEY
			weapons = ent:GetWeapons() -- sub-table of weapon entities (values)
		}

		ent:SetVNSTableEnts(value)
		print(("[VNS] set VNSTableEnts: player key + %d weapons"):format(#ent:GetWeapons()))
	end)
end

-- Registers a PRIVATE "VNSWeaponTag" var (default string) on weapon_rpg AND
-- tfa_csgo_ak47, both realms. Private = only the current owner receives it.
-- weapon_rpg is a C++ engine weapon (core re-networks it on WeaponEquip);
-- tfa_csgo_ak47 is a Lua SWEP (re-networked by the OwnerChanged wrap). Either way,
-- dropping the weapon and grabbing it as another player sends the value to them.
local VNS_TAGGED_WEAPONS = {
	["weapon_rpg"]    = true,
	["tfa_csgo_ak47"] = true,
}
local VNS_WEAPON_TAG_DEFAULT = "this is supposed to be networked"

local VNS_WEAPON_VARS_INSTALLED = false
local function InstallWeaponPrivateVars()
	if VNS_WEAPON_VARS_INSTALLED then return end
	VNS_WEAPON_VARS_INSTALLED = true

	-- register the var on both realms whenever a tagged weapon is created
	hook.Add("OnEntityCreated", "VNS_WeaponTag_PrivateVar", function(ent)
		timer.Simple(0, function()
			if not IsValid(ent) or not VNS_TAGGED_WEAPONS[ent:GetClass()] then return end
			if not ent.GetVNSWeaponTag then ent:PrivateNetworkVariable("String", "VNSWeaponTag", VNS_WEAPON_TAG_DEFAULT) end
		end)
	end)

	-- clients: register the same var (same default) + print on change
	BroadcastLua([[
		local TAGGED = { ["weapon_rpg"] = true, ["tfa_csgo_ak47"] = true }
		hook.Add("OnEntityCreated", "VNS_WeaponTag_PrivateVar", function(ent)
			timer.Simple(0, function()
				if not IsValid(ent) or not TAGGED[ent:GetClass()] then return end
				if ent.GetVNSWeaponTag then return end
				ent:PrivateNetworkVariable("String", "VNSWeaponTag", "this is supposed to be networked")
				ent.OnVNSWeaponTagChange = function(_, old, new)
					print("[VNS CL] VNSWeaponTag on " .. tostring(ent) .. " -> " .. tostring(new))
				end
			end)
		end)
	]])
end

-- Same idea, bots only: give each bot rpg + pistol + 357, publish their weapon
-- table, tag their RPG with a private var and make them select it.
function VNS_Test_Bots_Weapons()
	-- launch a Source engine fullupdate on every client (forces a fresh entity snapshot)
	BroadcastLua([[ RunConsoleCommand("cl_fullupdate") ]])

	InstallWeaponPrivateVars()

	local bots = player.GetBots()
	if #bots == 0 then print("[VNS] no bots present - spawn one with the 'bot' command") return end

	for _, bot in ipairs(bots) do
		bot:Give("weapon_rpg")
		bot:Give("weapon_pistol")
		bot:Give("weapon_357")
		bot:Give("tfa_csgo_ak47")

		if not bot.GetVNSBotWeapons then
			bot:PublicNetworkVariable("Table", "VNSBotWeapons")
		end

		BroadcastLua(([[
			local bot = Entity(%d)
			if IsValid(bot) then
				if not bot["GetVNSBotWeapons"] then bot:PublicNetworkVariable("Table", "VNSBotWeapons") end
				bot.OnVNSBotWeaponsChange = function(_, old, new)
					print("[VNS CL] VNSBotWeapons for " .. tostring(bot) .. ":")
					PrintTable(new)
				end
			end
		]]):format(bot:EntIndex()))
	end

	timer.Simple(0.1, function()
		for _, bot in ipairs(bots) do
			if not IsValid(bot) then continue end

			bot:SetVNSBotWeapons({ [bot] = "bot", weapons = bot:GetWeapons() })

			-- RPG + AK carry the default "VNSWeaponTag" value; leave it unset so the
			-- default is what replicates on pickup
			bot:SelectWeapon("weapon_rpg")
		end

		print(("[VNS] armed %d bot(s), tagged RPG + AK, selected RPG"):format(#bots))
	end)
end

function VNS_Test_All()
	VNS_Test_Number()  VNS_Test_Bool()   VNS_Test_String() VNS_Test_Vector()
	VNS_Test_Angle()   VNS_Test_Color()  VNS_Test_Entity() VNS_Test_Table()
	VNS_Test_Global()  VNS_Test_Table_Entities()
	print("[VNS] ran all. Check CLIENT console for [VNS CL] lines.")
end
