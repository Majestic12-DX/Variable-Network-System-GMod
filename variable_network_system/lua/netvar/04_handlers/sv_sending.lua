-- Tested: 9 bytes / 72 bits header
-- 24 internal engine bits for sending - 3 bytes / 24 bits
-- 24 bits ent creation id = 6 bytes / 48 bits
-- 13 bits ent index - 7 bytes 5 bits / 61 bits
-- 7 bits var id = 8 bytes 4 bits / 68 bits
-- 4 bits vartype = 9 bytes / 72 bits

local VAR_NET_SYS_VARIABLE_WRITE_FUNCS = {
	[VAR_NET_SYS_NUMBER] = net.WriteDouble,
	[VAR_NET_SYS_BOOL] = net.WriteBool,
	[VAR_NET_SYS_STRING] = net.WriteString,
	[VAR_NET_SYS_TABLE] = net.WriteCompressedTable,

	[VAR_NET_SYS_ENTITY] = function(ent)
		local isValidEntity = IsValidEntity(ent)
		net.WriteBool(isValidEntity)

		if not isValidEntity then return end

		net.WriteUInt(ent:EntIndex(), MAX_EDICT_BITS)
		net.WriteUInt(ent:GetCreationID(), CREATIONID_BYTE_SIZE)
	end,

	[VAR_NET_SYS_VECTOR] = net.WriteVectorUncompressed,
	[VAR_NET_SYS_ANGLE] = net.WriteAngle,
	[VAR_NET_SYS_COLOR] = net.WriteColor,
}

local function WriteVarNetSysNetworkVariable(variable, varTypeId)
	local writeTypeFunc = VAR_NET_SYS_VARIABLE_WRITE_FUNCS[varTypeId]
	if not writeTypeFunc then
		VAR_NET_SYS:Log(LOG_ERROR, "Network Variable Type %s doesn't have writing function!", varTypeId)
		return false
	end

	net.WriteUInt(varTypeId, VAR_NET_SYS_VARIABLE_TYPE_MAP_BYTE_SIZE)
	writeTypeFunc(variable, varTypeId == VAR_NET_SYS_COLOR or nil)

	return true
end

local LAST_DATA_SENT_TO_PLAYER = {}
local function SetLastSentDataToPlayer(ply, ent, varId, varTypeId, value)
	if not LAST_DATA_SENT_TO_PLAYER[ply] then
		LAST_DATA_SENT_TO_PLAYER[ply] = {}
	end

	local lastDataSentToPlayer = LAST_DATA_SENT_TO_PLAYER[ply]

	if not lastDataSentToPlayer[ent] then
		lastDataSentToPlayer[ent] = {}
	end

	-- this is problematic with mutables since they are basically "the same value"... (same memory address)
	local lastEntityDataSentToPlayer = lastDataSentToPlayer[ent]
	lastEntityDataSentToPlayer[varId] = value

	VAR_NET_SYS:Log(LOG_DEV, "Remembered last sent data of variable %s of %s entity to %s for delta-based optimization", varId, ent, ply)
end

local function GetLastEntDataSentToPlayer(ply, ent)
	local lastDataSentToPlayer = LAST_DATA_SENT_TO_PLAYER[ply]
	if not lastDataSentToPlayer then return end

	return lastDataSentToPlayer[ent]
end

local function GetLastEntVarDataToPlayer(ply, ent, varId)
	local lastEntityDataSentToPlayer = GetLastEntDataSentToPlayer(ply, ent)
	if not lastEntityDataSentToPlayer then return end

	return lastEntityDataSentToPlayer[varId]
end

local function HasReceivedLatestEntVarUpdate(ply, ent, varId, varTypeId, variable)
	-- This may be bad, but this fixes the problem where it considers that it has already sent newest data for the table
	-- Just because the memory address of it didn't change
	-- If this becomes a problem, we'll figure out a better way
	-- TODO: THIS IS TEMPORARY!! PROBABLY KNOW A PROPER FIX FOR ANGLES, VECTORS, COLORS AND TABLES!!!!!!!!
	if varTypeId == VAR_NET_SYS_TABLE or varTypeId == VAR_NET_SYS_ANGLE
		or varTypeId == VAR_NET_SYS_VECTOR or varTypeId == VAR_NET_SYS_COLOR then return false end

	local hasReceivedLatestEntVarUpdate = GetLastEntVarDataToPlayer(ply, ent, varId) == variable
	if hasReceivedLatestEntVarUpdate then
		VAR_NET_SYS:Log(LOG_DEV, "%s should not receive update for %s's %s variable, as latest sent value equals current one", ply, ent, varId)
	end

	return hasReceivedLatestEntVarUpdate
