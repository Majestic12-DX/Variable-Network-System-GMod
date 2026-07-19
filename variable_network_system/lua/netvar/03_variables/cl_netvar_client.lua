-- Should NOT be called manually. Called by AddNetworkVariableDataToEntity shared function
function VAR_NET_SYS:_AddNetworkVariableDataToEntity(ent, varType, varName, defaultValue, varId, varTypeId, technicalVarType, networkVarData)
	local function requestValueChange(mySelf, newValue)
		VAR_NET_SYS:SendNetworkVariableChangeRequest(mySelf, varId, newValue)
	end

	networkVarData.RequestSetFunc = requestValueChange

	ent["RequestSet" .. varName] = requestValueChange
end

function VAR_NET_SYS:SendNetworkVariableChangeRequest(ent, varId, newValue)

end
