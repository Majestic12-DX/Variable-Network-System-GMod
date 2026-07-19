-- Used by VarNetSys Entity Network Variable sub-system
-- All network variables must be initialized on shared
-- But with shareWithFunc you can decide who gets updates on the variable

local VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA = {}
local VAR_NET_SYS_ENTITIES_WITH_NETWORK_DATA = {}

-- The functions are here to not cause unexpected behavior because of reference types (userdata and tables)
local VAR_NET_SYS_VARIABLE_TYPE_DEFAULTS = {
	[VAR_NET_SYS_NUMBER] = function() return 0 end,
	[VAR_NET_SYS_BOOL] = function() return false end,
	[VAR_NET_SYS_STRING] = function() return "" end,
	[VAR_NET_SYS_TABLE] = function() return {} end,
	[VAR_NET_SYS_ENTITY] = function() return NULL end, -- May cause problems...
	[VAR_NET_SYS_VECTOR] = function() return Vector(0, 0, 0) end,
	[VAR_NET_SYS_ANGLE] = function() return Angle(0, 0, 0) end,
	[VAR_NET_SYS_COLOR] = function() return Color(255, 255, 255, 255) end
}

local function SetupNetworkingData(ent, varName, varType, defaultValue)
	local varTypeId = VAR_NET_SYS_VARIABLE_TYPE_MAP[varType]
	VAR_NET_SYS:Assert(varTypeId, "varType must lead to a proper VarNetSys network variable type from VAR_NET_SYS_VARIABLE_TYPE_MAP!")

	local getDefaultTypeValue = VAR_NET_SYS_VARIABLE_TYPE_DEFAULTS[varTypeId]
	VAR_NET_SYS:Assert(isfunction(getDefaultTypeValue), "getDefaultTypeValue for VarNetSys network variable type " .. varTypeId .. " is nil, but must be a defined function!")

	local defaultTypeValue = getDefaultTypeValue()
	local technicalVarType = type(defaultTypeValue)

	if type(defaultValue) ~= technicalVarType then
		if defaultValue ~= nil then
			VAR_NET_SYS:Log(LOG_WARNING, "defaultValue for %s is not of %s type! Changing defaultValue to a fallback %s value: %s",
				varName, varType, varType, defaultTypeValue)
		end

		defaultValue = defaultTypeValue
	end

	local varId = VAR_NET_SYS:GetEntityNetworkVariableDataAmount(ent)

	return varId, varTypeId, technicalVarType, defaultValue
end

local function GetNetworkData(ent, varId)
	local networkVarDataList = VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA[ent]
	if not networkVarDataList then
		VAR_NET_SYS:Log(LOG_ERROR, "Asked for data of Network Var (index %s) of %s entity, but network variables data list is non existent!", varId, ent)
		return
	end

	local networkVarData = networkVarDataList[varId]
	if not networkVarData then
		VAR_NET_SYS:Log(LOG_ERROR, "Asked for data of Network Var (index %s) of %s entity, but has no data related to the variable!", varId, ent)
		return
	end

	return networkVarData
end

local function ValidateOptionalFunction(func, name)
    if func ~= nil and not isfunction(func) then
        VAR_NET_SYS:Log(LOG_WARNING, "%s was a %s instead of nil or a function, setting to nil", name, type(func))
        return nil
    end

    return func
end