end

VAR_NET_SYS:AddNetworkSender("SendNetworkVariableUpdate", function(ent, varId)
	if not IsValid(ent) and not ent:IsWorld() then return "Entity is invalid!" end

	local networkVarData = VAR_NET_SYS:GetEntityNetworkVariableData(ent, varId)
	local variable = networkVarData.Value
	local varTypeId = networkVarData.TypeID

	local networkTargets = { }

	if VAR_NET_SYS:IsValidPlayer(ent) and not HasReceivedLatestEntVarUpdate(ent, ent, varId, varTypeId, variable) then
		table.insert(networkTargets, ent)
	end

	local owner = ent:GetOwner()
	if VAR_NET_SYS:IsValidPlayer(owner) and not HasReceivedLatestEntVarUpdate(owner, ent, varId, varTypeId, variable) then
		table.insert(networkTargets, owner)
	end

	local varName = networkVarData.Name

	local shareWithFunc = networkVarData.ShareWithFunc
	if shareWithFunc then
		for id, ply in player.Iterator() do
			if ply == ent or ply == owner or HasReceivedLatestEntVarUpdate(ply, ent, varId, varTypeId, variable) or not shareWithFunc(ply, ent, owner) then continue end

			table.insert(networkTargets, ply)
			VAR_NET_SYS:Log(LOG_DEV, "%s passed shareWithFunc check for %s entity's %s network variable", ply, ent, varName)
		end
	end

	if #networkTargets == 0 then return string.format("No valid player for networking for variable %s of %s entity!", varId, ent) end

	VAR_NET_SYS:Log(LOG_DEBUG, "Beginning to network variable update of %s variable of %s entity", varName, ent)

	local entCreationId = ent:GetCreationID()
	net.Start("netvar_update")
		-- Creation ID used to mark entities
		-- So in scenarios of index reuse we do wont
		-- Corrupt state of other entities
		net.WriteUInt(entCreationId, CREATIONID_BYTE_SIZE)

		net.WriteEntity(ent)

		net.WriteUInt(varId, VAR_NET_SYS_MAXVARS_BYTE_SIZE)

		if not WriteVarNetSysNetworkVariable(variable, varTypeId) then
			net.Abort()
			return "Failed to write network variable data to the packet!"
		end

		local bytesWritten, bitsWritten = net.BytesWritten()
		for i = 1, #networkTargets do
			local networkTarget = networkTargets[i]
			SetLastSentDataToPlayer(networkTarget, ent, varId, varTypeId, variable)

			VAR_NET_SYS:Log(LOG_DEBUG, "Network variable update of %s variable (\"%s\" new value) of %s entity (%s creation ID) sent to %s (%s bytes/%s bits)",
				varName, variable, ent, entCreationId, networkTarget, bitsWritten / 8, bitsWritten)
		end
	net.Send(networkTargets)
end)

-- If too many entities are deleted at once, this causes net buffer overflow. Gotta fix if this happens in actual scenarios
VAR_NET_SYS:AddNetworkSender("SendNetworkVariableClearData", function(ent)
	if not IsValid(ent) then return "Entity is invalid!" end

	-- This must be sent to anyone who has ever received/should receive ent data
	local networkTargets = {}

	-- useless?
	if VAR_NET_SYS:IsValidPlayer(ent) and GetLastEntDataSentToPlayer(ent, ent) then
		table.insert(networkTargets, ent)
	end

	local owner = ent:GetOwner()
	if VAR_NET_SYS:IsValidPlayer(owner) and GetLastEntDataSentToPlayer(owner, ent) then
		table.insert(networkTargets, owner)
	end

	for id, ply in player.Iterator() do
		if ply == ent or ply == owner or not GetLastEntDataSentToPlayer(ply, ent) then continue end
		table.insert(networkTargets, ply)

		VAR_NET_SYS:Log(LOG_DEV, "%s added to %s's clear data network targets list, had data about the entity sent to before", ply, ent)
	end

	if #networkTargets == 0 then return string.format("No valid player for networking data clear of %s entity!", ent) end

	local entCreationId = ent:GetCreationID()
	net.Start("netvar_cleardata")
		net.WriteUInt(entCreationId, CREATIONID_BYTE_SIZE)

		local bytesWritten, bitsWritten = net.BytesWritten()
		for i = 1, #networkTargets do
			local networkTarget = networkTargets[i]

			VAR_NET_SYS:Log(LOG_DEBUG, "Network variable clear data of %s entity (%s creation ID) sent to %s (%s bytes/%s bits)",
				ent, entCreationId, networkTarget, bitsWritten / 8, bitsWritten)
		end
	net.Send(networkTargets)
end)

