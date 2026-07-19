local VAR_NET_SYS_VARIABLE_READ_FUNCS = {
	[VAR_NET_SYS_NUMBER] = net.ReadDouble,
	[VAR_NET_SYS_BOOL] = net.ReadBool,
	[VAR_NET_SYS_STRING] = net.ReadString,

	-- No entity validity check on these. Whatever, later if it's really needed
	[VAR_NET_SYS_TABLE] = net.ReadCompressedTable,

	[VAR_NET_SYS_ENTITY] = function()
		local isValidEntity = net.ReadBool()
		if not isValidEntity then return { Entity = NULL, EntIndex = 0, EntCreationId = -1 } end

		local entIndex = net.ReadUInt(MAX_EDICT_BITS)
		local entCreationId = net.ReadUInt(CREATIONID_BYTE_SIZE)

		local ent = Entity(entIndex)
		local entByIndexValid = IsValidEntity(ent)

		local entByIndexCreationId = entByIndexValid and ent:GetCreationID()

		if not entByIndexValid then
			VAR_NET_SYS:Log(LOG_WARNING, "Read non-null %s entity from network (%s entity index, %s creation id), but entity doesn't exist on client right now",
				ent, entIndex, entCreationId)
		elseif entByIndexCreationId ~= entCreationId then
			VAR_NET_SYS:Log(LOG_WARNING, "Read %s entity from network (%s entity index), but creation ID doesn't match (got %s, expected %s). Setting to NULL",
				ent, entIndex, entByIndexCreationId, entCreationId)

			ent = NULL
		end

		return { Entity = ent, EntIndex = entIndex, EntCreationId = entCreationId }
	end,

	[VAR_NET_SYS_VECTOR] = net.ReadVectorUncompressed,
	[VAR_NET_SYS_ANGLE] = net.ReadAngle,
	[VAR_NET_SYS_COLOR] = net.ReadColor,
}

local function ReadVarNetSysNetworkVariable()
	local varTypeId = net.ReadUInt(VAR_NET_SYS_VARIABLE_TYPE_MAP_BYTE_SIZE)
	local readTypeFunc = VAR_NET_SYS_VARIABLE_READ_FUNCS[varTypeId]
	if not readTypeFunc then
		VAR_NET_SYS:Log(LOG_ERROR, "Network Variable Type %s doesn't have reading function!", varTypeId)
		return false, nil
	end

	local networkVar = readTypeFunc(varTypeId == VAR_NET_SYS_COLOR or varTypeId == VAR_NET_SYS_TABLE or nil)
	return true, varTypeId, networkVar
end

local function HandleNetworkedVariableChange(ent, varId, newValue)
	local networkVarData = VAR_NET_SYS:GetEntityNetworkVariableData(ent, varId)
	VAR_NET_SYS:Assert(networkVarData, "Received network variable update for non-existent network variable (index %s) of %s entity?", varId, ent)

	local oldValue = networkVarData.Value
	networkVarData.Value = newValue

	local varName = networkVarData.Name

	local onChangeFunc = ent["On" .. varName .. "Change"]
	if isfunction(onChangeFunc) then
		onChangeFunc(ent, oldValue, newValue)
	end

	VAR_NET_SYS:Log(LOG_DEBUG, "Handled %s (%s index) networked variable change with new value \"%s\" (old value \"%s\") for %s entity (%s creation ID), applying",
										varName, varId, newValue, oldValue, ent, ent:GetCreationID())
end

local function IsCorrectNetworkedEntity(varData, ent)
	if not ent then return false end

	local entIndex = varData.EntIndex
	local entCreationId = varData.EntCreationId
	local supposedToBeNull = entCreationId == -1

	return supposedToBeNull and ent == NULL or IsValidEntity(ent) and ent:EntIndex() == entIndex and ent:GetCreationID() == entCreationId
end

-- This should have been more low-level style...
local function GetCorrectNetworkedEntity(varData)
	local suspectedEnt = varData.Entity
	local entIndex = varData.EntIndex
	local entCreationId = varData.EntCreationId

	-- This is not a networked entity
	if not suspectedEnt or not entIndex or not entCreationId then return false end

	local supposedToBeNull = entCreationId == -1
	if supposedToBeNull then return NULL end

	local ent = Entity(entIndex)

	return IsValidEntity(ent) and ent:GetCreationID() == entCreationId and ent or nil
end