-- TODO: Add option to request value change from client
-- If changeRequestFunc is not provided then the value cannot be requested to change from client
-- The packet should contain: Entity, Variable Index, New Value
function VAR_NET_SYS:AddNetworkVariableDataToEntity(ent, varType, varName, defaultValue, processValueFunc, shareWithFunc, changeRequestFunc)
	VAR_NET_SYS:Assert(IsEntity(ent), "ent must be an entity!")
	VAR_NET_SYS:Assert(isstring(varType), "varType should be a string!")
	VAR_NET_SYS:Assert(isstring(varName), "varName should be a string!")

	varType = string.lower(varType)

	local varId, varTypeId, technicalVarType, defaultValue = SetupNetworkingData(ent, varName, varType, defaultValue)
	if not varId or not varTypeId or not technicalVarType or defaultValue == nil then return false end

	VAR_NET_SYS:Assert(varId <= VAR_NET_SYS_MAXVARS, "Tried allocating network variable above maximum limit!")

	if not VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA[ent] then
		VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA[ent] = {}
		table.insert(VAR_NET_SYS_ENTITIES_WITH_NETWORK_DATA, ent)
	end

	local entityNetworkVarData = VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA[ent]

	-- Local Player is not removed but still re-networked during full update, resulting in duplicates, resulting in this...
	-- Well, should've checked duplicates beforehand, silly me
	for index = 0, #entityNetworkVarData do
		local data = entityNetworkVarData[index]
		if not data or data.Name ~= varName then continue end

		VAR_NET_SYS:Log(LOG_WARNING, "Tried creating a network variable %s for %s, but variable with same name is already registered for this entity!",
											varName, ent)
		return false
	end

	entityNetworkVarData[varId] = {}
	local networkVarData = entityNetworkVarData[varId]

	networkVarData.Name = varName
	networkVarData.Value = defaultValue
	networkVarData.TypeID = varTypeId

	if SERVER then
		networkVarData.ProcessValueFunc = ValidateOptionalFunction(processValueFunc, "processValueFunc")
		networkVarData.ShareWithFunc = ValidateOptionalFunction(shareWithFunc, "shareWithFunc")
		networkVarData.ChangeRequestFunc = ValidateOptionalFunction(changeRequestFunc, "changeRequestFunc")
	end

	local getFunc = function(mySelf)
		local networkVarData = GetNetworkData(mySelf, varId)
		return networkVarData.Value
	end

	networkVarData.GetFunc = getFunc

	ent["Get" .. varName] = getFunc

	VAR_NET_SYS:_AddNetworkVariableDataToEntity(
		ent,
		varType,
		varName,
		defaultValue,
		varId,
		varTypeId,
		technicalVarType,

		-- Passing a reference to network variable data so it can be modified in sub-functions
		networkVarData
	)

	return true
end

function VAR_NET_SYS:ClearEntityNetworkVariableData(ent)
	if not VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA[ent] then return false end

	VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA[ent] = nil
	table.RemoveByValue(VAR_NET_SYS_ENTITIES_WITH_NETWORK_DATA, ent)

	return true
end

function VAR_NET_SYS:NetworkEntityVarData(ent, varId)
	VAR_NET_SYS:Assert(SERVER, "NetworkEntityVarData called outside server realm?")

	local networkData = GetNetworkData(ent, varId)
	local varTypeId = networkData.TypeID

	networkData.NetworkFunc(ent, varId, varTypeId)
end

function VAR_NET_SYS:GetEntityNetworkVariableData(ent, varId)
	return GetNetworkData(ent, varId)
end

-- This doesn't work well on client because there's no guarantee it's going to be sequential
-- We are not planning to use this on client, anyway
-- If we do, it can be simply refactored
function VAR_NET_SYS:GetEntityNetworkVariableDataAmount(ent)
	local networkVarDataList = VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA[ent]

	-- + 1 because # operator counts from 1 in a table
	-- but our lists are 0 indexed for networking purposes
	return networkVarDataList and #networkVarDataList + 1 or 0
end

function VAR_NET_SYS:GetListOfEntitiesWithNetworkData()
	return VAR_NET_SYS_ENTITIES_WITH_NETWORK_DATA
end

function VAR_NET_SYS:GetGlobalNetworkedVariable(variableName)
	local world = game.GetWorld()
	local getter = world["Get" .. variableName]

	if not getter then
		VAR_NET_SYS:Log(LOG_WARNING, "Tried getting Global Networked Variable %s, but it's missing! Returning nil", variableName)
		return nil
	end

	return getter(world)
end

-- Debug
function VAR_NET_SYS:GetEntitiesNetworkData()
	return VAR_NET_SYS:IsDebug() and VAR_NET_SYS_ENTITY_NETWORK_VARIABLES_DATA or {}
end