-- Called on: Player Full Load, Team Switch, Usergroup Switch
-- Gotta speed this thing up to be faster, somehow (coroutine?)
-- 128 players with three weapons that had around 3~ network variables each, shareWithFunc check ignored (everything is sent):
-- 11.5 ms without logging, 49.5 ms with logging (Local Host, AMD Ryzen 7 5800H)
-- I assume the biggest slowdown comes from JSON convertation + LZMA compression
-- Compressed (Smaller Test): 2138 bytes/17104 bits
-- Uncompressed (Smaller Test): Buffer Overflow (More than 64 KB) + 3x slower
-- Compressed (Larger Test): 20 ms no logging, 4770 bytes/38160 bits, 1382 entities with 4656 variables
local LAST_PLY_FULLUPDATES_BY_TICK = {}
VAR_NET_SYS:AddNetworkSender("SendNetworkVariablesFullUpdate", function(ply)
	if not VAR_NET_SYS:IsValidPlayer(ply) then return "ply is invalid!" end
	local startTime = SysTime()

	-- Since this is called in many places
	local currentTick = engine.TickCount()
	local lastFullUpdateTick = LAST_PLY_FULLUPDATES_BY_TICK[ply]
	if lastFullUpdateTick == currentTick then
		return "Already sent fullupdate this tick to " .. VAR_NET_SYS:GetPlayerDataString(ply) .. "!"
	end

	LAST_PLY_FULLUPDATES_BY_TICK[ply] = currentTick

	VAR_NET_SYS:Log(LOG_DEBUG, "Beginning to network variable full update for %s", ply)

	local networkFullUpdateTable = {}

	local networkVarEntsList = VAR_NET_SYS:GetListOfEntitiesWithNetworkData()
	for id, ent in ipairs(networkVarEntsList) do
		local entOwner = ent:GetOwner()
		local isOwnerOrEnt = ply == ent or entOwner == ply

		local creationId = ent:GetCreationID()
		networkFullUpdateTable[creationId] = {}

		local entityUpdateTable = networkFullUpdateTable[creationId]
		local isEmpty = true

		local networkVarAmount = VAR_NET_SYS:GetEntityNetworkVariableDataAmount(ent)
		for i = 0, networkVarAmount - 1 do
			local networkVarData = VAR_NET_SYS:GetEntityNetworkVariableData(ent, i)
			local variable = networkVarData.Value
			local varTypeId = networkVarData.TypeID

			if HasReceivedLatestEntVarUpdate(ply, ent, i, varTypeId, variable) then continue end

			local shareWithFunc = networkVarData.ShareWithFunc
			if not isOwnerOrEnt and (not shareWithFunc or not shareWithFunc(ply, ent, entOwner)) then continue end

			if not isOwnerOrEnt and shareWithFunc then
				VAR_NET_SYS:Log(LOG_DEV, "%s passed shareWithFunc check for %s entity's %s network variable", ply, ent, networkVarData.Name)
			end

			SetLastSentDataToPlayer(ply, ent, i, varTypeId, variable)

			entityUpdateTable[i] = variable

			isEmpty = false
		end

		if isEmpty then
			networkFullUpdateTable[creationId] = nil
			entityUpdateTable = nil

			VAR_NET_SYS:Log(LOG_DEV, "%s should not receive any data about %s entity's network variables", ply, ent)
		end
	end

	if VAR_NET_SYS:IsDebug() then
		--PrintTable(networkFullUpdateTable)
	end

	if next(networkFullUpdateTable) == nil then return "networkFullUpdateTable is empty" end

	net.Start("netvar_fullupdate")
		net.WriteCompressedTable(networkFullUpdateTable)

		local bytesWritten, bitsWritten = net.BytesWritten()
		VAR_NET_SYS:Log(LOG_DEBUG, "Network variables full update sent to %s (%s bytes/%s bits)",
				ply, bitsWritten / 8, bitsWritten)
	net.Send(ply)

	local endTime = SysTime()
	VAR_NET_SYS:Log(LOG_PERF, "Took %s seconds to send entity network variables full update to %s", endTime - startTime, VAR_NET_SYS:GetPlayerDataString(ply))
end)