local EnsureTableEntitiesAllNetworked

local function GetTableEntity(tbl, seen)
	local correctNetworkedEntity = GetCorrectNetworkedEntity(tbl)

	-- false from GetCorrectNetworkedEntity means this is not a data of a networked object
	if correctNetworkedEntity == false then
		-- We fail if sub table entities are not yet networked
		return EnsureTableEntitiesAllNetworked(tbl, seen)

	-- nil means there needs to be a networked entity, but it isn't on the client yet
	elseif correctNetworkedEntity == nil then return false
	else return correctNetworkedEntity end
end

-- Yes, tables with entities are only applied when client has them clientside
-- This is can easily make tables slow to apply, but it's safe due to PVS and full updates. Figure out a better technique
-- Needs a little DRY but not now
EnsureTableEntitiesAllNetworked = function(tbl, seen)
	if not istable(tbl) then return true end
	seen = seen or {}

	if seen[tbl] then return true end
	seen[tbl] = true

	local snapshottedKeys = table.GetKeys(tbl)
	for _, key in ipairs(snapshottedKeys) do
		local value = tbl[key]

		if istable(key) then
			correctNetworkedEntity = GetTableEntity(key, seen)

			if correctNetworkedEntity == false then return false
			elseif IsEntity(correctNetworkedEntity) then
				tbl[key] = nil
				tbl[correctNetworkedEntity] = value

				key = correctNetworkedEntity

				-- At this point, we have our networked entity
				VAR_NET_SYS:Log(LOG_DEV, "Entity data table key %s replaced with %s (%s ent index, %s creation id). " ..
													"Entity has been ensured to exist on client",
					key, correctNetworkedEntity, key.EntIndex, key.EntCreationId)
			end
		end

		if istable(value) then
			correctNetworkedEntity = GetTableEntity(value, seen)

			if correctNetworkedEntity == false then return false
			elseif IsEntity(correctNetworkedEntity) then
				tbl[key] = correctNetworkedEntity

				-- At this point, we have our networked entity
				VAR_NET_SYS:Log(LOG_DEV, "Entity data table value %s (inside %s key) replaced with %s (%s ent index, %s creation id). " ..
													"Entity has been ensured to exist on client",
					value, key, correctNetworkedEntity, value.EntIndex, value.EntCreationId)
			end
		end
	end

	return true
end

-- TODO: Implement table entity key/value existance validation
-- They are parsed as tables with ent index, creation id and current reference to the ent index
local CREATIONIDS_MARKED_AS_DELETED = {}
local function PrepareHandlingNetworkedVariableChange(ent, entIndex, entCreationId, varId, varValue, varTypeId)
	local isVarTable = istable(varValue) and varTypeId == VAR_NET_SYS_TABLE
	local isVarEntity = istable(varValue) and varTypeId == VAR_NET_SYS_ENTITY

	local varEnt = isVarEntity and varValue.Entity
	local varEntIndex = isVarEntity and varValue.EntIndex
	local varEntCreationId = isVarEntity and varValue.EntCreationId

	local newValue = isVarEntity and varEnt or varValue

	local attemptionName = "Entity_" .. entCreationId .. "_NetworkVariableChange_" .. varId

	if IsValidEntity(ent) and ent:GetCreationID() == entCreationId and (isVarEntity and IsCorrectNetworkedEntity(varValue, varEnt)
		or isVarTable and EnsureTableEntitiesAllNetworked(varValue) or not isVarEntity and not isVarTable) then

		HandleNetworkedVariableChange(ent, varId, newValue)

		-- Stop any previous attemptions, as they are now outdated
		VAR_NET_SYS:StopAttempting(attemptionName)

		VAR_NET_SYS:Log(LOG_DEV, "Called HandleNetworkedVariableChange instantly, entity exists!")
		return
	end

	VAR_NET_SYS:AttemptUntilDone(attemptionName,
		function()
			if CREATIONIDS_MARKED_AS_DELETED[entCreationId] then return true end

			if isVarEntity then
				local correctNetworkedEntity = GetCorrectNetworkedEntity(varValue)
				if correctNetworkedEntity == nil then return false end

				newValue = correctNetworkedEntity
			end

			if isVarTable and not EnsureTableEntitiesAllNetworked(varValue) then return false end

			-- CONSIDER: Maybe we should always require entIndex?...
			-- No, works fine
			ent = entIndex and Entity(entIndex) or VAR_NET_SYS:GetEntityByCreationID(entCreationId)
			return IsValidEntity(ent) and ent:GetCreationID() == entCreationId
		end,

		function()
			if CREATIONIDS_MARKED_AS_DELETED[entCreationId] then
				VAR_NET_SYS:Log(LOG_DEV, "Not calling HandleNetworkedVariableChange, entity (%s creation ID) was removed serverside!",
					entCreationId)

				return
			end

			if not IsValidEntity(ent) then
				VAR_NET_SYS:Log(LOG_DEV, "Not calling HandleNetworkedVariableChange, entity (%s creation ID) suddenly became invalid!",
					entCreationId)
				return
			end

			HandleNetworkedVariableChange(ent, varId, newValue)

			VAR_NET_SYS:Log(LOG_DEV, "Called HandleNetworkedVariableChange in a delay, entity (%s creation ID) was nonexistant!", entCreationId)
		end
	)
end

net.Receive("netvar_update", function()
	local entCreationId = net.ReadUInt(CREATIONID_BYTE_SIZE)

	if CREATIONIDS_MARKED_AS_DELETED[entCreationId] then
		CREATIONIDS_MARKED_AS_DELETED[entCreationId] = nil
		VAR_NET_SYS:Log(LOG_DEV, "Received network variable update for previously marked as deleted creation ID (%s), considering it valid again",
			entCreationId)
	end

	local entIndex = net.ReadUInt(MAX_EDICT_BITS)
	local ent = Entity(entIndex)

	local varId = net.ReadUInt(VAR_NET_SYS_MAXVARS_BYTE_SIZE)
	local readSuccess, varTypeId, varValue = ReadVarNetSysNetworkVariable()
	if not readSuccess then
		VAR_NET_SYS:Log(LOG_ERROR, "Failed to read network variable %s of %s entity (%s entity index, %s creation ID)",
			varId, ent, entIndex, entCreationId)
		return
	end

	VAR_NET_SYS:Log(LOG_DEBUG, "Received variable %s update (\"%s\" new value) for %s entity (%s entity index, %s creation ID)",
		varId, varValue, ent, entIndex, entCreationId)

	PrepareHandlingNetworkedVariableChange(ent, entIndex, entCreationId, varId, varValue, varTypeId)
end)

net.Receive("netvar_cleardata", function()
	local entCreationId = net.ReadUInt(CREATIONID_BYTE_SIZE)
	CREATIONIDS_MARKED_AS_DELETED[entCreationId] = true

	VAR_NET_SYS:Log(LOG_DEV, "Received Deletion Packet for %s Creation ID, stopping all attemptions. " ..
		"Assuming entity is already deleted and had its data cleared clientside", entCreationId)
end)

-- This is not meant to be fast (although it kind of is, around 5 ms for 512 entities with 1792 variables)
-- This clientside handling makes me doubt the design choices I've made for this system
-- Of course, they could be fixed by just parsing entIndex and varTypeId from server
-- But these are not needed *right* now. What matters is the compression ratio here
net.Receive("netvar_fullupdate", function()
	VAR_NET_SYS:Log(LOG_DEBUG, "Received Network Variables Fullupdate Packet")
	local startTime = SysTime()

	local fullUpdateTable = net.ReadCompressedTable(true)

	local varCounter = 0
	for creationId, data in pairs(fullUpdateTable) do
		local ent = VAR_NET_SYS:GetEntityByCreationID(creationId)
		VAR_NET_SYS:Log(LOG_DEBUG, "Started handling fullupdate variables of %s entity (%s creation id)", ent, creationId)
		for varId, variable in pairs(data) do
			varCounter = varCounter + 1

			local isTable = istable(variable)
			local isEntData = isTable and variable.Entity and variable.EntIndex and variable.EntCreationId and true

			local varTypeId = isEntData and VAR_NET_SYS_ENTITY or isTable and VAR_NET_SYS_TABLE or nil

			-- We only parse varTypeId here for entities so they are handled properly. Other types only need varTypeId to properly read variables
			PrepareHandlingNetworkedVariableChange(ent, nil, creationId, varId, variable, varTypeId)
		end
	end

	local endTime = SysTime()
	VAR_NET_SYS:Log(LOG_PERF, "Took %s seconds to process fullupdate packet from server for %s entities (%s variables received)",
		endTime - startTime, table.Count(fullUpdateTable), varCounter)
end)
